#![forbid(unsafe_code)]

//! 設定の窓．左に検索と一覧(見出しごとのページ)，右に開いているページを置く(macOS の SettingsView と同じ並び)．
//! 状態は UI スレッドの thread_local に持ち，窓の手続きはそこから借りる．借りている間に届いたメッセージは既定の扱いにする

use super::ffi::{self, Canvas, DrawTarget, Paint, Window};
use super::page::{DictionaryAction, Event, Extras, PageView, ThemeAction, WithExtras};
use super::theme::Theme;
use super::Store;
use crate::catalog::{Catalog, Timing};
use crate::engine::FileOutcome;
use crate::files::FileTask;
use crate::list::{Item, ListSpec};
use crate::model::SettingsModel;
use crate::options;
use crate::pages::{self, Action, DictionaryList, Group, Page};
use crate::store::StoreError;
use crate::strings::{
    association, dictionaries, features, keys, more, rule_list, settings, sync as sync_text,
    windows as text,
};
use ipc::{
    ContrastPair, DictionaryAddResult, DictionaryEntry, FileFailure, RequestBody, SymbolItem,
    SymbolKind, SymbolOrigin, SymbolSaveResult, SyncStatus,
};
use std::cell::RefCell;
use tokens::size::settings_windows as size;
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::Graphics::Gdi::{DT_END_ELLIPSIS, DT_LEFT, DT_SINGLELINE, DT_VCENTER};
use windows::Win32::UI::Controls::{
    CDDS_PREPAINT, CDRF_SKIPDEFAULT, EM_SETCUEBANNER, NM_CUSTOMDRAW,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CW_USEDEFAULT, EN_CHANGE, ES_AUTOHSCROLL, LBN_SELCHANGE, LBS_HASSTRINGS, LBS_NOINTEGRALHEIGHT,
    LBS_NOTIFY, LBS_OWNERDRAWVARIABLE, LB_ADDSTRING, LB_GETCURSEL, LB_RESETCONTENT, LB_SETCURSEL,
    SB_BOTTOM, SB_LINEDOWN, SB_LINEUP, SB_PAGEDOWN, SB_PAGEUP, SB_THUMBPOSITION, SB_THUMBTRACK,
    SB_TOP, WA_INACTIVE, WHEEL_DELTA, WINDOW_EX_STYLE, WINDOW_STYLE, WM_ACTIVATE, WM_COMMAND,
    WM_CTLCOLORBTN, WM_CTLCOLOREDIT, WM_CTLCOLORLISTBOX, WM_CTLCOLORSTATIC, WM_DESTROY,
    WM_DPICHANGED, WM_DRAWITEM, WM_ERASEBKGND, WM_GETMINMAXINFO, WM_MEASUREITEM, WM_MOUSEWHEEL,
    WM_NOTIFY, WM_PAINT, WM_SETTINGCHANGE, WM_SIZE, WM_SYSCOLORCHANGE, WM_THEMECHANGED, WM_TIMER,
    WM_VSCROLL, WS_CHILD, WS_CLIPCHILDREN, WS_EX_CLIENTEDGE, WS_EX_CONTROLPARENT,
    WS_OVERLAPPEDWINDOW, WS_TABSTOP, WS_VISIBLE, WS_VSCROLL,
};
use windows_core::{w, PCWSTR};

const MAIN_CLASS: PCWSTR = w!("s90.tokyo-ime.settings");
const HOST_CLASS: PCWSTR = w!("s90.tokyo-ime.settings.page");
const ID_SEARCH: u16 = 1;
const ID_NAV: u16 = 2;
const ID_HOST: u16 = 3;
/// つなぎ直しの時計の番号
const RECONNECT_TIMER: usize = 1;

/// 左の一覧の 1 項目．見出しの最初のページは上に見出しを描く
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct NavEntry {
    page: Page,
    header: Option<Group>,
}

/// 窓の外に出してから行うこと(借りている間にモーダルの窓を出さない)
enum After {
    Message {
        text: &'static str,
        warning: bool,
    },
    /// 件数などを含む知らせ
    Notice(String),
    OpenSettingsFile,
    /// ファイルを選ぶ窓を出してから，読み込む・書き出す
    File(FileTask),
    /// フォルダを選ぶ窓を出してから，同期のフォルダにする
    ChooseSyncFolder,
    /// 色を選ぶ窓を出してから，path の色を変える
    ChooseColor {
        path: &'static str,
        current: String,
    },
    /// アプリの実行ファイルを選ぶ窓を出してから，一覧の入力欄に名前を入れる
    ChooseApp {
        path: &'static str,
    },
    /// ファイルを選ぶ窓を出してから，辞書を取り込む
    ImportDictionary {
        list: DictionaryList,
        replacing: Option<String>,
    },
}

struct App {
    window: Window,
    search: Window,
    nav: Window,
    host: Window,
    theme: Theme,
    catalog: Catalog,
    connect: fn(&Timing) -> Option<Store>,
    model: Option<SettingsModel<Store>>,
    extras: Extras,
    /// 登録した単語(表の行と同じ並び．消すときに引く)
    dictionary: Vec<DictionaryEntry>,
    /// 項目ごとの同期の表の行(表と同じ並び．切り替えるときに引く)
    sync_rows: Vec<crate::sync::FieldRow>,
    /// 同期の状態の値(「sync.」の道筋)
    sync_values: crate::store::Fields,
    /// 外観のページで編集しているカスタムテーマの id
    editing_theme: Option<String>,
    /// 外観の見本を描くもの(初めて描くときに作る．作れなければ見本を描かない)
    preview: Option<candidate_ui::app::preview::Preview>,
    /// 記号の決まり(表の行と同じ並び．外す・切り替えるときに引く)
    sequences: Vec<SymbolItem>,
    readings: Vec<SymbolItem>,
    entries: Vec<NavEntry>,
    view: PageView,
    scroll: i32,
    content_height: i32,
}

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
    /// 左の一覧の項目の高さ．LB_ADDSTRING の中で WM_MEASUREITEM が届くので APP と分けて持つ
    static NAV_HEIGHTS: RefCell<Vec<u32>> = const { RefCell::new(Vec::new()) };
}

/// 窓を作る．メッセージの繰り返しに渡す窓を返す
pub fn open(catalog: Catalog, connect: fn(&Timing) -> Option<Store>) -> Option<Window> {
    ffi::register_class(MAIN_CLASS, Some(main_procedure));
    ffi::register_class(HOST_CLASS, Some(host_procedure));
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
    let theme = Theme::load(window, dpi)?;
    let search = ffi::create(
        WS_EX_CLIENTEDGE,
        w!("EDIT"),
        "",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(ES_AUTOHSCROLL as u32),
        (0, 0, 0, 0),
        Some(window),
        ID_SEARCH,
    )?;
    ffi::send_text(search, EM_SETCUEBANNER, 1, features::SEARCH);
    let nav = ffi::create(
        WINDOW_EX_STYLE::default(),
        w!("LISTBOX"),
        "",
        WS_CHILD
            | WS_VISIBLE
            | WS_TABSTOP
            | WS_VSCROLL
            | WINDOW_STYLE(
                (LBS_OWNERDRAWVARIABLE | LBS_HASSTRINGS | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT) as u32,
            ),
        (0, 0, 0, 0),
        Some(window),
        ID_NAV,
    )?;
    let host = ffi::create(
        WS_EX_CONTROLPARENT,
        HOST_CLASS,
        "",
        WS_CHILD | WS_VISIBLE | WS_VSCROLL | WS_CLIPCHILDREN,
        (0, 0, 0, 0),
        Some(window),
        ID_HOST,
    )?;
    let model =
        connect(&catalog.timing).and_then(|store| SettingsModel::load(store, &catalog).ok());
    let page = Page::Input;
    let view = match model {
        Some(_) => PageView::new(host, &theme, page, &catalog),
        None => PageView::unavailable(host, &theme, page, &catalog),
    };
    let app = App {
        window,
        search,
        nav,
        host,
        theme,
        catalog,
        connect,
        model,
        extras: Extras::default(),
        dictionary: Vec::new(),
        sync_rows: Vec::new(),
        sync_values: crate::store::Fields::new(),
        editing_theme: None,
        preview: None,
        sequences: Vec::new(),
        readings: Vec::new(),
        entries: Vec::new(),
        view,
        scroll: 0,
        content_height: 0,
    };
    APP.with(|cell| *cell.borrow_mut() = Some(app));
    with_app(|app| {
        app.apply_theme();
        if app.model.is_none() {
            app.disconnect();
        }
        app.fill_nav("");
        app.refresh();
        let px = |value: f32| app.theme.px(value);
        ffi::resize(window, px(size::WINDOW_WIDTH), px(size::WINDOW_HEIGHT));
        app.arrange_window();
    });
    ffi::show(window, true);
    Some(window)
}

/// 状態を借りて f を呼ぶ．借りられない(手続きの中から呼ばれた)ときは None
fn with_app<T>(f: impl FnOnce(&mut App) -> T) -> Option<T> {
    APP.with(|cell| {
        let mut borrowed = cell.try_borrow_mut().ok()?;
        borrowed.as_mut().map(f)
    })
}

fn run_after(window: Window, after: Option<After>) {
    match after {
        Some(After::Message { text, warning }) => {
            ffi::message(window, settings::WINDOW_TITLE, text, warning)
        }
        Some(After::Notice(text)) => ffi::message(window, settings::WINDOW_TITLE, &text, false),
        Some(After::OpenSettingsFile) => {
            if let Some(path) = settings_file().filter(|path| path.exists()) {
                ffi::open_with_default_app(&path);
            }
        }
        Some(After::ChooseApp { path }) => {
            let filter = crate::files::APP_FILTER;
            let Some(file) = ffi::choose_file(window, true, "", filter.name, filter.pattern) else {
                return;
            };
            // 除外設定はアプリを実行ファイルの名前(小文字)で見分ける
            let name = std::path::Path::new(&file)
                .file_name()
                .map(|name| name.to_string_lossy().to_lowercase())
                .unwrap_or_default();
            with_app(|app| app.view.set_list_input(path, 0, &name));
        }
        Some(After::ImportDictionary { list, replacing }) => {
            let filter = crate::files::TEXT_FILTER;
            let Some(path) = ffi::choose_file(window, true, "", filter.name, filter.pattern) else {
                return;
            };
            let after = with_app(|app| app.import_dictionary(list, path, replacing)).flatten();
            run_after(window, after);
        }
        Some(After::ChooseColor { path, current }) => {
            let Some((red, green, blue)) = ffi::choose_color(window, crate::themes::rgb(&current))
            else {
                return;
            };
            let value = serde_json::Value::String(format!("#{red:02X}{green:02X}{blue:02X}"));
            let after = with_app(|app| {
                app.handle(Event::Set {
                    path,
                    value,
                    clears: None,
                })
            })
            .flatten();
            run_after(window, after);
        }
        Some(After::ChooseSyncFolder) => {
            let Some(path) = ffi::choose_folder(window) else {
                return;
            };
            let after =
                with_app(|app| app.request_sync(RequestBody::SetSyncFolder { path })).flatten();
            run_after(window, after);
        }
        Some(After::File(task)) => {
            let Some(name) = with_app(|app| task.default_name(&app.catalog)) else {
                return;
            };
            let filter = task.filter();
            let Some(path) =
                ffi::choose_file(window, task.is_import(), &name, filter.name, filter.pattern)
            else {
                return;
            };
            let after = with_app(|app| app.run_file(task, path)).flatten();
            run_after(window, after);
        }
        None => {}
    }
}

/// 設定のファイルの置き場所(エンジンの S90Persistence と同じ %APPDATA%\s90.tokyo\IME\settings.json)
fn settings_file() -> Option<std::path::PathBuf> {
    std::env::var_os("APPDATA").map(|base| {
        std::path::PathBuf::from(base)
            .join("s90.tokyo")
            .join("IME")
            .join("settings.json")
    })
}

impl App {
    fn apply_theme(&self) {
        ffi::set_dark_title_bar(self.window, self.theme.dark);
        ffi::set_theme(self.search, self.theme.control_theme(true));
        ffi::set_theme(self.nav, self.theme.control_theme(false));
        ffi::set_theme(self.host, self.theme.control_theme(false));
        ffi::set_font(self.search, &self.theme.fonts.body);
        ffi::set_font(self.nav, &self.theme.fonts.body);
        self.view.apply_fonts(&self.theme);
        self.view.apply_theme(&self.theme);
    }

    /// 色・書体を作り直す(OS の設定や DPI が変わったとき)
    fn reload_theme(&mut self, dpi: u32) {
        if let Some(theme) = Theme::load(self.window, dpi) {
            self.theme = theme;
            self.apply_theme();
            let query = self.query();
            self.fill_nav(&query);
            self.arrange_window();
            ffi::invalidate(self.window);
            ffi::invalidate(self.host);
        }
    }

    fn query(&self) -> String {
        let length = ffi::send(
            self.search,
            windows::Win32::UI::WindowsAndMessaging::WM_GETTEXTLENGTH,
            0,
            0,
        );
        if length <= 0 {
            return String::new();
        }
        ffi::window_text(self.search)
    }

    /// 検索の言葉に合うページを左の一覧に並べる．開いているページが一覧から消えたら先頭のページを開く
    fn fill_nav(&mut self, query: &str) {
        let px = |value: f32| u32::try_from(self.theme.px(value)).unwrap_or(1);
        self.entries = pages::sidebar(pages::BUILT, query)
            .into_iter()
            .flat_map(|(group, pages)| {
                pages
                    .into_iter()
                    .enumerate()
                    .map(move |(index, page)| NavEntry {
                        page,
                        header: (index == 0).then_some(group),
                    })
            })
            .collect();
        let heights: Vec<u32> = self
            .entries
            .iter()
            .map(|entry| {
                px(size::NAV_ITEM_HEIGHT) + entry.header.map_or(0, |_| px(size::NAV_HEADER_HEIGHT))
            })
            .collect();
        NAV_HEIGHTS.with(|cell| *cell.borrow_mut() = heights);
        ffi::send(self.nav, LB_RESETCONTENT, 0, 0);
        for entry in &self.entries {
            ffi::send_text(self.nav, LB_ADDSTRING, 0, entry.page.title());
        }
        match self
            .entries
            .iter()
            .position(|entry| entry.page == self.view.page)
        {
            Some(index) => {
                ffi::send(self.nav, LB_SETCURSEL, index, 0);
            }
            None => {
                if let Some(first) = self.entries.first().map(|entry| entry.page) {
                    ffi::send(self.nav, LB_SETCURSEL, 0, 0);
                    self.open_page(first);
                }
            }
        }
    }

    fn open_page(&mut self, page: Page) {
        let view = match self.model {
            Some(_) => PageView::new(self.host, &self.theme, page, &self.catalog),
            None => PageView::unavailable(self.host, &self.theme, page, &self.catalog),
        };
        std::mem::replace(&mut self.view, view).destroy();
        self.scroll = 0;
        self.read_extras();
        self.refresh();
    }

    /// 開いているページが設定の値のほかに出すもの(統計・登録した単語)を読む
    fn read_extras(&mut self) {
        let Some(model) = &self.model else { return };
        match self.view.page {
            Page::Usage => {
                if let Ok(usage) = model.store().read_usage() {
                    self.extras.usage = usage;
                }
            }
            Page::Appearance => {
                // 初めは今使っているカスタムテーマを編集する
                if self.editing_theme.is_none() {
                    self.editing_theme = model
                        .value(crate::themes::ACTIVE)
                        .and_then(serde_json::Value::as_str)
                        .map(str::to_string);
                }
                self.check_theme();
            }
            Page::Sync => {
                if let Ok(status) = model.store().read_sync() {
                    self.show_sync(&status);
                }
            }
            Page::Symbols => {
                for kind in [SymbolKind::Sequence, SymbolKind::Reading] {
                    if let Ok(items) = model.store().read_symbol_items(kind) {
                        *self.extras.symbol_rows_mut(kind) = items.iter().map(symbol_row).collect();
                        match kind {
                            SymbolKind::Sequence => self.sequences = items,
                            SymbolKind::Reading => self.readings = items,
                        }
                    }
                }
            }
            Page::Dictionary => {
                if let Ok(entries) = model.store().read_user_dictionary() {
                    self.extras.dictionary = entries
                        .iter()
                        .map(|entry| vec![entry.reading.clone(), entry.word.clone()])
                        .collect();
                    self.dictionary = entries;
                }
            }
            _ => {}
        }
    }

    /// 値を部品に映して置き直す
    fn refresh(&mut self) {
        if let Some(model) = &self.model {
            if self.view.page == Page::Keys {
                self.extras.keymap_report = keymap_report(model);
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
            let values = WithExtras {
                values: model,
                extra: &self.extras.extra,
            };
            self.view.sync(&values, &self.extras);
        }
        self.arrange_page();
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
            None => self.connect(),
        }
    }

    /// エンジンにつなぐ．つながったら今のページを開き直し，つなぎ直しの時計を止める
    fn connect(&mut self) {
        self.model = (self.connect)(&self.catalog.timing)
            .and_then(|store| SettingsModel::load(store, &self.catalog).ok());
        if self.model.is_some() {
            ffi::kill_timer(self.window, RECONNECT_TIMER);
            self.open_page(self.view.page);
        }
    }

    /// エンジンが答えなくなった．画面は閉じずに知らせを出し，間隔をおいてつなぎ直す
    fn disconnect(&mut self) {
        self.model = None;
        self.open_page(self.view.page);
        let interval = self.catalog.timing.reconnect_interval().as_millis();
        ffi::set_timer(
            self.window,
            RECONNECT_TIMER,
            u32::try_from(interval).unwrap_or(u32::MAX),
        );
    }

    /// 頼みが失敗したときの後始末．つながらないならつなぎ直しに回し，ほかは書けなかったと知らせる
    fn failure(&mut self, error: StoreError) -> Option<After> {
        if error == StoreError::Unavailable {
            self.disconnect();
            return None;
        }
        if let Some(model) = self.model.as_mut() {
            if model.reload().is_err() {
                self.disconnect();
                return None;
            }
        }
        Some(failed())
    }

    fn arrange_window(&mut self) {
        let (width, height) = ffi::client_size(self.window);
        let px = |value: f32| self.theme.px(value);
        let nav_width = px(size::NAV_WIDTH).min(width / 2);
        let padding = px(size::NAV_PADDING_X);
        let top = px(size::PAGE_PADDING_TOP);
        let search_height = px(size::SEARCH_HEIGHT);
        ffi::place(
            self.search,
            padding,
            top,
            nav_width - padding * 2,
            search_height,
        );
        let nav_top = top + search_height + top;
        ffi::place(self.nav, 0, nav_top, nav_width, (height - nav_top).max(0));
        ffi::place(self.host, nav_width, 0, (width - nav_width).max(0), height);
        self.arrange_page();
    }

    fn arrange_page(&mut self) {
        let (width, height) = ffi::client_size(self.host);
        self.content_height = self.view.arrange(self.host, &self.theme, width, 0);
        let max = (self.content_height - height).max(0);
        self.scroll = self.scroll.clamp(0, max);
        if self.scroll != 0 {
            self.view
                .arrange(self.host, &self.theme, width, self.scroll);
        }
        ffi::set_vertical_scroll(self.host, self.content_height, height, self.scroll);
        ffi::invalidate(self.host);
    }

    fn scroll_to(&mut self, position: i32) {
        let (_, height) = ffi::client_size(self.host);
        let position = position.clamp(0, (self.content_height - height).max(0));
        if position != self.scroll {
            self.scroll = position;
            self.arrange_page();
        }
    }

    fn handle(&mut self, event: Event) -> Option<After> {
        if let Event::ListAdd {
            spec,
            limit,
            item,
            replacing,
        } = &event
        {
            return self.add_to_list(spec, limit.limit(&self.catalog), item, *replacing);
        }
        if let Event::ChooseApp { path } = event {
            return Some(After::ChooseApp { path });
        }
        if matches!(
            event,
            Event::SymbolSave { .. } | Event::SymbolRemove { .. } | Event::SymbolToggle { .. }
        ) {
            return self.edit_symbols(event);
        }
        // 同期の値は設定のファイルの項目ではないので，同期の要求にして頼む
        if let Event::Set { path, value, .. } = &event {
            if crate::sync::is_sync_path(path) {
                let body = crate::sync::request(path, value)?;
                return self.request_sync(body);
            }
            if crate::themes::is_theme_path(path) {
                return self.edit_theme(path, value);
            }
        }
        match event {
            Event::ThemeList {
                action,
                index,
                name: _,
            } => self.theme_list(action, index),
            Event::ThemeSelected(index) => {
                let entries =
                    crate::themes::entries(self.model.as_ref()?.value(crate::themes::THEMES));
                self.editing_theme =
                    index.and_then(|index| entries.get(index).map(|entry| entry.id.clone()));
                self.check_theme();
                self.refresh();
                None
            }
            Event::ChooseColor { path, current } => Some(After::ChooseColor { path, current }),
            other => self.handle_other(other),
        }
    }

    fn handle_other(&mut self, event: Event) -> Option<After> {
        if let Event::DictionaryList {
            list,
            action,
            index,
        } = event
        {
            return self.edit_dictionary_list(list, action, index);
        }
        match &event {
            Event::Action(Action::SyncNow) => return self.request_sync(RequestBody::SyncNow),
            Event::Action(Action::ChooseSyncFolder) => return Some(After::ChooseSyncFolder),
            Event::SyncToggleFields(indices) => {
                let changes: Vec<RequestBody> = indices
                    .iter()
                    .filter_map(|index| self.sync_rows.get(*index))
                    .map(|row| RequestBody::SetSyncLocalField {
                        field: row.field.clone(),
                        is_local: !row.local,
                    })
                    .collect();
                let mut after = None;
                for body in changes {
                    after = self.request_sync(body);
                    if after.is_some() {
                        break;
                    }
                }
                return after;
            }
            _ => {}
        }
        let model = self.model.as_mut()?;
        let result = match event {
            Event::Set {
                path,
                value,
                clears,
            } => model.set_clearing(path, value, clears),
            Event::Reset(path) => model.reset(path),
            Event::ListRemove { spec, indices } => {
                let list = spec.remove(model.value(spec.path), &indices);
                model.set(spec.path, list)
            }
            Event::ListAdd { .. }
            | Event::SymbolSave { .. }
            | Event::SymbolRemove { .. }
            | Event::SymbolToggle { .. }
            | Event::SyncToggleFields(_)
            | Event::DictionaryList { .. }
            | Event::ThemeList { .. }
            | Event::ThemeSelected(_)
            | Event::ChooseColor { .. }
            | Event::ChooseApp { .. }
            | Event::Action(Action::SyncNow | Action::ChooseSyncFolder) => return None,
            Event::DictionaryAdd { item, replacing } => {
                let entry = DictionaryEntry {
                    reading: item.first().cloned().unwrap_or_default(),
                    word: item.get(1).cloned().unwrap_or_default(),
                };
                // 書き換えるときは，新しい単語を登録できてから元の単語を消す(登録できなければ元のまま)
                let old = replacing
                    .and_then(|index| self.dictionary.get(index).cloned())
                    .filter(|old| *old != entry);
                let result = model.store().add_user_dictionary_entry(entry);
                if let (Ok(DictionaryAddResult::Added), Some(old)) = (&result, old) {
                    if let Err(error) = model.store().remove_user_dictionary_entry(old) {
                        return self.failure(error);
                    }
                }
                let result = match result {
                    Err(error) => return self.failure(error),
                    Ok(result) => result,
                };
                let after = match result {
                    DictionaryAddResult::Added => {
                        self.view.clear_list_inputs("");
                        None
                    }
                    DictionaryAddResult::AlreadyRegistered => Some(rule_list::ALREADY_REGISTERED),
                    DictionaryAddResult::Invalid => Some(settings::INVALID_ENTRY),
                    DictionaryAddResult::Full => Some(rule_list::FULL),
                };
                self.read_extras();
                self.refresh();
                return after.map(|text| After::Message {
                    text,
                    warning: true,
                });
            }
            Event::DictionaryRemove(indices) => {
                let entries: Vec<DictionaryEntry> = indices
                    .iter()
                    .filter_map(|index| self.dictionary.get(*index).cloned())
                    .collect();
                // 消せなかった語があっても残りは消す
                let error = entries
                    .into_iter()
                    .filter_map(|entry| model.store().remove_user_dictionary_entry(entry).err())
                    .last();
                if let Some(error) = error {
                    return self.failure(error);
                }
                self.read_extras();
                self.refresh();
                return None;
            }
            Event::Preview { text, preceding } => {
                let shown = if text.trim().is_empty() {
                    String::new()
                } else {
                    model
                        .store()
                        .preview_language(&text, &preceding)
                        .map(|words| crate::engine::preview_text(&words))
                        .unwrap_or_default()
                };
                self.view.show_preview(&shown);
                return None;
            }
            Event::Action(Action::RestoreDefaults) => model.restore_defaults(),
            Event::Action(Action::RestoreKeymap) => load_preset(model, STANDARD_PRESET),
            Event::LoadPreset(preset) => load_preset(model, preset),
            Event::Action(Action::ResetLearning) => {
                if let Err(error) = model.store().reset_learning() {
                    return self.failure(error);
                }
                self.refresh();
                return Some(After::Message {
                    text: settings::LEARNING_RESET,
                    warning: false,
                });
            }
            Event::Action(Action::OpenSettingsFile) => return Some(After::OpenSettingsFile),
            Event::Action(Action::File(task)) => return Some(After::File(task)),
            Event::Action(Action::ResetUsage) => {
                if let Err(error) = model.store().reset_usage() {
                    return self.failure(error);
                }
                self.read_extras();
                self.refresh();
                return None;
            }
        };
        // 書けなかったときは今の値を読み直して部品を戻す
        let after = match result {
            Err(error) => self.failure(error),
            Ok(()) => None,
        };
        self.refresh();
        after
    }

    /// 辞書の一覧の操作．名前などの書き換え・切り替え・並べ替えは設定の値を書き，取り込みと削除はエンジンに頼む
    fn edit_dictionary_list(
        &mut self,
        list: DictionaryList,
        action: DictionaryAction,
        index: Option<usize>,
    ) -> Option<After> {
        let model = self.model.as_mut()?;
        let path = list.path();
        let current = model.value(path).cloned();
        let entries = crate::dictionaries::entries(list, current.as_ref());
        let chosen = index.and_then(|index| entries.get(index));
        let changed = match (&action, index) {
            (DictionaryAction::Import, _) => {
                let limit = match list {
                    DictionaryList::Imported => self.catalog.limits.imported_dictionaries,
                    DictionaryList::Association => self.catalog.limits.association_dictionaries,
                };
                if entries.len() >= limit {
                    return Some(After::Notice(match list {
                        DictionaryList::Imported => dictionaries::too_many(limit),
                        DictionaryList::Association => association::too_many(limit),
                    }));
                }
                return Some(After::ImportDictionary {
                    list,
                    replacing: None,
                });
            }
            (DictionaryAction::Reimport, _) => {
                let entry = chosen.filter(|entry| !entry.is_bundled)?;
                return Some(After::ImportDictionary {
                    list,
                    replacing: Some(entry.id.clone()),
                });
            }
            (DictionaryAction::Remove, _) => {
                // 同梱の辞書は消せない(オフにはできる)
                let entry = chosen.filter(|entry| !entry.is_bundled)?;
                let outcome = model.store().remove_dictionary(list, entry.id.clone());
                return self.finish_dictionary(list, outcome, false);
            }
            (DictionaryAction::Update(inputs), Some(index)) => {
                match crate::dictionaries::update(list, current.as_ref(), index, inputs) {
                    Some(value) => value,
                    None => {
                        return Some(After::Message {
                            text: text::INVALID_APP,
                            warning: true,
                        })
                    }
                }
            }
            (DictionaryAction::Toggle, Some(index)) => {
                crate::dictionaries::toggle(current.as_ref(), index)?
            }
            (DictionaryAction::MoveUp, Some(index)) => {
                crate::dictionaries::moved(current.as_ref(), index, -1)?
            }
            (DictionaryAction::MoveDown, Some(index)) => {
                crate::dictionaries::moved(current.as_ref(), index, 1)?
            }
            _ => return None,
        };
        let result = model.set(path, changed);
        let after = result.err().and_then(|error| self.failure(error));
        self.refresh();
        after
    }

    /// 選んだファイルを辞書として取り込む
    fn import_dictionary(
        &mut self,
        list: DictionaryList,
        path: String,
        replacing: Option<String>,
    ) -> Option<After> {
        let outcome = self
            .model
            .as_ref()?
            .store()
            .import_dictionary(list, path, replacing);
        self.finish_dictionary(list, outcome, true)
    }

    /// 取り込み・削除の結果を知らせ，設定を読み直す
    fn finish_dictionary(
        &mut self,
        list: DictionaryList,
        outcome: Result<FileOutcome, StoreError>,
        importing: bool,
    ) -> Option<After> {
        let outcome = match outcome {
            Err(error) => return self.failure(error),
            Ok(outcome) => outcome,
        };
        if self.model.as_mut()?.reload().is_err() {
            self.disconnect();
            return None;
        }
        self.refresh();
        let import_failed = match list {
            DictionaryList::Imported => dictionaries::IMPORT_FAILED,
            DictionaryList::Association => association::IMPORT_FAILED,
        };
        match outcome {
            FileOutcome::Imported(count) => Some(After::Notice(match list {
                DictionaryList::Imported => dictionaries::imported(count),
                DictionaryList::Association => association::imported(count),
            })),
            FileOutcome::Failed(FileFailure::WriteFailed) => Some(failed()),
            FileOutcome::Failed(_) if importing => Some(After::Message {
                text: import_failed,
                warning: true,
            }),
            FileOutcome::Failed(_) | FileOutcome::Done => None,
        }
    }

    /// 編集しているカスタムテーマの色・形・書体を変える
    fn edit_theme(&mut self, path: &str, value: &serde_json::Value) -> Option<After> {
        let id = self.editing_theme.clone()?;
        let model = self.model.as_mut()?;
        let changed = crate::themes::edited(model.value(crate::themes::THEMES), &id, path, value)?;
        if let Err(error) = model.set(crate::themes::THEMES, changed) {
            return self.failure(error);
        }
        self.check_theme();
        self.refresh();
        None
    }

    /// 編集しているカスタムテーマの読みやすさをエンジンに確かめてもらう(macOS の CustomThemeEditor の読みやすさ)
    fn check_theme(&mut self) {
        self.extras.theme_report = String::new();
        let Some(model) = &self.model else { return };
        let entries = crate::themes::entries(model.value(crate::themes::THEMES));
        let Some(entry) = self
            .editing_theme
            .as_deref()
            .and_then(|id| entries.iter().find(|entry| entry.id == id))
        else {
            return;
        };
        let Ok(issues) = model.store().check_custom_theme(&entry.value) else {
            return;
        };
        self.extras.theme_report = issues
            .iter()
            .map(|issue| {
                let (name, ground) = match issue.pair {
                    ContrastPair::Text => (more::TEXT, more::SURFACE),
                    ContrastPair::TextMuted => (more::TEXT_MUTED, more::SURFACE),
                    ContrastPair::SelectionText => (more::SELECTION_TEXT, more::SELECTION),
                    ContrastPair::Correction => (more::CORRECTION, more::SURFACE),
                };
                more::low_contrast(name, ground, issue.ratio, issue.minimum)
            })
            .collect::<Vec<_>>()
            .join("\n");
    }

    /// カスタムテーマの一覧の操作(macOS の AppearancePage と SettingsModel の draftCustomTheme など)
    fn theme_list(&mut self, action: ThemeAction, index: Option<usize>) -> Option<After> {
        let limit = self.catalog.limits.custom_themes;
        let name_limit = self.catalog.limits.theme_name_length;
        let dark = self.theme.dark;
        let model = self.model.as_mut()?;
        let themes = model.value(crate::themes::THEMES).cloned();
        let active = model
            .value(crate::themes::ACTIVE)
            .and_then(serde_json::Value::as_str)
            .map(str::to_string);
        let entries = crate::themes::entries(themes.as_ref());
        let chosen = index.and_then(|index| entries.get(index));
        let full = || Some(After::Notice(more::themes_full(limit)));
        let seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |elapsed| elapsed.as_nanos());
        let mut changes: Vec<(&'static str, serde_json::Value)> = Vec::new();
        let mut editing = self.editing_theme.clone();
        match action {
            ThemeAction::Rename(name) => {
                let id = &chosen?.id;
                match crate::themes::renamed(themes.as_ref(), id, &name, name_limit) {
                    Some(changed) => changes.push((crate::themes::THEMES, changed)),
                    None => {
                        return Some(After::Message {
                            text: more::INVALID_THEME,
                            warning: true,
                        })
                    }
                }
            }
            ThemeAction::Create | ThemeAction::DuplicateCurrent => {
                if entries.len() >= limit {
                    return full();
                }
                let id = crate::themes::new_id(seed);
                let active_entry = active
                    .as_deref()
                    .and_then(|active| entries.iter().find(|entry| entry.id == active));
                let theme_name = model
                    .value("theme")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("automatic")
                    .to_string();
                let source_name = active_entry.map_or_else(
                    || options::label_of(options::THEMES, &theme_name).to_string(),
                    |entry| entry.name.clone(),
                );
                let name: String = match action {
                    ThemeAction::Create => more::NEW_THEME_NAME.to_string(),
                    _ => more::copy_name(&source_name),
                }
                .chars()
                .take(name_limit)
                .collect();
                let theme = match active_entry {
                    Some(entry) => crate::themes::copy(&entry.value, id.clone(), name)?,
                    None => preset_theme(&theme_name, id.clone(), name, dark),
                };
                changes.push((
                    crate::themes::THEMES,
                    crate::themes::appended(themes.as_ref(), theme),
                ));
                changes.push((crate::themes::ACTIVE, serde_json::Value::String(id.clone())));
                editing = Some(id);
            }
            ThemeAction::Use => {
                let entry = chosen?;
                changes.push((
                    crate::themes::ACTIVE,
                    serde_json::Value::String(entry.id.clone()),
                ));
            }
            ThemeAction::Duplicate => {
                if entries.len() >= limit {
                    return full();
                }
                let entry = chosen?;
                let id = crate::themes::new_id(seed);
                let name: String = more::copy_name(&entry.name)
                    .chars()
                    .take(name_limit)
                    .collect();
                let theme = crate::themes::copy(&entry.value, id.clone(), name)?;
                changes.push((
                    crate::themes::THEMES,
                    crate::themes::appended(themes.as_ref(), theme),
                ));
                changes.push((crate::themes::ACTIVE, serde_json::Value::String(id.clone())));
                editing = Some(id);
            }
            ThemeAction::Delete => {
                let entry = chosen?;
                changes.push((
                    crate::themes::THEMES,
                    crate::themes::removed(themes.as_ref(), &entry.id)?,
                ));
                if active.as_deref() == Some(entry.id.as_str()) {
                    changes.push((crate::themes::ACTIVE, serde_json::Value::Null));
                }
                if editing.as_deref() == Some(entry.id.as_str()) {
                    editing = None;
                }
            }
        }
        if let Err(error) = model.set_all(&changes) {
            return self.failure(error);
        }
        self.editing_theme = editing;
        self.check_theme();
        self.refresh();
        None
    }

    /// 外観の見本を描く．見本の部品でなければ false
    fn paint_preview(&mut self, target: &DrawTarget) -> bool {
        if !self.view.is_preview(target.window) {
            return false;
        }
        Canvas::of(target).fill(target.rect, self.theme.palette.card);
        let Some(model) = &self.model else {
            return true;
        };
        if self.preview.is_none() {
            self.preview = candidate_ui::app::preview::Preview::new().ok();
        }
        let Some(preview) = &self.preview else {
            return true;
        };
        // 編集しているカスタムテーマがあればそれを，無ければ今使っているテーマを見せる
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
            .unwrap_or("automatic");
        let look = candidate_ui::theme::SystemLook {
            dark: self.theme.dark,
            accent: None,
            increase_contrast: ffi::high_contrast(),
            backdrop: false,
        };
        let resolved =
            candidate_ui::theme::ResolvedTheme::resolve(theme_name, shown.as_ref(), &look);
        let font_size = model
            .value("candidateFontSize")
            .and_then(serde_json::Value::as_f64)
            .map_or(tokens::size::candidate::FONT_SIZE, |size| size as f32);
        let (left, top, right, bottom) = target.rect;
        let rect = windows::Win32::Foundation::RECT {
            left,
            top,
            right,
            bottom,
        };
        let scale = self.theme.dpi as f32 / ffi::BASE_DPI as f32;
        let _ = preview.paint(
            target.hdc,
            rect,
            &resolved,
            font_size,
            self.theme.dark,
            scale,
        );
        true
    }

    /// 同期の状態を画面の値にする
    fn show_sync(&mut self, status: &SyncStatus) {
        self.sync_values = crate::sync::values(status);
        self.extras.sync_folder = status
            .folder_name
            .clone()
            .unwrap_or_else(|| sync_text::NO_FOLDER.to_string());
        self.extras.last_synced = status
            .last_synced_at
            .as_deref()
            .and_then(crate::sync::parse_time)
            .map(|time| crate::sync::format_time(ffi::local_time(time).unwrap_or(time)))
            .unwrap_or_else(|| NO_TIME.to_string());
        self.sync_rows = crate::sync::field_rows(status);
        self.extras.sync_fields = crate::sync::field_table(&self.sync_rows);
    }

    /// 同期の要求をエンジンに頼み，返った状態を画面に出す
    fn request_sync(&mut self, body: RequestBody) -> Option<After> {
        let result = self.model.as_ref()?.store().sync(body);
        match result {
            Err(error) => self.failure(error),
            Ok(status) => {
                self.show_sync(&status);
                self.refresh();
                None
            }
        }
    }

    /// 記号の決まりを重ねる・外す・切り替える．終わったら一覧を読み直す
    fn edit_symbols(&mut self, event: Event) -> Option<After> {
        let model = self.model.as_ref()?;
        let store = model.store();
        let items = match &event {
            Event::SymbolSave { kind, .. }
            | Event::SymbolRemove { kind, .. }
            | Event::SymbolToggle { kind, .. } => match kind {
                SymbolKind::Sequence => &self.sequences,
                SymbolKind::Reading => &self.readings,
            },
            _ => return None,
        };
        let selected = |indices: &[usize]| -> Vec<SymbolItem> {
            indices
                .iter()
                .filter_map(|index| items.get(*index).cloned())
                .collect()
        };
        let mut notice = None;
        let result = match event {
            Event::SymbolSave {
                kind,
                item,
                replacing,
            } => {
                let input = item.first().cloned().unwrap_or_default();
                let output = item.get(1).cloned().unwrap_or_default();
                // 選んで書き換えている決まりは，その入力を置き換える(既定の決まりの入力は変えられない)
                let old = replacing
                    .and_then(|index| items.get(index))
                    .map(|item| item.input.clone());
                // 無効にしていた決まりを書き換えたときも無効のまま
                let enabled = items
                    .iter()
                    .find(|existing| {
                        Some(&existing.input) == old.as_ref() || existing.input == input
                    })
                    .is_none_or(|existing| existing.is_enabled);
                store
                    .save_symbol_rule(kind, input, output, enabled, old)
                    .map(|result| {
                        notice = match result {
                            SymbolSaveResult::Saved => None,
                            SymbolSaveResult::Invalid => Some(symbol_invalid(kind)),
                            SymbolSaveResult::Full => Some(rule_list::FULL),
                        };
                    })
            }
            Event::SymbolRemove { kind, indices } => {
                let inputs = selected(&indices)
                    .into_iter()
                    .map(|item| item.input)
                    .collect();
                store.remove_symbol_rules(kind, inputs)
            }
            Event::SymbolToggle { kind, indices } => {
                selected(&indices).into_iter().try_for_each(|item| {
                    store
                        .save_symbol_rule(kind, item.input, item.output, !item.is_enabled, None)
                        .map(|_| ())
                })
            }
            _ => Ok(()),
        };
        if let Err(error) = result {
            return self.failure(error);
        }
        if notice.is_none() {
            self.view.clear_symbol_inputs();
        }
        self.read_extras();
        self.refresh();
        notice.map(|text| After::Message {
            text,
            warning: true,
        })
    }

    /// 選んだファイルを読み込む・書き出す．読み込んだら設定と辞書を読み直す
    fn run_file(&mut self, task: FileTask, path: String) -> Option<After> {
        let model = self.model.as_mut()?;
        let outcome = model.store().run_file(task, path);
        let outcome = match outcome {
            Err(error) => return self.failure(error),
            Ok(outcome) => outcome,
        };
        if task.is_import() {
            if model.reload().is_err() {
                self.disconnect();
                return None;
            }
            self.read_extras();
            self.refresh();
        }
        match outcome {
            FileOutcome::Done => task.done().map(|text| After::Message {
                text,
                warning: false,
            }),
            FileOutcome::Imported(added) => Some(After::Notice(task.imported(added))),
            FileOutcome::Failed(_) => Some(After::Message {
                text: task.failed(),
                warning: true,
            }),
        }
    }

    /// 一覧に行を足す．上限を超える・形が誤っていて残らないときは知らせる
    fn add_to_list(
        &mut self,
        spec: &ListSpec,
        limit: usize,
        item: &Item,
        replacing: Option<usize>,
    ) -> Option<After> {
        if !spec.is_valid(item) {
            return Some(After::Message {
                text: spec.invalid,
                warning: true,
            });
        }
        let model = self.model.as_mut()?;
        // 選んで書き換えている行は，消してから足す(同じ位置ではなく，ほかの行と同じく決まりの並びで足す)
        let current = match replacing {
            Some(index) => Some(spec.remove(model.value(spec.path), &[index])),
            None => model.value(spec.path).cloned(),
        };
        let items = spec.items(current.as_ref());
        let is_new = !items.iter().any(|existing| spec.same_key(existing, item));
        if is_new && items.len() >= limit {
            return Some(After::Message {
                text: rule_list::FULL,
                warning: true,
            });
        }
        // いつも英語にする語といつも日本語にする語は，足した語をもう一方から除く(macOS と同じ)
        let mut changes = vec![(spec.path, spec.upsert(current.as_ref(), item))];
        if let (Some(other), Some(word)) = (spec.exclusive_with, item.first()) {
            changes.push((other, ListSpec::without(model.value(other), word)));
        }
        let result = model.set_all(&changes);
        let kept = spec.contains(model.value(spec.path), item);
        let after = match result {
            Err(error) => self.failure(error),
            Ok(()) if !kept => Some(After::Message {
                text: spec.invalid,
                warning: true,
            }),
            Ok(()) => {
                self.view.clear_list_inputs(spec.path);
                None
            }
        };
        self.refresh();
        after
    }

    fn draw_nav(&self, target: &DrawTarget) {
        let Some(entry) = target.index.and_then(|index| self.entries.get(index)) else {
            return;
        };
        let theme = &self.theme;
        let palette = &theme.palette;
        let px = |value: f32| theme.px(value);
        let canvas = Canvas::of(target);
        let (left, top, right, bottom) = target.rect;
        canvas.fill(target.rect, palette.background);
        let mut item_top = top;
        if let Some(group) = entry.header {
            item_top = top + px(size::NAV_HEADER_HEIGHT);
            canvas.text(
                (left + px(size::NAV_PADDING_X), top, right, item_top),
                group.title(),
                &theme.fonts.section,
                palette.text,
                DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS,
            );
        }
        let gap = px(size::CARD_GAP);
        let item = (
            left + gap,
            item_top + gap / 2,
            right - gap,
            bottom - gap / 2,
        );
        let text = if target.selected {
            canvas.round_rect(item, px(size::CARD_RADIUS), palette.nav_selected, None);
            let indicator_height = px(size::NAV_INDICATOR_HEIGHT);
            let middle = (item.1 + item.3) / 2;
            canvas.round_rect(
                (
                    item.0,
                    middle - indicator_height / 2,
                    item.0 + px(size::NAV_INDICATOR_WIDTH),
                    middle + indicator_height / 2,
                ),
                px(size::NAV_INDICATOR_WIDTH) / 2,
                palette.accent,
                None,
            );
            if theme.high_contrast {
                palette.accent_text
            } else {
                palette.text
            }
        } else {
            palette.text
        };
        let mut x = item.0 + px(size::NAV_PADDING_X);
        if let Some(icon) = &theme.fonts.icon {
            let icon_size = px(size::ICON_FONT_SIZE);
            canvas.text(
                (x, item.1, x + icon_size, item.3),
                &entry.page.glyph().to_string(),
                icon,
                text,
                DT_LEFT | DT_VCENTER | DT_SINGLELINE,
            );
            x += icon_size + px(size::NAV_ICON_GAP);
        }
        canvas.text(
            (x, item.1, item.2, item.3),
            entry.page.title(),
            &theme.fonts.body,
            text,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS,
        );
        if target.focused {
            canvas.frame(item, palette.text);
        }
    }
}

/// 標準のひな形の値(KeymapPreset.standard)
const STANDARD_PRESET: &str = "standard";

/// ひな形を読んで keymap の項目に書く
fn load_preset(model: &mut SettingsModel<Store>, preset: &str) -> Result<(), StoreError> {
    let fields = model.store().read_keymap_preset(preset)?;
    let keymap = fields.get("keymap").cloned().ok_or(StoreError::Malformed)?;
    model.set("keymap", keymap)
}

/// 今の表の問題を文にする．調べられなければ空
fn keymap_report(model: &SettingsModel<Store>) -> String {
    let Some(keymap) = model.value("keymap").cloned() else {
        return String::new();
    };
    let entries: Vec<(String, String, String)> = keymap
        .as_array()
        .map(|rows| {
            rows.iter()
                .map(|row| {
                    let text = |name: &str| {
                        row.get(name)
                            .and_then(serde_json::Value::as_str)
                            .unwrap_or("")
                            .to_string()
                    };
                    (text("state"), text("key"), text("command"))
                })
                .collect()
        })
        .unwrap_or_default();
    let mut values = crate::store::Fields::new();
    values.insert("keymap".to_string(), keymap);
    model
        .store()
        .check_keymap(&values)
        .map(|report| crate::keys::report_lines(&report, &entries).join("\n"))
        .unwrap_or_default()
}

/// 確かめてから行う操作の題と文
fn confirmation(event: &Event) -> Option<(String, String)> {
    let name = |preset: &str| {
        keys::PRESETS
            .iter()
            .find(|(value, _)| *value == preset)
            .map_or(preset, |(_, label)| label)
            .to_string()
    };
    match event {
        Event::LoadPreset(preset) => Some((
            keys::LOAD_PRESET_TITLE.to_string(),
            keys::load_preset_message(&name(preset)),
        )),
        Event::Action(Action::RestoreKeymap) => Some((
            keys::RESTORE_TITLE.to_string(),
            keys::RESTORE_MESSAGE.to_string(),
        )),
        Event::ThemeList {
            action: ThemeAction::Delete,
            name,
            ..
        } => Some((
            settings::WINDOW_TITLE.to_string(),
            more::confirm_delete_theme(name),
        )),
        _ => None,
    }
}

/// 既成のテーマの色を写したカスタムテーマ(macOS の SettingsModel.customTheme(from:) と同じ)．
/// 色は候補ウィンドウと同じ解き方で，今の画面の明暗の色にする
fn preset_theme(
    theme: &str,
    id: String,
    name: String,
    dark: bool,
) -> serde_json::Map<String, serde_json::Value> {
    use candidate_ui::theme::{Color, ResolvedTheme, SystemLook};
    let resolved = ResolvedTheme::resolve(
        theme,
        None,
        &SystemLook {
            dark,
            ..SystemLook::default()
        },
    );
    let hex = |color: Color| crate::themes::hex(color.red, color.green, color.blue);
    crate::themes::from_colors(
        id,
        name,
        theme,
        [
            ("surface", hex(resolved.surface)),
            ("text", hex(resolved.text)),
            ("textMuted", hex(resolved.text_muted)),
            ("selection", hex(resolved.selection)),
            ("selectionText", hex(resolved.selection_text)),
            ("correction", hex(resolved.correction)),
            ("line", hex(resolved.line)),
        ],
        f64::from(resolved.corner_radius),
    )
}

/// 一度も同期していないときの時刻(macOS の SyncPage と同じ)
const NO_TIME: &str = "—";

/// 記号の一覧の 1 行(入力・記号・状態)．状態は無効と，既定から変えた・足した印
fn symbol_row(item: &SymbolItem) -> Vec<String> {
    let origin = match item.origin {
        SymbolOrigin::Standard => None,
        SymbolOrigin::Changed => Some(features::CHANGED),
        SymbolOrigin::Added => Some(features::ADDED),
    };
    let state: Vec<&str> = (!item.is_enabled)
        .then_some(text::DISABLED)
        .into_iter()
        .chain(origin)
        .collect();
    vec![item.input.clone(), item.output.clone(), state.join("・")]
}

fn symbol_invalid(kind: SymbolKind) -> &'static str {
    match kind {
        SymbolKind::Sequence => features::INVALID_SYMBOL,
        SymbolKind::Reading => features::INVALID_READING_SYMBOL,
    }
}

fn failed() -> After {
    After::Message {
        text: settings::SAVE_FAILED,
        warning: true,
    }
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
        WM_MEASUREITEM => {
            let index = ffi::measure_item_index(lparam)?;
            let height = NAV_HEIGHTS.with(|cell| cell.borrow().get(index).copied())?;
            ffi::set_measured_height(lparam, height);
            Some(LRESULT(1))
        }
        WM_DRAWITEM => {
            let target = ffi::draw_item(lparam)?;
            with_app(|app| app.draw_nav(&target))?;
            Some(LRESULT(1))
        }
        WM_COMMAND => {
            let id = low_word(wparam.0) as u16;
            let notification = high_word(wparam.0);
            with_app(|app| match (id, notification) {
                (ID_SEARCH, EN_CHANGE) => {
                    let query = app.query();
                    app.fill_nav(&query);
                }
                (ID_NAV, LBN_SELCHANGE) => {
                    let index = usize::try_from(ffi::send(app.nav, LB_GETCURSEL, 0, 0)).ok();
                    if let Some(entry) = index.and_then(|index| app.entries.get(index)).copied() {
                        if entry.page != app.view.page {
                            app.open_page(entry.page);
                        }
                    }
                }
                _ => {}
            })?;
            Some(LRESULT(0))
        }
        WM_CTLCOLOREDIT | WM_CTLCOLORLISTBOX => with_app(|app| {
            let palette = &app.theme.palette;
            let (background, brush) = if message == WM_CTLCOLOREDIT {
                (palette.control, app.theme.control.handle())
            } else {
                (palette.background, app.theme.background.handle())
            };
            ffi::color_control(wparam.0, palette.text, background);
            LRESULT(brush)
        }),
        WM_ERASEBKGND => Some(LRESULT(1)),
        WM_PAINT => {
            let paint = Paint::begin(window);
            with_app(|app| {
                let (width, height) = ffi::client_size(window);
                paint
                    .canvas()
                    .fill((0, 0, width, height), app.theme.palette.background);
            });
            Some(LRESULT(0))
        }
        WM_SIZE => {
            with_app(App::arrange_window);
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
        WM_TIMER if wparam.0 == RECONNECT_TIMER => {
            with_app(|app| {
                if app.model.is_none() {
                    app.connect();
                } else {
                    ffi::kill_timer(app.window, RECONNECT_TIMER);
                }
            });
            Some(LRESULT(0))
        }
        WM_ACTIVATE => {
            if low_word(wparam.0) != WA_INACTIVE {
                with_app(App::reload);
            }
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
        WM_MOUSEWHEEL => {
            forward_wheel(wparam);
            Some(LRESULT(0))
        }
        WM_DESTROY => {
            APP.with(|cell| {
                if let Ok(mut app) = cell.try_borrow_mut() {
                    app.take();
                }
            });
            ffi::quit();
            Some(LRESULT(0))
        }
        _ => None,
    }
}

fn forward_wheel(wparam: WPARAM) {
    let delta = high_word(wparam.0) as u16 as i16;
    with_app(|app| {
        let step = app.theme.px(size::SCROLL_LINE) * 3;
        let lines = i32::from(delta) * step / WHEEL_DELTA as i32;
        app.scroll_to(app.scroll - lines);
    });
}

extern "system" fn host_procedure(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let handled = std::panic::catch_unwind(|| host_message(window, message, wparam, lparam));
    match handled {
        Ok(Some(result)) => result,
        _ => ffi::default_procedure(window, message, wparam, lparam),
    }
}

fn host_message(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
    match message {
        WM_ERASEBKGND => Some(LRESULT(1)),
        WM_DRAWITEM => {
            // 外観の見本(SS_OWNERDRAW)を候補ウィンドウと同じ描き方で描く
            let target = ffi::draw_item(lparam)?;
            let drawn = with_app(|app| app.paint_preview(&target))?;
            drawn.then_some(LRESULT(1))
        }
        WM_PAINT => {
            let paint = Paint::begin(window);
            with_app(|app| {
                let (width, height) = ffi::client_size(window);
                let canvas = paint.canvas();
                canvas.fill((0, 0, width, height), app.theme.palette.background);
                app.view.paint(canvas, &app.theme, app.scroll);
            });
            Some(LRESULT(0))
        }
        WM_COMMAND => {
            let control = HWND(lparam.0 as *mut _);
            let notification = high_word(wparam.0);
            let (owner, event) =
                with_app(|app| Some((app.window, app.view.command(control, notification)?)))??;
            // 表を置き換える操作は，借りている状態を返してから確かめる
            if let Some((title, text)) = confirmation(&event) {
                if !ffi::confirm(owner, &title, &text) {
                    return Some(LRESULT(0));
                }
            }
            let after = with_app(|app| app.handle(event))?;
            run_after(owner, after);
            Some(LRESULT(0))
        }
        WM_NOTIFY => {
            let (from, code) = ffi::notify_header(lparam)?;
            if code != NM_CUSTOMDRAW {
                let (handled, event) = with_app(|app| app.view.notify(from, code, lparam))?;
                if let Some(event) = event {
                    let owner = with_app(|app| app.window)?;
                    let after = with_app(|app| app.handle(event)).flatten();
                    run_after(owner, after);
                }
                return handled.then_some(LRESULT(1));
            }
            let (stage, target) = ffi::custom_draw(lparam)?;
            if stage != CDDS_PREPAINT.0 {
                return None;
            }
            let drawn = with_app(|app| app.view.draw(&target, &app.theme))?;
            drawn.then_some(LRESULT(CDRF_SKIPDEFAULT as isize))
        }
        WM_CTLCOLORSTATIC => with_app(|app| {
            let control = HWND(lparam.0 as *mut _);
            let palette = &app.theme.palette;
            let (on_card, secondary) = app.view.static_style(control).unwrap_or((false, false));
            let (background, brush) = if on_card {
                (palette.card, app.theme.card.handle())
            } else {
                (palette.background, app.theme.background.handle())
            };
            let text = if secondary {
                palette.text_secondary
            } else {
                palette.text
            };
            ffi::color_control(wparam.0, text, background);
            LRESULT(brush)
        }),
        WM_CTLCOLORLISTBOX | WM_CTLCOLOREDIT => with_app(|app| {
            let palette = &app.theme.palette;
            ffi::color_control(wparam.0, palette.text, palette.control);
            LRESULT(app.theme.control.handle())
        }),
        // ボタンの角の外はカードの地にする
        WM_CTLCOLORBTN => with_app(|app| {
            let palette = &app.theme.palette;
            ffi::color_control(wparam.0, palette.text, palette.card);
            LRESULT(app.theme.card.handle())
        }),
        WM_VSCROLL => {
            let request = low_word(wparam.0) as i32;
            let thumb = high_word(wparam.0) as i32;
            with_app(|app| {
                let line = app.theme.px(size::SCROLL_LINE);
                let (_, page) = ffi::client_size(app.host);
                let target = match request {
                    value if value == SB_LINEUP.0 => app.scroll - line,
                    value if value == SB_LINEDOWN.0 => app.scroll + line,
                    value if value == SB_PAGEUP.0 => app.scroll - page,
                    value if value == SB_PAGEDOWN.0 => app.scroll + page,
                    value if value == SB_THUMBTRACK.0 || value == SB_THUMBPOSITION.0 => thumb,
                    value if value == SB_TOP.0 => 0,
                    value if value == SB_BOTTOM.0 => app.content_height,
                    _ => app.scroll,
                };
                app.scroll_to(target);
            });
            Some(LRESULT(0))
        }
        WM_MOUSEWHEEL => {
            forward_wheel(wparam);
            Some(LRESULT(0))
        }
        _ => None,
    }
}
