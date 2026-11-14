#![forbid(unsafe_code)]

//! 設定の窓．左に検索と一覧(見出しごとのページ)，右に開いているページを置く(macOS の SettingsView と同じ並び)．
//! 窓は 1 枚で，Direct2D で描く．動きのあいだだけ描き直しを続け(画面の更新に合わせる)，止まっているときは描かない．
//! 状態は UI スレッドの thread_local に持ち，窓の手続きはそこから借りる．借りている間に届いたメッセージは既定の扱いにする

use super::actions::After;
use super::ffi::d2d::{self, Graphics, PreviewPixels, Surface};
use super::ffi::uia;
use super::ffi::{self, edit, Window};
use super::import_sheet::{self, ImportLayout, ImportPart, ImportSheet, PendingImport};
use super::page::{
    self, Availability, Described, EditorAction, Element, Event, Extras, Frame, PageView, Part,
};
use super::paint::{self, Canvas, Measure, TextLayout, TextStyle};
use super::sheet::{self, CommandSheet, SheetLayout, SheetPart};
use super::theme::{Color, Theme};
use super::Store;
use crate::catalog::{Catalog, Timing};
use crate::layout::Rect;
use crate::model::SettingsModel;
use crate::pages::{self, Page};
use crate::strings::{features, settings};
use crate::ui::anim::{Easing, Tween};
use crate::ui::menu::{MenuLayout, MenuMove, MenuRowKind};
use crate::ui::nav::NavLayout;
use crate::ui::scroll::{self, Scroller};
use crate::ui::table::Move;
use ipc::{DictionaryEntry, SymbolItem};
use std::cell::RefCell;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokens::motion::settings_windows as motion;
use tokens::size::settings_windows as size;
use tokens::size::{part, space};
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
    WM_MOUSEACTIVATE, WM_MOUSEMOVE, WM_MOUSEWHEEL, WM_NCHITTEST, WM_PAINT, WM_RBUTTONUP,
    WM_SETTINGCHANGE, WM_SIZE, WM_SYSCOLORCHANGE, WM_SYSKEYDOWN, WM_THEMECHANGED, WM_TIMER,
    WS_CLIPCHILDREN, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_OVERLAPPEDWINDOW,
    WS_POPUP,
};
use windows_core::{w, PCWSTR};

const MAIN_CLASS: PCWSTR = w!("hajime.settings");
const FLYOUT_CLASS: PCWSTR = w!("hajime.settings.flyout");
const ID_SEARCH: u16 = 1;
/// 前もって作る打つ欄の番号の始まり
const WARM_ID: u16 = 50;
/// 使い回しの欄が足りないときにシートの打つ欄を作る番号の始まり
const SHEET_FIELD_ID: u16 = 60;
/// つなぎ直しの時計の番号
const RECONNECT_TIMER: usize = 1;
/// 説明の吹き出しを出すまでの時計の番号
const TOOLTIP_TIMER: usize = 2;
/// ユーザー辞書の書き方の表の今の値を読み直す間隔のタイマー
const TEMPLATE_TIMER: usize = 3;
/// 書き方の表の今の値を読み直す間隔(ミリ秒．秒の値が変わるので 1 秒)
const TEMPLATE_INTERVAL: u32 = 1000;
/// ポインターを載せてから説明の吹き出しを出すまで(ミリ秒．OS のツールチップと同じくらい)
const TOOLTIP_DELAY: u32 = 500;
/// 見本の書き出しで，動き(トグルのつまみ・ページの入り・送り)が終わったとみなす時刻のずれ(ミリ秒)．
/// どの動きの長さ(motion.settings-windows)よりも長くする
const SNAPSHOT_SETTLE: f64 = 10_000.0;
/// 読み込みのスレッドが終わった知らせ
const WM_LOADED: u32 = WM_APP + 20;
/// 測る手順を 1 つ進める知らせ(--measure)
const WM_MEASURE: u32 = WM_APP + 21;
/// 見本の書き出しで写す状態(書き方のチップ．macOS の settings-templates-* と同じ 4 つと，変換マクロ)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Shot {
    /// ふつう(チップは閉じている)
    Plain,
    /// チップを開いた
    Open,
    /// 単語の欄で「{da」を打って絞り込んだ
    Typing,
    /// 「入力時の値にする」がオフ(ボタンもチップも出さない)
    DynamicOff,
    /// 辞書のファイルを取り込む前に中身を見せるシート(名詞にする行と読めない行を含む見本のファイル)
    ImportPreview,
    /// キー設定の表から確定の行を消した(キーの無い知らせと「既定のキーを追加」)
    MissingKeys,
    /// 組に分けた一覧を開いた(ユーザー辞書の品詞．組の見出しと区切りの線)
    GroupedMenu,
    /// キー設定の新しい行に，表にある行と同じ状態・同じキーを入れた(足す前の知らせ)．表は押したキーで絞り込んでいる(チップ)
    KeyDraft,
    /// キー設定の新しい行のキーを記録しているところ(案内と「記録を停止」)
    KeyRecording,
}

impl Shot {
    /// ふつうの 1 枚のほかに写すページと状態
    const TEMPLATES: [(Page, Shot); 9] = [
        (Page::Dictionary, Shot::Open),
        (Page::Dictionary, Shot::Typing),
        (Page::Dictionary, Shot::DynamicOff),
        (Page::Commands, Shot::Open),
        (Page::Dictionary, Shot::ImportPreview),
        (Page::Keys, Shot::MissingKeys),
        (Page::Dictionary, Shot::GroupedMenu),
        (Page::Keys, Shot::KeyDraft),
        (Page::Keys, Shot::KeyRecording),
    ];

    fn suffix(self) -> &'static str {
        match self {
            Shot::Plain => "",
            Shot::Open => "-templates-open",
            Shot::Typing => "-templates-typing",
            Shot::DynamicOff => "-templates-off",
            Shot::ImportPreview => "-import-preview",
            Shot::MissingKeys => "-missing-keys",
            Shot::GroupedMenu => "-word-classes-open",
            Shot::KeyDraft => "-key-draft",
            Shot::KeyRecording => "-key-recording",
        }
    }
}

/// 取り込む前のシートの見本(macOS の SnapshotRenderer の settings-import-preview-words と同じ中身)
fn import_sample() -> PendingImport {
    use ipc::{ImportColumn, ImportFormat, ImportPreview, ImportPreviewRow, ImportRowStatus};
    let row = |line: u32, cells: &[&str], status: ImportRowStatus| ImportPreviewRow {
        line,
        cells: cells.iter().map(|cell| (*cell).to_string()).collect(),
        status,
    };
    PendingImport {
        path: "C:\\ユーザー辞書.txt".into(),
        preview: ImportPreview {
            format: ImportFormat::TabSeparated,
            columns: vec![
                ImportColumn::Reading,
                ImportColumn::Word,
                ImportColumn::WordClass,
                ImportColumn::Comment,
            ],
            rows: vec![
                row(
                    2,
                    &["はじめ", "Hajime IME", "properNoun", ""],
                    ImportRowStatus::Ok,
                ),
                row(3, &["しぶや", "渋谷", "place", ""], ImportRowStatus::Ok),
                row(
                    4,
                    &["かぶしきがいしゃ", "株式会社", "noun", ""],
                    ImportRowStatus::DefaultedWordClass,
                ),
                row(
                    5,
                    &["めーる", "hajime@example.com", "abbreviation", ""],
                    ImportRowStatus::Ok,
                ),
                row(
                    6,
                    &["はしる", "走る", "noun", ""],
                    ImportRowStatus::DefaultedWordClass,
                ),
                row(7, &["ひとつだけ"], ImportRowStatus::Unreadable),
                row(
                    8,
                    &["とうきょう", "東京", "place", "首都"],
                    ImportRowStatus::Ok,
                ),
                row(
                    9,
                    &["漢字", "読みがひらがなでない"],
                    ImportRowStatus::Unreadable,
                ),
            ],
            importable: 6,
            defaulted: 2,
            unreadable: 2,
        },
        action: import_sheet::ImportAction::UserDictionary,
    }
}

/// 見本の書き出しで，キー設定の新しい行に入れて表を絞り込むキー(標準の表の入力中にある)
const SNAPSHOT_KEY: &str = "Space";

/// 見本の書き出しの 1 枚(ページ・状態・暗いか)
type SnapshotJob = (Page, Shot, bool);

/// 見本の書き出しの次の 1 枚(--render-snapshots)
const WM_SNAPSHOT: u32 = WM_APP + 26;
/// 手の空いたときに打つ欄を前もって作る知らせ
const WM_WARM: u32 = WM_APP + 24;
/// 前もって作っておく打つ欄の数(1 ページの欄の数の上限．記号のページの 6 つに少し足す)
const WARM_FIELDS: usize = 8;
/// 入力欄の書体(本文と同じ書体を GDI で)
const FIELD_FACE: &str = "Yu Gothic UI";

/// 左の一覧の幅(窓が狭いときは窓の半分)
pub(super) fn nav_width(width: f32) -> f32 {
    size::NAV_WIDTH.min(width / 2.0)
}

/// フォーカスのあるところ
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Focus {
    Search,
    Nav,
    Page(Element),
    /// カスタムテーマの編集の画面の下のボタン
    ThemeSheet(EditorAction),
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
    /// カスタムテーマの編集の画面の下のボタン
    ThemeSheet(EditorAction),
}

/// ページを送る場所(窓の中のタイトルバーの下の上端・下端，DIP)と，ページの中の座標を窓の中の座標にずらす量
#[derive(Debug, Clone, Copy, PartialEq)]
struct PageFrame {
    top: f32,
    bottom: f32,
    shift: f32,
}

/// 開いているドロップダウンの一覧
struct Flyout {
    element: Element,
    window: Window,
    surface: Surface,
    items: Vec<String>,
    /// 行の並び(項目と，組の見出し・区切りの線)．selected と hover は項目だけを数えた番号
    layout: MenuLayout,
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
    pub(super) graphics: Graphics,
    surface: Surface,
    pub(super) theme: Theme,
    /// 窓の背景を Mica にしているか(Windows 11 22H2 から．高コントラストでは使わない)
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
    /// 画面の中だけの値(「page.」の道筋．ユーザー辞書のページで出している一覧など)
    pub(super) view_values: crate::store::Fields,
    /// 開いているカスタムテーマの編集の画面(ページの場所に重ねる)
    pub(super) editor: Option<super::editor::ThemeEditor>,
    /// 外観の見本を描くもの(初めて描くときに作る．作れなければ見本を描かない)
    preview: Option<candidate_ui::app::preview::Preview>,
    preview_pixels: Option<(String, PreviewPixels)>,
    /// 見本を描いた大きさ(DIP)と，測った見本の中身(PreviewSource の key)
    preview_natural: Option<(String, (f32, f32))>,
    /// 見本の画像の通し番号(作り直すたびに増やす)
    preview_generation: u64,
    /// タイトルバーのアイコンの画像(DPI ごとに作り直す)
    title_icon: Option<(u32, PreviewPixels)>,
    /// 窓が前にあるか(タイトルバーの題の色を変える．WinUI の TitleBar と同じ)
    active: bool,
    /// 記号の決まり(表の行と同じ並び．外す・切り替えるときに引く)
    pub(super) sequences: Vec<SymbolItem>,
    pub(super) readings: Vec<SymbolItem>,
    pub(super) field_font: Option<ffi::Font>,
    field_brush: edit::Brush,
    /// 隠して使い回す打つ欄
    pub(super) pool: Vec<Window>,
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
    /// 説明の吹き出し(文と，ポインターの位置と，載せた時刻)
    tooltip: Option<(String, f32, f32, f64)>,
    pressed: Option<Target>,
    flyout: Option<Flyout>,
    /// 出しているコマンドのシート(macOS の CommandsPage の CommandEditor)
    pub(super) sheet: Option<CommandSheet>,
    started: Instant,
    /// 描いた時刻と描くのにかかった時間(測るとき)
    frames: Vec<(f64, f64)>,
    measuring: bool,
    /// ページを開く時間の内わけ(部品を作る・エンジンから読む・値を映して置く．測るとき)
    breakdown: (f64, f64, f64),
    measure: Option<Measurement>,
    /// 見本の書き出し(--render-snapshots)．書き出し先と，残りのページと状態と見た目(暗いか)
    snapshots: Option<(std::path::PathBuf, Vec<SnapshotJob>)>,
    /// 「更新を確認」の進み具合(R-19)
    pub(super) update: super::update::Updater,
    /// 辞書を取り込んだ結果の受け箱(取り込みは別のスレッドで待ち，終えたら WM_DICTIONARY_IMPORTED を送る)
    pub(super) dictionary_import: super::actions::ImportInbox,
    /// 取り込む前に読んだ結果の受け箱(読み終えたら WM_IMPORT_PREVIEWED を送る)
    pub(super) import_preview: super::actions::PreviewInbox,
    /// 取り込む前に中身を見せているシート
    pub(super) import_sheet: Option<ImportSheet>,
    /// 見本のエンジンで開いた(--offline)
    pub(super) offline: bool,
    /// 書き方のチップを開いている一覧(ページごとに覚える．見本のエンジンで開いたときは覚えない)
    pub(super) templates_open: std::collections::HashSet<pages::TemplateTarget>,
    /// 単語の登録で開いた(--register-word)．つながったら，エンジンが持っている語と読みを登録の欄に入れる
    register_word: bool,
}

/// タイトルバーのアイコンを描く画像の置き場所(0 は外観・情報のページの見本)
const TITLE_ICON_SLOT: usize = 1;

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
        view_values: crate::store::Fields::new(),
        editor: None,
        preview: None,
        preview_pixels: None,
        preview_natural: None,
        preview_generation: 0,
        title_icon: None,
        active: false,
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
        tooltip: None,
        pressed: None,
        flyout: None,
        sheet: None,
        started,
        frames: Vec::new(),
        measuring: options.measure.is_some(),
        breakdown: (0.0, 0.0, 0.0),
        measure: options.measure.map(Measurement::new),
        snapshots: options.snapshots.map(|directory| {
            let jobs = Page::ALL
                .into_iter()
                .map(|page| (page, Shot::Plain))
                .chain(Shot::TEMPLATES)
                .flat_map(|(page, shot)| [(page, shot, false), (page, shot, true)])
                .rev()
                .collect();
            (directory, jobs)
        }),
        update: super::update::Updater::default(),
        dictionary_import: super::actions::ImportInbox::default(),
        import_preview: super::actions::PreviewInbox::default(),
        import_sheet: None,
        offline: options.offline,
        templates_open: if options.offline {
            std::collections::HashSet::new()
        } else {
            [pages::TemplateTarget::Word, pages::TemplateTarget::Macro]
                .into_iter()
                .filter(|target| ffi::user_switch(target.storage_name()))
                .collect()
        },
        register_word: options.register_word,
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
    if options.check_for_updates {
        // 確かめる窓はこの窓を持ち主にして出すので，窓を出してから始める
        with_app(super::update::start_check);
    }
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
    /// 見本を書き出すディレクトリ(--render-snapshots)
    pub snapshots: Option<std::path::PathBuf>,
    /// 初めに開くページ(見本の撮影)
    pub page: Option<Page>,
    /// 見本のエンジンで開いた(--offline)．設定のファイルを開かず，ウィザードも見本の値で開く
    pub offline: bool,
    /// 単語の登録で開いた(--register-word)．ユーザー辞書のページの登録の欄に，エンジンが持っている語と読みを入れる
    pub register_word: bool,
    /// 入力メニューの「更新を確認」で開いた(--check-for-updates)．窓を出したら，情報のページの「更新を確認」を
    /// 押したときと同じ確認を始める
    pub check_for_updates: bool,
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

    /// タイトルバーの下の大きさ(DIP)．ページと左の一覧はタイトルバーの下を窓の中として扱う
    pub(super) fn size(&self) -> (f32, f32) {
        let (width, height) = ffi::client_size(self.window);
        (
            self.theme.dip(width),
            (self.theme.dip(height) - self.title_bar()).max(0.0),
        )
    }

    /// 窓の中に入れたタイトルバーの高さ(DIP)．OS の枠のままなら 0
    fn title_bar(&self) -> f32 {
        self.theme.dip(ffi::frame::title_bar(self.window))
    }

    /// タイトルバーの下の位置(DIP)を窓の中のピクセルにする
    fn client_px(&self, x: f32, y: f32) -> (i32, i32) {
        (self.theme.px(x), self.theme.px(y + self.title_bar()))
    }

    fn apply_theme(&mut self) {
        ffi::set_dark_title_bar(self.window, self.theme.dark);
        // 高コントラストのときは OS の色で塗るので Mica にしない
        self.mica = ffi::set_mica(self.window, !self.theme.high_contrast);
        // Mica のときはタイトルバーを窓の中に入れ，本文と同じ背景に描く(設定アプリと同じ)．Mica でなければ OS の枠のまま
        let title_bar = if self.mica {
            self.theme.px(size::TITLE_BAR_HEIGHT)
        } else {
            0
        };
        ffi::frame::set_title_bar(self.window, title_bar);
        // 先に作った検索欄は，背景を変えたあとに描き直す(自分の面を持つ窓なので，前の絵が残る)
        self.search_painted = false;
        edit::set_placeholder_color(self.theme.palette.text_placeholder);
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
                self.take_registration();
                ffi::post(self.window, WM_WARM, 0, 0);
                if let Some(measurement) = &mut self.measure {
                    measurement.content = Some(self.started.elapsed().as_secs_f64() * 1000.0);
                    ffi::post(self.window, WM_MEASURE, 0, 0);
                }
                if self.snapshots.is_some() {
                    ffi::post(self.window, WM_SNAPSHOT, 0, 0);
                }
            }
            None => self.disconnect(),
        }
    }

    /// 単語の登録で開いたとき，エンジンが持っている語と読みを受け取り，登録した単語の一覧の入力欄に入れて，読みの欄に入力位置を置く．
    /// つながってから一度だけ行う(エンジンは一度渡すと消す)．語と読みは入力内容なので，引数では受け取らない
    fn take_registration(&mut self) {
        if !self.register_word {
            return;
        }
        let Some(model) = &self.model else { return };
        self.register_word = false;
        let registration = model
            .store()
            .take_word_registration()
            .ok()
            .flatten()
            .unwrap_or_default();
        // 登録した単語の一覧を出す(取り込んだ辞書の一覧を出していたら切り替える)
        self.view_values.insert(
            pages::DICTIONARY_TAB.to_string(),
            serde_json::Value::String(pages::DICTIONARY_TAB_WORDS.to_string()),
        );
        if self.view.page == Page::Dictionary {
            self.refresh();
        } else {
            self.open_page(Page::Dictionary);
        }
        let Some(element) = self
            .view
            .fill_registration(&registration.reading, &registration.word)
        else {
            return;
        };
        self.set_focus(Focus::Page(element));
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
        // シートは前のページのコマンドを書いているので，ページを替える前に閉じる
        self.close_sheet();
        let start = Instant::now();
        // 編集の画面を開いたままページを作り直すとき(つなぎ直しなど)は，編集の画面を閉じる
        if self.editor.take().is_some() {
            ffi::enable(self.search, true);
        }
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
        let open = self.templates_open.clone();
        self.view
            .set_templates_open(|target| open.contains(&target));
        // 更新を確かめている途中に情報のページを開き直しても，進み具合を出し続ける
        self.view.set_version_status(self.update.status());
        let built = start.elapsed().as_secs_f64() * 1000.0;
        let now = self.now();
        self.reset_page_state(now);
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

    /// ページを作り直したときに，フォーカス・ポインター・送りを戻し，入りの動きを始める
    pub(super) fn reset_page_state(&mut self, now: f64) {
        if let Focus::Page(_) | Focus::ThemeSheet(_) = self.focus {
            self.focus = Focus::Nav;
        }
        self.focused_edit = None;
        self.close_flyout();
        self.hover = None;
        self.pressed = None;
        self.scroll = Scroller::default();
        self.enter = Tween::new(
            0.0,
            1.0,
            now,
            self.duration(motion::PAGE_ENTER),
            Easing::DECELERATE,
        );
    }

    pub(super) fn search_window(&self) -> Window {
        self.search
    }

    pub(super) fn scroll_offset(&self, now: f64) -> f32 {
        self.scroll.offset(now)
    }

    /// ページを offset まで送る(編集の画面を閉じて外観のページに戻ったとき)
    pub(super) fn restore_scroll(&mut self, offset: f32) {
        self.scroll.jump_to(offset);
        self.place_fields();
        ffi::invalidate(self.window);
    }

    /// ページの部品にフォーカスを置く
    pub(super) fn focus_page(&mut self, element: Element) {
        self.set_focus(Focus::Page(element));
    }

    pub(super) fn focus_visible(&self) -> bool {
        self.focus_visible
    }

    pub(super) fn theme_sheet_hover(&self) -> Option<EditorAction> {
        match self.hover {
            Some(Target::ThemeSheet(action)) => Some(action),
            _ => None,
        }
    }

    pub(super) fn theme_sheet_pressed(&self) -> Option<EditorAction> {
        match self.pressed {
            Some(Target::ThemeSheet(action)) => Some(action),
            _ => None,
        }
    }

    pub(super) fn theme_sheet_focus(&self) -> Option<EditorAction> {
        match self.focus {
            Focus::ThemeSheet(action) => Some(action),
            _ => None,
        }
    }

    /// ページを送る場所．ふだんは上に留めた題の下から窓の下まで．編集の画面では見本の帯の下からボタンの帯の上まで送り，
    /// ページの題の場所(layout の title)を見本の帯の下に隠す
    fn page_frame(&self) -> PageFrame {
        let (_, height) = self.size();
        match self.theme_sheet() {
            Some(sheet) => PageFrame {
                top: sheet.band.max_y(),
                bottom: sheet.footer.y,
                shift: sheet.band.max_y() + size::PAGE_PADDING_TOP - page_header(),
            },
            None => PageFrame {
                top: if self.availability() == Availability::Ready {
                    page_header()
                } else {
                    0.0
                },
                bottom: height,
                shift: 0.0,
            },
        }
    }

    /// 窓の中の y(DIP)をページの中の y にする
    fn page_y(&self, y: f32, now: f64) -> f32 {
        y + self.scroll.offset(now) - self.page_frame().shift
    }

    /// 値を部品に映して置き直す
    pub(super) fn refresh(&mut self) {
        let now = self.now();
        if let Some(model) = &self.model {
            if self.view.page == Page::Keys {
                (
                    self.extras.keymap_report,
                    self.extras.keymap_issues,
                    self.extras.keymap_missing,
                ) = super::actions::keymap_report(model);
                // キーの無い確定・取り消しがあれば，標準の表のキーを足すボタンを出す
                self.view_values.insert(
                    pages::KEYMAP_MISSING.to_string(),
                    serde_json::Value::Bool(self.extras.keymap_missing > 0),
                );
                self.extras.keymap_preset = super::actions::matching_preset(model);
            }
            // 書き方のチップは今の値を添える．開いているあいだは 1 秒ごとに読み直す(macOS の TimelineView)
            if let Some(items) = self.view.template_items() {
                let sample = self
                    .view
                    .macro_preview_inputs()
                    .map(|(text, reading, _)| (text, reading));
                let (text, reading) = sample.unwrap_or_default();
                self.extras.template_values = super::actions::template_values(
                    model,
                    &items,
                    (&text, &reading),
                    &self.extras.template_values,
                );
                ffi::set_timer(self.window, TEMPLATE_TIMER, TEMPLATE_INTERVAL);
            }
            // 変換マクロの一覧やオン・オフが変わったら，試した結果も読み直す
            if let Some((text, reading, _)) = self.view.macro_preview_inputs() {
                self.extras.macro_preview = super::actions::macro_preview(model, &text, &reading);
                self.extras.macro_results = super::actions::macro_results(model, &text, &reading);
            }
            // いつも英語・いつも日本語にする単語などが変わったら，英語と日本語の試した結果のタグも出し直す(macOS と同じ)
            if let Some((text, preceding)) = self.view.language_preview_inputs() {
                let shown = super::actions::language_preview(model, &text, &preceding);
                self.view
                    .show_preview(crate::pages::TryKind::Language, &shown);
            }
            if self.view.page == Page::Appearance && self.extras.fonts.is_empty() {
                self.extras.fonts = candidate_ui::app::fonts::installed();
            }
            // 同期の状態と，カスタムテーマの一覧と編集しているテーマの下書きの値を重ねる
            let entries = crate::themes::entries(model.value(crate::themes::THEMES));
            let mut extra = self.sync_values.clone();
            extra.extend(self.view_values.clone());
            if let Some(editor) = &self.editor {
                extra.extend(crate::themes::draft_values(&editor.draft));
            }
            extra.extend(crate::themes::list_values(
                entries.len(),
                self.catalog.limits.custom_themes,
            ));
            self.extras.extra = extra;
            let values = page::WithExtras {
                values: model,
                extra: &self.extras.extra,
            };
            self.view.sync(&values, &self.extras, now);
            // ページを開いた・スイッチを入れたなどで書き方のチップの欄を出したばかりなら，今の値をすぐ読んで映す
            // (読み直すまで決めておいた例の値を出さない)
            if let Some(items) = self.view.template_items() {
                let missing = items.iter().any(|item| {
                    !self
                        .extras
                        .template_values
                        .iter()
                        .any(|(sample, _)| *sample == item.sample)
                });
                if missing {
                    let (text, reading) = self
                        .view
                        .macro_preview_inputs()
                        .map(|(text, reading, _)| (text, reading))
                        .unwrap_or_default();
                    self.extras.template_values = super::actions::template_values(
                        model,
                        &items,
                        (&text, &reading),
                        &self.extras.template_values,
                    );
                    let values = page::WithExtras {
                        values: model,
                        extra: &self.extras.extra,
                    };
                    self.view.sync(&values, &self.extras, now);
                }
                ffi::set_timer(self.window, TEMPLATE_TIMER, TEMPLATE_INTERVAL);
            }
        }
        self.preview_pixels = None;
        self.arrange();
    }

    /// 窓の大きさに合わせて置き直す
    pub(super) fn arrange(&mut self) {
        let (width, height) = self.size();
        let nav_width = nav_width(width);
        self.measure_preview();
        let content = self.view.arrange(width - nav_width, &self.graphics);
        // ページの中の座標で，見える範囲の下の端までを送りの幅にする(ずらした分を引く)
        let frame = self.page_frame();
        self.scroll.set_extent(content, frame.bottom - frame.shift);
        let _ = height;
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
        // 右に虫めがねの絵を置く分(絵と，その左右の余白)を空ける
        let glass_left = rect.max_x() - size::FIELD_PADDING_X - size::CHEVRON_SIZE;
        let width = glass_left - size::FIELD_PADDING_X - x;
        let (left, top) = self.client_px(x, y);
        let (right, bottom) = self.client_px(x + width, y + line);
        ffi::place(self.search, left, top, right - left, bottom - top);
        // シートを出しているあいだは窓の中身の打つ欄を隠す(欄は窓なので暗くした背景の上に出てしまう)
        ffi::show(self.search, !self.modal_open());
    }

    /// ページの打つ欄を今の送りの位置に置く
    fn place_fields(&self) {
        let (width, _) = self.size();
        let now = self.now();
        let entering = self.enter.running(now);
        let frame = self.page_frame();
        // 下に留めた帯はカスタムテーマの編集の画面だけ(ほかのページは窓の下の端で欄が切れる)
        let bottom = if self.editor.is_some() {
            frame.bottom - frame.shift
        } else {
            f32::MAX
        };
        self.view.place_fields(
            &self.theme,
            (nav_width(width), self.title_bar() + frame.shift),
            (frame.top - frame.shift, bottom),
            self.scroll.offset(now),
            entering || self.modal_open(),
        );
        self.place_sheet_fields();
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
        let title_bar = self.title_bar();
        if title_bar > 0.0 {
            self.update_title_icon();
        }
        let (width, height) = self.size();
        let theme = self.theme;
        // Mica のときは背景を透明にし，Mica を見せる(カードと部品は不透明のまま描く)
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
            frame: self.page_frame(),
            theme_sheet: self
                .theme_sheet()
                .map(|layout| (layout, self.theme_sheet_state())),
            draw_fields: false,
        };
        let tooltip = self.tooltip.as_ref().filter(|(.., since)| {
            now - since >= f64::from(TOOLTIP_DELAY) && self.pressed.is_none()
        });
        let sheet = self.sheet.as_ref();
        let sheet_layout = self.sheet_layout();
        let import = self.import_sheet.as_ref();
        let import_layout = self.import_sheet_layout();
        let sheet_frame = sheet::SheetFrame {
            theme: &theme,
            size: (width, height),
            focused_edit: self.focused_edit,
            hover: 1.0,
        };
        let mut cpu = 0.0;
        let active = self.active;
        let icon = self
            .title_icon
            .as_ref()
            .filter(|_| title_bar > 0.0)
            .map(|(_, pixels)| pixels);
        let drawn = self.surface.draw_layers(
            graphics,
            size,
            theme.dpi,
            clear,
            &[preview, icon],
            |canvas| {
                let start = Instant::now();
                if title_bar > 0.0 {
                    paint_title_bar(canvas, &theme, width, title_bar, active);
                }
                // ページと左の一覧はタイトルバーの下に描く
                canvas.translate(0.0, title_bar);
                canvas.push_clip(Rect::new(0.0, 0.0, width, height));
                paint_window(canvas, &state, nav, nav_scroll, view, scroll);
                if let (Some(sheet), Some(layout)) = (sheet, &sheet_layout) {
                    sheet::paint(canvas, sheet, layout, &sheet_frame);
                }
                if let (Some(sheet), Some(layout)) = (import, &import_layout) {
                    import_sheet::paint(canvas, sheet, layout, &sheet_frame, now);
                }
                if let Some((text, x, y, _)) = tooltip {
                    paint_tooltip(canvas, &theme, text, (*x, *y), (width, height));
                }
                canvas.pop_clip();
                canvas.translate(0.0, -title_bar);
                cpu = start.elapsed().as_secs_f64() * 1000.0;
            },
        );
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

    /// kind の見本に今の設定で描くもの(テーマ・文字の大きさ・候補の窓)．つながっていなければ None
    fn preview_source(&self, kind: page::PreviewKind) -> Option<PreviewSource> {
        let model = self.model.as_ref()?;
        let entries = crate::themes::entries(model.value(crate::themes::THEMES));
        // 編集の画面では下書きを，ほかでは使っているテーマを描く(macOS の ThemeChoice(model.settings))
        let shown = match &self.editor {
            Some(editor) => crate::themes::to_wire(&editor.draft),
            None => model
                .value(crate::themes::ACTIVE)
                .and_then(serde_json::Value::as_str)
                .and_then(|id| entries.iter().find(|entry| entry.id == id))
                .and_then(|entry| crate::themes::to_wire(&entry.value)),
        };
        let theme_name = model
            .value("theme")
            .and_then(serde_json::Value::as_str)
            .unwrap_or("automatic")
            .to_string();
        let font_size = self
            .view
            .dragging(FONT_SIZE)
            .or_else(|| model.value(FONT_SIZE).and_then(serde_json::Value::as_f64))
            .map_or(tokens::size::candidate::FONT_SIZE, |size| size as f32);
        // パレットの見本は設定のとおりの列数・行数・マスの大きさで描く(macOS の PalettePreview)
        let number = |name: &str| {
            model
                .value(name)
                .and_then(serde_json::Value::as_f64)
                .unwrap_or(0.0)
        };
        let on = |name: &str| {
            model
                .value(name)
                .and_then(serde_json::Value::as_bool)
                .unwrap_or(false)
        };
        let palette = (kind == page::PreviewKind::Palette).then(|| {
            candidate_ui::palette::sample::settings(
                number("paletteColumns") as u32,
                number("paletteRows") as u32,
                if on("paletteRecordsHistory") {
                    number("paletteFrequentRows") as u32
                } else {
                    0
                },
                on("paletteShowsPreview"),
                ipc::PalettePreviewFields {
                    unicode_name: on("paletteShowsUnicodeName"),
                    readings: on("paletteShowsReadings"),
                    shortcodes: on("paletteShowsShortcodes"),
                    code_points: on("paletteShowsCodePoints"),
                },
                number("paletteCellSize"),
            )
        });
        // 絵文字の見本は設定のとおりの位置・数・名前で並べる(macOS の EmojiSection)
        let emoji = (kind == page::PreviewKind::Emoji).then(|| {
            use candidate_ui::scene::sample::{emoji_placement, EmojiSettings};
            emoji_placement(EmojiSettings {
                whole: on("emojiConversion"),
                position: number("emojiCandidatePosition") as usize,
                count: number("emojiCandidateCount") as usize,
                names: on("showsEmojiNames"),
                per_page: number("listCandidatesPerPage") as usize,
            })
        });
        // カスタムテーマはすべての項目(元のテーマ・色・書体・角の丸み)で見分ける．一部だけで見分けると，
        // ほかの項目を変えても見本を作り直さず，変えたことがすぐ映らない
        let key = format!(
            "{kind:?}|{:?}|{:?}|{theme_name}|{}|{font_size}|{}|{}",
            palette.as_ref().map(|panel| (
                panel.columns,
                panel.visible_rows,
                panel.cell_size,
                panel.shows_preview,
                panel.preview_fields.as_ref().map(|fields| (
                    fields.unicode_name,
                    fields.readings,
                    fields.shortcodes,
                    fields.code_points
                )),
                panel.rows.len()
            )),
            emoji.as_ref().map(|list| list
                .entries
                .iter()
                .map(|entry| (entry.text.clone(), entry.detail.clone()))
                .collect::<Vec<_>>()),
            shown
                .as_ref()
                .and_then(|theme| serde_json::to_string(theme).ok())
                .unwrap_or_default(),
            self.theme.dark,
            self.theme.dpi,
        );
        let look = candidate_ui::theme::SystemLook {
            dark: self.theme.dark,
            accent: None,
            increase_contrast: ffi::high_contrast(),
            backdrop: false,
        };
        let resolved =
            candidate_ui::theme::ResolvedTheme::resolve(&theme_name, shown.as_ref(), &look);
        Some(PreviewSource {
            key,
            resolved,
            font_size,
            palette,
            emoji,
        })
    }

    /// ページの見本を描いた大きさを測り，見本の行の高さにする(macOS の ScaledPreview は描いた大きさで置く)
    fn measure_preview(&mut self) {
        // 編集の画面は上に留めた帯に下書きの見本を描く
        let kind = if self.editor.is_some() {
            Some(page::PreviewKind::Theme)
        } else {
            self.view.preview_kind()
        };
        let source = kind.and_then(|kind| self.preview_source(kind));
        let Some(source) = source else {
            self.view.set_preview_size(None);
            return;
        };
        if let Some((key, size)) = &self.preview_natural {
            if *key == source.key {
                self.view.set_preview_size(Some(*size));
                return;
            }
        }
        if self.preview.is_none() {
            self.preview = candidate_ui::app::preview::Preview::new().ok();
        }
        let size = self.preview.as_ref().and_then(|preview| {
            preview
                .size(&source.resolved, source.font_size, source.shown())
                .ok()
        });
        self.preview_natural = size.map(|size| (source.key, size));
        self.view.set_preview_size(size);
    }

    /// 測った見本の大きさ(DIP)
    pub(super) fn preview_natural_size(&self) -> Option<(f32, f32)> {
        self.preview_natural.as_ref().map(|(_, size)| *size)
    }

    /// 見本の画像(外観の見本・パレットの見本・情報のページのアイコン)を作り直す(中身か大きさが変わったときだけ)
    fn update_preview(&mut self) {
        let shown = match self.theme_sheet() {
            Some(sheet) => Some((page::PreviewKind::Theme, sheet.preview)),
            None => self.view.preview_rect(),
        };
        let Some((kind, rect)) = shown else {
            self.preview_pixels = None;
            return;
        };
        if kind == page::PreviewKind::Icon {
            self.update_icon(rect);
            return;
        }
        let Some(source) = self.preview_source(kind) else {
            return;
        };
        let width = u32::try_from(self.theme.px(rect.width)).unwrap_or(0);
        let height = u32::try_from(self.theme.px(rect.height)).unwrap_or(0);
        let key = format!("{}|{width}x{height}", source.key);
        if self
            .preview_pixels
            .as_ref()
            .is_some_and(|(current, _)| *current == key)
        {
            return;
        }
        let scale = self.theme.dpi as f32 / ffi::BASE_DPI as f32;
        let Some(pixels) = self.render_preview_pixels(&source, width, height, scale) else {
            return;
        };
        self.preview_pixels = Some((key, pixels));
    }

    /// 見本の画像を width × height のピクセル(scale は 1 DIP あたりのピクセル)で作る．作れなければ None
    fn render_preview_pixels(
        &mut self,
        source: &PreviewSource,
        width: u32,
        height: u32,
        scale: f32,
    ) -> Option<PreviewPixels> {
        if self.preview.is_none() {
            self.preview = candidate_ui::app::preview::Preview::new().ok();
        }
        let preview = self.preview.as_ref()?;
        // 見本を捨てたあと(refresh)も前と同じ番号にしない．同じ番号だと描き先が前の画像を使い回す
        self.preview_generation += 1;
        let generation = self.preview_generation;
        // 見本のまわりの余白は置き場所(カードの中の見本の余白)でとるので，画像には余白を足さない
        let request = d2d::PreviewRequest {
            theme: &source.resolved,
            font_size: source.font_size,
            dark: self.theme.dark,
            scale,
            background: self.theme.palette.card,
            shown: source.shown(),
            // 絵文字の見本は設定の項目の名前と同じ左の端から置く(layout::place_preview)．ほかの見本は欄の真ん中
            placement: if source.emoji.is_some() {
                candidate_ui::app::preview::Placement::TopLeft {
                    ground: self.theme.palette.card,
                }
            } else {
                candidate_ui::app::preview::Placement::Fit {
                    ground: self.theme.palette.card,
                }
            },
        };
        let pixels = d2d::render_preview(preview, width, height, &request)?;
        Some(PreviewPixels {
            generation,
            width,
            height,
            pixels,
        })
    }

    /// 情報のページのアイコン(実行ファイルのリソースの 1 番)の画像を作る．カードの背景の上に描く
    /// タイトルバーのアイコンの画像を窓の DPI で作っておく
    fn update_title_icon(&mut self) {
        let dpi = self.theme.dpi;
        if self
            .title_icon
            .as_ref()
            .is_none_or(|(made, _)| *made != dpi)
        {
            let side = u32::try_from(self.theme.px(size::TITLE_BAR_ICON_SIZE)).unwrap_or(0);
            self.preview_generation += 1;
            let generation = self.preview_generation;
            self.title_icon = d2d::render_icon(side, side, None).map(|pixels| {
                (
                    dpi,
                    PreviewPixels {
                        generation,
                        width: side,
                        height: side,
                        pixels,
                    },
                )
            });
        }
    }

    fn update_icon(&mut self, rect: Rect) {
        let width = u32::try_from(self.theme.px(rect.width)).unwrap_or(0);
        let height = u32::try_from(self.theme.px(rect.height)).unwrap_or(0);
        let key = format!("icon|{}|{width}x{height}", self.theme.dark);
        if self
            .preview_pixels
            .as_ref()
            .is_some_and(|(current, _)| *current == key)
        {
            return;
        }
        // 見本を捨てたあと(refresh)も前と同じ番号にしない．同じ番号だと描き先が前の画像を使い回す
        self.preview_generation += 1;
        let generation = self.preview_generation;
        let Some(pixels) = d2d::render_icon(width, height, Some(self.theme.palette.card)) else {
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
    fn target_at(&mut self, x: f32, y: f32) -> Option<Target> {
        let (width, height) = self.size();
        let nav_width = nav_width(width);
        let now = self.now();
        // 編集の画面を開いているあいだは左の一覧を使えない．下のボタンだけを押せる
        if let Some(sheet) = self.theme_sheet() {
            if x < nav_width {
                return None;
            }
            if y >= sheet.footer.y {
                return sheet
                    .hit(x, y)
                    .filter(|action| self.theme_sheet_enabled(*action))
                    .map(Target::ThemeSheet);
            }
        }
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
        // ページの題の帯(編集の画面では見本の帯)は送らずに上に留めるので，その下に送ったページの部品は押せない
        let frame = self.page_frame();
        if y < frame.top || y >= frame.bottom {
            return None;
        }
        if self.scroll.can_scroll() && x >= width - size::SCROLLBAR_HIT && y < height {
            return Some(Target::PageScrollbar);
        }
        let page_x = x - nav_width;
        let page_y = self.page_y(y, now);
        let element = self.view.hit(page_x, page_y)?;
        if matches!(element.part, Part::Table | Part::Text) {
            if let Some(rect) = self.view.rect(element) {
                if page_x >= rect.max_x() - size::SCROLLBAR_HIT
                    && self.view.can_scroll_inside(element)
                {
                    return Some(Target::InnerScrollbar(element));
                }
            }
        }
        Some(Target::Page(element))
    }

    /// ポインターの位置(タイトルバーの下の DIP)
    fn point(&self, lparam: LPARAM) -> (f32, f32) {
        let x = (lparam.0 & 0xffff) as i16 as i32;
        let y = ((lparam.0 >> 16) & 0xffff) as i16 as i32;
        (self.theme.dip(x), self.theme.dip(y) - self.title_bar())
    }

    fn mouse_move(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        if self.import_sheet.is_some() {
            self.import_mouse_move(x, y);
            return;
        }
        if self.sheet.is_some() {
            self.sheet_mouse_move(x, y);
            return;
        }
        let now = self.now();
        let (width, height) = self.size();
        // つまみをつかんでいれば動かす
        match self.pressed {
            Some(Target::PageScrollbar) => {
                let frame = self.page_frame();
                self.scroll.drag(
                    y - frame.top - size::SCROLLBAR_MARGIN,
                    frame.bottom - frame.top - size::SCROLLBAR_MARGIN * 2.0,
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
            Some(Target::InnerScrollbar(element)) => {
                let page_y = self.page_y(y, now);
                self.view.drag_inner_scrollbar(element, page_y, now);
                ffi::invalidate(self.window);
                return;
            }
            Some(Target::Page(element)) if element.part == Part::Slider => {
                self.view.slider_drag(element, x - nav_width(width));
                // 見本のあるページは，動かしているあいだの値で見本を描き直して置き直す(文字の大きさで見本の高さが変わる)
                if self.view.preview_kind().is_some() {
                    self.arrange();
                }
                ffi::invalidate(self.window);
                return;
            }
            _ => {}
        }
        let target = self.target_at(x, y);
        // 表の中で切れた文字は，その欄に載せたときに全文を説明の吹き出しに出す(欄が変われば出し直す)
        let cell = match target {
            Some(Target::Page(element)) if element.part == Part::Table => {
                let page_x = x - nav_width(width);
                let page_y = self.page_y(y, now);
                self.view
                    .table_cell(element.row, page_x, page_y, now)
                    .filter(|(text, cell, style)| self.graphics.width(text, *style) > *cell)
                    .map(|(text, _, _)| text)
            }
            _ => None,
        };
        let cell_changed = cell.as_deref()
            != self
                .tooltip
                .as_ref()
                .filter(|_| matches!(target, Some(Target::Page(element)) if element.part == Part::Table))
                .map(|(text, ..)| text.as_str());
        if target != self.hover || cell_changed {
            self.hover = target;
            self.tooltip = match (target, cell) {
                (_, Some(text)) => Some((text, x, y, now)),
                (Some(Target::Page(element)), None) => self
                    .view
                    .tooltip(element)
                    .map(|text| (text.to_string(), x, y, now)),
                _ => None,
            };
            if self.tooltip.is_some() {
                ffi::set_timer(self.window, TOOLTIP_TIMER, TOOLTIP_DELAY);
            }
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
        // 左の一覧かページの上でポインターが動けば，そこの細いスクロールバーを出して送れることを知らせる
        if x < nav_width(width) {
            if y >= self.nav_top() {
                self.nav_scroll.reveal_bar(now);
            }
        } else {
            self.scroll.reveal_bar(now);
        }
        // 表の上なら行にも印を付ける
        let table_hover = match target {
            Some(Target::Page(element)) if element.part == Part::Table => {
                let page_y = self.page_y(y, now);
                self.view
                    .table_position(element.row, page_y, now)
                    .map(|position| (element.row, position))
            }
            _ => None,
        };
        let changed = self.view.set_table_hover(table_hover);
        let template_hover = match target {
            Some(Target::Page(element)) if element.part == Part::TemplateChips => {
                let page_y = y + self.scroll.offset(now);
                self.view
                    .template_chip_at(element.row, x - nav_width(width), page_y)
                    .map(|item| (element.row, item))
            }
            _ => None,
        };
        let changed = self.view.set_template_hover(template_hover) || changed;
        let _ = width;
        if changed || self.animating(now) || target.is_some() {
            ffi::invalidate(self.window);
        }
    }

    fn mouse_leave(&mut self) {
        let now = self.now();
        self.hover = None;
        self.tooltip = None;
        for tween in &mut self.nav_hover {
            tween.retarget(0.0, now, f64::from(motion::HOVER), Easing::LINEAR);
        }
        self.view.set_hover(None, now);
        self.view.set_scrollbar_hover(None, now);
        self.view.set_table_hover(None);
        self.view.set_template_hover(None);
        self.scroll.set_hover(false, now);
        self.nav_scroll.set_hover(false, now);
        ffi::invalidate(self.window);
    }

    /// 右クリック．表の行ならその行を選んでメニューを出す．カスタムテーマの行なら編集・複製・削除のメニューを出す
    fn right_click(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        let now = self.now();
        self.close_flyout();
        let Some(Target::Page(element)) = self.target_at(x, y) else {
            return;
        };
        if self.view.row_menu_opens(element) {
            self.open_row_menu(element.row, x, y);
            ffi::invalidate(self.window);
            return;
        }
        if element.part != Part::Table {
            return;
        }
        let page_y = self.page_y(y, now);
        let Some(position) = self.view.table_position(element.row, page_y, now) else {
            return;
        };
        if self.view.table_menu(element.row, position) {
            self.open_row_menu(element.row, x, y);
        }
        ffi::invalidate(self.window);
    }

    /// ポインターを押した．double は 2 回続けて押したとき(表の行を書き換える)
    fn mouse_down(&mut self, lparam: LPARAM, double: bool) {
        let (x, y) = self.point(lparam);
        if self.import_sheet.is_some() {
            self.import_mouse_down(x, y);
            return;
        }
        if self.sheet.is_some() {
            self.sheet_mouse_down(x, y);
            return;
        }
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
                let frame = self.page_frame();
                self.scroll.press(
                    y - frame.top - size::SCROLLBAR_MARGIN,
                    frame.bottom - frame.top - size::SCROLLBAR_MARGIN * 2.0,
                    now,
                );
                self.place_fields();
            }
            Some(Target::NavScrollbar) => {
                let top = self.nav_top();
                self.nav_scroll.press(y - top, height - top, now);
            }
            Some(Target::InnerScrollbar(element)) => {
                self.set_focus(Focus::Page(element));
                let page_y = self.page_y(y, now);
                self.view.press_inner_scrollbar(element, page_y, now);
            }
            Some(Target::Nav(_)) => self.set_focus(Focus::Nav),
            Some(Target::ThemeSheet(action)) => self.focus = Focus::ThemeSheet(action),
            Some(Target::Page(element)) if matches!(element.part, Part::TableChoice(_)) => {
                // 表の行の中の選ぶ欄は，その行を選んでから(離したときに)一覧を開く
                self.set_focus(Focus::Page(Element {
                    row: element.row,
                    part: Part::Table,
                }));
                if let Part::TableChoice(position) = element.part {
                    let event = self
                        .view
                        .table_click(element.row, position, false, false, false);
                    self.dispatch(event);
                }
            }
            Some(Target::Page(element)) => {
                if self.view.edit(element).is_none() {
                    self.set_focus(Focus::Page(element));
                }
                if element.part == Part::Slider {
                    let (width, _) = self.size();
                    self.view.slider_drag(element, x - nav_width(width));
                }
                if element.part == Part::TemplateChips {
                    let page_y = y + self.scroll.offset(now);
                    let (width, _) = self.size();
                    if let Some(item) =
                        self.view
                            .template_chip_at(element.row, x - nav_width(width), page_y)
                    {
                        self.insert_template(element.row, Some(item));
                    }
                    return;
                }
                if element.part == Part::Table {
                    let page_y = self.page_y(y, now);
                    let (width, _) = self.size();
                    let page_x = x - nav_width(width);
                    // 見出しを押したらその列で並べ替える(macOS の表と同じ)
                    if self.view.table_header_click(element.row, page_x, page_y) {
                        ffi::invalidate(self.window);
                        return;
                    }
                    let (width, _) = self.size();
                    let page_x = x - nav_width(width);
                    if let Some(position) = self.view.table_position(element.row, page_y, now) {
                        // 「有効」の列の印を押したら，その行の有効・無効を切り替える
                        if let Some(event) =
                            self.view.table_check_click(element.row, page_x, position)
                        {
                            self.dispatch(Some(event));
                            return;
                        }
                        let (control, shift) = ffi::modifiers();
                        let event =
                            self.view
                                .table_click(element.row, position, control, shift, double);
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
        if self.import_sheet.is_some() {
            self.import_mouse_up(x, y);
            return;
        }
        if self.sheet.is_some() {
            self.sheet_mouse_up(x, y);
            return;
        }
        let now = self.now();
        let pressed = self.pressed.take();
        ffi::release_capture();
        self.scroll.release(now);
        self.nav_scroll.release(now);
        self.view.release_inner_scrollbars(now);
        // スライダーは手を離したときに値を書く(押したところから外れても書く)
        if matches!(pressed, Some(Target::Page(element)) if element.part == Part::Slider) {
            let event = self.view.slider_release();
            self.dispatch(event);
            ffi::invalidate(self.window);
            return;
        }
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
            (Some(Target::ThemeSheet(action)), Some(Target::ThemeSheet(over)))
                if action == over =>
            {
                self.dispatch(Some(Event::ThemeEditor(action)));
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
        if element.part == Part::TemplateChips {
            self.insert_template(element.row, None);
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
        if let Some(sheet) = self.import_sheet.as_mut() {
            // シートの表を送る(表の外でも送る．シートの後ろのページは送らない)
            sheet.scroll.scroll_by(amount, now);
            ffi::invalidate(self.window);
            return;
        }
        if self.sheet.is_some() {
            return;
        }
        // ホイールの位置は画面の座標
        let screen_x = (lparam.0 & 0xffff) as i16 as i32;
        let screen_y = ((lparam.0 >> 16) & 0xffff) as i16 as i32;
        let (client_x, client_y) = ffi::to_client(self.window, screen_x, screen_y);
        let (x, y) = (
            self.theme.dip(client_x),
            self.theme.dip(client_y) - self.title_bar(),
        );
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
            Focus::Nav | Focus::ThemeSheet(_) => None,
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
        // 編集の画面では，ページの部品と下のボタンだけを巡る(左の一覧と検索には移らない)
        let mut stops = if self.editor.is_some() {
            Vec::new()
        } else {
            vec![Focus::Search, Focus::Nav]
        };
        if self.availability() == Availability::Ready {
            stops.extend(self.view.focusable().into_iter().map(Focus::Page));
        }
        if let Some(sheet) = self.theme_sheet() {
            stops.extend(
                sheet
                    .buttons
                    .iter()
                    .map(|(action, _)| *action)
                    .filter(|action| self.theme_sheet_enabled(*action))
                    .map(Focus::ThemeSheet),
            );
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
        if self.import_sheet.is_some() {
            return self.import_key(key, shift);
        }
        if self.sheet.is_some() {
            return self.sheet_key(key, shift);
        }
        if key == VK_TAB.0 {
            self.move_focus(shift);
            return true;
        }
        // 編集の画面は Esc で閉じる(macOS の cancelAction)
        if key == VK_ESCAPE.0 && self.editor.is_some() {
            self.dispatch(Some(Event::ThemeEditor(EditorAction::Cancel)));
            return true;
        }
        self.focus_visible = true;
        // 編集の画面を開いているあいだは左の一覧でページを移らない
        if self.editor.is_some() && matches!(self.focus, Focus::Nav | Focus::Search) {
            return self.page_key(key, control);
        }
        match self.focus {
            Focus::ThemeSheet(action) => {
                if key == VK_SPACE.0 || key == VK_RETURN.0 {
                    self.dispatch(Some(Event::ThemeEditor(action)));
                    return true;
                }
                self.page_key(key, control)
            }
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
        // 書き方のチップの欄の中で Esc を押したら閉じて，書き方を入れる欄に戻る
        if key == VK_ESCAPE.0
            && matches!(
                element.part,
                Part::TemplateChips | Part::TemplateSegment(_) | Part::TemplateButton
            )
        {
            let field = self.view.template_field(element.row);
            let event = self.view.close_templates(element.row);
            if event.is_some() {
                self.dispatch(event);
                if let Some(field) = field {
                    ffi::focus(field);
                }
                return true;
            }
        }
        match element.part {
            // チップは矢印で隣に移り，Space・Enter で欄に入れる
            Part::TemplateChips => {
                let delta = match key {
                    k if k == VK_LEFT.0 || k == VK_UP.0 => -1,
                    k if k == VK_RIGHT.0 || k == VK_DOWN.0 => 1,
                    k if k == VK_SPACE.0 || k == VK_RETURN.0 => {
                        self.press(element);
                        return true;
                    }
                    _ => return false,
                };
                if self.view.move_template_cursor(element.row, delta) {
                    ffi::invalidate(self.window);
                }
                true
            }
            Part::Table => {
                let page = self.view.table_page(element.row);
                let movement = match key {
                    k if k == VK_UP.0 => Move::Up,
                    k if k == VK_DOWN.0 => Move::Down,
                    k if k == VK_PRIOR.0 => Move::PageUp(page),
                    k if k == VK_NEXT.0 => Move::PageDown(page),
                    k if k == VK_HOME.0 => Move::Home,
                    k if k == VK_END.0 => Move::End,
                    // 選んだコマンドをシートで書き換える(macOS の表の primaryAction)
                    k if k == VK_RETURN.0 => {
                        let event = self.view.table_enter(element.row);
                        self.dispatch(event);
                        return true;
                    }
                    // 選んだ行の中の選ぶ欄を開く(除外設定の動作)
                    k if k == VK_SPACE.0 || k == VK_F4.0 => {
                        if let Some(choice) = self.view.table_choice(element.row) {
                            self.open_flyout(choice);
                        }
                        return true;
                    }
                    k if k == VK_DELETE.0 => {
                        // 選んだ行を消すボタンを押す
                        let Some(part) = self.view.remove_part(element.row) else {
                            return true;
                        };
                        let remove = Element {
                            row: element.row,
                            part,
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
                    k if k == VK_PRIOR.0 => -step * size::TABLE_PAGE_ROWS,
                    k if k == VK_NEXT.0 => step * size::TABLE_PAGE_ROWS,
                    _ => return false,
                };
                self.view.scroll_inside(element, delta, now);
                ffi::invalidate(self.window);
                true
            }
            // 数の部品は矢印で 1 段ずつ，Home・End で端まで動かす(WinUI の Slider と同じ)
            Part::Slider | Part::Decrement | Part::Increment => {
                let delta = match key {
                    k if k == VK_LEFT.0 || k == VK_DOWN.0 => -1,
                    k if k == VK_RIGHT.0 || k == VK_UP.0 => 1,
                    k if k == VK_HOME.0 => isize::MIN / 2,
                    k if k == VK_END.0 => isize::MAX / 2,
                    k if (k == VK_SPACE.0 || k == VK_RETURN.0) && element.part != Part::Slider => {
                        self.press(element);
                        return true;
                    }
                    _ => return false,
                };
                let event = self.view.step(element, delta);
                self.dispatch(event);
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
            k if k == VK_PRIOR.0 => self.scroll.scroll_by(-height * size::PAGE_SCROLL, now),
            k if k == VK_NEXT.0 => self.scroll.scroll_by(height * size::PAGE_SCROLL, now),
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
            Focus::ThemeSheet(action) => Some(NODE_THEME_SHEET + theme_sheet_index(action)),
            _ => None,
        }
    }

    /// 窓の中の DIP の四角を画面のピクセルの四角(左・上・幅・高さ)にする
    fn screen_rect(&self, rect: Rect) -> (i32, i32, i32, i32) {
        let (left, top) = self.client_px(rect.x, rect.y);
        let (right, bottom) = self.client_px(rect.max_x(), rect.max_y());
        let (x, y) = ffi::to_screen(self.window, left, top);
        (x, y, right - left, bottom - top)
    }

    fn nodes(&self) -> Vec<uia::Node> {
        if let Some(nodes) = self.import_nodes() {
            return nodes;
        }
        if let Some(nodes) = self.sheet_nodes() {
            return nodes;
        }
        let now = self.now();
        let (width, _) = self.size();
        let nav_width = nav_width(width);
        let nav_top = self.nav_top();
        let nav_offset = self.nav_scroll.offset(now);
        // 編集の画面を開いているあいだは，左の一覧と検索を読ませない(使えないので)
        if let Some(sheet) = self.theme_sheet() {
            let mut nodes: Vec<uia::Node> = sheet
                .buttons
                .iter()
                .map(|(action, rect)| uia::Node {
                    id: NODE_THEME_SHEET + theme_sheet_index(*action),
                    role: uia::Role::Button,
                    name: super::editor::label(*action).to_string(),
                    rect: self.screen_rect(*rect),
                    enabled: self.theme_sheet_enabled(*action),
                    focused: self.focus == Focus::ThemeSheet(*action),
                    toggled: None,
                    expanded: None,
                    value: None,
                    selected: None,
                    host: None,
                    parent: None,
                })
                .collect();
            nodes.extend(self.page_nodes(now));
            return nodes;
        }
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
            parent: None,
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
                parent: None,
            });
        }
        nodes.extend(self.page_nodes(now));
        nodes
    }

    /// ページの部品の読み上げの節
    fn page_nodes(&self, now: f64) -> Vec<uia::Node> {
        let mut nodes = Vec::new();
        if self.availability() != Availability::Ready {
            return nodes;
        }
        let (width, _) = self.size();
        let nav_width = nav_width(width);
        let offset = self.scroll.offset(now) - self.page_frame().shift;
        for element in self.view.elements() {
            let Some(described) = self.view.describe(element) else {
                continue;
            };
            let Some(rect) = self.view.rect(element) else {
                continue;
            };
            let mut host = None;
            let mut selected = None;
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
                Described::Slider(value) => (uia::Role::Slider, None, None, Some(value)),
                Described::Radio(on) => {
                    selected = Some(on);
                    (uia::Role::RadioButton, None, None, None)
                }
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
                selected,
                host,
                parent: None,
            });
        }
        nodes
    }

    fn accessibility_act(&mut self, id: i32, act: uia::Act) {
        if self.import_sheet.is_some() {
            // 表の行: フォーカス・選ぶは，その行を選んで表にフォーカスを置く
            if let Some(sheet) = self.import_sheet.as_mut() {
                let count = sheet.rows().len();
                if let Some(row) = (0..count).find(|row| import_row_node(*row) == id) {
                    sheet.focus = ImportPart::Table;
                    sheet.cursor = row;
                    self.import_focus_changed();
                    ffi::invalidate(self.window);
                    return;
                }
            }
            if let Some(part) = self.import_sheet_layout().and_then(|layout| {
                layout
                    .order()
                    .into_iter()
                    .find(|part| import_node(*part) == id)
            }) {
                match act {
                    uia::Act::Focus => {
                        if let Some(sheet) = self.import_sheet.as_mut() {
                            sheet.focus = part;
                        }
                    }
                    _ => self.import_press(part),
                }
                ffi::invalidate(self.window);
            }
            return;
        }
        if self.sheet.is_some() {
            self.sheet_act(id, act);
            return;
        }
        if let Some(sheet) = self.theme_sheet() {
            if let Some((action, _)) = sheet
                .buttons
                .iter()
                .find(|(action, _)| NODE_THEME_SHEET + theme_sheet_index(*action) == id)
            {
                match act {
                    uia::Act::Focus => self.set_focus(Focus::ThemeSheet(*action)),
                    _ => self.dispatch(Some(Event::ThemeEditor(*action))),
                }
                return;
            }
            // 左の一覧と検索は使えない
            if id < NODE_PAGE {
                return;
            }
        }
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
        self.view.reset_key_menu(element);
        self.open_flyout_at(element, None);
    }

    /// 部品の左下の画面の座標(キーボードで開いたメニューを部品の下に出すため)．部品が無ければ None
    pub(super) fn screen_below(&self, element: Element) -> Option<(i32, i32)> {
        let rect = self.view.rect(element)?;
        let (left, top) = self.window_point(rect.x, rect.max_y());
        let (x, y) = self.client_px(left, top);
        Some(ffi::to_screen(self.window, x, y))
    }

    /// ページの中の点を窓の中の点(DIP)にする
    fn window_point(&self, x: f32, y: f32) -> (f32, f32) {
        let (width, _) = self.size();
        (
            nav_width(width) + x,
            y - self.scroll.offset(self.now()) + self.page_frame().shift,
        )
    }

    /// 表の行のメニューを (x, y)(窓の中の DIP)に出す(macOS の表の contextMenu)
    fn open_row_menu(&mut self, row: usize, x: f32, y: f32) {
        let element = Element {
            row,
            part: Part::RowMenu,
        };
        // メニューの幅は WinUI の MenuFlyout と同じく，項目が短くても最小の幅を取る
        self.open_flyout_at(element, Some(Rect::new(x, y, size::SEGMENT_MIN_WIDTH, 0.0)));
    }

    /// 一覧の行の並びと大きさ(DIP)．幅は開いた部品の幅か，いちばん長い名前が収まる幅の広いほう
    fn flyout_size(
        &self,
        items: &[String],
        groups: &[crate::options::ChoiceGroup],
        anchor_width: f32,
    ) -> (MenuLayout, f32, f32) {
        let layout = MenuLayout::new(items.len(), groups);
        let widest = items
            .iter()
            .map(|label| self.graphics.width(label, TextStyle::Body))
            .chain(
                layout
                    .headings()
                    .map(|title| self.graphics.width(title, TextStyle::Caption)),
            )
            .fold(0.0f32, f32::max);
        let width = anchor_width
            .max(widest + size::FIELD_PADDING_X * 2.0 + size::NAV_INDICATOR_WIDTH * 2.0);
        let height = (layout.height() + size::FLYOUT_PADDING * 2.0).min(size::DROPDOWN_HEIGHT);
        (layout, width, height)
    }

    /// 一覧を出す．anchor(窓の中の DIP)があればその下に，無ければ部品の下に出す．下に収まらなければ上に出す
    fn open_flyout_at(&mut self, element: Element, anchor: Option<Rect>) {
        let now = self.now();
        let groups = if element == SHEET_KIND {
            &[]
        } else {
            self.view.dropdown_groups(element)
        };
        let (items, selected, left, top, rect) = if element == SHEET_KIND {
            // シートの動作(窓の中の位置)
            let Some((sheet, layout)) = self.sheet.as_ref().zip(self.sheet_layout()) else {
                return;
            };
            let (items, selected) = sheet.kinds();
            let Some(rect) = layout.rect(SheetPart::Kind) else {
                return;
            };
            (items, Some(selected), rect.x, rect.y, rect)
        } else if let Some(anchor) = anchor {
            let (items, selected) = self.view.dropdown_items(element);
            (items, selected, anchor.x, anchor.y, anchor)
        } else {
            let (items, selected) = self.view.dropdown_items(element);
            let Some(rect) = self.view.menu_rect(element) else {
                return;
            };
            // ページの中の位置を窓の中の位置にする
            let (left, top) = self.window_point(rect.x, rect.y);
            (items, selected, left, top, rect)
        };
        if items.is_empty() {
            return;
        }
        let padding = size::FLYOUT_PADDING;
        let (layout, flyout_width, flyout_height) = self.flyout_size(&items, groups, rect.width);
        let (client_left, client_top) = self.client_px(left, top + rect.height + padding);
        let (screen_left, screen_top) = ffi::to_screen(self.window, client_left, client_top);
        let (_, client_above) = self.client_px(0.0, top - padding - flyout_height);
        let (_, above_top) = ffi::to_screen(self.window, 0, client_above);
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
        scroll.set_extent(layout.height(), viewport);
        if let Some((selected_top, selected_bottom)) =
            selected.and_then(|selected| layout.item_span(selected))
        {
            scroll.jump_to(selected_top - (viewport - (selected_bottom - selected_top)) / 2.0);
        }
        self.flyout = Some(Flyout {
            element,
            window,
            surface: Surface::new(window),
            items,
            layout,
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
        if let Some(sheet) = self.sheet.as_mut().filter(|_| element == SHEET_KIND) {
            sheet.open = true;
        }
        ffi::invalidate(self.window);
    }

    pub(super) fn close_flyout(&mut self) {
        if let Some(flyout) = self.flyout.take() {
            ffi::destroy(flyout.window);
            ffi::invalidate(self.window);
        }
        if let Some(sheet) = self.sheet.as_mut() {
            sheet.open = false;
        }
    }

    fn flyout_choose(&mut self, index: usize) {
        let Some(flyout) = self.flyout.as_ref() else {
            return;
        };
        let element = flyout.element;
        self.close_flyout();
        if element == SHEET_KIND {
            self.sheet_choose_kind(index);
            return;
        }
        let event = if element.part == Part::RowMenu {
            let now = self.now();
            self.view.choose_row_menu(element.row, index, now)
        } else {
            self.view.choose(element, index)
        };
        self.dispatch(event);
        // キーを選ぶメニューのファンクションキーの項目は，続けてその一覧を同じ場所に出す(macOS の KeyField のサブメニュー)
        if self.view.opens_key_functions(element) {
            self.open_flyout_at(element, None);
        }
        ffi::invalidate(self.window);
    }

    fn flyout_key(&mut self, key: u16) -> bool {
        let Some(flyout) = self.flyout.as_mut() else {
            return false;
        };
        let current = flyout.hover.or(flyout.selected);
        // 矢印は項目だけを動く(組の見出しと区切りの線は飛ばす)
        let next = match key {
            k if k == VK_UP.0 => flyout.layout.moved(current, MenuMove::Up),
            k if k == VK_DOWN.0 => flyout.layout.moved(current, MenuMove::Down),
            k if k == VK_HOME.0 => flyout.layout.moved(current, MenuMove::First),
            k if k == VK_END.0 => flyout.layout.moved(current, MenuMove::Last),
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
            if let Some((top, bottom)) = flyout.layout.reveal_span(next) {
                flyout.scroll.reveal(top, bottom, now);
            }
            ffi::invalidate(flyout.window);
        }
        true
    }

    /// ドロップダウンの一覧の窓の中のポインターの位置(DIP)．一覧の窓にはタイトルバーが無いので，
    /// 設定の窓の point と違ってタイトルバーの高さを引かない(引くと 1 項目上を選んでしまう)
    fn flyout_local(&self, lparam: LPARAM) -> (f32, f32) {
        let x = (lparam.0 & 0xffff) as i16 as i32;
        let y = ((lparam.0 >> 16) & 0xffff) as i16 as i32;
        (self.theme.dip(x), self.theme.dip(y))
    }

    /// ドロップダウンの一覧の点がスクロールバーの上なら，トラックの中の y(上からの距離)とトラックの高さ
    fn flyout_scrollbar_point(&self, lparam: LPARAM) -> Option<(f32, f32)> {
        let flyout = self.flyout.as_ref()?;
        let (x, y) = self.flyout_local(lparam);
        let grabbing = flyout.scroll.grabbing();
        if !flyout.scroll.can_scroll() || (!grabbing && x < flyout.width - size::SCROLLBAR_HIT) {
            return None;
        }
        // paint_flyout の body の中に，page::scrollbar と同じ余白で置いたトラック
        let top = size::FLYOUT_PADDING + size::SCROLLBAR_MARGIN;
        let track = flyout.height - (size::FLYOUT_PADDING + size::SCROLLBAR_MARGIN) * 2.0;
        Some((y - top, track))
    }

    /// ドロップダウンの一覧でボタンを押した．スクロールバーの上ならつかむ
    fn flyout_press(&mut self, lparam: LPARAM) {
        let now = self.now();
        let Some((y, track)) = self.flyout_scrollbar_point(lparam) else {
            return;
        };
        if let Some(flyout) = self.flyout.as_mut() {
            flyout.scroll.press(y, track, now);
            ffi::capture(flyout.window);
            ffi::invalidate(flyout.window);
        }
    }

    /// ドロップダウンの一覧の上でポインターを動かした．つまみをつかんでいれば送り，そうでなければ項目に印を付ける
    fn flyout_move(&mut self, lparam: LPARAM) {
        let now = self.now();
        let bar = self.flyout_scrollbar_point(lparam);
        let index = self.flyout_point(lparam);
        let Some(flyout) = self.flyout.as_mut() else {
            return;
        };
        if flyout.scroll.grabbing() {
            if let Some((y, track)) = bar {
                flyout.scroll.drag(y, track, now);
            }
            ffi::invalidate(flyout.window);
            return;
        }
        let over_bar = bar.is_some();
        if flyout.scroll.hover() != over_bar {
            flyout.scroll.set_hover(over_bar, now);
            ffi::invalidate(flyout.window);
        }
        if over_bar {
            return;
        }
        if flyout.hover != index && index.is_some() {
            flyout.hover = index;
            ffi::invalidate(flyout.window);
        }
    }

    /// ドロップダウンの一覧でボタンを放した．つまみを放したときは選ばない
    fn flyout_release(&mut self, lparam: LPARAM) {
        let now = self.now();
        if let Some(flyout) = self.flyout.as_mut() {
            if flyout.scroll.grabbing() {
                flyout.scroll.release(now);
                ffi::release_capture();
                ffi::invalidate(flyout.window);
                return;
            }
        }
        if self.flyout_scrollbar_point(lparam).is_some() {
            return;
        }
        if let Some(index) = self.flyout_point(lparam) {
            self.flyout_choose(index);
        }
    }

    fn flyout_point(&self, lparam: LPARAM) -> Option<usize> {
        let flyout = self.flyout.as_ref()?;
        let (_, y) = self.flyout_local(lparam);
        let now = self.now();
        let local = y - size::FLYOUT_PADDING + flyout.scroll.offset(now);
        // 組の見出しと区切りの線の上は項目にならない(載せても押しても何もしない)
        flyout.layout.item_at(local)
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
        let layout = &flyout.layout;
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
                    canvas, &theme, items, layout, selected, hover, scroll, opened, width, height,
                    now,
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
            if let Some(sheet) = self.sheet.as_mut() {
                if let Some(part) = sheet.part_of(window) {
                    sheet.focus = part;
                }
            } else if window == self.search {
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

    /// 欄がキーの記録を始めた・やめた．キーの欄の右のボタン(メニューか「記録を停止」)を入れ替える
    fn field_recording(&mut self, window: Window, recording: bool) {
        self.view.set_recording(window, recording);
        // 「記録を停止」を押して記録をやめたら，フォーカスを同じ場所のメニューのボタンに移す
        if let Focus::Page(element) = self.focus {
            if element.part == Part::KeyStop && !recording {
                self.focus = Focus::Page(Element {
                    row: element.row,
                    part: Part::KeyMenu,
                });
            }
        }
        ffi::invalidate(self.window);
    }

    /// 「キーで検索」で押したキーを受け取った．そのキーの行だけを出す
    fn key_captured(&mut self, window: Window) {
        let Some(notation) = edit::take_captured(window) else {
            return;
        };
        let event = self.view.key_captured(window, &notation);
        self.dispatch(event);
        ffi::invalidate(self.window);
    }

    fn field_changed(&mut self, window: Window) {
        if let Some(sheet) = self.sheet.as_mut() {
            if let Some(part) = sheet.part_of(window) {
                sheet.set_text(part, ffi::window_text(window));
                ffi::invalidate(self.window);
            }
            return;
        }
        if window == self.search {
            self.fill_nav();
            return;
        }
        let Some(element) = self.view.element_of(window) else {
            return;
        };
        // 書き方を入れる欄で「{」を打ったらチップを開き，打ちかけの書き方で絞り込む
        let typed = self.view.template_typed(element);
        self.dispatch(typed);
        let event = self.view.edited(element);
        self.dispatch(event);
        // 打った行の確かめの文と追加のボタンを描き直す
        ffi::invalidate(self.window);
    }

    /// 欄で Esc を押した．書き方のチップを開いていれば閉じる(欄のフォーカスはそのまま)
    fn field_escape(&mut self, window: Window) {
        if self.editor.is_some() {
            self.dispatch(Some(Event::ThemeEditor(EditorAction::Cancel)));
            return;
        }
        if self.sheet.is_some() {
            self.close_sheet();
            return;
        }
        let Some(element) = self.view.element_of(window) else {
            return;
        };
        let event = self.view.close_templates(element.row);
        self.dispatch(event);
    }

    /// 書き方のチップ(item 番目．None ならキーボードで選んでいるチップ)を欄に入れる．
    /// ポインターで押したときは欄にフォーカスを戻し，続けて打てるようにする．キーボードで押したときはチップに残る
    fn insert_template(&mut self, row: usize, item: Option<usize>) {
        let Some(window) = self.view.insert_template(row, item) else {
            return;
        };
        // 窓の処理の中で書き換えたので，欄の知らせ(EN_CHANGE)の代わりにここで映す
        self.field_changed(window);
        if item.is_some() {
            ffi::focus(window);
        }
        ffi::invalidate(self.window);
    }

    fn field_enter(&mut self, window: Window) {
        if self.sheet.is_some() {
            self.save_sheet();
            return;
        }
        let Some(element) = self.view.element_of(window) else {
            return;
        };
        let now = self.now();
        let event = self.view.submit(element, now);
        self.dispatch(event);
    }

    // MARK: - 見本の書き出し(--render-snapshots)

    /// 残りの 1 枚を書き出して，次を頼む．終わったら窓を閉じる(プロセスを終える)．
    /// ページは中身の高さまで伸ばして 1 枚にし(送らずに全体を写す)，打つ欄の文字は自分で描く(EDIT は写らない)
    fn snapshot_step(&mut self) {
        let Some((directory, mut jobs)) = self.snapshots.take() else {
            return;
        };
        let Some((page, shot, dark)) = jobs.pop() else {
            ffi::destroy(self.window);
            return;
        };
        // 書き方のチップ: 開いているか(閉じた状態はふつうの 1 枚)と，「入力時の値にする」のオン・オフ
        self.templates_open = if matches!(
            shot,
            Shot::Plain
                | Shot::DynamicOff
                | Shot::ImportPreview
                | Shot::MissingKeys
                | Shot::GroupedMenu
                | Shot::KeyDraft
                | Shot::KeyRecording
        ) {
            std::collections::HashSet::new()
        } else {
            [pages::TemplateTarget::Word, pages::TemplateTarget::Macro].into()
        };
        if page == Page::Dictionary {
            if let Some(model) = &mut self.model {
                let _ = model.set(
                    "dynamicDictionary",
                    serde_json::Value::Bool(shot != Shot::DynamicOff),
                );
            }
        }
        // キーの無い知らせ: キー設定の表から確定の行を消して写し，写したら元の表に戻す
        let mut restored_keymap = None;
        if shot == Shot::MissingKeys {
            if let Some(model) = &mut self.model {
                if let Some(keymap) = model.value("keymap").cloned() {
                    let without_commit: Vec<serde_json::Value> = keymap
                        .as_array()
                        .into_iter()
                        .flatten()
                        .filter(|row| row["command"] != "commit")
                        .cloned()
                        .collect();
                    let _ = model.set("keymap", serde_json::Value::Array(without_commit));
                    restored_keymap = Some(keymap);
                }
            }
        }
        self.forced_theme = Some(if dark {
            ForcedTheme::Dark
        } else {
            ForcedTheme::Light
        });
        let dpi = self.theme.dpi;
        self.reload_theme(dpi);
        self.open_page(page);
        // 打ちかけの書き方で絞り込んだ状態: 単語の欄に「締切 {da」を打ったことにする(窓の処理の中なので知らせを自分で映す)
        if shot == Shot::Typing {
            if let Some(field) = self.view.first_template_field() {
                ffi::edit::replace(field, 0..0, "締切 {da");
                self.field_changed(field);
            }
        }
        // キー設定の新しい行: 表にある行と同じキーを入れて足す前の知らせを出し，そのキーで表を絞り込む．
        // 記録しているところは，欄を空にして案内と「記録を停止」を出す(欄にフォーカスは入れない)
        match shot {
            Shot::KeyDraft => {
                self.view.show_key_draft(SNAPSHOT_KEY, false);
                self.view.show_key_filter(SNAPSHOT_KEY);
            }
            Shot::KeyRecording => self.view.show_key_draft("", true),
            _ => {}
        }
        // 取り込む前のシート: 見本のエンジンはファイルを読めないので，macOS の見本と同じ中身を渡す
        self.import_sheet = None;
        if shot == Shot::ImportPreview {
            self.open_import_sheet(import_sample());
        }
        self.scroll.jump_to(0.0);
        let (width, height) = self.size();
        // 見本(外観・パレット・絵文字)の行の高さは見本を描いた大きさで決まるので，置く前に測る
        self.measure_preview();
        let content = self.view.arrange(width - nav_width(width), &self.graphics);
        // 見本の画像は書き出す倍率で作り，画面と同じ場所に描く(作らないと見本の行が空いて写る)
        let snapshot_preview = self.view.preview_rect().and_then(|(kind, rect)| {
            let source = (kind != page::PreviewKind::Icon)
                .then(|| self.preview_source(kind))
                .flatten()?;
            let scale = tokens::size::snapshot::SCALE;
            let pixel = |value: f32| (value * scale).round().max(0.0) as u32;
            self.render_preview_pixels(&source, pixel(rect.width), pixel(rect.height), scale)
        });
        // シートは窓の真ん中に出すので，窓の大きさで写す
        let total = if self.import_sheet.is_some() {
            height
        } else {
            content.max(height)
        };
        // 組に分けた一覧: 一覧は別の窓に描くものなので，同じ描き方でページの上に重ねて写す
        let menu = (shot == Shot::GroupedMenu)
            .then(|| self.view.grouped_dropdown())
            .flatten()
            .and_then(|element| {
                let rect = self.view.rect(element)?;
                let (items, selected) = self.view.dropdown_items(element);
                let groups = self.view.dropdown_groups(element);
                let (layout, menu_width, menu_height) =
                    self.flyout_size(&items, groups, rect.width);
                let origin = (
                    nav_width(width) + rect.x,
                    rect.max_y() + size::FLYOUT_PADDING,
                );
                Some((
                    element,
                    items,
                    selected,
                    layout,
                    origin,
                    menu_width,
                    menu_height,
                ))
            });
        let total = menu.as_ref().map_or(total, |menu| {
            total.max(menu.4 .1 + menu.6 + size::FLYOUT_PADDING)
        });
        let now = self.now() + SNAPSHOT_SETTLE;
        let name = format!(
            "settings-{}{}-{}.png",
            format!("{page:?}").to_lowercase(),
            shot.suffix(),
            if dark { "dark" } else { "light" }
        );
        let _ = std::fs::create_dir_all(&directory);
        let state = PaintState {
            theme: &self.theme,
            now,
            width,
            height: total,
            focus: Focus::Nav,
            focus_visible: false,
            focused_edit: None,
            pressed: None,
            open: menu.as_ref().map(|menu| menu.0),
            nav_hover: &self.nav_hover,
            nav_indicator: self.nav_indicator.value(now),
            enter: 1.0,
            availability: self.availability(),
            search: self.search_rect(),
            nav_top: self.nav_top(),
            // ページは中身の高さまで伸ばして 1 枚にする(送らずに全体を写す)
            frame: PageFrame {
                top: page_header(),
                bottom: total,
                shift: 0.0,
            },
            theme_sheet: None,
            draw_fields: true,
        };
        let written = ffi::d2d::write_png(
            &self.graphics,
            (width, total),
            tokens::size::snapshot::SCALE,
            Color::from(self.theme.palette.background),
            &directory.join(&name),
            snapshot_preview.as_ref(),
            |canvas| {
                paint_window(
                    canvas,
                    &state,
                    &self.nav,
                    &self.nav_scroll,
                    &self.view,
                    &self.scroll,
                );
                if let (Some(sheet), Some(layout)) =
                    (self.import_sheet.as_ref(), self.import_sheet_layout())
                {
                    let frame = sheet::SheetFrame {
                        theme: &self.theme,
                        size: (width, total),
                        focused_edit: None,
                        hover: 0.0,
                    };
                    import_sheet::paint(canvas, sheet, &layout, &frame, now);
                }
                if let Some((_, items, selected, layout, (left, top), menu_width, menu_height)) =
                    &menu
                {
                    let mut menu_scroll = Scroller::default();
                    menu_scroll
                        .set_extent(layout.height(), menu_height - size::FLYOUT_PADDING * 2.0);
                    canvas.translate(*left, *top);
                    canvas.fill_round(
                        Rect::new(0.0, 0.0, *menu_width, *menu_height),
                        size::FLYOUT_RADIUS,
                        Color::from(self.theme.palette.flyout),
                    );
                    paint_flyout_items(
                        canvas,
                        &self.theme,
                        items,
                        layout,
                        *selected,
                        *selected,
                        &menu_scroll,
                        1.0,
                        *menu_width,
                        *menu_height,
                        now,
                    );
                    canvas.translate(-*left, -*top);
                }
            },
        );
        self.import_sheet = None;
        if let Err(error) = written {
            eprintln!("{name} を書き出せませんでした: {error}");
        }
        if let (Some(keymap), Some(model)) = (restored_keymap, &mut self.model) {
            let _ = model.set("keymap", keymap);
        }
        // キーの欄は使い回すので，入れた文字を残さない
        if matches!(shot, Shot::KeyDraft | Shot::KeyRecording) {
            self.view.show_key_draft("", false);
        }
        self.snapshots = Some((directory, jobs));
        ffi::post(self.window, WM_SNAPSHOT, 0, 0);
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

// MARK: - コマンドのシート

impl App {
    /// シートを出す．index は書き換えるコマンドの表の行(足すなら None)
    pub(super) fn open_command_sheet(&mut self, index: Option<usize>) {
        if self.sheet.is_some() {
            return;
        }
        let Some((spec, _)) = self.view.list_spec(pages::COMMANDS) else {
            return;
        };
        let Some(model) = self.model.as_ref() else {
            return;
        };
        let list = model.value(spec.path);
        let draft = match index {
            Some(index) => {
                let Some(item) = spec.items(list).get(index).cloned() else {
                    return;
                };
                crate::commands::CommandDraft::from_item(spec.id_at(list, index), &item)
            }
            None => crate::commands::CommandDraft::default(),
        };
        let Some(font) = &self.field_font else {
            return;
        };
        // 打つ欄は使い回しの欄から取る(無ければ作る)
        let mut fields = Vec::new();
        for (offset, prompt) in ["", "", draft.target_prompt()].into_iter().enumerate() {
            let window = self.pool.pop().or_else(|| {
                let id = u16::try_from(offset)
                    .unwrap_or(0)
                    .wrapping_add(SHEET_FIELD_ID);
                edit::create(self.window, id, "", font)
            });
            let Some(window) = window else {
                fields.into_iter().for_each(|window| self.pool.push(window));
                return;
            };
            edit::set_record_on_click(window, None);
            edit::set_placeholder(window, prompt);
            fields.push(window);
        }
        let Ok(fields) = <[Window; 3]>::try_from(fields) else {
            return;
        };
        ffi::set_text(fields[0], &draft.reading);
        ffi::set_text(fields[1], &draft.title);
        ffi::set_text(fields[2], &draft.target);
        self.close_flyout();
        self.hover = None;
        self.tooltip = None;
        self.view.set_hover(None, self.now());
        self.view.set_table_hover(None);
        self.sheet = Some(CommandSheet::new(draft, index, fields));
        self.place_search();
        self.place_fields();
        self.sheet_focus(SheetPart::Reading);
        ffi::invalidate(self.window);
    }

    /// シート(コマンドか，取り込む前の中身)を出しているか．出しているあいだは窓の中身の打つ欄を隠す
    fn modal_open(&self) -> bool {
        self.sheet.is_some() || self.import_sheet.is_some()
    }

    // MARK: - 取り込む前に中身を見せるシート

    /// 取り込む前に中身を見せるシートを出す
    pub(super) fn open_import_sheet(&mut self, pending: PendingImport) {
        self.close_flyout();
        self.hover = None;
        self.tooltip = None;
        self.view.set_hover(None, self.now());
        self.view.set_table_hover(None);
        let mut sheet = ImportSheet::new(pending);
        let viewport = self
            .import_layout_for(&sheet)
            .map_or(0.0, |layout| layout.body.height);
        sheet
            .scroll
            .set_extent(ImportLayout::content_height(&sheet), viewport);
        self.import_sheet = Some(sheet);
        self.place_search();
        self.place_fields();
        ffi::focus(self.window);
        ffi::invalidate(self.window);
    }

    /// 取り込む前の中身のシートを閉じる(何も登録しない)．閉じたシートを返す
    pub(super) fn close_import_sheet(&mut self) -> Option<ImportSheet> {
        let sheet = self.import_sheet.take()?;
        self.place_search();
        self.place_fields();
        ffi::invalidate(self.window);
        Some(sheet)
    }

    fn import_layout_for(&self, sheet: &ImportSheet) -> Option<ImportLayout> {
        Some(ImportLayout::new(self.size(), sheet, &self.graphics))
    }

    fn import_sheet_layout(&self) -> Option<ImportLayout> {
        self.import_layout_for(self.import_sheet.as_ref()?)
    }

    /// シートの部品を押した(クリック・Space・Enter)
    fn import_press(&mut self, part: ImportPart) {
        let Some(sheet) = self.import_sheet.as_mut() else {
            return;
        };
        if !sheet.enabled(part) {
            return;
        }
        match part {
            ImportPart::Filter(index) => {
                sheet.set_filter(index);
                let viewport = self
                    .import_sheet_layout()
                    .map_or(0.0, |layout| layout.body.height);
                if let Some(sheet) = self.import_sheet.as_mut() {
                    sheet
                        .scroll
                        .set_extent(ImportLayout::content_height(sheet), viewport);
                }
            }
            ImportPart::Table => {}
            ImportPart::Cancel => {
                self.close_import_sheet();
            }
            ImportPart::Import => {
                let after = self.commit_import();
                if after.is_some() {
                    AFTER.with(|slot| *slot.borrow_mut() = after);
                    ffi::post(self.window, WM_AFTER, 0, 0);
                }
            }
        }
        ffi::invalidate(self.window);
    }

    /// シートでキーを押した．Tab で部品を巡り，Esc で閉じ，Enter で取り込む．表は矢印で送る
    fn import_key(&mut self, key: u16, shift: bool) -> bool {
        let now = self.now();
        let Some(layout) = self.import_sheet_layout() else {
            return false;
        };
        let Some(sheet) = self.import_sheet.as_mut() else {
            return false;
        };
        sheet.focus_visible = true;
        let focus = sheet.focus;
        // 切り替えはまとまりで 1 回だけ止まる(選んでいるところ)
        let order = sheet.tab_order(&layout);
        let viewport = layout.body.height;
        let page = ((viewport / size::TABLE_ROW_HEIGHT) as isize - 1).max(1);
        match key {
            k if k == VK_TAB.0 => {
                let index = order
                    .iter()
                    .position(|part| {
                        *part == focus
                            || matches!(
                                (part, focus),
                                (ImportPart::Filter(_), ImportPart::Filter(_))
                            )
                    })
                    .unwrap_or(0);
                let next = if shift {
                    (index + order.len() - 1) % order.len()
                } else {
                    (index + 1) % order.len()
                };
                sheet.focus = order[next];
                self.import_focus_changed();
            }
            k if k == VK_ESCAPE.0 => {
                self.close_import_sheet();
            }
            // 表は行を選んで移る(はみ出すときは送る)
            k if focus == ImportPart::Table
                && [
                    VK_UP.0, VK_DOWN.0, VK_PRIOR.0, VK_NEXT.0, VK_HOME.0, VK_END.0,
                ]
                .contains(&k) =>
            {
                let delta = match k {
                    k if k == VK_UP.0 => -1,
                    k if k == VK_DOWN.0 => 1,
                    k if k == VK_PRIOR.0 => -page,
                    k if k == VK_NEXT.0 => page,
                    k if k == VK_HOME.0 => isize::MIN / 2,
                    _ => isize::MAX / 2,
                };
                sheet.move_cursor(delta, viewport, now);
                self.import_focus_changed();
            }
            k if matches!(focus, ImportPart::Filter(_)) && (k == VK_LEFT.0 || k == VK_RIGHT.0) => {
                let ImportPart::Filter(index) = focus else {
                    return true;
                };
                let count = sheet.filters().len();
                let next = if k == VK_LEFT.0 {
                    index.saturating_sub(1)
                } else {
                    (index + 1).min(count.saturating_sub(1))
                };
                sheet.focus = ImportPart::Filter(next);
                self.import_press(ImportPart::Filter(next));
                self.import_focus_changed();
            }
            // Enter はキャンセルにフォーカスがあればキャンセル，ほかは取り込む(ContentDialog の既定のボタン)
            k if k == VK_RETURN.0 => {
                let part = if focus == ImportPart::Cancel {
                    ImportPart::Cancel
                } else {
                    ImportPart::Import
                };
                self.import_press(part);
            }
            k if k == VK_SPACE.0 => self.import_press(focus),
            _ => return false,
        }
        ffi::invalidate(self.window);
        true
    }

    fn import_mouse_move(&mut self, x: f32, y: f32) {
        let hover = self
            .import_sheet_layout()
            .and_then(|layout| layout.hit(x, y));
        if let Some(sheet) = self.import_sheet.as_mut() {
            if sheet.hover != hover {
                sheet.hover = hover;
                ffi::track_leave(self.window);
                ffi::invalidate(self.window);
            }
        }
    }

    fn import_mouse_down(&mut self, x: f32, y: f32) {
        let now = self.now();
        let Some(layout) = self.import_sheet_layout() else {
            return;
        };
        let Some(part) = layout.hit(x, y) else {
            return;
        };
        if let Some(sheet) = self.import_sheet.as_mut() {
            sheet.focus_visible = false;
            sheet.pressed = Some(part);
            sheet.focus = part;
            // 表の行を押したら，その行を選ぶ
            if part == ImportPart::Table {
                if let Some(row) = sheet.row_at(&layout, y, now) {
                    sheet.cursor = row;
                }
            }
        }
        self.import_focus_changed();
        ffi::capture(self.window);
        ffi::invalidate(self.window);
    }

    /// シートのフォーカスが移ったことを読み上げに知らせる(表なら選んでいる行)
    fn import_focus_changed(&self) {
        let Some(sheet) = self.import_sheet.as_ref() else {
            return;
        };
        let id = if sheet.focus == ImportPart::Table && !sheet.rows().is_empty() {
            import_row_node(sheet.cursor)
        } else {
            import_node(sheet.focus)
        };
        uia::focus_changed(self.window, id);
    }

    fn import_mouse_up(&mut self, x: f32, y: f32) {
        ffi::release_capture();
        let hit = self
            .import_sheet_layout()
            .and_then(|layout| layout.hit(x, y));
        let pressed = self
            .import_sheet
            .as_mut()
            .and_then(|sheet| sheet.pressed.take());
        if let (Some(pressed), Some(hit)) = (pressed, hit) {
            if pressed == hit {
                self.import_press(pressed);
            }
        }
        ffi::invalidate(self.window);
    }

    /// シートを閉じる(保存しない)．打つ欄は隠して使い回しに戻し，フォーカスをコマンドの表へ戻す
    pub(super) fn close_sheet(&mut self) {
        let Some(sheet) = self.sheet.take() else {
            return;
        };
        self.close_flyout();
        for window in sheet.fields {
            ffi::show(window, false);
            ffi::set_text(window, "");
            if self.focused_edit == Some(window) {
                self.focused_edit = None;
            }
            self.pool.push(window);
        }
        self.place_search();
        self.place_fields();
        match self.view.list_table(pages::COMMANDS) {
            Some(element) => self.set_focus(Focus::Page(element)),
            None => ffi::focus(self.window),
        }
        ffi::invalidate(self.window);
    }

    /// 保存する．保存できたら閉じる
    fn save_sheet(&mut self) {
        if !self
            .sheet
            .as_ref()
            .is_some_and(|sheet| sheet.enabled(SheetPart::Save))
        {
            return;
        }
        let (saved, after) = self.save_command();
        if saved {
            self.close_sheet();
        }
        if after.is_some() {
            AFTER.with(|slot| *slot.borrow_mut() = after);
            ffi::post(self.window, WM_AFTER, 0, 0);
        }
        ffi::invalidate(self.window);
    }

    /// シートの置き場所(出していなければ None)
    fn sheet_layout(&self) -> Option<SheetLayout> {
        let sheet = self.sheet.as_ref()?;
        Some(SheetLayout::new(self.size(), &sheet.draft, &self.graphics))
    }

    /// シートの打つ欄を置く
    fn place_sheet_fields(&self) {
        let (Some(sheet), Some(layout)) = (self.sheet.as_ref(), self.sheet_layout()) else {
            return;
        };
        let line = size::BODY_LINE_HEIGHT;
        for part in [SheetPart::Reading, SheetPart::Title, SheetPart::Target] {
            let (Some(window), Some(rect)) = (sheet.window(part), layout.rect(part)) else {
                continue;
            };
            let x = rect.x + size::FIELD_PADDING_X;
            let y = rect.y + (rect.height - line) / 2.0;
            let width = (rect.width - size::FIELD_PADDING_X * 2.0).max(0.0);
            let (left, top) = self.client_px(x, y);
            let (right, bottom) = self.client_px(x + width, y + line);
            ffi::place(window, left, top, right - left, bottom - top);
            ffi::show(window, true);
        }
    }

    /// シートの部品にフォーカスを移す(打つ欄なら欄に，ほかは窓に)
    fn sheet_focus(&mut self, part: SheetPart) {
        let Some(sheet) = self.sheet.as_mut() else {
            return;
        };
        sheet.focus = part;
        match sheet.window(part) {
            Some(window) => ffi::focus(window),
            None => {
                if ffi::focused() != Some(self.window) {
                    ffi::focus(self.window);
                }
            }
        }
        uia::focus_changed(self.window, sheet_node(part));
        ffi::invalidate(self.window);
    }

    /// Tab でシートの中だけを巡る(シートの外へは出ない．WinUI の ContentDialog と同じ)
    fn sheet_move_focus(&mut self, back: bool) {
        let Some(layout) = self.sheet_layout() else {
            return;
        };
        let Some(sheet) = self.sheet.as_ref() else {
            return;
        };
        let order: Vec<SheetPart> = layout
            .order()
            .into_iter()
            .filter(|part| sheet.enabled(*part))
            .collect();
        let current = order.iter().position(|part| *part == sheet.focus);
        if let Some(next) = crate::ui::cycle(current, order.len(), back) {
            if let Some(sheet) = self.sheet.as_mut() {
                sheet.focus_visible = true;
            }
            self.sheet_focus(order[next]);
        }
    }

    /// シートでキーを押した(窓にフォーカスがあるとき．打つ欄の Tab・Enter・Esc は欄から届く)
    fn sheet_key(&mut self, key: u16, shift: bool) -> bool {
        let Some(focus) = self.sheet.as_ref().map(|sheet| sheet.focus) else {
            return false;
        };
        if let Some(sheet) = self.sheet.as_mut() {
            sheet.focus_visible = true;
        }
        match key {
            k if k == VK_TAB.0 => self.sheet_move_focus(shift),
            k if k == VK_ESCAPE.0 => self.close_sheet(),
            k if (k == VK_SPACE.0 || k == VK_RETURN.0 || k == VK_F4.0)
                && focus == SheetPart::Kind =>
            {
                self.open_flyout(SHEET_KIND)
            }
            k if (k == VK_UP.0 || k == VK_DOWN.0) && focus == SheetPart::Kind => {
                let Some((_, selected)) = self.sheet.as_ref().map(CommandSheet::kinds) else {
                    return true;
                };
                let next = if k == VK_UP.0 {
                    selected.saturating_sub(1)
                } else {
                    (selected + 1).min(crate::options::COMMAND_KINDS.len() - 1)
                };
                self.sheet_choose_kind(next);
            }
            k if k == VK_SPACE.0 || k == VK_RETURN.0 => self.sheet_press(focus),
            _ => return false,
        }
        ffi::invalidate(self.window);
        true
    }

    fn sheet_mouse_move(&mut self, x: f32, y: f32) {
        let hover = self.sheet_layout().and_then(|layout| layout.hit(x, y));
        if let Some(sheet) = self.sheet.as_mut() {
            if sheet.hover != hover {
                sheet.hover = hover;
                ffi::track_leave(self.window);
                ffi::invalidate(self.window);
            }
        }
    }

    fn sheet_mouse_down(&mut self, x: f32, y: f32) {
        let hit = self.sheet_layout().and_then(|layout| layout.hit(x, y));
        // 開いている動作の一覧の上を押したら閉じるだけ
        if self.flyout.is_some() {
            self.close_flyout();
            if hit == Some(SheetPart::Kind) {
                return;
            }
        }
        let Some(part) = hit else {
            return;
        };
        if let Some(sheet) = self.sheet.as_mut() {
            sheet.focus_visible = false;
            sheet.pressed = Some(part);
        }
        ffi::capture(self.window);
        self.sheet_focus(part);
    }

    fn sheet_mouse_up(&mut self, x: f32, y: f32) {
        ffi::release_capture();
        let hit = self.sheet_layout().and_then(|layout| layout.hit(x, y));
        let pressed = self.sheet.as_mut().and_then(|sheet| sheet.pressed.take());
        if let (Some(pressed), Some(hit)) = (pressed, hit) {
            if pressed == hit {
                self.sheet_press(pressed);
            }
        }
        ffi::invalidate(self.window);
    }

    /// シートの部品を押した(クリック・Space・Enter)
    fn sheet_press(&mut self, part: SheetPart) {
        let Some(sheet) = self.sheet.as_ref() else {
            return;
        };
        if !sheet.enabled(part) {
            return;
        }
        match part {
            SheetPart::Kind => self.open_flyout(SHEET_KIND),
            SheetPart::Choose => {
                let application = sheet.draft.chooses_application();
                AFTER.with(|slot| {
                    *slot.borrow_mut() = Some(After::ChooseCommandTarget { application })
                });
                ffi::post(self.window, WM_AFTER, 0, 0);
            }
            SheetPart::Cancel => self.close_sheet(),
            SheetPart::Save => self.save_sheet(),
            SheetPart::Reading | SheetPart::Title | SheetPart::Target => {
                if let Some(window) = sheet.window(part) {
                    ffi::focus(window);
                }
            }
        }
    }

    /// シートの動作を選び直した．行き先の案内と選ぶボタンが変わる
    fn sheet_choose_kind(&mut self, index: usize) {
        let Some(sheet) = self.sheet.as_mut() else {
            return;
        };
        if index >= crate::options::COMMAND_KINDS.len() {
            return;
        }
        sheet.draft.kind = index;
        sheet.rejected = false;
        if let Some(window) = sheet.window(SheetPart::Target) {
            edit::set_placeholder(window, sheet.draft.target_prompt());
        }
        self.place_sheet_fields();
        ffi::invalidate(self.window);
    }

    /// 選ぶ窓で選んだアプリかファイルを行き先にする(名前が空ならファイルの名前を入れる)
    pub(super) fn sheet_choose(&mut self, path: &str) {
        let Some(sheet) = self.sheet.as_mut() else {
            return;
        };
        sheet.draft.choose(path);
        sheet.rejected = false;
        let draft = sheet.draft.clone();
        if let Some(window) = sheet.window(SheetPart::Target) {
            ffi::set_text(window, &draft.target);
        }
        if let Some(window) = sheet.window(SheetPart::Title) {
            ffi::set_text(window, &draft.title);
        }
        ffi::invalidate(self.window);
    }

    /// シートを出しているときの読み上げの要素(シートの部品だけ)
    /// 取り込む前のシートの部品(出しているあいだは，後ろのページの部品を読ませない)
    fn import_nodes(&self) -> Option<Vec<uia::Node>> {
        let sheet = self.import_sheet.as_ref()?;
        let layout = self.import_sheet_layout()?;
        let filters = sheet.filters();
        let rows = sheet.rows();
        // 表にフォーカスがあるときは，選んでいる行がフォーカスを持つ
        let on_row = sheet.focus == ImportPart::Table && !rows.is_empty();
        let mut nodes: Vec<uia::Node> = layout
            .parts
            .iter()
            .map(|(part, rect)| {
                let part = *part;
                let (role, selected) = match part {
                    ImportPart::Filter(index) => (
                        uia::Role::RadioButton,
                        filters
                            .get(index)
                            .map(|(filter, _)| *filter == sheet.filter),
                    ),
                    ImportPart::Table => (uia::Role::List, None),
                    ImportPart::Cancel | ImportPart::Import => (uia::Role::Button, None),
                };
                uia::Node {
                    id: import_node(part),
                    role,
                    name: sheet.name(part),
                    rect: self.screen_rect(*rect),
                    enabled: sheet.enabled(part),
                    focused: sheet.focus == part && !on_row,
                    toggled: None,
                    expanded: None,
                    value: None,
                    selected,
                    host: None,
                    parent: None,
                }
            })
            .collect();
        // 表の行(列の値と，名詞にする・取り込まない意味を名前に含める)．送って見えていない行も入れる
        let offset = sheet.scroll.offset(self.now());
        nodes.extend(rows.iter().enumerate().map(|(index, row)| {
            let top = layout.body.y + index as f32 * size::TABLE_ROW_HEIGHT - offset;
            uia::Node {
                id: import_row_node(index),
                role: uia::Role::ListItem,
                name: sheet.row_name(row),
                rect: self.screen_rect(Rect::new(
                    layout.body.x,
                    top,
                    layout.body.width,
                    size::TABLE_ROW_HEIGHT,
                )),
                enabled: true,
                focused: on_row && index == sheet.cursor,
                toggled: None,
                expanded: None,
                value: None,
                selected: Some(index == sheet.cursor),
                host: None,
                // 行は表の List の子(ナレーターが List の中の何件目として読む)
                parent: Some(import_node(ImportPart::Table)),
            }
        }));
        Some(nodes)
    }

    fn sheet_nodes(&self) -> Option<Vec<uia::Node>> {
        let sheet = self.sheet.as_ref()?;
        let layout = self.sheet_layout()?;
        let (items, selected) = sheet.kinds();
        Some(
            layout
                .parts
                .iter()
                .map(|(part, rect)| {
                    let part = *part;
                    let host = sheet.window(part);
                    let (role, value, expanded) = match part {
                        SheetPart::Kind => (
                            uia::Role::ComboBox,
                            items.get(selected).cloned(),
                            Some(sheet.open),
                        ),
                        _ if host.is_some() => (uia::Role::Edit, None, None),
                        _ => (uia::Role::Button, None, None),
                    };
                    uia::Node {
                        id: sheet_node(part),
                        role,
                        name: sheet.name(part).to_string(),
                        rect: self.screen_rect(*rect),
                        enabled: sheet.enabled(part),
                        focused: sheet.focus == part,
                        toggled: None,
                        expanded,
                        value,
                        selected: None,
                        host,
                        parent: None,
                    }
                })
                .collect(),
        )
    }

    fn sheet_act(&mut self, id: i32, act: uia::Act) {
        let Some(layout) = self.sheet_layout() else {
            return;
        };
        let Some(part) = layout
            .order()
            .into_iter()
            .find(|part| sheet_node(*part) == id)
        else {
            return;
        };
        match act {
            uia::Act::Focus => self.sheet_focus(part),
            uia::Act::Collapse => self.close_flyout(),
            uia::Act::Expand => self.open_flyout(SHEET_KIND),
            uia::Act::Invoke | uia::Act::Toggle | uia::Act::Select => self.sheet_press(part),
        }
        ffi::invalidate(self.window);
    }
}

/// 取り込む前のシートの部品の読み上げの番号
fn import_node(part: ImportPart) -> i32 {
    match part {
        ImportPart::Filter(index) => NODE_IMPORT_FILTER + index as i32,
        ImportPart::Table => NODE_IMPORT,
        ImportPart::Cancel => NODE_IMPORT + 1,
        ImportPart::Import => NODE_IMPORT + 2,
    }
}

/// 取り込む前のシートの表の行の読み上げの番号
fn import_row_node(row: usize) -> i32 {
    NODE_IMPORT_ROW + i32::try_from(row).unwrap_or(0)
}

/// シートの部品の読み上げの番号
fn sheet_node(part: SheetPart) -> i32 {
    let index = match part {
        SheetPart::Reading => 0,
        SheetPart::Title => 1,
        SheetPart::Kind => 2,
        SheetPart::Target => 3,
        SheetPart::Choose => 4,
        SheetPart::Cancel => 5,
        SheetPart::Save => 6,
    };
    NODE_SHEET + index
}

/// 候補の文字の大きさの設定(見本の文字の大きさ)
const FONT_SIZE: &str = "candidateFontSize";

/// 見本に描くもの(App::preview_source)．key は中身を見分ける文字(画像の大きさを除く)
struct PreviewSource {
    key: String,
    resolved: candidate_ui::theme::ResolvedTheme,
    font_size: f32,
    palette: Option<ipc::PalettePanel>,
    emoji: Option<ipc::CandidateList>,
}

impl PreviewSource {
    fn shown(&self) -> candidate_ui::app::preview::Shown<'_> {
        match (&self.palette, &self.emoji) {
            (Some(panel), _) => candidate_ui::app::preview::Shown::Palette(panel),
            // 絵文字の見本は足元の行を出さない小さな窓にする
            (None, Some(list)) => candidate_ui::app::preview::Shown::CompactList(list),
            (None, None) => candidate_ui::app::preview::Shown::Sample,
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
    /// ページを送る場所
    frame: PageFrame,
    /// 開いているカスタムテーマの編集の画面
    theme_sheet: Option<(super::editor::SheetLayout, super::editor::SheetState)>,
    /// 打つ欄の文字を自分で描く(見本の書き出し．EDIT は写らない)
    draw_fields: bool,
}

/// 上に留めるページの題の帯の高さ(DIP)．ページはこの下で送る
fn page_header() -> f32 {
    size::PAGE_PADDING_TOP + size::TITLE_HEIGHT
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
    let ready = state.availability == Availability::Ready;
    // ページの題は送らずに上に留める(macOS のツールバーの題・Windows 11 の設定アプリの見出しと同じ)．
    // ページはその下で送る．読み込み中などの知らせは題も含めて知らせの側で描く．
    // カスタムテーマの編集の画面では，題の代わりに見本の帯を上に留め，下にボタンの帯を留める
    let frame = state.frame;
    let page_area = Rect::new(
        nav_width,
        frame.top,
        state.width - nav_width,
        (frame.bottom - frame.top).max(0.0),
    );
    // 編集の画面を開いているあいだは左の一覧を使えないので薄くする
    if state.theme_sheet.is_some() {
        canvas.set_opacity(tokens::opacity::settings_windows::DISABLED_OVERLAY);
    }
    paint_nav(canvas, state, nav, nav_scroll, nav_width, view.page);
    canvas.set_opacity(1.0);
    if ready && state.theme_sheet.is_none() {
        let (left, content) = crate::layout::content_frame(state.width - nav_width);
        canvas.text(
            Rect::new(
                nav_width + left,
                size::PAGE_PADDING_TOP,
                content,
                size::TITLE_HEIGHT,
            ),
            view.page.title(),
            TextStyle::Title,
            Color::from(theme.palette.text),
            TextLayout::LINE,
        );
    }
    canvas.push_clip(page_area);
    let offset = (1.0 - state.enter) * size::PAGE_ENTER_OFFSET;
    let scroll_offset = scroll.offset(state.now);
    canvas.set_opacity(state.enter);
    canvas.translate(nav_width, offset - scroll_offset + frame.shift);
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
                draw_fields: state.draw_fields,
                visible: (
                    frame.top - frame.shift + scroll_offset - offset,
                    frame.bottom - frame.shift + scroll_offset - offset,
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
    canvas.translate(-nav_width, scroll_offset - offset - frame.shift);
    canvas.set_opacity(1.0);
    canvas.pop_clip();
    page::scrollbar(canvas, theme, page_area, scroll, state.now);
    if let Some((layout, sheet)) = &state.theme_sheet {
        super::editor::paint_sheet(canvas, theme, layout, sheet);
    }
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
    let selected = nav.position(page);
    for (index, item) in nav.items.iter().enumerate() {
        // 背景は左右を inset，上下を fine だけ縮め，隣の項目の背景と inset あける
        let rect = Rect::new(
            space::INSET,
            item.top + space::FINE,
            nav_width - space::INSET * 2.0,
            item.height - space::FINE * 2.0,
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
            Rect::new(space::INSET, top, size::NAV_INDICATOR_WIDTH, indicator),
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
    layout: &MenuLayout,
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
    let body = Rect::new(0.0, padding, width, height - padding * 2.0);
    canvas.push_clip(body);
    // 開くときに上から少し下りてくる
    let slide = (1.0 - opened) * -size::PAGE_ENTER_OFFSET;
    canvas.set_opacity(opened);
    let offset = scroll.offset(now);
    for row in layout.rows() {
        let top = padding + row.top - offset + slide;
        let item = row.height;
        if top + item < 0.0 || top > height {
            continue;
        }
        let index = match row.kind {
            MenuRowKind::Item(index) => index,
            // 組の見出し: 項目と左をそろえた小さい薄い文字(選べないので背景を付けない)
            MenuRowKind::Heading(title) => {
                canvas.text(
                    Rect::new(
                        padding + size::FIELD_PADDING_X,
                        top,
                        width - (padding + size::FIELD_PADDING_X) * 2.0,
                        item,
                    ),
                    title,
                    TextStyle::Caption,
                    Color::from(palette.text_secondary),
                    TextLayout::LINE,
                );
                continue;
            }
            // 組のあいだの線: 一覧の端から端まで引く(WinUI の MenuFlyoutSeparator)
            MenuRowKind::Divider => {
                canvas.fill_rect(
                    Rect::new(0.0, top + padding, width, part::STROKE),
                    Color::from(palette.flyout_stroke),
                );
                continue;
            }
        };
        let Some(label) = items.get(index) else {
            continue;
        };
        // 背景は上下を 1 ドットずつ縮め，隣の項目の背景と離す
        let rect = Rect::new(
            padding,
            top + part::STROKE,
            width - padding * 2.0,
            item - part::STROKE * 2.0,
        );
        // 背景は文字の色を薄く重ねる(一覧の背景の明るさによらず見分けられる)
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

/// 説明の吹き出し．ポインターの右下に出し，窓からはみ出さないよう詰める
/// タイトルバー(WinUI 3 の TitleBar)．背景は描かず Mica を見せる．閉じるボタンなどは DWM が描く．
/// 窓が後ろにあるときは題を薄くする
fn paint_title_bar(canvas: &mut dyn Canvas, theme: &Theme, width: f32, height: f32, active: bool) {
    let icon = size::TITLE_BAR_ICON_SIZE;
    let padding = size::TITLE_BAR_PADDING_X;
    canvas.preview_at(TITLE_ICON_SLOT, padding, (height - icon) / 2.0);
    let left = padding + icon + padding;
    let color = if active {
        theme.palette.text
    } else {
        theme.palette.text_disabled
    };
    canvas.text(
        Rect::new(left, 0.0, (width - left).max(0.0), height),
        settings::WINDOW_TITLE,
        TextStyle::Caption,
        Color::from(color),
        TextLayout::LINE,
    );
}

fn paint_tooltip(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    text: &str,
    (x, y): (f32, f32),
    (width, height): (f32, f32),
) {
    let palette = &theme.palette;
    let padding = size::FIELD_PADDING_X;
    let bubble_width = canvas.width(text, TextStyle::Caption) + padding * 2.0;
    let bubble_height = size::NOTE_LINE_HEIGHT + padding;
    let left = (x + padding)
        .min(width - bubble_width - size::CARD_GAP)
        .max(0.0);
    let below = y + size::TOOLTIP_OFFSET;
    let top = if below + bubble_height > height {
        y - bubble_height - size::CARD_GAP
    } else {
        below
    };
    let rect = Rect::new(left, top, bubble_width, bubble_height);
    canvas.fill_round(rect, size::CONTROL_RADIUS, Color::from(palette.card));
    canvas.stroke_round(
        rect,
        size::CONTROL_RADIUS,
        1.0,
        Color::from(palette.control_strong_stroke),
    );
    canvas.text(
        rect,
        text,
        TextStyle::Caption,
        Color::from(palette.text),
        TextLayout::CENTER,
    );
}

// MARK: - 窓の手続き

/// ページの部品の読み上げの番号の始まり(左の一覧の項目と分ける)
const NODE_PAGE: i32 = 1000;
/// 読み上げの番号: カスタムテーマの編集の画面の下のボタン(検索欄とページの部品の番号のあいだ)
const NODE_THEME_SHEET: i32 = 950;

fn theme_sheet_index(action: EditorAction) -> i32 {
    match action {
        EditorAction::Duplicate => 0,
        EditorAction::Cancel => 1,
        EditorAction::Save => 2,
    }
}
/// 読み上げの番号: 検索欄(左の一覧の項目の番号とページの部品の番号のあいだ)
const NODE_SEARCH: i32 = 900;
/// シートの部品の読み上げの番号の始まり
const NODE_SHEET: i32 = 800;
/// 取り込む前に中身を見せるシートの部品の読み上げの番号(切り替えは NODE_IMPORT_FILTER から，表の行は NODE_IMPORT_ROW から)
const NODE_IMPORT: i32 = 850;
const NODE_IMPORT_FILTER: i32 = 860;
const NODE_IMPORT_ROW: i32 = 100_000;
/// シートの動作の一覧を開いているときのドロップダウンの持ち主(ページの部品と重ならない番号)
const SHEET_KIND: Element = Element {
    row: usize::MAX,
    part: Part::Dropdown,
};

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
    // タイトルバーを窓の中に入れているときの枠(閉じるボタン・動かす・大きさを変える)
    if let Some(result) = ffi::frame::message(window, message, wparam, lparam) {
        return Some(result);
    }
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
        WM_SNAPSHOT => {
            with_app(App::snapshot_step);
            Some(LRESULT(0))
        }
        super::update::WM_UPDATE => {
            super::update::receive(window);
            Some(LRESULT(0))
        }
        super::actions::WM_IMPORT_PREVIEWED => {
            let after = with_app(App::finish_preview).flatten();
            super::actions::run_after(window, after);
            Some(LRESULT(0))
        }
        super::actions::WM_DICTIONARY_IMPORTED => {
            let after = with_app(App::finish_import).flatten();
            super::actions::run_after(window, after);
            Some(LRESULT(0))
        }
        WM_WARM => {
            with_app(App::warm_fields);
            Some(LRESULT(0))
        }
        WM_TIMER if wparam.0 == TEMPLATE_TIMER => {
            with_app(|app| {
                let Some(model) = &app.model else {
                    ffi::kill_timer(app.window, TEMPLATE_TIMER);
                    return;
                };
                if app.view.template_items().is_none() {
                    // ほかのページに移ったら読み直さない(開いたときの例も捨てる)
                    ffi::kill_timer(app.window, TEMPLATE_TIMER);
                    app.extras.template_values.clear();
                    return;
                }
                // 値を部品に映す(読み直しは refresh の中で行う)
                let _ = model;
                app.refresh();
                ffi::invalidate(app.window);
            });
            Some(LRESULT(0))
        }
        WM_TIMER if wparam.0 == TOOLTIP_TIMER => {
            ffi::kill_timer(window, TOOLTIP_TIMER);
            ffi::invalidate(window);
            None
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
            let double = message == WM_LBUTTONDBLCLK;
            with_app(|app| app.mouse_down(lparam, double));
            Some(LRESULT(0))
        }
        WM_LBUTTONUP => {
            with_app(|app| app.mouse_up(lparam));
            Some(LRESULT(0))
        }
        // 表の行を右クリックしたらメニューを出す(macOS の表の contextMenu)
        WM_RBUTTONUP => {
            with_app(|app| app.right_click(lparam));
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
            with_app(|app| {
                if app.sheet.is_some() {
                    app.sheet_move_focus(wparam.0 == 1);
                } else {
                    app.move_focus(wparam.0 == 1);
                }
            });
            Some(LRESULT(0))
        }
        // 欄の中で Esc を押したら，カスタムテーマの編集の画面かシートか，書き方のチップを閉じる(macOS の cancelAction)
        edit::WM_FIELD_ESCAPE => {
            let field = HWND(lparam.0 as *mut _);
            with_app(|app| app.field_escape(field));
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
            with_app(|app| {
                // 「キーで検索」で受け取ったキーは欄に入れず，表を絞り込む
                if wparam.0 == 1 {
                    app.key_captured(field);
                } else {
                    app.field_changed(field);
                }
            });
            Some(LRESULT(0))
        }
        edit::WM_FIELD_RECORDING => {
            let field = HWND(lparam.0 as *mut _);
            with_app(|app| app.field_recording(field, wparam.0 == 1));
            Some(LRESULT(0))
        }
        WM_CONFIRM => {
            let Some(event) = PENDING.with(|pending| pending.borrow_mut().take()) else {
                return Some(LRESULT(0));
            };
            if let Some((title, text)) = super::actions::confirmation(&event) {
                // 窓の題は設定の画面の名前にし，尋ねる文と説明を本文に並べる(Windows の確かめる窓の書き方)
                let body = if title == settings::WINDOW_TITLE {
                    text
                } else {
                    format!("{title}\n\n{text}")
                };
                if !ffi::confirm(window, settings::WINDOW_TITLE, &body) {
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
            let active = low_word(wparam.0) != WA_INACTIVE;
            with_app(|app| {
                app.active = active;
                ffi::invalidate(app.window);
            });
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
            ffi::frame::remove_title_bar(window);
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
            with_app(|app| app.flyout_move(lparam));
            Some(LRESULT(0))
        }
        WM_LBUTTONDOWN => {
            with_app(|app| app.flyout_press(lparam));
            Some(LRESULT(0))
        }
        WM_LBUTTONUP => {
            with_app(|app| app.flyout_release(lparam));
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
