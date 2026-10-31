#![forbid(unsafe_code)]

//! 設定の窓．左に検索と一覧(見出しごとのページ)，右に開いているページを置く(macOS の SettingsView と同じ並び)．
//! 窓は 1 枚で，Direct2D で描く．動きのあいだだけ描き直しを続け(画面の更新に合わせる)，止まっているときは描かない．
//! 状態は UI スレッドの thread_local に持ち，窓の手続きはそこから借りる．借りている間に届いたメッセージは既定の扱いにする

use super::actions::After;
use super::ffi::d2d::{self, Graphics, PreviewPixels, Surface};
use super::ffi::uia;
use super::ffi::{self, edit, Window};
use super::page::{self, Availability, Described, Element, Event, Extras, Frame, PageView, Part};
use super::paint::{self, Canvas, Measure, TextLayout, TextStyle};
use super::theme::{Color, Theme};
use super::Store;
use crate::catalog::{Catalog, Timing};
use crate::layout::Rect;
use crate::model::SettingsModel;
use crate::pages::{self, Page};
use crate::strings::{features, settings};
use crate::ui::anim::{Easing, Tween};
use crate::ui::nav::NavLayout;
use crate::ui::scroll::{self, Scroller};
use crate::ui::table::Move;
use ipc::{DictionaryEntry, SymbolItem};
use std::cell::RefCell;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokens::motion::settings_windows as motion;
use tokens::size::settings_windows as size;
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::Controls::WM_MOUSELEAVE;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    VK_DELETE, VK_DOWN, VK_END, VK_ESCAPE, VK_F4, VK_HOME, VK_LEFT, VK_NEXT, VK_PRIOR, VK_RETURN,
    VK_RIGHT, VK_SPACE, VK_TAB, VK_UP,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CW_USEDEFAULT, EN_CHANGE, MA_NOACTIVATE, WA_INACTIVE, WHEEL_DELTA, WINDOW_EX_STYLE,
    WM_ACTIVATE, WM_ACTIVATEAPP, WM_APP, WM_CANCELMODE, WM_CAPTURECHANGED, WM_COMMAND,
    WM_CTLCOLOREDIT, WM_CTLCOLORSTATIC, WM_DESTROY, WM_DPICHANGED, WM_ERASEBKGND, WM_GETMINMAXINFO,
    WM_GETOBJECT, WM_KEYDOWN, WM_KILLFOCUS, WM_LBUTTONDBLCLK, WM_LBUTTONDOWN, WM_LBUTTONUP,
    WM_MOUSEACTIVATE, WM_MOUSEMOVE, WM_MOUSEWHEEL, WM_NCHITTEST, WM_PAINT, WM_SETTINGCHANGE,
    WM_SIZE, WM_SYSCOLORCHANGE, WM_SYSKEYDOWN, WM_THEMECHANGED, WM_TIMER, WS_CLIPCHILDREN,
    WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_OVERLAPPEDWINDOW, WS_POPUP,
};
use windows_core::{w, PCWSTR};

const MAIN_CLASS: PCWSTR = w!("hajime.settings");
const FLYOUT_CLASS: PCWSTR = w!("hajime.settings.flyout");
const ID_SEARCH: u16 = 1;
/// 前もって作る打つ欄の番号の始まり
const WARM_ID: u16 = 50;
/// つなぎ直しの時計の番号
const RECONNECT_TIMER: usize = 1;
/// 読み込みのスレッドが終わった知らせ
const WM_LOADED: u32 = WM_APP + 20;
/// 測る手順を 1 つ進める知らせ(--measure)
const WM_MEASURE: u32 = WM_APP + 21;
/// 手の空いたときに打つ欄を前もって作る知らせ
const WM_WARM: u32 = WM_APP + 24;
/// 前もって作っておく打つ欄の数(1 ページの欄の数の上限．記号のページの 6 つに少し足す)
const WARM_FIELDS: usize = 8;
/// 入力欄の書体(本文と同じ書体を GDI で)
const FIELD_FACE: &str = "Yu Gothic UI";

/// 左の一覧の幅(窓が狭いときは窓の半分)
fn nav_width(width: f32) -> f32 {
    size::NAV_WIDTH.min(width / 2.0)
}

/// フォーカスのあるところ
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Focus {
    Search,
    Nav,
    Page(Element),
}

/// ポインターを載せている・押しているところ
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Target {
    Nav(usize),
    NavScrollbar,
    PageScrollbar,
    Page(Element),
    /// 部品の中のスクロールバー(表・長い文)
    InnerScrollbar(Element),
}

/// 開いているドロップダウンの一覧
struct Flyout {
    element: Element,
    window: Window,
    surface: Surface,
    items: Vec<String>,
    selected: Option<usize>,
    hover: Option<usize>,
    scroll: Scroller,
    opened: Tween,
    /// 一覧の大きさ(DIP)
    width: f32,
    height: f32,
}

/// 読み込みのスレッドが置いた結果(つながらなければ None)
type Loaded = Arc<Mutex<Option<Option<SettingsModel<Store>>>>>;

pub struct App {
    pub(super) window: Window,
    search: Window,
    graphics: Graphics,
    surface: Surface,
    pub(super) theme: Theme,
    /// 窓の地を Mica にしているか(Windows 11 22H2 から．高コントラストでは使わない)
    mica: bool,
    /// 窓を描いたあとに検索欄を描き直したか．検索欄は自分の面を持つ窓で，窓が出る前に描いた絵は画面に出ない
    search_painted: bool,
    /// --theme で決めた見た目(OS の設定を読まない)
    forced_theme: Option<ForcedTheme>,
    animations: bool,
    pub(super) catalog: Catalog,
    connect: fn(&Timing) -> Option<Store>,
    pub(super) model: Option<SettingsModel<Store>>,
    loaded: Loaded,
    loading: bool,
    pub(super) extras: Extras,
    /// 登録した単語(表の行と同じ並び．消すときに引く)
    pub(super) dictionary: Vec<DictionaryEntry>,
    /// 項目ごとの同期の表の行(表と同じ並び．切り替えるときに引く)
    pub(super) sync_rows: Vec<crate::sync::FieldRow>,
    /// 同期の状態の値(「sync.」の道筋)
    pub(super) sync_values: crate::store::Fields,
    /// 外観のページで編集しているカスタムテーマの id
    pub(super) editing_theme: Option<String>,
    /// 外観の見本を描くもの(初めて描くときに作る．作れなければ見本を描かない)
    preview: Option<candidate_ui::app::preview::Preview>,
    preview_pixels: Option<(String, PreviewPixels)>,
    /// 記号の決まり(表の行と同じ並び．外す・切り替えるときに引く)
    pub(super) sequences: Vec<SymbolItem>,
    pub(super) readings: Vec<SymbolItem>,
    field_font: Option<ffi::Font>,
    field_brush: edit::Brush,
    /// 隠して使い回す打つ欄
    pool: Vec<Window>,
    nav: NavLayout,
    nav_scroll: Scroller,
    nav_hover: Vec<Tween>,
    /// 選んでいる項目の印の位置(項目の上端)
    nav_indicator: Tween,
    pub(super) view: PageView,
    scroll: Scroller,
    /// ページの入りの動き(0 から 1)
    enter: Tween,
    focus: Focus,
    focus_visible: bool,
    focused_edit: Option<Window>,
    hover: Option<Target>,
    pressed: Option<Target>,
    flyout: Option<Flyout>,
    started: Instant,
    /// 描いた時刻と描くのにかかった時間(測るとき)
    frames: Vec<(f64, f64)>,
    measuring: bool,
    /// ページを開く時間の内わけ(部品を作る・エンジンから読む・値を映して置く．測るとき)
    breakdown: (f64, f64, f64),
    measure: Option<Measurement>,
}

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}

/// 窓を作って見せる．メッセージの繰り返しは呼ぶ側が回す
pub fn open(
    catalog: Catalog,
    connect: fn(&Timing) -> Option<Store>,
    options: Options,
) -> Option<Window> {
    let started = options.started;
    ffi::register_class(MAIN_CLASS, Some(main_procedure), false);
    ffi::register_class(FLYOUT_CLASS, Some(flyout_procedure), true);
    let window = ffi::create(
        WINDOW_EX_STYLE::default(),
        MAIN_CLASS,
        settings::WINDOW_TITLE,
        WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
        (CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT),
        None,
        0,
    )?;
    let dpi = ffi::dpi(window);
    let theme = match options.theme {
        Some(forced) => forced.theme(dpi),
        None => Theme::load(dpi),
    };
    let graphics = Graphics::new().ok()?;
    let field_font = ffi::Font::new(FIELD_FACE, theme.px(size::BODY_FONT_SIZE));
    let search = field_font
        .as_ref()
        .and_then(|font| edit::create(window, ID_SEARCH, features::SEARCH, font))?;
    let mut pool = Vec::new();
    let view = PageView::new(
        window,
        field_font.as_ref()?,
        &mut pool,
        options.page.unwrap_or(Page::Input),
        &catalog,
        Availability::Loading,
    );
    let field_brush = edit::Brush::new(theme.palette.control);
    let app = App {
        window,
        search,
        graphics,
        surface: Surface::new(window),
        theme,
        mica: false,
        search_painted: false,
        forced_theme: options.theme,
        animations: ffi::animations_enabled(),
        catalog,
        connect,
        model: None,
        loaded: Arc::new(Mutex::new(None)),
        loading: false,
        extras: Extras::default(),
        dictionary: Vec::new(),
        sync_rows: Vec::new(),
        sync_values: crate::store::Fields::new(),
        editing_theme: None,
        preview: None,
        preview_pixels: None,
        sequences: Vec::new(),
        readings: Vec::new(),
        field_font,
        field_brush,
        pool,
        nav: NavLayout::new(""),
        nav_scroll: Scroller::default(),
        nav_hover: Vec::new(),
        nav_indicator: Tween::fixed(0.0),
        view,
        scroll: Scroller::default(),
        enter: Tween::fixed(1.0),
        focus: Focus::Nav,
        focus_visible: false,
        focused_edit: None,
        hover: None,
        pressed: None,
        flyout: None,
        started,
        frames: Vec::new(),
        measuring: options.measure.is_some(),
        breakdown: (0.0, 0.0, 0.0),
        measure: options.measure.map(Measurement::new),
    };
    APP.with(|cell| *cell.borrow_mut() = Some(app));
    uia::install(uia::Hooks {
        nodes: accessibility_nodes,
        act: accessibility_act,
    });
    with_app(|app| {
        app.apply_theme();
        app.nav_hover = vec![Tween::fixed(0.0); app.nav.items.len()];
        if let Some(index) = app.nav.position(app.view.page) {
            app.nav_indicator.snap(app.nav.items[index].top);
        }
        ffi::resize(
            window,
            app.theme.px(size::WINDOW_WIDTH),
            app.theme.px(size::WINDOW_HEIGHT),
        );
        app.arrange();
        app.start_loading();
    });
    // 起動した側が決めた見せ方(前に出さないなど)に従う
    ffi::show_default(window);
    Some(window)
}

/// --theme で決める見た目．OS の設定を変えずに見本を撮る
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ForcedTheme {
    Light,
    Dark,
    /// 高コントラスト(OS の色で描き，Mica を使わない)
    Contrast,
}

impl ForcedTheme {
    pub(super) fn theme(self, dpi: u32) -> Theme {
        match self {
            Self::Light => Theme::fixed(false, dpi),
            Self::Dark => Theme::fixed(true, dpi),
            Self::Contrast => Theme::contrast(dpi),
        }
    }
}

/// 起動の引数で決めること
pub struct Options {
    pub started: Instant,
    /// 見た目を決める(見本の撮影)．None なら OS の設定
    pub theme: Option<ForcedTheme>,
    /// 測った結果を書くファイル
    pub measure: Option<std::path::PathBuf>,
    /// 初めに開くページ(見本の撮影)
    pub page: Option<Page>,
}

/// 状態を借りて f を呼ぶ．借りられない(手続きの中から呼ばれた)ときは None
pub(super) fn with_app<T>(f: impl FnOnce(&mut App) -> T) -> Option<T> {
    APP.with(|cell| {
        let mut borrowed = cell.try_borrow_mut().ok()?;
        borrowed.as_mut().map(f)
    })
}

impl App {
    pub(super) fn now(&self) -> f64 {
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

    fn apply_theme(&mut self) {
        ffi::set_dark_title_bar(self.window, self.theme.dark);
        // 高コントラストのときは OS の色で塗るので Mica にしない
        self.mica = ffi::set_mica(self.window, !self.theme.high_contrast);
        // 先に作った検索欄は，地を変えたあとに描き直す(自分の面を持つ窓なので，前の絵が残る)
        self.search_painted = false;
        edit::set_placeholder_color(self.theme.palette.text_secondary);
        self.field_brush = edit::Brush::new(self.theme.palette.control);
        if let Some(font) = &self.field_font {
            ffi::set_font(self.search, font);
            for window in self.view.windows() {
                ffi::set_font(window, font);
            }
        }
    }

    /// 色・書体を作り直す(OS の設定や DPI が変わったとき)
    fn reload_theme(&mut self, dpi: u32) {
        let font_changed = dpi != self.theme.dpi;
        self.theme = match self.forced_theme {
            Some(forced) => forced.theme(dpi),
            None => Theme::load(dpi),
        };
        self.animations = ffi::animations_enabled();
        if font_changed {
            self.field_font = ffi::Font::new(FIELD_FACE, self.theme.px(size::BODY_FONT_SIZE));
        }
        self.preview_pixels = None;
        self.apply_theme();
        self.arrange();
        ffi::invalidate(self.window);
    }

    // MARK: - 読み込み

    /// エンジンへの接続と設定の読み込みを別のスレッドで始める(窓は先に出しておく)
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
            .name("settings-loader".into())
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

    /// 読み込みのスレッドが終わった
    fn finish_loading(&mut self) {
        self.loading = false;
        let Some(model) = self.loaded.lock().ok().and_then(|mut slot| slot.take()) else {
            return;
        };
        match model {
            Some(model) => {
                self.model = Some(model);
                ffi::kill_timer(self.window, RECONNECT_TIMER);
                let page = self.view.page;
                self.open_page(page);
                ffi::post(self.window, WM_WARM, 0, 0);
                if let Some(measurement) = &mut self.measure {
                    measurement.content = Some(self.started.elapsed().as_secs_f64() * 1000.0);
                    ffi::post(self.window, WM_MEASURE, 0, 0);
                }
            }
            None => self.disconnect(),
        }
    }

    pub(super) fn availability(&self) -> Availability {
        match (&self.model, self.loading) {
            (Some(_), _) => Availability::Ready,
            (None, true) if self.view.availability == Availability::Loading => {
                Availability::Loading
            }
            (None, true) => Availability::Unavailable,
            (None, false) => Availability::Unavailable,
        }
    }

    /// エンジンが答えなくなった．画面は閉じずに知らせを出し，間隔をおいてつなぎ直す
    pub(super) fn disconnect(&mut self) {
        self.model = None;
        let page = self.view.page;
        self.open_page(page);
        let interval = self.catalog.timing.reconnect_interval().as_millis();
        ffi::set_timer(
            self.window,
            RECONNECT_TIMER,
            u32::try_from(interval).unwrap_or(u32::MAX),
        );
    }

    /// エンジンが設定を変えたかもしれないので読み直す．つながっていなければつなぎ直す
    fn reload(&mut self) {
        match &mut self.model {
            Some(model) => {
                if model.reload().is_err() {
                    self.disconnect();
                    return;
                }
                self.read_extras();
                self.refresh();
            }
            None => self.start_loading(),
        }
    }

    // MARK: - ページ

    pub(super) fn open_page(&mut self, page: Page) {
        let start = Instant::now();
        let availability = self.availability();
        let Some(font) = &self.field_font else { return };
        let mut pool = std::mem::take(&mut self.pool);
        let view = PageView::new(
            self.window,
            font,
            &mut pool,
            page,
            &self.catalog,
            availability,
        );
        std::mem::replace(&mut self.view, view).release(&mut pool);
        self.pool = pool;
        let built = start.elapsed().as_secs_f64() * 1000.0;
        if let Focus::Page(_) = self.focus {
            self.focus = Focus::Nav;
        }
        self.focused_edit = None;
        self.close_flyout();
        self.hover = None;
        self.scroll = Scroller::default();
        let now = self.now();
        self.enter = Tween::new(
            0.0,
            1.0,
            now,
            self.duration(motion::PAGE_ENTER),
            Easing::DECELERATE,
        );
        if let Some(index) = self.nav.position(page) {
            let top = self.nav.items[index].top;
            let duration = self.duration(motion::NAV_INDICATOR);
            self.nav_indicator
                .retarget(top, now, duration, Easing::STANDARD);
        }
        self.read_extras();
        let read = start.elapsed().as_secs_f64() * 1000.0;
        self.refresh();
        if self.measuring {
            let refreshed = start.elapsed().as_secs_f64() * 1000.0;
            self.breakdown = (built, read - built, refreshed - read);
        }
    }

    /// 値を部品に映して置き直す
    pub(super) fn refresh(&mut self) {
        let now = self.now();
        if let Some(model) = &self.model {
            if self.view.page == Page::Keys {
                self.extras.keymap_report = super::actions::keymap_report(model);
            }
            if self.view.page == Page::Appearance && self.extras.fonts.is_empty() {
                self.extras.fonts = candidate_ui::app::fonts::installed();
            }
            // 同期の状態と，編集しているカスタムテーマの値を重ねる
            let entries = crate::themes::entries(model.value(crate::themes::THEMES));
            let editing = self
                .editing_theme
                .as_deref()
                .and_then(|id| entries.iter().find(|entry| entry.id == id));
            let mut extra = self.sync_values.clone();
            extra.extend(crate::themes::values(editing, &self.extras.theme_report));
            self.extras.extra = extra;
            let values = page::WithExtras {
                values: model,
                extra: &self.extras.extra,
            };
            self.view.sync(&values, &self.extras, now);
        }
        self.preview_pixels = None;
        self.arrange();
    }

    /// 窓の大きさに合わせて置き直す
    pub(super) fn arrange(&mut self) {
        let (width, height) = self.size();
        let nav_width = nav_width(width);
        let content = self.view.arrange(width - nav_width, &self.graphics);
        self.scroll.set_extent(content, height);
        let nav_top = self.nav_top();
        self.nav_scroll
            .set_extent(self.nav.height, height - nav_top);
        self.place_search();
        self.place_fields();
        ffi::invalidate(self.window);
    }

    /// 検索欄の枠(DIP)
    fn search_rect(&self) -> Rect {
        let (width, _) = self.size();
        let padding = size::NAV_PADDING_X;
        Rect::new(
            padding,
            size::PAGE_PADDING_TOP,
            nav_width(width) - padding * 2.0,
            size::SEARCH_HEIGHT,
        )
    }

    fn nav_top(&self) -> f32 {
        let search = self.search_rect();
        search.max_y() + size::PAGE_PADDING_TOP
    }

    fn place_search(&self) {
        let rect = self.search_rect();
        let line = size::BODY_LINE_HEIGHT;
        let x = rect.x + size::FIELD_PADDING_X;
        let y = rect.y + (rect.height - line) / 2.0;
        // 右に虫めがねの絵を置く分を空ける
        let width = rect.width - size::FIELD_PADDING_X * 3.0 - size::CHEVRON_SIZE;
        let left = self.theme.px(x);
        let top = self.theme.px(y);
        ffi::place(
            self.search,
            left,
            top,
            self.theme.px(x + width) - left,
            self.theme.px(y + line) - top,
        );
        ffi::show(self.search, true);
    }

    /// ページの打つ欄を今の送りの位置に置く
    fn place_fields(&self) {
        let (width, _) = self.size();
        let now = self.now();
        let entering = self.enter.running(now);
        self.view.place_fields(
            &self.theme,
            (nav_width(width), 0.0),
            self.scroll.offset(now),
            entering,
        );
    }

    /// 検索の言葉に合うページを左の一覧に並べる．開いているページが一覧から消えたら先頭のページを開く
    fn fill_nav(&mut self) {
        let query = ffi::window_text(self.search);
        self.nav = NavLayout::new(&query);
        self.nav_hover = vec![Tween::fixed(0.0); self.nav.items.len()];
        match self.nav.position(self.view.page) {
            Some(index) => self.nav_indicator.snap(self.nav.items[index].top),
            None => {
                if let Some(first) = self.nav.items.first().map(|item| item.page) {
                    self.open_page(first);
                    self.nav_indicator.snap(self.nav.items[0].top);
                }
            }
        }
        self.arrange();
    }

    // MARK: - 描く

    fn animating(&self, now: f64) -> bool {
        self.enter.running(now)
            || self.nav_indicator.running(now)
            || self.nav_hover.iter().any(|tween| tween.running(now))
            || self.scroll.animating(now)
            || self.nav_scroll.animating(now)
            || self.view.animating(now)
            || self.availability() == Availability::Loading
            || self
                .flyout
                .as_ref()
                .is_some_and(|flyout| flyout.opened.running(now) || flyout.scroll.animating(now))
    }

    fn paint(&mut self) {
        let now = self.now();
        self.update_preview();
        let (width, height) = self.size();
        let theme = self.theme;
        // Mica のときは地を透明にし，Mica を見せる(カードと部品は不透明のまま描く)
        let clear = if self.mica {
            Color::from(theme.palette.background).with_alpha(0.0)
        } else {
            Color::from(theme.palette.background)
        };
        let size = ffi::client_size(self.window);
        let preview = self.preview_pixels.as_ref().map(|(_, pixels)| pixels);
        let graphics = &self.graphics;
        let nav = &self.nav;
        let view = &self.view;
        let scroll = &self.scroll;
        let nav_scroll = &self.nav_scroll;
        let state = PaintState {
            theme: &theme,
            now,
            width,
            height,
            focus: self.focus,
            focus_visible: self.focus_visible,
            focused_edit: self.focused_edit,
            pressed: self.pressed,
            open: self.flyout.as_ref().map(|flyout| flyout.element),
            nav_hover: &self.nav_hover,
            nav_indicator: self.nav_indicator.value(now),
            enter: self.enter.value(now),
            availability: self.availability(),
            search: self.search_rect(),
            nav_top: self.nav_top(),
        };
        let mut cpu = 0.0;
        let drawn = self
            .surface
            .draw(graphics, size, theme.dpi, clear, preview, |canvas| {
                let start = Instant::now();
                paint_window(canvas, &state, nav, nav_scroll, view, scroll);
                cpu = start.elapsed().as_secs_f64() * 1000.0;
            });
        if drawn.is_err() {
            return;
        }
        if let Some(measurement) = &mut self.measure {
            measurement.shown.get_or_insert(now);
        }
        if self.measuring {
            self.frames.push((now, cpu));
        }
        // 入りの動きが終わったら打つ欄を出す．送っているあいだは欄も送る
        self.place_fields();
        if !self.search_painted {
            self.search_painted = true;
            ffi::invalidate(self.search);
        }
        // 描いた時刻で動いていたら，もう 1 フレーム描く．描き終えた時刻で決めると，動きが終わる直前の
        // フレーム(入りの動きの途中の薄い絵)のまま止まり，入りの動きのあとに出す打つ欄も出ない
        if self.animating(now) {
            // 画面の合成に合わせて次のフレームを描く(速く回しすぎない)
            ffi::wait_for_compositor();
            ffi::invalidate(self.window);
        }
    }

    /// 外観の見本の画像を作り直す(見本の中身か大きさが変わったときだけ)
    fn update_preview(&mut self) {
        let Some(rect) = self.view.preview_rect() else {
            self.preview_pixels = None;
            return;
        };
        let Some(model) = &self.model else { return };
        let entries = crate::themes::entries(model.value(crate::themes::THEMES));
        let shown = self
            .editing_theme
            .clone()
            .or_else(|| {
                model
                    .value(crate::themes::ACTIVE)
                    .and_then(serde_json::Value::as_str)
                    .map(str::to_string)
            })
            .and_then(|id| entries.iter().find(|entry| entry.id == id))
            .and_then(|entry| crate::themes::to_wire(&entry.value));
        let theme_name = model
            .value("theme")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("automatic")
            .to_string();
        let font_size = model
            .value("candidateFontSize")
            .and_then(serde_json::Value::as_f64)
            .map_or(tokens::size::candidate::FONT_SIZE, |size| size as f32);
        let width = u32::try_from(self.theme.px(rect.width)).unwrap_or(0);
        let height = u32::try_from(self.theme.px(rect.height)).unwrap_or(0);
        // カスタムテーマはすべての項目(元のテーマ・色・書体・角の丸み)で見分ける．一部だけで見分けると，
        // ほかの項目を変えても見本を作り直さず，変えたことがすぐ映らない
        let key = format!(
            "{theme_name}|{}|{font_size}|{}|{}|{width}x{height}",
            shown
                .as_ref()
                .and_then(|theme| serde_json::to_string(theme).ok())
                .unwrap_or_default(),
            self.theme.dark,
            self.theme.dpi,
        );
        if self
            .preview_pixels
            .as_ref()
            .is_some_and(|(current, _)| *current == key)
        {
            return;
        }
        if self.preview.is_none() {
            self.preview = candidate_ui::app::preview::Preview::new().ok();
        }
        let Some(preview) = &self.preview else { return };
        let look = candidate_ui::theme::SystemLook {
            dark: self.theme.dark,
            accent: None,
            increase_contrast: ffi::high_contrast(),
            backdrop: false,
        };
        let resolved =
            candidate_ui::theme::ResolvedTheme::resolve(&theme_name, shown.as_ref(), &look);
        let scale = self.theme.dpi as f32 / ffi::BASE_DPI as f32;
        let generation = self
            .preview_pixels
            .as_ref()
            .map_or(1, |(_, pixels)| pixels.generation + 1);
        // 見本は少し内側に描く(カードの縁と重ねない)
        let request = d2d::PreviewRequest {
            theme: &resolved,
            font_size,
            dark: self.theme.dark,
            scale,
            background: self.theme.palette.card,
            shown: candidate_ui::app::preview::Shown::Sample,
            placement: candidate_ui::app::preview::Placement::Center,
        };
        let Some(pixels) = d2d::render_preview(preview, width, height, &request) else {
            return;
        };
        self.preview_pixels = Some((
            key,
            PreviewPixels {
                generation,
                width,
                height,
                pixels,
            },
        ));
    }

    // MARK: - ポインター

    /// 窓の中の点(DIP)にあるもの
    fn target_at(&self, x: f32, y: f32) -> Option<Target> {
        let (width, height) = self.size();
        let nav_width = nav_width(width);
        let now = self.now();
        if x < nav_width {
            let nav_top = self.nav_top();
            if y < nav_top {
                return None;
            }
            if self.nav_scroll.can_scroll() && x >= nav_width - size::SCROLLBAR_HIT {
                return Some(Target::NavScrollbar);
            }
            let local = y - nav_top + self.nav_scroll.offset(now);
            return self.nav.hit(local).map(Target::Nav);
        }
        if self.availability() != Availability::Ready {
            return None;
        }
        if self.scroll.can_scroll() && x >= width - size::SCROLLBAR_HIT && y < height {
            return Some(Target::PageScrollbar);
        }
        let page_x = x - nav_width;
        let page_y = y + self.scroll.offset(now);
        let element = self.view.hit(page_x, page_y)?;
        if matches!(element.part, Part::Table | Part::Text) {
            if let Some(rect) = self.view.rect(element) {
                if page_x >= rect.max_x() - size::SCROLLBAR_HIT {
                    return Some(Target::InnerScrollbar(element));
                }
            }
        }
        Some(Target::Page(element))
    }

    fn point(&self, lparam: LPARAM) -> (f32, f32) {
        let x = (lparam.0 & 0xffff) as i16 as i32;
        let y = ((lparam.0 >> 16) & 0xffff) as i16 as i32;
        (self.theme.dip(x), self.theme.dip(y))
    }

    fn mouse_move(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        let now = self.now();
        let (width, height) = self.size();
        // つまみをつかんでいれば動かす
        match self.pressed {
            Some(Target::PageScrollbar) => {
                self.scroll.drag(
                    y - size::SCROLLBAR_MARGIN,
                    height - size::SCROLLBAR_MARGIN * 2.0,
                    now,
                );
                self.place_fields();
                ffi::invalidate(self.window);
                return;
            }
            Some(Target::NavScrollbar) => {
                let top = self.nav_top();
                self.nav_scroll.drag(y - top, height - top, now);
                ffi::invalidate(self.window);
                return;
            }
            _ => {}
        }
        let target = self.target_at(x, y);
        if target != self.hover {
            self.hover = target;
            for (index, tween) in self.nav_hover.iter_mut().enumerate() {
                let on = target == Some(Target::Nav(index));
                tween.retarget(
                    if on { 1.0 } else { 0.0 },
                    now,
                    f64::from(motion::HOVER),
                    Easing::LINEAR,
                );
            }
            let element = match target {
                Some(Target::Page(element)) => Some(element),
                _ => None,
            };
            self.view.set_hover(element, now);
            let inner = match target {
                Some(Target::InnerScrollbar(element)) => Some(element),
                _ => None,
            };
            self.view.set_scrollbar_hover(inner, now);
            self.scroll
                .set_hover(target == Some(Target::PageScrollbar), now);
            self.nav_scroll
                .set_hover(target == Some(Target::NavScrollbar), now);
            ffi::track_leave(self.window);
        }
        // 表の上なら行にも印を付ける
        let table_hover = match target {
            Some(Target::Page(element)) if element.part == Part::Table => {
                let page_y = y + self.scroll.offset(now);
                self.view
                    .table_position(element.row, page_y, now)
                    .map(|position| (element.row, position))
            }
            _ => None,
        };
        let changed = self.view.set_table_hover(table_hover);
        let _ = width;
        if changed || self.animating(now) || target.is_some() {
            ffi::invalidate(self.window);
        }
    }

    fn mouse_leave(&mut self) {
        let now = self.now();
        self.hover = None;
        for tween in &mut self.nav_hover {
            tween.retarget(0.0, now, f64::from(motion::HOVER), Easing::LINEAR);
        }
        self.view.set_hover(None, now);
        self.view.set_scrollbar_hover(None, now);
        self.view.set_table_hover(None);
        self.scroll.set_hover(false, now);
        self.nav_scroll.set_hover(false, now);
        ffi::invalidate(self.window);
    }

    fn mouse_down(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        let now = self.now();
        let (_, height) = self.size();
        let target = self.target_at(x, y);
        let reopening = matches!(
            (target, &self.flyout),
            (Some(Target::Page(element)), Some(flyout)) if flyout.element == element
        );
        if self.flyout.is_some() {
            self.close_flyout();
            if reopening {
                // 開いていたドロップダウンを押したら閉じるだけ
                return;
            }
        }
        self.focus_visible = false;
        self.pressed = target;
        ffi::capture(self.window);
        match target {
            Some(Target::PageScrollbar) => {
                self.scroll.press(
                    y - size::SCROLLBAR_MARGIN,
                    height - size::SCROLLBAR_MARGIN * 2.0,
                    now,
                );
                self.place_fields();
            }
            Some(Target::NavScrollbar) => {
                let top = self.nav_top();
                self.nav_scroll.press(y - top, height - top, now);
            }
            Some(Target::InnerScrollbar(element)) => self.set_focus(Focus::Page(element)),
            Some(Target::Nav(_)) => self.set_focus(Focus::Nav),
            Some(Target::Page(element)) => {
                if self.view.edit(element).is_none() {
                    self.set_focus(Focus::Page(element));
                }
                if element.part == Part::Table {
                    let page_y = y + self.scroll.offset(now);
                    if let Some(position) = self.view.table_position(element.row, page_y, now) {
                        let (control, shift) = ffi::modifiers();
                        let event = self.view.table_click(element.row, position, control, shift);
                        self.dispatch(event);
                    }
                }
            }
            None => {}
        }
        ffi::invalidate(self.window);
    }

    fn mouse_up(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        let now = self.now();
        let pressed = self.pressed.take();
        ffi::release_capture();
        self.scroll.release(now);
        self.nav_scroll.release(now);
        let target = self.target_at(x, y);
        match (pressed, target) {
            (Some(Target::Nav(index)), Some(Target::Nav(over))) if index == over => {
                if let Some(page) = self.nav.items.get(index).map(|item| item.page) {
                    if page != self.view.page {
                        self.open_page(page);
                    }
                }
            }
            (Some(Target::Page(element)), Some(Target::Page(over))) if element == over => {
                self.press(element);
            }
            _ => {}
        }
        ffi::invalidate(self.window);
    }

    /// 部品を押した(クリック・Space・Enter)
    fn press(&mut self, element: Element) {
        if self.view.is_dropdown(element) {
            self.open_flyout(element);
            return;
        }
        if element.part == Part::Table || element.part == Part::Text {
            return;
        }
        if let Some(window) = self.view.edit(element) {
            ffi::focus(window);
            return;
        }
        let now = self.now();
        let event = self.view.activate(element, now);
        self.dispatch(event);
    }

    fn wheel(&mut self, wparam: WPARAM, lparam: LPARAM) {
        let delta = ((wparam.0 >> 16) & 0xffff) as u16 as i16 as i32;
        let amount = scroll::wheel_delta(delta, WHEEL_DELTA as i32);
        let now = self.now();
        if let Some(flyout) = &mut self.flyout {
            flyout.scroll.scroll_by(amount, now);
            ffi::invalidate(flyout.window);
            return;
        }
        // ホイールの位置は画面の座標
        let screen_x = (lparam.0 & 0xffff) as i16 as i32;
        let screen_y = ((lparam.0 >> 16) & 0xffff) as i16 as i32;
        let (client_x, client_y) = ffi::to_client(self.window, screen_x, screen_y);
        let (x, y) = (self.theme.dip(client_x), self.theme.dip(client_y));
        let (width, _) = self.size();
        if x < nav_width(width) {
            self.nav_scroll.scroll_by(amount, now);
        } else {
            let inside = match self.target_at(x, y) {
                Some(Target::Page(element) | Target::InnerScrollbar(element)) => {
                    self.view.scroll_inside(element, amount, now)
                }
                _ => false,
            };
            if !inside {
                self.scroll.scroll_by(amount, now);
            }
        }
        ffi::invalidate(self.window);
    }

    // MARK: - キーボード

    fn set_focus(&mut self, focus: Focus) {
        self.focus = focus;
        if let Some(id) = self.focus_id() {
            uia::focus_changed(self.window, id);
        }
        let window = match focus {
            Focus::Search => Some(self.search),
            Focus::Page(element) => self.view.edit(element),
            Focus::Nav => None,
        };
        match window {
            Some(window) => ffi::focus(window),
            None => {
                if ffi::focused() != Some(self.window) {
                    ffi::focus(self.window);
                }
            }
        }
        // 見えるところまで送る
        if let Focus::Page(element) = focus {
            if let Some(rect) = self.view.rect(element) {
                let now = self.now();
                let margin = size::SECTION_GAP;
                self.scroll
                    .reveal(rect.y - margin, rect.max_y() + margin, now);
            }
        }
        ffi::invalidate(self.window);
    }

    /// Tab で次(back なら前)へ動かす
    fn move_focus(&mut self, back: bool) {
        let mut stops = vec![Focus::Search, Focus::Nav];
        if self.availability() == Availability::Ready {
            stops.extend(self.view.focusable().into_iter().map(Focus::Page));
        }
        let current = stops.iter().position(|stop| *stop == self.focus);
        if let Some(next) = crate::ui::cycle(current, stops.len(), back) {
            self.focus_visible = true;
            self.set_focus(stops[next]);
        }
    }

    /// キーを押した．扱ったら true
    fn key(&mut self, key: u16) -> bool {
        let now = self.now();
        let (control, shift) = ffi::modifiers();
        if self.flyout.is_some() {
            return self.flyout_key(key);
        }
        if key == VK_TAB.0 {
            self.move_focus(shift);
            return true;
        }
        self.focus_visible = true;
        match self.focus {
            Focus::Nav => {
                let current = self.nav.position(self.view.page);
                let next = match key {
                    k if k == VK_UP.0 => self.nav.step(current, -1),
                    k if k == VK_DOWN.0 => self.nav.step(current, 1),
                    k if k == VK_HOME.0 => self.nav.step(None, 1),
                    k if k == VK_END.0 => self.nav.step(None, -1),
                    _ => return self.page_key(key, control),
                };
                if let Some(page) = next
                    .and_then(|index| self.nav.items.get(index))
                    .map(|item| item.page)
                {
                    if page != self.view.page {
                        self.open_page(page);
                    }
                    if let Some(index) = self.nav.position(page) {
                        let item = self.nav.items[index];
                        self.nav_scroll
                            .reveal(item.top, item.top + item.height, now);
                    }
                }
                ffi::invalidate(self.window);
                true
            }
            Focus::Page(element) => {
                let handled = self.element_key(element, key, shift);
                handled || self.page_key(key, control)
            }
            Focus::Search => false,
        }
    }

    /// フォーカスのある部品でのキー
    fn element_key(&mut self, element: Element, key: u16, shift: bool) -> bool {
        let now = self.now();
        match element.part {
            Part::Table => {
                let page = self.view.table_page(element.row);
                let movement = match key {
                    k if k == VK_UP.0 => Move::Up,
                    k if k == VK_DOWN.0 => Move::Down,
                    k if k == VK_PRIOR.0 => Move::PageUp(page),
                    k if k == VK_NEXT.0 => Move::PageDown(page),
                    k if k == VK_HOME.0 => Move::Home,
                    k if k == VK_END.0 => Move::End,
                    k if k == VK_DELETE.0 => {
                        // 選んだ行を消すボタンを押す
                        let remove = Element {
                            row: element.row,
                            part: Part::Top(1),
                        };
                        if self.view.enabled(remove) {
                            let event = self.view.activate(remove, now);
                            self.dispatch(event);
                        }
                        return true;
                    }
                    _ => return false,
                };
                let event = self.view.table_key(element.row, movement, shift, now);
                self.dispatch(event);
                ffi::invalidate(self.window);
                true
            }
            Part::Text => {
                let step = size::SCROLL_LINE;
                let delta = match key {
                    k if k == VK_UP.0 => -step,
                    k if k == VK_DOWN.0 => step,
                    k if k == VK_PRIOR.0 => -step * 4.0,
                    k if k == VK_NEXT.0 => step * 4.0,
                    _ => return false,
                };
                self.view.scroll_inside(element, delta, now);
                ffi::invalidate(self.window);
                true
            }
            _ if self.view.is_dropdown(element) => {
                let (items, selected) = self.view.dropdown_items(element);
                match key {
                    k if k == VK_SPACE.0 || k == VK_RETURN.0 || k == VK_F4.0 => {
                        self.open_flyout(element);
                        true
                    }
                    // 閉じたまま上下で選び直す(WinUI の ComboBox と同じ)
                    k if k == VK_UP.0 || k == VK_DOWN.0 => {
                        let current = selected.unwrap_or(0);
                        let next = if k == VK_UP.0 {
                            current.saturating_sub(1)
                        } else {
                            (current + 1).min(items.len().saturating_sub(1))
                        };
                        if Some(next) != selected && !items.is_empty() {
                            let event = self.view.choose(element, next);
                            self.dispatch(event);
                        }
                        true
                    }
                    _ => false,
                }
            }
            _ => {
                if key == VK_SPACE.0 || key == VK_RETURN.0 {
                    self.press(element);
                    return true;
                }
                false
            }
        }
    }

    /// ページを送るキー
    fn page_key(&mut self, key: u16, control: bool) -> bool {
        let now = self.now();
        let (_, height) = self.size();
        let line = size::SCROLL_LINE;
        match key {
            k if k == VK_PRIOR.0 => self.scroll.scroll_by(-height * 0.8, now),
            k if k == VK_NEXT.0 => self.scroll.scroll_by(height * 0.8, now),
            k if k == VK_HOME.0 && control => self.scroll.scroll_to(0.0, now),
            k if k == VK_END.0 && control => self.scroll.scroll_to(f32::MAX, now),
            k if k == VK_UP.0 && self.focus != Focus::Nav => self.scroll.scroll_by(-line, now),
            k if k == VK_DOWN.0 && self.focus != Focus::Nav => self.scroll.scroll_by(line, now),
            _ => return false,
        }
        ffi::invalidate(self.window);
        true
    }

    /// 頼みを行い，あとのこと(知らせ・ファイルを選ぶ窓)をする
    pub(super) fn dispatch(&mut self, event: Option<Event>) {
        let Some(event) = event else {
            ffi::invalidate(self.window);
            return;
        };
        // 確かめる操作は，窓の外(手続きを返してから)で確かめる
        let window = self.window;
        if super::actions::confirmation(&event).is_some() {
            PENDING.with(|pending| *pending.borrow_mut() = Some(event));
            ffi::post(window, WM_CONFIRM, 0, 0);
            return;
        }
        let after = self.handle(event);
        if after.is_some() {
            AFTER.with(|slot| *slot.borrow_mut() = after);
            ffi::post(window, WM_AFTER, 0, 0);
        }
        ffi::invalidate(self.window);
    }

    // MARK: - 読み上げ

    /// 読み上げの番号．左の一覧の項目は 1 から，ページの部品は NODE_PAGE から
    fn focus_id(&self) -> Option<i32> {
        match self.focus {
            Focus::Nav => self
                .nav
                .position(self.view.page)
                .and_then(|index| i32::try_from(index).ok())
                .map(|index| index + 1),
            Focus::Page(element) if self.view.edit(element).is_none() => {
                Some(NODE_PAGE + PageView::element_id(element))
            }
            _ => None,
        }
    }

    /// 窓の中の DIP の四角を画面のピクセルの四角(左・上・幅・高さ)にする
    fn screen_rect(&self, rect: Rect) -> (i32, i32, i32, i32) {
        let left = self.theme.px(rect.x);
        let top = self.theme.px(rect.y);
        let (x, y) = ffi::to_screen(self.window, left, top);
        (
            x,
            y,
            self.theme.px(rect.max_x()) - left,
            self.theme.px(rect.max_y()) - top,
        )
    }

    fn nodes(&self) -> Vec<uia::Node> {
        let now = self.now();
        let (width, _) = self.size();
        let nav_width = nav_width(width);
        let nav_top = self.nav_top();
        let nav_offset = self.nav_scroll.offset(now);
        let mut nodes = vec![uia::Node {
            id: NODE_SEARCH,
            role: uia::Role::Edit,
            name: features::SEARCH.to_string(),
            rect: self.screen_rect(self.search_rect()),
            enabled: true,
            focused: self.focus == Focus::Search,
            toggled: None,
            expanded: None,
            value: None,
            selected: None,
            host: Some(self.search),
        }];
        // 見えている範囲の外の項目も入れる(読み上げの側が送って読めるように)
        for (index, item) in self.nav.items.iter().enumerate() {
            let top = nav_top + item.top - nav_offset;
            let selected = item.page == self.view.page;
            nodes.push(uia::Node {
                id: i32::try_from(index).unwrap_or(0) + 1,
                role: uia::Role::ListItem,
                name: item.page.title().to_string(),
                rect: self.screen_rect(Rect::new(0.0, top, nav_width, item.height)),
                enabled: true,
                focused: self.focus == Focus::Nav && selected,
                toggled: None,
                expanded: None,
                value: None,
                selected: Some(selected),
                host: None,
            });
        }
        if self.availability() != Availability::Ready {
            return nodes;
        }
        let offset = self.scroll.offset(now);
        for element in self.view.elements() {
            let Some(described) = self.view.describe(element) else {
                continue;
            };
            let Some(rect) = self.view.rect(element) else {
                continue;
            };
            let mut host = None;
            let (role, toggled, expanded, value) = match described {
                // 打つ欄は標準の EDIT を元にする(中身と操作は EDIT が答える)
                Described::Edit => {
                    host = self.view.edit(element);
                    if host.is_none() {
                        continue;
                    }
                    (uia::Role::Edit, None, None, None)
                }
                Described::Button => (uia::Role::Button, None, None, None),
                Described::Toggle(on) => (uia::Role::CheckBox, Some(on), None, None),
                Described::Dropdown(label) => (
                    uia::Role::ComboBox,
                    None,
                    Some(
                        self.flyout
                            .as_ref()
                            .is_some_and(|flyout| flyout.element == element),
                    ),
                    Some(label),
                ),
                Described::Table => (uia::Role::List, None, None, None),
                Described::Text => (uia::Role::Document, None, None, None),
            };
            let window_rect =
                Rect::new(nav_width + rect.x, rect.y - offset, rect.width, rect.height);
            nodes.push(uia::Node {
                id: NODE_PAGE + PageView::element_id(element),
                role,
                name: self.view.name(element),
                rect: self.screen_rect(window_rect),
                enabled: self.view.enabled(element),
                focused: self.focus == Focus::Page(element),
                toggled,
                expanded,
                value,
                selected: None,
                host,
            });
        }
        nodes
    }

    fn accessibility_act(&mut self, id: i32, act: uia::Act) {
        if id == NODE_SEARCH {
            if act == uia::Act::Focus {
                self.set_focus(Focus::Search);
            }
            return;
        }
        if id < NODE_PAGE {
            let Some(page) = usize::try_from(id - 1)
                .ok()
                .and_then(|index| self.nav.items.get(index))
                .map(|item| item.page)
            else {
                return;
            };
            if page != self.view.page {
                self.open_page(page);
            }
            self.set_focus(Focus::Nav);
            return;
        }
        let Some(element) = self
            .view
            .focusable()
            .into_iter()
            .find(|element| NODE_PAGE + PageView::element_id(*element) == id)
        else {
            return;
        };
        match act {
            uia::Act::Focus => self.set_focus(Focus::Page(element)),
            uia::Act::Collapse => self.close_flyout(),
            uia::Act::Expand => self.open_flyout(element),
            uia::Act::Invoke | uia::Act::Toggle | uia::Act::Select => self.press(element),
        }
        ffi::invalidate(self.window);
    }

    // MARK: - ドロップダウン

    fn open_flyout(&mut self, element: Element) {
        let (items, selected) = self.view.dropdown_items(element);
        if items.is_empty() {
            return;
        }
        let Some(rect) = self.view.rect(element) else {
            return;
        };
        let now = self.now();
        let (width, _) = self.size();
        // ページの中の位置を窓の中の位置にする
        let left = nav_width(width) + rect.x;
        let top = rect.y - self.scroll.offset(now);
        let padding = size::FLYOUT_PADDING;
        let item = size::FLYOUT_ITEM_HEIGHT;
        let widest = items
            .iter()
            .map(|label| self.graphics.width(label, TextStyle::Body))
            .fold(0.0f32, f32::max);
        let flyout_width = rect
            .width
            .max(widest + size::FIELD_PADDING_X * 2.0 + size::NAV_INDICATOR_WIDTH * 2.0);
        let flyout_height = (items.len() as f32 * item + padding * 2.0).min(size::DROPDOWN_HEIGHT);
        let (screen_left, screen_top) = ffi::to_screen(
            self.window,
            self.theme.px(left),
            self.theme.px(top + rect.height + padding),
        );
        let (_, above_top) =
            ffi::to_screen(self.window, 0, self.theme.px(top - padding - flyout_height));
        let (_, work_top, _, work_bottom) = ffi::work_area(self.window);
        let pixel_height = self.theme.px(flyout_height);
        let y = if screen_top + pixel_height > work_bottom && above_top >= work_top {
            above_top
        } else {
            screen_top
        };
        let Some(window) = ffi::create(
            WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST,
            FLYOUT_CLASS,
            "",
            WS_POPUP,
            (screen_left, y, self.theme.px(flyout_width), pixel_height),
            Some(self.window),
            0,
        ) else {
            return;
        };
        ffi::set_round_corners(window);
        let mut scroll = Scroller::default();
        let viewport = flyout_height - padding * 2.0;
        scroll.set_extent(items.len() as f32 * item, viewport);
        if let Some(selected) = selected {
            let selected_top = selected as f32 * item;
            scroll.jump_to(selected_top - (viewport - item) / 2.0);
        }
        self.flyout = Some(Flyout {
            element,
            window,
            surface: Surface::new(window),
            items,
            selected,
            hover: selected,
            scroll,
            opened: Tween::new(
                0.0,
                1.0,
                now,
                self.duration(motion::FLYOUT),
                Easing::DECELERATE,
            ),
            width: flyout_width,
            height: flyout_height,
        });
        ffi::show_inactive(window);
        ffi::invalidate(window);
        ffi::invalidate(self.window);
    }

    pub(super) fn close_flyout(&mut self) {
        if let Some(flyout) = self.flyout.take() {
            ffi::destroy(flyout.window);
            ffi::invalidate(self.window);
        }
    }

    fn flyout_choose(&mut self, index: usize) {
        let Some(flyout) = self.flyout.as_ref() else {
            return;
        };
        let element = flyout.element;
        self.close_flyout();
        let event = self.view.choose(element, index);
        self.dispatch(event);
    }

    fn flyout_key(&mut self, key: u16) -> bool {
        let Some(flyout) = self.flyout.as_mut() else {
            return false;
        };
        let count = flyout.items.len();
        let current = flyout.hover.or(flyout.selected);
        let next = match key {
            k if k == VK_UP.0 => {
                Some(current.map_or(count.saturating_sub(1), |index| index.saturating_sub(1)))
            }
            k if k == VK_DOWN.0 => {
                Some(current.map_or(0, |index| (index + 1).min(count.saturating_sub(1))))
            }
            k if k == VK_HOME.0 => Some(0),
            k if k == VK_END.0 => Some(count.saturating_sub(1)),
            k if k == VK_RETURN.0 || k == VK_SPACE.0 => {
                if let Some(index) = current {
                    self.flyout_choose(index);
                }
                return true;
            }
            k if k == VK_ESCAPE.0
                || k == VK_TAB.0
                || k == VK_F4.0
                || k == VK_LEFT.0
                || k == VK_RIGHT.0 =>
            {
                self.close_flyout();
                return true;
            }
            _ => None,
        };
        if let Some(next) = next {
            flyout.hover = Some(next);
            let now = self.started.elapsed().as_secs_f64() * 1000.0;
            let item = size::FLYOUT_ITEM_HEIGHT;
            flyout
                .scroll
                .reveal(next as f32 * item, (next + 1) as f32 * item, now);
            ffi::invalidate(flyout.window);
        }
        true
    }

    fn flyout_point(&self, lparam: LPARAM) -> Option<usize> {
        let flyout = self.flyout.as_ref()?;
        let (_, y) = self.point(lparam);
        let now = self.now();
        let local = y - size::FLYOUT_PADDING + flyout.scroll.offset(now);
        if local < 0.0 {
            return None;
        }
        let index = (local / size::FLYOUT_ITEM_HEIGHT) as usize;
        (index < flyout.items.len()).then_some(index)
    }

    fn paint_flyout(&mut self) {
        let now = self.now();
        let theme = self.theme;
        let Some(flyout) = self.flyout.as_mut() else {
            return;
        };
        let size = ffi::client_size(flyout.window);
        let graphics = &self.graphics;
        let items = &flyout.items;
        let selected = flyout.selected;
        let hover = flyout.hover;
        let scroll = &flyout.scroll;
        let opened = flyout.opened.value(now);
        let (width, height) = (flyout.width, flyout.height);
        let clear = Color::from(theme.palette.flyout);
        let _ = flyout
            .surface
            .draw(graphics, size, theme.dpi, clear, None, |canvas| {
                paint_flyout_items(
                    canvas, &theme, items, selected, hover, scroll, opened, width, height, now,
                );
            });
        let animating = flyout.opened.running(now) || flyout.scroll.animating(now);
        if animating {
            ffi::invalidate(flyout.window);
        }
    }

    // MARK: - 打つ欄

    /// 打つ欄を前もって作って隠しておく(ページを初めて開くときに作らなくてよいように)
    fn warm_fields(&mut self) {
        let Some(font) = &self.field_font else { return };
        let have = self.pool.len() + self.view.windows().len();
        for index in have..WARM_FIELDS {
            let id = u16::try_from(index).unwrap_or(0).wrapping_add(WARM_ID);
            if let Some(window) = edit::create(self.window, id, "", font) {
                self.pool.push(window);
            }
        }
    }

    fn field_focus(&mut self, window: Window, focused: bool) {
        if focused {
            self.focused_edit = Some(window);
            if window == self.search {
                self.focus = Focus::Search;
            } else if let Some(element) = self.view.element_of(window) {
                self.focus = Focus::Page(element);
                if let Some(rect) = self.view.rect(element) {
                    let now = self.now();
                    self.scroll.reveal(
                        rect.y - size::SECTION_GAP,
                        rect.max_y() + size::SECTION_GAP,
                        now,
                    );
                }
            }
        } else if self.focused_edit == Some(window) {
            self.focused_edit = None;
        }
        ffi::invalidate(self.window);
    }

    fn field_changed(&mut self, window: Window) {
        if window == self.search {
            self.fill_nav();
            return;
        }
        let Some(element) = self.view.element_of(window) else {
            return;
        };
        let event = self.view.edited(element);
        self.dispatch(event);
    }

    fn field_enter(&mut self, window: Window) {
        let Some(element) = self.view.element_of(window) else {
            return;
        };
        let now = self.now();
        let event = self.view.submit(element, now);
        self.dispatch(event);
    }

    // MARK: - 測る(--measure)

    fn measure_step(&mut self) {
        let Some(mut measurement) = self.measure.take() else {
            return;
        };
        let done = measurement.step(self);
        self.measure = Some(measurement);
        if done {
            if let Some(measurement) = &self.measure {
                measurement.write();
            }
            ffi::destroy(self.window);
        } else {
            ffi::post(self.window, WM_MEASURE, 0, 0);
        }
    }
}

/// 描くときに使う状態(借りたまま描くために App から分ける)
struct PaintState<'a> {
    theme: &'a Theme,
    now: f64,
    width: f32,
    height: f32,
    focus: Focus,
    focus_visible: bool,
    focused_edit: Option<Window>,
    pressed: Option<Target>,
    open: Option<Element>,
    nav_hover: &'a [Tween],
    nav_indicator: f32,
    enter: f32,
    availability: Availability,
    search: Rect,
    nav_top: f32,
}

fn paint_window(
    canvas: &mut dyn Canvas,
    state: &PaintState,
    nav: &NavLayout,
    nav_scroll: &Scroller,
    view: &PageView,
    scroll: &Scroller,
) {
    let theme = state.theme;
    let nav_width = nav_width(state.width);
    let page_area = Rect::new(nav_width, 0.0, state.width - nav_width, state.height);
    paint_nav(canvas, state, nav, nav_scroll, nav_width, view.page);
    canvas.push_clip(page_area);
    let offset = (1.0 - state.enter) * size::PAGE_ENTER_OFFSET;
    let scroll_offset = scroll.offset(state.now);
    canvas.set_opacity(state.enter);
    canvas.translate(nav_width, offset - scroll_offset);
    match state.availability {
        Availability::Ready => {
            let frame = Frame {
                theme,
                now: state.now,
                focus: match state.focus {
                    Focus::Page(element) => Some(element),
                    _ => None,
                },
                focus_visible: state.focus_visible,
                pressed: match state.pressed {
                    Some(Target::Page(element)) => Some(element),
                    _ => None,
                },
                open: state.open,
                focused_edit: state.focused_edit,
                draw_fields: false,
                visible: (
                    scroll_offset - offset,
                    scroll_offset - offset + state.height,
                ),
            };
            view.paint(canvas, &frame);
        }
        availability => page::paint_status(
            canvas,
            theme,
            view.page,
            availability,
            page_area.width,
            state.height,
            state.now,
        ),
    }
    canvas.translate(-nav_width, scroll_offset - offset);
    canvas.set_opacity(1.0);
    canvas.pop_clip();
    page::scrollbar(canvas, theme, page_area, scroll, state.now);
}

fn paint_nav(
    canvas: &mut dyn Canvas,
    state: &PaintState,
    nav: &NavLayout,
    nav_scroll: &Scroller,
    nav_width: f32,
    page: Page,
) {
    let theme = state.theme;
    let palette = &theme.palette;
    // 検索欄(文字は標準の EDIT が描く)
    let search_focused = state.focus == Focus::Search;
    paint::field_frame(
        canvas,
        theme,
        state.search,
        search_focused,
        paint::State::enabled(),
    );
    let glyph = Rect::new(
        state.search.max_x() - size::FIELD_PADDING_X - size::CHEVRON_SIZE,
        state.search.y,
        size::CHEVRON_SIZE,
        state.search.height,
    );
    canvas.text(
        glyph,
        theme.glyphs.search,
        TextStyle::IconSmall,
        Color::from(palette.text_secondary),
        TextLayout::CENTER,
    );
    let list = Rect::new(
        0.0,
        state.nav_top,
        nav_width,
        (state.height - state.nav_top).max(0.0),
    );
    canvas.push_clip(list);
    let offset = nav_scroll.offset(state.now);
    canvas.translate(0.0, state.nav_top - offset);
    // 見出しは小さい薄い字にして，見出しの下側(項目の近く)に置く
    for header in &nav.headers {
        let line = size::NOTE_LINE_HEIGHT;
        canvas.text(
            Rect::new(
                size::NAV_PADDING_X,
                header.top + header.height - line - size::CARD_GAP,
                nav_width - size::NAV_PADDING_X * 2.0,
                line,
            ),
            header.group.title(),
            TextStyle::NavHeader,
            Color::from(palette.text_secondary),
            TextLayout::LINE,
        );
    }
    let gap = size::CARD_GAP;
    let selected = nav.position(page);
    for (index, item) in nav.items.iter().enumerate() {
        let rect = Rect::new(
            gap,
            item.top + gap / 2.0,
            nav_width - gap * 2.0,
            item.height - gap,
        );
        let hover = state
            .nav_hover
            .get(index)
            .map_or(0.0, |tween| tween.value(state.now));
        let pressed = state.pressed == Some(Target::Nav(index));
        let fill = if Some(index) == selected {
            Color::from(palette.nav_selected)
        } else if pressed {
            Color::from(palette.nav_pressed)
        } else {
            Color::from(palette.nav_hover).with_alpha(hover)
        };
        canvas.fill_round(rect, size::CONTROL_RADIUS, fill);
        let text = if theme.high_contrast && Some(index) == selected {
            palette.accent_text
        } else {
            palette.text
        };
        let mut x = rect.x + size::NAV_PADDING_X;
        canvas.text(
            Rect::new(x, rect.y, size::ICON_FONT_SIZE, rect.height),
            &item.page.glyph().to_string(),
            TextStyle::Icon,
            Color::from(text),
            TextLayout::CENTER,
        );
        x += size::ICON_FONT_SIZE + size::NAV_ICON_GAP;
        canvas.text(
            Rect::new(
                x,
                rect.y,
                rect.max_x() - x - size::NAV_PADDING_X,
                rect.height,
            ),
            item.page.title(),
            TextStyle::Body,
            Color::from(text),
            TextLayout::LINE,
        );
        if state.focus == Focus::Nav && state.focus_visible && Some(index) == selected {
            paint::focus_ring(canvas, theme, rect, size::CONTROL_RADIUS);
        }
    }
    // 選んでいる項目の印(項目のあいだを動く)
    if selected.is_some() {
        let item_height = size::NAV_ITEM_HEIGHT;
        let indicator = size::NAV_INDICATOR_HEIGHT;
        let top = state.nav_indicator + (item_height - indicator) / 2.0;
        canvas.fill_round(
            Rect::new(gap, top, size::NAV_INDICATOR_WIDTH, indicator),
            size::NAV_INDICATOR_WIDTH / 2.0,
            Color::from(palette.accent),
        );
    }
    canvas.translate(0.0, offset - state.nav_top);
    canvas.pop_clip();
    page::scrollbar(canvas, theme, list, nav_scroll, state.now);
}

#[allow(clippy::too_many_arguments)]
fn paint_flyout_items(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    items: &[String],
    selected: Option<usize>,
    hover: Option<usize>,
    scroll: &Scroller,
    opened: f32,
    width: f32,
    height: f32,
    now: f64,
) {
    let palette = &theme.palette;
    let whole = Rect::new(0.0, 0.0, width, height);
    canvas.stroke_round(
        whole,
        size::FLYOUT_RADIUS,
        1.0,
        Color::from(palette.flyout_stroke),
    );
    let padding = size::FLYOUT_PADDING;
    let item = size::FLYOUT_ITEM_HEIGHT;
    let body = Rect::new(0.0, padding, width, height - padding * 2.0);
    canvas.push_clip(body);
    // 開くときに上から少し下りてくる
    let slide = (1.0 - opened) * -size::PAGE_ENTER_OFFSET;
    canvas.set_opacity(opened);
    let offset = scroll.offset(now);
    for (index, label) in items.iter().enumerate() {
        let top = padding + index as f32 * item - offset + slide;
        if top + item < 0.0 || top > height {
            continue;
        }
        let rect = Rect::new(padding, top + 1.0, width - padding * 2.0, item - 2.0);
        // 地は文字の色を薄く重ねる(一覧の地の明るさによらず見分けられる)
        let subtle = |opacity: f32| Color::from(palette.text).with_alpha(opacity);
        if Some(index) == selected {
            let opacity = if Some(index) == hover {
                tokens::opacity::settings::SUBTLE_SELECTED + tokens::opacity::settings::SUBTLE_HOVER
            } else {
                tokens::opacity::settings::SUBTLE_SELECTED
            };
            canvas.fill_round(rect, size::CONTROL_RADIUS, subtle(opacity));
            let indicator = size::NAV_INDICATOR_HEIGHT;
            canvas.fill_round(
                Rect::new(
                    rect.x,
                    rect.y + (rect.height - indicator) / 2.0,
                    size::NAV_INDICATOR_WIDTH,
                    indicator,
                ),
                size::NAV_INDICATOR_WIDTH / 2.0,
                Color::from(palette.accent),
            );
        } else if Some(index) == hover {
            canvas.fill_round(
                rect,
                size::CONTROL_RADIUS,
                subtle(tokens::opacity::settings::SUBTLE_HOVER),
            );
        }
        canvas.text(
            Rect::new(
                rect.x + size::FIELD_PADDING_X,
                rect.y,
                rect.width - size::FIELD_PADDING_X * 2.0,
                rect.height,
            ),
            label,
            TextStyle::Body,
            Color::from(palette.text),
            TextLayout::LINE,
        );
    }
    canvas.set_opacity(1.0);
    canvas.pop_clip();
    page::scrollbar(canvas, theme, body, scroll, now);
}

// MARK: - 窓の手続き

/// ページの部品の読み上げの番号の始まり(左の一覧の項目と分ける)
const NODE_PAGE: i32 = 1000;
/// 読み上げの番号: 検索欄(左の一覧の項目の番号とページの部品の番号のあいだ)
const NODE_SEARCH: i32 = 900;

fn accessibility_nodes() -> Vec<uia::Node> {
    with_app(|app| app.nodes()).unwrap_or_default()
}

fn accessibility_act(id: i32, act: uia::Act) {
    with_app(|app| app.accessibility_act(id, act));
}

/// 確かめる操作を待たせる(確かめる窓は手続きを返してから出す)
const WM_CONFIRM: u32 = WM_APP + 22;
/// あとのことを手続きの外で行う
const WM_AFTER: u32 = WM_APP + 23;

thread_local! {
    static PENDING: RefCell<Option<Event>> = const { RefCell::new(None) };
    static AFTER: RefCell<Option<After>> = const { RefCell::new(None) };
}

fn low_word(value: usize) -> u32 {
    (value & 0xffff) as u32
}

fn high_word(value: usize) -> u32 {
    ((value >> 16) & 0xffff) as u32
}

extern "system" fn main_procedure(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let handled = std::panic::catch_unwind(|| main_message(window, message, wparam, lparam));
    match handled {
        Ok(Some(result)) => result,
        _ => ffi::default_procedure(window, message, wparam, lparam),
    }
}

fn main_message(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
    match message {
        WM_ERASEBKGND => Some(LRESULT(1)),
        WM_PAINT => {
            // 描く前に済んだことにする．描いたあとにすると，描く中で頼んだ次のフレーム(動き)が打ち消されて止まる
            ffi::validate(window);
            with_app(App::paint);
            Some(LRESULT(0))
        }
        WM_SIZE => {
            with_app(App::arrange);
            Some(LRESULT(0))
        }
        WM_GETMINMAXINFO => {
            let dpi = ffi::dpi(window);
            ffi::set_min_size(
                lparam,
                ffi::scale(size::WINDOW_MIN_WIDTH, dpi),
                ffi::scale(size::WINDOW_MIN_HEIGHT, dpi),
            );
            Some(LRESULT(0))
        }
        WM_LOADED => {
            with_app(App::finish_loading);
            Some(LRESULT(0))
        }
        WM_MEASURE => {
            with_app(App::measure_step);
            Some(LRESULT(0))
        }
        WM_WARM => {
            with_app(App::warm_fields);
            Some(LRESULT(0))
        }
        WM_TIMER if wparam.0 == RECONNECT_TIMER => {
            with_app(|app| {
                if app.model.is_none() {
                    app.start_loading();
                } else {
                    ffi::kill_timer(app.window, RECONNECT_TIMER);
                }
            });
            Some(LRESULT(0))
        }
        WM_MOUSEMOVE => {
            with_app(|app| app.mouse_move(lparam));
            Some(LRESULT(0))
        }
        WM_MOUSELEAVE => {
            with_app(App::mouse_leave);
            Some(LRESULT(0))
        }
        WM_LBUTTONDOWN | WM_LBUTTONDBLCLK => {
            with_app(|app| app.mouse_down(lparam));
            Some(LRESULT(0))
        }
        WM_LBUTTONUP => {
            with_app(|app| app.mouse_up(lparam));
            Some(LRESULT(0))
        }
        WM_CAPTURECHANGED | WM_CANCELMODE => {
            with_app(|app| {
                if app.pressed.is_some() {
                    app.pressed = None;
                    ffi::invalidate(app.window);
                }
            });
            None
        }
        WM_MOUSEWHEEL => {
            with_app(|app| app.wheel(wparam, lparam));
            Some(LRESULT(0))
        }
        WM_KEYDOWN | WM_SYSKEYDOWN => {
            let key = low_word(wparam.0) as u16;
            // Alt+↓ でドロップダウンを開く
            let key = if message == WM_SYSKEYDOWN && key == VK_DOWN.0 {
                VK_F4.0
            } else {
                key
            };
            let handled = with_app(|app| app.key(key)).unwrap_or(false);
            if handled {
                Some(LRESULT(0))
            } else {
                None
            }
        }
        WM_KILLFOCUS => {
            with_app(|app| {
                app.pressed = None;
                ffi::invalidate(app.window);
            });
            None
        }
        WM_COMMAND => {
            let control = HWND(lparam.0 as *mut _);
            if high_word(wparam.0) == EN_CHANGE {
                with_app(|app| app.field_changed(control));
            }
            Some(LRESULT(0))
        }
        WM_CTLCOLOREDIT | WM_CTLCOLORSTATIC => with_app(|app| {
            let palette = &app.theme.palette;
            let enabled = message == WM_CTLCOLOREDIT;
            let text = if enabled {
                palette.text
            } else {
                palette.text_disabled
            };
            edit::color_field(wparam.0, text, palette.control);
            LRESULT(app.field_brush.handle())
        }),
        edit::WM_FIELD_TAB => {
            with_app(|app| app.move_focus(wparam.0 == 1));
            Some(LRESULT(0))
        }
        edit::WM_FIELD_ENTER => {
            let field = HWND(lparam.0 as *mut _);
            with_app(|app| app.field_enter(field));
            Some(LRESULT(0))
        }
        edit::WM_FIELD_FOCUS => {
            let field = HWND(lparam.0 as *mut _);
            with_app(|app| app.field_focus(field, wparam.0 == 1));
            Some(LRESULT(0))
        }
        edit::WM_FIELD_RECORDED => {
            let field = HWND(lparam.0 as *mut _);
            with_app(|app| app.field_changed(field));
            Some(LRESULT(0))
        }
        WM_CONFIRM => {
            let Some(event) = PENDING.with(|pending| pending.borrow_mut().take()) else {
                return Some(LRESULT(0));
            };
            if let Some((title, text)) = super::actions::confirmation(&event) {
                if !ffi::confirm(window, &title, &text) {
                    return Some(LRESULT(0));
                }
            }
            let after = with_app(|app| {
                let after = app.handle(event);
                ffi::invalidate(app.window);
                after
            })
            .flatten();
            super::actions::run_after(window, after);
            Some(LRESULT(0))
        }
        WM_AFTER => {
            let after = AFTER.with(|slot| slot.borrow_mut().take());
            super::actions::run_after(window, after);
            Some(LRESULT(0))
        }
        WM_ACTIVATE => {
            if low_word(wparam.0) == WA_INACTIVE {
                with_app(App::close_flyout);
            } else {
                with_app(App::reload);
            }
            None
        }
        WM_ACTIVATEAPP if wparam.0 == 0 => {
            with_app(App::close_flyout);
            None
        }
        WM_SETTINGCHANGE | WM_SYSCOLORCHANGE | WM_THEMECHANGED => {
            with_app(|app| app.reload_theme(app.theme.dpi));
            None
        }
        WM_DPICHANGED => {
            let dpi = high_word(wparam.0);
            with_app(|app| app.reload_theme(dpi));
            if let Some((x, y, width, height)) = ffi::suggested_rect(lparam) {
                ffi::place(window, x, y, width, height);
            }
            Some(LRESULT(0))
        }
        WM_GETOBJECT => uia::get_object(window, wparam, lparam),
        WM_DESTROY => {
            uia::disconnect(window);
            APP.with(|cell| {
                if let Ok(mut app) = cell.try_borrow_mut() {
                    if let Some(app) = app.as_mut() {
                        app.close_flyout();
                    }
                    app.take();
                }
            });
            ffi::quit();
            Some(LRESULT(0))
        }
        _ => None,
    }
}

extern "system" fn flyout_procedure(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let handled = std::panic::catch_unwind(|| flyout_message(window, message, wparam, lparam));
    match handled {
        Ok(Some(result)) => result,
        _ => ffi::default_procedure(window, message, wparam, lparam),
    }
}

fn flyout_message(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
    match message {
        WM_ERASEBKGND => Some(LRESULT(1)),
        WM_PAINT => {
            ffi::validate(window);
            with_app(App::paint_flyout);
            Some(LRESULT(0))
        }
        // 押しても前に出さない(フォーカスは設定の窓に残す)
        WM_MOUSEACTIVATE => Some(LRESULT(MA_NOACTIVATE as isize)),
        WM_NCHITTEST => None,
        WM_MOUSEMOVE => {
            with_app(|app| {
                let index = app.flyout_point(lparam);
                if let Some(flyout) = app.flyout.as_mut() {
                    if flyout.hover != index && index.is_some() {
                        flyout.hover = index;
                        ffi::invalidate(flyout.window);
                    }
                }
            });
            Some(LRESULT(0))
        }
        WM_LBUTTONUP => {
            with_app(|app| {
                if let Some(index) = app.flyout_point(lparam) {
                    app.flyout_choose(index);
                }
            });
            Some(LRESULT(0))
        }
        WM_MOUSEWHEEL => {
            with_app(|app| app.wheel(wparam, lparam));
            Some(LRESULT(0))
        }
        _ => None,
    }
}

// MARK: - 測る

/// 1 ページの測った値(開く時間，初めて描く時間，2 回目に描く時間，開く時間の内わけ)
type PageMeasure = (Page, f64, f64, f64, (f64, f64, f64));

/// --measure で測る手順と結果．窓を出してから中身が出るまで，ページを開く時間，送るときの 1 フレームの間隔を測る
struct Measurement {
    path: std::path::PathBuf,
    /// 窓を描き終えた時刻(起動からのミリ秒)
    shown: Option<f64>,
    /// 中身(設定)を出せるようになった時刻
    content: Option<f64>,
    /// ページごとの開く時間(組み立てと置き直し．エンジンへの頼みを含む)，初めて描く時間，2 回目に描く時間
    /// (描く時間は Direct2D に描かせるまでの CPU の時間．画面の更新を待つ時間は含まない)
    pages: Vec<PageMeasure>,
    next_page: usize,
    /// 送りの動きのあいだのフレームの間隔と，1 フレームを描く CPU の時間
    scroll_frames: Vec<f64>,
    scroll_cpu: Vec<f64>,
    scrolling: bool,
}

impl Measurement {
    fn new(path: std::path::PathBuf) -> Self {
        Self {
            path,
            shown: None,
            content: None,
            pages: Vec::new(),
            next_page: 0,
            scroll_frames: Vec::new(),
            scroll_cpu: Vec::new(),
            scrolling: false,
        }
    }

    /// 1 つ進める．終わったら true
    fn step(&mut self, app: &mut App) -> bool {
        if let Some(page) = pages::BUILT.get(self.next_page) {
            self.next_page += 1;
            let start = Instant::now();
            app.open_page(*page);
            app.enter.snap(1.0);
            let opened = start.elapsed().as_secs_f64() * 1000.0;
            app.frames.clear();
            app.paint();
            app.paint();
            let cold = app.frames.first().map_or(-1.0, |(_, cpu)| *cpu);
            let warm = app.frames.get(1).map_or(-1.0, |(_, cpu)| *cpu);
            self.pages.push((*page, opened, cold, warm, app.breakdown));
            return false;
        }
        if !self.scrolling {
            // いちばん長いページで，上から下まで送る
            self.scrolling = true;
            app.open_page(Page::Keys);
            app.enter.snap(1.0);
            app.paint();
            app.frames.clear();
            let now = app.now();
            app.scroll.scroll_to(f32::MAX, now);
            let deadline = Instant::now()
                + std::time::Duration::from_millis(u64::from(motion::SCROLL as u32) + 200);
            while Instant::now() < deadline {
                app.paint();
            }
            self.scroll_frames = app
                .frames
                .windows(2)
                .map(|pair| pair[1].0 - pair[0].0)
                .collect();
            self.scroll_cpu = app.frames.iter().map(|(_, cpu)| *cpu).collect();
            return false;
        }
        true
    }

    fn write(&self) {
        let average = |values: &[f64]| {
            if values.is_empty() {
                0.0
            } else {
                values.iter().sum::<f64>() / values.len() as f64
            }
        };
        let maximum = |values: &[f64]| values.iter().copied().fold(0.0, f64::max);
        let opened: Vec<f64> = self.pages.iter().map(|page| page.1).collect();
        let cold: Vec<f64> = self.pages.iter().map(|page| page.2).collect();
        let warm: Vec<f64> = self.pages.iter().map(|page| page.3).collect();
        let mut lines = vec![
            format!("window_shown_ms {:.1}", self.shown.unwrap_or(-1.0)),
            format!("content_ready_ms {:.1}", self.content.unwrap_or(-1.0)),
            format!(
                "page_open_ms average {:.2} max {:.2}",
                average(&opened),
                maximum(&opened)
            ),
            format!(
                "page_first_paint_cpu_ms average {:.2} max {:.2}",
                average(&cold),
                maximum(&cold)
            ),
            format!(
                "page_paint_cpu_ms average {:.2} max {:.2}",
                average(&warm),
                maximum(&warm)
            ),
            format!(
                "scroll_frame_interval_ms average {:.2} max {:.2} frames {}",
                average(&self.scroll_frames),
                maximum(&self.scroll_frames),
                self.scroll_frames.len()
            ),
            format!(
                "scroll_frame_cpu_ms average {:.2} max {:.2}",
                average(&self.scroll_cpu),
                maximum(&self.scroll_cpu)
            ),
        ];
        for (page, opened, cold, warm, (built, read, refreshed)) in &self.pages {
            lines.push(format!(
                "page {page:?} open {opened:.2} (build {built:.2} engine {read:.2} sync {refreshed:.2}) first_paint {cold:.2} paint {warm:.2}"
            ));
        }
        let _ = std::fs::write(&self.path, lines.join("\n") + "\n");
    }
}
