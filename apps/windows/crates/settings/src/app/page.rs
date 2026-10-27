#![forbid(unsafe_code)]

//! 1 ページ分の部品．項目の並び(pages::Section)から部品の状態を作り，値を映し，押された部品を頼み(Event)にする．
//! 部品は子の窓にせず，状態だけを持って Direct2D で描く(ページを開くたびに窓を作り直さない)．
//! 文字を打つ欄だけは標準の EDIT にする(IME・クリップボード・読み上げのため)

use super::ffi::{self, edit, Window};
use super::paint::{self, Canvas, State, TextLayout, TextStyle};
use super::theme::{Color, Theme};
use crate::catalog::Catalog;
use crate::layout::{self, PageLayout, Rect};
use crate::list::{Item, ListSpec};
use crate::model::SettingsModel;
use crate::options;
use crate::pages::{self, Action, Control, DictionaryList, Info, LimitKind, Page, Row, Section};
use crate::store::SettingsStore;
use crate::strings::{features, keys, more, rule_list, settings, windows as text};
use crate::ui::anim::{Easing, Tween};
use crate::ui::scroll::Scroller;
use crate::ui::table::{Move, Table};
use crate::usage::Usage;
use ipc::SymbolKind;
use serde_json::Value;
use std::collections::HashMap;
use tokens::motion::settings_windows as motion;
use tokens::size::settings_windows as size;

/// 部品の番号の始まり(0 は使わない．窓の部品の番号と分ける)
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
    /// 一覧に行を足す．replacing は書き換える行(表の行の番号)
    ListAdd {
        spec: ListSpec,
        limit: LimitKind,
        item: Item,
        replacing: Option<usize>,
    },
    ListRemove {
        spec: ListSpec,
        indices: Vec<usize>,
    },
    /// 単語を登録する(読み・単語)．replacing は書き換える単語(表の行の番号)
    DictionaryAdd {
        item: Item,
        replacing: Option<usize>,
    },
    /// 選んだ単語を消す(表の行の番号)
    DictionaryRemove(Vec<usize>),
    /// 記号の決まりを重ねる(入力・記号)．replacing は書き換える決まり(表の行の番号)
    SymbolSave {
        kind: SymbolKind,
        item: Item,
        replacing: Option<usize>,
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
    /// カスタムテーマの一覧の操作(index は選んだ行，name はそのテーマの名前)
    ThemeList {
        action: ThemeAction,
        index: Option<usize>,
        name: String,
    },
    /// カスタムテーマの一覧で行を選んだ(選んでいなければ None)
    ThemeSelected(Option<usize>),
    /// アプリの実行ファイルを選ぶ窓を出し，path の一覧の入力欄に名前を入れる
    ChooseApp {
        path: &'static str,
    },
    /// 色を選ぶ窓を出す(path の値を変える．current は今の色)
    ChooseColor {
        path: &'static str,
        current: String,
    },
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

/// カスタムテーマの一覧のボタンの操作
#[derive(Debug, Clone, PartialEq)]
pub enum ThemeAction {
    /// 入力欄の名前に変える
    Rename(String),
    /// 今のテーマを写して新しく作る
    Create,
    /// 今使っているテーマを複製する
    DuplicateCurrent,
    Use,
    Duplicate,
    Delete,
}

impl ThemeAction {
    /// 表の下のボタンの並び(pages::Control::list_buttons と同じ)
    const BOTTOM: [ThemeAction; 5] = [
        ThemeAction::Create,
        ThemeAction::DuplicateCurrent,
        ThemeAction::Use,
        ThemeAction::Duplicate,
        ThemeAction::Delete,
    ];
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

/// 表の下のボタンのうち，行を選ばなくても使えるもの(キーの記録・アプリの追加)
fn bottom_always_enabled(control: &Control, index: usize) -> bool {
    match control {
        Control::List(spec, _) => !(spec.path == "keymap" && index == 1),
        _ => false,
    }
}

/// 表の下のボタンのうち，行を選ばなくても使える先頭のボタンの数(作る・取り込む)
fn always_enabled(control: &Control) -> usize {
    match control {
        Control::CustomThemes(_) => 2,
        Control::Dictionaries(..) => 1,
        _ => 0,
    }
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

/// 設定のファイルの項目でない値の道筋か(同期の状態「sync.」と，編集しているカスタムテーマ「customTheme.」)
pub fn is_extra_path(path: &str) -> bool {
    crate::sync::is_sync_path(path) || crate::themes::is_theme_path(path)
}

/// 設定の値に，同期の状態と編集しているカスタムテーマの値(is_extra_path の道筋)を重ねたもの
pub struct WithExtras<'a, V: Values> {
    pub values: &'a V,
    pub extra: &'a crate::store::Fields,
}

impl<V: Values> Values for WithExtras<'_, V> {
    fn value(&self, path: &str) -> Option<&Value> {
        if is_extra_path(path) {
            return self.extra.get(path);
        }
        self.values.value(path)
    }

    /// 重ねた値には既定に戻すボタンを出さない
    fn is_default(&self, path: &str) -> bool {
        is_extra_path(path) || self.values.is_default(path)
    }

    /// 重ねた値は読めたときだけ使える
    fn is_readable(&self, path: &str) -> bool {
        if is_extra_path(path) {
            return self.extra.contains_key(path);
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
    /// 同期の状態と編集しているカスタムテーマの値(is_extra_path の道筋)
    pub extra: crate::store::Fields,
    /// カスタムテーマの読みにくい組み合わせの知らせ(無ければ空)
    pub theme_report: String,
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

/// 行の中の押せる部品
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Part {
    /// 既定に戻すボタン
    Reset,
    Toggle,
    /// 値を選ぶドロップダウン(選択肢・数・秒・ひな形)
    Dropdown,
    /// 操作のボタン
    Action,
    /// 色のボタン
    Color,
    /// ひな形を読み込むボタン
    PresetLoad,
    /// 一覧の入力欄(打つ欄か選ぶ欄)
    Field(usize),
    /// 入力欄の右のボタン(追加・削除・切り替え・更新)
    Top(usize),
    /// 表の下の検索欄
    Search,
    /// 表の下のボタン
    Bottom(usize),
    Table,
    /// 試す欄(打つ文・前の文字列)
    PreviewField(usize),
    /// 読むだけの長い文(送れる)
    Text,
}

/// ページの中の部品(行の番号と部品)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Element {
    pub row: usize,
    pub part: Part,
}

/// 読み上げに見せる部品の種類
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Described {
    Button,
    Toggle(bool),
    /// 選んでいる選択肢の名前
    Dropdown(String),
    Table,
    Text,
    /// 標準の EDIT(自分で読ませる)
    Edit,
}

/// 一覧の入力欄
#[derive(Debug)]
enum Input {
    /// 打つ欄(標準の EDIT)
    Edit(Window),
    /// 選ぶ欄(選んでいる選択肢の番号)
    Choice(usize),
}

struct RowState {
    row: Row,
    section: usize,
    /// 部品を置いたカード(出さない行は None)
    card: Option<layout::CardLayout>,
    visible: bool,
    enabled: bool,
    readable: bool,
    /// 既定に戻すボタンを出す
    resettable: bool,
    on: bool,
    /// トグルのつまみの位置(0 はオフ，1 はオン)
    knob: Tween,
    /// ドロップダウンで選んでいる番号
    choice: Option<usize>,
    /// 数を選ぶ部品の選択肢
    numbers: Vec<f64>,
    /// 統計・情報・バージョン・知らせの文
    text: String,
    /// 色のボタンに出す色(「#RRGGBB」)
    color: String,
    /// 一覧の表
    table: Table,
    table_scroll: Scroller,
    /// 一覧の入力欄(list_spec の欄と同じ並び)
    inputs: Vec<Input>,
    /// 表の下の検索欄
    search: Option<Window>,
    /// 一覧で選んで書き換えている行(rows の番号)．追加のボタンは「更新」になり，この行を置き換える
    editing: Option<usize>,
    /// 辞書・カスタムテーマの一覧の行ごとの入力欄の値(行を選んだら入力欄に出す)
    dictionary_inputs: Vec<Vec<String>>,
    /// 試す欄(打つ文・前の文字列)と結果
    preview_fields: Vec<Window>,
    preview_result: String,
    /// 長い文の送り
    text_scroll: Scroller,
}

impl RowState {
    fn new(row: &Row, section: usize, catalog: &Catalog) -> Self {
        let numbers = match &row.control {
            Control::Stepper(range) => options::steps(range.range(catalog), 1.0),
            Control::Seconds(range) => options::steps(range.range(catalog), catalog.seconds_step),
            _ => Vec::new(),
        };
        let text = match &row.control {
            Control::Notices => notices(),
            Control::Version => text::version(env!("CARGO_PKG_VERSION")),
            _ => String::new(),
        };
        Self {
            row: row.clone(),
            section,
            card: None,
            visible: true,
            enabled: true,
            readable: true,
            resettable: false,
            on: false,
            knob: Tween::fixed(0.0),
            choice: matches!(row.control, Control::Preset).then_some(0),
            numbers,
            text,
            color: String::new(),
            table: Table::default(),
            table_scroll: Scroller::default(),
            inputs: Vec::new(),
            search: None,
            editing: None,
            dictionary_inputs: Vec::new(),
            preview_fields: Vec::new(),
            preview_result: String::new(),
            text_scroll: Scroller::default(),
        }
    }

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

    /// 入力欄・追加・削除のある一覧か(項目ごとの同期・辞書の一覧・カスタムテーマの一覧は違う)
    fn has_add_remove(&self) -> bool {
        self.list_spec().is_some()
            && !matches!(
                self.row.control,
                Control::SyncFields(_) | Control::Dictionaries(..) | Control::CustomThemes(_)
            )
    }

    /// 辞書・カスタムテーマの一覧か(入力欄・更新・表の下のボタン)
    fn is_dictionary_list(&self) -> bool {
        matches!(
            self.row.control,
            Control::Dictionaries(..) | Control::CustomThemes(_)
        )
    }

    /// 選んだ行を切り替えるボタン(記号の有効と無効，項目ごとの同期の範囲)
    fn toggle_part(&self) -> Option<Part> {
        match self.row.control {
            Control::Symbols(..) => Some(Part::Top(2)),
            Control::SyncFields(_) => Some(Part::Top(0)),
            _ => None,
        }
    }

    /// 入力欄の値(選ぶ欄は設定のファイルに書く値)
    fn input_values(&self) -> Vec<String> {
        let Some(spec) = self.row.control.list_spec() else {
            return Vec::new();
        };
        spec.fields
            .iter()
            .zip(&self.inputs)
            .map(|(field, input)| match (input, field.choices) {
                (Input::Choice(index), Some(choices)) => choices
                    .get(*index)
                    .map_or_else(String::new, |(value, _)| (*value).to_string()),
                (Input::Edit(window), _) => ffi::window_text(*window),
                (Input::Choice(_), None) => String::new(),
            })
            .collect()
    }

    /// 入力欄の選ぶ欄で選んでいる値(注記を入れ替えるため)
    fn chosen_values(&self) -> Vec<String> {
        let Some(spec) = self.row.control.list_spec() else {
            return Vec::new();
        };
        spec.fields
            .iter()
            .zip(&self.inputs)
            .filter_map(|(field, input)| match (input, field.choices) {
                (Input::Choice(index), Some(choices)) => {
                    choices.get(*index).map(|(value, _)| (*value).to_string())
                }
                _ => None,
            })
            .collect()
    }

    /// rows の index の行を入力欄に出す．選ぶ欄は表に出した名前から選ぶ
    fn fill_inputs(&mut self, index: usize) {
        let Some(spec) = self.row.control.list_spec().copied() else {
            return;
        };
        let Some(cells) = self.table.rows().get(index).cloned() else {
            return;
        };
        for ((input, field), cell) in self.inputs.iter_mut().zip(spec.fields).zip(&cells) {
            match (input, field.choices) {
                (Input::Choice(selected), Some(choices)) => {
                    if let Some(position) = choices.iter().position(|(_, label)| label == cell) {
                        *selected = position;
                    }
                }
                (Input::Edit(window), _) => ffi::set_text(*window, cell),
                _ => {}
            }
        }
    }

    /// 辞書・カスタムテーマの一覧で選んだ行の値を入力欄に出す
    fn fill_dictionary_inputs(&mut self, position: usize) {
        let Some(spec) = self.row.control.list_spec().copied() else {
            return;
        };
        let Some(values) = self.dictionary_inputs.get(position).cloned() else {
            return;
        };
        for ((input, field), value) in self.inputs.iter_mut().zip(spec.fields).zip(&values) {
            match (input, field.choices) {
                (Input::Choice(selected), Some(choices)) => {
                    *selected = options::index_of(choices, value);
                }
                (Input::Edit(window), _) => ffi::set_text(*window, value),
                _ => {}
            }
        }
    }

    fn windows(&self) -> impl Iterator<Item = Window> + '_ {
        self.inputs
            .iter()
            .filter_map(|input| match input {
                Input::Edit(window) => Some(*window),
                Input::Choice(_) => None,
            })
            .chain(self.search)
            .chain(self.preview_fields.iter().copied())
    }

    /// 部品の位置(ページの中の座標)
    fn part_rect(&self, part: Part) -> Option<Rect> {
        let card = self.card.as_ref()?;
        let fields = self
            .row
            .control
            .list_spec()
            .map_or(0, |spec| spec.fields.len());
        let buttons = self.row.control.list_buttons();
        let top = buttons.map_or(0, |buttons| buttons.top.len());
        let search = buttons.is_some_and(|buttons| buttons.search);
        match part {
            Part::Reset => Some(card.reset),
            Part::Toggle
            | Part::Dropdown
            | Part::Action
            | Part::Color
            | Part::Table
            | Part::Text => Some(card.control),
            Part::PresetLoad => card.parts.first().copied(),
            Part::Field(index) | Part::PreviewField(index) => card.parts.get(index).copied(),
            Part::Top(index) => card.parts.get(fields + index).copied(),
            Part::Search => search
                .then(|| card.parts.get(fields + top).copied())
                .flatten(),
            Part::Bottom(index) => card
                .parts
                .get(fields + top + usize::from(search) + index)
                .copied(),
        }
    }

    /// 行の押せる部品(フォーカスの順)
    fn parts(&self) -> Vec<Part> {
        let mut parts = Vec::new();
        match &self.row.control {
            Control::Toggle => parts.push(Part::Toggle),
            Control::Choice(_) | Control::Stepper(_) | Control::Seconds(_) => {
                parts.push(Part::Dropdown)
            }
            Control::Action(_) => parts.push(Part::Action),
            Control::Color => parts.push(Part::Color),
            Control::Preset => parts.extend([Part::Dropdown, Part::PresetLoad]),
            Control::Notices | Control::KeymapReport | Control::ThemeReport => {
                parts.push(Part::Text)
            }
            Control::Preview => parts.extend([Part::PreviewField(0), Part::PreviewField(1)]),
            control => {
                if let (Some(spec), Some(buttons)) = (control.list_spec(), control.list_buttons()) {
                    parts.extend((0..spec.fields.len()).map(Part::Field));
                    parts.extend((0..buttons.top.len()).map(Part::Top));
                    parts.push(Part::Table);
                    if buttons.search {
                        parts.push(Part::Search);
                    }
                    parts.extend((0..buttons.bottom.len()).map(Part::Bottom));
                }
            }
        }
        if self.resettable {
            parts.insert(0, Part::Reset);
        }
        parts
    }

    /// 部品を使えるか(選んだ行に効くボタンは，行を選ぶまで使えない)
    fn part_enabled(&self, part: Part) -> bool {
        if !self.enabled {
            return false;
        }
        let selected = !self.table.selected_positions().is_empty();
        let fields = self
            .row
            .control
            .list_spec()
            .map_or(0, |spec| spec.fields.len());
        match part {
            Part::Top(0) if self.has_add_remove() => {
                self.editing.is_some()
                    || self
                        .list_spec()
                        .is_some_and(|(spec, _)| spec.is_filled(&self.input_values()))
            }
            Part::Top(1) if self.has_add_remove() => selected,
            Part::Top(index) if self.toggle_part() == Some(Part::Top(index)) => selected,
            // 辞書・カスタムテーマの一覧の更新
            Part::Top(0) if self.is_dictionary_list() => selected,
            Part::Bottom(index) if self.is_dictionary_list() => {
                index < always_enabled(&self.row.control) || selected
            }
            Part::Bottom(index) => bottom_always_enabled(&self.row.control, index) || selected,
            Part::Field(index) => index < fields,
            _ => true,
        }
    }

    /// ボタンの名前(追加のボタンは書き換えているあいだ「更新」)
    fn button_label(&self, part: Part) -> &'static str {
        let buttons = self.row.control.list_buttons();
        match part {
            Part::Top(0) if self.has_add_remove() && self.editing.is_some() => rule_list::UPDATE,
            Part::Top(index) => buttons
                .and_then(|buttons| buttons.top.get(index).copied())
                .unwrap_or(""),
            Part::Bottom(index) => buttons
                .and_then(|buttons| buttons.bottom.get(index).copied())
                .unwrap_or(""),
            Part::PresetLoad => keys::LOAD,
            Part::Action => self.row.title,
            _ => "",
        }
    }

    /// ドロップダウンの選択肢の名前
    fn dropdown_items(&self, part: Part) -> Vec<String> {
        match (&self.row.control, part) {
            (Control::Choice(choices), Part::Dropdown) => choices
                .iter()
                .map(|(_, name)| (*name).to_string())
                .collect(),
            (Control::Stepper(_), Part::Dropdown) => self
                .numbers
                .iter()
                .map(|number| format!("{number}"))
                .collect(),
            (Control::Seconds(_), Part::Dropdown) => self
                .numbers
                .iter()
                .map(|number| more::seconds(*number))
                .collect(),
            (Control::Preset, Part::Dropdown) => keys::PRESETS
                .iter()
                .map(|(_, name)| (*name).to_string())
                .collect(),
            (control, Part::Field(index)) => control
                .list_spec()
                .and_then(|spec| spec.fields.get(index))
                .and_then(|field| field.choices)
                .map(|choices| {
                    choices
                        .iter()
                        .map(|(_, name)| (*name).to_string())
                        .collect()
                })
                .unwrap_or_default(),
            _ => Vec::new(),
        }
    }

    /// ドロップダウンで選んでいる番号
    fn dropdown_selected(&self, part: Part) -> Option<usize> {
        match part {
            Part::Dropdown => self.choice,
            Part::Field(index) => match self.inputs.get(index) {
                Some(Input::Choice(selected)) => Some(*selected),
                _ => None,
            },
            _ => None,
        }
    }

    /// 部品が選ぶ欄か
    fn is_dropdown(&self, part: Part) -> bool {
        match part {
            Part::Dropdown => true,
            Part::Field(index) => matches!(self.inputs.get(index), Some(Input::Choice(_))),
            _ => false,
        }
    }

    /// 打つ欄の窓
    fn edit(&self, part: Part) -> Option<Window> {
        match part {
            Part::Field(index) => match self.inputs.get(index) {
                Some(Input::Edit(window)) => Some(*window),
                _ => None,
            },
            Part::PreviewField(index) => self.preview_fields.get(index).copied(),
            Part::Search => self.search,
            _ => None,
        }
    }
}

/// 配布物に入れた利用表記のファイルの中身(実行ファイルと同じディレクトリ．tools/windows/stage.ps1)
fn notices() -> String {
    const NOTICES_FILE: &str = "THIRD_PARTY_NOTICES.md";
    std::env::current_exe()
        .ok()
        .and_then(|path| path.parent().map(|dir| dir.join(NOTICES_FILE)))
        .and_then(|path| std::fs::read_to_string(path).ok())
        .map(|text| text.replace("\r\n", "\n"))
        .unwrap_or_else(|| more::NOTICES_MISSING.to_string())
}

/// ページの状態(読み込み中・使える・エンジンにつながらない)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Availability {
    Loading,
    Ready,
    Unavailable,
}

pub struct PageView {
    pub page: Page,
    pub availability: Availability,
    sections: Vec<Section>,
    rows: Vec<RowState>,
    layout: PageLayout,
    /// 節の注記として出している文(注記を入れ替える節がある)
    footers: Vec<Option<&'static str>>,
    /// ポインターを載せている部品と，載せた・外した動き
    hover: HashMap<Element, Tween>,
    /// 表の上でポインターを載せている行(行の番号と表の中の位置)
    table_hover: Option<(usize, usize)>,
    /// 中身の幅(DIP)
    width: f32,
}

/// 描くときに窓から渡すもの
pub struct Frame<'a> {
    pub theme: &'a Theme,
    pub now: f64,
    pub focus: Option<Element>,
    /// フォーカスの印を出す(キーボードで動かしたあと)
    pub focus_visible: bool,
    /// ボタンを押している部品
    pub pressed: Option<Element>,
    /// 開いているドロップダウン
    pub open: Option<Element>,
    /// フォーカスのある打つ欄の窓
    pub focused_edit: Option<Window>,
    /// 標準の EDIT を描けないとき(見本の書き出し)は，欄の文字を自分で描く
    pub draw_fields: bool,
    /// 見えているところ(ページの中の上端と下端)．外の部品は描かない
    pub visible: (f32, f32),
}

impl Frame<'_> {
    fn shows(&self, rect: Rect) -> bool {
        rect.max_y() >= self.visible.0 && rect.y <= self.visible.1
    }
}

impl PageView {
    /// pool は前のページで使った打つ欄(作り直さずに使い回す．作るのは 1 つ数ミリ秒かかる)
    pub fn new(
        parent: Window,
        font: &ffi::Font,
        pool: &mut Vec<Window>,
        page: Page,
        catalog: &Catalog,
        availability: Availability,
    ) -> Self {
        let sections = match availability {
            Availability::Ready => pages::sections(page).unwrap_or_default(),
            Availability::Loading | Availability::Unavailable => Vec::new(),
        };
        let mut id = FIRST_ID;
        let mut next_id = || {
            id = id.wrapping_add(1);
            id
        };
        let mut rows = Vec::new();
        for (index, section) in sections.iter().enumerate() {
            for row in &section.rows {
                let mut state = RowState::new(row, index, catalog);
                let mut fields = FieldSource {
                    parent,
                    font,
                    pool: &mut *pool,
                    next_id: &mut next_id,
                };
                create_inputs(&mut fields, &mut state);
                rows.push(state);
            }
        }
        let footers = sections.iter().map(|section| section.footer).collect();
        Self {
            page,
            availability,
            sections,
            rows,
            layout: PageLayout {
                title: Rect::default(),
                sections: Vec::new(),
                height: 0.0,
            },
            footers,
            hover: HashMap::new(),
            table_hover: None,
            width: 0.0,
        }
    }

    /// 標準の EDIT の窓を隠して pool に返す(次のページで使い回す)
    pub fn release(self, pool: &mut Vec<Window>) {
        for window in self.windows() {
            ffi::show(window, false);
            ffi::set_text(window, "");
            pool.push(window);
        }
    }

    /// 標準の EDIT の窓
    pub fn windows(&self) -> Vec<Window> {
        self.rows.iter().flat_map(RowState::windows).collect()
    }

    /// 値を部品に映し，出す・使える状態を決める
    pub fn sync(&mut self, values: &impl Values, extras: &Extras, now: f64) {
        for row in &mut self.rows {
            let condition = |condition| {
                pages::holds(condition, |path| values.text(path), |path| values.on(path))
            };
            row.visible = row.row.visible.is_none_or(condition)
                && (row.row.control != Control::KeymapReport || !extras.keymap_report.is_empty())
                && (row.row.control != Control::ThemeReport || !extras.theme_report.is_empty());
            row.readable = row.row.path.is_empty() || values.is_readable(row.row.path);
            row.enabled = row.readable && row.row.enabled.is_none_or(condition);
            row.resettable =
                row.row.has_value() && row.readable && !values.is_default(row.row.path);
            match &row.row.control {
                Control::Toggle => {
                    let on = values.on(row.row.path);
                    if on != row.on {
                        row.knob.retarget(
                            if on { 1.0 } else { 0.0 },
                            now,
                            f64::from(motion::TOGGLE),
                            Easing::STANDARD,
                        );
                        row.on = on;
                    }
                }
                Control::Choice(choices) => {
                    row.choice = Some(options::index_of(choices, &values.text(row.row.path)));
                }
                Control::Stepper(_) | Control::Seconds(_) => {
                    let value = values
                        .value(row.row.path)
                        .and_then(Value::as_f64)
                        .unwrap_or(0.0);
                    row.choice = Some(options::nearest(&row.numbers, value));
                }
                Control::Stat(stat) => row.text = extras.usage.text(*stat),
                Control::Info(Info::SyncFolder) => row.text = extras.sync_folder.clone(),
                Control::Info(Info::LastSynced) => row.text = extras.last_synced.clone(),
                Control::KeymapReport => row.text = extras.keymap_report.clone(),
                Control::ThemeReport => row.text = extras.theme_report.clone(),
                Control::Color => row.color = values.text(row.row.path),
                _ => {}
            }
            if let Some(rows) = list_rows(&row.row, values, extras) {
                // 一覧を入れ替えると選んだ行が外れるので，書き換えもやめる
                row.table.set_rows(rows);
                if let Some(search) = row.search {
                    row.table.filter(&ffi::window_text(search));
                }
                row.editing = None;
                let content = row.table.len() as f32 * size::TABLE_ROW_HEIGHT;
                row.table_scroll.set_extent(content, table_viewport(row));
            }
            match &row.row.control {
                Control::Dictionaries(list, _) => {
                    let entries = crate::dictionaries::entries(*list, values.value(list.path()));
                    row.dictionary_inputs = entries
                        .iter()
                        .map(|entry| crate::dictionaries::inputs(*list, entry))
                        .collect();
                }
                Control::CustomThemes(_) => {
                    row.dictionary_inputs =
                        crate::themes::entries(values.value(crate::themes::THEMES))
                            .into_iter()
                            .map(|entry| vec![entry.name])
                            .collect();
                }
                _ => {}
            }
            for window in row.windows().collect::<Vec<_>>() {
                ffi::enable(window, row.enabled);
            }
        }
        self.show_footer_variants();
    }

    /// 部品を置く．width はページの幅(DIP)．中身の高さを返す
    pub fn arrange(&mut self, width: f32, measure: &dyn paint::Measure) -> f32 {
        self.width = width;
        let visible: Vec<bool> = self.rows.iter().map(|row| row.visible).collect();
        let all: Vec<&Row> = self
            .sections
            .iter()
            .flat_map(|section| &section.rows)
            .collect();
        let line = size::NOTE_LINE_HEIGHT;
        self.layout = layout::layout(
            &self.sections,
            width,
            |row| {
                all.iter()
                    .position(|candidate| std::ptr::eq(*candidate, row))
                    .is_none_or(|index| visible[index])
            },
            |text, width| {
                let height = measure.wrapped_height(text, TextStyle::Caption, width);
                ((height / line).ceil() as usize).max(1)
            },
        );
        for row in &mut self.rows {
            row.card = None;
        }
        let mut offset = 0;
        let mut starts = Vec::new();
        for section in &self.sections {
            starts.push(offset);
            offset += section.rows.len();
        }
        for (index, section) in self.layout.sections.iter().enumerate() {
            for card in &section.cards {
                let flat = starts[index] + card.row;
                if let Some(row) = self.rows.get_mut(flat) {
                    row.card = Some(card.clone());
                }
            }
        }
        for row in &mut self.rows {
            if row.card.is_some() {
                let content = row.table.len() as f32 * size::TABLE_ROW_HEIGHT;
                let viewport = table_viewport(row);
                row.table_scroll.set_extent(content, viewport);
                if matches!(
                    row.row.control,
                    Control::Notices | Control::KeymapReport | Control::ThemeReport
                ) {
                    if let Some(card) = &row.card {
                        let inner = card.control.width - size::FIELD_PADDING_X * 2.0;
                        let height = measure.wrapped_height(&row.text, TextStyle::Caption, inner)
                            + size::FIELD_PADDING_X;
                        row.text_scroll.set_extent(height, card.control.height);
                    }
                }
            }
        }
        self.layout.height
    }

    /// 打つ欄を置く．origin はページの左上の窓の中の位置(DIP)，scroll は送った量．hidden なら隠す(ページの入りの動きのあいだ)
    pub fn place_fields(&self, theme: &Theme, origin: (f32, f32), scroll: f32, hidden: bool) {
        for row in &self.rows {
            let shown = !hidden && row.visible && row.card.is_some();
            for part in row.parts() {
                let Some(window) = row.edit(part) else {
                    continue;
                };
                let Some(rect) = row.part_rect(part).filter(|_| shown) else {
                    ffi::show(window, false);
                    continue;
                };
                let line = size::BODY_LINE_HEIGHT;
                let x = origin.0 + rect.x + size::FIELD_PADDING_X;
                let y = origin.1 + rect.y - scroll + (rect.height - line) / 2.0;
                let width = rect.width - size::FIELD_PADDING_X * 2.0;
                let left = theme.px(x);
                let top = theme.px(y);
                ffi::place(
                    window,
                    left,
                    top,
                    theme.px(x + width) - left,
                    theme.px(y + line) - top,
                );
                ffi::show(window, true);
            }
        }
    }

    /// フォーカスで巡る部品(出していて使えるもの)
    pub fn focusable(&self) -> Vec<Element> {
        self.rows
            .iter()
            .enumerate()
            .filter(|(_, row)| row.visible && row.card.is_some())
            .flat_map(|(index, row)| {
                row.parts()
                    .into_iter()
                    .filter(|part| row.part_enabled(*part))
                    .map(move |part| Element { row: index, part })
            })
            .collect()
    }

    /// 出している部品(使えないものも含む．読み上げ)
    pub fn elements(&self) -> Vec<Element> {
        self.rows
            .iter()
            .enumerate()
            .filter(|(_, row)| row.visible && row.card.is_some())
            .flat_map(|(index, row)| {
                row.parts()
                    .into_iter()
                    .map(move |part| Element { row: index, part })
            })
            .collect()
    }

    /// 部品の位置(ページの中の座標)
    pub fn rect(&self, element: Element) -> Option<Rect> {
        self.rows.get(element.row)?.part_rect(element.part)
    }

    /// 部品の名前(読み上げ)
    pub fn name(&self, element: Element) -> String {
        let Some(row) = self.rows.get(element.row) else {
            return String::new();
        };
        match element.part {
            Part::Reset => format!("{} {}", row.row.title, features::RESTORE_DEFAULT),
            Part::Top(_) | Part::Bottom(_) | Part::PresetLoad | Part::Action => {
                row.button_label(element.part).to_string()
            }
            Part::Field(index) => row
                .row
                .control
                .list_spec()
                .and_then(|spec| spec.fields.get(index))
                .map_or_else(String::new, |field| field.label.to_string()),
            Part::Search => features::SEARCH.to_string(),
            Part::Table => row.row.control.table_columns().join("・"),
            _ => row.row.title.to_string(),
        }
    }

    /// 打つ欄の窓
    pub fn edit(&self, element: Element) -> Option<Window> {
        self.rows.get(element.row)?.edit(element.part)
    }

    /// 読み上げに見せる部品の種類と状態
    pub fn describe(&self, element: Element) -> Option<Described> {
        let row = self.rows.get(element.row)?;
        Some(match element.part {
            Part::Toggle => Described::Toggle(row.on),
            Part::Dropdown | Part::Field(_) if row.is_dropdown(element.part) => {
                let items = row.dropdown_items(element.part);
                let label = row
                    .dropdown_selected(element.part)
                    .and_then(|selected| items.get(selected).cloned())
                    .unwrap_or_default();
                Described::Dropdown(label)
            }
            Part::Table => Described::Table,
            Part::Text => Described::Text,
            Part::Field(_) | Part::Search | Part::PreviewField(_) => Described::Edit,
            _ => Described::Button,
        })
    }

    /// 部品の番号(読み上げで見分ける．ページの中で変わらない)
    pub fn element_id(element: Element) -> i32 {
        let part = match element.part {
            Part::Reset => 0,
            Part::Toggle => 1,
            Part::Dropdown => 2,
            Part::Action => 3,
            Part::Color => 4,
            Part::PresetLoad => 5,
            Part::Field(index) => 10 + index,
            Part::Top(index) => 20 + index,
            Part::Search => 30,
            Part::Bottom(index) => 40 + index,
            Part::Table => 50,
            Part::PreviewField(index) => 60 + index,
            Part::Text => 70,
        };
        let id = element.row * 100 + part;
        i32::try_from(id).unwrap_or(i32::MAX)
    }

    /// 窓から打つ欄を引く
    pub fn element_of(&self, window: Window) -> Option<Element> {
        self.rows.iter().enumerate().find_map(|(index, row)| {
            row.parts()
                .into_iter()
                .find(|part| row.edit(*part) == Some(window))
                .map(|part| Element { row: index, part })
        })
    }

    /// (x, y)(ページの中の座標)にある部品
    pub fn hit(&self, x: f32, y: f32) -> Option<Element> {
        self.rows.iter().enumerate().find_map(|(index, row)| {
            if !row.visible || row.card.is_none() {
                return None;
            }
            row.parts().into_iter().find_map(|part| {
                let rect = row.part_rect(part)?;
                let inside = x >= rect.x && x < rect.max_x() && y >= rect.y && y < rect.max_y();
                (inside && row.part_enabled(part)).then_some(Element { row: index, part })
            })
        })
    }

    pub fn enabled(&self, element: Element) -> bool {
        self.rows
            .get(element.row)
            .is_some_and(|row| row.visible && row.part_enabled(element.part))
    }

    pub fn is_dropdown(&self, element: Element) -> bool {
        self.rows
            .get(element.row)
            .is_some_and(|row| row.is_dropdown(element.part))
    }

    pub fn dropdown_items(&self, element: Element) -> (Vec<String>, Option<usize>) {
        self.rows
            .get(element.row)
            .map_or((Vec::new(), None), |row| {
                (
                    row.dropdown_items(element.part),
                    row.dropdown_selected(element.part),
                )
            })
    }

    /// ポインターを載せた部品を変える．動きが始まったら true
    pub fn set_hover(&mut self, element: Option<Element>, now: f64) {
        let duration = f64::from(motion::HOVER);
        for (key, tween) in &mut self.hover {
            if Some(*key) != element {
                tween.retarget(0.0, now, duration, Easing::LINEAR);
            }
        }
        if let Some(element) = element {
            self.hover
                .entry(element)
                .or_insert_with(|| Tween::fixed(0.0))
                .retarget(1.0, now, duration, Easing::LINEAR);
        }
        self.hover
            .retain(|_, tween| tween.target() > 0.0 || tween.running(now));
    }

    pub fn set_table_hover(&mut self, hover: Option<(usize, usize)>) -> bool {
        let changed = self.table_hover != hover;
        self.table_hover = hover;
        changed
    }

    /// 動きの途中か(フレームを回し続けるか)
    pub fn animating(&self, now: f64) -> bool {
        self.hover.values().any(|tween| tween.running(now))
            || self.rows.iter().any(|row| {
                row.knob.running(now)
                    || row.table_scroll.animating(now)
                    || row.text_scroll.animating(now)
            })
    }

    fn hover_value(&self, element: Element, now: f64) -> f32 {
        self.hover
            .get(&element)
            .map_or(0.0, |tween| tween.value(now))
    }

    /// 部品を押した(クリック・Space・Enter)．頼みがあれば返す
    pub fn activate(&mut self, element: Element, now: f64) -> Option<Event> {
        let event = self.handle_activate(element, now);
        self.show_footer_variants();
        event
    }

    fn handle_activate(&mut self, element: Element, now: f64) -> Option<Event> {
        let row = self.rows.get_mut(element.row)?;
        if !row.part_enabled(element.part) {
            return None;
        }
        let part = element.part;
        match (&row.row.control, part) {
            (_, Part::Reset) => return Some(Event::Reset(row.row.path)),
            (Control::Toggle, Part::Toggle) => {
                let on = !row.on;
                row.on = on;
                row.knob.retarget(
                    if on { 1.0 } else { 0.0 },
                    now,
                    f64::from(motion::TOGGLE),
                    Easing::STANDARD,
                );
                return Some(Event::Set {
                    path: row.row.path,
                    value: Value::Bool(on),
                    clears: row.row.clears,
                });
            }
            (Control::Action(action), Part::Action) => return Some(Event::Action(*action)),
            (Control::Color, Part::Color) => {
                return Some(Event::ChooseColor {
                    path: row.row.path,
                    current: row.color.clone(),
                })
            }
            (Control::Preset, Part::PresetLoad) => {
                let (preset, _) = keys::PRESETS.get(row.choice?)?;
                return Some(Event::LoadPreset(preset));
            }
            _ => {}
        }
        let positions = row.table.selected_positions();
        let first = positions.first().copied();
        if let (Control::CustomThemes(_), Part::Top(0) | Part::Bottom(_)) = (&row.row.control, part)
        {
            let action = match part {
                Part::Top(_) => ThemeAction::Rename(
                    row.edit(Part::Field(0))
                        .map(ffi::window_text)
                        .unwrap_or_default(),
                ),
                Part::Bottom(index) => ThemeAction::BOTTOM.get(index)?.clone(),
                _ => return None,
            };
            let name = first
                .and_then(|index| row.dictionary_inputs.get(index))
                .and_then(|inputs| inputs.first().cloned())
                .unwrap_or_default();
            return Some(Event::ThemeList {
                action,
                index: first,
                name,
            });
        }
        if let (Control::Dictionaries(list, _), Part::Top(0) | Part::Bottom(_)) =
            (&row.row.control, part)
        {
            let action = match part {
                Part::Top(_) => DictionaryAction::Update(row.input_values()),
                Part::Bottom(index) => DictionaryAction::BOTTOM.get(index)?.clone(),
                _ => return None,
            };
            return Some(Event::DictionaryList {
                list: *list,
                action,
                index: first,
            });
        }
        if let Control::SyncFields(_) = row.row.control {
            return (Some(part) == row.toggle_part() && !positions.is_empty())
                .then_some(Event::SyncToggleFields(positions));
        }
        if let Control::List(spec, _) = &row.row.control {
            match (spec.path, part) {
                ("keymap", Part::Bottom(0)) => {
                    // キーの欄(状態・キー・コマンドの 2 つ目)で，次に押したキーを書く
                    if let Some(window) = row.edit(Part::Field(1)) {
                        edit::record_key(window, keys::PRESS);
                    }
                    return None;
                }
                ("keymap", Part::Bottom(1)) => {
                    // 選んだ行を入力欄に写し，追加のボタンで新しい行として足す
                    let index = *row.table.selected_rows().first()?;
                    row.fill_inputs(index);
                    row.editing = None;
                    return None;
                }
                ("profileRules", Part::Bottom(0)) => {
                    return Some(Event::ChooseApp { path: spec.path })
                }
                _ => {}
            }
        }
        if !row.has_add_remove() {
            return None;
        }
        let (spec, limit) = row.list_spec().map(|(spec, limit)| (*spec, limit))?;
        let values = row.input_values();
        let selected = row.table.selected_rows();
        let dictionary = matches!(row.row.control, Control::Dictionary(_));
        if let Control::Symbols(kind, _) = row.row.control {
            return match part {
                Part::Top(0) if spec.is_filled(&values) => Some(Event::SymbolSave {
                    kind,
                    item: spec.make(&values),
                    replacing: row.editing,
                }),
                Part::Top(1) => (!selected.is_empty()).then_some(Event::SymbolRemove {
                    kind,
                    indices: selected,
                }),
                Part::Top(2) => (!selected.is_empty()).then_some(Event::SymbolToggle {
                    kind,
                    indices: selected,
                }),
                _ => None,
            };
        }
        match part {
            Part::Top(0) if spec.is_filled(&values) && dictionary => Some(Event::DictionaryAdd {
                item: spec.make(&values),
                replacing: row.editing,
            }),
            Part::Top(0) if spec.is_filled(&values) => Some(Event::ListAdd {
                spec,
                limit,
                item: spec.make(&values),
                replacing: row.editing,
            }),
            Part::Top(1) if dictionary => {
                (!selected.is_empty()).then_some(Event::DictionaryRemove(selected))
            }
            Part::Top(1) => (!selected.is_empty()).then_some(Event::ListRemove {
                spec,
                indices: selected,
            }),
            _ => None,
        }
    }

    /// ドロップダウンで index を選んだ．頼みがあれば返す
    pub fn choose(&mut self, element: Element, index: usize) -> Option<Event> {
        let row = self.rows.get_mut(element.row)?;
        let event = match (&row.row.control, element.part) {
            (Control::Choice(choices), Part::Dropdown) => {
                let (value, _) = choices.get(index)?;
                row.choice = Some(index);
                Some(Event::Set {
                    path: row.row.path,
                    value: Value::String((*value).to_string()),
                    clears: row.row.clears,
                })
            }
            (Control::Stepper(_) | Control::Seconds(_), Part::Dropdown) => {
                let number = *row.numbers.get(index)?;
                row.choice = Some(index);
                Some(Event::Set {
                    path: row.row.path,
                    value: crate::model::number(number),
                    clears: row.row.clears,
                })
            }
            (Control::Preset, Part::Dropdown) => {
                row.choice = Some(index);
                None
            }
            (_, Part::Field(field)) => {
                if let Some(Input::Choice(selected)) = row.inputs.get_mut(field) {
                    *selected = index;
                }
                None
            }
            _ => None,
        };
        self.show_footer_variants();
        event
    }

    /// 打つ欄の文字が変わった．頼みがあれば返す(試す欄)
    pub fn edited(&mut self, element: Element) -> Option<Event> {
        let row = self.rows.get_mut(element.row)?;
        match element.part {
            Part::Search => {
                let query = row.search.map(ffi::window_text).unwrap_or_default();
                row.table.filter(&query);
                row.editing = None;
                let content = row.table.len() as f32 * size::TABLE_ROW_HEIGHT;
                let viewport = table_viewport(row);
                row.table_scroll.set_extent(content, viewport);
                row.table_scroll.jump_to(0.0);
                None
            }
            Part::PreviewField(_) => {
                let texts: Vec<String> = row
                    .preview_fields
                    .iter()
                    .map(|window| ffi::window_text(*window))
                    .collect();
                Some(Event::Preview {
                    text: texts.first().cloned().unwrap_or_default(),
                    preceding: texts.get(1).cloned().unwrap_or_default(),
                })
            }
            _ => None,
        }
    }

    /// 打つ欄で Enter を押した(一覧なら追加・更新のボタンを押す)
    pub fn submit(&mut self, element: Element, now: f64) -> Option<Event> {
        let row = self.rows.get(element.row)?;
        if !matches!(element.part, Part::Field(_)) {
            return None;
        }
        let button = Element {
            row: element.row,
            part: Part::Top(0),
        };
        if row.list_spec().is_some() && row.part_enabled(Part::Top(0)) {
            return self.activate(button, now);
        }
        None
    }

    /// 表の行を押した．頼みがあれば返す
    pub fn table_click(
        &mut self,
        row_index: usize,
        position: usize,
        control: bool,
        shift: bool,
    ) -> Option<Event> {
        let row = self.rows.get_mut(row_index)?;
        if !row.table.click(position, control, shift) {
            return None;
        }
        self.selection_changed(row_index)
    }

    /// 表の上でキーを押した．頼みがあれば返す
    pub fn table_key(
        &mut self,
        row_index: usize,
        movement: Move,
        shift: bool,
        now: f64,
    ) -> Option<Event> {
        let row = self.rows.get_mut(row_index)?;
        if !row.table.move_cursor(movement, shift) {
            return None;
        }
        if let Some(cursor) = row.table.cursor() {
            let top = cursor as f32 * size::TABLE_ROW_HEIGHT;
            row.table_scroll
                .reveal(top, top + size::TABLE_ROW_HEIGHT, now);
        }
        self.selection_changed(row_index)
    }

    /// 表の行の数(1 ページ分．PageUp・PageDown で動かす数)
    pub fn table_page(&self, row_index: usize) -> usize {
        self.rows
            .get(row_index)
            .map_or(1, |row| {
                (table_viewport(row) / size::TABLE_ROW_HEIGHT).floor() as usize
            })
            .max(1)
    }

    /// 表で選んだ行が変わったあとの入力欄・ボタンの状態(macOS の RuleListEditor と同じ)
    fn selection_changed(&mut self, row_index: usize) -> Option<Event> {
        let row = self.rows.get_mut(row_index)?;
        let positions = row.table.selected_positions();
        if row.is_dictionary_list() {
            // 選んだ辞書の名前などを入力欄に出す(書き換えて「更新」を押す)
            if let Some(first) = positions.first() {
                row.fill_dictionary_inputs(*first);
            }
        }
        if row.has_add_remove() {
            // 1 行だけ選んだら入力欄に出し，追加のボタンを「更新」にする
            match row.table.selected_rows().as_slice() {
                [index] => {
                    let index = *index;
                    row.fill_inputs(index);
                    row.editing = Some(index);
                }
                _ => row.editing = None,
            }
        }
        let event = matches!(row.row.control, Control::CustomThemes(_))
            .then(|| Event::ThemeSelected(positions.first().copied()));
        self.show_footer_variants();
        event
    }

    /// 表の (x, y)(ページの中の座標)にある行の位置
    pub fn table_position(&self, row_index: usize, y: f32, now: f64) -> Option<usize> {
        let row = self.rows.get(row_index)?;
        let rect = row.part_rect(Part::Table)?;
        let top = rect.y + size::TABLE_HEADER_HEIGHT;
        if y < top {
            return None;
        }
        let position = ((y - top + row.table_scroll.offset(now)) / size::TABLE_ROW_HEIGHT) as usize;
        (position < row.table.len()).then_some(position)
    }

    /// ホイールで部品の中を送る．送れたら true(送れなければページを送る)
    pub fn scroll_inside(&mut self, element: Element, delta: f32, now: f64) -> bool {
        let Some(row) = self.rows.get_mut(element.row) else {
            return false;
        };
        let scroller = match element.part {
            Part::Table => &mut row.table_scroll,
            Part::Text => &mut row.text_scroll,
            _ => return false,
        };
        let before = scroller.target();
        scroller.scroll_by(delta, now);
        scroller.target() != before
    }

    /// path の一覧の field 番目の入力欄に text を入れる(アプリを選んで足すとき)
    pub fn set_list_input(&mut self, path: &str, field: usize, text: &str) {
        for row in &mut self.rows {
            if let Control::List(spec, _) = &row.row.control {
                if spec.path != path {
                    continue;
                }
                if let Some(Input::Edit(window)) = row.inputs.get(field) {
                    ffi::set_text(*window, text);
                }
            }
        }
    }

    /// 足し終えた記号の一覧の入力欄を空にする
    pub fn clear_symbol_inputs(&mut self) {
        for row in &mut self.rows {
            if let Control::Symbols(..) = row.row.control {
                for input in &row.inputs {
                    if let Input::Edit(window) = input {
                        ffi::set_text(*window, "");
                    }
                }
                row.editing = None;
            }
        }
    }

    /// 足し終えた一覧の入力欄を空にする
    pub fn clear_list_inputs(&mut self, path: &str) {
        for row in self.rows.iter_mut().filter(|row| row.row.path == path) {
            if !row.has_add_remove() {
                continue;
            }
            for input in &row.inputs {
                if let Input::Edit(window) = input {
                    ffi::set_text(*window, "");
                }
            }
            row.editing = None;
        }
    }

    /// 試した結果を出す
    pub fn show_preview(&mut self, text: &str) {
        for row in &mut self.rows {
            if row.row.control == Control::Preview {
                row.preview_result = text.to_string();
            }
        }
    }

    /// 外観の見本を描く場所(ページの中の座標)
    pub fn preview_rect(&self) -> Option<Rect> {
        self.rows
            .iter()
            .find(|row| row.row.control == Control::ThemePreview && row.visible)
            .and_then(|row| row.card.as_ref())
            .map(|card| card.control)
    }

    /// 注記に入れ替えて出す文(キー設定のコマンドの説明)を，入力欄で選んでいる値に合わせる．合う文が無ければ元の注記
    fn show_footer_variants(&mut self) {
        for (index, section) in self.sections.iter().enumerate() {
            if section.footer_variants.is_empty() {
                continue;
            }
            let Some(note) = section.footer else {
                continue;
            };
            let chosen: Vec<String> = self
                .rows
                .iter()
                .filter(|row| row.section == index)
                .flat_map(RowState::chosen_values)
                .collect();
            let shown = section
                .footer_variants
                .iter()
                .find(|(value, _)| chosen.iter().any(|chosen| chosen == value))
                .map_or(note, |(_, text)| *text);
            if let Some(slot) = self.footers.get_mut(index) {
                *slot = Some(shown);
            }
        }
    }

    /// ページを描く(座標はページの中．呼ぶ側が送った量だけずらしておく)
    pub fn paint(&self, canvas: &mut dyn Canvas, frame: &Frame) {
        let theme = frame.theme;
        let palette = &theme.palette;
        if frame.shows(self.layout.title) {
            canvas.text(
                self.layout.title,
                self.page.title(),
                TextStyle::Title,
                Color::from(palette.text),
                TextLayout::LINE,
            );
        }
        for (index, section) in self.layout.sections.iter().enumerate() {
            if let (Some(rect), Some(title)) = (
                section.title.filter(|rect| frame.shows(*rect)),
                self.sections.get(index).and_then(|section| section.title),
            ) {
                canvas.text(
                    rect,
                    title,
                    TextStyle::Section,
                    Color::from(palette.text),
                    TextLayout::LINE,
                );
            }
            for card in section.cards.iter().filter(|card| frame.shows(card.card)) {
                canvas.fill_round(card.card, size::CARD_RADIUS, Color::from(palette.card));
                canvas.stroke_round(
                    card.card,
                    size::CARD_RADIUS,
                    1.0,
                    Color::from(palette.card_stroke),
                );
            }
            if let (Some(rect), Some(Some(footer))) = (
                section.footer.filter(|rect| frame.shows(*rect)),
                self.footers.get(index),
            ) {
                canvas.text(
                    rect,
                    footer,
                    TextStyle::Caption,
                    Color::from(palette.text_secondary),
                    TextLayout::WRAP,
                );
            }
        }
        for (index, row) in self.rows.iter().enumerate() {
            let shown = row.card.as_ref().is_some_and(|card| frame.shows(card.card));
            if row.visible && shown {
                self.paint_row(canvas, frame, index, row);
            }
        }
    }

    fn state(&self, frame: &Frame, element: Element, enabled: bool) -> State {
        State {
            enabled,
            hover: if enabled {
                self.hover_value(element, frame.now)
            } else {
                0.0
            },
            pressed: frame.pressed == Some(element),
            focus_visible: frame.focus_visible && frame.focus == Some(element),
        }
    }

    fn paint_row(&self, canvas: &mut dyn Canvas, frame: &Frame, index: usize, row: &RowState) {
        let theme = frame.theme;
        let palette = &theme.palette;
        let Some(card) = &row.card else { return };
        let label_color = if row.enabled || row.row.control == Control::Note {
            palette.text
        } else {
            palette.text_disabled
        };
        if card.label.width > 0.0 && card.label.height > 0.0 {
            canvas.text(
                card.label,
                row.row.title,
                TextStyle::Body,
                Color::from(label_color),
                TextLayout::LINE,
            );
        }
        for (position, rect) in &card.descriptions {
            let Some(note) = self
                .rows
                .iter()
                .filter(|other| other.section == row.section)
                .nth(*position)
            else {
                continue;
            };
            canvas.text(
                *rect,
                note.row.title,
                TextStyle::Caption,
                Color::from(palette.text_secondary),
                TextLayout::WRAP,
            );
        }
        let element = |part| Element { row: index, part };
        if row.resettable {
            let reset = element(Part::Reset);
            paint::button(
                canvas,
                theme,
                card.reset,
                theme.glyphs.undo,
                paint::ButtonKind::Subtle,
                self.state(frame, reset, row.enabled),
            );
        }
        match &row.row.control {
            Control::Toggle => {
                let toggle = element(Part::Toggle);
                paint::toggle(
                    canvas,
                    theme,
                    card.control,
                    row.on,
                    row.knob.value(frame.now),
                    text::ON,
                    text::OFF,
                    self.state(frame, toggle, row.enabled),
                );
            }
            Control::Choice(_) | Control::Stepper(_) | Control::Seconds(_) | Control::Preset => {
                let dropdown = element(Part::Dropdown);
                let items = row.dropdown_items(Part::Dropdown);
                let label = row
                    .choice
                    .and_then(|choice| items.get(choice))
                    .cloned()
                    .unwrap_or_default();
                paint::dropdown(
                    canvas,
                    theme,
                    card.control,
                    &label,
                    frame.open == Some(dropdown),
                    self.state(frame, dropdown, row.enabled),
                );
                if let (Control::Preset, Some(rect)) =
                    (&row.row.control, row.part_rect(Part::PresetLoad))
                {
                    let load = element(Part::PresetLoad);
                    paint::button(
                        canvas,
                        theme,
                        rect,
                        keys::LOAD,
                        paint::ButtonKind::Standard,
                        self.state(frame, load, row.enabled),
                    );
                }
            }
            Control::Action(_) => {
                let action = element(Part::Action);
                paint::button(
                    canvas,
                    theme,
                    card.control,
                    row.row.title,
                    paint::ButtonKind::Standard,
                    self.state(frame, action, row.enabled),
                );
            }
            Control::Color => self.paint_color(canvas, frame, index, row, card.control),
            Control::Stat(_) | Control::Info(_) | Control::Version => {
                canvas.text(
                    card.control,
                    &row.text,
                    TextStyle::Body,
                    Color::from(palette.text_secondary),
                    TextLayout::TRAILING,
                );
            }
            Control::Notices | Control::KeymapReport | Control::ThemeReport => {
                self.paint_text_box(canvas, frame, index, row, card.control);
            }
            Control::ThemePreview => canvas.preview(card.control),
            Control::Preview => {
                for field in 0..2 {
                    self.paint_field(canvas, frame, index, row, Part::PreviewField(field));
                }
                canvas.text(
                    card.control,
                    &row.preview_result,
                    TextStyle::Body,
                    Color::from(palette.text),
                    TextLayout::WRAP,
                );
            }
            Control::Note => {}
            _ => self.paint_list(canvas, frame, index, row),
        }
    }

    fn paint_field(
        &self,
        canvas: &mut dyn Canvas,
        frame: &Frame,
        index: usize,
        row: &RowState,
        part: Part,
    ) {
        let Some(rect) = row.part_rect(part) else {
            return;
        };
        let element = Element { row: index, part };
        let window = row.edit(part);
        let focused = window.is_some() && window == frame.focused_edit;
        paint::field_frame(
            canvas,
            frame.theme,
            rect,
            focused,
            self.state(frame, element, row.enabled),
        );
        if frame.draw_fields {
            // 見本の書き出しでは EDIT が写らないので，欄の文字か案内を描く
            let text = window.map(ffi::window_text).unwrap_or_default();
            let (shown, color) = if text.is_empty() {
                (self.name(element), frame.theme.palette.text_secondary)
            } else {
                (text, frame.theme.palette.text)
            };
            let inner = Rect::new(
                rect.x + size::FIELD_PADDING_X,
                rect.y,
                rect.width - size::FIELD_PADDING_X * 2.0,
                rect.height,
            );
            canvas.text(
                inner,
                &shown,
                TextStyle::Body,
                Color::from(color),
                TextLayout::LINE,
            );
        }
    }

    fn paint_color(
        &self,
        canvas: &mut dyn Canvas,
        frame: &Frame,
        index: usize,
        row: &RowState,
        rect: Rect,
    ) {
        let theme = frame.theme;
        let palette = &theme.palette;
        let element = Element {
            row: index,
            part: Part::Color,
        };
        let state = self.state(frame, element, row.enabled);
        paint::button(canvas, theme, rect, "", paint::ButtonKind::Standard, state);
        let gap = size::CONTROL_GAP;
        let swatch_size = rect.height - gap * 2.0;
        let swatch = Rect::new(rect.x + gap, rect.y + gap, swatch_size, swatch_size);
        if let Some((red, green, blue)) = crate::themes::rgb(&row.color) {
            canvas.fill_round(
                swatch,
                size::CONTROL_RADIUS,
                Color::from(tokens::Rgb { red, green, blue }),
            );
            canvas.stroke_round(
                swatch,
                size::CONTROL_RADIUS,
                1.0,
                Color::from(palette.control_stroke),
            );
        }
        let text = if row.enabled {
            palette.text
        } else {
            palette.text_disabled
        };
        canvas.text(
            Rect::new(
                swatch.max_x() + gap,
                rect.y,
                rect.width - swatch_size - gap * 3.0,
                rect.height,
            ),
            &row.color,
            TextStyle::Body,
            Color::from(text),
            TextLayout::LINE,
        );
    }

    fn paint_text_box(
        &self,
        canvas: &mut dyn Canvas,
        frame: &Frame,
        index: usize,
        row: &RowState,
        rect: Rect,
    ) {
        let theme = frame.theme;
        let palette = &theme.palette;
        canvas.fill_round(rect, size::CONTROL_RADIUS, Color::from(palette.control));
        canvas.stroke_round(
            rect,
            size::CONTROL_RADIUS,
            1.0,
            Color::from(palette.control_stroke),
        );
        let offset = row.text_scroll.offset(frame.now);
        let padding = size::FIELD_PADDING_X;
        canvas.push_clip(rect);
        // 高さは測ったときと同じにして，組んだ文字を使い回す
        let inner = Rect::new(
            rect.x + padding,
            rect.y + padding / 2.0 - offset,
            rect.width - padding * 2.0,
            f32::MAX,
        );
        canvas.text(
            inner,
            &row.text,
            TextStyle::Caption,
            Color::from(palette.text),
            TextLayout::WRAP,
        );
        canvas.pop_clip();
        scrollbar(canvas, theme, rect, &row.text_scroll, frame.now);
        let element = Element {
            row: index,
            part: Part::Text,
        };
        if frame.focus_visible && frame.focus == Some(element) {
            paint::focus_ring(canvas, theme, rect, size::CONTROL_RADIUS);
        }
    }

    fn paint_list(&self, canvas: &mut dyn Canvas, frame: &Frame, index: usize, row: &RowState) {
        let theme = frame.theme;
        for part in row.parts() {
            let element = Element { row: index, part };
            let Some(rect) = row.part_rect(part) else {
                continue;
            };
            match part {
                Part::Field(_) if row.is_dropdown(part) => {
                    let items = row.dropdown_items(part);
                    let label = row
                        .dropdown_selected(part)
                        .and_then(|selected| items.get(selected))
                        .cloned()
                        .unwrap_or_default();
                    paint::dropdown(
                        canvas,
                        theme,
                        rect,
                        &label,
                        frame.open == Some(element),
                        self.state(frame, element, row.part_enabled(part)),
                    );
                }
                Part::Field(_) | Part::Search => self.paint_field(canvas, frame, index, row, part),
                Part::Top(_) | Part::Bottom(_) => {
                    let kind = if part == Part::Top(0) && row.has_add_remove() {
                        paint::ButtonKind::Accent
                    } else {
                        paint::ButtonKind::Standard
                    };
                    paint::button(
                        canvas,
                        theme,
                        rect,
                        row.button_label(part),
                        kind,
                        self.state(frame, element, row.part_enabled(part)),
                    );
                }
                Part::Table => self.paint_table(canvas, frame, index, row, rect),
                _ => {}
            }
        }
    }

    fn paint_table(
        &self,
        canvas: &mut dyn Canvas,
        frame: &Frame,
        index: usize,
        row: &RowState,
        rect: Rect,
    ) {
        let theme = frame.theme;
        let palette = &theme.palette;
        canvas.fill_round(rect, size::CONTROL_RADIUS, Color::from(palette.control));
        let columns = row.row.control.table_columns();
        let count = columns.len().max(1) as f32;
        let padding = size::FIELD_PADDING_X;
        let column_width = (rect.width - padding) / count;
        let header = Rect::new(rect.x, rect.y, rect.width, size::TABLE_HEADER_HEIGHT);
        for (column, title) in columns.iter().enumerate() {
            canvas.text(
                Rect::new(
                    header.x + padding + column_width * column as f32,
                    header.y,
                    column_width - padding,
                    header.height,
                ),
                title,
                TextStyle::Caption,
                Color::from(palette.text_secondary),
                TextLayout::LINE,
            );
        }
        canvas.fill_rect(
            Rect::new(rect.x, header.max_y() - 1.0, rect.width, 1.0),
            Color::from(palette.card_stroke),
        );
        let body = Rect::new(
            rect.x,
            header.max_y(),
            rect.width,
            (rect.height - size::TABLE_HEADER_HEIGHT).max(0.0),
        );
        canvas.push_clip(body);
        if row.table.is_empty() {
            let empty = row.list_spec().map_or("", |(spec, _)| spec.empty);
            canvas.text(
                body,
                empty,
                TextStyle::Body,
                Color::from(palette.text_secondary),
                TextLayout::CENTER,
            );
        }
        let offset = row.table_scroll.offset(frame.now);
        let row_height = size::TABLE_ROW_HEIGHT;
        let first = (offset / row_height).floor().max(0.0) as usize;
        let visible = (body.height / row_height).ceil() as usize + 1;
        for position in first..(first + visible).min(row.table.len()) {
            let Some(cells) = row.table.shown_row(position) else {
                continue;
            };
            let top = body.y + position as f32 * row_height - offset;
            let line = Rect::new(rect.x + 2.0, top + 1.0, rect.width - 4.0, row_height - 2.0);
            let selected = row.table.is_selected(position);
            if selected {
                canvas.fill_round(
                    line,
                    size::CONTROL_RADIUS,
                    Color::from(palette.nav_selected),
                );
                let indicator = size::NAV_INDICATOR_HEIGHT.min(row_height - 8.0);
                canvas.fill_round(
                    Rect::new(
                        line.x,
                        line.y + (line.height - indicator) / 2.0,
                        size::NAV_INDICATOR_WIDTH,
                        indicator,
                    ),
                    size::NAV_INDICATOR_WIDTH / 2.0,
                    Color::from(palette.accent),
                );
            } else if self.table_hover == Some((index, position)) {
                canvas.fill_round(line, size::CONTROL_RADIUS, Color::from(palette.nav_hover));
            }
            let text = if row.enabled {
                palette.text
            } else {
                palette.text_disabled
            };
            for (column, cell) in cells.iter().enumerate() {
                canvas.text(
                    Rect::new(
                        rect.x + padding + column_width * column as f32,
                        top,
                        column_width - padding,
                        row_height,
                    ),
                    cell,
                    TextStyle::Body,
                    Color::from(text),
                    TextLayout::LINE,
                );
            }
        }
        canvas.pop_clip();
        scrollbar(canvas, theme, body, &row.table_scroll, frame.now);
        canvas.stroke_round(
            rect,
            size::CONTROL_RADIUS,
            1.0,
            Color::from(palette.control_stroke),
        );
        let element = Element {
            row: index,
            part: Part::Table,
        };
        if frame.focus_visible && frame.focus == Some(element) {
            paint::focus_ring(canvas, theme, rect, size::CONTROL_RADIUS);
        }
    }

    /// 部品の中の送り(ポインターを載せたとき太くする)
    pub fn set_scrollbar_hover(&mut self, element: Option<Element>, now: f64) {
        for (index, row) in self.rows.iter_mut().enumerate() {
            let table = element
                == Some(Element {
                    row: index,
                    part: Part::Table,
                });
            let text = element
                == Some(Element {
                    row: index,
                    part: Part::Text,
                });
            row.table_scroll.set_hover(table, now);
            row.text_scroll.set_hover(text, now);
        }
    }
}

/// 表の行を見せる高さ
fn table_viewport(row: &RowState) -> f32 {
    row.card.as_ref().map_or(0.0, |card| {
        (card.control.height - size::TABLE_HEADER_HEIGHT).max(0.0)
    })
}

/// 重ねる細いスクロールバー(track の右端)
pub fn scrollbar(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    track: Rect,
    scroller: &Scroller,
    now: f64,
) {
    let opacity = scroller.bar_opacity(now);
    if opacity <= 0.0 {
        return;
    }
    let margin = size::SCROLLBAR_MARGIN;
    let inner = track.height - margin * 2.0;
    let Some(thumb) = scroller.thumb(inner, now) else {
        return;
    };
    let width = scroller.bar_width(now);
    let rect = Rect::new(
        track.max_x() - margin - width,
        track.y + margin + thumb.top,
        width,
        thumb.height,
    );
    canvas.fill_round(
        rect,
        width / 2.0,
        Color::from(theme.palette.scrollbar).with_alpha(opacity),
    );
}

/// 打つ欄を用意するところ(使い回せる欄があれば使い，無ければ作る)
struct FieldSource<'a, F: FnMut() -> u16> {
    parent: Window,
    font: &'a ffi::Font,
    pool: &'a mut Vec<Window>,
    next_id: &'a mut F,
}

impl<F: FnMut() -> u16> FieldSource<'_, F> {
    fn take(&mut self, placeholder: &str) -> Option<Window> {
        if let Some(window) = self.pool.pop() {
            edit::set_placeholder(window, placeholder);
            ffi::set_font(window, self.font);
            ffi::enable(window, true);
            return Some(window);
        }
        edit::create(self.parent, (self.next_id)(), placeholder, self.font)
    }
}

/// 一覧の入力欄・検索欄・試す欄の標準の EDIT を用意する
fn create_inputs<F: FnMut() -> u16>(fields: &mut FieldSource<F>, row: &mut RowState) {
    match &row.row.control {
        Control::Preview => {
            for label in [features::TRY_PLACEHOLDER, features::TRY_PRECEDING] {
                if let Some(window) = fields.take(label) {
                    row.preview_fields.push(window);
                }
            }
        }
        control => {
            let (Some(spec), Some(buttons)) = (control.list_spec(), control.list_buttons()) else {
                return;
            };
            for field in spec.fields {
                let input = match field.choices {
                    Some(_) => Input::Choice(0),
                    None => match fields.take(field.label) {
                        Some(window) => Input::Edit(window),
                        None => Input::Choice(0),
                    },
                };
                row.inputs.push(input);
            }
            if buttons.search {
                row.search = fields.take(features::SEARCH);
            }
        }
    }
}

/// 一覧の表の行(列ごとの文字)．一覧でなければ None
fn list_rows(row: &Row, values: &impl Values, extras: &Extras) -> Option<Vec<Vec<String>>> {
    Some(match &row.control {
        Control::Dictionary(_) => extras.dictionary.clone(),
        Control::Symbols(kind, _) => extras.symbol_rows(*kind).to_vec(),
        Control::SyncFields(_) => extras.sync_fields.clone(),
        Control::Dictionaries(list, _) => {
            let entries = crate::dictionaries::entries(*list, values.value(list.path()));
            crate::dictionaries::table(*list, &entries)
        }
        Control::List(spec, _) => spec
            .items(values.value(spec.path))
            .into_iter()
            .map(|item| spec.display(&item))
            .collect(),
        Control::CustomThemes(_) => {
            let entries = crate::themes::entries(values.value(crate::themes::THEMES));
            let active = values.value(crate::themes::ACTIVE).and_then(Value::as_str);
            crate::themes::table(&entries, active)
        }
        _ => return None,
    })
}

/// ページの名前と知らせ(読み込み中・つながらない)を描く
pub fn paint_status(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    page: Page,
    availability: Availability,
    width: f32,
    height: f32,
    now: f64,
) {
    let palette = &theme.palette;
    let (left, content) = layout::content_frame(width);
    let title = Rect::new(left, size::PAGE_PADDING_TOP, content, size::TITLE_HEIGHT);
    canvas.text(
        title,
        page.title(),
        TextStyle::Title,
        Color::from(palette.text),
        TextLayout::LINE,
    );
    let middle = (height / 2.0).max(title.max_y() + size::PROGRESS_RING_SIZE * 2.0);
    let message = Rect::new(
        left,
        middle + size::PROGRESS_RING_SIZE,
        content,
        size::BODY_LINE_HEIGHT * 3.0,
    );
    match availability {
        Availability::Loading => {
            let period = f64::from(motion::PROGRESS_RING);
            let phase = ((now % period) / period) as f32;
            paint::progress_ring(canvas, theme, left + content / 2.0, middle, phase);
            canvas.text(
                message,
                settings::LOADING,
                TextStyle::Body,
                Color::from(palette.text_secondary),
                TextLayout {
                    align: paint::Align::Center,
                    wrap: true,
                    center: false,
                },
            );
        }
        Availability::Unavailable => {
            canvas.text(
                Rect::new(
                    left,
                    middle - size::ICON_FONT_SIZE,
                    content,
                    size::ICON_FONT_SIZE * 2.0,
                ),
                theme.glyphs.warning,
                TextStyle::Icon,
                Color::from(palette.caution),
                TextLayout::CENTER,
            );
            canvas.text(
                message,
                text::ENGINE_UNAVAILABLE_DETAIL,
                TextStyle::Body,
                Color::from(palette.text_secondary),
                TextLayout {
                    align: paint::Align::Center,
                    wrap: true,
                    center: false,
                },
            );
        }
        Availability::Ready => {}
    }
}
