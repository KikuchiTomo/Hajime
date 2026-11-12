#![allow(unsafe_code)]

//! パレットの窓を出し入れし，押した対象をエンジンに送る(macOS の PaletteController)．窓はプロセスで 1 つだけ使い回す．
//! 窓は開いたときの入力位置の近くに置き，開いているあいだは動かさない(マス目の位置を覚えて選べるように)

mod window;

use super::layout::{cell_size, Fonts, Layout, Wheel};
use super::scene;
use crate::announce::{self, Announcer};
use crate::app::render::{Renderer, TextMeasure};
use crate::app::system;
use crate::geometry::{origin, Bounds};
use crate::scene::{surround, Look, Scene, Surround};
use crate::theme::ResolvedTheme;
use ipc::windows::{pipe_name, EngineClient};
use ipc::{PalettePanel, PaletteTarget, Rect, RequestBody};
use std::cell::RefCell;
use window::{Event, Window};

/// 出しているパレット
struct Shown {
    panel: PalettePanel,
    layout: Layout,
    /// 窓の全体(角丸のテーマは影の余白を含む)
    scene: Scene,
    measure: std::rc::Rc<TextMeasure>,
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
        let scene = surround(
            scene::palette(&panel, &layout, &look, &measure),
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
        self.window.show_at(
            left - pixels(scene.body.x),
            top - pixels(scene.body.y),
            (scene.width * scale).ceil() as i32,
            (scene.height * scale).ceil() as i32,
        );
        if opening {
            self.pointer = Some(self.window.pointer());
        }
        let text = announce::palette(&panel);
        self.shown = Some(Shown {
            panel,
            layout,
            scene,
            measure,
        });
        self.repaint();
        // ナレーターが動いているときだけ，選んでいる文字の名前と知らせを読み上げる
        if system::screen_reader() {
            if let Some(text) = self.announcer.next(text) {
                self.window.announce(&text);
            }
        }
    }

    fn hide(&mut self) {
        self.window.hide();
        self.shown = None;
        self.origin = None;
        self.hovered = None;
        self.pointer = None;
        self.wheel.reset();
        self.announcer.reset();
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
