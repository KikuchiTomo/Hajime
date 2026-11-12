#![forbid(unsafe_code)]

//! 初期設定の窓(macOS の OnboardingView)．設定の画面と同じ描き方(Direct2D・トークンの色・Mica・DPI・高コントラスト・読み上げ)で，
//! 左に実演の舞台，右にページ(見出し・選ぶもの・足元)を置く．大きさ・余白・動きは onboarding のトークン(macOS と同じ値)．
//! 実演は台本(demo)を時間で進め，候補の窓とモードの札は candidate-ui の描き方で描いて舞台に重ねる．
//! 止まっているコマのあいだは時計で次のコマを待ち，CPU を使わない．動きを減らす設定のときは最後のコマだけを出す．
//! 値は「はじめる」でまとめてエンジンに書く．済んだことは HKCU に書く(ffi::set_setup_completed)

use super::ffi::d2d::{self, Graphics, Layer, LayerLook, PreviewPixels, Surface};
use super::ffi::uia;
use super::ffi::{self, Window};
use super::paint::{self, ButtonKind, Canvas, Measure, State, TextLayout, TextStyle};
use super::theme::{Color, Theme};
use super::window::ForcedTheme;
use super::Store;
use crate::catalog::{Catalog, Timing};
use crate::demo::{self, Frame, Mode, Panel, Script, Style, Today};
use crate::layout::Rect;
use crate::model::SettingsModel;
use crate::strings::{more, windows_wizard as notes, wizard as text};
use crate::ui::anim::{Easing, Tween};
use crate::ui::scroll::{self, Scroller};
use crate::wizard::{self, Card, Choices, Field, Info, Item, Mark, Picker, Spot, Step};
use candidate_ui::app::preview::{Preview, Shown};
use std::cell::RefCell;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokens::motion::onboarding as pace;
use tokens::motion::settings_windows as motion;
use tokens::opacity::onboarding as shade;
use tokens::size::onboarding as board;
use tokens::size::settings_windows as size;
use tokens::size::{part, space};
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::Controls::WM_MOUSELEAVE;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    VK_DOWN, VK_END, VK_ESCAPE, VK_F4, VK_HOME, VK_LEFT, VK_RETURN, VK_RIGHT, VK_SPACE, VK_TAB,
    VK_UP,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CW_USEDEFAULT, WHEEL_DELTA, WINDOW_EX_STYLE, WM_APP, WM_CAPTURECHANGED, WM_DESTROY,
    WM_DPICHANGED, WM_ERASEBKGND, WM_GETOBJECT, WM_KEYDOWN, WM_LBUTTONDOWN, WM_LBUTTONUP,
    WM_MOUSEMOVE, WM_MOUSEWHEEL, WM_PAINT, WM_SETTINGCHANGE, WM_SYSCOLORCHANGE, WM_THEMECHANGED,
    WM_TIMER, WS_CAPTION, WS_MINIMIZEBOX, WS_OVERLAPPED, WS_SYSMENU,
};
use windows_core::{w, PCWSTR};

pub const CLASS: PCWSTR = w!("hajime.setup");
/// 実演の次のコマを待つ時計
const DEMO_TIMER: usize = 1;
/// エンジンにつなぎ直す時計
const RECONNECT_TIMER: usize = 2;
/// 読み込みのスレッドが終わった
const WM_LOADED: u32 = WM_APP + 1;

/// 読み上げの要素の番号
const NODE_CARD: i32 = 1000;
const NODE_THEME: i32 = 2000;
const NODE_PICKER: i32 = 3000;
const NODE_SLIDER: i32 = 3500;
const NODE_SPOT: i32 = 4000;
const NODE_MENU: i32 = 5000;
const NODE_BUTTON: i32 = 6000;
const NODE_DEMO: i32 = 7000;
const NODE_INFO: i32 = 8000;

/// ページを替える動き(macOS の easeInOut)
const EASE_IN_OUT: Easing = Easing::new(0.42, 0.0, 0.58, 1.0);
/// 説明の札を浮かべる動き(macOS のばねの動きに近い，弾まずに柔らかく止まる曲線)
const SOFT: Easing = Easing::new(0.22, 1.0, 0.36, 1.0);
/// 説明の札を浮かべる長さ(ページを替える動きの何倍か．macOS の spring の response と同じ比)
const CAPTION_MOTION: f32 = 1.6 * 1.3;
/// 前の説明の札を消す長さ(ページを替える動きの何倍か)
const CAPTION_LEAVE: f32 = 0.6;

/// 見出しの「n / 9」の行の高さ
const COUNTER_HEIGHT: f32 = board::COUNTER_HEIGHT;
/// カードの名前の行の高さ
const LINE: f32 = size::BODY_LINE_HEIGHT;
/// 選択肢のカードの丸の大きさ(macOS の title3 の記号)
const CHECK: f32 = board::CHECK_SIZE;
/// 推奨の札の高さ
const BADGE_HEIGHT: f32 = board::BADGE_HEIGHT;
/// テーマのカードの見本の高さ(macOS の fieldHeight × 1.3)
const SWATCH_HEIGHT: f32 = board::FIELD_HEIGHT * 1.3;
/// 機能の行の上下の余白(macOS と同じ)
const SPOT_PADDING_Y: f32 = space::GROUP;
/// スライダーのつまみの大きさ
const THUMB: f32 = board::SLIDER_THUMB;
/// 足元のボタンの最小の幅
const BUTTON_MIN_WIDTH: f32 = board::BUTTON_MIN_WIDTH;
/// メニューの影のにじみの輪の数
const MENU_SHADOW_RINGS: usize = 4;
/// 覚えておく実演の画像の数(1 つの台本の窓が収まる数)
const OVERLAY_CACHE: usize = 24;

type Model = SettingsModel<Store>;
type Loaded = Arc<Mutex<Option<Option<Model>>>>;

/// 足元のボタン
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Button {
    Skip,
    Back,
    /// 最後のページでは「はじめる」
    Next,
}

const BUTTONS: [Button; 3] = [Button::Skip, Button::Back, Button::Next];

/// 押せるもの(item はページの並べるものの番号)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Target {
    Card(usize, usize),
    Theme(usize),
    Picker(usize),
    Slider(usize),
    /// 機能の行(ポインターを置くと実演を見せる)
    Spot(usize),
    /// 機能の行のスイッチ
    Switch(usize),
    MenuItem(usize),
    Button(Button),
}

/// キーボードで選んでいるもの(カードとテーマのまとまりは 1 つとして Tab で移り，矢印で選ぶ)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Focus {
    Cards(usize),
    Themes,
    Picker(usize),
    Slider(usize),
    Spot(usize),
    Button(Button),
}

/// ページの中の置き場所(content の座標は，スクロールする領域の左上から)
struct PageLayout {
    counter: Rect,
    title: Rect,
    detail: Rect,
    /// スクロールする領域(窓の座標)
    viewport: Rect,
    parts: Vec<Part>,
    content_height: f32,
}

#[derive(Debug, Clone, Copy)]
enum PartKind {
    Card {
        item: usize,
        index: usize,
        field: Field,
        card: Card,
    },
    Info(usize, Info),
    Theme(usize),
    Picker {
        item: usize,
        picker: Picker,
        /// メニューのボタン(content の座標)
        control: Rect,
    },
    Slider {
        item: usize,
        title: &'static str,
        field: Field,
        track: Rect,
    },
    Spot {
        index: usize,
        spot: Spot,
        switch: Rect,
    },
    /// タスクバーから設定を開ける案内(最後のページ)
    TaskbarNote,
}

#[derive(Debug, Clone, Copy)]
struct Part {
    kind: PartKind,
    rect: Rect,
}

/// 開いているメニュー(入力する文字の行と最初に選ぶ文節)
struct Menu {
    item: usize,
    picker: Picker,
    highlighted: usize,
    /// 窓の座標
    rect: Rect,
    opened: Tween,
}

/// 舞台に重ねる候補の窓とモードの札の画像
struct Overlay {
    pixels: PreviewPixels,
    /// 舞台の座標(DIP)の左上
    x: f32,
    y: f32,
}

/// ページを替えるあいだ，薄くして消す前のページ
struct Leaving {
    step: Step,
    scroll: f32,
    frame: Option<Frame>,
    overlay: Option<Overlay>,
}

pub struct Options {
    pub started: Instant,
    pub theme: Option<ForcedTheme>,
    /// 初めに開くページ(見本の撮影)
    pub step: Option<Step>,
    /// エンジンにつながずに見本の値で開く(見本の撮影．値は書かない)
    pub offline: bool,
}

struct Wizard {
    window: Window,
    graphics: Graphics,
    surface: Surface,
    theme: Theme,
    forced_theme: Option<ForcedTheme>,
    mica: bool,
    animations: bool,
    catalog: Catalog,
    connect: fn(&Timing) -> Option<Store>,
    /// エンジンにつながず，見本の値で開いた(書き込まない)
    offline: bool,
    model: Option<Model>,
    loaded: Loaded,
    loading: bool,
    step: Step,
    choices: Choices,
    script: Script,
    /// 台本を作り直すたびに増やす(実演の画像を作り直すかを決める)
    script_id: u64,
    /// 実演を始めた時(ミリ秒)
    demo_started: f64,
    today: Today,
    /// ページを替える動き(0 から 1)と，薄くしていく前のページ
    fade: Tween,
    leaving: Option<Leaving>,
    /// 機能の紹介のページで見せている機能と，その説明の札を浮かべる動き．前の札は薄くして消す
    spotlight: Option<&'static str>,
    caption: Tween,
    caption_leaving: Option<(&'static str, Step, Tween)>,
    /// 見せている機能の行を強調する動き
    spot_glows: Vec<(&'static str, Tween)>,
    /// オン・オフを切り替えたときのつまみの動き(0 はオフ，1 はオン)
    knobs: Vec<(&'static str, Tween)>,
    /// ポインターを載せたときの色の動き
    hovers: Vec<(Target, Tween)>,
    scroll: Scroller,
    focus: Focus,
    focus_visible: bool,
    hover: Option<Target>,
    pressed: Option<Target>,
    menu: Option<Menu>,
    /// スライダーを動かしている途中の値(放したら選ぶ)
    dragging: Option<f64>,
    error: Option<&'static str>,
    preview: Option<Preview>,
    overlay: Option<Overlay>,
    /// 実演の画像を作った台本とコマ
    overlay_source: Option<(u64, usize)>,
    overlay_cache: Vec<(String, u32, u32, Vec<u8>, f32, f32)>,
    generation: u64,
    started: Instant,
}

thread_local! {
    static WIZARD: RefCell<Option<Wizard>> = const { RefCell::new(None) };
    /// 窓がまだあるか(ボタンで窓を閉じたあとに描かない)
    static WIZARD_ALIVE: std::cell::Cell<bool> = const { std::cell::Cell::new(true) };
}

fn with_wizard<T>(f: impl FnOnce(&mut Wizard) -> T) -> Option<T> {
    WIZARD.with(|cell| {
        let mut borrowed = cell.try_borrow_mut().ok()?;
        borrowed.as_mut().map(f)
    })
}

/// ウィザードの窓を開く．すでに開いていれば開かない
pub fn open(
    catalog: Catalog,
    connect: fn(&Timing) -> Option<Store>,
    options: Options,
) -> Option<Window> {
    if ffi::window_exists(CLASS) {
        return None;
    }
    ffi::register_class(CLASS, Some(procedure), false);
    let window = ffi::create(
        WINDOW_EX_STYLE::default(),
        CLASS,
        text::WINDOW_TITLE,
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        (CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT),
        None,
        0,
    )?;
    let dpi = ffi::dpi(window);
    let theme = match options.theme {
        Some(forced) => forced.theme(dpi),
        None => Theme::load(dpi),
    };
    let step = options.step.unwrap_or(Step::ALL[0]);
    let wizard = Wizard {
        window,
        graphics: Graphics::new().ok()?,
        surface: Surface::new(window),
        theme,
        forced_theme: options.theme,
        mica: false,
        animations: ffi::animations_enabled(),
        catalog,
        connect,
        model: None,
        loaded: Arc::new(Mutex::new(None)),
        loading: false,
        step,
        offline: options.offline,
        choices: Choices::default(),
        script: Script::default(),
        script_id: 0,
        demo_started: 0.0,
        today: Today::from_fields(now_fields()),
        fade: Tween::fixed(1.0),
        leaving: None,
        spotlight: step.spots().first().map(|spot| spot.path),
        caption: Tween::fixed(1.0),
        caption_leaving: None,
        spot_glows: Vec::new(),
        knobs: Vec::new(),
        hovers: Vec::new(),
        scroll: Scroller::default(),
        focus: Focus::Button(Button::Next),
        focus_visible: false,
        hover: None,
        pressed: None,
        menu: None,
        dragging: None,
        error: None,
        preview: None,
        overlay: None,
        overlay_source: None,
        overlay_cache: Vec::new(),
        generation: 0,
        started: options.started,
    };
    WIZARD.with(|cell| *cell.borrow_mut() = Some(wizard));
    uia::install(uia::Hooks {
        nodes: accessibility_nodes,
        act: accessibility_act,
    });
    with_wizard(|wizard| {
        wizard.apply_theme();
        wizard.fit_window();
        if let Some(path) = wizard.spotlight {
            wizard.spot_glows.push((path, Tween::fixed(1.0)));
        }
        if wizard.offline {
            wizard.choices = Choices::load(&Sample::new());
        } else {
            wizard.start_loading();
        }
        wizard.restart_demo();
    });
    // 最初の 1 枚を描いてから出す(白いコマを見せない)
    ffi::cloak(window, true);
    ffi::show_default(window);
    with_wizard(Wizard::paint);
    ffi::cloak(window, false);
    Some(window)
}

/// エンジンにつながずに開くときの値(見本の撮影)
struct Sample(serde_json::Value);

impl Sample {
    fn new() -> Self {
        Self(serde_json::json!({
            "punctuation": "toutenKuten",
            "brackets": "corner",
            "slash": "nakaguro",
            "yenKey": "alwaysBackslash",
            "spaceWidth": "fullwidth",
            "numberWidth": "halfwidth",
            "alphabetWidth": "halfwidth",
            "association": true,
            "calculation": true,
            "postalCodeConversion": true,
            "dateConversion": true,
            "theme": "automatic",
        }))
    }
}

impl wizard::Read for Sample {
    fn value(&self, path: &str) -> Option<&serde_json::Value> {
        self.0.get(path)
    }
}

/// 今の地方時の年・月・日・時・分・秒
fn now_fields() -> [u16; 6] {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_secs());
    let universal = demo::utc_fields(seconds);
    ffi::local_time(universal).unwrap_or(universal)
}

/// 候補の窓の色を設定の画面の色にする
fn ui_color(color: candidate_ui::theme::Color) -> Color {
    Color {
        red: color.red,
        green: color.green,
        blue: color.blue,
        alpha: color.alpha,
    }
}

/// 舞台の右下からにじませる色(標準のテーマの補正の色．macOS の systemPink と同じ)
fn secondary_glow() -> Color {
    tokens::THEMES
        .iter()
        .find(|(name, _)| *name == "standard")
        .map_or(
            Color::from(tokens::THEMES[0].1.correction),
            |(_, palette)| Color::from(palette.correction),
        )
}

/// 機能のアイコン(Segoe Fluent Icons．macOS の OnboardingSpotlight.symbol に近いもの)
fn spot_glyph(path: &str) -> &'static str {
    match path {
        "association" => "\u{E71B}",
        "calculation" => "\u{E8EF}",
        "postalCodeConversion" => "\u{E715}",
        "dateConversion" => "\u{E787}",
        "looseReadings" => "\u{E897}",
        "phoneticSpelling" => "\u{E767}",
        "handShiftCorrection" => "\u{E765}",
        "conversionMacros" => "\u{E70F}",
        "dynamicDictionary" => "\u{E81C}",
        "launcherCommands" => "\u{E768}",
        _ => "\u{E946}",
    }
}
/// 案内の行のアイコン(情報)
const INFO_GLYPH: &str = "\u{E946}";

fn mode_label(mode: Mode) -> &'static str {
    candidate_ui::strings::mode(match mode {
        Mode::Direct => ipc::InputMode::Direct,
        Mode::Japanese => ipc::InputMode::Japanese,
    })
}

fn mark_label(mark: Mark) -> String {
    match mark {
        Mark::Direct => mode_label(Mode::Direct).into(),
        Mark::Japanese => mode_label(Mode::Japanese).into(),
        Mark::Both => format!("{}{}", mode_label(Mode::Direct), mode_label(Mode::Japanese)),
    }
}

fn button_label(button: Button, step: Step) -> &'static str {
    match button {
        Button::Skip => text::SKIP,
        Button::Back => text::BACK,
        Button::Next if step.is_last() => text::FINISH,
        Button::Next => text::NEXT,
    }
}

fn inside(rect: &Rect, x: f32, y: f32) -> bool {
    x >= rect.x && x < rect.max_x() && y >= rect.y && y < rect.max_y()
}

/// 窓の座標の舞台(左)
fn stage_rect(height: f32) -> Rect {
    Rect::new(0.0, 0.0, board::STAGE_WIDTH, height)
}

/// 入力欄の模型(舞台の上 1/4 ほど．下に候補の窓を広げる場所を空ける)
fn field_rect() -> Rect {
    Rect::new(
        board::STAGE_PADDING,
        board::FIELD_TOP,
        board::STAGE_WIDTH - board::STAGE_PADDING * 2.0,
        board::FIELD_HEIGHT,
    )
}

/// 確定した文字の後ろ(組み立て中の文字の始まり)と，文字の終わりの x
fn text_positions(frame: &Frame, measure: &dyn Measure) -> (f32, f32) {
    let start = field_rect().x + board::CARD_PADDING;
    let committed = measure.width(&frame.committed, TextStyle::Demo);
    let marked: f32 = frame
        .marked
        .iter()
        .map(|segment| measure.width(&segment.text, TextStyle::Demo))
        .sum();
    (start + committed, start + committed + marked)
}

impl Wizard {
    fn now(&self) -> f64 {
        self.started.elapsed().as_secs_f64() * 1000.0
    }

    fn duration(&self, milliseconds: f32) -> f64 {
        if self.animations {
            f64::from(milliseconds)
        } else {
            0.0
        }
    }

    fn size(&self) -> (f32, f32) {
        let (width, height) = ffi::client_size(self.window);
        (self.theme.dip(width), self.theme.dip(height))
    }

    /// 中の大きさがトークンの大きさ(macOS の初期設定の窓と同じ)になるよう，窓の大きさを決める
    fn fit_window(&self) {
        let width = self.theme.px(board::WIDTH);
        let height = self.theme.px(board::HEIGHT);
        ffi::resize(self.window, width, height);
        let (client_width, client_height) = ffi::client_size(self.window);
        ffi::resize(
            self.window,
            width * 2 - client_width,
            height * 2 - client_height,
        );
    }

    fn apply_theme(&mut self) {
        ffi::set_dark_title_bar(self.window, self.theme.dark);
        self.mica = ffi::set_mica(self.window, !self.theme.high_contrast);
        self.overlay = None;
        self.overlay_source = None;
        self.overlay_cache.clear();
        if let Some(leaving) = &mut self.leaving {
            leaving.overlay = None;
        }
    }

    fn reload_theme(&mut self, dpi: u32) {
        self.theme = match self.forced_theme {
            Some(forced) => forced.theme(dpi),
            None => Theme::load(dpi),
        };
        self.animations = ffi::animations_enabled();
        self.apply_theme();
        ffi::invalidate(self.window);
    }

    // MARK: - 読み込み

    fn start_loading(&mut self) {
        if self.loading {
            return;
        }
        self.loading = true;
        let connect = self.connect;
        let catalog = self.catalog.clone();
        let loaded = Arc::clone(&self.loaded);
        let window = self.window.0 as isize;
        let spawned = std::thread::Builder::new()
            .name("setup-loader".into())
            .spawn(move || {
                let model = connect(&catalog.timing)
                    .and_then(|store| SettingsModel::load(store, &catalog).ok());
                if let Ok(mut slot) = loaded.lock() {
                    *slot = Some(model);
                }
                ffi::post(HWND(window as *mut _), WM_LOADED, 0, 0);
            });
        if spawned.is_err() {
            self.loading = false;
        }
    }

    fn finish_loading(&mut self) {
        self.loading = false;
        let Some(model) = self.loaded.lock().ok().and_then(|mut slot| slot.take()) else {
            return;
        };
        match model {
            Some(model) => {
                self.choices = Choices::load(&model);
                self.model = Some(model);
                ffi::kill_timer(self.window, RECONNECT_TIMER);
                self.restart_demo();
            }
            None => {
                let interval = self.catalog.timing.reconnect_interval().as_millis();
                ffi::set_timer(
                    self.window,
                    RECONNECT_TIMER,
                    u32::try_from(interval).unwrap_or(u32::MAX),
                );
            }
        }
        ffi::invalidate(self.window);
    }

    /// 選ぶものを出せるか(エンジンから値を読んだ)
    fn ready(&self) -> bool {
        self.model.is_some() || self.offline
    }

    // MARK: - ページ

    /// 台本を作り直して初めから見せる(ページ・見せている機能・選んだ値が変わったとき．macOS と同じ)
    fn restart_demo(&mut self) {
        self.script = demo::script(self.step, &self.choices, self.spotlight, self.today);
        self.script_id += 1;
        self.demo_started = self.now();
        ffi::kill_timer(self.window, DEMO_TIMER);
        ffi::invalidate(self.window);
    }

    /// 選んだ値をまとめてエンジンに書く(macOS と同じく，終えるときだけ書く)．書けなければ誤りを出して false
    fn save(&mut self) -> bool {
        let Some(model) = &mut self.model else {
            return true;
        };
        let changes = self.choices.changes(model);
        if changes.is_empty() {
            return true;
        }
        match model.set_all(&changes) {
            Ok(()) => {
                self.error = None;
                true
            }
            Err(_) => {
                self.error = Some(notes::SAVE_FAILED);
                ffi::invalidate(self.window);
                false
            }
        }
    }

    fn go(&mut self, step: Step) {
        let now = self.now();
        let frame = self.demo_frame(now).cloned();
        self.leaving = Some(Leaving {
            step: self.step,
            scroll: self.scroll.offset(now),
            frame,
            overlay: self.overlay.take(),
        });
        self.overlay_source = None;
        self.fade = Tween::new(0.0, 1.0, now, self.duration(pace::PAGE), EASE_IN_OUT);
        let old_step = self.step;
        self.step = step;
        self.scroll = Scroller::default();
        self.hover = None;
        self.menu = None;
        self.error = None;
        // ページを替えたら最初の機能を見せる(macOS と同じ)
        self.set_spotlight(step.spots().first().map(|spot| spot.path), old_step, now);
        self.focus = Focus::Button(Button::Next);
        self.restart_demo();
        // 収まらないページは，スクロールできることが分かるよう一度スクロールバーを出す
        let layout = self.layout(step);
        self.scroll
            .set_extent(layout.content_height, layout.viewport.height);
        if self.scroll.can_scroll() {
            self.scroll.scroll_by(0.0, now);
        }
        uia::focus_changed(self.window, self.focus_node());
    }

    /// 見せる機能を変え，説明の札を浮かべ直す
    fn set_spotlight(&mut self, path: Option<&'static str>, from: Step, now: f64) {
        if self.spotlight == path {
            return;
        }
        if let Some(old) = self.spotlight {
            self.caption_leaving = Some((
                old,
                from,
                // 消える札は短く薄くし，浮かんでくる札と重なって見える間を短くする
                Tween::new(
                    1.0,
                    0.0,
                    now,
                    self.duration(pace::PAGE * CAPTION_LEAVE),
                    Easing::DECELERATE,
                ),
            ));
            let duration = self.duration(pace::PAGE);
            if let Some((_, glow)) = self.spot_glows.iter_mut().find(|(spot, _)| *spot == old) {
                glow.retarget(0.0, now, duration, Easing::DECELERATE);
            }
        }
        self.spotlight = path;
        self.caption = Tween::new(
            0.0,
            1.0,
            now,
            self.duration(pace::PAGE * CAPTION_MOTION),
            SOFT,
        );
        if let Some(path) = path {
            let duration = self.duration(pace::PAGE);
            match self.spot_glows.iter_mut().find(|(spot, _)| *spot == path) {
                Some((_, glow)) => glow.retarget(1.0, now, duration, Easing::DECELERATE),
                None => self.spot_glows.push((
                    path,
                    Tween::new(0.0, 1.0, now, duration, Easing::DECELERATE),
                )),
            }
        }
    }

    fn spotlight_index(&mut self, index: usize) {
        let Some(spot) = self.step.spots().get(index) else {
            return;
        };
        if self.spotlight == Some(spot.path) {
            return;
        }
        let now = self.now();
        self.set_spotlight(Some(spot.path), self.step, now);
        self.restart_demo();
    }

    fn activate(&mut self, button: Button) {
        match button {
            Button::Back => {
                if let Some(previous) = self.step.previous() {
                    self.go(previous);
                }
            }
            Button::Next => match self.step.next() {
                Some(next) => self.go(next),
                None => {
                    if !self.ready() || !self.save() {
                        return;
                    }
                    if !self.offline {
                        ffi::set_setup_completed();
                    }
                    ffi::destroy(self.window);
                }
            },
            // あとで設定する: 保存せずに済んだことにする(macOS と同じ．設定の画面であとから変えられる)
            Button::Skip => {
                if !self.offline {
                    ffi::set_setup_completed();
                }
                ffi::destroy(self.window);
            }
        }
    }

    fn button_visible(&self, button: Button) -> bool {
        button != Button::Back || !self.step.is_first()
    }

    fn button_enabled(&self, button: Button) -> bool {
        // 最後のページは，値を読むまで終えられない
        button != Button::Next || !self.step.is_last() || self.ready()
    }

    fn select(&mut self, field: Field, value: &str) {
        if self.choices.value(field) != value {
            self.choices.select(field, value);
            self.restart_demo();
        }
    }

    fn select_theme(&mut self, index: usize) {
        if let Some(name) = wizard::THEME_ORDER.get(index) {
            if !self.choices.theme_selected(name) {
                self.choices.select(wizard::THEME, name);
                self.overlay_source = None;
                self.restart_demo();
            }
        }
    }

    fn toggle(&mut self, index: usize) {
        let Some(spot) = self.step.spots().get(index).copied() else {
            return;
        };
        let on = self.choices.is_on(spot.path);
        self.choices.set_toggle(spot.path, !on);
        let now = self.now();
        let duration = self.duration(motion::TOGGLE);
        let target = if on { 0.0 } else { 1.0 };
        match self.knobs.iter_mut().find(|(path, _)| *path == spot.path) {
            Some((_, knob)) => knob.retarget(target, now, duration, Easing::STANDARD),
            None => self.knobs.push((
                spot.path,
                Tween::new(1.0 - target, target, now, duration, Easing::STANDARD),
            )),
        }
        self.spotlight_index(index);
        self.restart_demo();
    }

    fn set_seconds(&mut self, field: Field, seconds: f64) {
        let range = self.catalog.ranges.live_conversion_delay;
        let step = self.catalog.seconds_step.max(0.01);
        let seconds = ((range.clamp(seconds) / step).round() * step * 10.0).round() / 10.0;
        if (self.choices.seconds(field) - seconds).abs() > f64::EPSILON {
            self.choices.set_seconds(field, seconds);
            self.restart_demo();
        }
    }

    fn open_menu(&mut self, item: usize) {
        let layout = self.layout(self.step);
        let offset = self.scroll.offset(self.now());
        let Some((picker, control)) = layout.parts.iter().find_map(|part| match part.kind {
            PartKind::Picker {
                item: candidate,
                picker,
                control,
            } if candidate == item => Some((picker, control)),
            _ => None,
        }) else {
            return;
        };
        let control = Rect::new(
            layout.viewport.x + control.x,
            layout.viewport.y + control.y - offset,
            control.width,
            control.height,
        );
        let current = self.choices.value(picker.field);
        let selected = picker
            .choices
            .iter()
            .position(|(value, _)| *value == current)
            .unwrap_or(0);
        let widest = picker
            .choices
            .iter()
            .map(|(value, label)| {
                self.graphics
                    .width(&menu_label(&picker, value, label), TextStyle::Body)
            })
            .fold(0.0, f32::max);
        let width = control
            .width
            // 項目の左の選んでいる印の分(group)も空ける
            .max(widest + size::FIELD_PADDING_X * 2.0 + size::FLYOUT_PADDING * 2.0 + space::GROUP);
        let height =
            picker.choices.len() as f32 * size::FLYOUT_ITEM_HEIGHT + size::FLYOUT_PADDING * 2.0;
        let (_, window_height) = self.size();
        // 選んでいる項目がボタンに重なる位置に開く(WinUI の ComboBox と同じ)．窓からははみ出さない
        let top = (control.y + (control.height - size::FLYOUT_ITEM_HEIGHT) / 2.0
            - size::FLYOUT_PADDING
            - selected as f32 * size::FLYOUT_ITEM_HEIGHT)
            .min(window_height - height - size::CONTROL_GAP)
            .max(size::CONTROL_GAP);
        let now = self.now();
        self.menu = Some(Menu {
            item,
            picker,
            highlighted: selected,
            rect: Rect::new(control.max_x() - width, top, width, height),
            opened: Tween::new(
                0.0,
                1.0,
                now,
                self.duration(motion::FLYOUT),
                Easing::DECELERATE,
            ),
        });
        self.focus = Focus::Picker(item);
        ffi::invalidate(self.window);
    }

    fn choose_menu(&mut self, index: usize) {
        let Some(menu) = self.menu.take() else {
            return;
        };
        if let Some((value, _)) = menu.picker.choices.get(index) {
            self.select(menu.picker.field, value);
        }
        ffi::invalidate(self.window);
    }

    fn press(&mut self, target: Target) {
        if !self.ready() && !matches!(target, Target::Button(_)) {
            return;
        }
        match target {
            Target::Card(item, index) => {
                self.focus = Focus::Cards(item);
                if let Some(Item::Cards(field, cards)) = self.step.items().get(item).copied() {
                    if let Some(card) = cards.get(index) {
                        self.select(field, card.value);
                    }
                }
            }
            Target::Theme(index) => {
                self.focus = Focus::Themes;
                self.select_theme(index);
            }
            Target::Picker(item) => self.open_menu(item),
            Target::Slider(item) => self.focus = Focus::Slider(item),
            Target::Spot(index) => {
                self.focus = Focus::Spot(index);
                self.spotlight_index(index);
            }
            Target::Switch(index) => {
                self.focus = Focus::Spot(index);
                self.toggle(index);
            }
            Target::MenuItem(index) => self.choose_menu(index),
            Target::Button(button) => {
                if self.button_visible(button) && self.button_enabled(button) {
                    self.activate(button);
                }
            }
        }
    }

    // MARK: - 置き場所

    /// step のページの置き場所
    fn layout(&self, step: Step) -> PageLayout {
        let (_, height) = self.size();
        let measure: &dyn Measure = &self.graphics;
        let x = board::STAGE_WIDTH + board::PADDING;
        let width = board::WIDTH - board::STAGE_WIDTH - board::PADDING * 2.0;
        let gap = board::CARD_GAP;
        let mut y = board::PADDING;
        let counter = Rect::new(x, y, width, COUNTER_HEIGHT);
        y += COUNTER_HEIGHT + space::STACK;
        let title_height = measure.wrapped_height(step.title(), TextStyle::Title, width);
        let title = Rect::new(x, y, width, title_height);
        y += title_height + space::STACK;
        // 添える 1 行の無いページは，見出しのすぐ下から選ぶものを並べる
        let detail_height = step.detail().map_or(0.0, |detail| {
            measure.wrapped_height(detail, TextStyle::Body, width)
        });
        let detail = Rect::new(x, y, width, detail_height);
        y += detail_height + gap;
        let footer = height - board::PADDING - size::CONTROL_HEIGHT;
        let viewport = Rect::new(x, y, width, (footer - gap - y).max(0.0));
        let (parts, content_height) = self.parts(step, width);
        PageLayout {
            counter,
            title,
            detail,
            viewport,
            parts,
            content_height,
        }
    }

    /// ページに並べるものの置き場所(content の座標)と，中身の高さ
    fn parts(&self, step: Step, width: f32) -> (Vec<Part>, f32) {
        let measure: &dyn Measure = &self.graphics;
        let gap = board::CARD_GAP;
        let padding = board::CARD_PADDING;
        let mut parts = Vec::new();
        // カードの縁の線がスクロールの端で切れないように空ける(macOS と同じ)
        let mut y = space::INSET;
        let detail_height = |detail: &str, inner: f32| {
            space::STACK + measure.wrapped_height(detail, TextStyle::Caption, inner)
        };
        for (item_index, item) in step.items().into_iter().enumerate() {
            if item_index > 0 {
                y += gap;
            }
            match item {
                Item::Cards(field, cards) => {
                    let inner = width - padding * 2.0 - CHECK - gap;
                    for (index, card) in cards.iter().enumerate() {
                        if index > 0 {
                            y += gap;
                        }
                        let height = padding * 2.0
                            + LINE
                            + card
                                .detail
                                .map_or(0.0, |detail| detail_height(detail, inner));
                        parts.push(Part {
                            kind: PartKind::Card {
                                item: item_index,
                                index,
                                field,
                                card: *card,
                            },
                            rect: Rect::new(0.0, y, width, height),
                        });
                        y += height;
                    }
                }
                Item::Info(infos) => {
                    for (index, info) in infos.iter().enumerate() {
                        if index > 0 {
                            y += gap;
                        }
                        let height = padding * 2.0 + LINE.max(board::INFO_SYMBOL_WIDTH);
                        parts.push(Part {
                            kind: PartKind::Info(index, *info),
                            rect: Rect::new(0.0, y, width, height),
                        });
                        y += height;
                    }
                }
                Item::Themes => {
                    let columns = 3;
                    let tile_width = (width - gap * (columns - 1) as f32) / columns as f32;
                    let tile_height = padding * 2.0 + SWATCH_HEIGHT + space::STACK + LINE;
                    for index in 0..wizard::THEME_ORDER.len() {
                        parts.push(Part {
                            kind: PartKind::Theme(index),
                            rect: Rect::new(
                                (index % columns) as f32 * (tile_width + gap),
                                y + (index / columns) as f32 * (tile_height + gap),
                                tile_width,
                                tile_height,
                            ),
                        });
                    }
                    let rows = wizard::THEME_ORDER.len().div_ceil(columns);
                    y += rows as f32 * tile_height + (rows - 1) as f32 * gap;
                }
                Item::Seconds { title, field } => {
                    let label = measure.width(title, TextStyle::Body);
                    let track_x = label + space::GROUP;
                    let track = Rect::new(
                        track_x,
                        y,
                        (width - size::SECONDS_LABEL_WIDTH - gap - track_x).max(0.0),
                        size::CONTROL_HEIGHT,
                    );
                    parts.push(Part {
                        kind: PartKind::Slider {
                            item: item_index,
                            title,
                            field,
                            track,
                        },
                        rect: Rect::new(0.0, y, width, size::CONTROL_HEIGHT),
                    });
                    y += size::CONTROL_HEIGHT;
                }
                Item::Picker(picker) => {
                    let widest = picker
                        .choices
                        .iter()
                        .map(|(value, label)| {
                            measure.width(&menu_label(&picker, value, label), TextStyle::Body)
                        })
                        .fold(0.0, f32::max);
                    // ドロップダウンの並び(左の余白・名前・名前と印のあいだ・山形の印・右の余白)に，
                    // 測った幅と描いた幅の差の見込み(inset)を足す
                    let control_width = (size::FIELD_PADDING_X
                        + widest
                        + size::FIELD_PADDING_X
                        + size::CHEVRON_SIZE
                        + size::FIELD_PADDING_X
                        + space::INSET)
                        .ceil();
                    let (height, inset) = if picker.framed {
                        (size::CONTROL_HEIGHT + padding, padding)
                    } else {
                        (size::CONTROL_HEIGHT, 0.0)
                    };
                    let control = Rect::new(
                        width - inset - control_width,
                        y + (height - size::CONTROL_HEIGHT) / 2.0,
                        control_width,
                        size::CONTROL_HEIGHT,
                    );
                    parts.push(Part {
                        kind: PartKind::Picker {
                            item: item_index,
                            picker,
                            control,
                        },
                        rect: Rect::new(0.0, y, width, height),
                    });
                    y += height;
                }
                Item::Spotlight(spots) => {
                    let height = SPOT_PADDING_Y * 2.0 + LINE;
                    for (index, spot) in spots.iter().enumerate() {
                        if index > 0 {
                            y += gap;
                        }
                        let switch = Rect::new(
                            width - padding - size::SWITCH_WIDTH,
                            y,
                            size::SWITCH_WIDTH,
                            height,
                        );
                        parts.push(Part {
                            kind: PartKind::Spot {
                                index,
                                spot: *spot,
                                switch,
                            },
                            rect: Rect::new(0.0, y, width, height),
                        });
                        y += height;
                    }
                    if step.is_last() {
                        y += gap;
                        let inner = width - size::CHEVRON_SIZE - space::INLINE;
                        let note = measure
                            .wrapped_height(notes::TASKBAR_NOTE, TextStyle::Caption, inner)
                            .max(size::NOTE_LINE_HEIGHT);
                        parts.push(Part {
                            kind: PartKind::TaskbarNote,
                            rect: Rect::new(0.0, y, width, note),
                        });
                        y += note;
                    }
                }
            }
        }
        (parts, y + space::INSET)
    }

    /// 足元のボタンの置き場所(見えるものだけ)
    fn buttons(&self, step: Step) -> Vec<(Button, Rect)> {
        let (width, height) = self.size();
        let y = height - board::PADDING - size::CONTROL_HEIGHT;
        let mut right = width - board::PADDING;
        let mut placed = Vec::new();
        for button in BUTTONS.into_iter().rev() {
            if button == Button::Back && step.is_first() {
                continue;
            }
            let label = self
                .graphics
                .width(button_label(button, step), TextStyle::Body);
            // 「あとで設定する」は文字だけ(macOS の plain)．ほかは文字に余白を足し，短い名前は幅をそろえる
            let button_width = if button == Button::Skip {
                label.ceil()
            } else {
                (label + size::BUTTON_PADDING_X * 2.0)
                    .max(BUTTON_MIN_WIDTH)
                    .ceil()
            };
            right -= button_width;
            placed.push((
                button,
                Rect::new(right, y, button_width, size::CONTROL_HEIGHT),
            ));
            right -= board::CARD_GAP;
        }
        placed.reverse();
        placed
    }

    /// part を窓の座標にする
    fn place(viewport: &Rect, rect: Rect, offset: f32) -> Rect {
        Rect::new(
            viewport.x + rect.x,
            viewport.y + rect.y - offset,
            rect.width,
            rect.height,
        )
    }

    fn target_at(&self, x: f32, y: f32) -> Option<Target> {
        if let Some(menu) = &self.menu {
            if !inside(&menu.rect, x, y) {
                return None;
            }
            let index =
                ((y - menu.rect.y - size::FLYOUT_PADDING) / size::FLYOUT_ITEM_HEIGHT).floor();
            return (index >= 0.0 && (index as usize) < menu.picker.choices.len())
                .then_some(Target::MenuItem(index as usize));
        }
        for (button, rect) in self.buttons(self.step) {
            if inside(&rect, x, y) {
                return Some(Target::Button(button));
            }
        }
        if !self.ready() {
            return None;
        }
        let layout = self.layout(self.step);
        if !inside(&layout.viewport, x, y) {
            return None;
        }
        let offset = self.scroll.offset(self.now());
        for part in &layout.parts {
            let rect = Self::place(&layout.viewport, part.rect, offset);
            if !inside(&rect, x, y) {
                continue;
            }
            return match part.kind {
                PartKind::Card { item, index, .. } => Some(Target::Card(item, index)),
                PartKind::Theme(index) => Some(Target::Theme(index)),
                PartKind::Picker { item, control, .. } => {
                    inside(&Self::place(&layout.viewport, control, offset), x, y)
                        .then_some(Target::Picker(item))
                }
                PartKind::Slider { item, track, .. } => {
                    let track = Self::place(&layout.viewport, track, offset);
                    let hit = Rect::new(
                        track.x - THUMB / 2.0,
                        track.y,
                        track.width + THUMB,
                        track.height,
                    );
                    (inside(&hit, x, y) && self.choices.live()).then_some(Target::Slider(item))
                }
                PartKind::Spot { index, switch, .. } => {
                    let switch = Self::place(&layout.viewport, switch, offset);
                    let hit = Rect::new(
                        switch.x - size::CONTROL_GAP,
                        switch.y,
                        switch.width + size::CONTROL_GAP * 2.0,
                        switch.height,
                    );
                    Some(if inside(&hit, x, y) {
                        Target::Switch(index)
                    } else {
                        Target::Spot(index)
                    })
                }
                PartKind::Info(..) | PartKind::TaskbarNote => None,
            };
        }
        None
    }

    // MARK: - 実演

    /// 実演の今のコマ．動きを減らす設定なら最後のコマ
    fn demo_frame(&self, now: f64) -> Option<&Frame> {
        self.demo_position(now).map_or_else(
            || self.script.last(),
            |position| self.script.frame(position.index),
        )
    }

    fn demo_position(&self, now: f64) -> Option<demo::Position> {
        if !self.animations {
            return None;
        }
        self.script.position(now - self.demo_started)
    }

    /// 候補の窓を描くテーマ
    fn candidate_theme(&self) -> candidate_ui::theme::ResolvedTheme {
        let look = candidate_ui::theme::SystemLook {
            dark: self.theme.dark,
            accent: None,
            increase_contrast: self.theme.high_contrast,
            backdrop: false,
        };
        candidate_ui::theme::ResolvedTheme::resolve(self.choices.theme(), None, &look)
    }

    fn font_size(&self) -> f32 {
        self.choices
            .font_size()
            .map_or(tokens::size::candidate::FONT_SIZE, |size| size as f32)
    }

    /// 今のコマに合わせて，舞台に重ねる候補の窓とモードの札の画像を作る
    fn update_overlay(&mut self, now: f64) {
        let index = self
            .demo_position(now)
            .map_or(self.script.len().saturating_sub(1), |position| {
                position.index
            });
        if self.overlay_source == Some((self.script_id, index)) {
            return;
        }
        self.overlay_source = Some((self.script_id, index));
        let Some(frame) = self.script.frame(index).cloned() else {
            self.overlay = None;
            return;
        };
        self.overlay = self.make_overlay(&frame);
    }

    fn make_overlay(&mut self, frame: &Frame) -> Option<Overlay> {
        if frame.panel.is_none() && frame.mode.is_none() {
            return None;
        }
        if self.preview.is_none() {
            self.preview = Preview::new().ok();
        }
        let theme = self.candidate_theme();
        let font_size = self.font_size();
        let preview = self.preview.as_ref()?;
        let (marked_start, end) = text_positions(frame, &self.graphics);
        let padding = board::STAGE_PADDING;
        let top = field_rect().max_y() + board::DEMO_GAP;
        let (_, height) = self.size();
        let available = (board::STAGE_WIDTH - padding * 2.0, height - top - padding);
        let mode = frame.mode.map(mode_label);
        let mut layers: Vec<(Shown, Rect)> = Vec::new();
        if let Some(panel) = &frame.panel {
            let shown = match panel {
                Panel::Lattice(map) => Shown::Branch(map),
                Panel::List(list) => Shown::List(list),
                Panel::Note(note) => Shown::Note(note),
            };
            let (width, height) = preview.size(&theme, font_size, shown).ok()?;
            if width <= 0.0 || height <= 0.0 {
                return None;
            }
            let fit = (available.0 / width).min(available.1 / height).min(1.0);
            let (width, height) = ((width * fit).round(), (height * fit).round());
            let x = (marked_start - board::CARD_PADDING)
                .max(padding)
                .min(board::STAGE_WIDTH - padding - width);
            layers.push((shown, Rect::new(x.round(), top, width, height)));
        }
        if let Some(label) = mode {
            let shown = Shown::Mode(label);
            let (width, height) = preview.size(&theme, font_size, shown).ok()?;
            let x = (end + space::GROUP).min(board::STAGE_WIDTH - padding - width);
            layers.push((
                shown,
                Rect::new(x.round(), top, width.ceil(), height.ceil()),
            ));
        }
        let scale = self.theme.dpi as f32 / ffi::BASE_DPI as f32;
        let left = layers
            .iter()
            .map(|(_, rect)| rect.x)
            .fold(f32::MAX, f32::min);
        let origin = ((left * scale).floor(), (top * scale).floor());
        let pixel_rects: Vec<(i32, i32, i32, i32)> = layers
            .iter()
            .map(|(_, rect)| {
                (
                    ((rect.x * scale).round() - origin.0) as i32,
                    ((rect.y * scale).round() - origin.1) as i32,
                    (rect.width * scale).ceil() as i32,
                    (rect.height * scale).ceil() as i32,
                )
            })
            .collect();
        let width = pixel_rects
            .iter()
            .map(|(x, _, width, _)| x + width)
            .max()
            .unwrap_or(0);
        let height = pixel_rects
            .iter()
            .map(|(_, y, _, height)| y + height)
            .max()
            .unwrap_or(0);
        let width = u32::try_from(width).ok()?;
        let height = u32::try_from(height).ok()?;
        // 窓の中身そのものを鍵にする(台本を始め直しても，同じ窓なら描き直さない)
        let content = serde_json::json!({
            "panel": match &frame.panel {
                Some(Panel::Lattice(map)) => serde_json::to_value(map).ok(),
                Some(Panel::List(list)) => serde_json::to_value(list).ok(),
                Some(Panel::Note(note)) => serde_json::to_value(note).ok(),
                None => None,
            },
            "mode": mode,
            "rects": pixel_rects,
        });
        let key = format!(
            "{}|{}|{}|{}|{font_size}|{origin:?}|{content}",
            self.choices.theme(),
            self.theme.dark,
            self.theme.high_contrast,
            self.theme.dpi
        );
        self.generation += 1;
        let generation = self.generation;
        let (x, y) = (origin.0 / scale, origin.1 / scale);
        if let Some(position) = self
            .overlay_cache
            .iter()
            .position(|(cached, ..)| *cached == key)
        {
            let entry = self.overlay_cache.remove(position);
            let overlay = Overlay {
                pixels: PreviewPixels {
                    generation,
                    width: entry.1,
                    height: entry.2,
                    pixels: entry.3.clone(),
                },
                x: entry.4,
                y: entry.5,
            };
            self.overlay_cache.push(entry);
            return Some(overlay);
        }
        let painted: Vec<Layer> = layers
            .iter()
            .zip(&pixel_rects)
            .map(|((shown, _), rect)| Layer {
                shown: *shown,
                rect: *rect,
            })
            .collect();
        let look = LayerLook {
            theme: &theme,
            font_size,
            dark: self.theme.dark,
            scale,
        };
        let pixels = d2d::render_layers(preview, width, height, &look, &painted)?;
        if self.overlay_cache.len() >= OVERLAY_CACHE {
            self.overlay_cache.remove(0);
        }
        self.overlay_cache
            .push((key.clone(), width, height, pixels.clone(), x, y));
        Some(Overlay {
            pixels: PreviewPixels {
                generation,
                width,
                height,
                pixels,
            },
            x,
            y,
        })
    }

    // MARK: - 描く

    fn hover_value(&self, target: Target, now: f64) -> f32 {
        self.hovers
            .iter()
            .find(|(candidate, _)| *candidate == target)
            .map_or(0.0, |(_, tween)| tween.value(now))
    }

    fn set_hover(&mut self, hover: Option<Target>) {
        if hover == self.hover {
            return;
        }
        let now = self.now();
        let duration = self.duration(motion::HOVER);
        if let Some(old) = self.hover {
            if let Some((_, tween)) = self.hovers.iter_mut().find(|(target, _)| *target == old) {
                tween.retarget(0.0, now, duration, Easing::LINEAR);
            }
        }
        if let Some(new) = hover {
            match self.hovers.iter_mut().find(|(target, _)| *target == new) {
                Some((_, tween)) => tween.retarget(1.0, now, duration, Easing::LINEAR),
                None => self
                    .hovers
                    .push((new, Tween::new(0.0, 1.0, now, duration, Easing::LINEAR))),
            }
        }
        self.hovers.retain(|(target, tween)| {
            Some(*target) == hover || tween.running(now) || tween.value(now) > 0.0
        });
        self.hover = hover;
        ffi::invalidate(self.window);
    }

    fn paint(&mut self) {
        let now = self.now();
        self.update_overlay(now);
        if self.leaving.is_some() && !self.fade.running(now) {
            self.leaving = None;
        }
        if let Some((_, _, tween)) = &self.caption_leaving {
            if !tween.running(now) {
                self.caption_leaving = None;
            }
        }
        let layout = self.layout(self.step);
        self.scroll
            .set_extent(layout.content_height, layout.viewport.height);
        let leaving_layout = self
            .leaving
            .as_ref()
            .map(|leaving| self.layout(leaving.step));
        let theme = self.theme;
        let clear = if self.mica {
            Color::from(theme.palette.background).with_alpha(0.0)
        } else {
            Color::from(theme.palette.background)
        };
        let size = ffi::client_size(self.window);
        // 描き先は描くあいだだけ借りる(ほかの状態は描く関数が読む)
        let mut surface = std::mem::replace(&mut self.surface, Surface::new(self.window));
        let previews = [
            self.overlay.as_ref().map(|overlay| &overlay.pixels),
            self.leaving
                .as_ref()
                .and_then(|leaving| leaving.overlay.as_ref())
                .map(|overlay| &overlay.pixels),
        ];
        let state = PaintState {
            wizard: self,
            layout: &layout,
            leaving: leaving_layout.as_ref(),
            now,
        };
        let _ = surface.draw_layers(
            &self.graphics,
            size,
            theme.dpi,
            clear,
            &previews,
            |canvas| {
                paint_window(canvas, &state);
            },
        );
        self.surface = surface;
        self.schedule(now);
    }

    /// 次に描く時を決める．動いているあいだは画面の更新に合わせ，止まっているコマでは次のコマまで時計で待つ
    fn schedule(&self, now: f64) {
        let tweens = self.fade.running(now)
            || self.caption.running(now)
            || self
                .caption_leaving
                .as_ref()
                .is_some_and(|(_, _, tween)| tween.running(now))
            || self.knobs.iter().any(|(_, knob)| knob.running(now))
            || self.spot_glows.iter().any(|(_, glow)| glow.running(now))
            || self.hovers.iter().any(|(_, hover)| hover.running(now))
            || self
                .menu
                .as_ref()
                .is_some_and(|menu| menu.opened.running(now))
            || self.scroll.animating(now);
        let loading = !self.ready();
        if tweens || loading {
            ffi::wait_for_compositor();
            ffi::invalidate(self.window);
            return;
        }
        if let Some(position) = self.demo_position(now) {
            let wait = position.remaining.ceil().max(1.0) as u32;
            ffi::set_timer(self.window, DEMO_TIMER, wait);
        }
    }

    // MARK: - キーボード

    fn focusables(&self) -> Vec<Focus> {
        let mut focusables = Vec::new();
        if self.ready() {
            for (index, item) in self.step.items().into_iter().enumerate() {
                match item {
                    Item::Cards(..) => focusables.push(Focus::Cards(index)),
                    Item::Themes => focusables.push(Focus::Themes),
                    Item::Picker(_) => focusables.push(Focus::Picker(index)),
                    Item::Seconds { .. } if self.choices.live() => {
                        focusables.push(Focus::Slider(index));
                    }
                    Item::Spotlight(spots) => {
                        focusables.extend((0..spots.len()).map(Focus::Spot));
                    }
                    Item::Info(_) | Item::Seconds { .. } => {}
                }
            }
        }
        focusables.extend(
            BUTTONS
                .into_iter()
                .filter(|button| self.button_visible(*button) && self.button_enabled(*button))
                .map(Focus::Button),
        );
        focusables
    }

    /// キーボードで選んだものが見えるようにスクロールする
    fn reveal_focus(&mut self) {
        let layout = self.layout(self.step);
        let found = layout
            .parts
            .iter()
            .filter(|part| match (self.focus, part.kind) {
                (
                    Focus::Cards(item),
                    PartKind::Card {
                        item: candidate, ..
                    },
                ) => item == candidate,
                (Focus::Themes, PartKind::Theme(_)) => true,
                (
                    Focus::Picker(item),
                    PartKind::Picker {
                        item: candidate, ..
                    },
                ) => item == candidate,
                (
                    Focus::Slider(item),
                    PartKind::Slider {
                        item: candidate, ..
                    },
                ) => item == candidate,
                (
                    Focus::Spot(index),
                    PartKind::Spot {
                        index: candidate, ..
                    },
                ) => index == candidate,
                _ => false,
            });
        let (top, bottom) = found.fold((f32::MAX, f32::MIN), |(top, bottom), part| {
            (top.min(part.rect.y), bottom.max(part.rect.max_y()))
        });
        if top <= bottom {
            let now = self.now();
            self.scroll
                .set_extent(layout.content_height, layout.viewport.height);
            self.scroll.reveal(top, bottom, now);
        }
    }

    /// 選んでいるものの矢印のキー
    fn arrow(&mut self, key: u16) {
        let forward = key == VK_DOWN.0 || key == VK_RIGHT.0;
        let vertical = key == VK_DOWN.0 || key == VK_UP.0;
        let step_by = |current: usize, count: usize, amount: usize| {
            if forward {
                (current + amount).min(count.saturating_sub(1))
            } else {
                current.saturating_sub(amount)
            }
        };
        match self.focus {
            Focus::Cards(item) => {
                if let Some(Item::Cards(field, cards)) = self.step.items().get(item).copied() {
                    let current = self.choices.value(field);
                    let position = cards
                        .iter()
                        .position(|card| card.value == current)
                        .unwrap_or(0);
                    if let Some(card) = cards.get(step_by(position, cards.len(), 1)) {
                        self.select(field, card.value);
                    }
                }
            }
            Focus::Themes => {
                let count = wizard::THEME_ORDER.len();
                let position = wizard::THEME_ORDER
                    .iter()
                    .position(|name| self.choices.theme_selected(name))
                    .unwrap_or(0);
                self.select_theme(step_by(position, count, if vertical { 3 } else { 1 }));
            }
            Focus::Picker(item) => {
                if let Some(Item::Picker(picker)) = self.step.items().get(item).copied() {
                    let current = self.choices.value(picker.field);
                    let position = picker
                        .choices
                        .iter()
                        .position(|(value, _)| *value == current)
                        .unwrap_or(0);
                    if let Some((value, _)) =
                        picker
                            .choices
                            .get(step_by(position, picker.choices.len(), 1))
                    {
                        self.select(picker.field, value);
                    }
                }
            }
            Focus::Slider(_) => {
                let step = self.catalog.seconds_step;
                let current = self.choices.seconds(wizard::LIVE_DELAY);
                let next = if forward || key == VK_UP.0 {
                    current + step
                } else {
                    current - step
                };
                self.set_seconds(wizard::LIVE_DELAY, next);
            }
            Focus::Spot(index) => {
                if vertical {
                    let next = step_by(index, self.step.spots().len(), 1);
                    self.focus = Focus::Spot(next);
                    self.spotlight_index(next);
                }
            }
            Focus::Button(_) => {
                let buttons: Vec<Button> = BUTTONS
                    .into_iter()
                    .filter(|button| self.button_visible(*button) && self.button_enabled(*button))
                    .collect();
                if let Some(position) = buttons
                    .iter()
                    .position(|button| Focus::Button(*button) == self.focus)
                {
                    self.focus = Focus::Button(buttons[step_by(position, buttons.len(), 1)]);
                }
            }
        }
    }

    fn menu_key(&mut self, key: u16) -> bool {
        let Some(menu) = &mut self.menu else {
            return false;
        };
        let count = menu.picker.choices.len();
        match key {
            key if key == VK_UP.0 => menu.highlighted = menu.highlighted.saturating_sub(1),
            key if key == VK_DOWN.0 => {
                menu.highlighted = (menu.highlighted + 1).min(count.saturating_sub(1));
            }
            key if key == VK_HOME.0 => menu.highlighted = 0,
            key if key == VK_END.0 => menu.highlighted = count.saturating_sub(1),
            key if key == VK_RETURN.0 || key == VK_SPACE.0 => {
                let index = menu.highlighted;
                self.choose_menu(index);
            }
            key if key == VK_ESCAPE.0 || key == VK_TAB.0 || key == VK_F4.0 => self.menu = None,
            _ => return false,
        }
        true
    }

    fn key(&mut self, key: u16) -> bool {
        if self.menu.is_some() {
            if self.menu_key(key) {
                self.focus_visible = true;
                uia::focus_changed(self.window, self.focus_node());
                ffi::invalidate(self.window);
            }
            return true;
        }
        match key {
            key if key == VK_TAB.0 => {
                let (_, shift) = ffi::modifiers();
                let focusables = self.focusables();
                let current = focusables.iter().position(|focus| *focus == self.focus);
                if let Some(next) = crate::ui::cycle(current, focusables.len(), shift) {
                    self.focus = focusables[next];
                }
                if let Focus::Spot(index) = self.focus {
                    self.spotlight_index(index);
                }
                self.reveal_focus();
            }
            key if [VK_UP.0, VK_DOWN.0, VK_LEFT.0, VK_RIGHT.0].contains(&key) => {
                self.arrow(key);
                self.reveal_focus();
            }
            key if key == VK_F4.0 => {
                if let Focus::Picker(item) = self.focus {
                    self.open_menu(item);
                }
            }
            key if key == VK_SPACE.0 => match self.focus {
                Focus::Spot(index) => self.toggle(index),
                Focus::Picker(item) => self.open_menu(item),
                Focus::Button(button) => self.activate(button),
                _ => {}
            },
            key if key == VK_RETURN.0 => match self.focus {
                Focus::Button(button) => self.activate(button),
                Focus::Picker(item) => self.open_menu(item),
                // ほかの上で Enter なら既定のボタン(次へ・はじめる)
                _ => self.activate(Button::Next),
            },
            // Esc は閉じるボタンと同じ(済んだことにはしない)
            key if key == VK_ESCAPE.0 => ffi::destroy(self.window),
            _ => return false,
        }
        if WIZARD_ALIVE.with(|alive| alive.get()) {
            self.focus_visible = true;
            uia::focus_changed(self.window, self.focus_node());
            ffi::invalidate(self.window);
        }
        true
    }

    // MARK: - ポインター

    fn point(&self, lparam: LPARAM) -> (f32, f32) {
        let x = (lparam.0 & 0xffff) as i16 as i32;
        let y = ((lparam.0 >> 16) & 0xffff) as i16 as i32;
        (self.theme.dip(x), self.theme.dip(y))
    }

    /// スライダーの x の値(秒)
    fn slider_value(&self, x: f32) -> Option<f64> {
        let layout = self.layout(self.step);
        let offset = self.scroll.offset(self.now());
        layout.parts.iter().find_map(|part| match part.kind {
            PartKind::Slider { track, .. } => {
                let track = Self::place(&layout.viewport, track, offset);
                let range = self.catalog.ranges.live_conversion_delay;
                let ratio = f64::from(
                    ((x - track.x - THUMB / 2.0) / (track.width - THUMB)).clamp(0.0, 1.0),
                );
                Some(range.lower() + (range.upper() - range.lower()) * ratio)
            }
            _ => None,
        })
    }

    fn snapped(&self, seconds: f64) -> f64 {
        let range = self.catalog.ranges.live_conversion_delay;
        let step = self.catalog.seconds_step.max(0.01);
        (range.clamp(seconds) / step).round() * step
    }

    fn mouse_move(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        if self.dragging.is_some() {
            self.dragging = self.slider_value(x).map(|value| self.snapped(value));
            ffi::invalidate(self.window);
            return;
        }
        let hover = self.target_at(x, y);
        match hover {
            Some(Target::Spot(index) | Target::Switch(index)) => self.spotlight_index(index),
            Some(Target::MenuItem(index)) => {
                if let Some(menu) = &mut self.menu {
                    menu.highlighted = index;
                }
            }
            _ => {}
        }
        if hover != self.hover {
            ffi::track_leave(self.window);
            self.set_hover(hover);
        }
    }

    fn mouse_down(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        let target = self.target_at(x, y);
        // メニューの外を押したら閉じるだけにする
        if self.menu.is_some() && target.is_none() {
            self.menu = None;
            ffi::invalidate(self.window);
            return;
        }
        self.pressed = target;
        self.focus_visible = false;
        if let Some(Target::Slider(item)) = target {
            self.focus = Focus::Slider(item);
            self.dragging = self.slider_value(x).map(|value| self.snapped(value));
        }
        if self.pressed.is_some() {
            ffi::capture(self.window);
        }
        ffi::invalidate(self.window);
    }

    fn mouse_up(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        let pressed = self.pressed.take();
        ffi::release_capture();
        if let Some(seconds) = self.dragging.take() {
            self.set_seconds(wizard::LIVE_DELAY, seconds);
        } else if let Some(target) = pressed.filter(|target| self.target_at(x, y) == Some(*target))
        {
            self.press(target);
        }
        if WIZARD_ALIVE.with(|alive| alive.get()) {
            ffi::invalidate(self.window);
        }
    }

    fn wheel(&mut self, wparam: WPARAM, lparam: LPARAM) {
        if self.menu.is_some() {
            return;
        }
        let delta = ((wparam.0 >> 16) & 0xffff) as u16 as i16 as i32;
        // ホイールの位置は画面の座標
        let screen_x = (lparam.0 & 0xffff) as i16 as i32;
        let screen_y = ((lparam.0 >> 16) & 0xffff) as i16 as i32;
        let (client_x, _) = ffi::to_client(self.window, screen_x, screen_y);
        let _ = screen_y;
        if self.theme.dip(client_x) < board::STAGE_WIDTH {
            return;
        }
        let now = self.now();
        let layout = self.layout(self.step);
        self.scroll
            .set_extent(layout.content_height, layout.viewport.height);
        self.scroll
            .scroll_by(scroll::wheel_delta(delta, WHEEL_DELTA as i32), now);
        ffi::invalidate(self.window);
    }

    // MARK: - 読み上げ

    fn focus_node(&self) -> i32 {
        if let Some(menu) = &self.menu {
            return NODE_MENU + menu.highlighted as i32;
        }
        match self.focus {
            Focus::Cards(item) => {
                let selected = match self.step.items().get(item) {
                    Some(Item::Cards(field, cards)) => {
                        let current = self.choices.value(*field);
                        cards
                            .iter()
                            .position(|card| card.value == current)
                            .unwrap_or(0)
                    }
                    _ => 0,
                };
                NODE_CARD + (item * 100 + selected) as i32
            }
            Focus::Themes => {
                NODE_THEME
                    + wizard::THEME_ORDER
                        .iter()
                        .position(|name| self.choices.theme_selected(name))
                        .unwrap_or(0) as i32
            }
            Focus::Picker(item) => NODE_PICKER + item as i32,
            Focus::Slider(item) => NODE_SLIDER + item as i32,
            Focus::Spot(index) => NODE_SPOT + index as i32,
            Focus::Button(button) => {
                NODE_BUTTON + BUTTONS.iter().position(|b| *b == button).unwrap_or(0) as i32
            }
        }
    }

    fn nodes(&self) -> Vec<uia::Node> {
        let layout = self.layout(self.step);
        let offset = self.scroll.offset(self.now());
        let focused = self.focus_node();
        let pixels = |rect: &Rect| {
            (
                self.theme.px(rect.x),
                self.theme.px(rect.y),
                self.theme.px(rect.width),
                self.theme.px(rect.height),
            )
        };
        let node = |id: i32, role: uia::Role, name: String, rect: &Rect| uia::Node {
            id,
            role,
            name,
            rect: pixels(rect),
            enabled: true,
            focused: id == focused,
            toggled: None,
            expanded: None,
            value: None,
            selected: None,
            host: None,
        };
        let mut nodes = Vec::new();
        if self.ready() {
            for part in &layout.parts {
                let rect = Self::place(&layout.viewport, part.rect, offset);
                match part.kind {
                    PartKind::Card {
                        item,
                        index,
                        field,
                        card,
                    } => {
                        let mut name = card.title.to_string();
                        if card.recommended {
                            name = format!("{name} {}", text::RECOMMENDED);
                        }
                        if let Some(detail) = card.detail {
                            name = format!("{name} {detail}");
                        }
                        nodes.push(uia::Node {
                            selected: Some(self.choices.value(field) == card.value),
                            ..node(
                                NODE_CARD + (item * 100 + index) as i32,
                                uia::Role::ListItem,
                                name,
                                &rect,
                            )
                        });
                    }
                    PartKind::Info(index, info) => nodes.push(node(
                        NODE_INFO + index as i32,
                        uia::Role::Document,
                        info.title.to_string(),
                        &rect,
                    )),
                    PartKind::Theme(index) => {
                        let name = wizard::THEME_ORDER[index];
                        let mut label = wizard::theme_label(name).to_string();
                        if index == 0 {
                            label = format!("{label} {}", text::RECOMMENDED);
                        }
                        nodes.push(uia::Node {
                            selected: Some(self.choices.theme_selected(name)),
                            ..node(NODE_THEME + index as i32, uia::Role::ListItem, label, &rect)
                        });
                    }
                    PartKind::Picker {
                        item,
                        picker,
                        control,
                    } => {
                        let current = self.choices.value(picker.field);
                        let value = picker
                            .choices
                            .iter()
                            .find(|(value, _)| *value == current)
                            .map(|(value, label)| menu_label(&picker, value, label));
                        nodes.push(uia::Node {
                            expanded: Some(
                                self.menu.as_ref().is_some_and(|menu| menu.item == item),
                            ),
                            value,
                            ..node(
                                NODE_PICKER + item as i32,
                                uia::Role::ComboBox,
                                picker.title.to_string(),
                                &Self::place(&layout.viewport, control, offset),
                            )
                        });
                    }
                    PartKind::Slider {
                        item, title, field, ..
                    } => nodes.push(uia::Node {
                        enabled: self.choices.live(),
                        ..node(
                            NODE_SLIDER + item as i32,
                            uia::Role::List,
                            format!("{title} {}", more::seconds(self.choices.seconds(field))),
                            &rect,
                        )
                    }),
                    PartKind::Spot { index, spot, .. } => nodes.push(uia::Node {
                        toggled: Some(self.choices.is_on(spot.path)),
                        ..node(
                            NODE_SPOT + index as i32,
                            uia::Role::CheckBox,
                            format!("{} {}", spot.title, spot.detail),
                            &rect,
                        )
                    }),
                    PartKind::TaskbarNote => {}
                }
            }
        }
        if let Some(menu) = &self.menu {
            let current = self.choices.value(menu.picker.field);
            for (index, (value, label)) in menu.picker.choices.iter().enumerate() {
                let rect = Rect::new(
                    menu.rect.x,
                    menu.rect.y + size::FLYOUT_PADDING + index as f32 * size::FLYOUT_ITEM_HEIGHT,
                    menu.rect.width,
                    size::FLYOUT_ITEM_HEIGHT,
                );
                nodes.push(uia::Node {
                    selected: Some(*value == current),
                    ..node(
                        NODE_MENU + index as i32,
                        uia::Role::ListItem,
                        menu_label(&menu.picker, value, label),
                        &rect,
                    )
                });
            }
        }
        for (button, rect) in self.buttons(self.step) {
            nodes.push(uia::Node {
                enabled: self.button_enabled(button),
                ..node(
                    NODE_BUTTON + BUTTONS.iter().position(|b| *b == button).unwrap_or(0) as i32,
                    uia::Role::Button,
                    button_label(button, self.step).to_string(),
                    &rect,
                )
            });
        }
        // 実演は見せている機能の説明を名前にする(見本の文字だけで，利用者の入力は含まない)
        let (_, height) = self.size();
        let caption = self
            .spotlight
            .and_then(|path| self.step.spots().iter().find(|spot| spot.path == path))
            .map_or(String::new(), |spot| {
                format!(" {} {}", spot.title, spot.detail)
            });
        nodes.push(node(
            NODE_DEMO,
            uia::Role::Document,
            format!("{}{caption}", notes::DEMO),
            &stage_rect(height),
        ));
        nodes
    }

    fn accessibility_act(&mut self, id: i32, act: uia::Act) {
        let target = match id {
            id if (NODE_CARD..NODE_THEME).contains(&id) => {
                let offset = (id - NODE_CARD) as usize;
                Target::Card(offset / 100, offset % 100)
            }
            id if (NODE_THEME..NODE_PICKER).contains(&id) => {
                Target::Theme((id - NODE_THEME) as usize)
            }
            id if (NODE_PICKER..NODE_SLIDER).contains(&id) => {
                let item = (id - NODE_PICKER) as usize;
                match act {
                    uia::Act::Collapse => {
                        self.menu = None;
                        ffi::invalidate(self.window);
                        return;
                    }
                    uia::Act::Focus => {
                        self.focus = Focus::Picker(item);
                        ffi::invalidate(self.window);
                        return;
                    }
                    _ => Target::Picker(item),
                }
            }
            id if (NODE_SLIDER..NODE_SPOT).contains(&id) => {
                Target::Slider((id - NODE_SLIDER) as usize)
            }
            id if (NODE_SPOT..NODE_MENU).contains(&id) => {
                let index = (id - NODE_SPOT) as usize;
                match act {
                    uia::Act::Toggle | uia::Act::Invoke => Target::Switch(index),
                    _ => Target::Spot(index),
                }
            }
            id if (NODE_MENU..NODE_BUTTON).contains(&id) => {
                Target::MenuItem((id - NODE_MENU) as usize)
            }
            id if (NODE_BUTTON..NODE_DEMO).contains(&id) => {
                match BUTTONS.get((id - NODE_BUTTON) as usize) {
                    Some(button) => Target::Button(*button),
                    None => return,
                }
            }
            _ => return,
        };
        if act == uia::Act::Focus {
            self.focus = match target {
                Target::Card(item, _) => Focus::Cards(item),
                Target::Theme(_) => Focus::Themes,
                Target::Picker(item) => Focus::Picker(item),
                Target::Slider(item) => Focus::Slider(item),
                Target::Spot(index) | Target::Switch(index) => Focus::Spot(index),
                Target::Button(button) => Focus::Button(button),
                Target::MenuItem(_) => self.focus,
            };
            ffi::invalidate(self.window);
            return;
        }
        self.press(target);
    }
}

/// メニューの項目の名前(推奨の値には「(推奨)」を添える)
fn menu_label(picker: &Picker, value: &str, label: &str) -> String {
    if picker.recommended == Some(value) {
        text::recommended(label)
    } else {
        label.to_string()
    }
}

// MARK: - 描く

struct PaintState<'a> {
    wizard: &'a Wizard,
    layout: &'a PageLayout,
    leaving: Option<&'a PageLayout>,
    now: f64,
}

fn paint_window(canvas: &mut dyn Canvas, state: &PaintState) {
    let wizard = state.wizard;
    let (_, height) = wizard.size();
    let fade = wizard.fade.value(state.now);
    paint_stage(canvas, state, fade, height);
    // ページ(見出しと選ぶもの)は前のページを薄くしながら，今のページを濃くする(macOS の cross-fade)
    if let (Some(leaving), Some(layout)) = (&wizard.leaving, state.leaving) {
        if fade < 1.0 {
            paint_page(
                canvas,
                state,
                leaving.step,
                layout,
                leaving.scroll,
                1.0 - fade,
                false,
            );
        }
    }
    let offset = wizard.scroll.offset(state.now);
    paint_page(canvas, state, wizard.step, state.layout, offset, fade, true);
    canvas.set_opacity(1.0);
    super::page::scrollbar(
        canvas,
        &wizard.theme,
        Rect::new(
            state.layout.viewport.x,
            state.layout.viewport.y,
            // 中身から group だけ右に離し，ページの余白の中に置く
            state.layout.viewport.width + space::GROUP,
            state.layout.viewport.height,
        ),
        &wizard.scroll,
        state.now,
    );
    paint_footer(canvas, state, fade);
    paint_menu(canvas, state);
}

// MARK: - 舞台

fn paint_stage(canvas: &mut dyn Canvas, state: &PaintState, fade: f32, height: f32) {
    let wizard = state.wizard;
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let stage = stage_rect(height);
    canvas.set_opacity(1.0);
    let ground = if theme.high_contrast {
        Color::from(palette.background)
    } else if theme.dark {
        Color::from(palette.background).mix(
            Color::from(tokens::Rgb {
                red: 0,
                green: 0,
                blue: 0,
            }),
            0.25,
        )
    } else {
        Color::from(palette.background).mix(Color::from(palette.text), 0.04)
    };
    canvas.fill_rect(stage, ground);
    if theme.high_contrast {
        canvas.fill_rect(
            Rect::new(stage.max_x() - 1.0, 0.0, 1.0, height),
            Color::from(palette.card_stroke),
        );
    } else {
        // アクセントの色と補正の色を，左上と右下からにじませる(macOS と同じ)
        canvas.radial_glow(
            stage,
            0.0,
            0.0,
            board::HEIGHT * 0.8,
            Color::from(palette.accent).with_alpha(shade::STAGE_GLOW),
        );
        canvas.radial_glow(
            stage,
            stage.max_x(),
            stage.max_y(),
            board::HEIGHT * 0.7,
            secondary_glow().with_alpha(shade::STAGE_GLOW_SECONDARY),
        );
    }
    canvas.push_clip(stage);
    if let Some(leaving) = &wizard.leaving {
        if fade < 1.0 {
            paint_stage_frame(
                canvas,
                state,
                leaving.frame.as_ref(),
                leaving.overlay.as_ref().map(|overlay| (1, overlay)),
                1.0 - fade,
            );
        }
    }
    let frame = wizard.demo_frame(state.now);
    paint_stage_frame(
        canvas,
        state,
        frame,
        wizard.overlay.as_ref().map(|overlay| (0, overlay)),
        fade,
    );
    paint_captions(canvas, state, height);
    canvas.pop_clip();
    canvas.set_opacity(1.0);
}

/// 入力欄の模型と文字，その下に重ねる候補の窓とモードの札
fn paint_stage_frame(
    canvas: &mut dyn Canvas,
    state: &PaintState,
    frame: Option<&Frame>,
    overlay: Option<(usize, &Overlay)>,
    alpha: f32,
) {
    let wizard = state.wizard;
    let theme = &wizard.theme;
    let palette = &theme.palette;
    canvas.set_opacity(alpha);
    let field = field_rect();
    if let Some(application) = frame.and_then(|frame| frame.application) {
        // 入力欄の上に，入力先のアプリの名前を窓の見出しのように出す
        let label = canvas.width(application, TextStyle::NavHeader);
        // 札の形(1 行の欄の左右の余白，札の上下の余白)にし，入力欄の上に stack だけ離して置く(macOS と同じ)
        let tab_height = size::NOTE_LINE_HEIGHT + part::TAG_PADDING_Y * 2.0;
        let tab = Rect::new(
            field.x,
            field.y - space::STACK - tab_height,
            label + part::FIELD_PADDING_X * 2.0,
            tab_height,
        );
        canvas.fill_round(
            tab,
            tab.height / 2.0,
            Color::from(palette.accent).with_alpha(shade::CARD_SELECTED),
        );
        canvas.text(
            tab,
            application,
            TextStyle::NavHeader,
            Color::from(palette.text_secondary),
            TextLayout::CENTER,
        );
    }
    let field_fill = if theme.high_contrast {
        Color::from(palette.control)
    } else if theme.dark {
        Color::from(palette.card).with_alpha(shade::FIELD)
    } else {
        Color::from(palette.control).with_alpha(shade::FIELD)
    };
    canvas.fill_round(field, board::FIELD_RADIUS, field_fill);
    canvas.stroke_round(
        field,
        board::FIELD_RADIUS,
        1.0,
        if theme.high_contrast {
            Color::from(palette.control_stroke)
        } else {
            Color::from(palette.text).with_alpha(shade::FIELD_STROKE)
        },
    );
    let line = canvas.wrapped_height("あ", TextStyle::Demo, field.width);
    let line_top = (field.y + (field.height - line) / 2.0).round();
    let underline = line_top + line - 1.0;
    let mut x = field.x + board::CARD_PADDING;
    canvas.push_clip(field);
    if let Some(frame) = frame {
        let committed = canvas.width(&frame.committed, TextStyle::Demo);
        canvas.text(
            // 最後の字が切れないように fine だけ広く測る
            Rect::new(x, line_top, committed + space::FINE, line),
            &frame.committed,
            TextStyle::Demo,
            Color::from(palette.text),
            TextLayout::LINE,
        );
        x += committed;
        let correction = ui_color(wizard.candidate_theme().correction);
        for segment in &frame.marked {
            let width = canvas.width(&segment.text, TextStyle::Demo);
            canvas.text(
                Rect::new(x, line_top, width + space::FINE, line),
                &segment.text,
                TextStyle::Demo,
                Color::from(palette.text),
                TextLayout::LINE,
            );
            match segment.style {
                Style::Reading | Style::Converted => canvas.fill_rect(
                    Rect::new(x, underline, width, 1.0),
                    Color::from(palette.text_secondary),
                ),
                Style::Focused => canvas.fill_rect(
                    Rect::new(x, underline - 0.5, width, 2.0),
                    Color::from(palette.text),
                ),
                Style::Correction => {
                    let dot = 2.0;
                    let mut dot_x = x + 0.5;
                    while dot_x + dot <= x + width {
                        canvas.fill_round(
                            Rect::new(dot_x, underline - 0.5, dot, dot),
                            dot / 2.0,
                            correction,
                        );
                        dot_x += dot * 2.0;
                    }
                }
            }
            x += width + space::FINE;
        }
    }
    // 入力位置
    canvas.fill_rect(
        Rect::new(x.round(), line_top, 2.0, line),
        Color::from(palette.accent),
    );
    canvas.pop_clip();
    if let Some((slot, overlay)) = overlay {
        canvas.preview_at(slot, overlay.x, overlay.y);
    }
}

/// 見せている機能の説明の札(舞台の下)．項目を移るたびに下から浮かび上がる
fn paint_captions(canvas: &mut dyn Canvas, state: &PaintState, height: f32) {
    let wizard = state.wizard;
    let page = wizard.fade.value(state.now);
    if let Some((path, step, tween)) = &wizard.caption_leaving {
        let leaving_page = if *step == wizard.step {
            1.0
        } else {
            1.0 - page
        };
        paint_caption(
            canvas,
            state,
            *step,
            path,
            tween.value(state.now) * leaving_page,
            0.0,
            height,
        );
    }
    if let Some(path) = wizard.spotlight {
        let shown = wizard.caption.value(state.now);
        paint_caption(
            canvas,
            state,
            wizard.step,
            path,
            shown.clamp(0.0, 1.0) * page,
            (1.0 - shown) * board::CARD_GAP * 2.0,
            height,
        );
    }
}

fn paint_caption(
    canvas: &mut dyn Canvas,
    state: &PaintState,
    step: Step,
    path: &str,
    alpha: f32,
    lift: f32,
    height: f32,
) {
    let Some(spot) = step.spots().iter().find(|spot| spot.path == path) else {
        return;
    };
    if alpha <= 0.0 {
        return;
    }
    let wizard = state.wizard;
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let padding = board::CARD_PADDING;
    let gap = board::CARD_GAP;
    let icon = board::FIELD_HEIGHT;
    let width = board::STAGE_WIDTH - board::STAGE_PADDING * 2.0;
    let text_width = width - padding * 2.0 - icon - gap;
    let detail = canvas.wrapped_height(spot.detail, TextStyle::Body, text_width);
    let card_height = (LINE + space::STACK + detail).max(icon) + padding * 2.0;
    let card = Rect::new(
        board::STAGE_PADDING,
        height - board::STAGE_PADDING - card_height + lift,
        width,
        card_height,
    );
    canvas.set_opacity(alpha);
    canvas.fill_round(
        card,
        board::CARD_RADIUS,
        if theme.high_contrast {
            Color::from(palette.background)
        } else {
            Color::from(palette.flyout).with_alpha(shade::CAPTION)
        },
    );
    canvas.stroke_round(
        card,
        board::CARD_RADIUS,
        1.0,
        if theme.high_contrast {
            Color::from(palette.card_stroke)
        } else {
            Color::from(palette.text).with_alpha(shade::CAPTION_STROKE)
        },
    );
    let circle = Rect::new(card.x + padding, card.y + padding, icon, icon);
    canvas.fill_round(circle, icon / 2.0, Color::from(palette.accent));
    canvas.text(
        circle,
        spot_glyph(path),
        TextStyle::Icon,
        Color::from(palette.accent_text),
        TextLayout::CENTER,
    );
    let text_x = circle.max_x() + gap;
    canvas.text(
        Rect::new(text_x, card.y + padding, text_width, LINE),
        spot.title,
        TextStyle::Section,
        Color::from(palette.text),
        TextLayout::LINE,
    );
    canvas.text(
        Rect::new(
            text_x,
            card.y + padding + LINE + space::STACK,
            text_width,
            detail + space::FINE,
        ),
        spot.detail,
        TextStyle::Body,
        Color::from(palette.text_secondary),
        TextLayout::WRAP,
    );
}

// MARK: - ページ

#[allow(clippy::too_many_arguments)]
fn paint_page(
    canvas: &mut dyn Canvas,
    state: &PaintState,
    step: Step,
    layout: &PageLayout,
    offset: f32,
    alpha: f32,
    current: bool,
) {
    let wizard = state.wizard;
    let theme = &wizard.theme;
    let palette = &theme.palette;
    canvas.set_opacity(alpha);
    canvas.text(
        layout.counter,
        &text::step(step.index() + 1, Step::ALL.len()),
        TextStyle::NavHeader,
        Color::from(palette.accent),
        TextLayout::LINE,
    );
    canvas.text(
        layout.title,
        step.title(),
        TextStyle::Title,
        Color::from(palette.text),
        TextLayout::WRAP,
    );
    if let Some(detail) = step.detail() {
        canvas.text(
            layout.detail,
            detail,
            TextStyle::Body,
            Color::from(palette.text_secondary),
            TextLayout::WRAP,
        );
    }
    canvas.push_clip(layout.viewport);
    if !wizard.ready() {
        let y = layout.viewport.y + board::CARD_GAP;
        paint::progress_ring(
            canvas,
            theme,
            layout.viewport.x + size::PROGRESS_RING_SIZE / 2.0,
            y + size::PROGRESS_RING_SIZE / 2.0,
            ((state.now % f64::from(motion::PROGRESS_RING)) / f64::from(motion::PROGRESS_RING))
                as f32,
        );
        canvas.text(
            Rect::new(
                layout.viewport.x + size::PROGRESS_RING_SIZE + size::CONTROL_GAP,
                y,
                layout.viewport.width,
                size::PROGRESS_RING_SIZE,
            ),
            notes::LOADING,
            TextStyle::Body,
            Color::from(palette.text_secondary),
            TextLayout::LINE,
        );
        canvas.pop_clip();
        return;
    }
    for part in &layout.parts {
        let rect = Wizard::place(&layout.viewport, part.rect, offset);
        if rect.max_y() < layout.viewport.y || rect.y > layout.viewport.max_y() {
            continue;
        }
        let look = Look {
            current,
            now: state.now,
        };
        match part.kind {
            PartKind::Card {
                item,
                index,
                field,
                card,
            } => paint_card(canvas, wizard, rect, &look, (item, index), field, card),
            PartKind::Info(_, info) => paint_info(canvas, wizard, rect, info),
            PartKind::Theme(index) => paint_theme(canvas, wizard, rect, &look, index),
            PartKind::Picker {
                item,
                picker,
                control,
            } => paint_picker(
                canvas,
                wizard,
                rect,
                Wizard::place(&layout.viewport, control, offset),
                &look,
                item,
                picker,
            ),
            PartKind::Slider {
                item,
                title,
                field,
                track,
            } => paint_slider(
                canvas,
                wizard,
                rect,
                Wizard::place(&layout.viewport, track, offset),
                &look,
                (item, title, field),
            ),
            PartKind::Spot {
                index,
                spot,
                switch,
            } => paint_spot(
                canvas,
                wizard,
                rect,
                Wizard::place(&layout.viewport, switch, offset),
                &look,
                index,
                spot,
            ),
            PartKind::TaskbarNote => {
                paint_note(canvas, theme, rect, INFO_GLYPH, notes::TASKBAR_NOTE)
            }
        }
        canvas.set_opacity(alpha);
    }
    canvas.pop_clip();
}

/// 部品を描くときの共通の値
struct Look {
    /// 今のページ(ポインターとキーボードの印を出す)
    current: bool,
    now: f64,
}

/// カードの地と縁(macOS の OptionCard．選んだものはアクセントの色の地と縁)
fn card_ground(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    selected: bool,
    hover: f32,
    pressed: bool,
) {
    let palette = &theme.palette;
    let radius = board::CARD_RADIUS;
    if theme.high_contrast {
        canvas.fill_round(rect, radius, Color::from(palette.background));
        canvas.stroke_round(
            rect,
            radius,
            if selected { 2.0 } else { 1.0 },
            Color::from(if selected {
                palette.accent
            } else {
                palette.card_stroke
            }),
        );
        return;
    }
    let lift = if pressed { 2.0 } else { hover };
    let fill = if selected {
        Color::from(palette.accent).with_alpha(shade::CARD_SELECTED + lift * 0.04)
    } else {
        Color::from(palette.text).with_alpha(shade::CARD_IDLE + lift * 0.035)
    };
    canvas.fill_round(rect, radius, fill);
    if selected {
        canvas.stroke_round(rect, radius, 1.5, Color::from(palette.accent));
    }
}

/// 推奨の札．x は左端，line は名前の行
fn badge(canvas: &mut dyn Canvas, theme: &Theme, x: f32, line: Rect) {
    let width = canvas.width(text::RECOMMENDED, TextStyle::NavHeader) + board::CARD_PADDING;
    let rect = Rect::new(
        x,
        line.y + (line.height - BADGE_HEIGHT) / 2.0,
        width,
        BADGE_HEIGHT,
    );
    canvas.fill_round(rect, board::BADGE_RADIUS, Color::from(theme.palette.accent));
    canvas.text(
        rect,
        text::RECOMMENDED,
        TextStyle::NavHeader,
        Color::from(theme.palette.accent_text),
        TextLayout::CENTER,
    );
}

/// 名前(と推奨の札)と説明
fn card_text(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    x: f32,
    rect: Rect,
    title: &str,
    detail: Option<&str>,
    recommended: bool,
) {
    let palette = &theme.palette;
    let width = rect.max_x() - board::CARD_PADDING - x;
    let line = Rect::new(x, rect.y + board::CARD_PADDING, width, LINE);
    canvas.text(
        line,
        title,
        TextStyle::Section,
        Color::from(palette.text),
        TextLayout::LINE,
    );
    if recommended {
        let title_width = canvas.width(title, TextStyle::Section);
        badge(canvas, theme, x + title_width + space::INLINE, line);
    }
    if let Some(detail) = detail {
        let top = line.max_y() + space::STACK;
        canvas.text(
            Rect::new(x, top, width, rect.max_y() - top),
            detail,
            TextStyle::Caption,
            Color::from(palette.text_secondary),
            TextLayout::WRAP,
        );
    }
}

fn paint_card(
    canvas: &mut dyn Canvas,
    wizard: &Wizard,
    rect: Rect,
    look: &Look,
    (item, index): (usize, usize),
    field: Field,
    card: Card,
) {
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let target = Target::Card(item, index);
    let selected = wizard.choices.value(field) == card.value;
    let (hover, pressed) = if look.current {
        (
            wizard.hover_value(target, look.now),
            wizard.pressed == Some(target),
        )
    } else {
        (0.0, false)
    };
    card_ground(canvas, theme, rect, selected, hover, pressed);
    // 丸．選んだものはアクセントの色の丸にチェック
    let circle = Rect::new(
        rect.x + board::CARD_PADDING,
        rect.y + board::CARD_PADDING + (LINE - CHECK) / 2.0,
        CHECK,
        CHECK,
    );
    if selected {
        canvas.fill_round(circle, CHECK / 2.0, Color::from(palette.accent));
        canvas.text(
            circle,
            theme.glyphs.check,
            TextStyle::IconSmall,
            Color::from(palette.accent_text),
            TextLayout::CENTER,
        );
    } else {
        canvas.stroke_round(
            circle,
            CHECK / 2.0,
            1.5,
            Color::from(palette.text_secondary),
        );
    }
    card_text(
        canvas,
        theme,
        circle.max_x() + board::CARD_GAP,
        rect,
        card.title,
        card.detail,
        card.recommended,
    );
    if look.current && wizard.focus_visible && wizard.focus == Focus::Cards(item) && selected {
        paint::focus_ring(canvas, theme, rect, board::CARD_RADIUS);
    }
}

/// 説明だけのカード．入力モードの札を枠に入れて並べる(macOS の InfoCard)
fn paint_info(canvas: &mut dyn Canvas, wizard: &Wizard, rect: Rect, info: Info) {
    let theme = &wizard.theme;
    let palette = &theme.palette;
    card_ground(canvas, theme, rect, false, 0.0, false);
    let mark = Rect::new(
        rect.x + board::CARD_PADDING,
        rect.y + (rect.height - board::INFO_SYMBOL_WIDTH) / 2.0,
        board::INFO_SYMBOL_WIDTH * 2.0,
        board::INFO_SYMBOL_WIDTH,
    );
    canvas.stroke_round(
        mark,
        board::CARD_RADIUS / 2.0,
        1.5,
        Color::from(palette.accent),
    );
    canvas.text(
        mark,
        &mark_label(info.mark),
        TextStyle::Section,
        Color::from(palette.accent),
        TextLayout::CENTER,
    );
    // 名前は札と同じく縦の真ん中に置く(macOS の InfoCard)
    let x = mark.max_x() + board::CARD_GAP;
    canvas.text(
        Rect::new(
            x,
            rect.y,
            rect.max_x() - board::CARD_PADDING - x,
            rect.height,
        ),
        info.title,
        TextStyle::Section,
        Color::from(palette.text),
        TextLayout::LINE,
    );
}

/// テーマのカード．そのテーマの地・選択・文字・補正の色を小さく並べた見本と名前(macOS の ThemeTile)
fn paint_theme(canvas: &mut dyn Canvas, wizard: &Wizard, rect: Rect, look: &Look, index: usize) {
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let name = wizard::THEME_ORDER[index];
    let target = Target::Theme(index);
    let selected = wizard.choices.theme_selected(name);
    let (hover, pressed) = if look.current {
        (
            wizard.hover_value(target, look.now),
            wizard.pressed == Some(target),
        )
    } else {
        (0.0, false)
    };
    card_ground(canvas, theme, rect, selected, hover, pressed);
    let systems = candidate_ui::theme::SystemLook {
        dark: theme.dark,
        accent: None,
        increase_contrast: theme.high_contrast,
        backdrop: false,
    };
    let colors = candidate_ui::theme::ResolvedTheme::resolve(name, None, &systems);
    let inset = board::CARD_PADDING;
    let swatch = Rect::new(
        rect.x + inset,
        rect.y + inset,
        rect.width - inset * 2.0,
        SWATCH_HEIGHT,
    );
    let radius = board::CARD_RADIUS / 2.0;
    canvas.fill_round(swatch, radius, ui_color(colors.surface).with_alpha(1.0));
    let dot = board::DOT_SIZE;
    let bars = [
        (
            board::THEME_SAMPLE_WIDTH,
            dot * 1.6,
            ui_color(colors.selection),
        ),
        (
            board::THEME_SAMPLE_WIDTH * 0.75,
            dot / 1.5,
            ui_color(colors.text).with_alpha(shade::SWATCH_TEXT),
        ),
        (
            board::THEME_SAMPLE_WIDTH * 0.5,
            dot / 2.0,
            ui_color(colors.correction),
        ),
    ];
    let total: f32 = bars.iter().map(|(_, height, _)| height).sum::<f32>() + board::DOT_GAP * 2.0;
    let mut y = swatch.y + (swatch.height - total) / 2.0;
    for (width, height, color) in bars {
        canvas.fill_round(
            Rect::new(
                swatch.x + space::GROUP,
                y,
                width.min(swatch.width - space::GROUP * 2.0),
                height,
            ),
            height / 2.0,
            color,
        );
        y += height + board::DOT_GAP;
    }
    canvas.stroke_round(
        swatch,
        radius,
        1.0,
        ui_color(colors.frame).with_alpha(shade::SWATCH_FRAME),
    );
    let line = Rect::new(swatch.x, swatch.max_y() + space::STACK, swatch.width, LINE);
    let label = wizard::theme_label(name);
    canvas.text(
        line,
        label,
        TextStyle::Body,
        Color::from(palette.text),
        TextLayout::LINE,
    );
    if index == 0 {
        let width = canvas.width(label, TextStyle::Body);
        badge(canvas, theme, line.x + width + space::INLINE, line);
    }
    if look.current && wizard.focus_visible && wizard.focus == Focus::Themes && selected {
        paint::focus_ring(canvas, theme, rect, board::CARD_RADIUS);
    }
}

/// 名前とメニューのボタンの行(入力する文字の行はカードの地に載せる)
fn paint_picker(
    canvas: &mut dyn Canvas,
    wizard: &Wizard,
    rect: Rect,
    control: Rect,
    look: &Look,
    item: usize,
    picker: Picker,
) {
    let theme = &wizard.theme;
    let palette = &theme.palette;
    if picker.framed {
        card_ground(canvas, theme, rect, false, 0.0, false);
    }
    let inset = if picker.framed {
        board::CARD_PADDING
    } else {
        0.0
    };
    canvas.text(
        Rect::new(
            rect.x + inset,
            rect.y,
            (control.x - rect.x - inset - board::CARD_GAP).max(0.0),
            rect.height,
        ),
        picker.title,
        TextStyle::Body,
        Color::from(palette.text),
        TextLayout::LINE,
    );
    let current = wizard.choices.value(picker.field);
    let label = picker
        .choices
        .iter()
        .find(|(value, _)| *value == current)
        .map_or(String::new(), |(value, label)| {
            menu_label(&picker, value, label)
        });
    let target = Target::Picker(item);
    let open = wizard.menu.as_ref().is_some_and(|menu| menu.item == item);
    let state = if look.current {
        State {
            enabled: true,
            hover: wizard.hover_value(target, look.now),
            pressed: wizard.pressed == Some(target),
            focus_visible: wizard.focus_visible && wizard.focus == Focus::Picker(item) && !open,
        }
    } else {
        State::enabled()
    };
    paint::dropdown(canvas, theme, control, &label, open, state);
}

/// 秒の値のスライダー(macOS の SecondsSlider．名前・つまみ・値)
fn paint_slider(
    canvas: &mut dyn Canvas,
    wizard: &Wizard,
    rect: Rect,
    track: Rect,
    look: &Look,
    (item, title, field): (usize, &'static str, Field),
) {
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let enabled = wizard.choices.live();
    let text_color = Color::from(if enabled {
        palette.text
    } else {
        palette.text_disabled
    });
    canvas.text(
        Rect::new(rect.x, rect.y, track.x - rect.x, rect.height),
        title,
        TextStyle::Body,
        text_color,
        TextLayout::LINE,
    );
    let range = wizard.catalog.ranges.live_conversion_delay;
    let seconds = if look.current {
        wizard
            .dragging
            .unwrap_or_else(|| wizard.choices.seconds(field))
    } else {
        wizard.choices.seconds(field)
    };
    canvas.text(
        Rect::new(
            rect.max_x() - size::SECONDS_LABEL_WIDTH,
            rect.y,
            size::SECONDS_LABEL_WIDTH,
            rect.height,
        ),
        &more::seconds(seconds),
        TextStyle::Body,
        text_color,
        TextLayout::TRAILING,
    );
    let ratio =
        ((seconds - range.lower()) / (range.upper() - range.lower())).clamp(0.0, 1.0) as f32;
    let travel = track.width - THUMB;
    let center_x = track.x + THUMB / 2.0 + travel * ratio;
    let center_y = track.y + track.height / 2.0;
    let rail = board::SLIDER_RAIL;
    let accent = if enabled {
        Color::from(palette.accent)
    } else {
        Color::from(palette.text_disabled)
    };
    canvas.fill_round(
        Rect::new(track.x + THUMB / 2.0, center_y - rail / 2.0, travel, rail),
        rail / 2.0,
        Color::from(palette.control_strong_stroke).with_alpha(if enabled {
            shade::SLIDER_RAIL
        } else {
            shade::SLIDER_RAIL_DISABLED
        }),
    );
    canvas.fill_round(
        Rect::new(
            track.x + THUMB / 2.0,
            center_y - rail / 2.0,
            center_x - track.x - THUMB / 2.0,
            rail,
        ),
        rail / 2.0,
        accent,
    );
    // つまみ(WinUI と同じく，ポインターを載せると中の丸が大きく，押すと小さくなる)
    let target = Target::Slider(item);
    let hover = if look.current && enabled {
        wizard.hover_value(target, look.now)
    } else {
        0.0
    };
    let pressed = look.current && wizard.dragging.is_some();
    let thumb = Rect::new(center_x - THUMB / 2.0, center_y - THUMB / 2.0, THUMB, THUMB);
    canvas.fill_round(thumb, THUMB / 2.0, Color::from(palette.control));
    canvas.stroke_round(thumb, THUMB / 2.0, 1.0, Color::from(palette.control_stroke));
    let inner = if pressed { 10.0 } else { 12.0 + 2.0 * hover };
    canvas.fill_round(
        Rect::new(center_x - inner / 2.0, center_y - inner / 2.0, inner, inner),
        inner / 2.0,
        accent,
    );
    if look.current && wizard.focus_visible && wizard.focus == Focus::Slider(item) {
        paint::focus_ring(canvas, theme, thumb, THUMB / 2.0);
    }
}

/// 機能の行．アイコン・名前・スイッチ．見せている機能の行はアクセントの色の地と縁(macOS の SpotlightRow)
#[allow(clippy::too_many_arguments)]
fn paint_spot(
    canvas: &mut dyn Canvas,
    wizard: &Wizard,
    rect: Rect,
    switch: Rect,
    look: &Look,
    index: usize,
    spot: Spot,
) {
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let glow = if look.current {
        wizard
            .spot_glows
            .iter()
            .find(|(path, _)| *path == spot.path)
            .map_or(0.0, |(_, tween)| tween.value(look.now))
    } else {
        f32::from(u8::from(wizard.spotlight == Some(spot.path)))
    };
    let radius = board::CARD_RADIUS;
    if theme.high_contrast {
        card_ground(canvas, theme, rect, glow > 0.5, 0.0, false);
    } else {
        canvas.fill_round(
            rect,
            radius,
            Color::from(palette.text).with_alpha(shade::CARD_IDLE * (1.0 - glow)),
        );
        canvas.fill_round(
            rect,
            radius,
            Color::from(palette.accent).with_alpha(shade::CARD_SELECTED * glow),
        );
        canvas.stroke_round(
            rect,
            radius,
            1.5,
            Color::from(palette.accent).with_alpha(glow),
        );
    }
    let icon = Rect::new(
        rect.x + board::CARD_PADDING,
        rect.y,
        board::INFO_SYMBOL_WIDTH,
        rect.height,
    );
    canvas.text(
        icon,
        spot_glyph(spot.path),
        TextStyle::Icon,
        Color::from(palette.text_secondary).mix(Color::from(palette.accent), glow),
        TextLayout::CENTER,
    );
    let title_x = icon.max_x() + board::CARD_GAP;
    canvas.text(
        Rect::new(
            title_x,
            rect.y,
            (switch.x - title_x - board::CARD_GAP).max(0.0),
            rect.height,
        ),
        spot.title,
        TextStyle::Section,
        Color::from(palette.text),
        TextLayout::LINE,
    );
    let on = wizard.choices.is_on(spot.path);
    let knob = wizard
        .knobs
        .iter()
        .find(|(path, _)| *path == spot.path)
        .map_or(if on { 1.0 } else { 0.0 }, |(_, knob)| knob.value(look.now));
    let target = Target::Switch(index);
    let state = if look.current {
        State {
            enabled: true,
            hover: wizard.hover_value(target, look.now),
            pressed: wizard.pressed == Some(target),
            focus_visible: false,
        }
    } else {
        State::enabled()
    };
    paint::toggle(canvas, theme, switch, on, knob, "", "", state);
    if look.current && wizard.focus_visible && wizard.focus == Focus::Spot(index) {
        paint::focus_ring(canvas, theme, rect, radius);
    }
}

/// アイコンの付いた小さい案内
fn paint_note(canvas: &mut dyn Canvas, theme: &Theme, rect: Rect, glyph: &str, note: &str) {
    let color = Color::from(theme.palette.text_secondary);
    canvas.text(
        Rect::new(rect.x, rect.y, size::CHEVRON_SIZE, size::NOTE_LINE_HEIGHT),
        glyph,
        TextStyle::IconSmall,
        color,
        TextLayout::CENTER,
    );
    let x = rect.x + size::CHEVRON_SIZE + space::INLINE;
    canvas.text(
        Rect::new(x, rect.y + 1.0, rect.max_x() - x, rect.height),
        note,
        TextStyle::Caption,
        color,
        TextLayout::WRAP,
    );
}

// MARK: - 足元

fn paint_footer(canvas: &mut dyn Canvas, state: &PaintState, fade: f32) {
    let wizard = state.wizard;
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let (_, height) = wizard.size();
    let y = height - board::PADDING - size::CONTROL_HEIGHT;
    let x = board::STAGE_WIDTH + board::PADDING;
    canvas.set_opacity(1.0);
    if let Some(error) = wizard.error {
        let right = wizard
            .buttons(wizard.step)
            .first()
            .map_or(x, |(_, rect)| rect.x - board::CARD_GAP);
        canvas.text(
            Rect::new(x, y, (right - x).max(0.0), size::CONTROL_HEIGHT),
            error,
            TextStyle::Caption,
            Color::from(palette.caution),
            TextLayout::WRAP,
        );
    } else {
        // 進み具合の点．今のページはアクセントの色(ページを替えるあいだは色を移す)
        let previous = wizard.leaving.as_ref().map(|leaving| leaving.step);
        let idle = Color::from(palette.text_secondary).with_alpha(shade::CARD_SELECTED * 3.0);
        let accent = Color::from(palette.accent);
        for (index, step) in Step::ALL.into_iter().enumerate() {
            let shown = |current: bool| if current { accent } else { idle };
            let color = match previous {
                Some(previous) => shown(previous == step).mix(shown(wizard.step == step), fade),
                None => shown(wizard.step == step),
            };
            canvas.fill_round(
                Rect::new(
                    x + index as f32 * (board::DOT_SIZE + board::DOT_GAP),
                    y + (size::CONTROL_HEIGHT - board::DOT_SIZE) / 2.0,
                    board::DOT_SIZE,
                    board::DOT_SIZE,
                ),
                board::DOT_SIZE / 2.0,
                color,
            );
        }
    }
    for (button, rect) in wizard.buttons(wizard.step) {
        let target = Target::Button(button);
        let control = State {
            enabled: wizard.button_enabled(button),
            hover: wizard.hover_value(target, state.now),
            pressed: wizard.pressed == Some(target),
            focus_visible: wizard.focus_visible
                && wizard.menu.is_none()
                && wizard.focus == Focus::Button(button),
        };
        // 1 ページ目から移るとき・戻るときは「戻る」を薄くして出し入れする
        let appearing = wizard
            .leaving
            .as_ref()
            .is_some_and(|leaving| leaving.step.is_first());
        canvas.set_opacity(if button == Button::Back && appearing {
            fade
        } else {
            1.0
        });
        let label = button_label(button, wizard.step);
        match button {
            Button::Skip => paint_plain_button(canvas, theme, rect, label, control),
            Button::Back => {
                paint::button(canvas, theme, rect, label, ButtonKind::Standard, control)
            }
            Button::Next => paint::button(canvas, theme, rect, label, ButtonKind::Accent, control),
        }
    }
    canvas.set_opacity(1.0);
}

/// 地の無い文字だけのボタン(macOS の plain．ポインターを載せると文字を濃くし，押すと薄くする)
fn paint_plain_button(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    label: &str,
    state: State,
) {
    let palette = &theme.palette;
    let color = Color::from(palette.text_secondary).mix(Color::from(palette.text), state.hover);
    let color = if state.pressed {
        color.with_alpha(0.7)
    } else {
        color
    };
    canvas.text(rect, label, TextStyle::Body, color, TextLayout::CENTER);
    if state.focus_visible {
        paint::focus_ring(canvas, theme, rect, size::CONTROL_RADIUS);
    }
}

/// 開いているメニュー(WinUI の ComboBox の一覧)
fn paint_menu(canvas: &mut dyn Canvas, state: &PaintState) {
    let wizard = state.wizard;
    let Some(menu) = &wizard.menu else {
        return;
    };
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let opened = menu.opened.value(state.now);
    canvas.set_opacity(opened);
    let lift = (1.0 - opened) * -size::CONTROL_GAP;
    canvas.translate(0.0, lift);
    // 柔らかい影(WinUI のメニューの影に近いもの)．にじみの輪を重ねて描く
    if !theme.high_contrast {
        let shadow = if theme.dark { 0.14 } else { 0.035 };
        for ring in 1..=MENU_SHADOW_RINGS {
            let spread = ring as f32 * 1.5;
            canvas.set_opacity(opened);
            canvas.fill_round(
                Rect::new(
                    menu.rect.x - spread,
                    menu.rect.y - spread + ring as f32,
                    menu.rect.width + spread * 2.0,
                    menu.rect.height + spread * 2.0,
                ),
                size::FLYOUT_RADIUS + spread,
                Color::from(tokens::Rgb {
                    red: 0,
                    green: 0,
                    blue: 0,
                })
                .with_alpha(shadow),
            );
        }
    }
    canvas.fill_round(menu.rect, size::FLYOUT_RADIUS, Color::from(palette.flyout));
    canvas.stroke_round(
        menu.rect,
        size::FLYOUT_RADIUS,
        1.0,
        Color::from(palette.flyout_stroke),
    );
    let current = wizard.choices.value(menu.picker.field);
    for (index, (value, label)) in menu.picker.choices.iter().enumerate() {
        let row = Rect::new(
            menu.rect.x + size::FLYOUT_PADDING,
            menu.rect.y + size::FLYOUT_PADDING + index as f32 * size::FLYOUT_ITEM_HEIGHT,
            menu.rect.width - size::FLYOUT_PADDING * 2.0,
            size::FLYOUT_ITEM_HEIGHT,
        );
        let selected = *value == current;
        let fill = if wizard.pressed == Some(Target::MenuItem(index)) {
            Some(palette.nav_pressed)
        } else if index == menu.highlighted {
            Some(palette.nav_hover)
        } else if selected {
            Some(palette.nav_selected)
        } else {
            None
        };
        if let Some(fill) = fill {
            let inner = Rect::new(
                row.x,
                row.y + space::FINE,
                row.width,
                row.height - space::FINE * 2.0,
            );
            canvas.fill_round(inner, size::CONTROL_RADIUS, Color::from(fill));
        }
        if selected {
            canvas.fill_round(
                Rect::new(
                    row.x,
                    row.y + (row.height - size::NAV_INDICATOR_HEIGHT) / 2.0,
                    size::NAV_INDICATOR_WIDTH,
                    size::NAV_INDICATOR_HEIGHT,
                ),
                size::NAV_INDICATOR_WIDTH / 2.0,
                Color::from(palette.accent),
            );
        }
        canvas.text(
            Rect::new(
                row.x + size::FIELD_PADDING_X,
                row.y,
                row.width - size::FIELD_PADDING_X * 2.0,
                row.height,
            ),
            &menu_label(&menu.picker, value, label),
            TextStyle::Body,
            Color::from(palette.text),
            TextLayout::LINE,
        );
        if wizard.focus_visible && index == menu.highlighted {
            paint::focus_ring(canvas, theme, row, size::CONTROL_RADIUS);
        }
    }
    canvas.translate(0.0, -lift);
    canvas.set_opacity(1.0);
}

fn accessibility_nodes() -> Vec<uia::Node> {
    with_wizard(|wizard| wizard.nodes()).unwrap_or_default()
}

fn accessibility_act(id: i32, act: uia::Act) {
    with_wizard(|wizard| wizard.accessibility_act(id, act));
}

fn low_word(value: usize) -> u32 {
    (value & 0xffff) as u32
}

fn high_word(value: usize) -> u32 {
    ((value >> 16) & 0xffff) as u32
}

extern "system" fn procedure(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let handled = std::panic::catch_unwind(|| handle(window, message, wparam, lparam));
    match handled {
        Ok(Some(result)) => result,
        _ => ffi::default_procedure(window, message, wparam, lparam),
    }
}

fn handle(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
    match message {
        WM_ERASEBKGND => Some(LRESULT(1)),
        WM_PAINT => {
            // 描く前に済んだことにする(描く中で頼んだ次のフレームを打ち消さない)
            ffi::validate(window);
            with_wizard(Wizard::paint);
            Some(LRESULT(0))
        }
        WM_LOADED => {
            with_wizard(Wizard::finish_loading);
            Some(LRESULT(0))
        }
        WM_TIMER if wparam.0 == DEMO_TIMER => {
            ffi::kill_timer(window, DEMO_TIMER);
            ffi::invalidate(window);
            Some(LRESULT(0))
        }
        WM_TIMER if wparam.0 == RECONNECT_TIMER => {
            ffi::kill_timer(window, RECONNECT_TIMER);
            with_wizard(Wizard::start_loading);
            Some(LRESULT(0))
        }
        WM_MOUSEMOVE => {
            with_wizard(|wizard| wizard.mouse_move(lparam));
            Some(LRESULT(0))
        }
        WM_MOUSELEAVE => {
            with_wizard(|wizard| wizard.set_hover(None));
            Some(LRESULT(0))
        }
        WM_LBUTTONDOWN => {
            with_wizard(|wizard| wizard.mouse_down(lparam));
            Some(LRESULT(0))
        }
        WM_LBUTTONUP => {
            with_wizard(|wizard| wizard.mouse_up(lparam));
            Some(LRESULT(0))
        }
        WM_MOUSEWHEEL => {
            with_wizard(|wizard| wizard.wheel(wparam, lparam));
            Some(LRESULT(0))
        }
        WM_CAPTURECHANGED => {
            with_wizard(|wizard| {
                wizard.pressed = None;
                if let Some(seconds) = wizard.dragging.take() {
                    wizard.set_seconds(wizard::LIVE_DELAY, seconds);
                }
            });
            None
        }
        WM_KEYDOWN => {
            let key = low_word(wparam.0) as u16;
            with_wizard(|wizard| wizard.key(key))
                .unwrap_or(false)
                .then_some(LRESULT(0))
        }
        WM_SETTINGCHANGE | WM_SYSCOLORCHANGE | WM_THEMECHANGED => {
            with_wizard(|wizard| wizard.reload_theme(wizard.theme.dpi));
            None
        }
        WM_DPICHANGED => {
            let dpi = high_word(wparam.0);
            with_wizard(|wizard| wizard.reload_theme(dpi));
            if let Some((x, y, width, height)) = ffi::suggested_rect(lparam) {
                ffi::place(window, x, y, width, height);
            }
            Some(LRESULT(0))
        }
        WM_GETOBJECT => uia::get_object(window, wparam, lparam),
        WM_DESTROY => {
            WIZARD_ALIVE.with(|alive| alive.set(false));
            uia::disconnect(window);
            ffi::kill_timer(window, DEMO_TIMER);
            ffi::kill_timer(window, RECONNECT_TIMER);
            // 借りている途中(ボタンで閉じた)なら，手続きを返したあとに片付ける
            WIZARD.with(|cell| {
                if let Ok(mut wizard) = cell.try_borrow_mut() {
                    wizard.take();
                }
            });
            ffi::quit();
            Some(LRESULT(0))
        }
        _ => None,
    }
}
