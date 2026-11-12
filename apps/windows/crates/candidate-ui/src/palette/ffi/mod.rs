#![allow(unsafe_code)]

//! パレットの窓を出し入れし，押した対象をエンジンに送る(macOS の PaletteController)．窓はプロセスで 1 つだけ使い回す．
//! 窓は開いたときの入力位置の近くに置き，開いているあいだは動かさない(マス目の位置を覚えて選べるように)

mod window;

use super::layout::{cell_size, Fonts, Layout, Wheel};
use super::motion::{ease_out, progress, Motion};
use super::scene;
use crate::announce::{self, Announcer};
use crate::app::render::{Renderer, TextMeasure};
use crate::app::{system, FRAME_MILLISECONDS};
use crate::geometry::{origin, Bounds};
use crate::scene::{surround, Draw, Look, Scene, Surround};
use crate::theme::ResolvedTheme;
use ipc::windows::{pipe_name, EngineClient};
use ipc::{PalettePanel, PaletteTarget, Rect, RequestBody};
use std::cell::RefCell;
use std::time::Instant;
use tokens::motion::palette as duration;
use window::{Event, Window};

/// 出しているパレット
struct Shown {
    panel: PalettePanel,
    layout: Layout,
    /// 窓の全体(角丸のテーマは影の余白を含む)
    scene: Scene,
    measure: std::rc::Rc<TextMeasure>,
    /// 動きの 1 コマごとに中身を作り直すために覚えておく
    theme: ResolvedTheme,
    /// 窓の左上と大きさ(画面のピクセル)
    placement: (i32, i32, i32, i32),
}

/// パレットの窓の状態．候補ウィンドウのプロセスの窓のスレッドだけで触る
struct Controller {
    window: Window,
    renderer: Renderer,
    engine: Option<EngineClient>,
    shown: Option<Shown>,
    /// 本体の左上(画面のピクセル)．開いているあいだは動かさない
    origin: Option<(i32, i32)>,
    /// ポインタを置いているマス(行と列)．ほかのマスに移ったときだけエンジンに知らせる
    hovered: Option<(u32, u32)>,
    /// 最後に知ったポインタの位置(窓の中の DIP)．窓を出し直したときに OS が送る，動いていない WM_MOUSEMOVE を除く
    /// (キーで開いたパレットの下にたまたまポインタがあっても，選んでいる文字を変えない)
    pointer: Option<(f32, f32)>,
    wheel: Wheel,
    announcer: Announcer,
    /// 動いている部品(選択の枠・印・中身・帯・ピン)
    motion: Motion,
    /// 開く動きを始めた時刻．開き終えたら None
    opening: Option<Instant>,
    /// 動きの 1 コマを描く時計が動いているか
    ticking: bool,
}

thread_local! {
    static CONTROLLER: RefCell<Option<Controller>> = const { RefCell::new(None) };
}

/// パレットを出す．初めて出すときは入力位置(anchor．無ければマウスの位置)の近くに置き，
/// 出ているあいだは本体の左上を保って大きさだけを変える．gap は入力位置とのあいだ(ピクセル)
pub fn show(panel: PalettePanel, anchor: Option<Rect>, theme: ResolvedTheme, gap: i32) {
    CONTROLLER.with(|cell| {
        let Ok(mut slot) = cell.try_borrow_mut() else {
            return;
        };
        if slot.is_none() {
            *slot = Controller::create();
        }
        if let Some(controller) = slot.as_mut() {
            controller.show(panel, anchor, &theme, gap);
        }
    });
}

pub fn hide() {
    CONTROLLER.with(|cell| {
        if let Ok(mut slot) = cell.try_borrow_mut() {
            if let Some(controller) = slot.as_mut() {
                controller.hide();
            }
        }
    });
}

fn on_event(event: Event) {
    CONTROLLER.with(|cell| {
        if let Ok(mut slot) = cell.try_borrow_mut() {
            if let Some(controller) = slot.as_mut() {
                controller.handle(event);
            }
        }
    });
}

impl Controller {
    fn create() -> Option<Self> {
        Some(Self {
            window: Window::create(on_event).ok()?,
            renderer: Renderer::new().ok()?,
            engine: None,
            shown: None,
            origin: None,
            hovered: None,
            pointer: None,
            wheel: Wheel::default(),
            announcer: Announcer::default(),
            motion: Motion::default(),
            opening: None,
            ticking: false,
        })
    }

    fn show(&mut self, panel: PalettePanel, anchor: Option<Rect>, theme: &ResolvedTheme, gap: i32) {
        let font_size = tokens::size::candidate::FONT_SIZE;
        let fonts = Fonts::new(cell_size(&panel));
        let Ok(measure) = self.renderer.measure_with(theme, font_size, &fonts.all()) else {
            return;
        };
        let layout = Layout::new(&panel, theme, &measure);
        let look = Look::new(theme, font_size);
        // 窓の大きさと位置を決めるための，止まっている中身(描くのは frame で動きの途中の形にしてから)
        let scene = surround(
            scene::palette(
                &panel,
                &layout,
                &look,
                measure.as_ref(),
                super::motion::Tween::default(),
            ),
            theme,
            Surround::Shadow,
        );
        let scale = self.window.scale();
        let pixels = |value: f32| (value * scale).round() as i32;
        let (left, top) = match self.origin {
            Some(placed) => placed,
            None => {
                let caret = anchor.map_or_else(Window::cursor, |anchor| Bounds {
                    left: anchor.x,
                    top: anchor.y,
                    right: anchor.x + anchor.width.max(1),
                    bottom: anchor.y + anchor.height.max(1),
                });
                origin(
                    caret,
                    Window::work_area(caret),
                    pixels(layout.width),
                    pixels(layout.height),
                    gap,
                )
            }
        };
        let opening = self.origin.is_none();
        self.origin = Some((left, top));
        let placement = (
            left - pixels(scene.body.x),
            top - pixels(scene.body.y),
            (scene.width * scale).ceil() as i32,
            (scene.height * scale).ceil() as i32,
        );
        // 動きを始める．「アニメーション効果」がオフなら動かさない
        let now = Instant::now();
        let animates = !system::reduce_motion();
        match &self.shown {
            Some(old) if animates => {
                self.motion
                    .start(&old.panel, &old.layout, &panel, &layout, now)
            }
            _ => self.motion.reset(),
        }
        if opening {
            self.opening = animates.then_some(now);
        }
        self.window
            .show_at(placement.0, placement.1, placement.2, placement.3);
        if opening {
            self.pointer = Some(self.window.pointer());
        }
        let text = announce::palette(&panel);
        self.shown = Some(Shown {
            panel,
            layout,
            scene,
            measure,
            theme: theme.clone(),
            placement,
        });
        self.frame(now);
        // ナレーターが動いているときだけ，選んでいる文字の名前と知らせを読み上げる
        if system::screen_reader() {
            if let Some(text) = self.announcer.next(text) {
                self.window.announce(&text);
            }
        }
    }

    fn hide(&mut self) {
        self.window.hide();
        self.motion.reset();
        self.opening = None;
        self.ticking = false;
        self.shown = None;
        self.origin = None;
        self.hovered = None;
        self.pointer = None;
        self.wheel.reset();
        self.announcer.reset();
    }

    /// now の時点の動きの途中の形で中身を作り直して描く．開くあいだは窓を少し下から上げながら濃くする．
    /// 動いているあいだは次のコマを描く時計を動かし，止まったら時計を止める
    fn frame(&mut self, now: Instant) {
        let Some(shown) = self.shown.as_mut() else {
            return;
        };
        let tween = self.motion.tween(&shown.panel, &shown.layout, now);
        let look = Look::new(&shown.theme, tokens::size::candidate::FONT_SIZE);
        let content = scene::palette(
            &shown.panel,
            &shown.layout,
            &look,
            shown.measure.as_ref(),
            tween,
        );
        let mut scene = surround(content, &shown.theme, Surround::Shadow);
        let (x, y, width, height) = shown.placement;
        let opening = self
            .opening
            .map(|start| progress(start, duration::OPEN, now))
            .filter(|t| *t < 1.0);
        match opening {
            Some(t) => {
                let shown_amount = ease_out(t);
                let rise =
                    tokens::size::palette::OPEN_RISE * self.window.scale() * (1.0 - shown_amount);
                self.window
                    .show_at(x, y + rise.round() as i32, width, height);
                scene = faded(scene, shown_amount);
            }
            None => {
                if self.opening.take().is_some() {
                    self.window.show_at(x, y, width, height);
                }
            }
        }
        shown.scene = scene;
        self.repaint();
        let moving = opening.is_some() || self.motion.is_active(now);
        if moving && !self.ticking {
            self.window.start_motion_timer(FRAME_MILLISECONDS);
        } else if !moving && self.ticking {
            self.window.stop_motion_timer();
        }
        self.ticking = moving;
    }

    fn repaint(&mut self) {
        if let Some(shown) = &self.shown {
            let _ = self
                .window
                .draw(&self.renderer, &shown.scene, &shown.measure);
        }
    }

    fn handle(&mut self, event: Event) {
        match event {
            Event::Press(x, y) => {
                if let Some(target) = self.target_at(x, y, false) {
                    self.send(target);
                }
            }
            Event::Move(x, y) => {
                if self.pointer.replace((x, y)) == Some((x, y)) {
                    return;
                }
                match self.target_at(x, y, true) {
                    Some(PaletteTarget::Hover { row, column }) => {
                        if self.hovered != Some((row, column)) {
                            self.hovered = Some((row, column));
                            self.send(PaletteTarget::Hover { row, column });
                        }
                    }
                    _ => self.hovered = None,
                }
            }
            Event::Leave => {
                self.hovered = None;
                self.pointer = None;
            }
            Event::Wheel(notches) => {
                if self.shown.is_none() {
                    return;
                }
                let rows = self.wheel.turn(notches);
                if rows != 0 {
                    self.send(PaletteTarget::Scroll { rows });
                }
            }
            Event::Paint => self.repaint(),
            Event::Tick => self.frame(Instant::now()),
        }
    }

    /// 窓の中の (x, y)(DIP)の対象．影の余白を除いた本体の座標にして調べる
    fn target_at(&self, x: f32, y: f32, hovering: bool) -> Option<PaletteTarget> {
        let shown = self.shown.as_ref()?;
        let body = shown.scene.body;
        shown
            .layout
            .target(&shown.panel, x - body.x, y - body.y, hovering)
    }

    /// 押した対象をエンジンに送る．エンジンはパレットを出しているセッションの次の wake で，キーと同じに処理する
    fn send(&mut self, target: PaletteTarget) {
        if self.engine.is_none() {
            self.engine = pipe_name("engine")
                .ok()
                .and_then(|name| EngineClient::start(name).ok());
        }
        if let Some(engine) = &self.engine {
            let _ = engine.send(RequestBody::ChoosePalette { target });
        }
    }
}

/// 窓の全体を opacity の濃さにした中身(開く動き)．色の絵文字も同じ濃さにするため，全体をまとまり(Draw::Group)にする
fn faded(scene: Scene, opacity: f32) -> Scene {
    let whole = crate::geometry::Frame::new(0.0, 0.0, scene.width, scene.height);
    Scene {
        draws: vec![Draw::Group {
            clip: whole,
            opacity,
            scale: 1.0,
            draws: scene.draws,
        }],
        ..scene
    }
}
