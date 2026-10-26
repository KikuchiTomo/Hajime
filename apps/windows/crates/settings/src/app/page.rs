#![forbid(unsafe_code)]

//! 1 ページ分の部品．項目の並び(pages::Section)から部品を作り，値を映し，押された部品を頼み(Event)にする．
//! 名前と説明は STATIC にして読み上げで部品の名前として読まれるようにし，カードの地は親の窓が描く

use super::ffi::{self, Canvas, DrawTarget, Window};
use super::theme::Theme;
use crate::catalog::Catalog;
use crate::layout::{self, PageLayout};
use crate::list::{Item, ListSpec};
use crate::model::SettingsModel;
use crate::options;
use crate::pages::{self, Action, Control, DictionaryList, Info, LimitKind, Page, Row, Section};
use crate::store::SettingsStore;
use crate::strings::{features, keys, more, windows as text};
use crate::usage::Usage;
use ipc::SymbolKind;
use serde_json::Value;
use tokens::size::settings_windows as size;
use windows::Win32::Foundation::LPARAM;
use windows::Win32::Graphics::Gdi::{DT_RIGHT, DT_SINGLELINE, DT_VCENTER};
use windows::Win32::System::SystemServices::{SS_ENDELLIPSIS, SS_NOPREFIX, SS_RIGHT};
use windows::Win32::UI::Controls::{
    EM_SETCUEBANNER, LVN_GETEMPTYMARKUP, LVN_ITEMCHANGED, LVS_NOSORTHEADER, LVS_REPORT,
    LVS_SHOWSELALWAYS, WC_LISTVIEW,
};
use windows::Win32::UI::WindowsAndMessaging::{
    BM_GETCHECK, BM_SETCHECK, BN_CLICKED, BS_AUTOCHECKBOX, BS_PUSHBUTTON, CBN_SELCHANGE,
    CBS_DROPDOWNLIST, CB_ADDSTRING, CB_GETCURSEL, CB_SETCURSEL, CB_SETITEMHEIGHT, WINDOW_EX_STYLE,
    WINDOW_STYLE, WS_CHILD, WS_TABSTOP, WS_VISIBLE, WS_VSCROLL,
};
use windows::Win32::UI::WindowsAndMessaging::{
    EN_CHANGE, ES_AUTOHSCROLL, ES_AUTOVSCROLL, ES_MULTILINE, ES_READONLY, WS_EX_CLIENTEDGE,
};
use windows_core::w;

/// 部品の番号の始まり(0 は使わない)
const FIRST_ID: u16 = 100;

/// 部品の操作から生まれる頼み
#[derive(Debug, Clone, PartialEq)]
pub enum Event {
    Set {
        path: &'static str,
        value: Value,
        clears: Option<&'static str>,
    },
    Reset(&'static str),
    Action(Action),
    ListAdd {
        spec: ListSpec,
        limit: LimitKind,
        item: Item,
    },
    ListRemove {
        spec: ListSpec,
        indices: Vec<usize>,
    },
    /// 単語を登録する(読み・単語)
    DictionaryAdd(Item),
    /// 選んだ単語を消す(表の行の番号)
    DictionaryRemove(Vec<usize>),
    /// 記号の決まりを重ねる(入力・記号)
    SymbolSave {
        kind: SymbolKind,
        item: Item,
    },
    /// 選んだ記号の決まりを外す(表の行の番号)
    SymbolRemove {
        kind: SymbolKind,
        indices: Vec<usize>,
    },
    /// 選んだ記号の決まりの有効と無効を切り替える(表の行の番号)
    SymbolToggle {
        kind: SymbolKind,
        indices: Vec<usize>,
    },
    /// 選んだ項目の同期の範囲を切り替える(表の行の番号)
    SyncToggleFields(Vec<usize>),
    /// 辞書の一覧の操作(index は選んだ行)
    DictionaryList {
        list: DictionaryList,
        action: DictionaryAction,
        index: Option<usize>,
    },
    /// キー設定のひな形を読み込む(ひな形の値)
    LoadPreset(&'static str),
    /// 英語と日本語の見分けを試す
    Preview {
        text: String,
        preceding: String,
    },
}

/// 辞書の一覧のボタンの操作
#[derive(Debug, Clone, PartialEq)]
pub enum DictionaryAction {
    /// 入力欄の値(名前・分野・使う場面・アプリ)で選んだ辞書を書き換える
    Update(Vec<String>),
    Import,
    Reimport,
    MoveUp,
    MoveDown,
    Toggle,
    Remove,
}

impl DictionaryAction {
    /// 表の下のボタンの並び(pages::Control::list_buttons と同じ)
    const BOTTOM: [DictionaryAction; 6] = [
        DictionaryAction::Import,
        DictionaryAction::Reimport,
        DictionaryAction::MoveUp,
        DictionaryAction::MoveDown,
        DictionaryAction::Toggle,
        DictionaryAction::Remove,
    ];
}

/// 画面に映す値
pub trait Values {
    fn value(&self, path: &str) -> Option<&Value>;
    fn is_default(&self, path: &str) -> bool;
    fn is_readable(&self, path: &str) -> bool;

    fn text(&self, path: &str) -> String {
        self.value(path)
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string()
    }

    fn on(&self, path: &str) -> bool {
        self.value(path).and_then(Value::as_bool).unwrap_or(false)
    }
}

impl<S: SettingsStore> Values for SettingsModel<S> {
    fn value(&self, path: &str) -> Option<&Value> {
        SettingsModel::value(self, path)
    }

    fn is_default(&self, path: &str) -> bool {
        SettingsModel::is_default(self, path)
    }

    fn is_readable(&self, path: &str) -> bool {
        SettingsModel::is_readable(self, path)
    }
}

/// 設定の値に，同期の状態の値(「sync.」の道筋．crate::sync)を重ねたもの
pub struct WithSync<'a, V: Values> {
    pub values: &'a V,
    pub sync: &'a crate::store::Fields,
}

impl<V: Values> Values for WithSync<'_, V> {
    fn value(&self, path: &str) -> Option<&Value> {
        if crate::sync::is_sync_path(path) {
            return self.sync.get(path);
        }
        self.values.value(path)
    }

    /// 同期の値には既定に戻すボタンを出さない
    fn is_default(&self, path: &str) -> bool {
        crate::sync::is_sync_path(path) || self.values.is_default(path)
    }

    /// 同期の値はエンジンから読めたときだけ使える
    fn is_readable(&self, path: &str) -> bool {
        if crate::sync::is_sync_path(path) {
            return self.sync.contains_key(path);
        }
        self.values.is_readable(path)
    }
}

/// 設定の値のほかにエンジンから読んで画面に出すもの
#[derive(Debug, Default)]
pub struct Extras {
    pub usage: Usage,
    /// 登録した単語(読み・単語)
    pub dictionary: Vec<Vec<String>>,
    /// 記号の一覧(入力・記号・状態)．連続入力と読み
    pub sequences: Vec<Vec<String>>,
    pub readings: Vec<Vec<String>>,
    /// 同期の状態の値(「sync.」の道筋)
    pub sync: crate::store::Fields,
    /// 同期のフォルダの名前と最後に同期した時刻(出す形)
    pub sync_folder: String,
    pub last_synced: String,
    /// 項目ごとの同期の表(項目・範囲)
    pub sync_fields: Vec<Vec<String>>,
    /// キー設定の表の問題の文(無ければ空)
    pub keymap_report: String,
}

impl Extras {
    pub fn symbol_rows(&self, kind: SymbolKind) -> &[Vec<String>] {
        match kind {
            SymbolKind::Sequence => &self.sequences,
            SymbolKind::Reading => &self.readings,
        }
    }

    pub fn symbol_rows_mut(&mut self, kind: SymbolKind) -> &mut Vec<Vec<String>> {
        match kind {
            SymbolKind::Sequence => &mut self.sequences,
            SymbolKind::Reading => &mut self.readings,
        }
    }
}

struct RowView {
    row: Row,
    /// 名前(注記では説明)
    label: Option<Window>,
    control: Option<Window>,
    reset: Option<Window>,
    /// 数を選ぶ部品の選択肢
    numbers: Vec<f64>,
    /// 一覧の入力欄とボタン(layout の CardLayout::parts と同じ並び)
    parts: Vec<Window>,
    visible: bool,
    /// 辞書の一覧の行ごとの入力欄の値(行を選んだら入力欄に出す)
    dictionary_inputs: Vec<Vec<String>>,
}

impl RowView {
    fn list_spec(&self) -> Option<(&ListSpec, LimitKind)> {
        match &self.row.control {
            Control::List(spec, limit) => Some((spec, *limit)),
            Control::Dictionary(spec) => Some((spec, LimitKind::UserDictionaryEntries)),
            // 記号・辞書の上限はエンジンが確かめ，項目ごとの同期は足さないので，上限は使わない
            Control::Symbols(_, spec)
            | Control::SyncFields(spec)
            | Control::Dictionaries(_, spec) => Some((spec, LimitKind::ProfileRules)),
            _ => None,
        }
    }

    /// 表の列の数
    fn columns(&self) -> Option<usize> {
        self.list_spec()?;
        Some(self.row.control.table_columns().len())
    }

    /// 選んだ行を切り替えるボタン(記号の有効と無効，項目ごとの同期の範囲)
    fn toggle_button(&self) -> Option<Window> {
        let (spec, _) = self.list_spec()?;
        match self.row.control {
            Control::Symbols(..) => self.parts.get(spec.fields.len() + 2).copied(),
            Control::SyncFields(_) => self.parts.first().copied(),
            _ => None,
        }
    }

    /// 一覧の入力欄(左・右)と追加・削除のボタン．追加・削除の無い一覧(項目ごとの同期・辞書の一覧)では None
    fn list_parts(&self) -> Option<(&[Window], Window, Window)> {
        if matches!(
            self.row.control,
            Control::SyncFields(_) | Control::Dictionaries(..)
        ) {
            return None;
        }
        let (spec, _) = self.list_spec()?;
        let fields = spec.fields.len();
        Some((
            self.parts.get(..fields)?,
            *self.parts.get(fields)?,
            *self.parts.get(fields + 1)?,
        ))
    }

    /// 辞書の一覧の入力欄・更新のボタン・表の下のボタン(取り込む・再読み込み・上げる・下げる・切り替え・削除)
    fn dictionary_parts(&self) -> Option<(&[Window], Window, &[Window])> {
        let Control::Dictionaries(_, spec) = &self.row.control else {
            return None;
        };
        let fields = spec.fields.len();
        Some((
            self.parts.get(..fields)?,
            *self.parts.get(fields)?,
            self.parts.get(fields + 1..)?,
        ))
    }

    fn windows(&self) -> impl Iterator<Item = Window> + '_ {
        [self.label, self.control, self.reset]
            .into_iter()
            .flatten()
            .chain(self.parts.iter().copied())
    }
}

pub struct PageView {
    pub page: Page,
    sections: Vec<Section>,
    title: Option<Window>,
    section_titles: Vec<Option<Window>>,
    footers: Vec<Option<Window>>,
    rows: Vec<Vec<RowView>>,
    layout: PageLayout,
}

impl PageView {
    /// エンジンにつながらないときのページ(名前と知らせだけ)
    pub fn unavailable(host: Window, theme: &Theme, page: Page, catalog: &Catalog) -> Self {
        let sections = vec![Section {
            title: None,
            rows: Vec::new(),
            footer: Some(text::ENGINE_UNAVAILABLE),
        }];
        Self::build(host, theme, page, sections, catalog)
    }

    pub fn new(host: Window, theme: &Theme, page: Page, catalog: &Catalog) -> Self {
        Self::build(
            host,
            theme,
            page,
            pages::sections(page).unwrap_or_default(),
            catalog,
        )
    }

    fn build(
        host: Window,
        theme: &Theme,
        page: Page,
        sections: Vec<Section>,
        catalog: &Catalog,
    ) -> Self {
        let mut id = FIRST_ID;
        let mut next_id = || {
            id = id.wrapping_add(1);
            id
        };
        let title = label(host, page.title(), &theme.fonts.title, next_id());
        let mut section_titles = Vec::new();
        let mut footers = Vec::new();
        let mut rows = Vec::new();
        for section in &sections {
            section_titles.push(
                section
                    .title
                    .and_then(|title| label(host, title, &theme.fonts.section, next_id())),
            );
            let mut views = Vec::new();
            for row in &section.rows {
                views.push(create_row(host, theme, row, catalog, &mut next_id));
            }
            rows.push(views);
            footers.push(
                section
                    .footer
                    .and_then(|footer| label(host, footer, &theme.fonts.caption, next_id())),
            );
        }
        Self {
            page,
            sections,
            title,
            section_titles,
            footers,
            rows,
            layout: PageLayout {
                title: Default::default(),
                sections: Vec::new(),
                height: 0.0,
            },
        }
    }

    /// 部品をすべて消す
    pub fn destroy(self) {
        let windows = self
            .rows
            .iter()
            .flatten()
            .flat_map(|row| row.windows().collect::<Vec<_>>())
            .chain(self.section_titles.iter().flatten().copied())
            .chain(self.footers.iter().flatten().copied())
            .chain(self.title);
        for window in windows.collect::<Vec<_>>() {
            ffi::destroy(window);
        }
    }

    /// 書体を付け直す(DPI が変わったとき)
    pub fn apply_fonts(&self, theme: &Theme) {
        let fonts = &theme.fonts;
        if let Some(title) = self.title {
            ffi::set_font(title, &fonts.title);
        }
        for title in self.section_titles.iter().flatten() {
            ffi::set_font(*title, &fonts.section);
        }
        for footer in self.footers.iter().flatten() {
            ffi::set_font(*footer, &fonts.caption);
        }
        for row in self.rows.iter().flatten() {
            let label_font = if row.row.control == Control::Note {
                &fonts.caption
            } else {
                &fonts.body
            };
            if let Some(label) = row.label {
                ffi::set_font(label, label_font);
            }
            for part in &row.parts {
                ffi::set_font(*part, &fonts.body);
            }
            if let Some(control) = row.control {
                ffi::set_font(control, &fonts.body);
                if matches!(
                    row.row.control,
                    Control::Choice(_) | Control::Stepper(_) | Control::Seconds(_)
                ) {
                    let field = theme.px(size::CONTROL_HEIGHT) - theme.px(size::CONTROL_GAP);
                    ffi::send(control, CB_SETITEMHEIGHT, usize::MAX, field as isize);
                }
            }
        }
    }

    /// 標準の部品の見た目をライト・ダークに合わせる
    pub fn apply_theme(&self, theme: &Theme) {
        for row in self.rows.iter().flatten() {
            let Some(control) = row.control else { continue };
            match &row.row.control {
                Control::Choice(_) | Control::Stepper(_) | Control::Seconds(_) => {
                    ffi::set_theme(control, theme.control_theme(true))
                }
                Control::Action(_) => ffi::set_theme(control, theme.control_theme(false)),
                Control::Preview => {
                    for part in &row.parts {
                        ffi::set_theme(*part, theme.control_theme(true));
                    }
                }
                list if list.list_buttons().is_some() => {
                    apply_list_theme(control, theme);
                    let fields = list.list_spec().map_or(0, |spec| spec.fields.len());
                    for (index, part) in row.parts.iter().enumerate() {
                        ffi::set_theme(*part, theme.control_theme(index < fields));
                    }
                }
                _ => {}
            }
        }
    }

    /// 値を部品に映し，出す・使える状態を決める
    pub fn sync(&mut self, values: &impl Values, extras: &Extras) {
        for row in self.rows.iter_mut().flatten() {
            let condition = |condition| {
                pages::holds(condition, |path| values.text(path), |path| values.on(path))
            };
            row.visible = row.row.visible.is_none_or(condition)
                && (row.row.control != Control::KeymapReport || !extras.keymap_report.is_empty());
            let readable = row.row.path.is_empty() || values.is_readable(row.row.path);
            let enabled = readable && row.row.enabled.is_none_or(condition);
            for window in row.windows().collect::<Vec<_>>() {
                ffi::show(window, row.visible);
            }
            if let Some(control) = row.control {
                ffi::enable(control, enabled);
                show_value(control, &row.row, &row.numbers, values, extras);
            }
            // 一覧を入れ替えると選んだ行が外れるので，削除と切り替えのボタンも使えなくする
            if let Some((fields, _, remove)) = row.list_parts() {
                ffi::enable(remove, false);
                for field in fields {
                    ffi::enable(*field, enabled);
                }
            }
            if let Some(toggle) = row.toggle_button() {
                ffi::enable(toggle, false);
            }
            if let Control::Dictionaries(list, _) = &row.row.control {
                let entries = crate::dictionaries::entries(*list, values.value(list.path()));
                row.dictionary_inputs = entries
                    .iter()
                    .map(|entry| crate::dictionaries::inputs(*list, entry))
                    .collect();
            }
            if let Some((_, update, bottom)) = row.dictionary_parts() {
                // 選んだ行に効くボタンは，行を選ぶまで使えなくする(取り込むボタンだけはいつでも使える)
                ffi::enable(update, false);
                for (index, button) in bottom.iter().enumerate() {
                    ffi::enable(*button, enabled && index == 0);
                }
            }
            if let Some(label) = row.label {
                ffi::enable(label, enabled || row.row.control == Control::Note);
            }
            if let Some(reset) = row.reset {
                ffi::show(
                    reset,
                    row.visible && readable && !values.is_default(row.row.path),
                );
                ffi::enable(reset, enabled);
            }
        }
    }

    /// 部品を置く．width は窓の幅，scroll は上に送った量(どちらも窓の DPI の値)．中身の高さを返す
    pub fn arrange(&mut self, host: Window, theme: &Theme, width: i32, scroll: i32) -> i32 {
        let dpi = theme.dpi;
        let width_96 = width as f32 * ffi::BASE_DPI as f32 / dpi as f32;
        let visible: Vec<bool> = self.rows.iter().flatten().map(|row| row.visible).collect();
        let all: Vec<&Row> = self
            .sections
            .iter()
            .flat_map(|section| &section.rows)
            .collect();
        let line = theme.px(size::NOTE_LINE_HEIGHT).max(1);
        let caption = &theme.fonts.caption;
        self.layout = layout::layout(
            &self.sections,
            width_96,
            |row| {
                all.iter()
                    .position(|candidate| std::ptr::eq(*candidate, row))
                    .is_none_or(|index| visible[index])
            },
            |text, width| {
                let height = ffi::text_height(host, caption, text, ffi::scale(width, dpi));
                usize::try_from((height + line - 1) / line)
                    .unwrap_or(1)
                    .max(1)
            },
        );
        let place = |window: Option<Window>, rect: layout::Rect| {
            if let Some(window) = window {
                let (left, top, right, bottom) = ffi::scaled_rect(rect, dpi, scroll);
                ffi::place(window, left, top, right - left, bottom - top);
            }
        };
        place(self.title, self.layout.title);
        for (index, section) in self.layout.sections.iter().enumerate() {
            if let Some(rect) = section.title {
                place(self.section_titles[index], rect);
            }
            if let Some(rect) = section.footer {
                place(self.footers[index], rect);
            }
            for card in &section.cards {
                let row = &self.rows[index][card.row];
                place(row.label, card.label);
                place(row.reset, card.reset);
                let mut control = card.control;
                if matches!(
                    row.row.control,
                    Control::Choice(_) | Control::Stepper(_) | Control::Seconds(_)
                ) {
                    // 一覧の高さは開いたときの高さ
                    control.height = size::DROPDOWN_HEIGHT;
                }
                place(row.control, control);
                for (part, rect) in row.parts.iter().zip(&card.parts) {
                    place(Some(*part), *rect);
                }
                if let (Some(list), Some(columns)) = (row.control, row.columns()) {
                    // 列の幅は表の幅を等しく分ける(縦の送りの分を残す)
                    let columns = columns.max(1);
                    let width = ffi::scale(card.control.width, dpi)
                        - ffi::scrollbar_width(dpi)
                        - theme.px(size::CONTROL_GAP);
                    for column in 0..columns {
                        ffi::list_set_column_width(list, column, (width / columns as i32).max(0));
                    }
                }
                for (position, rect) in &card.descriptions {
                    place(self.rows[index][*position].label, *rect);
                }
            }
        }
        ffi::scale(self.layout.height, dpi)
    }

    /// カードの地を描く
    pub fn paint(&self, canvas: Canvas, theme: &Theme, scroll: i32) {
        let radius = theme.px(size::CARD_RADIUS);
        for section in &self.layout.sections {
            for card in &section.cards {
                let rect = ffi::scaled_rect(card.card, theme.dpi, scroll);
                canvas.round_rect(
                    rect,
                    radius,
                    theme.palette.card,
                    Some(theme.palette.card_stroke),
                );
            }
        }
    }

    /// STATIC がカードの上にあるか(地の色を決める)．説明か統計の値なら薄い文字にする
    pub fn static_style(&self, window: Window) -> Option<(bool, bool)> {
        if self.title == Some(window) || self.section_titles.contains(&Some(window)) {
            return Some((false, false));
        }
        if self.footers.contains(&Some(window)) {
            return Some((false, true));
        }
        self.rows.iter().flatten().find_map(|row| {
            if row.label == Some(window) {
                Some((true, row.row.control == Control::Note))
            } else if row.control == Some(window) {
                Some((
                    true,
                    matches!(
                        row.row.control,
                        Control::Stat(_) | Control::Version | Control::Info(_)
                    ),
                ))
            } else {
                None
            }
        })
    }

    /// 部品からの WM_COMMAND を頼みにする
    pub fn command(&self, window: Window, notification: u32) -> Option<Event> {
        let row = self.rows.iter().flatten().find(|row| {
            row.control == Some(window) || row.reset == Some(window) || row.parts.contains(&window)
        })?;
        if row.row.control == Control::Preset {
            let button = *row.parts.first()?;
            if window != button || notification != BN_CLICKED {
                return None;
            }
            let (preset, _) = keys::PRESETS.get(selected(row.control?)?)?;
            return Some(Event::LoadPreset(preset));
        }
        if row.row.control == Control::Preview {
            let texts: Vec<String> = row
                .parts
                .iter()
                .map(|part| ffi::window_text(*part))
                .collect();
            return (row.parts.contains(&window) && notification == EN_CHANGE).then(|| {
                Event::Preview {
                    text: texts.first().cloned().unwrap_or_default(),
                    preceding: texts.get(1).cloned().unwrap_or_default(),
                }
            });
        }
        if let (Control::Dictionaries(list, _), Some((fields, update, bottom))) =
            (&row.row.control, row.dictionary_parts())
        {
            if notification != BN_CLICKED {
                return None;
            }
            let index = row
                .control
                .map(ffi::list_selected)
                .and_then(|indices| indices.first().copied());
            let action = if window == update {
                let values = fields
                    .iter()
                    .zip(row.row.control.list_spec()?.fields)
                    .map(|(window, field)| match field.choices {
                        Some(choices) => selected(*window)
                            .and_then(|index| choices.get(index))
                            .map_or_else(String::new, |(value, _)| (*value).to_string()),
                        None => ffi::window_text(*window),
                    })
                    .collect();
                DictionaryAction::Update(values)
            } else {
                let position = bottom.iter().position(|button| *button == window)?;
                DictionaryAction::BOTTOM.get(position)?.clone()
            };
            return Some(Event::DictionaryList {
                list: *list,
                action,
                index,
            });
        }
        if let Control::SyncFields(_) = row.row.control {
            let indices = row.control.map(ffi::list_selected).unwrap_or_default();
            return (notification == BN_CLICKED
                && Some(window) == row.toggle_button()
                && !indices.is_empty())
            .then_some(Event::SyncToggleFields(indices));
        }
        if let Some((fields, add, remove)) = row.list_parts() {
            let (spec, limit) = row.list_spec()?;
            let values: Vec<String> = spec
                .fields
                .iter()
                .zip(fields)
                .map(|(field, window)| match field.choices {
                    Some(choices) => selected(*window)
                        .and_then(|index| choices.get(index))
                        .map_or_else(String::new, |(value, _)| (*value).to_string()),
                    None => ffi::window_text(*window),
                })
                .collect();
            if fields.contains(&window) && notification == EN_CHANGE {
                ffi::enable(add, spec.is_filled(&values));
                return None;
            }
            let dictionary = matches!(row.row.control, Control::Dictionary(_));
            if let Control::Symbols(kind, _) = row.row.control {
                let indices = || row.control.map(ffi::list_selected).unwrap_or_default();
                return match notification {
                    BN_CLICKED if window == add && spec.is_filled(&values) => {
                        Some(Event::SymbolSave {
                            kind,
                            item: spec.make(&values),
                        })
                    }
                    BN_CLICKED if window == remove => {
                        let indices = indices();
                        (!indices.is_empty()).then_some(Event::SymbolRemove { kind, indices })
                    }
                    BN_CLICKED if Some(window) == row.toggle_button() => {
                        let indices = indices();
                        (!indices.is_empty()).then_some(Event::SymbolToggle { kind, indices })
                    }
                    _ => None,
                };
            }
            if window == add && notification == BN_CLICKED && spec.is_filled(&values) && dictionary
            {
                return Some(Event::DictionaryAdd(spec.make(&values)));
            }
            if window == add && notification == BN_CLICKED && spec.is_filled(&values) {
                return Some(Event::ListAdd {
                    spec: *spec,
                    limit,
                    item: spec.make(&values),
                });
            }
            if window == remove && notification == BN_CLICKED {
                let indices = ffi::list_selected(row.control?);
                if dictionary {
                    return (!indices.is_empty()).then_some(Event::DictionaryRemove(indices));
                }
                return (!indices.is_empty()).then_some(Event::ListRemove {
                    spec: *spec,
                    indices,
                });
            }
            return None;
        }
        if row.reset == Some(window) {
            return (notification == BN_CLICKED).then_some(Event::Reset(row.row.path));
        }
        let value = match (&row.row.control, notification) {
            (Control::Toggle, BN_CLICKED) => Value::Bool(ffi::send(window, BM_GETCHECK, 0, 0) == 1),
            (Control::Choice(choices), CBN_SELCHANGE) => {
                let (value, _) = choices.get(selected(window)?)?;
                Value::String((*value).to_string())
            }
            (Control::Stepper(_) | Control::Seconds(_), CBN_SELCHANGE) => {
                crate::model::number(*row.numbers.get(selected(window)?)?)
            }
            (Control::Action(action), BN_CLICKED) => return Some(Event::Action(*action)),
            _ => return None,
        };
        Some(Event::Set {
            path: row.row.path,
            value,
            clears: row.row.clears,
        })
    }

    /// 一覧からの WM_NOTIFY．空のときの文を返し，行を選んだら削除のボタンを使えるようにする．扱ったら true
    pub fn notify(&self, window: Window, code: u32, lparam: LPARAM) -> bool {
        let Some(row) = self
            .rows
            .iter()
            .flatten()
            .find(|row| row.control == Some(window))
        else {
            return false;
        };
        let Some((spec, _)) = row.list_spec() else {
            return false;
        };
        match code {
            LVN_GETEMPTYMARKUP => {
                ffi::set_empty_markup(lparam, spec.empty);
                true
            }
            LVN_ITEMCHANGED => {
                let selected = !ffi::list_selected(window).is_empty();
                if let Some((fields, update, bottom)) = row.dictionary_parts() {
                    ffi::enable(update, selected);
                    for button in bottom.iter().skip(1) {
                        ffi::enable(*button, selected);
                    }
                    // 選んだ辞書の名前などを入力欄に出す(書き換えて「更新」を押す)
                    let chosen = ffi::list_selected(window)
                        .first()
                        .and_then(|index| row.dictionary_inputs.get(*index));
                    if let (Some(values), Some(spec)) = (chosen, row.row.control.list_spec()) {
                        for ((window, field), value) in fields.iter().zip(spec.fields).zip(values) {
                            match field.choices {
                                Some(choices) => {
                                    ffi::send(
                                        *window,
                                        CB_SETCURSEL,
                                        options::index_of(choices, value),
                                        0,
                                    );
                                }
                                None => ffi::set_text(*window, value),
                            }
                        }
                    }
                }
                if let Some((_, _, remove)) = row.list_parts() {
                    ffi::enable(remove, selected);
                }
                if let Some(toggle) = row.toggle_button() {
                    ffi::enable(toggle, selected);
                }
                false
            }
            _ => false,
        }
    }

    /// 試した結果を出す
    pub fn show_preview(&self, text: &str) {
        for row in self.rows.iter().flatten() {
            if let (Control::Preview, Some(result)) = (&row.row.control, row.control) {
                ffi::set_text(result, text);
            }
        }
    }

    /// 足し終えた記号の一覧の入力欄を空にする
    pub fn clear_symbol_inputs(&self) {
        for row in self.rows.iter().flatten() {
            if let (Control::Symbols(..), Some((fields, add, _))) =
                (&row.row.control, row.list_parts())
            {
                for window in fields {
                    ffi::set_text(*window, "");
                }
                ffi::enable(add, false);
            }
        }
    }

    /// 足し終えた一覧の入力欄を空にする
    pub fn clear_list_inputs(&self, path: &str) {
        for row in self
            .rows
            .iter()
            .flatten()
            .filter(|row| row.row.path == path)
        {
            if let (Some((fields, add, _)), Some((spec, _))) = (row.list_parts(), row.list_spec()) {
                for (field, window) in spec.fields.iter().zip(fields) {
                    if field.choices.is_none() {
                        ffi::set_text(*window, "");
                    }
                }
                ffi::enable(
                    add,
                    !spec.fields.iter().any(|field| field.choices.is_none()),
                );
            }
        }
    }

    /// 自分で描く部品(オン・オフと既定に戻す)を描く．描いたら true
    pub fn draw(&self, target: &DrawTarget, theme: &Theme) -> bool {
        let Some(row) = self
            .rows
            .iter()
            .flatten()
            .find(|row| row.control == Some(target.window) || row.reset == Some(target.window))
        else {
            return false;
        };
        let canvas = Canvas::of(target);
        let palette = &theme.palette;
        canvas.fill(target.rect, palette.card);
        if row.reset == Some(target.window) {
            draw_reset(&canvas, target, theme);
            return true;
        }
        if row.row.control != Control::Toggle {
            return false;
        }
        let on = ffi::send(target.window, BM_GETCHECK, 0, 0) == 1;
        let (left, top, right, bottom) = target.rect;
        let switch_width = theme.px(size::SWITCH_WIDTH);
        let switch_height = theme.px(size::SWITCH_HEIGHT);
        let switch_left = right - switch_width - 1;
        let switch_top = top + (bottom - top - switch_height) / 2;
        let switch = (
            switch_left,
            switch_top,
            switch_left + switch_width,
            switch_top + switch_height,
        );
        let (fill, stroke, knob) = match (on, target.disabled) {
            (true, false) => (palette.accent, palette.accent, palette.accent_text),
            (true, true) => (palette.switch_off, palette.switch_off, palette.card),
            (false, _) => (palette.card, palette.switch_off, palette.switch_off),
        };
        canvas.round_rect(switch, switch_height / 2, fill, Some(stroke));
        let inset = theme.px(size::SWITCH_HEIGHT / 5.0);
        let knob_size = switch_height - inset * 2;
        let knob_left = if on {
            switch.2 - inset - knob_size
        } else {
            switch.0 + inset
        };
        canvas.round_rect(
            (
                knob_left,
                switch.1 + inset,
                knob_left + knob_size,
                switch.1 + inset + knob_size,
            ),
            knob_size / 2,
            knob,
            None,
        );
        let color = if target.disabled {
            palette.text_secondary
        } else {
            palette.text
        };
        let gap = theme.px(size::CONTROL_GAP) + theme.px(size::CONTROL_GAP);
        canvas.text(
            (left, top, switch_left - gap, bottom),
            if on { text::ON } else { text::OFF },
            &theme.fonts.body,
            color,
            DT_RIGHT | DT_VCENTER | DT_SINGLELINE,
        );
        if target.focused {
            let outer = theme.px(2.0);
            canvas.frame(
                (
                    switch.0 - outer,
                    switch.1 - outer,
                    switch.2 + outer,
                    switch.3 + outer,
                ),
                palette.text,
            );
        }
        true
    }
}

fn draw_reset(canvas: &Canvas, target: &DrawTarget, theme: &Theme) {
    let palette = &theme.palette;
    if target.hot || target.pressed {
        canvas.round_rect(
            target.rect,
            theme.px(size::CARD_RADIUS),
            palette.nav_selected,
            None,
        );
    }
    let color = if target.disabled {
        palette.text_secondary
    } else {
        palette.accent
    };
    match &theme.fonts.icon {
        // Undo の絵
        Some(icon) => canvas.text(
            target.rect,
            "\u{E7A7}",
            icon,
            color,
            windows::Win32::Graphics::Gdi::DT_CENTER | DT_VCENTER | DT_SINGLELINE,
        ),
        None => canvas.text(
            target.rect,
            "↺",
            &theme.fonts.body,
            color,
            windows::Win32::Graphics::Gdi::DT_CENTER | DT_VCENTER | DT_SINGLELINE,
        ),
    }
    if target.focused {
        canvas.frame(target.rect, palette.text);
    }
}

fn label(host: Window, text: &str, font: &ffi::Font, id: u16) -> Option<Window> {
    let window = ffi::create(
        WINDOW_EX_STYLE::default(),
        w!("STATIC"),
        text,
        WS_CHILD | WS_VISIBLE | WINDOW_STYLE(SS_NOPREFIX.0),
        (0, 0, 0, 0),
        Some(host),
        id,
    )?;
    ffi::set_font(window, font);
    Some(window)
}

fn create_row(
    host: Window,
    theme: &Theme,
    row: &Row,
    catalog: &Catalog,
    next_id: &mut impl FnMut() -> u16,
) -> RowView {
    let fonts = &theme.fonts;
    let mut view = RowView {
        row: row.clone(),
        label: None,
        control: None,
        reset: None,
        numbers: Vec::new(),
        parts: Vec::new(),
        visible: true,
        dictionary_inputs: Vec::new(),
    };
    match &row.control {
        Control::Note => {
            view.label = label(host, row.title, &fonts.caption, next_id());
            return view;
        }
        control if control.list_buttons().is_some() => {
            create_list(host, theme, control, &mut view, next_id);
            return view;
        }
        Control::Preview => {
            create_preview(host, theme, &mut view, next_id);
            return view;
        }
        Control::Action(_) => {}
        _ => {
            let style = WS_CHILD | WS_VISIBLE | WINDOW_STYLE(SS_NOPREFIX.0 | SS_ENDELLIPSIS.0);
            view.label = ffi::create(
                WINDOW_EX_STYLE::default(),
                w!("STATIC"),
                row.title,
                style,
                (0, 0, 0, 0),
                Some(host),
                next_id(),
            );
            if let Some(label) = view.label {
                ffi::set_font(label, &fonts.body);
            }
        }
    }
    let combo_style =
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_VSCROLL | WINDOW_STYLE(CBS_DROPDOWNLIST as u32);
    let (class, title, style) = match &row.control {
        // 名前は読み上げのために項目の名前にする(画面には自分で「オン」「オフ」を描く)
        Control::Toggle => (
            w!("BUTTON"),
            row.title,
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(BS_AUTOCHECKBOX as u32),
        ),
        Control::Choice(_) | Control::Stepper(_) | Control::Seconds(_) => {
            (w!("COMBOBOX"), "", combo_style)
        }
        Control::Action(_) => (
            w!("BUTTON"),
            row.title,
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(BS_PUSHBUTTON as u32),
        ),
        Control::Stat(_) | Control::Info(_) => (
            w!("STATIC"),
            "",
            WS_CHILD | WS_VISIBLE | WINDOW_STYLE(SS_NOPREFIX.0 | SS_RIGHT.0),
        ),
        Control::Preset => (
            w!("COMBOBOX"),
            "",
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_VSCROLL | WINDOW_STYLE(CBS_DROPDOWNLIST as u32),
        ),
        Control::Version => (
            w!("STATIC"),
            "",
            WS_CHILD | WS_VISIBLE | WINDOW_STYLE(SS_NOPREFIX.0 | SS_RIGHT.0),
        ),
        Control::Notices => {
            view.label = None;
            view.control = create_notices(host, theme, next_id());
            return view;
        }
        Control::KeymapReport => {
            view.label = None;
            view.control = create_read_only(host, theme, "", next_id());
            return view;
        }
        Control::Note
        | Control::List(..)
        | Control::Preview
        | Control::Dictionary(_)
        | Control::Symbols(..)
        | Control::SyncFields(_)
        | Control::Dictionaries(..) => return view,
    };
    view.control = ffi::create(
        WINDOW_EX_STYLE::default(),
        class,
        title,
        style,
        (0, 0, 0, 0),
        Some(host),
        next_id(),
    );
    let Some(control) = view.control else {
        return view;
    };
    ffi::set_font(control, &fonts.body);
    match &row.control {
        Control::Choice(choices) => {
            for (_, name) in choices.iter() {
                ffi::send_text(control, CB_ADDSTRING, 0, name);
            }
        }
        Control::Preset => {
            for (_, name) in keys::PRESETS {
                ffi::send_text(control, CB_ADDSTRING, 0, name);
            }
            ffi::send(control, CB_SETCURSEL, 0, 0);
            ffi::set_theme(control, theme.control_theme(true));
            if let Some(button) = ffi::create(
                WINDOW_EX_STYLE::default(),
                w!("BUTTON"),
                keys::LOAD,
                WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(BS_PUSHBUTTON as u32),
                (0, 0, 0, 0),
                Some(host),
                next_id(),
            ) {
                ffi::set_font(button, &fonts.body);
                ffi::set_theme(button, theme.control_theme(false));
                view.parts.push(button);
            }
        }
        Control::Stepper(range) => {
            view.numbers = options::steps(range.range(catalog), 1.0);
            for number in &view.numbers {
                ffi::send_text(control, CB_ADDSTRING, 0, &format!("{number}"));
            }
        }
        Control::Seconds(range) => {
            view.numbers = options::steps(range.range(catalog), catalog.seconds_step);
            for number in &view.numbers {
                ffi::send_text(control, CB_ADDSTRING, 0, &more::seconds(*number));
            }
        }
        _ => {}
    }
    if matches!(
        row.control,
        Control::Choice(_) | Control::Stepper(_) | Control::Seconds(_)
    ) {
        let field = theme.px(size::CONTROL_HEIGHT) - theme.px(size::CONTROL_GAP);
        ffi::send(control, CB_SETITEMHEIGHT, usize::MAX, field as isize);
        ffi::set_theme(control, theme.control_theme(true));
    }
    if let Control::Action(_) = row.control {
        ffi::set_theme(control, theme.control_theme(false));
    }
    if row.has_value() {
        view.reset = ffi::create(
            WINDOW_EX_STYLE::default(),
            w!("BUTTON"),
            crate::strings::features::RESTORE_DEFAULT,
            WS_CHILD | WS_TABSTOP | WINDOW_STYLE(BS_PUSHBUTTON as u32),
            (0, 0, 0, 0),
            Some(host),
            next_id(),
        );
    }
    view
}

/// 一覧の部品を作る．入力欄は案内の文字(cue banner)に欄の名前を出す
/// 一覧の入力欄・ボタン・表を作る．buttons は入力欄の後ろに並べるボタン，more_columns は入力欄の列の後ろに足す表の列
fn create_list(
    host: Window,
    theme: &Theme,
    control: &Control,
    view: &mut RowView,
    next_id: &mut impl FnMut() -> u16,
) {
    let (Some(spec), Some(buttons)) = (control.list_spec(), control.list_buttons()) else {
        return;
    };
    let fonts = &theme.fonts;
    let labels = control.table_columns();
    for field in spec.fields {
        let window = match field.choices {
            None => create_edit(host, theme, field.label, next_id()),
            Some(choices) => {
                let combo = ffi::create(
                    WINDOW_EX_STYLE::default(),
                    w!("COMBOBOX"),
                    "",
                    WS_CHILD
                        | WS_VISIBLE
                        | WS_TABSTOP
                        | WS_VSCROLL
                        | WINDOW_STYLE(CBS_DROPDOWNLIST as u32),
                    (0, 0, 0, 0),
                    Some(host),
                    next_id(),
                );
                if let Some(combo) = combo {
                    ffi::set_font(combo, &fonts.body);
                    for (_, name) in choices {
                        ffi::send_text(combo, CB_ADDSTRING, 0, name);
                    }
                    ffi::send(combo, CB_SETCURSEL, 0, 0);
                    ffi::set_theme(combo, theme.control_theme(true));
                }
                combo
            }
        };
        view.parts.extend(window);
    }
    // 入力欄の右のボタンと表の下のボタン(配置の parts と同じ並び)．取り込むボタンだけは選ばなくても使える
    for (index, title) in buttons.top.iter().chain(buttons.bottom).enumerate() {
        let enabled = matches!(control, Control::Dictionaries(..)) && index == buttons.top.len();
        if let Some(button) = ffi::create(
            WINDOW_EX_STYLE::default(),
            w!("BUTTON"),
            title,
            WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(BS_PUSHBUTTON as u32),
            (0, 0, 0, 0),
            Some(host),
            next_id(),
        ) {
            ffi::set_font(button, &fonts.body);
            ffi::set_theme(button, theme.control_theme(false));
            ffi::enable(button, enabled);
            view.parts.push(button);
        }
    }
    view.control = ffi::create(
        WS_EX_CLIENTEDGE,
        WC_LISTVIEW,
        "",
        WS_CHILD
            | WS_VISIBLE
            | WS_TABSTOP
            | WINDOW_STYLE(LVS_REPORT | LVS_SHOWSELALWAYS | LVS_NOSORTHEADER),
        (0, 0, 0, 0),
        Some(host),
        next_id(),
    );
    if let Some(list) = view.control {
        ffi::set_font(list, &fonts.body);
        ffi::list_set_columns(list, &labels, &vec![0; labels.len()]);
        apply_list_theme(list, theme);
    }
}

/// 謝辞の欄．配布物の THIRD_PARTY_NOTICES.md(実行ファイルと同じディレクトリ)を読むだけの欄に出す
fn create_notices(host: Window, theme: &Theme, id: u16) -> Option<Window> {
    let text = std::env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(|dir| dir.join(NOTICES_FILE)))
        .and_then(|path| std::fs::read_to_string(path).ok())
        // EDIT の改行は CR LF
        .map(|text| text.replace("\r\n", "\n").replace('\n', "\r\n"))
        .unwrap_or_else(|| more::NOTICES_MISSING.to_string());
    create_read_only(host, theme, &text, id)
}

/// 読むだけの複数行の欄
fn create_read_only(host: Window, theme: &Theme, text: &str, id: u16) -> Option<Window> {
    let field = ffi::create(
        WS_EX_CLIENTEDGE,
        w!("EDIT"),
        text,
        WS_CHILD
            | WS_VISIBLE
            | WS_TABSTOP
            | WS_VSCROLL
            | WINDOW_STYLE((ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL) as u32),
        (0, 0, 0, 0),
        Some(host),
        id,
    )?;
    ffi::set_font(field, &theme.fonts.caption);
    ffi::set_theme(field, theme.control_theme(true));
    Some(field)
}

/// 配布物に入れる利用表記のファイルの名前(tools/windows/stage.ps1)
const NOTICES_FILE: &str = "THIRD_PARTY_NOTICES.md";

/// 打つ欄．案内の文字(cue banner)に欄の名前を出す
fn create_edit(host: Window, theme: &Theme, label: &str, id: u16) -> Option<Window> {
    let field = ffi::create(
        WS_EX_CLIENTEDGE,
        w!("EDIT"),
        "",
        WS_CHILD | WS_VISIBLE | WS_TABSTOP | WINDOW_STYLE(ES_AUTOHSCROLL as u32),
        (0, 0, 0, 0),
        Some(host),
        id,
    )?;
    ffi::set_font(field, &theme.fonts.body);
    ffi::send_text(field, EM_SETCUEBANNER, 1, label);
    ffi::set_theme(field, theme.control_theme(true));
    Some(field)
}

/// 試す欄の部品(打つ文・前の文字列・結果)
fn create_preview(
    host: Window,
    theme: &Theme,
    view: &mut RowView,
    next_id: &mut impl FnMut() -> u16,
) {
    for label in [features::TRY_PLACEHOLDER, features::TRY_PRECEDING] {
        view.parts
            .extend(create_edit(host, theme, label, next_id()));
    }
    view.control = ffi::create(
        WINDOW_EX_STYLE::default(),
        w!("STATIC"),
        "",
        WS_CHILD | WS_VISIBLE | WINDOW_STYLE(SS_NOPREFIX.0),
        (0, 0, 0, 0),
        Some(host),
        next_id(),
    );
    if let Some(result) = view.control {
        ffi::set_font(result, &theme.fonts.body);
    }
}

fn apply_list_theme(list: Window, theme: &Theme) {
    ffi::set_theme(list, theme.control_theme(false));
    ffi::list_set_colors(list, theme.palette.text, theme.palette.control);
}

fn selected(combo: Window) -> Option<usize> {
    usize::try_from(ffi::send(combo, CB_GETCURSEL, 0, 0)).ok()
}

fn show_value(control: Window, row: &Row, numbers: &[f64], values: &impl Values, extras: &Extras) {
    match &row.control {
        Control::Toggle => {
            ffi::send(control, BM_SETCHECK, usize::from(values.on(row.path)), 0);
            ffi::invalidate(control);
        }
        Control::Choice(choices) => {
            let index = options::index_of(choices, &values.text(row.path));
            ffi::send(control, CB_SETCURSEL, index, 0);
        }
        Control::Stepper(_) | Control::Seconds(_) => {
            let value = values
                .value(row.path)
                .and_then(Value::as_f64)
                .unwrap_or(0.0);
            ffi::send(control, CB_SETCURSEL, options::nearest(numbers, value), 0);
        }
        Control::Stat(stat) => ffi::set_text(control, &extras.usage.text(*stat)),
        Control::Dictionary(_) => ffi::list_set_rows(control, &extras.dictionary),
        Control::Symbols(kind, _) => ffi::list_set_rows(control, extras.symbol_rows(*kind)),
        Control::SyncFields(_) => ffi::list_set_rows(control, &extras.sync_fields),
        Control::Dictionaries(list, _) => {
            let entries = crate::dictionaries::entries(*list, values.value(list.path()));
            ffi::list_set_rows(control, &crate::dictionaries::table(*list, &entries));
        }
        Control::Info(Info::SyncFolder) => ffi::set_text(control, &extras.sync_folder),
        Control::Info(Info::LastSynced) => ffi::set_text(control, &extras.last_synced),
        Control::List(spec, _) => {
            let rows: Vec<Vec<String>> = spec
                .items(values.value(spec.path))
                .into_iter()
                .map(|item| spec.display(&item))
                .collect();
            ffi::list_set_rows(control, &rows);
        }
        Control::Version => ffi::set_text(
            control,
            &crate::strings::windows::version(env!("CARGO_PKG_VERSION")),
        ),
        Control::KeymapReport => {
            ffi::set_text(control, &extras.keymap_report.replace('\n', "\r\n"))
        }
        Control::Action(_)
        | Control::Note
        | Control::Preview
        | Control::Preset
        | Control::Notices => {}
    }
}
