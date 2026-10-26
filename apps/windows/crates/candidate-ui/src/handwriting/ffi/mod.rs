#![allow(unsafe_code)]

mod recognizer;
mod render;
mod window;

use super::ink::{Ink, Point};
use super::layout::{origin, Bounds, Hit, Layout};
use super::strings;
use crate::theme::ResolvedTheme;
use ipc::windows::{pipe_name, EngineClient};
use ipc::{Rect, RequestBody};
use recognizer::{Outcome, Recognizer};
use render::{Fonts, Renderer};
use std::cell::RefCell;
use std::sync::{Arc, Mutex};
use window::{Event, Window};

/// 入力位置と窓のあいだの隙間(ピクセル)
const ANCHOR_GAP: i32 = 4;

type Results = Arc<Mutex<Option<(u64, Outcome)>>>;

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
    delay: u32,
    unavailable: bool,
    visible: bool,
}

thread_local! {
    static CONTROLLER: RefCell<Option<Controller>> = const { RefCell::new(None) };
}

/// 窓を入力位置の近くに出す．anchor が無ければマウスの位置の近くに出す
pub fn show(
    anchor: Option<Rect>,
    recognition_delay_milliseconds: u32,
    theme: ResolvedTheme,
    font_size: f32,
) {
    with_controller(|controller| {
        controller.delay = recognition_delay_milliseconds;
        controller.fonts = controller.renderer.fonts(font_size).ok();
        controller.theme = Some(theme);
        controller.ink.clear();
        controller.relayout();
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

fn on_event(event: &Event) -> bool {
    CONTROLLER.with(|cell| {
        let Ok(mut slot) = cell.try_borrow_mut() else {
            return false;
        };
        slot.as_mut()
            .is_some_and(|controller| controller.handle(event))
    })
}

impl Controller {
    fn create() -> Option<Self> {
        let window = Window::create(on_event).ok()?;
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
            delay: 0,
            unavailable: false,
            visible: false,
        })
    }

    fn handle(&mut self, event: &Event) -> bool {
        match *event {
            Event::IsHeader(x, y) => {
                return self
                    .layout
                    .as_ref()
                    .is_some_and(|layout| layout.hit(x, y) == Hit::Header);
            }
            Event::Press(x, y) => self.press(x, y),
            Event::Move(x, y) => {
                if self.ink.is_stroking() {
                    if let Some((x, y)) =
                        self.layout.as_ref().map(|layout| layout.canvas_point(x, y))
                    {
                        if self.ink.extend(Point { x, y }) {
                            self.repaint();
                        }
                    }
                }
            }
            Event::Release | Event::CaptureLost => {
                if self.ink.end().is_some() {
                    self.window.release();
                    self.window.start_timer(self.delay);
                }
            }
            Event::RecognizeNow => {
                if let Some(recognizer) = &self.recognizer {
                    recognizer.recognize(self.ink.generation(), self.ink.strokes().to_vec());
                } else {
                    self.unavailable = true;
                    self.repaint();
                }
            }
            Event::Recognized => self.receive(),
            Event::Paint => self.repaint(),
        }
        false
    }

    fn press(&mut self, x: f32, y: f32) {
        let Some(layout) = &self.layout else { return };
        match layout.hit(x, y) {
            Hit::Canvas => {
                let (x, y) = layout.canvas_point(x, y);
                self.window.stop_timer();
                if self.ink.begin(Point { x, y }) {
                    self.window.capture();
                    self.repaint();
                }
            }
            Hit::Candidate(index) => {
                if let Some(text) = self.ink.candidates().get(index).cloned() {
                    self.send(RequestBody::HandwritingChosen { text });
                    self.close();
                }
            }
            Hit::Clear => {
                self.window.stop_timer();
                self.ink.clear();
                self.relayout();
                self.repaint();
            }
            Hit::Close => {
                self.send(RequestBody::HandwritingClosed);
                self.close();
            }
            Hit::Header | Hit::Nothing => {}
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
        self.relayout();
        self.repaint();
    }

    /// 選んだ文字と閉じたことはエンジンに送る．エンジンが窓を開いた入力欄に入れる
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
    }

    fn relayout(&mut self) {
        let Some(fonts) = &self.fonts else { return };
        self.layout = Some(Layout::new(
            fonts.label_height(),
            self.ink.candidates(),
            strings::CLEAR,
            fonts,
        ));
    }

    fn place(&mut self, anchor: Option<Rect>) {
        let Some(layout) = &self.layout else { return };
        let caret = anchor.map_or_else(Window::cursor, |anchor| Bounds {
            left: anchor.x,
            top: anchor.y,
            right: anchor.x + anchor.width.max(1),
            bottom: anchor.y + anchor.height.max(1),
        });
        let scale = self.window.scale();
        let width = (layout.width * scale).ceil() as i32;
        let height = (layout.height * scale).ceil() as i32;
        let (x, y) = origin(caret, Window::work_area(caret), width, height, ANCHOR_GAP);
        self.window.show_at(x, y, width, height);
        self.visible = true;
    }

    fn repaint(&mut self) {
        if !self.visible {
            return;
        }
        let (Some(layout), Some(fonts), Some(theme)) = (&self.layout, &self.fonts, &self.theme)
        else {
            return;
        };
        let note = self.unavailable.then_some(strings::NO_RECOGNIZER);
        let _ = self.renderer.draw(
            self.window.hwnd(),
            self.window.scale(),
            layout,
            &self.ink,
            note,
            theme,
            fonts,
        );
    }
}
