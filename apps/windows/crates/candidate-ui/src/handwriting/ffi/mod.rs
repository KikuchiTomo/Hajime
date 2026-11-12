#![allow(unsafe_code)]

//! 手書きの窓を出し入れし，選んだ文字をエンジンに送る(macOS の HandwritingController)．窓はプロセスで 1 つだけ使い回す．
//! 窓はキーボードの入力を受けず，入力先のアプリを前面のまま残す．書く・選ぶ・動かす・広げるのはすべてマウス

mod recognizer;
mod render;
mod window;

use super::ink::{Ink, Point};
use super::layout::{minimum_size, Control, Hit, Layout};
use super::strings;
use crate::geometry::{origin, Bounds};
use crate::theme::ResolvedTheme;
use ipc::windows::{pipe_name, EngineClient};
use ipc::{Rect, RequestBody};
use recognizer::{Outcome, Recognizer};
use render::{Chrome, Fonts, Renderer, State};
use std::cell::RefCell;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use window::{Event, Handlers, Window};

type Results = Arc<Mutex<Option<(u64, Outcome)>>>;

/// 押している最中のもの
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Pressing {
    /// 書く欄で線を書いている
    Stroke,
    /// ボタン(離したときにまだその上なら押したことにする．Windows のボタンと同じ)
    Control(Control),
}

/// 手書きの窓の状態．候補ウィンドウのプロセスの窓のスレッドだけで触る
struct Controller {
    window: Window,
    renderer: Renderer,
    recognizer: Option<Recognizer>,
    results: Results,
    engine: Option<EngineClient>,
    ink: Ink,
    layout: Option<Layout>,
    fonts: Option<Fonts>,
    theme: Option<ResolvedTheme>,
    chrome: Chrome,
    delay: u32,
    timeout: Duration,
    unavailable: bool,
    visible: bool,
    hovered: Option<Control>,
    pressing: Option<Pressing>,
    /// 候補の行を送った量(DIP)
    scroll: f32,
}

thread_local! {
    static CONTROLLER: RefCell<Option<Controller>> = const { RefCell::new(None) };
}

/// 窓を入力位置の近くに出す．anchor が無ければマウスの位置の近くに出す．dark は OS がダークモードか
pub fn show(
    anchor: Option<Rect>,
    recognition_delay_milliseconds: u32,
    recognition_timeout_milliseconds: u32,
    theme: ResolvedTheme,
    dark: bool,
) {
    with_controller(|controller| {
        controller.delay = recognition_delay_milliseconds;
        controller.timeout = Duration::from_millis(u64::from(recognition_timeout_milliseconds));
        if controller.fonts.is_none() {
            controller.fonts = controller.renderer.fonts().ok();
        }
        controller.theme = Some(theme);
        controller.chrome = Chrome::new(dark);
        controller.window.set_dark(dark);
        controller.ink.clear();
        controller.unavailable = false;
        controller.hovered = None;
        controller.pressing = None;
        controller.scroll = 0.0;
        controller.place(anchor);
        controller.repaint();
    });
}

pub fn hide() {
    CONTROLLER.with(|controller| {
        if let Ok(mut controller) = controller.try_borrow_mut() {
            if let Some(controller) = controller.as_mut() {
                controller.close();
            }
        }
    });
}

/// 窓が無ければ作ってから body を呼ぶ
fn with_controller(body: impl FnOnce(&mut Controller)) {
    CONTROLLER.with(|cell| {
        let Ok(mut slot) = cell.try_borrow_mut() else {
            return;
        };
        if slot.is_none() {
            *slot = Controller::create();
        }
        if let Some(controller) = slot.as_mut() {
            body(controller);
        }
    });
}

fn on_event(event: &Event) {
    CONTROLLER.with(|cell| {
        if let Ok(mut slot) = cell.try_borrow_mut() {
            if let Some(controller) = slot.as_mut() {
                controller.handle(event);
            }
        }
    });
}

fn on_hit(x: f32, y: f32) -> Hit {
    CONTROLLER.with(|cell| {
        cell.try_borrow().ok().map_or(Hit::Nothing, |slot| {
            slot.as_ref()
                .and_then(|controller| controller.layout.as_ref())
                .map_or(Hit::Nothing, |layout| layout.hit(x, y))
        })
    })
}

impl Controller {
    fn create() -> Option<Self> {
        let window = Window::create(Handlers {
            hit: on_hit,
            event: on_event,
        })
        .ok()?;
        let renderer = Renderer::new().ok()?;
        let results: Results = Arc::new(Mutex::new(None));
        let notifier = window.notifier();
        let shared = results.clone();
        let recognizer = Recognizer::start(move |generation, outcome| {
            if let Ok(mut slot) = shared.lock() {
                *slot = Some((generation, outcome));
            }
            notifier.recognized();
        })
        .ok();
        Some(Self {
            window,
            renderer,
            recognizer,
            results,
            engine: None,
            ink: Ink::default(),
            layout: None,
            fonts: None,
            theme: None,
            chrome: Chrome::new(false),
            delay: 0,
            timeout: Duration::ZERO,
            unavailable: false,
            visible: false,
            hovered: None,
            pressing: None,
            scroll: 0.0,
        })
    }

    fn handle(&mut self, event: &Event) {
        match *event {
            Event::Press(x, y) => self.press(x, y),
            Event::Move(x, y) => self.moved(x, y),
            Event::Release(x, y) => self.release(Some((x, y))),
            Event::CaptureLost => self.release(None),
            Event::Leave => {
                if self.hovered.take().is_some() {
                    self.repaint();
                }
            }
            Event::Wheel { delta, .. } => {
                self.scroll -= delta * tokens::size::handwriting::WHEEL_STEP;
                self.relayout();
                self.repaint();
            }
            Event::Resized => {
                let canvas = self.layout.as_ref().map(|layout| layout.canvas);
                self.relayout();
                // 書く欄の大きさが変わったら，書いた線と欄の位置が合わなくなるので書き直してもらう(macOS と同じ)
                if self.layout.as_ref().map(|layout| layout.canvas) != canvas
                    && canvas.is_some()
                    && !self.ink.is_empty()
                {
                    self.clear();
                }
                self.repaint();
            }
            Event::RecognizeNow => self.recognize(),
            Event::Recognized => self.receive(),
            Event::Paint => self.repaint(),
        }
    }

    fn press(&mut self, x: f32, y: f32) {
        let Some(layout) = &self.layout else { return };
        match layout.hit(x, y) {
            Hit::Canvas => {
                let (x, y) = layout.canvas_point(x, y);
                self.window.stop_timer();
                if self.ink.begin(Point { x, y }) {
                    self.pressing = Some(Pressing::Stroke);
                    self.window.capture();
                    self.repaint();
                }
            }
            Hit::Control(control) if self.enabled(control) => {
                self.pressing = Some(Pressing::Control(control));
                self.hovered = Some(control);
                self.window.capture();
                self.repaint();
            }
            _ => {}
        }
    }

    fn moved(&mut self, x: f32, y: f32) {
        if self.pressing == Some(Pressing::Stroke) {
            if let Some((x, y)) = self.layout.as_ref().map(|layout| layout.canvas_point(x, y)) {
                if self.ink.extend(Point { x, y }) {
                    self.repaint();
                }
            }
            return;
        }
        let hovered = match self.layout.as_ref().map(|layout| layout.hit(x, y)) {
            Some(Hit::Control(control)) if self.enabled(control) => Some(control),
            _ => None,
        };
        if hovered != self.hovered {
            self.hovered = hovered;
            self.repaint();
        }
    }

    /// 離した．at は離した位置(押していた状態が切れただけなら None)
    fn release(&mut self, at: Option<(f32, f32)>) {
        let Some(pressing) = self.pressing.take() else {
            return;
        };
        self.window.release();
        match pressing {
            Pressing::Stroke => {
                if self.ink.end().is_some() {
                    self.window.start_timer(self.delay);
                }
                self.repaint();
            }
            Pressing::Control(control) => {
                let still_over = at
                    .zip(self.layout.as_ref())
                    .is_some_and(|((x, y), layout)| layout.hit(x, y) == Hit::Control(control));
                if still_over {
                    self.activate(control);
                } else {
                    self.repaint();
                }
            }
        }
    }

    fn enabled(&self, control: Control) -> bool {
        match control {
            Control::Undo | Control::Clear => !self.ink.is_empty(),
            Control::Candidate(index) => index < self.ink.candidates().len(),
            Control::Close => true,
        }
    }

    fn activate(&mut self, control: Control) {
        match control {
            Control::Candidate(index) => {
                // 選んだ文字は入力先に入れて閉じる(macOS の onSelect と同じ)
                if let Some(text) = self.ink.candidates().get(index).cloned() {
                    self.send(RequestBody::HandwritingChosen { text });
                    self.close();
                }
            }
            Control::Undo => {
                self.window.stop_timer();
                if self.ink.undo() {
                    if !self.ink.is_empty() {
                        // 残った線を読み直す
                        self.window.start_timer(self.delay);
                    }
                    self.after_change();
                }
            }
            Control::Clear => self.clear(),
            Control::Close => {
                self.send(RequestBody::HandwritingClosed);
                self.close();
            }
        }
    }

    fn clear(&mut self) {
        self.window.stop_timer();
        self.ink.clear();
        self.after_change();
    }

    /// 線や候補が変わったあとで，押せなくなった部品の強調を外して描き直す
    fn after_change(&mut self) {
        if self.hovered.is_some_and(|control| !self.enabled(control)) {
            self.hovered = None;
        }
        self.scroll = 0.0;
        self.relayout();
        self.repaint();
    }

    fn recognize(&mut self) {
        if self.ink.is_empty() {
            return;
        }
        if let Some(recognizer) = &self.recognizer {
            recognizer.recognize(
                self.ink.generation(),
                self.ink.strokes().to_vec(),
                self.timeout,
            );
        } else {
            self.unavailable = true;
            self.repaint();
        }
    }

    fn receive(&mut self) {
        let received = self.results.lock().ok().and_then(|mut slot| slot.take());
        let Some((generation, outcome)) = received else {
            return;
        };
        match outcome {
            Outcome::Candidates(candidates) => {
                self.unavailable = false;
                if !self.ink.accept(generation, candidates) {
                    return;
                }
            }
            Outcome::Unavailable => self.unavailable = true,
        }
        self.after_change();
    }

    /// 選んだ文字と閉じたことはエンジンに送る．エンジンが入力先の入力欄に入れる
    fn send(&mut self, body: RequestBody) {
        if self.engine.is_none() {
            self.engine = pipe_name("engine")
                .ok()
                .and_then(|name| EngineClient::start(name).ok());
        }
        if let Some(engine) = &self.engine {
            let _ = engine.send(body);
        }
    }

    fn close(&mut self) {
        self.window.release();
        self.window.hide();
        self.ink.clear();
        self.unavailable = false;
        self.visible = false;
        self.hovered = None;
        self.pressing = None;
    }

    fn relayout(&mut self) {
        let Some(fonts) = &self.fonts else { return };
        let (width, height) = if self.visible {
            self.window.size()
        } else {
            minimum_size()
        };
        let layout = Layout::new(
            width,
            height,
            self.ink.candidates(),
            strings::CLEAR,
            self.scroll,
            fonts,
        );
        self.scroll = layout.scroll;
        self.layout = Some(layout);
    }

    /// 入力位置(ピクセル)の近くに，いちばん小さい大きさで出す(macOS も開くたびに決まった大きさにする)
    fn place(&mut self, anchor: Option<Rect>) {
        let caret = anchor.map_or_else(Window::cursor, |anchor| Bounds {
            left: anchor.x,
            top: anchor.y,
            right: anchor.x + anchor.width.max(1),
            bottom: anchor.y + anchor.height.max(1),
        });
        // 置く先の画面の DPI で大きさを決めるため，先にその画面へ動かす(窓はまだ見せない)
        if !self.visible {
            self.window.move_to(caret.left, caret.bottom);
        }
        self.visible = false;
        self.relayout();
        let scale = self.window.scale();
        let (width, height) = minimum_size();
        let width = (width * scale).round() as i32;
        let height = (height * scale).round() as i32;
        let (x, y) = origin(
            caret,
            Window::work_area(caret),
            width,
            height,
            (tokens::size::handwriting::ANCHOR_GAP * scale).round() as i32,
        );
        self.window.show_at(x, y, width, height);
        self.visible = true;
        self.relayout();
    }

    fn repaint(&mut self) {
        if !self.visible {
            return;
        }
        let (Some(layout), Some(fonts), Some(theme)) = (&self.layout, &self.fonts, &self.theme)
        else {
            return;
        };
        let pressed = match self.pressing {
            Some(Pressing::Control(control)) => Some(control),
            _ => None,
        };
        let state = State {
            hovered: self.hovered,
            pressed,
            note: self.unavailable.then_some(strings::NO_RECOGNIZER),
        };
        let _ = self.renderer.draw(
            self.window.hwnd(),
            self.window.scale(),
            layout,
            &self.ink,
            state,
            theme,
            &self.chrome,
            fonts,
        );
    }
}

/// 見本の PNG(デバッグビルドの --render-snapshots)．macOS の見本と見比べられるよう，空の窓・書いた窓・候補を送った窓を描く
#[cfg(debug_assertions)]
pub mod snapshot {
    use super::render::{Chrome, Renderer, State};
    use crate::handwriting::ink::{Ink, Point};
    use crate::handwriting::layout::{minimum_size, Control, Layout};
    use crate::handwriting::strings;
    use crate::theme::ResolvedTheme;
    use windows::Win32::Graphics::Direct2D::ID2D1Factory;
    use windows::Win32::Graphics::Direct2D::ID2D1RenderTarget;
    use windows_core::Result;

    /// 見本の種類
    #[derive(Debug, Clone, Copy)]
    pub enum Sample {
        /// 開いたところ(案内だけ)
        Empty,
        /// 書いて候補が出たところ．候補にポインタを置いている
        Written,
        /// 候補を右の端まで送ったところ
        Scrolled,
        /// 日本語の手書き認識が入っていない
        Unavailable,
    }

    pub const SAMPLES: [(&str, Sample); 4] = [
        ("empty", Sample::Empty),
        ("written", Sample::Written),
        ("scrolled", Sample::Scrolled),
        ("unavailable", Sample::Unavailable),
    ];

    pub struct Snapshot {
        renderer: Renderer,
    }

    impl Snapshot {
        pub fn new() -> Result<Self> {
            Ok(Self {
                renderer: Renderer::new()?,
            })
        }

        pub fn factory(&self) -> &ID2D1Factory {
            self.renderer.factory()
        }

        /// 見本の窓の大きさ(DIP)
        pub fn size() -> (f32, f32) {
            minimum_size()
        }

        pub fn paint(
            &self,
            target: &ID2D1RenderTarget,
            scale: f32,
            sample: Sample,
            theme: &ResolvedTheme,
            dark: bool,
        ) -> Result<()> {
            let fonts = self.renderer.fonts()?;
            let mut ink = Ink::default();
            if !matches!(sample, Sample::Empty) {
                // 「永」に似た画
                let strokes: [&[(f32, f32)]; 5] = [
                    &[(120.0, 40.0), (138.0, 52.0)],
                    &[(70.0, 80.0), (150.0, 74.0), (128.0, 120.0)],
                    &[(130.0, 76.0), (130.0, 220.0), (112.0, 206.0)],
                    &[(70.0, 140.0), (110.0, 120.0), (60.0, 200.0)],
                    &[(190.0, 100.0), (150.0, 140.0), (210.0, 210.0)],
                ];
                let mut generation = 0;
                for stroke in strokes {
                    for (index, (x, y)) in stroke.iter().enumerate() {
                        let point = Point { x: *x, y: *y };
                        if index == 0 {
                            ink.begin(point);
                        } else {
                            ink.extend(point);
                        }
                    }
                    generation = ink.end().unwrap_or(generation);
                }
                if !matches!(sample, Sample::Unavailable) {
                    let candidates = ["永", "氷", "水", "泳", "詠", "栄", "求", "氾"];
                    ink.accept(
                        generation,
                        candidates.iter().map(|text| text.to_string()).collect(),
                    );
                }
            }
            let (width, height) = minimum_size();
            let scroll = if matches!(sample, Sample::Scrolled) {
                f32::MAX
            } else {
                0.0
            };
            let layout = Layout::new(
                width,
                height,
                ink.candidates(),
                strings::CLEAR,
                scroll,
                &fonts,
            );
            let state = State {
                hovered: matches!(sample, Sample::Written).then_some(Control::Candidate(1)),
                pressed: None,
                note: matches!(sample, Sample::Unavailable).then_some(strings::NO_RECOGNIZER),
            };
            self.renderer.paint(
                target,
                scale,
                &layout,
                &ink,
                state,
                theme,
                &Chrome::new(dark),
                &fonts,
            )
        }
    }
}
