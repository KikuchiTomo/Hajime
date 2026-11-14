#![forbid(unsafe_code)]

//! 1 ページ分の部品．項目の並び(pages::Section)から部品の状態を作り，値を映し，押された部品を頼み(Event)にする．
//! 部品は子の窓にせず，状態だけを持って Direct2D で描く(ページを開くたびに窓を作り直さない)．
//! 文字を打つ欄だけは標準の EDIT にする(IME・クリップボード・読み上げのため)

mod dictionary_rows;

pub use dictionary_rows::EntryPart;

use super::ffi::{self, edit, Window};
use super::paint::{self, Canvas, State, TextLayout, TextStyle};
use super::theme::{Color, Theme};
use crate::catalog::Catalog;
use crate::layout::{self, Metrics, PageLayout, Rect, TextKind};
use crate::list::{Item, ListSpec};
use crate::model::SettingsModel;
use crate::options;
use crate::pages::{
    self, Action, Cell, Control, DictionaryList, FontPart, Info, LimitKind, Page, RangeKind, Row,
    Section, TemplateTarget, TryKind, DICTIONARY_CONDITIONS, MACROS_PATH, PROFILE_RULES,
};
use crate::store::SettingsStore;
use crate::strings::{choice, extras, features, keys, more, rule_list, settings, windows as text};
use crate::template_reference::{self as reference, Face};
use crate::ui::anim::{Easing, Tween};
use crate::ui::scroll::Scroller;
use crate::ui::table::{Move, Table};
use crate::usage::Usage;
use candidate_ui::fonts::{self as fonts, InstalledFace, Selection};
use ipc::SymbolKind;
use serde_json::Value;
use std::collections::HashMap;
use tokens::motion::settings_windows as motion;
use tokens::opacity::settings_windows as opacity;
use tokens::size::settings_windows as size;
use tokens::size::{part, space};

/// Jinen モデルの項目と，エンジンが「自動」で決めた結果を添える名前(core の SettingsFields.automaticJinenModelName)
const JINEN_MODEL_PATH: &str = "jinenModel";
const AUTOMATIC_JINEN_MODEL: &str = "automaticJinenModel";

/// 部品の番号の始まり(0 は使わない．窓の部品の番号と分ける)
const FIRST_ID: u16 = 100;

/// 辞書の行の部品の読み上げの番号(ほかの部品の番号 行 * 100 + 部品 と重ならないよう後ろに置く)
const ENTRY_ID_BASE: usize = 10_000_000;
const ENTRY_ID_ROW: usize = 1_000_000;
const ENTRY_ID_ENTRY: usize = 1_000;

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
    /// 選んだ行を，それぞれ元の行のすぐ下に複製する(キー設定の表．表の行の番号)
    ListDuplicate {
        spec: ListSpec,
        indices: Vec<usize>,
    },
    /// 選んだ行の有効と無効を切り替える(コマンドと変換マクロ．表の行の番号)
    ListToggle {
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
    /// カスタムテーマの一覧の操作(index は押した行のテーマの番号，name はそのテーマの名前)
    ThemeList {
        action: ThemeAction,
        index: Option<usize>,
        name: String,
    },
    /// カスタムテーマの編集の画面の下のボタン(名前の欄で Enter を押すと保存)
    ThemeEditor(EditorAction),
    /// アプリの実行ファイルを選ぶ窓を出し(いくつも選べる)，path の一覧に表の下で選んでいる動作で足す
    ChooseApp {
        path: &'static str,
    },
    /// 英語と日本語の試した語(word)を，いつも英語・いつも日本語にする単語のどちらに足すかを選ぶメニューを出す(macOS の resultChip)．
    /// chip は押したタグ(キーボードで開いたときは，メニューをこのタグの下に出す)
    ChooseWordList {
        word: String,
        chip: Element,
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
    /// 試す．英語と日本語の見分けなら打った文と前の文字列，変換マクロなら試す語と読みと，変換マクロの欄に書いている途中の形(draft)
    Preview {
        kind: TryKind,
        text: String,
        preceding: String,
        draft: String,
    },
    /// 単語の欄に書いた書き方を入れたときの結果を求める(path の一覧の入力欄のすぐ下に出す)
    DraftResult {
        path: &'static str,
        draft: String,
    },
    /// 既定のブラウザーで開く(謝辞の出どころ)
    OpenUrl(String),
    /// コマンドを足す・書き換えるシートを出す(書き換えるコマンドの表の行の番号．足すなら None)
    EditCommand(Option<usize>),
    /// 表の中の選ぶ欄で選び直した(index は表の行の番号，field は欄，value は設定のファイルに書く値)．すぐ書く
    ListSet {
        spec: ListSpec,
        index: usize,
        field: usize,
        value: String,
    },
    /// 選んだ行を offset だけ上(負)か下(正)へ動かす(除外設定の優先度．index は表の行の番号)
    ListMove {
        spec: ListSpec,
        index: usize,
        offset: isize,
    },
    /// 部品の大きさが変わったので置き直す(謝辞のライセンスの全文を開いた・閉じた)
    Relayout,
    /// 書き方のチップを開けた・閉じた(覚えて置き直す)
    TemplatePanel {
        target: TemplateTarget,
        open: bool,
    },
}

/// カスタムテーマの操作(macOS の AppearancePage と CustomThemeRow)
#[derive(Debug, Clone, PartialEq)]
pub enum ThemeAction {
    /// 今のテーマを写して新しく作る
    Create,
    /// 今使っているテーマを複製する
    DuplicateCurrent,
    /// 行を押して使う
    Use,
    /// 行の右のボタン(編集・複製・削除)
    Edit,
    Duplicate,
    Delete,
}

impl ThemeAction {
    /// カスタムテーマの行の右のボタンの並び(Part::Button の番号)
    const ROW: [ThemeAction; 3] = [
        ThemeAction::Edit,
        ThemeAction::Duplicate,
        ThemeAction::Delete,
    ];
}

/// カスタムテーマの編集の画面の下のボタン(macOS の CustomThemeEditor)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EditorAction {
    /// 別の新しいテーマとして保存する(保存したテーマを直しているときだけ)
    Duplicate,
    Cancel,
    Save,
}

/// 辞書の一覧の操作(macOS の ImportedDictionariesView・AssociationSection の部品)
#[derive(Debug, Clone, PartialEq)]
pub enum DictionaryAction {
    /// ファイルを選んで新しい辞書を取り込む
    Import,
    /// ファイルを選んで辞書を取り込み直す
    Reimport,
    MoveUp,
    MoveDown,
    Toggle,
    Remove,
    /// 名前・分野を打った値に変える
    Rename(String),
    SetField(String),
    /// 使う場面(always・apps・context)を変える
    SetCondition(&'static str),
    /// アプリの実行ファイルを選ぶ窓を出して，選んだアプリに足す
    ChooseApps,
    /// 選んだ実行ファイル(場所)を選んだアプリに足す
    AddApps(Vec<String>),
    /// 選んだアプリの index 番目を外す
    RemoveApp(usize),
}

/// 一覧の表の下のボタンの役割(ボタンの名前から決める)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ListButton {
    /// 選んだ行を消す
    Remove,
    /// 選んだ 1 行をシートで書き換える(コマンド)
    Edit,
    /// シートで足す(コマンド)
    Add,
    /// 選んだ 1 行を上・下へ動かす(除外設定)
    MoveUp,
    MoveDown,
    /// 選んだ行を入力欄に写す(キー設定の複製)
    Duplicate,
    /// 行を選ばなくても使える(アプリを追加・キー設定を既定に戻す)
    Always,
}

fn list_button(label: &str) -> ListButton {
    match label {
        // コマンドの「削除」(extras::REMOVE_COMMAND)も同じ文字
        settings::REMOVE => ListButton::Remove,
        extras::EDIT_COMMAND => ListButton::Edit,
        extras::ADD_COMMAND => ListButton::Add,
        crate::strings::dictionaries::MOVE_UP => ListButton::MoveUp,
        crate::strings::dictionaries::MOVE_DOWN => ListButton::MoveDown,
        keys::DUPLICATE => ListButton::Duplicate,
        _ => ListButton::Always,
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

/// 設定のファイルの項目でない値の道筋か(同期の状態「sync.」，編集しているカスタムテーマ「customTheme.」，画面の中だけの値「page.」)
pub fn is_extra_path(path: &str) -> bool {
    crate::sync::is_sync_path(path)
        || crate::themes::is_theme_path(path)
        || pages::is_view_path(path)
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

    /// 重ねた値は読めたときだけ使える．画面の中だけの値はいつも使える(まだ選んでいなければ先頭を選んでいる)
    fn is_readable(&self, path: &str) -> bool {
        if pages::is_view_path(path) {
            return true;
        }
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
    /// 編集しているカスタムテーマの読みにくい組み合わせ(知らせの文と組み合わせ)
    pub theme_issues: Vec<String>,
    pub theme_pairs: Vec<ipc::ContrastPair>,
    /// カスタムテーマごとに，読みにくい組み合わせがあるか(設定のファイルの customThemes と同じ並び)
    pub theme_warnings: Vec<bool>,
    /// 同期のフォルダの名前と最後に同期した時刻(出す形)
    pub sync_folder: String,
    pub last_synced: String,
    /// 項目ごとの同期の表(項目・範囲)
    pub sync_fields: Vec<Vec<String>>,
    /// キー設定の表の問題の文(無ければ空)
    pub keymap_report: String,
    /// keymap_report の先頭のうち，キーの無い確定・取り消しの行の数(注意の印と色で出す．macOS の KeymapPage の missingWarning)
    pub keymap_missing: usize,
    /// キー設定の行ごとの問題(行の印と，使われない行を薄く出すのに使う)
    pub keymap_issues: Vec<ipc::KeymapRowIssue>,
    /// キー設定の表に合うひな形(keys::PRESETS の番号．合わなければ None)
    pub keymap_preset: Option<usize>,
    /// 変換マクロを試した結果(コマンドのページを出すたびに読む)
    pub macro_preview: crate::engine::PreviewShown,
    /// 変換マクロの一覧の行ごとの，試す語と読みに当てた結果(一覧と同じ並び．行の右に控えめに添える)
    pub macro_results: Vec<String>,
    /// OS に入っている書体(外観のページを初めて開いたときに読む)
    pub fonts: Vec<InstalledFace>,
    /// 書き方のチップに添える今の値．チップの値を求める書き方(Item::sample)と値の組(読めなければ空)．
    /// ページやまとまりを切り替えたあと読み直すまでのあいだ，ほかのチップの値を出さないよう書き方で引く
    pub template_values: Vec<(&'static str, String)>,
    /// 辞書を取り込んでいる(macOS の isImportingDictionary．取り込むボタンを使えなくし，輪を回す)
    pub importing_dictionary: bool,
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
    /// 謝辞の出どころの行の中の URL(行の番号)
    Link(usize),
    /// 英語と日本語の試す欄の結果のタグ(番号)．押すと，その語をいつも英語・いつも日本語にする単語に足すメニューを出す
    PreviewChip(usize),
    /// 謝辞のライセンスの全文を開く・閉じる
    Expand,
    /// 数を 1 段減らす・増やすボタン
    Decrement,
    Increment,
    /// スライダー
    Slider,
    /// 選ぶ印(テーマ)．カードのどこを押しても選ぶ
    Radio,
    /// 一覧を切り替える部品の欄
    Segment(usize),
    /// 一覧の書き方を入れる欄の右の「{ }」のボタン(書き方のチップを開け閉めする)
    TemplateButton,
    /// 書き方のチップのまとまりの切り替え
    TemplateSegment(usize),
    /// 書き方のチップの並び(矢印で選び，Space・Enter で欄に入れる)
    TemplateChips,
    /// 1 つのカードに並べたボタン
    Button(usize),
    /// 表の下の状態で絞り込む欄(キー設定)
    Filter,
    /// 表の行を右クリックしたときのメニュー(macOS の表の contextMenu)
    RowMenu,
    /// 表の行の中の選ぶ欄(表の中の位置．列は表の選ぶ欄の列．除外設定の動作)
    TableChoice(usize),
    /// 辞書の一覧の辞書の行の部品(辞書の番号と部品)
    Entry(usize, EntryPart),
    /// 辞書の一覧の下の取り込むボタン
    Import,
    /// 押したキーで表を絞り込むボタン(キー設定．macOS の「キーで検索」)
    KeySearch,
    /// キーの欄の右の，押して記録しにくいキーと修飾キーを選ぶメニュー(キー設定．macOS の KeyField の menu)
    KeyMenu,
    /// キーを記録しているあいだ，メニューの代わりに出す「記録を停止」のボタン(macOS の KeyField の xmark)
    KeyStop,
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
    /// スライダー(今の値の文字)
    Slider(String),
    /// 選ぶ印(選んでいるか)
    Radio(bool),
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
    /// キー設定のコマンドを置ける状態(新しい行のコマンドの欄を，選んだ状態に置けるものだけにする)
    command_states: std::collections::BTreeMap<String, Vec<String>>,
    /// 打った行の形が誤っているときの文(一覧の形の invalid．上限は catalog から)
    invalid_text: String,
    section: usize,
    /// 部品を置いたカード(出さない行は None)
    card: Option<layout::CardLayout>,
    visible: bool,
    /// 名前の横の見本を出す(条件付きの見本は条件を満たすときだけ)
    shows_example: bool,
    enabled: bool,
    readable: bool,
    /// 既定に戻すボタンを出す
    resettable: bool,
    on: bool,
    /// トグルのつまみの位置(0 はオフ，1 はオン)
    knob: Tween,
    /// ドロップダウンで選んでいる番号
    choice: Option<usize>,
    /// 選択肢の後ろに足して選んだ状態にする名前(カスタムテーマを使っているときのテーマの欄．macOS と同じく，
    /// 既成のテーマのどれも選んでいないことを見せる)．選んでも何もしない
    extra_choice: Option<String>,
    /// 選択肢「自動」の名前を置き換えるもの．Jinen モデルを「自動」にしたときにエンジンが決めた大きさを添える(「自動(small)」)
    automatic_label: Option<String>,
    /// カスタムテーマの書体の欄の選択肢(選んだときに入れる値と画面に出す名前)
    font_items: Vec<(String, String)>,
    /// 数を選ぶ部品の選択肢
    numbers: Vec<f64>,
    /// 書き方のチップに添える今の値(並べているチップと同じ並び)
    lines: Vec<String>,
    text: String,
    /// text の先頭のうち，注意の印を付ける行の数(キー設定の知らせのキーの無い確定・取り消し)
    text_marks: usize,
    /// 色のボタンに出す色(「#RRGGBB」)
    color: String,
    /// カスタムテーマの行のテーマ(見本の色のタグに描く)と，読みにくい組み合わせがあるか
    custom: Option<ipc::CustomTheme>,
    warns: bool,
    /// まだカスタムテーマを作れる(複製のボタン)
    room: bool,
    /// 一覧の表
    table: Table,
    table_scroll: Scroller,
    /// 一覧の入力欄(list_spec の欄と同じ並び)
    inputs: Vec<Input>,
    /// 表の下の検索欄
    search: Option<Window>,
    /// 一覧で選んで書き換えている行(rows の番号)．追加のボタンは「更新」になり，この行を置き換える
    editing: Option<usize>,
    /// 試す欄(打つ文・前の文字列)と結果
    preview_fields: Vec<Window>,
    preview_result: crate::engine::PreviewShown,
    /// 試した結果のタグの置き場所(ページの中の座標．preview_result と同じ並び)．置くときに測る
    chip_areas: Vec<Rect>,
    /// 長い文の送り
    text_scroll: Scroller,
    /// 謝辞のライセンスの全文を開いている
    expanded: bool,
    /// 謝辞のカードの中の置き場所(ページの中の座標)
    acknowledgement: Option<AcknowledgementLayout>,
    /// スライダーを動かしているあいだの値(手を離したときに書く．macOS と同じく 1 段ごとに書かない)
    dragging: Option<f64>,
    /// 表の下の状態で絞り込む欄で選んでいる番号(0 はすべての状態)
    filter: usize,
    /// 一覧の行の数の上限(足すボタンを使えるか．上限の無い一覧は usize::MAX)
    limit: usize,
    /// 辞書の一覧の状態(辞書の一覧の行だけ)．入力欄(inputs)は開いた辞書の名前と分野
    dictionaries: Option<dictionary_rows::Rows>,
    /// 入力欄に入れたときの結果(書き方を書ける単語・変換マクロの形．入力欄のすぐ下に出す)
    result_text: String,
    result_problems: Vec<String>,
    /// 書き方のチップを開いているか(一覧の template_target)．ページごとに覚える
    template_open: bool,
    /// 書き方のチップを使えるか(単語は「入力時の値にする」がオンのときだけ．オフならボタンもチップも出さない)
    template_enabled: bool,
    /// 欄の入力位置の前で書き方を打ちかけているか(「{」を打ったら開く)
    template_typing: bool,
    /// 打ちかけの書き方に当たるチップと足し方(絞り込まないときは None)
    template_matches: Option<Vec<(reference::Item, reference::Kind)>>,
    /// キーボードで選んでいるチップ(並びの番号)
    template_cursor: usize,
    /// 書き方のチップで選んでいるまとまり(groups の番号)
    template_group: usize,
    /// 書き方のチップの切り替えの欄(ページの中の座標．arrange で置く)
    template_switch: Vec<Rect>,
    /// 書き方のチップの置き場所(チップを並べる欄の左上を 0 とする)と，その欄の左上(ページの中の座標)
    template_chips: reference::Chips,
    template_origin: (f32, f32),
    /// 押したキーで表を絞り込んでいるときのキー(整えた書き方．キー設定．macOS の KeymapPage の keyFilter)
    key_filter: Option<String>,
    /// キーを記録している欄(キー設定のキーの欄か検索欄)．欄が記録を始めた・やめたと知らせてくる
    recording: Option<Part>,
    /// キーを選ぶメニューで，ファンクションキーの一覧を出しているか
    key_functions: bool,
}

/// 謝辞のカードの中の置き場所
#[derive(Debug, Clone, Default, PartialEq)]
struct AcknowledgementLayout {
    name: Rect,
    /// 出どころの行と，行の中の URL(押せる欄)
    sources: Vec<(Rect, Option<Rect>)>,
    /// ライセンスの全文を開くボタン(全文が無ければ None)
    expand: Option<Rect>,
    /// 開いたライセンスの全文の欄
    license: Option<Rect>,
}

impl AcknowledgementLayout {
    /// 謝辞の項目を幅 width に置いたときの置き場所と高さ．(x, y) はカードの中身の左上(カードの上端)
    fn new(
        item: Option<&crate::notices::Acknowledgement>,
        (x, y, width): (f32, f32, f32),
        expanded: bool,
        measure: &dyn paint::Measure,
    ) -> (Self, f32) {
        let padding = (size::ROW_HEIGHT - size::CONTROL_HEIGHT) / 2.0;
        let Some(item) = item else {
            // 謝辞のファイルが無いときは名前(知らせ)だけを 1 行で出す
            let name = Rect::new(
                x,
                y + (size::ROW_HEIGHT - size::BODY_LINE_HEIGHT) / 2.0,
                width,
                size::BODY_LINE_HEIGHT,
            );
            return (
                Self {
                    name,
                    ..Self::default()
                },
                size::ROW_HEIGHT,
            );
        };
        let mut top = y + padding;
        let name = Rect::new(x, top, width, size::BODY_LINE_HEIGHT);
        top += size::BODY_LINE_HEIGHT + size::CARD_GAP;
        let mut sources = Vec::new();
        for line in &item.sources {
            let parts = crate::notices::split_url(line);
            // 前置きと URL が 1 行に収まれば，URL のあとの文はその下に折り返して出す
            let fits = parts.is_some_and(|(prefix, url, _)| {
                measure.width(prefix, TextStyle::Caption) + measure.width(url, TextStyle::Caption)
                    <= width
            });
            // URL のあとの文は，URL と同じ行に収まる分を続けて書き，残りを下に折り返す(macOS の文の中の Link と同じ流れ)
            let height = match parts {
                Some((prefix, url, suffix)) if fits && !suffix.trim().is_empty() => {
                    let used = measure.width(prefix, TextStyle::Caption)
                        + measure.width(url, TextStyle::Caption);
                    let (_, rest) = split_to_width(measure, suffix, width - used);
                    size::NOTE_LINE_HEIGHT
                        + if rest.trim().is_empty() {
                            0.0
                        } else {
                            measure.wrapped_height(rest.trim(), TextStyle::Caption, width)
                        }
                }
                _ => measure
                    .wrapped_height(line, TextStyle::Caption, width)
                    .max(size::NOTE_LINE_HEIGHT),
            };
            let rect = Rect::new(x, top, width, height);
            let link = parts.map(|(prefix, url, _)| {
                if fits {
                    let before = measure.width(prefix, TextStyle::Caption);
                    let length = measure.width(url, TextStyle::Caption);
                    Rect::new(x + before, top, length, size::NOTE_LINE_HEIGHT)
                } else {
                    rect
                }
            });
            sources.push((rect, link));
            top += height;
        }
        let mut expand = None;
        let mut license = None;
        if let Some(text) = &item.license {
            top += space::STACK;
            let label = measure.width(more::LICENSE_TEXT, TextStyle::Body);
            // 開く印を本文の左の端にそろえ，押せる背景は inset だけ外に広げる
            let button = Rect::new(
                x - space::INSET,
                top,
                space::INSET * 2.0 + size::CHEVRON_SIZE + space::INLINE + label,
                size::CONTROL_HEIGHT,
            );
            expand = Some(button);
            top += size::CONTROL_HEIGHT;
            if expanded {
                top += size::CONTROL_GAP;
                let inner = width - size::FIELD_PADDING_X * 2.0;
                let height = measure.wrapped_height(text, TextStyle::Mono, inner)
                    + size::FIELD_PADDING_X * 2.0;
                license = Some(Rect::new(x, top, width, height));
                top += height;
            }
        }
        top += padding;
        (
            Self {
                name,
                sources,
                expand,
                license,
            },
            top - y,
        )
    }
}

impl RowState {
    fn new(row: &Row, section: usize, catalog: &Catalog) -> Self {
        let numbers = match &row.control {
            Control::Stepper(range) | Control::Slider(range) => {
                options::steps(range.range(catalog), range.step(catalog))
            }
            Control::Seconds(range) => {
                options::steps(range.range(catalog), range.seconds_step(catalog))
            }
            _ => Vec::new(),
        };
        let text = match &row.control {
            Control::Version => text::version(env!("CARGO_PKG_VERSION")),
            _ => String::new(),
        };
        let command_states = match &row.control {
            Control::List(spec, _) if spec.path == "keymap" => {
                catalog.keymap_command_states.clone()
            }
            _ => Default::default(),
        };
        let invalid_text = row
            .control
            .list_spec()
            .map(|spec| spec.invalid.resolve(&catalog.limits).into_owned())
            .unwrap_or_default();
        Self {
            row: row.clone(),
            command_states,
            invalid_text,
            section,
            card: None,
            visible: true,
            shows_example: true,
            enabled: true,
            readable: true,
            resettable: false,
            on: false,
            knob: Tween::fixed(0.0),
            choice: None,
            extra_choice: None,
            automatic_label: None,
            font_items: Vec::new(),
            numbers,
            text,
            text_marks: 0,
            lines: Vec::new(),
            color: String::new(),
            custom: None,
            warns: false,
            room: false,
            table: Table::default(),
            table_scroll: Scroller::default(),
            inputs: Vec::new(),
            search: None,
            editing: None,
            preview_fields: Vec::new(),
            preview_result: Default::default(),
            chip_areas: Vec::new(),
            text_scroll: Scroller::default(),
            expanded: false,
            acknowledgement: None,
            dragging: None,
            filter: 0,
            limit: match &row.control {
                Control::List(_, limit) => limit.limit(catalog),
                _ => usize::MAX,
            },
            dictionaries: match row.control {
                Control::Dictionaries(list) => Some(dictionary_rows::Rows::new(list)),
                _ => None,
            },
            result_text: String::new(),
            result_problems: Vec::new(),
            template_open: false,
            template_enabled: false,
            template_typing: false,
            template_matches: None,
            template_cursor: 0,
            template_group: 0,
            template_switch: Vec::new(),
            template_chips: reference::Chips::default(),
            template_origin: (0.0, 0.0),
            key_filter: None,
            recording: None,
            key_functions: false,
        }
    }

    /// 書き方のチップの欄を出しているか(開いていて，使えるとき)
    fn template_panel_open(&self) -> bool {
        self.row.control.template_target().is_some() && self.template_open && self.template_enabled
    }

    /// 書き方のチップの欄に並べるチップと足し方．絞り込んでいれば当たるもの，でなければ選んでいるまとまり．
    /// 欄を出していなければ None
    fn template_items(&self) -> Option<Vec<(reference::Item, reference::Kind)>> {
        if !self.template_panel_open() {
            return None;
        }
        if let Some(found) = &self.template_matches {
            return Some(found.clone());
        }
        let group = self
            .row
            .control
            .template_target()?
            .groups()
            .get(self.template_group)?;
        Some(group.items.iter().map(|item| (*item, group.kind)).collect())
    }

    /// 数の部品の今の値(動かしているあいだはその値)
    fn number(&self) -> Option<f64> {
        self.dragging.or_else(|| {
            self.choice
                .and_then(|index| self.numbers.get(index).copied())
        })
    }

    /// 数の部品の値を出す文字
    fn number_text(&self, value: f64) -> String {
        match &self.row.control {
            Control::Stepper(
                RangeKind::LiveConversionSkipLength | RangeKind::EnglishSkipLength,
            ) => more::skip_length(value),
            Control::Stepper(RangeKind::SuggestionSkipCount) => more::skip_count(value),
            Control::Stepper(RangeKind::BranchSegmentsPerGroup) => {
                choice::branch_segment_count(value)
            }
            Control::Stepper(RangeKind::EmojiCandidatePosition) => {
                settings::emoji_candidate_position(value)
            }
            // 表に広げたときの大きさ(一覧の候補数の行 × 列数．行の数は値を映すときに text に入れておく)
            Control::Stepper(RangeKind::CandidateGridColumns) => {
                more::grid_size(self.text.parse().unwrap_or(0.0), value)
            }
            Control::Seconds(_) => more::seconds(value),
            _ => format!("{value}"),
        }
    }

    /// 名前(スライダーは名前に今の値を付ける．macOS の「候補の文字サイズ: 15」)
    fn title(&self) -> String {
        match (&self.row.control, self.number()) {
            (Control::Slider(RangeKind::CandidateFontSize), Some(value)) => {
                settings::font_size(value)
            }
            (Control::Slider(RangeKind::PaletteCellSize), Some(value)) => {
                crate::strings::palette::cell_size_value(value)
            }
            // カスタムテーマの行は利用者の付けた名前
            (Control::CustomTheme(_), _) => self.text.clone(),
            _ => self.row.title.to_string(),
        }
    }

    /// スライダーの値を右に出すか(秒と角の丸さ．ほかは名前に付ける)
    fn shows_value(&self) -> bool {
        matches!(
            self.row.control,
            Control::Seconds(_) | Control::Slider(RangeKind::CustomThemeCornerRadius)
        )
    }

    /// スライダーの溝の位置(値を右に出すものは値の欄を除く)
    fn slider_rect(&self) -> Option<Rect> {
        let control = self.card.as_ref()?.control;
        Some(if self.shows_value() {
            Rect::new(
                control.x,
                control.y,
                (control.width - size::SECONDS_LABEL_WIDTH - size::CONTROL_GAP).max(0.0),
                control.height,
            )
        } else {
            control
        })
    }

    /// スライダーの x の位置の値(刻みに丸める)
    fn slider_value(&self, x: f32) -> Option<f64> {
        let rect = self.slider_rect()?;
        let first = *self.numbers.first()?;
        let last = *self.numbers.last()?;
        let thumb = size::SLIDER_THUMB_SIZE;
        let width = (rect.width - thumb).max(1.0);
        let progress = f64::from(((x - rect.x - thumb / 2.0) / width).clamp(0.0, 1.0));
        let value = first + (last - first) * progress;
        Some(self.numbers[options::nearest(&self.numbers, value)])
    }

    /// スライダーのつまみの位置(0〜1)
    fn slider_progress(&self) -> f32 {
        let (Some(first), Some(last), Some(value)) =
            (self.numbers.first(), self.numbers.last(), self.number())
        else {
            return 0.0;
        };
        if last <= first {
            return 0.0;
        }
        ((value - first) / (last - first)).clamp(0.0, 1.0) as f32
    }

    /// 数を delta 段動かして書く頼み．端を越えたら端で止め，動かなければ None
    fn step(&mut self, delta: isize) -> Option<Event> {
        let index = self.choice?;
        let last = self.numbers.len().checked_sub(1)?;
        let next = index.saturating_add_signed(delta).min(last);
        if next == index {
            return None;
        }
        self.choice = Some(next);
        Some(Event::Set {
            path: self.row.path,
            value: crate::model::number(self.numbers[next]),
            clears: self.row.clears,
        })
    }

    /// 表の下のボタンの数(ファイルのボタンを除く)
    fn bottom_count(&self) -> usize {
        self.row
            .control
            .list_buttons()
            .map_or(0, |buttons| buttons.bottom.len())
    }

    /// 表の下のファイルのボタンの操作(index は表の下のボタンの通し番号)
    fn file_task(&self, index: usize) -> Option<crate::files::FileTask> {
        let files = self.row.control.list_buttons()?.files?;
        let position = index.checked_sub(self.bottom_count())?;
        (position < 2).then(|| files.task(position))
    }

    /// 謝辞の項目(番号が無ければ None)
    fn notice(&self) -> Option<&'static crate::notices::Acknowledgement> {
        match self.row.control {
            Control::Acknowledgement(index) => crate::notices::installed().get(index),
            _ => None,
        }
    }

    fn list_spec(&self) -> Option<(&ListSpec, LimitKind)> {
        match &self.row.control {
            Control::List(spec, limit) => Some((spec, *limit)),
            Control::Dictionary(spec) => Some((spec, LimitKind::UserDictionaryEntries)),
            // 記号の上限はエンジンが確かめ，項目ごとの同期は足さないので，上限は使わない
            Control::Symbols(_, spec) | Control::SyncFields(spec) => {
                Some((spec, LimitKind::ProfileRules))
            }
            _ => None,
        }
    }

    /// 押したキーで絞り込んでいるときに，「キーで検索」の代わりに出すチップの文字(キーの名前)
    fn key_chip(&self) -> Option<String> {
        self.key_filter.as_deref().map(crate::keys::display)
    }

    /// 表を押したキー(key_filter)の行だけにする．表のキーの列と同じ書き方で比べる
    fn restrict_key(&mut self) {
        let cell = self
            .key_filter
            .as_deref()
            .and_then(crate::keys::filter_cell);
        self.table
            .restrict(pages::KEYMAP_KEY_FIELD, cell.as_deref());
    }

    /// 押したキーでの絞り込みを変える(None で外す)．表を絞り直し，選んだ行と書き換えを外して，先頭に戻す
    fn set_key_filter(&mut self, notation: Option<&str>) {
        self.key_filter = notation.and_then(crate::keys::canonical);
        self.restrict_key();
        self.editing = None;
        let content = self.table.len() as f32 * size::TABLE_ROW_HEIGHT;
        let viewport = table_viewport(self);
        self.table_scroll.set_extent(content, viewport);
        self.table_scroll.jump_to(0.0);
    }

    /// 欄の枠の中の右の端にボタンを置く欄か(キー設定のキーの欄．キーを選ぶメニューと「記録を停止」)
    fn holds_key_button(&self, part: Part) -> bool {
        let field = self
            .row
            .control
            .list_buttons()
            .and_then(|buttons| buttons.key_menu);
        matches!(part, Part::Field(index) if Some(index) == field)
            && self
                .card
                .as_ref()
                .is_some_and(|card| card.key_button.is_some())
    }

    /// 欄の枠(ページの中の座標)．枠の中にボタンを置く欄は，ボタンまでを 1 つの枠にする
    fn field_frame(&self, part: Part) -> Option<Rect> {
        let rect = self.part_rect(part)?;
        let button = self
            .card
            .as_ref()
            .and_then(|card| card.key_button)
            .filter(|_| self.holds_key_button(part));
        Some(match button {
            Some(button) => Rect::new(rect.x, rect.y, button.max_x() - rect.x, rect.height),
            None => rect,
        })
    }

    /// キーを選ぶメニューを添える欄(キー設定のキーの欄)の窓
    fn key_window(&self) -> Option<Window> {
        let field = self.row.control.list_buttons()?.key_menu?;
        self.edit(Part::Field(field))
    }

    /// キーを選ぶメニューに並べる項目(ファンクションキーの一覧を出しているあいだはその一覧)
    fn key_choices(&self) -> Vec<crate::keys::KeyChoice> {
        if self.key_functions {
            return crate::keys::function_choices();
        }
        let current = self.key_window().map(ffi::window_text).unwrap_or_default();
        crate::keys::key_choices(&current)
    }

    /// 入力欄・追加・削除のある一覧か(項目ごとの同期は違う)
    fn has_add_remove(&self) -> bool {
        self.list_spec().is_some() && !matches!(self.row.control, Control::SyncFields(_))
    }

    /// 表の行を右クリックしたときのメニューの項目(macOS の RuleListEditor・KeymapPage の contextMenu)．
    /// 1 行だけ選んでいれば編集，選んだ行があれば削除，キー設定は複製も
    fn row_menu(&self) -> Vec<RowMenuItem> {
        if !self.has_add_remove() || !self.enabled {
            return Vec::new();
        }
        let selected = self.table.selected_rows();
        let mut items = Vec::new();
        if selected.len() == 1 {
            items.push(RowMenuItem::Edit);
        }
        if !selected.is_empty() {
            // 複製は，選んだ行をそれぞれ元の行のすぐ下に足す(何行でも)
            if self
                .row
                .control
                .list_spec()
                .is_some_and(|spec| spec.path == "keymap")
            {
                items.push(RowMenuItem::Duplicate);
            }
            items.push(RowMenuItem::Remove);
        }
        items
    }

    /// 選んだ行を消すボタン(足す一覧の表の下の「削除」)
    pub fn remove_part(&self) -> Option<Part> {
        if !self.has_add_remove() {
            return None;
        }
        let buttons = self.row.control.list_buttons()?;
        buttons
            .bottom
            .iter()
            .position(|label| list_button(label) == ListButton::Remove)
            .map(Part::Bottom)
    }

    /// 表の下の index 番目のボタンの役割(ファイルのボタンは除く)
    fn list_button(&self, index: usize) -> Option<ListButton> {
        let buttons = self.row.control.list_buttons()?;
        buttons.bottom.get(index).map(|label| list_button(label))
    }

    /// 一覧の上に並べる欄の数と，表の下の帯に置く欄の数
    fn field_counts(&self) -> (usize, usize) {
        let fields = self
            .row
            .control
            .list_spec()
            .map_or(0, |spec| spec.fields.len());
        match self.row.control.list_buttons() {
            Some(buttons) => {
                let top = buttons.top_fields(fields);
                (top, buttons.input_fields(fields) - top)
            }
            None => (fields, 0),
        }
    }

    /// 選んだ 1 行を offset だけ動かせるか(除外設定の優先度)
    fn can_move(&self, offset: isize) -> bool {
        if !self.row.control.reorderable() {
            return false;
        }
        let selected = self.table.selected_rows();
        let [index] = selected.as_slice() else {
            return false;
        };
        index
            .checked_add_signed(offset)
            .is_some_and(|target| target < self.table.total())
    }

    /// 表の選ぶ欄の列(表の列の番号と，行の値の何番目か)
    fn choice_column(&self) -> Option<(usize, usize)> {
        self.row
            .control
            .table_layout()
            .columns
            .iter()
            .enumerate()
            .find(|(_, column)| column.cell == Cell::Choice)
            .map(|(index, column)| (index, column.source))
    }

    /// 表の position 番目の行の選ぶ欄の位置(ページの中の座標．送った位置)
    fn table_choice_rect(&self, position: usize) -> Option<Rect> {
        let rect = self.part_rect(Part::Table)?;
        let (column, _) = self.choice_column()?;
        let layout = self.row.control.table_layout();
        let (left, width) = *layout
            .spans(rect.width, size::FIELD_PADDING_X)
            .get(column)?;
        let top = rect.y + size::TABLE_HEADER_HEIGHT + position as f32 * size::TABLE_ROW_HEIGHT
            - self.table_scroll.target();
        let inset = size::TABLE_ROW_INSET;
        Some(Rect::new(
            rect.x + left - size::FIELD_PADDING_X,
            top + inset,
            width,
            size::TABLE_ROW_HEIGHT - inset * 2.0,
        ))
    }

    /// 入力欄の値(選ぶ欄は設定のファイルに書く値)
    /// 打った行の確かめの文と，足せない問題か(macOS の RuleListEditor の message)．
    /// 形が誤っていれば理由，同じ見分ける欄の行があれば上書きすること，同じ行があれば登録済みであること
    fn input_message(&self) -> Option<(String, bool)> {
        let spec = self.row.control.list_spec()?;
        if !self.has_add_remove() {
            return None;
        }
        let values = self.input_values();
        if !spec.is_filled(&values) || values.iter().all(|value| value.trim().is_empty()) {
            return None;
        }
        let item = spec.make(&values);
        if !spec.is_valid(&item) {
            return Some((self.invalid_text.clone(), true));
        }
        // キー設定は，同じ状態・同じキーの行と，文字を打てなくなるキーを知らせる(足すことはできる．macOS の KeymapPage の draftNote)
        if spec.path == "keymap" {
            let entries: Vec<(String, String, String)> = self
                .table
                .rows()
                .iter()
                .map(|cells| crate::keys::entry_of(cells))
                .collect();
            let note =
                crate::keys::draft_note(item.first()?, item.get(1)?, &entries, self.editing)?;
            return Some((note.text(), false));
        }
        let shown = spec.display(&item);
        let fields = spec.fields.len();
        let others: Vec<&Vec<String>> = self
            .table
            .rows()
            .iter()
            .enumerate()
            .filter(|(index, _)| Some(*index) != self.editing)
            .map(|(_, row)| row)
            .collect();
        let same_row =
            |row: &&Vec<String>, count: usize| row.iter().take(count).eq(shown.iter().take(count));
        if matches!(self.row.control, Control::Dictionary(_)) {
            // ユーザー辞書は読みと単語の両方が同じ行を重なりとみなす
            let same = others.iter().find(|row| same_row(row, 2))?;
            return Some(if same.iter().take(fields).eq(shown.iter().take(fields)) {
                (rule_list::ALREADY_REGISTERED.to_string(), true)
            } else {
                (rule_list::CHANGES_KIND.to_string(), false)
            });
        }
        let keys: Vec<usize> = spec
            .fields
            .iter()
            .enumerate()
            .filter(|(_, field)| field.key)
            .map(|(index, _)| index)
            .collect();
        if keys.is_empty() {
            return None;
        }
        let collides = others.iter().any(|row| {
            keys.iter()
                .all(|index| row.get(*index) == shown.get(*index))
        });
        collides.then(|| {
            let key = item.first().cloned().unwrap_or_default();
            (rule_list::overwrites(&key), false)
        })
    }

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
    /// 行の書き換えをやめ，入力欄を空に戻す
    fn cancel_edit(&mut self) {
        let defaults: Vec<usize> = self
            .row
            .control
            .list_spec()
            .map(|spec| {
                spec.fields
                    .iter()
                    .map(|field| field.default_choice)
                    .collect()
            })
            .unwrap_or_default();
        for (index, input) in self.inputs.iter_mut().enumerate() {
            match input {
                Input::Edit(window) => ffi::set_text(*window, ""),
                Input::Choice(selected) => *selected = defaults.get(index).copied().unwrap_or(0),
            }
        }
        self.editing = None;
    }

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
        let (fields, bottom_fields) = self.field_counts();
        let buttons = self.row.control.list_buttons();
        let top = buttons.map_or(0, |buttons| buttons.top.len());
        let search = buttons.is_some_and(|buttons| buttons.search);
        let filter = buttons.is_some_and(|buttons| buttons.filter);
        let stepper_button = |index: f32| {
            let width = size::STEPPER_BUTTON_WIDTH;
            let control = card.control;
            Rect::new(
                control.max_x() - width * (2.0 - index),
                control.y,
                width,
                control.height,
            )
        };
        match part {
            Part::Reset => Some(card.reset),
            // 行のメニューは押した位置に出すので，部品の欄は持たない
            Part::RowMenu => None,
            Part::KeySearch => card.parts.last().copied(),
            Part::KeyMenu | Part::KeyStop => card.key_button,
            // 更新を確かめるボタン・値の右のボタンは部品の欄の外
            Part::Action
                if matches!(self.row.control, Control::Version | Control::InfoAction(..)) =>
            {
                card.parts.first().copied()
            }
            Part::Decrement => Some(stepper_button(0.0)),
            Part::Increment => Some(stepper_button(1.0)),
            Part::Slider => self.slider_rect(),
            // カスタムテーマの行は右のボタンを除いたところを押して選ぶ
            Part::Radio => Some(match self.row.control {
                Control::CustomTheme(_) => {
                    let right = card
                        .parts
                        .first()
                        .map_or(card.card.max_x(), |button| button.x);
                    Rect::new(
                        card.card.x,
                        card.card.y,
                        right - card.card.x,
                        card.card.height,
                    )
                }
                _ => card.card,
            }),
            Part::TemplateButton => card.template_button,
            Part::TemplateSegment(index) => self.template_switch.get(index).copied(),
            // 書き方のチップを並べる欄(切り替えの下)
            Part::TemplateChips => card.template_panel.map(|panel| {
                Rect::new(
                    self.template_origin.0,
                    self.template_origin.1,
                    panel.width,
                    self.template_chips.height,
                )
            }),
            Part::Segment(index) | Part::Button(index) => card.parts.get(index).copied(),
            Part::Filter => filter
                .then(|| card.parts.get(fields + top + usize::from(search)).copied())
                .flatten(),
            Part::Link(index) => self
                .acknowledgement
                .as_ref()
                .and_then(|layout| layout.sources.get(index))
                .and_then(|(_, link)| *link),
            Part::Expand => self
                .acknowledgement
                .as_ref()
                .and_then(|layout| layout.expand),
            Part::PreviewChip(index) => self.chip_areas.get(index).copied(),
            Part::Entry(index, part) => self.dictionaries.as_ref()?.part_rect(index, part),
            Part::Import => card.parts.first().copied(),
            Part::Toggle
            | Part::Dropdown
            | Part::Action
            | Part::Color
            | Part::Table
            | Part::Text => Some(card.control),
            // 表の下の帯に置く欄は，検索欄・絞り込みのあと，下のボタンの前
            Part::Field(index) if index >= fields => card
                .parts
                .get(fields + top + usize::from(search) + usize::from(filter) + index - fields)
                .copied(),
            Part::Field(index) | Part::PreviewField(index) => card.parts.get(index).copied(),
            Part::TableChoice(position) => self.table_choice_rect(position),
            Part::Top(index) => card.parts.get(fields + index).copied(),
            Part::Search => search
                .then(|| card.parts.get(fields + top).copied())
                .flatten(),
            Part::Bottom(index) => card
                .parts
                .get(
                    fields
                        + top
                        + usize::from(search)
                        + usize::from(filter)
                        + bottom_fields
                        + index,
                )
                .copied(),
        }
    }

    /// 行の押せる部品(フォーカスの順)
    fn parts(&self) -> Vec<Part> {
        let mut parts = Vec::new();
        match &self.row.control {
            Control::Toggle => parts.push(Part::Toggle),
            Control::Choice(_) | Control::ThemeFont(_) => parts.push(Part::Dropdown),
            Control::Stepper(_) => parts.extend([Part::Decrement, Part::Increment]),
            Control::Seconds(_) | Control::Slider(_) => parts.push(Part::Slider),
            Control::ThemeOption(_) => parts.push(Part::Radio),
            Control::CustomTheme(_) => {
                parts.push(Part::Radio);
                parts.extend((0..ThemeAction::ROW.len()).map(Part::Button));
            }
            Control::Segmented(choices) => parts.extend((0..choices.len()).map(Part::Segment)),
            Control::Buttons(buttons) => parts.extend((0..buttons.len()).map(Part::Button)),
            Control::Action(_)
            | Control::LabeledAction(..)
            | Control::Version
            | Control::InfoAction(..) => parts.push(Part::Action),
            Control::Acknowledgement(_) => {
                if let Some(item) = self.notice() {
                    parts.extend(
                        item.sources
                            .iter()
                            .enumerate()
                            .filter(|(_, line)| crate::notices::split_url(line).is_some())
                            .map(|(index, _)| Part::Link(index)),
                    );
                    if item.license.is_some() {
                        parts.push(Part::Expand);
                    }
                }
            }
            Control::Color => parts.push(Part::Color),
            // ひな形は 1 つのメニューで，選ぶと読み込む(macOS の KeymapPage のひな形のメニュー)
            Control::Preset => parts.push(Part::Dropdown),
            Control::KeymapReport => parts.push(Part::Text),
            Control::TextField => parts.push(Part::Field(0)),
            Control::Dictionaries(_) => {
                if let Some(rows) = &self.dictionaries {
                    parts.extend(
                        rows.placement
                            .parts
                            .iter()
                            .map(|(index, part, _)| Part::Entry(*index, *part)),
                    );
                }
                parts.push(Part::Import);
            }
            Control::Preview(kind) => {
                parts.extend([Part::PreviewField(0), Part::PreviewField(1)]);
                if *kind == TryKind::Language {
                    parts.extend((0..self.chip_areas.len()).map(Part::PreviewChip));
                }
            }
            control => {
                if let (Some(_), Some(buttons)) = (control.list_spec(), control.list_buttons()) {
                    let (fields, bottom_fields) = self.field_counts();
                    // 添え書きの欄(2 行目)は書き方のチップの欄の下にあるので，フォーカスもチップのあと
                    let note = buttons.note_line && fields >= 2;
                    let first_line = fields - usize::from(note);
                    let button = self
                        .card
                        .as_ref()
                        .is_some_and(|card| card.template_button.is_some());
                    for index in 0..first_line {
                        parts.push(Part::Field(index));
                        if button && buttons.template_field == Some(index) {
                            parts.push(Part::TemplateButton);
                        }
                        // キーの欄の右は，記録しているあいだは「記録を停止」，ほかはキーを選ぶメニュー
                        if buttons.key_menu == Some(index) {
                            parts.push(if self.recording == Some(Part::Field(index)) {
                                Part::KeyStop
                            } else {
                                Part::KeyMenu
                            });
                        }
                    }
                    // キャンセル(上の 2 つ目)は書き換えているあいだだけ出す
                    let editing = self.editing.is_some();
                    parts.extend(
                        (0..buttons.top.len())
                            .filter(|index| !(*index == 1 && self.has_add_remove() && !editing))
                            .map(Part::Top),
                    );
                    if self.template_panel_open() {
                        // 打ちかけの書き方で絞り込んでいるあいだは，切り替えを出さない
                        if self.template_matches.is_none() {
                            let groups = control
                                .template_target()
                                .map_or(0, |target| target.groups().len());
                            parts.extend((0..groups).map(Part::TemplateSegment));
                        }
                        if !self.template_chips.chips.is_empty() {
                            parts.push(Part::TemplateChips);
                        }
                    }
                    if note {
                        parts.push(Part::Field(first_line));
                    }
                    parts.push(Part::Table);
                    if buttons.search {
                        parts.push(Part::Search);
                    }
                    if buttons.filter {
                        parts.push(Part::Filter);
                    }
                    if buttons.toolbar {
                        parts.push(Part::KeySearch);
                    }
                    parts.extend((fields..fields + bottom_fields).map(Part::Field));
                    parts.extend((0..buttons.bottom_labels().len()).map(Part::Bottom));
                }
            }
        }
        // 既定に戻すボタンは部品の右にあるので，フォーカスも部品のあと
        if self.resettable {
            parts.push(Part::Reset);
        }
        parts
    }

    /// 部品を使えるか(選んだ行に効くボタンは，行を選ぶまで使えない)
    fn part_enabled(&self, part: Part) -> bool {
        if !self.enabled {
            return false;
        }
        let selected = !self.table.selected_positions().is_empty();
        let fields = {
            let (top, bottom) = self.field_counts();
            top + bottom
        };
        match part {
            Part::Entry(index, part) => self
                .dictionaries
                .as_ref()
                .is_some_and(|rows| rows.part_enabled(index, part)),
            Part::Import => self.dictionaries.as_ref().is_some_and(|rows| !rows.busy),
            Part::Decrement => self.choice.is_some_and(|index| index > 0),
            Part::Increment => self
                .choice
                .is_some_and(|index| index + 1 < self.numbers.len()),
            // 読み込むボタンはいつでも使える．書き出すボタンは書き出す行があるときだけ(macOS と同じ)
            Part::Bottom(index) if self.file_task(index).is_some() => self
                .file_task(index)
                .is_some_and(|task| task.is_import() || self.table.total() > 0),
            // 打った行に問題があれば足せない(macOS の RuleListEditor)
            Part::Top(0) if self.has_add_remove() => {
                (self.editing.is_some()
                    || self
                        .list_spec()
                        .is_some_and(|(spec, _)| spec.is_filled(&self.input_values())))
                    && !self.input_message().is_some_and(|(_, problem)| problem)
            }
            // キャンセルは書き換えているあいだ，削除は行を選んでいるとき
            Part::Top(1) if self.has_add_remove() => self.editing.is_some(),
            Part::Bottom(index) => match self.list_button(index) {
                Some(ListButton::Remove | ListButton::Duplicate) => selected,
                Some(ListButton::Edit) => self.table.selected_positions().len() == 1,
                Some(ListButton::Add) => self.table.total() < self.limit,
                Some(ListButton::MoveUp) => self.can_move(-1),
                Some(ListButton::MoveDown) => self.can_move(1),
                Some(ListButton::Always) => true,
                None => selected,
            },
            Part::TableChoice(position) => position < self.table.len(),
            Part::Field(index) => index < fields || self.row.control == Control::TextField,
            // カスタムテーマの複製は上限まで作ったら使えない(macOS と同じ)
            Part::Button(1) if matches!(self.row.control, Control::CustomTheme(_)) => self.room,
            _ => true,
        }
    }

    /// ボタンの名前(追加のボタンは書き換えているあいだ「更新」)
    fn button_label(&self, part: Part) -> &'static str {
        let buttons = self.row.control.list_buttons();
        match part {
            Part::KeySearch => keys::SEARCH_BY_KEY,
            Part::KeyMenu => keys::CHOOSE_KEY,
            Part::KeyStop => keys::STOP_RECORDING,
            Part::Top(0) if self.has_add_remove() && self.editing.is_some() => rule_list::UPDATE,
            Part::Top(index) => buttons
                .and_then(|buttons| buttons.top.get(index).copied())
                .unwrap_or(""),
            Part::Bottom(index) => buttons
                .and_then(|buttons| buttons.bottom_labels().get(index).copied())
                .unwrap_or(""),
            Part::Action => match self.row.control {
                Control::Version => more::CHECK_FOR_UPDATES,
                Control::LabeledAction(_, label) | Control::InfoAction(_, _, label) => label,
                _ => self.row.title,
            },
            Part::Button(index) => match self.row.control {
                Control::Buttons(buttons) => buttons.get(index).map_or("", |(label, _)| label),
                Control::CustomTheme(_) => match ThemeAction::ROW.get(index) {
                    Some(ThemeAction::Edit) => more::EDIT_THEME,
                    Some(ThemeAction::Duplicate) => more::DUPLICATE_THEME,
                    Some(_) => more::DELETE_THEME,
                    None => "",
                },
                _ => "",
            },
            Part::Segment(index) => match self.row.control {
                Control::Segmented(choices) => choices.get(index).map_or("", |(_, label)| label),
                _ => "",
            },
            Part::TemplateSegment(index) => self
                .row
                .control
                .template_target()
                .and_then(|target| target.groups().get(index))
                .map_or("", |group| group.title),
            Part::TemplateButton => crate::strings::templates::BUTTON,
            Part::Link(index) => self
                .notice()
                .and_then(|item| item.sources.get(index))
                .and_then(|line| crate::notices::split_url(line))
                .map_or("", |(_, url, _)| url),
            Part::Expand => more::LICENSE_TEXT,
            _ => "",
        }
    }

    /// ドロップダウンの選択肢の名前
    fn dropdown_items(&self, part: Part) -> Vec<String> {
        if part == Part::RowMenu {
            return self
                .row_menu()
                .iter()
                .map(|item| item.label().to_string())
                .collect();
        }
        if part == Part::KeyMenu {
            let current = self.key_window().map(ffi::window_text).unwrap_or_default();
            return self
                .key_choices()
                .iter()
                .map(|choice| crate::keys::choice_label(choice, &current))
                .collect();
        }
        match (&self.row.control, part) {
            (Control::ThemeFont(_), Part::Dropdown) => self
                .font_items
                .iter()
                .map(|(_, label)| label.clone())
                .collect(),
            (Control::Choice(choices), Part::Dropdown) => choices
                .iter()
                .map(|(value, name)| match (&self.automatic_label, *value) {
                    (Some(label), "automatic") => label.clone(),
                    _ => (*name).to_string(),
                })
                .chain(self.extra_choice.clone())
                .collect(),
            (_, Part::Filter) => std::iter::once(keys::ALL_STATES)
                .chain(keys::STATES.iter().map(|(_, label)| *label))
                .map(str::to_string)
                .collect(),
            (Control::Preset, Part::Dropdown) => keys::PRESETS
                .iter()
                .map(|(_, name)| (*name).to_string())
                .collect(),
            (Control::Dictionaries(_), Part::Entry(_, EntryPart::Condition)) => {
                DICTIONARY_CONDITIONS
                    .iter()
                    .map(|(_, name)| (*name).to_string())
                    .collect()
            }
            (control, Part::Field(index)) => control
                .list_spec()
                .and_then(|spec| spec.fields.get(index))
                .and_then(|field| field.choices)
                .map(|choices| {
                    self.choice_positions(index)
                        .iter()
                        .filter_map(|position| choices.get(*position))
                        .map(|(_, name)| (*name).to_string())
                        .collect()
                })
                .unwrap_or_default(),
            (control, Part::TableChoice(_)) => self
                .choice_column()
                .and_then(|(_, source)| control.list_spec()?.fields.get(source))
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
            Part::Filter => Some(self.filter),
            Part::Field(index) => match self.inputs.get(index) {
                Some(Input::Choice(selected)) => self
                    .choice_positions(index)
                    .iter()
                    .position(|position| position == selected),
                _ => None,
            },
            Part::Entry(index, EntryPart::Condition) => {
                self.dictionaries.as_ref()?.condition_index(index)
            }
            // 表に出している名前から選んでいるものを引く
            Part::TableChoice(position) => {
                let (_, source) = self.choice_column()?;
                let label = self.table.shown_row(position)?.get(source)?;
                self.dropdown_items(part)
                    .iter()
                    .position(|item| item == label)
            }
            _ => None,
        }
    }

    /// 選ぶ欄に出す選択肢(選択肢の番号の並び)．キー設定のコマンドの欄は，選んだ状態に置けるものだけにする
    /// (macOS の KeymapPage の commandPicker)．ほかの欄はすべて
    fn choice_positions(&self, index: usize) -> Vec<usize> {
        let Some(spec) = self.row.control.list_spec() else {
            return Vec::new();
        };
        let Some(choices) = spec.fields.get(index).and_then(|field| field.choices) else {
            return Vec::new();
        };
        if spec.path != "keymap" || index != KEYMAP_COMMAND || self.command_states.is_empty() {
            return (0..choices.len()).collect();
        }
        let state = self.keymap_state();
        (0..choices.len())
            .filter(|position| self.command_available(choices[*position].0, state))
            .collect()
    }

    /// 新しい行の状態の値(キー設定)
    fn keymap_state(&self) -> &'static str {
        let states = self
            .row
            .control
            .list_spec()
            .and_then(|spec| spec.fields.first())
            .and_then(|field| field.choices)
            .unwrap_or(&[]);
        match self.inputs.first() {
            Some(Input::Choice(selected)) => states.get(*selected).map_or("", |(value, _)| value),
            _ => "",
        }
    }

    /// command を state の行に置けるか(KeymapCommand.isAvailable(in:))
    fn command_available(&self, command: &str, state: &str) -> bool {
        state == KEYMAP_ANYWHERE
            || self
                .command_states
                .get(command)
                .is_none_or(|states| states.iter().any(|value| value == state))
    }

    /// 部品が選ぶ欄か
    fn is_dropdown(&self, part: Part) -> bool {
        match part {
            Part::Dropdown
            | Part::Filter
            | Part::KeyMenu
            | Part::TableChoice(_)
            | Part::Entry(_, EntryPart::Condition) => true,
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
            // 開いた辞書の名前と分野の欄(開いた辞書は 1 つだけなので，欄も 1 組)
            Part::Entry(index, part @ (EntryPart::Name | EntryPart::Field)) => {
                if self.dictionaries.as_ref()?.expanded_index() != Some(index) {
                    return None;
                }
                let position = usize::from(part == EntryPart::Field);
                match self.inputs.get(position) {
                    Some(Input::Edit(window)) => Some(*window),
                    _ => None,
                }
            }
            _ => None,
        }
    }

    /// 辞書の一覧の部品を押した
    fn activate_dictionary(&mut self, list: DictionaryList, part: Part, now: f64) -> Option<Event> {
        let rows = self.dictionaries.as_mut()?;
        let event = |action, index| {
            Some(Event::DictionaryList {
                list,
                action,
                index,
            })
        };
        let (index, part) = match part {
            Part::Import => return event(DictionaryAction::Import, None),
            Part::Entry(index, part) => (index, part),
            _ => return None,
        };
        let entry = rows.entries.get(index)?.clone();
        let action = match part {
            EntryPart::Expand => {
                // 開くのは 1 つだけ．開いたら名前と分野を欄に入れる
                let open = rows.expanded_index() == Some(index);
                rows.expanded = (!open).then(|| entry.id.clone());
                if !open {
                    let texts = [&entry.name, &entry.field];
                    for (input, text) in self.inputs.iter().zip(texts) {
                        if let Input::Edit(window) = input {
                            ffi::set_text(*window, text);
                        }
                    }
                }
                return Some(Event::Relayout);
            }
            EntryPart::Toggle => {
                if let Some(knob) = rows.knobs.get_mut(index) {
                    let target = if entry.is_enabled { 0.0 } else { 1.0 };
                    knob.retarget(target, now, f64::from(motion::TOGGLE), Easing::STANDARD);
                }
                DictionaryAction::Toggle
            }
            EntryPart::MoveUp => DictionaryAction::MoveUp,
            EntryPart::MoveDown => DictionaryAction::MoveDown,
            EntryPart::AddApp => DictionaryAction::ChooseApps,
            EntryPart::RemoveApp(app) => DictionaryAction::RemoveApp(app),
            EntryPart::Reimport => DictionaryAction::Reimport,
            EntryPart::Remove => DictionaryAction::Remove,
            // 打つ欄は窓が受け取り，使う場面の欄はドロップダウンで選ぶ(choose)
            EntryPart::Name | EntryPart::Field | EntryPart::Condition => return None,
        };
        event(action, Some(index))
    }

    /// 辞書の一覧の打つ欄が変わった(macOS と同じく打つたびに書く．今の値と同じなら書かない)
    fn dictionary_edited(&self, list: DictionaryList, part: Part) -> Option<Event> {
        let Part::Entry(index, entry_part) = part else {
            return None;
        };
        let rows = self.dictionaries.as_ref()?;
        let entry = rows.entries.get(index)?;
        let typed = self.edit(part).map(ffi::window_text)?;
        let action = match entry_part {
            EntryPart::Name if typed.trim() != entry.name => DictionaryAction::Rename(typed),
            EntryPart::Field if typed.trim() != entry.field => DictionaryAction::SetField(typed),
            _ => return None,
        };
        Some(Event::DictionaryList {
            list,
            action,
            index: Some(index),
        })
    }
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
    /// 書き方のチップの上でポインターを載せているチップ(行の番号と並びの番号)
    template_hover: Option<(usize, usize)>,
    /// 中身の幅(DIP)
    width: f32,
    /// 見本(外観・パレット・絵文字)を描いた大きさ(DIP)．見本の行の高さを決める
    preview_size: Option<(f32, f32)>,
    /// ページの題を描く(カスタムテーマの編集の画面は題の代わりに見本を上に留めるので描かない)
    titled: bool,
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
            Availability::Ready => pages::with_custom_theme_rows(
                pages::sections(page).unwrap_or_default(),
                catalog.limits.custom_themes,
            ),
            Availability::Loading | Availability::Unavailable => Vec::new(),
        };
        Self::with_sections(parent, font, pool, page, sections, catalog, availability)
    }

    /// 項目の並びを決めて作る(カスタムテーマの編集の画面．page は左の一覧で選んでおくページ)
    pub fn with_sections(
        parent: Window,
        font: &ffi::Font,
        pool: &mut Vec<Window>,
        page: Page,
        sections: Vec<Section>,
        catalog: &Catalog,
        availability: Availability,
    ) -> Self {
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
            template_hover: None,
            width: 0.0,
            preview_size: None,
            titled: true,
        }
    }

    /// ページの題を描かない(カスタムテーマの編集の画面)
    pub fn untitled(mut self) -> Self {
        self.titled = false;
        self
    }

    /// 試した語(word)を，いつも英語(english)・いつも日本語にする単語の一覧に足す．もう一方の一覧にあれば移す(ListSpec.exclusive_with)
    pub fn word_list_add(&self, word: String, english: bool) -> Option<Event> {
        let path = if english {
            "wordLanguage.englishWords"
        } else {
            "wordLanguage.japaneseWords"
        };
        let (spec, limit) = self.rows.iter().find_map(|row| match &row.row.control {
            Control::List(spec, limit) if spec.path == path => Some((*spec, *limit)),
            _ => None,
        })?;
        Some(Event::ListAdd {
            spec,
            limit,
            item: vec![word],
            replacing: None,
        })
    }

    /// ページにある見本の種類(外観・パレット・絵文字)．見本が無ければ None
    pub fn preview_kind(&self) -> Option<PreviewKind> {
        self.rows.iter().find_map(|row| match row.row.control {
            Control::ThemePreview => Some(PreviewKind::Theme),
            Control::PalettePreview => Some(PreviewKind::Palette),
            Control::EmojiPreview => Some(PreviewKind::Emoji),
            _ => None,
        })
    }

    /// 見本を描いた大きさを決める(次に置くときに見本の行の高さにする)
    pub fn set_preview_size(&mut self, size: Option<(f32, f32)>) {
        self.preview_size = size;
    }

    /// 標準の EDIT の窓を隠して pool に返す(次のページで使い回す)
    /// バージョンの行に，更新の進み具合(None ならバージョン)を出す
    pub fn set_version_status(&mut self, status: Option<String>) {
        for row in &mut self.rows {
            if row.row.control == Control::Version {
                row.text = status
                    .clone()
                    .unwrap_or_else(|| text::version(env!("CARGO_PKG_VERSION")));
            }
        }
    }

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
                && (row.row.control != Control::KeymapReport || !extras.keymap_report.is_empty());
            row.shows_example = row.row.example_visible.is_none_or(condition);
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
                Control::ThemeFont(part) => {
                    let (items, choice) =
                        font_items(*part, &extras.fonts, &values.text(row.row.path));
                    row.visible &= !items.is_empty();
                    row.font_items = items;
                    row.choice = choice;
                }
                Control::Choice(choices) => {
                    row.automatic_label = (row.row.path == JINEN_MODEL_PATH)
                        .then(|| values.text(AUTOMATIC_JINEN_MODEL))
                        .filter(|variant| !variant.is_empty())
                        .map(|value| {
                            // 決めた結果の値(small・xsmall・off)を，選択肢の名前(「使わない」など)にする
                            let name = options::JINEN_MODELS
                                .iter()
                                .find(|(choice, _)| *choice == value)
                                .map_or(value.as_str(), |(_, name)| name);
                            format!("{}({name})", text::JINEN_AUTOMATIC_WITH)
                        });
                    row.extra_choice = (row.row.path == crate::themes::BASE_THEME)
                        .then(|| {
                            crate::themes::active_name(
                                values.value(crate::themes::THEMES),
                                &values.text(crate::themes::ACTIVE),
                            )
                        })
                        .flatten();
                    row.choice = Some(match row.extra_choice {
                        Some(_) => choices.len(),
                        None => options::index_of(choices, &values.text(row.row.path)),
                    });
                }
                Control::Stepper(_) | Control::Seconds(_) | Control::Slider(_) => {
                    let value = values
                        .value(row.row.path)
                        .and_then(Value::as_f64)
                        .unwrap_or(0.0);
                    row.choice = Some(options::nearest(&row.numbers, value));
                    if row.row.control == Control::Stepper(RangeKind::CandidateGridColumns) {
                        let rows = values
                            .value("listCandidatesPerPage")
                            .and_then(Value::as_f64)
                            .unwrap_or(0.0);
                        row.text = format!("{rows}");
                    }
                }
                Control::ThemeOption(value) => {
                    // カスタムテーマを使っているときは，既成のテーマのどれも選ばない(macOS と同じ)
                    let custom = crate::themes::active_name(
                        values.value(crate::themes::THEMES),
                        &values.text(crate::themes::ACTIVE),
                    );
                    row.on = custom.is_none()
                        && options::index_of(options::THEMES, &values.text(row.row.path))
                            == options::index_of(options::THEMES, value);
                }
                Control::Segmented(choices) => {
                    row.choice = Some(options::index_of(choices, &values.text(row.row.path)));
                }
                Control::Stat(stat) => row.text = extras.usage.text(*stat),
                Control::Info(Info::SyncFolder) | Control::InfoAction(Info::SyncFolder, ..) => {
                    row.text = extras.sync_folder.clone()
                }
                Control::Info(Info::LastSynced) | Control::InfoAction(Info::LastSynced, ..) => {
                    row.text = extras.last_synced.clone()
                }
                Control::Info(Info::PaletteKeys(command))
                | Control::InfoAction(Info::PaletteKeys(command), ..) => {
                    row.text = crate::keys::assigned(values.value("keymap"), command)
                }
                Control::KeymapReport => {
                    row.text = extras.keymap_report.clone();
                    row.text_marks = extras.keymap_missing;
                }
                Control::Preset => row.choice = extras.keymap_preset,
                Control::Preview(TryKind::Macros) | Control::PreviewChips(TryKind::Macros) => {
                    row.preview_result = extras.macro_preview.clone();
                }
                Control::ThemeIssue(index) => {
                    row.text = extras.theme_issues.get(*index).cloned().unwrap_or_default();
                    row.visible &= *index < extras.theme_issues.len();
                }
                Control::Color => {
                    row.color = values.text(row.row.path);
                    row.warns = crate::themes::warns(row.row.path, &extras.theme_pairs);
                }
                // 打っている途中は書き直さない(同じ値なら触らない．書き直すと入力位置が先頭に戻る)
                Control::TextField => {
                    if let Some(Input::Edit(window)) = row.inputs.first() {
                        let text = values.text(row.row.path);
                        if ffi::window_text(*window) != text {
                            ffi::set_text(*window, &text);
                        }
                    }
                }
                _ => {}
            }
            // 書き方のチップ: 単語は「入力時の値にする」がオンのときだけ使える．開いていれば今の値を添える
            if let Some(target) = row.row.control.template_target() {
                row.template_enabled = target == TemplateTarget::Macro
                    || values.value("dynamicDictionary").and_then(Value::as_bool) == Some(true);
                if let Some(items) = row.template_items() {
                    row.lines = items
                        .iter()
                        .map(|(item, _)| {
                            extras
                                .template_values
                                .iter()
                                .find(|(sample, _)| *sample == item.sample)
                                .map_or_else(String::new, |(_, value)| value.clone())
                        })
                        .collect();
                }
            }
            if let Some(rows) = list_rows(&row.row, values, extras) {
                // 一覧が変わると選んだ行が外れるので，書き換えもやめる．変わらなければ選んだ行を残す
                if row.table.set_rows(rows) {
                    row.editing = None;
                }
                if let Some(search) = row.search {
                    row.table.filter(&ffi::window_text(search));
                }
                row.table.restrict(0, state_filter(row.filter));
                row.restrict_key();
                let content = row.table.len() as f32 * size::TABLE_ROW_HEIGHT;
                row.table_scroll.set_extent(content, table_viewport(row));
            }
            match &row.row.control {
                Control::Dictionaries(list) => {
                    let entries = crate::dictionaries::entries(*list, values.value(list.path()));
                    if let Some(rows) = &mut row.dictionaries {
                        rows.set_entries(entries, now);
                        rows.busy = extras.importing_dictionary;
                    }
                }
                Control::CustomTheme(index) => {
                    // 今あるテーマの数だけ出す．押すと使い，使っているテーマに選ぶ印を付ける
                    let entries = crate::themes::entries(values.value(crate::themes::THEMES));
                    let entry = entries.get(*index);
                    row.visible = entry.is_some();
                    row.text = entry.map(|entry| entry.name.clone()).unwrap_or_default();
                    row.on =
                        entry.is_some_and(|entry| values.text(crate::themes::ACTIVE) == entry.id);
                    row.custom = entry.and_then(|entry| crate::themes::to_wire(&entry.value));
                    row.warns = extras.theme_warnings.get(*index).copied().unwrap_or(false);
                    row.room = values.on(crate::themes::ROOM);
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
        let examples: Vec<bool> = self.rows.iter().map(|row| row.shows_example).collect();
        let all: Vec<&Row> = self
            .sections
            .iter()
            .flat_map(|section| &section.rows)
            .collect();
        let expanded: Vec<bool> = self.rows.iter().map(|row| row.expanded).collect();
        let heights: Vec<Option<f32>> = self
            .rows
            .iter()
            .map(|row| row.dictionaries.as_ref().map(dictionary_rows::Rows::height))
            .collect();
        let texts: Vec<String> = self.rows.iter().map(|row| row.text.clone()).collect();
        let chips: Vec<crate::engine::PreviewShown> = self
            .rows
            .iter()
            .map(|row| row.preview_result.clone())
            .collect();
        let lists: Vec<ListInput> = self
            .rows
            .iter()
            .map(|row| ListInput {
                key_chip: row.key_chip(),
                template_button: row.row.control.template_target().is_some()
                    && row.template_enabled,
                result: !(row.result_text.is_empty() && row.result_problems.is_empty()),
                panel: row.template_items().map(|items| PanelInput {
                    items: items.into_iter().map(|(item, _)| item).collect(),
                    values: row.lines.clone(),
                    switch: row.template_matches.is_none(),
                }),
            })
            .collect();
        let metrics = Measured {
            measure,
            all: &all,
            expanded: &expanded,
            heights: &heights,
            preview: self.preview_size,
            texts: &texts,
            chips: &chips,
            lists: &lists,
        };
        self.layout = layout::layout(
            &self.sections,
            width,
            |row| metrics.position(row).is_none_or(|index| visible[index]),
            |row| metrics.position(row).is_none_or(|index| examples[index]),
            &metrics,
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
        let button = |label: &str| {
            let metrics = Measured {
                measure,
                all: &[],
                expanded: &[],
                heights: &[],
                preview: None,
                texts: &[],
                chips: &[],
                lists: &[],
            };
            layout::button_width(label, &metrics)
        };
        // 英語と日本語の試した結果のタグの置き場所(押した位置を調べるため)．描くときと同じ並べ方
        for row in &mut self.rows {
            row.chip_areas = match (&row.row.control, &row.card) {
                (Control::Preview(TryKind::Language), Some(card)) => chip_areas(
                    measure,
                    card.control,
                    &row.preview_result,
                    tokens::size::settings::PREVIEW_BUTTON_GAP,
                ),
                _ => Vec::new(),
            };
        }
        for row in &mut self.rows {
            if let (Some(rows), Some(card)) = (&mut row.dictionaries, &row.card) {
                let area = (card.card.x, card.card.y, card.card.width);
                rows.placement = dictionary_rows::place(
                    rows.list,
                    &rows.entries,
                    rows.expanded_index(),
                    area,
                    &button,
                );
            }
        }
        // 書き方のチップの欄: 上にまとまりの切り替え(絞り込んでいるあいだは無し)，その下にチップ
        for row in &mut self.rows {
            let panel = row.card.as_ref().and_then(|card| card.template_panel);
            let (Some(target), Some(panel), Some(items)) = (
                row.row.control.template_target(),
                panel,
                row.template_items(),
            ) else {
                row.template_switch.clear();
                row.template_chips = reference::Chips::default();
                continue;
            };
            let switch = row.template_matches.is_none();
            row.template_switch = if switch {
                reference::place_switch(target.groups(), &TemplateMeasure(measure))
                    .into_iter()
                    .map(|rect| {
                        Rect::new(panel.x + rect.x, panel.y + rect.y, rect.width, rect.height)
                    })
                    .collect()
            } else {
                Vec::new()
            };
            let head = if switch {
                tokens::size::part::FIELD_HEIGHT + tokens::size::space::GROUP
            } else {
                0.0
            };
            row.template_origin = (panel.x, panel.y + head);
            let items: Vec<reference::Item> = items.into_iter().map(|(item, _)| item).collect();
            row.template_chips =
                reference::place_chips(&items, &row.lines, panel.width, &TemplateMeasure(measure));
            row.template_cursor = row.template_cursor.min(items.len().saturating_sub(1));
        }
        for row in &mut self.rows {
            row.acknowledgement = match (&row.row.control, &row.card) {
                (Control::Acknowledgement(_), Some(card)) => {
                    let inner = card.control;
                    let origin = (inner.x, inner.y, inner.width);
                    Some(AcknowledgementLayout::new(row.notice(), origin, row.expanded, measure).0)
                }
                _ => None,
            };
        }
        for row in &mut self.rows {
            if row.card.is_some() {
                let content = row.table.len() as f32 * size::TABLE_ROW_HEIGHT;
                let viewport = table_viewport(row);
                row.table_scroll.set_extent(content, viewport);
                if row.row.control == Control::KeymapReport {
                    if let Some(card) = &row.card {
                        let inner = card.control.width - size::FIELD_PADDING_X * 2.0;
                        let height = report_lines(&row.text, row.text_marks, inner, measure)
                            .last()
                            .map_or(0.0, |line| line.top + line.height)
                            + size::FIELD_PADDING_Y * 2.0;
                        row.text_scroll.set_extent(height, card.control.height);
                    }
                }
            }
        }
        self.layout.height
    }

    /// 打つ欄を置く．origin はページの左上の窓の中の位置(DIP)，scroll は送った量．hidden なら隠す(ページの入りの動きのあいだ)．
    /// ページの上の端より上へ送った欄も隠す
    pub fn place_fields(
        &self,
        theme: &Theme,
        origin: (f32, f32),
        band: (f32, f32),
        scroll: f32,
        hidden: bool,
    ) {
        for row in &self.rows {
            let shown = !hidden && row.visible && row.card.is_some();
            // 部品に無い欄(閉じた辞書の行の欄)は隠す
            let placed: Vec<Window> = row
                .parts()
                .into_iter()
                .filter_map(|part| row.edit(part))
                .collect();
            for window in row.windows().filter(|window| !placed.contains(window)) {
                ffi::show(window, false);
            }
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
                // 欄は窓なので，描いた絵のようにページの枠で切れない．上に留めた題の帯(band の上端より上)や，
                // 下に留めたボタンの帯(band の下端より下．カスタムテーマの編集の画面)へ出たら隠す
                if y < origin.1 + band.0 || y + line > origin.1 + band.1 {
                    ffi::show(window, false);
                    continue;
                }
                // 枠の中の右にボタンを置く欄は，ボタンのすぐ左まで使う(ボタンが右の余白になる)
                let width = if row.holds_key_button(part) {
                    rect.width - size::FIELD_PADDING_X
                } else {
                    rect.width - size::FIELD_PADDING_X * 2.0
                };
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

    /// ポインターを載せたときに出す説明(絵だけのボタン．macOS の .help)
    /// 表の (x, y)(ページの中の座標)の欄の文字と，欄の幅と書体．文字の欄でなければ None
    /// (切れた文字の全文を説明の吹き出しに出すため．macOS の表は切れた文字に全文の説明を出す)
    pub fn table_cell(
        &self,
        row_index: usize,
        x: f32,
        y: f32,
        now: f64,
    ) -> Option<(String, f32, TextStyle)> {
        let row = self.rows.get(row_index)?;
        let rect = row.part_rect(Part::Table)?;
        let position = self.table_position(row_index, y, now)?;
        let layout = row.row.control.table_layout();
        let padding = size::FIELD_PADDING_X;
        let spans = layout.spans(rect.width, padding);
        let (column, (_, width)) = layout
            .columns
            .iter()
            .zip(&spans)
            .find(|(_, (left, width))| x >= rect.x + left && x < rect.x + left + width)?;
        let style = match column.cell {
            Cell::Mono => TextStyle::Code,
            Cell::Text | Cell::Secondary => TextStyle::Body,
            _ => return None,
        };
        let text = row.table.shown_row(position)?.get(column.source)?.clone();
        Some((text, (width - padding).max(0.0), style))
    }

    pub fn tooltip(&self, element: Element) -> Option<&'static str> {
        match element.part {
            Part::Reset => Some(features::RESTORE_DEFAULT),
            Part::Entry(index, part) => self
                .rows
                .get(element.row)?
                .dictionaries
                .as_ref()?
                .tooltip(index, part),
            // 絵だけのボタン(カスタムテーマの編集・複製・削除)は名前を出す
            Part::Button(_) => self
                .rows
                .get(element.row)
                .filter(|row| matches!(row.row.control, Control::CustomTheme(_)))
                .map(|row| row.button_label(element.part)),
            Part::Bottom(_) => {
                let row = self.rows.get(element.row)?;
                let label = row.button_label(element.part);
                row.row
                    .control
                    .list_buttons()
                    .filter(|buttons| buttons.is_icon(label))
                    .map(|_| label)
            }
            Part::TemplateButton => Some(crate::strings::templates::BUTTON_HELP),
            // 「キーで検索」は何をするかを，絞り込んでいるあいだのチップは押すと外れることを出す
            Part::KeySearch => Some(
                if self
                    .rows
                    .get(element.row)
                    .is_some_and(|row| row.key_filter.is_some())
                {
                    keys::CLEAR_KEY_FILTER
                } else {
                    keys::SEARCH_BY_KEY_HELP
                },
            ),
            // 絵だけのボタン(キーを選ぶメニュー・記録を停止)は名前を出す
            Part::KeyMenu => Some(keys::CHOOSE_KEY),
            Part::KeyStop => Some(keys::STOP_RECORDING),
            _ => None,
        }
    }

    /// 部品の名前(読み上げ)
    pub fn name(&self, element: Element) -> String {
        let Some(row) = self.rows.get(element.row) else {
            return String::new();
        };
        match element.part {
            Part::Reset => format!("{} {}", row.row.title, features::RESTORE_DEFAULT),
            Part::Decrement => format!("{} {}", row.row.title, text::DECREASE),
            Part::Increment => format!("{} {}", row.row.title, text::INCREASE),
            Part::Slider => row.title(),
            Part::Filter => keys::STATE.to_string(),
            // 絞り込んでいるあいだは，外すことと絞り込んでいるキーを読む
            Part::KeySearch => match row.key_chip() {
                Some(chip) => format!("{} {chip}", keys::CLEAR_KEY_FILTER),
                None => keys::SEARCH_BY_KEY.to_string(),
            },
            Part::Segment(_)
            | Part::Button(_)
            | Part::TemplateSegment(_)
            | Part::TemplateButton => row.button_label(element.part).to_string(),
            // 選んでいるチップの書き方と値
            Part::TemplateChips => row
                .template_items()
                .and_then(|items| items.get(row.template_cursor).copied())
                .map_or_else(String::new, |(item, _)| {
                    let value = reference::value_of(
                        &item,
                        row.lines.get(row.template_cursor).map(String::as_str),
                    );
                    format!("{} {value} {}", item.code, item.meaning)
                }),
            Part::Top(_)
            | Part::Bottom(_)
            | Part::Action
            | Part::Link(_)
            | Part::Expand
            | Part::KeyMenu
            | Part::KeyStop => row.button_label(element.part).to_string(),
            // 読み上げは入る文字と，英語か日本語か(macOS の resultChip と同じく 1 つにまとめる)
            Part::PreviewChip(index) => {
                let chip = row
                    .preview_result
                    .chips
                    .get(index)
                    .map_or("", String::as_str);
                match row
                    .preview_result
                    .labels
                    .get(index)
                    .and_then(Option::as_ref)
                {
                    Some((label, _)) => format!("{chip} {label}"),
                    None => chip.to_string(),
                }
            }
            Part::Field(index) => row
                .row
                .control
                .list_spec()
                .and_then(|spec| spec.fields.get(index))
                .map_or_else(
                    || row.row.title.to_string(),
                    |field| field.label.to_string(),
                ),
            Part::Search => features::SEARCH.to_string(),
            Part::PreviewField(index) => match row.row.control {
                Control::Preview(TryKind::Language) => {
                    [features::TRY_PLACEHOLDER, features::TRY_PRECEDING][index.min(1)].to_string()
                }
                _ => [extras::TRY_MACRO_WORD, extras::TRY_MACRO_READING][index.min(1)].to_string(),
            },
            Part::Table => row.row.control.table_columns().join("・"),
            Part::Entry(index, part) => row
                .dictionaries
                .as_ref()
                .map_or_else(String::new, |rows| rows.name(index, part)),
            Part::Import => match row.row.control {
                Control::Dictionaries(list) => list.import_label().to_string(),
                _ => String::new(),
            },
            // 読みにくいカスタムテーマは名前のあとに知らせる(macOS は印に読みやすさの名前を付ける)
            Part::Radio if row.warns => format!("{}、{}", row.title(), more::READABILITY),
            Part::Radio => row.title(),
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
            Part::Entry(index, EntryPart::Toggle) => Described::Toggle(
                row.dictionaries
                    .as_ref()
                    .and_then(|rows| rows.entries.get(index))
                    .is_some_and(|entry| entry.is_enabled),
            ),
            Part::Entry(_, EntryPart::Name | EntryPart::Field) => Described::Edit,
            Part::Slider => Described::Slider(
                row.number()
                    .map(|value| row.number_text(value))
                    .unwrap_or_default(),
            ),
            Part::Radio => Described::Radio(row.on),
            Part::TemplateButton => Described::Toggle(row.template_open),
            Part::TemplateSegment(index) => Described::Radio(row.template_group == index),
            Part::TemplateChips => Described::Button,
            Part::Segment(index) => Described::Radio(row.choice == Some(index)),
            Part::Dropdown | Part::Field(_) | Part::Filter | Part::Entry(..)
                if row.is_dropdown(element.part) =>
            {
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
        // 辞書の行の部品は辞書の数だけあるので，ほかの部品の番号より後ろに分けて数える
        if let Part::Entry(index, part) = element.part {
            let id = ENTRY_ID_BASE
                + element.row * ENTRY_ID_ROW
                + index * ENTRY_ID_ENTRY
                + part.ordinal();
            return i32::try_from(id).unwrap_or(i32::MAX);
        }
        let part = match element.part {
            Part::Reset => 0,
            Part::Toggle => 1,
            Part::Dropdown => 2,
            Part::Action => 3,
            Part::Color => 4,
            Part::Decrement => 6,
            Part::Increment => 7,
            Part::Slider => 8,
            Part::Radio => 9,
            Part::TemplateButton => 5,
            Part::TemplateChips => 51,
            // 一覧の行には試す欄(60・61)が無いので，書き方のまとまりの切り替えはその番号を使う
            Part::TemplateSegment(index) => 60 + index,
            Part::Filter => 31,
            Part::RowMenu => 52,
            Part::KeySearch => 32,
            Part::KeyMenu => 34,
            Part::KeyStop => 35,
            Part::Segment(index) => 90 + index,
            Part::Button(index) => 95 + index,
            Part::Field(index) => 10 + index,
            Part::Top(index) => 20 + index,
            Part::Search => 30,
            Part::Bottom(index) => 40 + index,
            Part::Table => 50,
            Part::TableChoice(_) => 51,
            Part::PreviewField(index) => 60 + index,
            Part::Text => 70,
            Part::Expand => 79,
            Part::PreviewChip(index) => 90 + index.min(9),
            Part::Link(index) => 80 + index,
            Part::Import => 33,
            Part::Entry(..) => 0,
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
            let inside =
                |rect: Rect| x >= rect.x && x < rect.max_x() && y >= rect.y && y < rect.max_y();
            let part = row.parts().into_iter().find(|part| {
                row.part_rect(*part)
                    .is_some_and(|rect| inside(rect) && row.part_enabled(*part))
            })?;
            // 表の行の中の選ぶ欄(見出しの下の行の中だけ)
            if part == Part::Table && row.choice_column().is_some() {
                let table = row.part_rect(Part::Table)?;
                let top = table.y + size::TABLE_HEADER_HEIGHT;
                if y >= top {
                    let position =
                        ((y - top + row.table_scroll.target()) / size::TABLE_ROW_HEIGHT) as usize;
                    let choice = Part::TableChoice(position);
                    if row.part_enabled(choice) && row.part_rect(choice).is_some_and(inside) {
                        return Some(Element {
                            row: index,
                            part: choice,
                        });
                    }
                }
            }
            Some(Element { row: index, part })
        })
    }

    pub fn enabled(&self, element: Element) -> bool {
        self.rows
            .get(element.row)
            .is_some_and(|row| row.visible && row.part_enabled(element.part))
    }

    /// 欄がキーの記録を始めた・やめた．記録しているあいだ，キーの欄の右を「記録を停止」のボタンにする
    pub fn set_recording(&mut self, window: Window, recording: bool) {
        let Some(element) = self.element_of(window) else {
            return;
        };
        if let Some(row) = self.rows.get_mut(element.row) {
            if recording {
                row.recording = Some(element.part);
            } else if row.recording == Some(element.part) {
                row.recording = None;
            }
        }
    }

    /// 「キーで検索」で押したキー(window は受け取った検索欄)で表を絞り込む．チップの幅が変わるので置き直す
    pub fn key_captured(&mut self, window: Window, notation: &str) -> Option<Event> {
        let element = self.element_of(window)?;
        let row = self.rows.get_mut(element.row)?;
        row.set_key_filter(Some(notation));
        Some(Event::Relayout)
    }

    /// 見本の書き出しで，キー設定の表を notation のキーで絞り込んだ状態にする
    pub fn show_key_filter(&mut self, notation: &str) {
        for row in &mut self.rows {
            if row
                .row
                .control
                .list_buttons()
                .is_some_and(|buttons| buttons.toolbar)
            {
                row.set_key_filter(Some(notation));
            }
        }
    }

    /// 見本の書き出しで，キー設定の新しい行のキーの欄に text を入れた状態(recording なら記録しているところ)にする
    pub fn show_key_draft(&mut self, text: &str, recording: bool) {
        for row in &mut self.rows {
            let Some(field) = row
                .row
                .control
                .list_buttons()
                .and_then(|buttons| buttons.key_menu)
            else {
                continue;
            };
            if let Some(window) = row.key_window() {
                ffi::set_text(window, text);
            }
            row.recording = recording.then_some(Part::Field(field));
            // 状態は入力中にし(macOS の新しい行の初めの状態)，コマンドはその状態に置けるものにする
            let composing = keys::STATES
                .iter()
                .position(|(value, _)| *value == "composing");
            if let (Some(Input::Choice(state)), Some(composing)) =
                (row.inputs.first_mut(), composing)
            {
                *state = composing;
            }
            let allowed = row.choice_positions(KEYMAP_COMMAND);
            if let Some(Input::Choice(command)) = row.inputs.get_mut(KEYMAP_COMMAND) {
                if !allowed.is_empty() && !allowed.contains(command) {
                    *command = allowed[0];
                }
            }
        }
    }

    /// 開く一覧を下に出す部品の場所(ページの中の座標)．キーを選ぶメニューは，キーの欄の左の端にそろえて出す
    pub fn menu_rect(&self, element: Element) -> Option<Rect> {
        let row = self.rows.get(element.row)?;
        let field = row
            .row
            .control
            .list_buttons()
            .and_then(|buttons| buttons.key_menu);
        match (element.part, field) {
            (Part::KeyMenu, Some(field)) => row.field_frame(Part::Field(field)),
            _ => row.part_rect(element.part),
        }
    }

    /// キーを選ぶメニューを初めから開く(ファンクションキーの一覧から戻す)
    pub fn reset_key_menu(&mut self, element: Element) {
        if let Some(row) = self.rows.get_mut(element.row) {
            row.key_functions = false;
        }
    }

    /// キーを選ぶメニューでファンクションキーの項目を選んだか(続けてその一覧を開く)
    pub fn opens_key_functions(&self, element: Element) -> bool {
        element.part == Part::KeyMenu
            && self
                .rows
                .get(element.row)
                .is_some_and(|row| row.key_functions)
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
                    || row
                        .dictionaries
                        .as_ref()
                        .is_some_and(|rows| rows.animating(now))
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
        if let Control::Dictionaries(list) = row.row.control {
            return row.activate_dictionary(list, part, now);
        }
        match (&row.row.control, part) {
            (_, Part::Reset) => return Some(Event::Reset(row.row.path)),
            // 押したキーで絞り込んでいれば外す(チップを押した)．でなければ次に押したキーを検索欄で受け取り，
            // そのキーの行だけを出す(set_key_filter．検索欄の言葉とは別に絞る．macOS の KeymapPage の keyFilter)
            (_, Part::KeySearch) => {
                if row.key_filter.is_some() {
                    row.set_key_filter(None);
                    return Some(Event::Relayout);
                }
                if let Some(search) = row.search {
                    edit::start_recording(search, keys::PRESS);
                }
                return None;
            }
            // 記録をやめて，欄を記録の前のキーに戻す(macOS の KeyField の「記録を停止」)
            (_, Part::KeyStop) => {
                if let Some(window) = row.key_window() {
                    edit::stop_recording(window);
                }
                row.recording = None;
                return None;
            }
            (Control::Stepper(_), Part::Decrement) => return row.step(-1),
            (Control::Stepper(_), Part::Increment) => return row.step(1),
            (Control::ThemeOption(value), Part::Radio) => {
                row.on = true;
                return Some(Event::Set {
                    path: row.row.path,
                    value: Value::String((*value).to_string()),
                    clears: row.row.clears,
                });
            }
            (Control::Segmented(choices), Part::Segment(index)) => {
                let (value, _) = choices.get(index)?;
                row.choice = Some(index);
                return Some(Event::Set {
                    path: row.row.path,
                    value: Value::String((*value).to_string()),
                    clears: None,
                });
            }
            (Control::Buttons(buttons), Part::Button(index)) => {
                return Some(Event::Action(buttons.get(index)?.1))
            }
            (Control::CustomTheme(position), Part::Radio | Part::Button(_)) => {
                let action = match part {
                    Part::Button(index) => ThemeAction::ROW.get(index)?.clone(),
                    _ => ThemeAction::Use,
                };
                return Some(Event::ThemeList {
                    action,
                    index: Some(*position),
                    name: row.text.clone(),
                });
            }
            (Control::InfoAction(_, action, _), Part::Action) => {
                return Some(Event::Action(*action))
            }
            (_, Part::Bottom(index)) if row.file_task(index).is_some() => {
                return row
                    .file_task(index)
                    .map(|task| Event::Action(Action::File(task)));
            }
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
            (Control::Action(action) | Control::LabeledAction(action, _), Part::Action) => {
                return Some(Event::Action(*action))
            }
            (Control::Version, Part::Action) => {
                return Some(Event::Action(Action::CheckForUpdates))
            }
            (Control::Acknowledgement(_), Part::Link(index)) => {
                let url = row
                    .notice()
                    .and_then(|item| item.sources.get(index))
                    .and_then(|line| crate::notices::split_url(line))
                    .map(|(_, url, _)| url.to_string())?;
                return Some(Event::OpenUrl(url));
            }
            (Control::Preview(TryKind::Language), Part::PreviewChip(index)) => {
                let word = row.preview_result.typed.get(index)?.trim().to_lowercase();
                return (!word.is_empty()).then_some(Event::ChooseWordList {
                    word,
                    chip: element,
                });
            }
            (_, Part::TemplateSegment(index)) => {
                row.template_group = index;
                row.template_cursor = 0;
                // 前のまとまりの値は捨て，読み直すまでは決めておいた例を出す
                row.lines.clear();
                return Some(Event::Relayout);
            }
            (_, Part::TemplateButton) => {
                let target = row.row.control.template_target()?;
                row.template_open = !row.template_open;
                return Some(Event::TemplatePanel {
                    target,
                    open: row.template_open,
                });
            }
            (Control::Acknowledgement(_), Part::Expand) => {
                row.expanded = !row.expanded;
                return Some(Event::Relayout);
            }
            (Control::Color, Part::Color) => {
                return Some(Event::ChooseColor {
                    path: row.row.path,
                    current: row.color.clone(),
                })
            }
            _ => {}
        }
        // 項目ごとの同期は表の「同期する」の印で切り替える(table_check_click)
        if let Control::SyncFields(_) = row.row.control {
            return None;
        }
        if let Control::List(spec, _) = &row.row.control {
            match (spec.path, part) {
                ("keymap", Part::Bottom(2)) => {
                    return Some(Event::Action(pages::Action::RestoreKeymap))
                }
                ("keymap", Part::Bottom(1)) => {
                    // 選んだ行を，それぞれ元の行のすぐ下に複製する(macOS と同じ)
                    let selected = row.table.selected_rows();
                    return (!selected.is_empty()).then_some(Event::ListDuplicate {
                        spec: *spec,
                        indices: selected,
                    });
                }
                _ => {}
            }
            if let Part::Bottom(index) = part {
                let selected = row.table.selected_rows();
                match row.list_button(index) {
                    Some(ListButton::Add) => return Some(Event::EditCommand(None)),
                    Some(ListButton::Edit) => {
                        return selected
                            .first()
                            .map(|index| Event::EditCommand(Some(*index)))
                    }
                    Some(ListButton::MoveUp | ListButton::MoveDown) => {
                        let offset = if row.list_button(index) == Some(ListButton::MoveUp) {
                            -1
                        } else {
                            1
                        };
                        let [index] = selected.as_slice() else {
                            return None;
                        };
                        return Some(Event::ListMove {
                            spec: *spec,
                            index: *index,
                            offset,
                        });
                    }
                    Some(ListButton::Always) if spec.path == PROFILE_RULES => {
                        return Some(Event::ChooseApp { path: spec.path })
                    }
                    _ => {}
                }
            }
        }
        if !row.has_add_remove() {
            return None;
        }
        if part == Part::Top(1) && row.editing.is_some() {
            row.cancel_edit();
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
                Part::Bottom(0) => (!selected.is_empty()).then_some(Event::SymbolRemove {
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
            Part::Bottom(0) if dictionary => {
                (!selected.is_empty()).then_some(Event::DictionaryRemove(selected))
            }
            Part::Bottom(_) if Some(part) == row.remove_part() => {
                (!selected.is_empty()).then_some(Event::ListRemove {
                    spec,
                    indices: selected,
                })
            }
            _ => None,
        }
    }

    /// ドロップダウンで index を選んだ．頼みがあれば返す
    pub fn choose(&mut self, element: Element, index: usize) -> Option<Event> {
        let row = self.rows.get_mut(element.row)?;
        let event = match (&row.row.control, element.part) {
            (Control::ThemeFont(_), Part::Dropdown) => {
                let (value, _) = row.font_items.get(index)?;
                row.choice = Some(index);
                Some(Event::Set {
                    path: row.row.path,
                    value: Value::String(value.clone()),
                    clears: row.row.clears,
                })
            }
            (Control::Choice(choices), Part::Dropdown) => {
                let (value, _) = choices.get(index)?;
                row.choice = Some(index);
                Some(Event::Set {
                    path: row.row.path,
                    value: Value::String((*value).to_string()),
                    clears: row.row.clears,
                })
            }
            (_, Part::Filter) => {
                row.filter = index;
                row.table.restrict(0, state_filter(index));
                row.editing = None;
                let content = row.table.len() as f32 * size::TABLE_ROW_HEIGHT;
                let viewport = table_viewport(row);
                row.table_scroll.set_extent(content, viewport);
                row.table_scroll.jump_to(0.0);
                None
            }
            (Control::Preset, Part::Dropdown) => keys::PRESETS
                .get(index)
                .map(|(preset, _)| Event::LoadPreset(preset)),
            // 選んだキー・修飾キーを，記録したときと同じ書き方でキーの欄に入れる(macOS の KeyField の menu)
            (_, Part::KeyMenu) => {
                let choice = row.key_choices().get(index)?.clone();
                // ファンクションキーの項目は一覧を出し直す(窓が opens_key_functions を見て開く)
                row.key_functions = choice == crate::keys::KeyChoice::FunctionKeys;
                let window = row.key_window()?;
                if let Some(notation) = crate::keys::chosen(&ffi::window_text(window), &choice) {
                    ffi::set_text(window, &crate::keys::display(&notation));
                }
                None
            }
            (_, Part::Field(field)) => {
                // 出した選択肢の位置を選択肢の番号にする(キー設定のコマンドは置けるものだけを出す)
                let positions = row.choice_positions(field);
                if let (Some(Input::Choice(selected)), Some(position)) =
                    (row.inputs.get_mut(field), positions.get(index))
                {
                    *selected = *position;
                }
                // キー設定の状態を変えたら，置けないコマンドを置けるものの先頭にする(macOS の setDraftState)
                if field == 0 {
                    let allowed = row.choice_positions(KEYMAP_COMMAND);
                    if let Some(Input::Choice(command)) = row.inputs.get_mut(KEYMAP_COMMAND) {
                        if !allowed.is_empty() && !allowed.contains(command) {
                            *command = allowed[0];
                        }
                    }
                }
                None
            }
            (Control::Dictionaries(list), Part::Entry(entry, EntryPart::Condition)) => {
                let (value, _) = DICTIONARY_CONDITIONS.get(index)?;
                Some(Event::DictionaryList {
                    list: *list,
                    action: DictionaryAction::SetCondition(value),
                    index: Some(entry),
                })
            }
            // 表の行の中で選び直したら，その行のその欄だけをすぐ書く(macOS の ExclusionsPage の Picker)
            (Control::List(spec, _), Part::TableChoice(position)) => {
                let (_, source) = row.choice_column()?;
                let (value, _) = spec.fields.get(source)?.choices?.get(index)?;
                let row_index = row.table.row_index(position)?;
                (row.dropdown_selected(element.part) != Some(index)).then(|| Event::ListSet {
                    spec: *spec,
                    index: row_index,
                    field: source,
                    value: (*value).to_string(),
                })
            }
            _ => None,
        };
        self.show_footer_variants();
        event
    }

    /// 打つ欄の文字が変わった．頼みがあれば返す(試す欄．変換マクロの欄に書いている形も試す)
    pub fn edited(&mut self, element: Element) -> Option<Event> {
        let changed = self.rows.get(element.row)?;
        let macro_preview = match (&changed.row.control, element.part) {
            (Control::Preview(TryKind::Macros), Part::PreviewField(_)) => true,
            (Control::List(spec, _), Part::Field(0)) => spec.path == MACROS_PATH,
            _ => false,
        };
        if let Control::Dictionaries(list) = changed.row.control {
            return changed.dictionary_edited(list, element.part);
        }
        if macro_preview {
            let (text, preceding, draft) = self.macro_preview_inputs()?;
            return Some(Event::Preview {
                kind: TryKind::Macros,
                text,
                preceding,
                draft,
            });
        }
        // 単語の欄に書き方を書いたら，入れたときの結果を求める
        if let (Control::Dictionary(spec), Part::Field(field)) =
            (&changed.row.control, element.part)
        {
            if spec.fields.get(field).and_then(|field| field.name) == Some("word") {
                let draft = changed
                    .edit(element.part)
                    .map(ffi::window_text)
                    .unwrap_or_default();
                return Some(Event::DraftResult {
                    path: spec.path,
                    draft,
                });
            }
        }
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
            Part::Field(0) if row.row.control == Control::TextField => {
                let text = row.edit(Part::Field(0)).map(ffi::window_text)?;
                Some(Event::Set {
                    path: row.row.path,
                    value: Value::String(text),
                    clears: None,
                })
            }
            Part::PreviewField(_) => {
                let texts: Vec<String> = row
                    .preview_fields
                    .iter()
                    .map(|window| ffi::window_text(*window))
                    .collect();
                Some(Event::Preview {
                    kind: TryKind::Language,
                    text: texts.first().cloned().unwrap_or_default(),
                    preceding: texts.get(1).cloned().unwrap_or_default(),
                    draft: String::new(),
                })
            }
            _ => None,
        }
    }

    /// 変換マクロの試す欄の語と読みと，変換マクロの欄に書いている途中の形．試す欄が無いページでは None
    pub fn macro_preview_inputs(&self) -> Option<(String, String, String)> {
        let preview = self
            .rows
            .iter()
            .find(|row| row.row.control == Control::Preview(TryKind::Macros))?;
        let texts: Vec<String> = preview
            .preview_fields
            .iter()
            .map(|window| ffi::window_text(*window))
            .collect();
        let draft = self
            .rows
            .iter()
            .find(|row| matches!(&row.row.control, Control::List(spec, _) if spec.path == MACROS_PATH))
            .and_then(|row| row.edit(Part::Field(0)))
            .map(ffi::window_text)
            .unwrap_or_default();
        Some((
            texts.first().cloned().unwrap_or_default(),
            texts.get(1).cloned().unwrap_or_default(),
            draft,
        ))
    }

    /// 英語と日本語の試す欄の文と前の文字列．試す欄が無いページか，文が空なら None
    pub fn language_preview_inputs(&self) -> Option<(String, String)> {
        let preview = self
            .rows
            .iter()
            .find(|row| row.row.control == Control::Preview(TryKind::Language))?;
        let texts: Vec<String> = preview
            .preview_fields
            .iter()
            .map(|window| ffi::window_text(*window))
            .collect();
        let text = texts.first().cloned().unwrap_or_default();
        (!text.trim().is_empty()).then(|| (text, texts.get(1).cloned().unwrap_or_default()))
    }

    /// 打つ欄で Enter を押した(一覧なら追加・更新のボタンを押す)
    pub fn submit(&mut self, element: Element, now: f64) -> Option<Event> {
        let row = self.rows.get(element.row)?;
        if !matches!(element.part, Part::Field(_)) {
            return None;
        }
        // カスタムテーマの名前の欄で Enter を押したら保存する(macOS の保存のボタンは既定の操作)
        if row.row.control == Control::TextField {
            return Some(Event::ThemeEditor(EditorAction::Save));
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

    /// 表の行を押した．頼みがあれば返す．1 回押すと選ぶだけで，2 回押すと(double)その行を入力欄に出して書き換える
    /// (macOS の RuleListEditor と同じ．選んだだけで書き換えにすると，打ちかけた行で選んだ行を上書きしてしまう)
    pub fn table_click(
        &mut self,
        row_index: usize,
        position: usize,
        control: bool,
        shift: bool,
        double: bool,
    ) -> Option<Event> {
        let row = self.rows.get_mut(row_index)?;
        let changed = row.table.click(position, control, shift);
        // コマンドは 2 回押すとシートで書き換える(macOS の CommandsPage の primaryAction)．
        // 除外設定は行の中で動作を選び直すので，2 回押しても書き換えない(macOS と同じ)
        let sheet = row
            .row
            .control
            .list_buttons()
            .is_some_and(|buttons| buttons.sheet);
        if double && !control && !shift && sheet {
            return row
                .table
                .row_index(position)
                .map(|index| Event::EditCommand(Some(index)));
        }
        if double && !control && !shift && row.row.control.reorderable() {
            return changed.then(|| self.selection_changed(row_index)).flatten();
        }
        if double && !control && !shift && row.has_add_remove() {
            if let [index] = row.table.selected_rows().as_slice() {
                let index = *index;
                row.fill_inputs(index);
                row.editing = Some(index);
                self.show_footer_variants();
                return None;
            }
        }
        if !changed {
            return None;
        }
        self.selection_changed(row_index)
    }

    /// このページで開いている書き方のチップの欄に並べるチップ(今の値を読み直す．開いていなければ None)
    pub fn template_items(&self) -> Option<Vec<reference::Item>> {
        self.rows.iter().find_map(|row| {
            row.template_items()
                .map(|items| items.into_iter().map(|(item, _)| item).collect())
        })
    }

    /// 書き方のチップを開いているかを決める(ページを開いたとき．覚えておいた状態)
    pub fn set_templates_open(&mut self, open: impl Fn(TemplateTarget) -> bool) {
        for row in &mut self.rows {
            if let Some(target) = row.row.control.template_target() {
                row.template_open = open(target);
            }
        }
    }

    /// 書き方のチップ(並びの item 番目．None ならキーボードで選んでいるチップ)を，書き方を入れる欄の入力位置に入れる．
    /// 打ちかけの書き方は置き換える．欄の取り消し(Ctrl+Z)で戻せる．入れた欄を返す(欄の変化は呼ぶ側で映す．
    /// 窓の処理の中で書き換えるので，欄の知らせ(EN_CHANGE)は届かない)
    pub fn insert_template(&mut self, row_index: usize, item: Option<usize>) -> Option<Window> {
        let row = self.rows.get(row_index)?;
        let target = row.row.control.template_target()?;
        let (entry, kind) = *row
            .template_items()?
            .get(item.unwrap_or(row.template_cursor))?;
        let window = row.edit(Part::Field(target.field()))?;
        let text = ffi::window_text(window);
        let insertion = reference::insertion(&entry, kind, &text, edit::selection(window));
        edit::replace(window, insertion.range, &insertion.replacement);
        Some(window)
    }

    /// 書き方を入れる欄で文字が変わった．入力位置の前で書き方を打ち始めたら(「{」)チップを開き，
    /// 打ちかけの書き方でチップを絞り込む．置き直しや覚える頼みがあれば返す
    pub fn template_typed(&mut self, element: Element) -> Option<Event> {
        let row = self.rows.get_mut(element.row)?;
        let target = row.row.control.template_target()?;
        if element.part != Part::Field(target.field()) || !row.template_enabled {
            return None;
        }
        let window = row.edit(element.part)?;
        let text = ffi::window_text(window);
        let utf16: Vec<u16> = text.encode_utf16().collect();
        let caret = edit::selection(window).start.min(utf16.len());
        let typed = reference::typing(&String::from_utf16_lossy(&utf16[..caret]));
        let matches = reference::matches(target.groups(), typed.as_ref());
        let started = typed.is_some() && !row.template_typing;
        row.template_typing = typed.is_some();
        let changed = matches != row.template_matches;
        if changed {
            row.template_matches = matches;
            row.template_cursor = 0;
            row.lines.clear();
        }
        if started && !row.template_open {
            row.template_open = true;
            return Some(Event::TemplatePanel { target, open: true });
        }
        (changed && row.template_open).then_some(Event::Relayout)
    }

    /// 書き方のチップを閉じる(Esc)．開いていなければ None
    pub fn close_templates(&mut self, row_index: usize) -> Option<Event> {
        let row = self.rows.get_mut(row_index)?;
        let target = row.row.control.template_target()?;
        if !row.template_panel_open() {
            return None;
        }
        row.template_open = false;
        Some(Event::TemplatePanel {
            target,
            open: false,
        })
    }

    /// このページで最初の書き方を入れる欄(見本の書き出しで打ったことにする)
    pub fn first_template_field(&self) -> Option<Window> {
        (0..self.rows.len()).find_map(|index| self.template_field(index))
    }

    /// 書き方を入れる欄(Esc で閉じたあとにフォーカスを戻す)
    pub fn template_field(&self, row_index: usize) -> Option<Window> {
        let row = self.rows.get(row_index)?;
        row.edit(Part::Field(row.row.control.template_target()?.field()))
    }

    /// 書き方のチップの (x, y)(ページの中の座標)にあるチップ(並びの番号)
    pub fn template_chip_at(&self, row_index: usize, x: f32, y: f32) -> Option<usize> {
        let row = self.rows.get(row_index)?;
        row.template_chips
            .item_at(x - row.template_origin.0, y - row.template_origin.1)
    }

    /// キーボードで選ぶチップを前(-1)か後ろ(+1)に移す
    pub fn move_template_cursor(&mut self, row_index: usize, delta: isize) -> bool {
        let Some(row) = self.rows.get_mut(row_index) else {
            return false;
        };
        let count = row.template_chips.chips.len();
        let next = row.template_cursor.saturating_add_signed(delta);
        if count == 0 || next >= count || next == row.template_cursor {
            return false;
        }
        row.template_cursor = next;
        true
    }

    pub fn set_template_hover(&mut self, hover: Option<(usize, usize)>) -> bool {
        let changed = self.template_hover != hover;
        self.template_hover = hover;
        changed
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
    /// 表の行を右クリックした．その行を選び(選んでいる行の中なら選びをそのままにし)，メニューを出せるなら true
    pub fn table_menu(&mut self, row_index: usize, position: usize) -> bool {
        let Some(row) = self.rows.get_mut(row_index) else {
            return false;
        };
        if !row.table.is_selected(position) {
            row.table.click(position, false, false);
            self.selection_changed(row_index);
        }
        self.rows
            .get(row_index)
            .is_some_and(|row| !row.row_menu().is_empty())
    }

    /// 表の行のメニューで index を選んだ．編集は入力欄に写し，複製と削除は表の下のボタンと同じにする
    pub fn choose_row_menu(&mut self, row_index: usize, index: usize, now: f64) -> Option<Event> {
        let row = self.rows.get_mut(row_index)?;
        let item = *row.row_menu().get(index)?;
        match item {
            RowMenuItem::Edit => {
                let selected = *row.table.selected_rows().first()?;
                row.fill_inputs(selected);
                row.editing = Some(selected);
                self.show_footer_variants();
                None
            }
            RowMenuItem::Duplicate => self.activate(
                Element {
                    row: row_index,
                    part: Part::Bottom(1),
                },
                now,
            ),
            RowMenuItem::Remove => self.activate(
                Element {
                    row: row_index,
                    part: Part::Bottom(0),
                },
                now,
            ),
        }
    }

    /// 行の一覧で，選んだ行を消すボタン(足す一覧でなければ None)
    pub fn remove_part(&self, row_index: usize) -> Option<Part> {
        self.rows.get(row_index)?.remove_part()
    }

    /// 表の (x, y)(ページの中の座標)が見出しの上なら，その列で並べ替える．並べ替えたら true
    pub fn table_header_click(&mut self, row_index: usize, x: f32, y: f32) -> bool {
        let Some(row) = self.rows.get_mut(row_index) else {
            return false;
        };
        let Some(rect) = row.part_rect(Part::Table) else {
            return false;
        };
        if y >= rect.y + size::TABLE_HEADER_HEIGHT {
            return false;
        }
        if !row.row.control.sortable() {
            return false;
        }
        let layout = row.row.control.table_layout();
        let spans = layout.spans(rect.width, size::FIELD_PADDING_X);
        let hit = layout
            .columns
            .iter()
            .zip(&spans)
            .find(|(_, (left, width))| x >= rect.x + left && x < rect.x + left + width);
        match hit {
            Some((column, _)) if column.cell != Cell::Check => {
                let editing = row.editing.is_some();
                row.table.toggle_sort(column.source);
                if editing {
                    row.cancel_edit();
                }
                true
            }
            _ => false,
        }
    }

    /// 表の (x, y) が「有効」の列の印の上なら，その行の有効・無効を切り替える頼みを返す
    pub fn table_check_click(&self, row_index: usize, x: f32, position: usize) -> Option<Event> {
        let row = self.rows.get(row_index)?;
        if !row.enabled {
            return None;
        }
        let rect = row.part_rect(Part::Table)?;
        let layout = row.row.control.table_layout();
        let spans = layout.spans(rect.width, size::FIELD_PADDING_X);
        let (_, (left, _)) = layout
            .columns
            .iter()
            .zip(&spans)
            .find(|(column, _)| column.cell == Cell::Check)?;
        let start = rect.x + left;
        if x < start || x > start + size::RADIO_SIZE {
            return None;
        }
        let index = row.table.row_index(position)?;
        match &row.row.control {
            Control::Symbols(kind, _) => Some(Event::SymbolToggle {
                kind: *kind,
                indices: vec![index],
            }),
            Control::List(spec, _) if spec.has_enabled_flag() => Some(Event::ListToggle {
                spec: *spec,
                indices: vec![index],
            }),
            Control::SyncFields(_) => Some(Event::SyncToggleFields(vec![index])),
            _ => None,
        }
    }

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
        if row.has_add_remove() {
            // 書き換えている行から選びが外れたら，書き換えをやめる(入力欄はその行の値なので空にする)
            if let Some(editing) = row.editing {
                if row.table.selected_rows().as_slice() != [editing] {
                    row.cancel_edit();
                }
            }
        }
        self.show_footer_variants();
        None
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

    /// 部品の中の送りのトラック(ページの中の座標．つまみが動く範囲)と送り．送れなければ None
    fn inner_scroller(&mut self, element: Element) -> Option<(Rect, &mut Scroller)> {
        let row = self.rows.get_mut(element.row)?;
        let rect = row.part_rect(element.part)?;
        let (track, scroller) = match element.part {
            Part::Table => (
                Rect::new(
                    rect.x,
                    rect.y + size::TABLE_HEADER_HEIGHT,
                    rect.width,
                    (rect.height - size::TABLE_HEADER_HEIGHT).max(0.0),
                ),
                &mut row.table_scroll,
            ),
            Part::Text => (rect, &mut row.text_scroll),
            _ => return None,
        };
        if !scroller.can_scroll() {
            return None;
        }
        let margin = size::SCROLLBAR_MARGIN;
        let inner = Rect::new(
            track.x,
            track.y + margin,
            track.width,
            (track.height - margin * 2.0).max(0.0),
        );
        Some((inner, scroller))
    }

    /// 部品の中を送れるか(右端を押したらスクロールバーとして扱う)
    pub fn can_scroll_inside(&mut self, element: Element) -> bool {
        self.inner_scroller(element).is_some()
    }

    /// 部品の中のスクロールバーを y(ページの中の座標)で押した．つまみならつかみ，外ならそこへ送る
    pub fn press_inner_scrollbar(&mut self, element: Element, y: f32, now: f64) {
        if let Some((track, scroller)) = self.inner_scroller(element) {
            scroller.press(y - track.y, track.height, now);
        }
    }

    /// 部品の中のスクロールバーのつまみをつかんだまま y(ページの中の座標)まで動かした
    pub fn drag_inner_scrollbar(&mut self, element: Element, y: f32, now: f64) {
        if let Some((track, scroller)) = self.inner_scroller(element) {
            scroller.drag(y - track.y, track.height, now);
        }
    }

    /// 部品の中のスクロールバーのつまみを放した
    pub fn release_inner_scrollbars(&mut self, now: f64) {
        for row in &mut self.rows {
            row.table_scroll.release(now);
            row.text_scroll.release(now);
        }
    }

    /// path の一覧の表で，rows の index 番目の行だけを選ぶ(除外設定の行を動かしたあと．macOS は動かした行を選んだまま)
    pub fn select_list_row(&mut self, path: &str, index: usize, now: f64) {
        for row in &mut self.rows {
            if matches!(&row.row.control, Control::List(spec, _) if spec.path == path) {
                row.table.select_row(index);
                if let Some(position) = row.table.cursor() {
                    let top = position as f32 * size::TABLE_ROW_HEIGHT;
                    row.table_scroll
                        .reveal(top, top + size::TABLE_ROW_HEIGHT, now);
                }
            }
        }
    }

    /// 表で Enter を押した．シートで書き換える一覧(コマンド)なら，選んだ 1 行を書き換えるシートを出す
    pub fn table_enter(&self, row_index: usize) -> Option<Event> {
        let row = self.rows.get(row_index)?;
        if !row.row.control.list_buttons()?.sheet {
            return None;
        }
        match row.table.selected_rows().as_slice() {
            [index] => Some(Event::EditCommand(Some(*index))),
            _ => None,
        }
    }

    /// 表で選んでいる 1 行の中の選ぶ欄(無ければ None)．キーボードで開く
    pub fn table_choice(&self, row_index: usize) -> Option<Element> {
        let row = self.rows.get(row_index)?;
        row.choice_column()?;
        let position = row.table.cursor()?;
        row.table.is_selected(position).then_some(Element {
            row: row_index,
            part: Part::TableChoice(position),
        })
    }

    /// path の一覧の表
    pub fn list_table(&self, path: &str) -> Option<Element> {
        self.rows
            .iter()
            .position(|row| matches!(&row.row.control, Control::List(spec, _) if spec.path == path))
            .map(|row| Element {
                row,
                part: Part::Table,
            })
    }

    /// path の一覧の決まりと上限
    pub fn list_spec(&self, path: &str) -> Option<(ListSpec, LimitKind)> {
        self.rows.iter().find_map(|row| match &row.row.control {
            Control::List(spec, limit) if spec.path == path => Some((*spec, *limit)),
            _ => None,
        })
    }

    /// path の一覧の field 番目の選ぶ欄で選んでいる値(設定のファイルに書く名前．除外設定の表の下の動作)
    pub fn list_choice(&self, path: &str, field: usize) -> Option<&'static str> {
        self.rows.iter().find_map(|row| {
            let Control::List(spec, _) = &row.row.control else {
                return None;
            };
            if spec.path != path {
                return None;
            }
            match row.inputs.get(field)? {
                Input::Choice(selected) => spec
                    .fields
                    .get(field)?
                    .choices?
                    .get(*selected)
                    .map(|(value, _)| *value),
                Input::Edit(_) => None,
            }
        })
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

    /// 単語の登録で受け取った語と読みを，登録した単語の一覧の入力欄(読み・単語)に入れる．
    /// 入力位置を置く読みの欄を返す(登録した単語の一覧が無いページなら None)
    pub fn fill_registration(&mut self, reading: &str, word: &str) -> Option<Element> {
        let index = self
            .rows
            .iter()
            .position(|row| matches!(row.row.control, Control::Dictionary(_)))?;
        let row = self.rows.get_mut(index)?;
        let spec = row.row.control.list_spec().copied()?;
        let mut reading_field = None;
        for (position, (field, input)) in spec.fields.iter().zip(&row.inputs).enumerate() {
            let text = match field.name {
                Some("reading") => {
                    reading_field = Some(position);
                    reading
                }
                Some("word") => word,
                _ => continue,
            };
            if let Input::Edit(window) = input {
                ffi::set_text(*window, text);
            }
        }
        row.editing = None;
        Some(Element {
            row: index,
            part: Part::Field(reading_field?),
        })
    }

    /// スライダーを x(ページの中の座標)まで動かす．値を書くのは手を離したとき(slider_release)
    pub fn slider_drag(&mut self, element: Element, x: f32) {
        let Some(row) = self.rows.get_mut(element.row) else {
            return;
        };
        if element.part == Part::Slider && row.enabled {
            row.dragging = row.slider_value(x);
        }
    }

    /// path のスライダーを動かしているあいだの値(動かしていなければ None)．
    /// 外観の見本は動かしているあいだも文字の大きさを映す(macOS の AppearancePage の fontSize)
    pub fn dragging(&self, path: &str) -> Option<f64> {
        self.rows
            .iter()
            .find(|row| row.row.path == path)
            .and_then(|row| row.dragging)
    }

    /// スライダーから手を離した．値が変わっていれば書く
    pub fn slider_release(&mut self) -> Option<Event> {
        let row = self.rows.iter_mut().find(|row| row.dragging.is_some())?;
        let value = row.dragging.take()?;
        let index = options::nearest(&row.numbers, value);
        if row.choice == Some(index) {
            return None;
        }
        row.choice = Some(index);
        Some(Event::Set {
            path: row.row.path,
            value: crate::model::number(row.numbers[index]),
            clears: row.row.clears,
        })
    }

    /// 数の部品(数を 1 段ずつ変える部品・スライダー)を delta 段動かす(キーボード)．端を越えたら端で止める
    pub fn step(&mut self, element: Element, delta: isize) -> Option<Event> {
        let row = self.rows.get_mut(element.row)?;
        if !row.enabled
            || !matches!(
                element.part,
                Part::Slider | Part::Decrement | Part::Increment
            )
        {
            return None;
        }
        row.step(delta)
    }

    /// path の一覧の入力欄のすぐ下に，入れたときの結果と置き換えられない部分(書き方の誤り)を出す(空なら出さない)
    /// 結果の行を出す・消すことになったら true(置き直す)
    pub fn show_result(&mut self, path: &str, result: &str, problems: Vec<String>) -> bool {
        let mut changed = false;
        for row in &mut self.rows {
            if row
                .row
                .control
                .list_spec()
                .is_some_and(|spec| spec.path == path)
            {
                let before = row.result_text.is_empty() && row.result_problems.is_empty();
                // 打っている途中の書き方(入力位置の前の閉じていない `{da`)は，誤りの印を付けない
                let typing = row
                    .row
                    .control
                    .template_target()
                    .and_then(|target| row.edit(Part::Field(target.field())))
                    .and_then(|window| {
                        let text = ffi::window_text(window);
                        let utf16: Vec<u16> = text.encode_utf16().collect();
                        let caret = edit::selection(window).start.min(utf16.len());
                        reference::open_placeholder(&String::from_utf16_lossy(&utf16[..caret]))
                    });
                row.result_text = result.to_string();
                row.result_problems = problems
                    .iter()
                    .filter(|problem| Some(*problem) != typing.as_ref())
                    .cloned()
                    .collect();
                let after = row.result_text.is_empty() && row.result_problems.is_empty();
                changed |= before != after;
            }
        }
        changed
    }

    /// 試した結果を出す
    pub fn show_preview(&mut self, kind: TryKind, shown: &crate::engine::PreviewShown) {
        for row in &mut self.rows {
            if row.row.control == Control::Preview(kind)
                || row.row.control == Control::PreviewChips(kind)
            {
                row.preview_result.clone_from(shown);
            }
        }
    }

    /// 見本の画像を描く場所(ページの中の座標)と，描くもの(外観の見本・パレットの見本・情報のページのアイコン)
    pub fn preview_rect(&self) -> Option<(PreviewKind, Rect)> {
        self.rows.iter().filter(|row| row.visible).find_map(|row| {
            let card = row.card.as_ref()?;
            match row.row.control {
                Control::ThemePreview => Some((PreviewKind::Theme, card.control)),
                Control::PalettePreview => Some((PreviewKind::Palette, card.control)),
                Control::EmojiPreview => Some((PreviewKind::Emoji, card.control)),
                Control::Version => Some((PreviewKind::Icon, card.icon)),
                _ => None,
            }
        })
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
        if self.titled && frame.shows(self.layout.title) {
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
            // まとまりの行は 1 枚のカードにまとめ，行のあいだに区切り線を引く(macOS の Form の grouped)．
            // 切り替えの帯(Segmented)はカードに入れない
            let rows = self.sections.get(index).map(|section| &section.rows);
            let grouped: Vec<Rect> = section
                .cards
                .iter()
                .filter(|card| {
                    let control = rows
                        .and_then(|rows| rows.get(card.row))
                        .map(|row| &row.control);
                    !matches!(control, Some(Control::Segmented(_)))
                })
                .map(|card| card.card)
                .collect();
            if let (Some(first), Some(last)) = (grouped.first(), grouped.last()) {
                let group = Rect::new(first.x, first.y, first.width, last.max_y() - first.y);
                if frame.shows(group) {
                    canvas.fill_round(group, size::CARD_RADIUS, Color::from(palette.card));
                    canvas.stroke_round(
                        group,
                        size::CARD_RADIUS,
                        1.0,
                        Color::from(palette.card_stroke),
                    );
                    for card in grouped.iter().skip(1) {
                        canvas.fill_rect(
                            Rect::new(
                                card.x + size::CARD_PADDING_X,
                                card.y,
                                (card.width - size::CARD_PADDING_X * 2.0).max(0.0),
                                1.0,
                            ),
                            Color::from(palette.card_stroke),
                        );
                    }
                }
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
            // 辞書の一覧の取り込むボタンはカードの下にあるので，ボタンだけ見えていても描く
            let shown = row.card.as_ref().is_some_and(|card| {
                frame.shows(card.card) || card.parts.iter().any(|part| frame.shows(*part))
            });
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
        // テーマの行はカードのどこを押しても選ぶので，ポインターを載せたらカードの背景を変える(名前より先に塗る)
        if let Control::ThemeOption(_) | Control::CustomTheme(_) = row.row.control {
            let hover = self.hover_value(
                Element {
                    row: index,
                    part: Part::Radio,
                },
                frame.now,
            );
            canvas.fill_round(
                card.card,
                size::CARD_RADIUS,
                Color::from(palette.nav_hover).with_alpha(hover),
            );
        }
        // 値の右のボタンだけを使えなくする行(今すぐ同期)は，名前と値をふつうの色で出す
        let label_color = if row.row.control == Control::Placeholder {
            palette.text_secondary
        } else if row.enabled || matches!(row.row.control, Control::Note | Control::InfoAction(..))
        {
            palette.text
        } else {
            palette.text_disabled
        };
        let label_style = if row.row.control == Control::Version {
            TextStyle::Subtitle
        } else {
            TextStyle::Body
        };
        if card.label.width > 0.0 && card.label.height > 0.0 {
            // 名前が収まらなければ折り返す(狭い窓で名前を消さない)
            let layout = if card.label.height > size::BODY_LINE_HEIGHT {
                TextLayout::WRAP
            } else {
                TextLayout::LINE
            };
            let title = match row.row.control {
                Control::Version => text::APP_NAME.to_string(),
                _ => row.title(),
            };
            canvas.text(
                card.label,
                &title,
                label_style,
                Color::from(label_color),
                layout,
            );
        }
        if let Some(example) = row.row.example.filter(|_| row.shows_example) {
            example_chip(canvas, theme, card.icon, example, row.enabled);
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
            let color = if note.row.danger {
                palette.danger
            } else {
                palette.text_secondary
            };
            canvas.text(
                *rect,
                note.row.title,
                TextStyle::Caption,
                Color::from(color),
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
            Control::Stepper(_) => {
                let value = row
                    .number()
                    .map(|value| row.number_text(value))
                    .unwrap_or_default();
                paint::stepper_frame(canvas, theme, card.control, &value, row.enabled);
                for (part, glyph) in [
                    (Part::Decrement, theme.glyphs.minus),
                    (Part::Increment, theme.glyphs.plus),
                ] {
                    if let Some(rect) = row.part_rect(part) {
                        let inset = space::INSET;
                        let rect = Rect::new(
                            rect.x,
                            rect.y + inset,
                            rect.width - inset,
                            rect.height - inset * 2.0,
                        );
                        paint::button(
                            canvas,
                            theme,
                            rect,
                            glyph,
                            paint::ButtonKind::Quiet,
                            self.state(frame, element(part), row.part_enabled(part)),
                        );
                    }
                }
            }
            Control::Seconds(_) | Control::Slider(_) => {
                let slider = element(Part::Slider);
                let mut state = self.state(frame, slider, row.enabled);
                state.pressed |= row.dragging.is_some();
                if let Some(rect) = row.slider_rect() {
                    paint::slider(canvas, theme, rect, row.slider_progress(), state);
                }
                if row.shows_value() {
                    let value = row
                        .number()
                        .map(|value| row.number_text(value))
                        .unwrap_or_default();
                    let color = if row.enabled {
                        palette.text
                    } else {
                        palette.text_disabled
                    };
                    canvas.text(
                        Rect::new(
                            card.control.max_x() - size::SECONDS_LABEL_WIDTH,
                            card.control.y,
                            size::SECONDS_LABEL_WIDTH,
                            card.control.height,
                        ),
                        &value,
                        TextStyle::Body,
                        Color::from(color),
                        TextLayout::TRAILING,
                    );
                }
            }
            Control::ThemeOption(value) => {
                let radio = element(Part::Radio);
                let state = self.state(frame, radio, row.enabled);
                if let Some(rect) = card.parts.first() {
                    paint::radio(canvas, theme, *rect, row.on, state);
                }
                paint_swatch(canvas, theme, card.icon, value, None);
                if state.focus_visible {
                    paint::focus_ring(canvas, theme, card.card, size::CARD_RADIUS);
                }
            }
            Control::CustomTheme(_) => self.paint_custom_theme(canvas, frame, index, row),
            // 切り替えの帯(macOS の segmented の Picker)．溝は薄い灰色で，選んだところだけを浮かせて描く
            Control::Segmented(_) => {
                canvas.fill_round(
                    card.control,
                    size::CONTROL_RADIUS,
                    Color::from(palette.nav_selected),
                );
                for part in row.parts() {
                    if let (Part::Segment(position), Some(rect)) = (part, row.part_rect(part)) {
                        paint::segment(
                            canvas,
                            theme,
                            rect,
                            row.button_label(part),
                            row.choice == Some(position),
                            self.state(frame, element(part), row.enabled),
                        );
                    }
                }
            }
            Control::Buttons(buttons) => {
                for (position, (label, action)) in buttons.iter().enumerate() {
                    let part = Part::Button(position);
                    if let Some(rect) = row.part_rect(part) {
                        paint::button(
                            canvas,
                            theme,
                            rect,
                            label,
                            button_kind(*action),
                            self.state(frame, element(part), row.enabled),
                        );
                    }
                }
            }
            Control::InfoAction(..) => {
                canvas.text(
                    card.control,
                    &row.text,
                    TextStyle::Body,
                    Color::from(palette.text_secondary),
                    value_layout(card),
                );
                if let Some(rect) = row.part_rect(Part::Action) {
                    paint::button(
                        canvas,
                        theme,
                        rect,
                        row.button_label(Part::Action),
                        paint::ButtonKind::Standard,
                        self.state(frame, element(Part::Action), row.enabled),
                    );
                }
            }
            Control::PalettePreview | Control::EmojiPreview => canvas.preview(card.control),
            Control::Choice(_) | Control::ThemeFont(_) | Control::Preset => {
                let dropdown = element(Part::Dropdown);
                let items = row.dropdown_items(Part::Dropdown);
                // ひな形は今の表に合うひな形の名前を出す．合わなければ「カスタム」(macOS の currentPreset)
                let label = match row.row.control {
                    Control::Preset => keys::current_preset(
                        row.choice
                            .and_then(|choice| items.get(choice))
                            .map_or(keys::CUSTOM_PRESET, String::as_str),
                    ),
                    _ => row
                        .choice
                        .and_then(|choice| items.get(choice))
                        .cloned()
                        .unwrap_or_default(),
                };
                paint::dropdown(
                    canvas,
                    theme,
                    card.control,
                    &label,
                    frame.open == Some(dropdown),
                    self.state(frame, dropdown, row.enabled),
                );
            }
            Control::Action(kind) => {
                let action = element(Part::Action);
                paint::button(
                    canvas,
                    theme,
                    card.control,
                    row.row.title,
                    button_kind(*kind),
                    self.state(frame, action, row.enabled),
                );
            }
            Control::Color => self.paint_color(canvas, frame, index, row, card.control),
            Control::LabeledAction(_, label) => {
                let action = element(Part::Action);
                paint::button(
                    canvas,
                    theme,
                    card.control,
                    label,
                    paint::ButtonKind::Standard,
                    self.state(frame, action, row.enabled),
                );
            }
            Control::Acknowledgement(_) => self.paint_acknowledgement(canvas, frame, index, row),
            Control::Version => {
                canvas.preview(card.icon);
                canvas.text(
                    card.control,
                    &row.text,
                    TextStyle::Body,
                    Color::from(palette.text_secondary),
                    TextLayout::LINE,
                );
                if let Some(rect) = row.part_rect(Part::Action) {
                    let update = element(Part::Action);
                    paint::button(
                        canvas,
                        theme,
                        rect,
                        more::CHECK_FOR_UPDATES,
                        paint::ButtonKind::Standard,
                        self.state(frame, update, row.enabled),
                    );
                }
            }
            Control::Stat(_) | Control::Info(_) => {
                let color = if row.enabled {
                    palette.text_secondary
                } else {
                    palette.text_disabled
                };
                canvas.text(
                    card.control,
                    &row.text,
                    TextStyle::Body,
                    Color::from(color),
                    value_layout(card),
                );
            }
            Control::KeymapReport => {
                self.paint_text_box(canvas, frame, index, row, card.control);
            }
            Control::ThemeIssue(_) => paint_issue(canvas, theme, card.control, &row.text),
            Control::TextField => self.paint_field(canvas, frame, index, row, Part::Field(0)),
            Control::ThemePreview => canvas.preview(card.control),
            // 変換マクロの試す欄には下のボタンが無い(part_rect が無いので描かない)
            Control::PreviewChips(_) => {
                let gap = tokens::size::settings::PREVIEW_CHIP_GAP;
                preview_chips(
                    canvas,
                    theme,
                    card.control,
                    &row.preview_result,
                    gap,
                    &|_| None,
                );
            }
            Control::Preview(kind) => {
                for field in 0..2 {
                    self.paint_field(canvas, frame, index, row, Part::PreviewField(field));
                }
                // 英語と日本語の結果は押せるチップなので group で離す(押せる部品どうし)
                let gap = if *kind == TryKind::Language {
                    tokens::size::settings::PREVIEW_BUTTON_GAP
                } else {
                    tokens::size::settings::PREVIEW_CHIP_GAP
                };
                // 英語と日本語の結果のタグは押せる(押すと，その語をいつも英語・いつも日本語にする単語に足すメニューを出す)
                let chip_state = |chip: usize| {
                    (*kind == TryKind::Language && chip_opens_menu(&row.preview_result, chip))
                        .then(|| self.state(frame, element(Part::PreviewChip(chip)), row.enabled))
                };
                preview_chips(
                    canvas,
                    theme,
                    card.control,
                    &row.preview_result,
                    gap,
                    &chip_state,
                );
            }
            Control::Note | Control::Placeholder => {}
            Control::Dictionaries(_) => self.paint_dictionaries(canvas, frame, index, row),
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
            row.field_frame(part).unwrap_or(rect),
            focused,
            self.state(frame, element, row.enabled),
        );
        if frame.draw_fields {
            // 見本の書き出しでは EDIT が写らないので，欄の文字か案内を描く
            let text = window.map(ffi::window_text).unwrap_or_default();
            let (shown, color) = if row.recording == Some(part) {
                // 記録しているあいだは，欄が出す案内を描く
                (keys::PRESS.to_string(), frame.theme.palette.text_secondary)
            } else if text.is_empty() {
                (self.name(element), frame.theme.palette.text_secondary)
            } else {
                (text, frame.theme.palette.text)
            };
            let padding = if row.holds_key_button(part) {
                size::FIELD_PADDING_X
            } else {
                size::FIELD_PADDING_X * 2.0
            };
            let inner = Rect::new(
                rect.x + size::FIELD_PADDING_X,
                rect.y,
                rect.width - padding,
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

    /// カスタムテーマの行(macOS の CustomThemeRow)．選ぶ印・見本の色・名前・読みにくい印と，右に編集・複製・削除の絵のボタン
    fn paint_custom_theme(
        &self,
        canvas: &mut dyn Canvas,
        frame: &Frame,
        index: usize,
        row: &RowState,
    ) {
        let theme = frame.theme;
        let Some(card) = &row.card else { return };
        let element = |part| Element { row: index, part };
        let state = self.state(frame, element(Part::Radio), row.enabled);
        paint::radio(canvas, theme, card.control, row.on, state);
        if let Some(custom) = &row.custom {
            paint_swatch(canvas, theme, card.icon, &custom.base, Some(custom));
        }
        // 読みにくい組み合わせがあれば，名前の右に注意の印を出す(macOS の exclamationmark.triangle.fill)
        if let (true, Some(mark)) = (row.warns, card.parts.get(ThemeAction::ROW.len())) {
            canvas.text(
                *mark,
                theme.glyphs.warning,
                TextStyle::IconSmall,
                Color::from(theme.palette.caution),
                TextLayout::CENTER,
            );
        }
        for position in 0..ThemeAction::ROW.len() {
            let part = Part::Button(position);
            let Some(rect) = row.part_rect(part) else {
                continue;
            };
            let glyph = match ThemeAction::ROW[position] {
                ThemeAction::Edit => theme.glyphs.edit,
                ThemeAction::Duplicate => theme.glyphs.copy,
                _ => theme.glyphs.delete,
            };
            paint::button(
                canvas,
                theme,
                rect,
                glyph,
                paint::ButtonKind::Quiet,
                self.state(frame, element(part), row.part_enabled(part)),
            );
        }
        if state.focus_visible {
            if let Some(rect) = row.part_rect(Part::Radio) {
                paint::focus_ring(canvas, theme, rect, size::CARD_RADIUS);
            }
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
        // 読みにくい組み合わせに入る色は，色のボタンの左に注意の印を出す(macOS の CustomThemeEditor)
        if row.warns {
            let icon = size::ICON_FONT_SIZE;
            canvas.text(
                Rect::new(rect.x - size::CONTROL_GAP - icon, rect.y, icon, rect.height),
                theme.glyphs.warning,
                TextStyle::IconSmall,
                Color::from(palette.caution),
                TextLayout::CENTER,
            );
        }
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
        let left = swatch.max_x() + gap;
        canvas.text(
            Rect::new(left, rect.y, rect.max_x() - gap - left, rect.height),
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
        // 行ごとに置く．キーの無い確定・取り消しの行は注意の印を付ける(macOS の KeymapPage の missingWarning)．
        // 印の無い行も同じ左の端から書き，文の列をそろえる
        let left = rect.x + padding;
        let top = rect.y + size::FIELD_PADDING_Y - offset;
        let inner = rect.width - padding * 2.0;
        let icon = size::ICON_FONT_SIZE;
        for line in report_lines(&row.text, row.text_marks, inner, &*canvas) {
            if line.marked {
                canvas.text(
                    Rect::new(left, top + line.top, icon, size::NOTE_LINE_HEIGHT),
                    theme.glyphs.warning,
                    TextStyle::IconSmall,
                    Color::from(palette.caution),
                    TextLayout::CENTER,
                );
            }
            canvas.text(
                Rect::new(
                    left + icon + space::INLINE,
                    top + line.top,
                    (inner - icon - space::INLINE).max(0.0),
                    line.height,
                ),
                line.text,
                TextStyle::Caption,
                Color::from(palette.text),
                TextLayout::WRAP,
            );
        }
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

    /// 謝辞の 1 項目(名前・出どころ・ライセンスの全文を開くボタンと全文)．macOS の AcknowledgementRow
    fn paint_acknowledgement(
        &self,
        canvas: &mut dyn Canvas,
        frame: &Frame,
        index: usize,
        row: &RowState,
    ) {
        let theme = frame.theme;
        let palette = &theme.palette;
        let Some(layout) = &row.acknowledgement else {
            return;
        };
        let Some(item) = row.notice() else {
            canvas.text(
                layout.name,
                row.row.title,
                TextStyle::Body,
                Color::from(palette.text_secondary),
                TextLayout::LINE,
            );
            return;
        };
        canvas.text(
            layout.name,
            &item.name,
            TextStyle::Section,
            Color::from(palette.text),
            TextLayout::LINE,
        );
        let secondary = Color::from(palette.text_secondary);
        for (position, (line, (rect, link))) in item.sources.iter().zip(&layout.sources).enumerate()
        {
            match (crate::notices::split_url(line), link) {
                // URL の前置きは文字で，URL は押せる色で出す(macOS の Link)
                (Some((prefix, url, suffix)), Some(link))
                    if link.height <= size::NOTE_LINE_HEIGHT =>
                {
                    if !prefix.is_empty() {
                        // 前置きは URL と同じ 1 行目に置く(行全体の高さで真ん中に置くと，下に折り返した文と重なる)
                        canvas.text(
                            Rect::new(rect.x, rect.y, rect.width, size::NOTE_LINE_HEIGHT),
                            prefix,
                            TextStyle::Caption,
                            secondary,
                            TextLayout::LINE,
                        );
                    }
                    let element = Element {
                        row: index,
                        part: Part::Link(position),
                    };
                    let state = self.state(frame, element, row.enabled);
                    let accent = Color::from(palette.accent);
                    let color = accent.mix(
                        Color::from(palette.text),
                        state.hover * opacity::LINK_HOVER_MIX,
                    );
                    canvas.text(*link, url, TextStyle::Caption, color, TextLayout::LINE);
                    // 押せることを下線で示す(ポインターを載せると濃くする)
                    canvas.fill_rect(
                        Rect::new(link.x, link.max_y() - space::FINE, link.width, part::STROKE),
                        color.with_alpha(opacity::LINK + (1.0 - opacity::LINK) * state.hover),
                    );
                    // URL のあとの文(「(v0.2.0)」など)はリンクにせず，URL と同じ行に収まる分を続けて書き，残りを下に折り返す
                    if !suffix.trim().is_empty() {
                        let (head, rest) =
                            split_to_width(canvas, suffix, rect.max_x() - link.max_x());
                        canvas.text(
                            Rect::new(
                                link.max_x(),
                                rect.y,
                                (rect.max_x() - link.max_x()).max(0.0),
                                size::NOTE_LINE_HEIGHT,
                            ),
                            head,
                            TextStyle::Caption,
                            secondary,
                            TextLayout::LINE,
                        );
                        if !rest.trim().is_empty() {
                            canvas.text(
                                Rect::new(
                                    rect.x,
                                    rect.y + size::NOTE_LINE_HEIGHT,
                                    rect.width,
                                    rect.height - size::NOTE_LINE_HEIGHT,
                                ),
                                rest.trim(),
                                TextStyle::Caption,
                                secondary,
                                TextLayout::WRAP,
                            );
                        }
                    }
                    if state.focus_visible {
                        paint::focus_ring(canvas, theme, *link, size::CONTROL_RADIUS);
                    }
                }
                (Some(_), Some(link)) => {
                    let element = Element {
                        row: index,
                        part: Part::Link(position),
                    };
                    let state = self.state(frame, element, row.enabled);
                    let accent = Color::from(palette.accent);
                    canvas.text(*link, line, TextStyle::Caption, accent, TextLayout::WRAP);
                    if state.focus_visible {
                        paint::focus_ring(canvas, theme, *link, size::CONTROL_RADIUS);
                    }
                }
                _ => canvas.text(*rect, line, TextStyle::Caption, secondary, TextLayout::WRAP),
            }
        }
        if let Some(button) = layout.expand {
            let element = Element {
                row: index,
                part: Part::Expand,
            };
            let state = self.state(frame, element, row.enabled);
            if state.hover > 0.0 || state.pressed {
                let opacity = tokens::opacity::settings::SUBTLE_HOVER
                    * if state.pressed { 2.0 } else { state.hover };
                canvas.fill_round(
                    button,
                    size::CONTROL_RADIUS,
                    Color::from(palette.text).with_alpha(opacity),
                );
            }
            let glyph = if row.expanded {
                theme.glyphs.chevron_down
            } else {
                theme.glyphs.chevron_right
            };
            let padding = space::INSET;
            canvas.text(
                Rect::new(
                    button.x + padding,
                    button.y,
                    size::CHEVRON_SIZE,
                    button.height,
                ),
                glyph,
                TextStyle::IconSmall,
                Color::from(palette.text_secondary),
                TextLayout::CENTER,
            );
            canvas.text(
                Rect::new(
                    button.x + padding + size::CHEVRON_SIZE + space::INLINE,
                    button.y,
                    button.width - padding * 2.0 - size::CHEVRON_SIZE - space::INLINE,
                    button.height,
                ),
                more::LICENSE_TEXT,
                TextStyle::Body,
                Color::from(palette.text),
                TextLayout::LINE,
            );
            if state.focus_visible {
                paint::focus_ring(canvas, theme, button, size::CONTROL_RADIUS);
            }
        }
        if let (Some(rect), Some(text)) = (layout.license, &item.license) {
            canvas.fill_round(rect, size::CONTROL_RADIUS, Color::from(palette.control));
            canvas.stroke_round(
                rect,
                size::CONTROL_RADIUS,
                1.0,
                Color::from(palette.control_stroke),
            );
            let padding = size::FIELD_PADDING_X;
            canvas.text(
                Rect::new(
                    rect.x + padding,
                    rect.y + padding,
                    rect.width - padding * 2.0,
                    rect.height - padding * 2.0,
                ),
                text,
                TextStyle::Mono,
                Color::from(palette.text),
                TextLayout::WRAP,
            );
        }
    }

    fn paint_list(&self, canvas: &mut dyn Canvas, frame: &Frame, index: usize, row: &RowState) {
        let theme = frame.theme;
        // 打った行の確かめの文(問題は注意の色と警告の印，上書きの知らせは薄い文字と情報の印)を表のすぐ上に出す
        if let (Some((text, problem)), Some(table)) =
            (row.input_message(), row.part_rect(Part::Table))
        {
            let line = Rect::new(
                table.x,
                table.y - size::NOTE_LINE_HEIGHT - space::STACK,
                table.width,
                size::NOTE_LINE_HEIGHT,
            );
            let (glyph, color) = if problem {
                (theme.glyphs.warning, theme.palette.caution)
            } else {
                (theme.glyphs.info, theme.palette.text_secondary)
            };
            canvas.text(
                Rect::new(
                    line.x,
                    line.y,
                    size::CHEVRON_SIZE + size::CONTROL_GAP,
                    line.height,
                ),
                glyph,
                TextStyle::IconSmall,
                Color::from(color),
                TextLayout::LINE,
            );
            let left = line.x + size::CHEVRON_SIZE + size::CONTROL_GAP;
            canvas.text(
                Rect::new(left, line.y, (line.max_x() - left).max(0.0), line.height),
                &text,
                TextStyle::Caption,
                Color::from(color),
                TextLayout::LINE,
            );
        }
        // 入れたときの結果(入力欄のすぐ下．結果を求めた欄の左端から)．置き換えられない部分は，その書き方のまま印を付けて添える
        if !(row.result_text.is_empty() && row.result_problems.is_empty()) {
            if let Some(rect) = row.card.as_ref().and_then(|card| card.result) {
                let shown = format!("{}{}", text::RESULT_MARK, row.result_text);
                canvas.text(
                    rect,
                    &shown,
                    TextStyle::Body,
                    Color::from(theme.palette.text_secondary),
                    TextLayout::LINE,
                );
                if !row.result_problems.is_empty() {
                    let left =
                        rect.x + canvas.width(&shown, TextStyle::Body) + tokens::size::space::GROUP;
                    canvas.text(
                        Rect::new(left, rect.y, (rect.max_x() - left).max(0.0), rect.height),
                        &format!("{}{}", text::PROBLEM_MARK, row.result_problems.join(" ")),
                        TextStyle::Body,
                        Color::from(theme.palette.caution),
                        TextLayout::LINE,
                    );
                }
            }
        }
        // 書き方のチップを開け閉めするボタン(開いているあいだはアクセントの色．WinUI の ToggleButton)と，チップの欄
        if let Some(rect) = row.part_rect(Part::TemplateButton) {
            let element = Element {
                row: index,
                part: Part::TemplateButton,
            };
            let kind = if row.template_open {
                paint::ButtonKind::Accent
            } else {
                paint::ButtonKind::Standard
            };
            paint::button(
                canvas,
                theme,
                rect,
                text::TEMPLATE_BUTTON_LABEL,
                kind,
                self.state(frame, element, row.enabled),
            );
        }
        if let Some(target) = row.row.control.template_target() {
            if row.template_panel_open() {
                self.paint_template_panel(canvas, frame, index, row, target.groups());
            }
        }
        // 打つもの → 置き換えるものの矢印(macOS の RuleListEditor の arrow.right)
        let arrow = row
            .row
            .control
            .list_buttons()
            .and_then(|buttons| buttons.arrow);
        if let Some((first, second)) = arrow.and_then(|index| {
            Some((
                row.part_rect(Part::Field(index))?,
                row.part_rect(Part::Field(index + 1))?,
            ))
        }) {
            let color = if row.enabled {
                theme.palette.text_secondary
            } else {
                theme.palette.text_disabled
            };
            canvas.text(
                Rect::new(
                    first.max_x(),
                    first.y,
                    second.x - first.max_x(),
                    first.height,
                ),
                theme.glyphs.arrow_right,
                TextStyle::IconSmall,
                Color::from(color),
                TextLayout::CENTER,
            );
        }
        // 欄の前に置く名前(判別ルールの「直前」)．欄のすぐ左に，欄と同じ間を空けて置く
        if let Some((field, text)) = row
            .row
            .control
            .list_buttons()
            .and_then(|buttons| buttons.caption)
        {
            if let Some(rect) = row.part_rect(Part::Field(field)) {
                let width = canvas.width(text, TextStyle::Body).ceil();
                let color = if row.enabled {
                    theme.palette.text_secondary
                } else {
                    theme.palette.text_disabled
                };
                canvas.text(
                    Rect::new(
                        rect.x - size::CONTROL_GAP - width,
                        rect.y,
                        width,
                        rect.height,
                    ),
                    text,
                    TextStyle::Body,
                    Color::from(color),
                    TextLayout::CENTER,
                );
            }
        }
        for part in row.parts() {
            let element = Element { row: index, part };
            let Some(rect) = row.part_rect(part) else {
                continue;
            };
            match part {
                Part::Field(_) | Part::Filter if row.is_dropdown(part) => {
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
                Part::KeySearch => {
                    let state = self.state(frame, element, row.part_enabled(part));
                    match row.key_chip() {
                        // 押したキーで絞り込んでいるあいだは，キーの名前と外す印のチップにする(押すと外す)
                        Some(chip) => {
                            paint::button(
                                canvas,
                                theme,
                                rect,
                                "",
                                paint::ButtonKind::Standard,
                                state,
                            );
                            let (label, mark) = key_chip_areas(rect);
                            canvas.text(
                                label,
                                &chip,
                                TextStyle::Body,
                                Color::from(theme.palette.text),
                                TextLayout::LINE,
                            );
                            canvas.text(
                                mark,
                                theme.glyphs.close,
                                TextStyle::IconSmall,
                                Color::from(theme.palette.text_secondary),
                                TextLayout::CENTER,
                            );
                        }
                        None => paint::button(
                            canvas,
                            theme,
                            rect,
                            keys::SEARCH_BY_KEY,
                            paint::ButtonKind::Standard,
                            state,
                        ),
                    }
                }
                // キーの欄の枠の中の右の端の絵のボタン(名前は説明の吹き出しと読み上げに出す)
                Part::KeyMenu | Part::KeyStop => paint::field_button(
                    canvas,
                    theme,
                    rect,
                    if part == Part::KeyStop {
                        theme.glyphs.close
                    } else {
                        theme.glyphs.chevron_down
                    },
                    self.state(frame, element, row.part_enabled(part)),
                ),
                Part::Top(_) | Part::Bottom(_) => {
                    let label = row.button_label(part);
                    let icon = row
                        .row
                        .control
                        .list_buttons()
                        .is_some_and(|buttons| buttons.is_icon(label));
                    let kind = if part == Part::Top(0) && row.has_add_remove() {
                        paint::ButtonKind::Accent
                    } else if icon {
                        paint::ButtonKind::Icon
                    } else {
                        paint::ButtonKind::Standard
                    };
                    // 優先度を上げる・下げるは山形の絵で描く(名前は説明の吹き出しと読み上げに出す)
                    let shown = match label {
                        _ if !icon => label,
                        crate::strings::dictionaries::MOVE_UP => theme.glyphs.chevron_up,
                        _ => theme.glyphs.chevron_down,
                    };
                    paint::button(
                        canvas,
                        theme,
                        rect,
                        shown,
                        kind,
                        self.state(frame, element, row.part_enabled(part)),
                    );
                }
                Part::Table => self.paint_table(canvas, frame, index, row, rect),
                _ => {}
            }
        }
        // 絞り込める表は，出している行の数を表の下の帯の左の組(削除など)のすぐ右に出す(macOS の KeymapPage の行の数)
        if let Some(buttons) = row.row.control.list_buttons() {
            let leading = buttons.bottom.len().saturating_sub(buttons.trailing_bottom);
            if buttons.filter && leading > 0 {
                if let Some(rect) = row.part_rect(Part::Bottom(leading - 1)) {
                    let left = rect.max_x() + size::CONTROL_GAP;
                    let right = row
                        .part_rect(Part::Bottom(leading))
                        .map_or(left, |next| next.x - size::CONTROL_GAP);
                    canvas.text(
                        Rect::new(left, rect.y, (right - left).max(0.0), rect.height),
                        &keys::row_count(row.table.len(), row.table.total()),
                        TextStyle::Caption,
                        Color::from(theme.palette.text_secondary),
                        TextLayout::LINE,
                    );
                }
            }
        }
    }

    /// 書き方のチップの欄(macOS の TemplatePalette と同じ形)．上にまとまりの切り替え(絞り込んでいるあいだは無し)，
    /// 下にチップと値．チップにポインターを載せたらチップの背景を濃くする(押すと欄に入る)．
    /// キーボードで選んでいるチップにはフォーカスの枠を付ける．当たるチップが無ければその知らせを出す
    fn paint_template_panel(
        &self,
        canvas: &mut dyn Canvas,
        frame: &Frame,
        index: usize,
        row: &RowState,
        groups: &[reference::Group],
    ) {
        use tokens::opacity::settings::SUBTLE_SELECTED;
        use tokens::size::part;
        let palette = &frame.theme.palette;
        let text = Color::from(palette.text);
        let secondary = Color::from(palette.text_secondary);
        for (position, rect) in row.template_switch.iter().enumerate() {
            let element = Element {
                row: index,
                part: Part::TemplateSegment(position),
            };
            let title = groups.get(position).map_or("", |group| group.title);
            paint::segment(
                canvas,
                frame.theme,
                *rect,
                title,
                position == row.template_group,
                self.state(frame, element, row.enabled),
            );
        }
        let (left, top) = row.template_origin;
        let items = row.template_items().unwrap_or_default();
        if items.is_empty() {
            let width = row
                .card
                .as_ref()
                .and_then(|card| card.template_panel)
                .map_or(0.0, |panel| panel.width);
            canvas.text(
                Rect::new(left, top, width, size::BODY_LINE_HEIGHT),
                rule_list::NO_MATCHES,
                TextStyle::Caption,
                secondary,
                TextLayout::LINE,
            );
            return;
        }
        let place = |rect: Rect| Rect::new(left + rect.x, top + rect.y, rect.width, rect.height);
        let focused = frame.focus_visible
            && frame.focus
                == Some(Element {
                    row: index,
                    part: Part::TemplateChips,
                });
        for chip in &row.template_chips.chips {
            let Some((item, _)) = items.get(chip.item) else {
                continue;
            };
            let hovered = self.template_hover == Some((index, chip.item));
            canvas.fill_round(
                place(chip.tag),
                part::TAG_RADIUS,
                text.with_alpha(if hovered {
                    SUBTLE_SELECTED * 2.0
                } else {
                    SUBTLE_SELECTED
                }),
            );
            canvas.text(
                place(chip.code),
                item.code,
                TextStyle::Mono,
                text,
                TextLayout::WRAP,
            );
            if chip.value.width > 0.0 {
                let style = if item.code_value {
                    TextStyle::Mono
                } else {
                    TextStyle::Caption
                };
                let value = reference::value_of(item, row.lines.get(chip.item).map(String::as_str));
                canvas.text(place(chip.value), value, style, secondary, TextLayout::WRAP);
            }
            if focused && chip.item == row.template_cursor {
                paint::focus_ring(canvas, frame.theme, place(chip.area), part::TAG_RADIUS);
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
        let layout = row.row.control.table_layout();
        let padding = size::FIELD_PADDING_X;
        let spans = layout.spans(rect.width, padding);
        let header = Rect::new(rect.x, rect.y, rect.width, size::TABLE_HEADER_HEIGHT);
        let sort = row.table.sort();
        for (column, (left, width)) in layout.columns.iter().zip(&spans) {
            let cell = Rect::new(
                header.x + left,
                header.y,
                (width - padding).max(0.0),
                header.height,
            );
            canvas.text(
                cell,
                column.title,
                TextStyle::Caption,
                Color::from(palette.text_secondary),
                TextLayout::LINE,
            );
            // 並べ替えている列には向きの印を付ける(macOS の表の見出しの山形)
            if let Some((_, ascending)) = sort.filter(|(sorted, _)| *sorted == column.source) {
                let title = canvas.width(column.title, TextStyle::Caption);
                let glyph = if ascending {
                    theme.glyphs.chevron_up
                } else {
                    theme.glyphs.chevron_down
                };
                canvas.text(
                    Rect::new(
                        cell.x + title + space::INLINE,
                        cell.y,
                        size::CHEVRON_SIZE,
                        cell.height,
                    ),
                    glyph,
                    TextStyle::IconSmall,
                    Color::from(palette.text_secondary),
                    TextLayout::LINE,
                );
            }
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
            // 行はあるのに検索・絞り込みで無くなったときは「一致する項目はありません」(macOS と同じ)．
            // 一覧の形はカスタムテーマの一覧も含めて部品から引く
            let spec = row.row.control.list_spec();
            let empty = if row.table.total() > 0 {
                match spec.map(|spec| spec.path) {
                    Some("keymap") => crate::strings::keys::NO_MATCHES,
                    _ => crate::strings::rule_list::NO_MATCHES,
                }
            } else {
                spec.map_or("", |spec| spec.empty)
            };
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
            // 左右は表の枠から離し，上下は隣の行の背景と 1 ドットずつ離す
            let inset = size::TABLE_ROW_INSET;
            let line = Rect::new(
                rect.x + inset,
                top + part::STROKE,
                rect.width - inset * 2.0,
                row_height - part::STROKE * 2.0,
            );
            let selected = row.table.is_selected(position);
            if selected {
                canvas.fill_round(
                    line,
                    size::CONTROL_RADIUS,
                    Color::from(palette.nav_selected),
                );
                let indicator =
                    size::NAV_INDICATOR_HEIGHT.min(row_height - size::TABLE_INDICATOR_INSET);
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
            // 1 行おきに薄く敷く(macOS の表の縞)．選んだ行とポインターを載せた行は上の背景のまま
            if position % 2 == 1 && !selected && self.table_hover != Some((index, position)) {
                canvas.fill_rect(
                    Rect::new(
                        rect.x + part::STROKE,
                        top,
                        rect.width - part::STROKE * 2.0,
                        row_height,
                    ),
                    Color::from(palette.text).with_alpha(opacity::TABLE_STRIPE),
                );
            }
            // 使えない一覧と，無効にした行は薄く出す(macOS と同じ)
            let enabled = row.enabled && layout.row_enabled(cells);
            let text = if row.enabled {
                palette.text
            } else {
                palette.text_disabled
            };
            let secondary = if row.enabled {
                palette.text_secondary
            } else {
                palette.text_disabled
            };
            for (column, (left, width)) in layout.columns.iter().zip(&spans) {
                let cell_rect =
                    Rect::new(rect.x + left, top, (width - padding).max(0.0), row_height);
                let value = cells.get(column.source).map_or("", String::as_str);
                let (style, color) = match column.cell {
                    Cell::Check => {
                        paint_check(canvas, theme, cell_rect, !value.is_empty(), row.enabled);
                        continue;
                    }
                    Cell::Choice => {
                        let element = Element {
                            row: index,
                            part: Part::TableChoice(position),
                        };
                        let state = self.state(frame, element, row.enabled);
                        paint_table_choice(
                            canvas,
                            theme,
                            row.part_rect(element.part).unwrap_or(cell_rect),
                            value,
                            frame.open == Some(element),
                            state,
                        );
                        continue;
                    }
                    Cell::Path => {
                        let shown = paint::truncate_middle(
                            &*canvas,
                            value,
                            TextStyle::Body,
                            cell_rect.width,
                        );
                        canvas.text(
                            cell_rect,
                            &shown,
                            TextStyle::Body,
                            Color::from(if enabled { text } else { secondary }),
                            TextLayout::LINE,
                        );
                        continue;
                    }
                    Cell::Mark => {
                        // 使われない行は塗った警告，一部の状態で使われない行は情報，文字を打てなくなる行は線の警告
                        let (glyph, color) = match value {
                            pages::keymap_mark::HIDDEN => (theme.glyphs.warning, palette.caution),
                            pages::keymap_mark::PARTLY => {
                                (theme.glyphs.info, palette.text_secondary)
                            }
                            pages::keymap_mark::BLOCKS => {
                                (theme.glyphs.warning_outline, palette.text_secondary)
                            }
                            _ => continue,
                        };
                        canvas.text(
                            cell_rect,
                            glyph,
                            TextStyle::IconSmall,
                            Color::from(color),
                            TextLayout::LINE,
                        );
                        continue;
                    }
                    Cell::Mono => (TextStyle::Code, if enabled { text } else { secondary }),
                    Cell::Text => (TextStyle::Body, if enabled { text } else { secondary }),
                    Cell::Secondary => (TextStyle::Body, secondary),
                };
                let badge = column
                    .badge
                    .and_then(|source| cells.get(source))
                    .filter(|badge| !badge.is_empty());
                let badge_width = badge.map_or(0.0, |badge| {
                    canvas.width(badge, TextStyle::Caption) + size::CONTROL_GAP
                });
                canvas.text(
                    Rect::new(
                        cell_rect.x,
                        cell_rect.y,
                        (cell_rect.width - badge_width).max(0.0),
                        cell_rect.height,
                    ),
                    value,
                    style,
                    Color::from(color),
                    TextLayout::LINE,
                );
                if let Some(badge) = badge {
                    canvas.text(
                        cell_rect,
                        badge,
                        TextStyle::Caption,
                        Color::from(secondary),
                        TextLayout::TRAILING,
                    );
                }
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

/// 名前の横の候補の見本(「びーる → 🍺」)．読みと矢印は薄い色，候補はふつうの色で，名前と同じ大きさの文字で書く
fn example_chip(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    example: (&str, &str),
    enabled: bool,
) {
    use tokens::size::settings::{PREVIEW_CHIP_PADDING_Y, PREVIEW_CHIP_RADIUS};
    if rect.width <= 0.0 {
        return;
    }
    let palette = &theme.palette;
    let (secondary, primary) = if enabled {
        (palette.text_secondary, palette.text)
    } else {
        (palette.text_disabled, palette.text_disabled)
    };
    // チップは試す欄の結果のチップと同じく，枠を付けず文字の色を薄く敷く(macOS の CandidateExample と同じ)
    canvas.fill_round(
        rect,
        PREVIEW_CHIP_RADIUS,
        Color::from(palette.text).with_alpha(opacity::PREVIEW_CHIP),
    );
    let parts = crate::layout::example_parts(example, |text| canvas.width(text, TextStyle::Body));
    let texts = [
        (example.0, secondary),
        (crate::layout::EXAMPLE_ARROW, secondary),
        (example.1, primary),
    ];
    canvas.push_clip(rect);
    for ((x, width), (text, color)) in parts.into_iter().zip(texts) {
        canvas.text(
            Rect::new(
                rect.x + x,
                rect.y + PREVIEW_CHIP_PADDING_Y,
                width.ceil(),
                size::BODY_LINE_HEIGHT,
            ),
            text,
            TextStyle::Body,
            Color::from(color),
            TextLayout::LINE,
        );
    }
    canvas.pop_clip();
}

/// 表の行を見せる高さ
/// 試した結果のタグの高さ(2 行目に英語か日本語かを出すときは 2 行)
fn chip_height(shown: &crate::engine::PreviewShown) -> f32 {
    let two_lines = shown.labels.iter().any(Option::is_some);
    size::BODY_LINE_HEIGHT
        + if two_lines {
            size::NOTE_LINE_HEIGHT
        } else {
            0.0
        }
        + tokens::size::settings::PREVIEW_CHIP_PADDING_Y * 2.0
}

/// 押せるタグ(打った語があるタグ)か．押すとメニューを出すので，文字の後ろに下向きの山形を添える
fn chip_opens_menu(shown: &crate::engine::PreviewShown, index: usize) -> bool {
    shown
        .typed
        .get(index)
        .is_some_and(|typed| !typed.is_empty())
}

/// 試した結果のタグの置き場所．rect の中に左から並べ，幅に収まらなければ次の行に送る(macOS の WrappingStack)．
/// rect からはみ出すタグは置かない．描くとき(preview_chips)と押した位置を調べるとき(Part::PreviewChip)の両方で使う
fn chip_areas(
    measure: &dyn paint::Measure,
    rect: Rect,
    shown: &crate::engine::PreviewShown,
    gap: f32,
) -> Vec<Rect> {
    use tokens::size::settings::PREVIEW_CHIP_PADDING_X;
    let height = chip_height(shown);
    let (mut x, mut y) = (rect.x, rect.y);
    let mut areas = Vec::new();
    for (index, chip) in shown.chips.iter().enumerate() {
        let label = shown.labels.get(index).and_then(Option::as_ref);
        let mut text_width = measure
            .width(chip, TextStyle::Body)
            .max(label.map_or(0.0, |(label, _)| measure.width(label, TextStyle::Caption)));
        if chip_opens_menu(shown, index) {
            text_width += tokens::size::space::INLINE
                + measure.width(super::theme::GLYPHS.chevron_down, TextStyle::IconSmall);
        }
        let width = (text_width + PREVIEW_CHIP_PADDING_X * 2.0).min(rect.width);
        if x > rect.x && x + width > rect.x + rect.width {
            x = rect.x;
            y += height + gap;
        }
        if y + height > rect.y + rect.height {
            break;
        }
        areas.push(Rect::new(x, y, width, height));
        x += width + gap;
    }
    areas
}

/// 試した結果を rect の中に描く．語はタグにして左から並べ，幅に収まらなければ次の行に送る(macOS の WrappingStack)．
/// タグにしない 1 行(書いている途中の形の結果)はそのまま折り返して書く．rect からはみ出すタグは描かない．
/// state はタグごとの押せる部品の状態(押せるタグはポインターを載せると背景を変え，フォーカスの印を出す)．押せないタグは None
fn preview_chips(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    shown: &crate::engine::PreviewShown,
    gap: f32,
    state: &dyn Fn(usize) -> Option<State>,
) {
    use tokens::size::settings::{
        PREVIEW_CHIP_PADDING_X, PREVIEW_CHIP_PADDING_Y, PREVIEW_CHIP_RADIUS,
    };
    let palette = &theme.palette;
    if !shown.line.is_empty() {
        canvas.text(
            rect,
            &shown.line,
            TextStyle::Body,
            Color::from(palette.text),
            TextLayout::WRAP,
        );
    }
    // タグは macOS の resultChip と同じく枠の無い薄い背景にし，2 行目に英語か日本語かを小さく出す(日本語はアクセントの色)
    let two_lines = shown.labels.iter().any(Option::is_some);
    let areas = chip_areas(&*canvas, rect, shown, gap);
    canvas.push_clip(rect);
    for (index, area) in areas.into_iter().enumerate() {
        let Some(chip) = shown.chips.get(index) else {
            break;
        };
        let label = shown.labels.get(index).and_then(Option::as_ref);
        canvas.fill_round(
            area,
            PREVIEW_CHIP_RADIUS,
            Color::from(palette.text).with_alpha(opacity::PREVIEW_CHIP),
        );
        let chip_state = state(index);
        if let Some(chip_state) = chip_state {
            // 押せるタグは，ポインターを載せたら背景を変える(テーマの行と同じ色)
            canvas.fill_round(
                area,
                PREVIEW_CHIP_RADIUS,
                Color::from(palette.nav_hover).with_alpha(
                    chip_state
                        .hover
                        .max(if chip_state.pressed { 1.0 } else { 0.0 }),
                ),
            );
        }
        let menu = chip_opens_menu(shown, index);
        let chevron = if menu {
            tokens::size::space::INLINE
                + canvas.width(theme.glyphs.chevron_down, TextStyle::IconSmall)
        } else {
            0.0
        };
        let inner = Rect::new(
            area.x + PREVIEW_CHIP_PADDING_X,
            area.y + PREVIEW_CHIP_PADDING_Y,
            area.width - PREVIEW_CHIP_PADDING_X * 2.0,
            size::BODY_LINE_HEIGHT,
        );
        let text_area = Rect::new(
            inner.x,
            inner.y,
            (inner.width - chevron).max(0.0),
            inner.height,
        );
        let layout = if two_lines {
            TextLayout::CENTER
        } else {
            TextLayout::LINE
        };
        canvas.text(
            text_area,
            chip,
            TextStyle::Body,
            Color::from(palette.text),
            layout,
        );
        if menu {
            canvas.text(
                Rect::new(
                    text_area.max_x() + tokens::size::space::INLINE,
                    inner.y,
                    chevron - tokens::size::space::INLINE,
                    inner.height,
                ),
                theme.glyphs.chevron_down,
                TextStyle::IconSmall,
                Color::from(palette.text_secondary),
                TextLayout::CENTER,
            );
        }
        if let Some((label, japanese)) = label {
            let color = if *japanese {
                palette.accent
            } else {
                palette.text_secondary
            };
            canvas.text(
                Rect::new(inner.x, inner.max_y(), inner.width, size::NOTE_LINE_HEIGHT),
                label,
                TextStyle::Caption,
                Color::from(color),
                TextLayout::CENTER,
            );
        }
        if chip_state.is_some_and(|state| state.focus_visible) {
            paint::focus_ring(canvas, theme, area, PREVIEW_CHIP_RADIUS);
        }
    }
    canvas.pop_clip();
}

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
            // 前のページのキーの欄だったら，普通の欄に戻す
            edit::set_record_on_click(window, None);
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
        // 辞書の一覧は開いた辞書の名前と分野の欄(連想の辞書は名前だけ)
        Control::Dictionaries(list) => {
            let prompts: &[&str] = match list {
                DictionaryList::Imported => &[
                    crate::strings::dictionaries::NAME,
                    crate::strings::dictionaries::FIELD_PROMPT,
                ],
                DictionaryList::Association => &[crate::strings::dictionaries::NAME],
            };
            for prompt in prompts {
                if let Some(window) = fields.take(prompt) {
                    row.inputs.push(Input::Edit(window));
                }
            }
        }
        Control::TextField => {
            if let Some(window) = fields.take(row.row.title) {
                // 使い回した欄がキーを記録する欄だったら戻す
                edit::set_record_on_click(window, None);
                row.inputs.push(Input::Edit(window));
            }
        }
        Control::Preview(kind) => {
            let labels = match kind {
                TryKind::Language => [features::TRY_PLACEHOLDER, features::TRY_PRECEDING],
                TryKind::Macros => [extras::TRY_MACRO_WORD, extras::TRY_MACRO_READING],
            };
            for label in labels {
                if let Some(window) = fields.take(label) {
                    row.preview_fields.push(window);
                }
            }
        }
        control => {
            let (Some(spec), Some(buttons)) = (control.list_spec(), control.list_buttons()) else {
                return;
            };
            for field in spec
                .fields
                .iter()
                .take(buttons.input_fields(spec.fields.len()))
            {
                let input = match field.choices {
                    Some(_) => Input::Choice(field.default_choice),
                    None => match fields.take(field.prompt.unwrap_or(field.label)) {
                        Some(window) => {
                            // キーの書き方の欄は押したらキーを記録する(macOS の KeyField)
                            edit::set_record_on_click(
                                window,
                                field.notation.then_some(keys::PRESS),
                            );
                            Input::Edit(window)
                        }
                        None => Input::Choice(0),
                    },
                };
                row.inputs.push(input);
            }
            if buttons.search {
                // キー設定の検索欄は何で探せるかを案内する(macOS の KeymapPage)
                let prompt = match control {
                    Control::List(spec, _) if spec.path == "keymap" => keys::SEARCH_PROMPT,
                    _ => features::SEARCH,
                };
                row.search = fields.take(prompt);
            }
        }
    }
}

/// 押したキーで絞り込んでいるときのチップの幅(キーの名前の幅から．左右の余白と，名前と外す印のあいだを足す)
fn key_chip_width(label: f32) -> f32 {
    (label + size::BUTTON_PADDING_X * 2.0 + space::INLINE + size::CHEVRON_SIZE).ceil()
}

/// チップの中の，キーの名前と外す印の置き場所
fn key_chip_areas(rect: Rect) -> (Rect, Rect) {
    let left = rect.x + size::BUTTON_PADDING_X;
    let mark = rect.max_x() - size::BUTTON_PADDING_X - size::CHEVRON_SIZE;
    (
        Rect::new(
            left,
            rect.y,
            (mark - space::INLINE - left).max(0.0),
            rect.height,
        ),
        Rect::new(mark, rect.y, size::CHEVRON_SIZE, rect.height),
    )
}

/// 表の行のメニューの項目
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RowMenuItem {
    Edit,
    Duplicate,
    Remove,
}

impl RowMenuItem {
    fn label(self) -> &'static str {
        match self {
            RowMenuItem::Edit => crate::strings::rule_list::EDIT,
            RowMenuItem::Duplicate => keys::DUPLICATE,
            RowMenuItem::Remove => crate::strings::settings::REMOVE,
        }
    }
}

/// キー設定の入力欄のうちコマンドの欄の番号(状態・キー・コマンド)
const KEYMAP_COMMAND: usize = 2;
/// キー設定の「いつでも」の状態(KeymapState.anywhere)．どのコマンドも置ける
const KEYMAP_ANYWHERE: &str = "anywhere";

/// 表の行の中の選ぶ欄(macOS の表の中の Picker)．ふだんは背景を描かずに名前と山形の印だけを出し，
/// ポインターを載せた・開いているときだけドロップダウンの背景を出す(行の縞と選んだ行の背景を消さない)
fn paint_table_choice(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    label: &str,
    open: bool,
    state: State,
) {
    if open || state.hover > 0.0 || state.pressed {
        let fade = if open || state.pressed {
            1.0
        } else {
            state.hover
        };
        canvas.set_opacity(fade);
        paint::dropdown(
            canvas,
            theme,
            rect,
            "",
            open,
            State {
                focus_visible: false,
                ..state
            },
        );
        canvas.set_opacity(1.0);
    }
    let palette = &theme.palette;
    let (text, secondary) = if state.enabled {
        (palette.text, palette.text_secondary)
    } else {
        (palette.text_disabled, palette.text_disabled)
    };
    let padding = size::FIELD_PADDING_X;
    let chevron = size::CHEVRON_SIZE;
    // 右の端に開く印を置き，印と名前のあいだにも同じ余白をとる
    let chevron_left = rect.max_x() - padding - chevron;
    canvas.text(
        Rect::new(
            rect.x + padding,
            rect.y,
            (chevron_left - padding - (rect.x + padding)).max(0.0),
            rect.height,
        ),
        label,
        TextStyle::Body,
        Color::from(text),
        TextLayout::LINE,
    );
    canvas.text(
        Rect::new(chevron_left, rect.y, chevron, rect.height),
        theme.glyphs.chevron_down,
        TextStyle::IconSmall,
        Color::from(secondary),
        TextLayout::CENTER,
    );
}

/// text の先頭から，幅 width に収まる分と残りに分ける(謝辞の URL のあとの文を URL と同じ行に続けるため)
fn split_to_width<'a>(
    measure: &dyn paint::Measure,
    text: &'a str,
    width: f32,
) -> (&'a str, &'a str) {
    let mut end = 0;
    for (index, character) in text.char_indices() {
        let next = index + character.len_utf8();
        if measure.width(&text[..next], TextStyle::Caption) > width {
            break;
        }
        end = next;
    }
    text.split_at(end)
}

/// 表の有効の印(WinUI 3 の CheckBox．入れたら色を塗ってチェックを描く)．cell の左に置き，上下は真ん中にする
fn paint_check(canvas: &mut dyn Canvas, theme: &Theme, cell: Rect, checked: bool, enabled: bool) {
    let palette = &theme.palette;
    let side = size::RADIO_SIZE;
    let rect = Rect::new(cell.x, cell.y + (cell.height - side) / 2.0, side, side);
    if checked {
        let fill = if enabled {
            Color::from(palette.accent)
        } else {
            Color::from(palette.control_strong_stroke).with_alpha(opacity::ACCENT_DISABLED)
        };
        canvas.fill_round(rect, size::CONTROL_RADIUS, fill);
        canvas.text(
            rect,
            theme.glyphs.check,
            TextStyle::IconSmall,
            Color::from(palette.accent_text),
            TextLayout::CENTER,
        );
    } else {
        canvas.fill_round(rect, size::CONTROL_RADIUS, Color::from(palette.control));
        let stroke = if enabled {
            palette.control_strong_stroke
        } else {
            palette.text_disabled
        };
        canvas.stroke_round(rect, size::CONTROL_RADIUS, 1.0, Color::from(stroke));
    }
}

/// 一覧の表の行(列ごとの文字)．一覧でなければ None
fn list_rows(row: &Row, values: &impl Values, extras: &Extras) -> Option<Vec<Vec<String>>> {
    Some(match &row.control {
        Control::Dictionary(_) => extras.dictionary.clone(),
        Control::Symbols(kind, _) => extras.symbol_rows(*kind).to_vec(),
        Control::SyncFields(_) => extras.sync_fields.clone(),
        Control::List(spec, _) if spec.has_enabled_flag() => {
            let list = values.value(spec.path);
            spec.items(list)
                .into_iter()
                .zip(spec.enabled_flags(list))
                .enumerate()
                .map(|(index, (item, enabled))| {
                    // 有効の印は表の先頭の列に印として出す(macOS の「有効」の列)
                    let mut columns = spec.display(&item);
                    columns.push(if enabled {
                        pages::ENABLED_CELL.to_string()
                    } else {
                        String::new()
                    });
                    // 変換マクロは，試す語と読みに当てた結果を後ろに持つ(形の列の右に添える)
                    if spec.path == MACROS_PATH {
                        columns.push(extras.macro_results.get(index).cloned().unwrap_or_default());
                    }
                    columns
                })
                .collect()
        }
        // キー設定は行の印(重なり・文字を打てなくなる)と，使われるかの印を後ろに足す(macOS の KeymapPage)
        Control::List(spec, _) if spec.path == "keymap" => spec
            .items(values.value(spec.path))
            .into_iter()
            .enumerate()
            .map(|(index, item)| {
                let issue = extras
                    .keymap_issues
                    .iter()
                    .find(|issue| issue.row as usize == index);
                let hidden = issue.is_some_and(|issue| {
                    !issue.hidden_by.is_empty() && issue.hidden_states.is_empty()
                });
                let mark = match issue {
                    Some(_) if hidden => pages::keymap_mark::HIDDEN,
                    Some(issue) if !issue.hidden_by.is_empty() => pages::keymap_mark::PARTLY,
                    Some(issue) if issue.blocks_typing => pages::keymap_mark::BLOCKS,
                    _ => "",
                };
                let mut columns = spec.display(&item);
                columns.push(mark.to_string());
                columns.push(if hidden {
                    String::new()
                } else {
                    pages::ENABLED_CELL.to_string()
                });
                columns
            })
            .collect(),
        Control::List(spec, _) => spec
            .items(values.value(spec.path))
            .into_iter()
            .map(|item| spec.display(&item))
            .collect(),
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
        size::BODY_LINE_HEIGHT * size::STATUS_LINES,
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

/// 名前の右の値の置き方．右の端にそろえ，狭い窓で名前の下に置いたときは左に寄せる
fn value_layout(card: &layout::CardLayout) -> TextLayout {
    if card.control.y >= card.label.max_y() {
        TextLayout::LINE
    } else {
        TextLayout::TRAILING
    }
}

/// 操作のボタンの種類(消す・戻す操作は危険の色)
fn button_kind(action: Action) -> paint::ButtonKind {
    if action.is_destructive() {
        paint::ButtonKind::Destructive
    } else {
        paint::ButtonKind::Standard
    }
}

/// テーマの見本(背景・文字・選択の色．macOS の ThemeSwatch)．色は候補ウィンドウと同じ解き方で，今の画面の明暗の色にする．
/// value は既成のテーマの値(カスタムテーマは元のテーマ)，custom はカスタムテーマの色
fn paint_swatch(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    value: &str,
    custom: Option<&ipc::CustomTheme>,
) {
    use candidate_ui::theme::{ResolvedTheme, SystemLook};
    let resolved = ResolvedTheme::resolve(
        value,
        custom,
        &SystemLook {
            dark: theme.dark,
            ..SystemLook::default()
        },
    );
    let color = |color: candidate_ui::theme::Color| Color {
        red: color.red,
        green: color.green,
        blue: color.blue,
        alpha: color.alpha,
    };
    let radius = if resolved.is_rounded() {
        (resolved.corner_radius / 2.0).min(size::THEME_SWATCH_RADIUS)
    } else {
        0.0
    };
    canvas.fill_round(rect, radius, color(resolved.surface));
    canvas.stroke_round(rect, radius, 1.0, color(resolved.frame));
    let mark = size::THEME_SWATCH_FONT_SIZE;
    let selection_width = size::THEME_SWATCH_SELECTION_WIDTH;
    let selection_height = size::THEME_SWATCH_SELECTION_HEIGHT;
    let total = mark + size::THEME_SWATCH_GAP + selection_width;
    let left = rect.x + (rect.width - total) / 2.0;
    canvas.text(
        Rect::new(left, rect.y, mark, rect.height),
        text::JAPANESE_MODE,
        TextStyle::Swatch,
        color(resolved.text),
        TextLayout::CENTER,
    );
    canvas.fill_round(
        Rect::new(
            left + mark + size::THEME_SWATCH_GAP,
            rect.y + (rect.height - selection_height) / 2.0,
            selection_width,
            selection_height,
        ),
        radius / 2.0,
        color(resolved.selection),
    );
}

/// 読みにくい組み合わせの知らせの行の高さ(注意の印と，折り返した文．width はカードの中の幅)
fn issue_height(text: &str, width: f32, measure: &dyn paint::Measure) -> f32 {
    let inner = (width - size::ICON_FONT_SIZE - size::CONTROL_GAP).max(1.0);
    (measure.wrapped_height(text, TextStyle::Body, inner) + size::CARD_PADDING_Y * 2.0)
        .max(size::ROW_HEIGHT)
}

/// 読みにくい組み合わせの知らせ(macOS の Label と exclamationmark.triangle.fill)．rect はカードの中
fn paint_issue(canvas: &mut dyn Canvas, theme: &Theme, rect: Rect, text: &str) {
    let icon = size::ICON_FONT_SIZE;
    let line = size::BODY_LINE_HEIGHT;
    let top = rect.y + size::CARD_PADDING_Y;
    canvas.text(
        Rect::new(rect.x, top, icon, line),
        theme.glyphs.warning,
        TextStyle::IconSmall,
        Color::from(theme.palette.caution),
        TextLayout::CENTER,
    );
    let left = rect.x + icon + size::CONTROL_GAP;
    canvas.text(
        Rect::new(
            left,
            top,
            (rect.max_x() - left).max(0.0),
            (rect.height - size::CARD_PADDING_Y * 2.0).max(line),
        ),
        text,
        TextStyle::Body,
        Color::from(theme.palette.text),
        TextLayout::WRAP,
    );
}

/// キー設定の知らせの 1 行(text_box の中の位置)
struct ReportLine<'a> {
    text: &'a str,
    /// 注意の印を付けるか(キーの無い確定・取り消し)
    marked: bool,
    top: f32,
    height: f32,
}

/// キー設定の知らせを行に分け，印の分を空けた幅で折り返したときの位置と高さを返す(測るときと描くときで同じにする)
fn report_lines<'a>(
    text: &'a str,
    marks: usize,
    width: f32,
    measure: &dyn paint::Measure,
) -> Vec<ReportLine<'a>> {
    let inner = (width - size::ICON_FONT_SIZE - space::INLINE).max(1.0);
    let mut top = 0.0;
    text.lines()
        .filter(|line| !line.is_empty())
        .enumerate()
        .map(|(index, line)| {
            let height = measure
                .wrapped_height(line, TextStyle::Caption, inner)
                .max(size::NOTE_LINE_HEIGHT);
            let placed = ReportLine {
                text: line,
                marked: index < marks,
                top,
                height,
            };
            top += height;
            placed
        })
        .collect()
}

/// 見本の画像の種類
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreviewKind {
    /// 外観の見本(分岐図)
    Theme,
    /// パレットの見本
    Palette,
    /// 絵文字の候補の見本(候補の一覧)
    Emoji,
    /// 情報のページのアイコン
    Icon,
}

/// 状態で絞り込む欄の index 番目の状態の名前(0 はすべての状態で，絞り込まない)
fn state_filter(index: usize) -> Option<&'static str> {
    index
        .checked_sub(1)
        .and_then(|index| keys::STATES.get(index))
        .map(|(_, label)| *label)
}

/// 置くときに文字を測る口(layout::Metrics)．DirectWrite で測り，謝辞のカードは中身から高さを決める
/// 書き方のチップの置き場所を DirectWrite で測る．チップの書き方と値は注記と同じ大きさ(コードは等幅)，切り替えは本文
struct TemplateMeasure<'a>(&'a dyn paint::Measure);

impl TemplateMeasure<'_> {
    fn style(face: Face) -> TextStyle {
        match face {
            Face::Code | Face::CodeValue => TextStyle::Mono,
            Face::Value => TextStyle::Caption,
            Face::Switch => TextStyle::Body,
        }
    }
}

impl reference::Measure for TemplateMeasure<'_> {
    fn width(&self, text: &str, face: Face) -> f32 {
        self.0.width(text, Self::style(face))
    }

    fn line_height(&self, face: Face) -> f32 {
        // 日本語の書体の行が高いので，日本語の字で測る
        self.0.wrapped_height("あ", Self::style(face), f32::MAX)
    }

    fn baseline(&self, text: &str, face: Face) -> f32 {
        self.0.baseline(text, Self::style(face))
    }
}

struct Measured<'a> {
    measure: &'a dyn paint::Measure,
    /// ページのすべての行(行の位置を引く)
    all: &'a [&'a Row],
    /// 謝辞のライセンスの全文を開いているか(行と同じ並び)
    expanded: &'a [bool],
    /// 辞書の一覧のカードの高さ(行と同じ並び．辞書の一覧でなければ None)
    heights: &'a [Option<f32>],
    /// ページの見本(外観・パレット・絵文字)を描いた大きさ．測れていなければ None
    preview: Option<(f32, f32)>,
    /// 行ごとの文(行と同じ並び．読みにくい組み合わせの知らせの高さを測る)
    texts: &'a [String],
    /// 行ごとの試した結果(行と同じ並び．変換マクロを試す欄の高さを結果の行の数に合わせる)
    chips: &'a [crate::engine::PreviewShown],
    /// 一覧の行の，状態で出し入れするもの(行と同じ並び)
    lists: &'a [ListInput],
}

/// 一覧の行の，状態で出し入れするもの(layout::ListState の元)
struct ListInput {
    /// 押したキーで絞り込んでいるときのチップの文字
    key_chip: Option<String>,
    template_button: bool,
    result: bool,
    panel: Option<PanelInput>,
}

/// 書き方のチップの欄に並べるもの
struct PanelInput {
    items: Vec<reference::Item>,
    values: Vec<String>,
    /// まとまりの切り替えを出す(絞り込んでいなければ)
    switch: bool,
}

impl Measured<'_> {
    fn position(&self, row: &Row) -> Option<usize> {
        self.all
            .iter()
            .position(|candidate| std::ptr::eq(*candidate, row))
    }
}

impl Metrics for Measured<'_> {
    fn lines(&self, text: &str, kind: TextKind, width: f32) -> usize {
        let style = match kind {
            TextKind::Body => TextStyle::Body,
            TextKind::Caption => TextStyle::Caption,
        };
        // 行の数は書体の 1 行の高さで割って数える．置く場所の行の高さ(BODY_LINE_HEIGHT・NOTE_LINE_HEIGHT)は
        // 書体の行より高いので，それで割ると長い文の行が足りなくなり，最後の行が欠ける
        let line = self.measure.wrapped_height("あ", style, f32::MAX);
        if line <= 0.0 {
            return 1;
        }
        let height = self.measure.wrapped_height(text, style, width.max(1.0));
        ((height / line).round() as usize).max(1)
    }

    fn width(&self, text: &str, kind: TextKind) -> f32 {
        let style = match kind {
            TextKind::Body => TextStyle::Body,
            TextKind::Caption => TextStyle::Caption,
        };
        self.measure.width(text, style)
    }

    fn list_state(&self, row: &Row, width: f32) -> layout::ListState {
        let Some(input) = self
            .position(row)
            .and_then(|position| self.lists.get(position))
        else {
            return layout::ListState::default();
        };
        let inner = (width - size::CARD_PADDING_X * 2.0).max(0.0);
        // 書き方のチップの欄: 切り替え(絞り込んでいなければ)と，チップの並び(当たるものが無ければその知らせの 1 行)
        let panel = input.panel.as_ref().map(|panel| {
            let head = if panel.switch {
                tokens::size::part::FIELD_HEIGHT + tokens::size::space::GROUP
            } else {
                0.0
            };
            let chips = if panel.items.is_empty() {
                size::BODY_LINE_HEIGHT
            } else {
                reference::place_chips(
                    &panel.items,
                    &panel.values,
                    inner,
                    &TemplateMeasure(self.measure),
                )
                .height
            };
            head + chips
        });
        layout::ListState {
            template_button: input.template_button,
            result: input.result,
            panel,
            key_search: input
                .key_chip
                .as_ref()
                .map(|chip| key_chip_width(self.measure.width(chip, TextStyle::Body))),
        }
    }

    fn height(&self, row: &Row, width: f32) -> Option<f32> {
        if matches!(
            row.control,
            Control::ThemePreview | Control::PalettePreview | Control::EmojiPreview
        ) {
            return self
                .preview
                .map(|natural| layout::preview_height(natural, width));
        }
        let inner = (width - size::CARD_PADDING_X * 2.0).max(0.0);
        if let Control::ThemeIssue(_) = row.control {
            let text = self
                .position(row)
                .and_then(|position| self.texts.get(position))?;
            return Some(issue_height(text, inner, self.measure));
        }
        if let Control::Dictionaries(_) = row.control {
            return self
                .position(row)
                .and_then(|position| self.heights.get(position).copied().flatten());
        }
        // 変換マクロを試す欄は，結果のタグを並べた行の数だけの高さにする(結果が無ければ 1 行)
        if let Control::PreviewChips(_) = row.control {
            let shown = self
                .position(row)
                .and_then(|position| self.chips.get(position))?;
            if !shown.line.is_empty() {
                return Some(
                    self.measure
                        .wrapped_height(&shown.line, TextStyle::Body, inner)
                        .max(size::BODY_LINE_HEIGHT),
                );
            }
            let gap = tokens::size::settings::PREVIEW_CHIP_GAP;
            let areas = chip_areas(
                self.measure,
                Rect::new(0.0, 0.0, inner, f32::MAX),
                shown,
                gap,
            );
            return Some(
                areas
                    .iter()
                    .map(Rect::max_y)
                    .fold(size::BODY_LINE_HEIGHT, f32::max),
            );
        }
        let Control::Acknowledgement(index) = row.control else {
            return None;
        };
        let open = self
            .position(row)
            .is_some_and(|position| self.expanded[position]);
        let inner = (width - size::CARD_PADDING_X * 2.0).max(0.0);
        let item = crate::notices::installed().get(index);
        Some(AcknowledgementLayout::new(item, (0.0, 0.0, inner), open, self.measure).1)
    }
}

/// カスタムテーマの書体の欄の選択肢と，選んでいる番号(macOS の ThemeFontPicker)．
/// 選択肢は選んだときに入れる値と画面に出す名前．ファミリーを選ぶと，太さと斜体が今の書体に近いスタイルの PostScript 名を入れる．
/// スタイルの欄は，今の書体が入っていなければ選択肢を空にする(出さない)
fn font_items(
    part: FontPart,
    faces: &[InstalledFace],
    value: &str,
) -> (Vec<(String, String)>, Option<usize>) {
    let current = fonts::find(faces, value);
    match part {
        FontPart::Family => {
            let mut items = vec![(String::new(), more::THEME_FONT.to_string())];
            // 入っていない書体を保存していれば，その名前のまま出す(選び直すまで値を変えない)
            if !value.is_empty() && current.is_none() {
                items.push((value.to_string(), value.to_string()));
            }
            let mut choice = Some(if value.is_empty() { 0 } else { 1 });
            let groups = fonts::by_family(faces);
            for (family, label) in fonts::families(faces) {
                if current.is_some_and(|current| current.family() == family) {
                    choice = Some(items.len());
                }
                let target = groups
                    .get(&family.to_lowercase())
                    .and_then(|members| fonts::closest_in(members, current))
                    .map_or_else(|| family.to_string(), |face| face.postscript.clone());
                items.push((target, label.to_string()));
            }
            (items, choice)
        }
        FontPart::Style => {
            let Some(current) = current else {
                return (Vec::new(), None);
            };
            let members = fonts::faces_of(faces, current.family());
            let choice = match current {
                Selection::Face(face) => members
                    .iter()
                    .position(|member| member.postscript == face.postscript),
                Selection::Family(_) => None,
            };
            let items = members
                .into_iter()
                .map(|face| (face.postscript.clone(), face.label.clone()))
                .collect();
            (items, choice)
        }
    }
}

#[cfg(test)]
mod chip_tests {
    use super::*;

    /// 1 字を 10 の幅で数える(絵の書体の字も 10)
    struct Fixed;

    impl paint::Measure for Fixed {
        fn width(&self, text: &str, _: TextStyle) -> f32 {
            text.chars().count() as f32 * 10.0
        }
        fn wrapped_height(&self, _: &str, _: TextStyle, _: f32) -> f32 {
            size::BODY_LINE_HEIGHT
        }
        fn baseline(&self, _: &str, _: TextStyle) -> f32 {
            size::BODY_LINE_HEIGHT * 0.75
        }
    }

    #[test]
    fn キーの無い確定と取り消しの行だけに注意の印を付け_行を上から重ねずに置く() {
        let lines = report_lines("入力中に「確定」のキーがありません\n変換中に「確定」のキーがありません\nCtrl+K: 使われません", 2, 300.0, &Fixed);
        assert_eq!(
            lines.iter().map(|line| line.marked).collect::<Vec<_>>(),
            [true, true, false]
        );
        assert_eq!(lines[0].top, 0.0);
        for pair in lines.windows(2) {
            assert_eq!(pair[1].top, pair[0].top + pair[0].height);
        }
    }

    fn shown(chips: &[&str], typed: &[&str]) -> crate::engine::PreviewShown {
        crate::engine::PreviewShown {
            chips: chips.iter().map(|chip| (*chip).to_string()).collect(),
            line: String::new(),
            labels: chips
                .iter()
                .map(|_| Some(("英語".to_string(), false)))
                .collect(),
            typed: typed.iter().map(|typed| (*typed).to_string()).collect(),
        }
    }

    #[test]
    fn 押せるタグは山形の分だけ広く_幅に収まらなければ次の行に送る() {
        let gap = tokens::size::settings::PREVIEW_BUTTON_GAP;
        let rect = Rect::new(0.0, 0.0, 300.0, 200.0);
        let plain = chip_areas(&Fixed, rect, &shown(&["zoom", "会議"], &[]), gap);
        let menu = chip_areas(
            &Fixed,
            rect,
            &shown(&["zoom", "会議"], &["zoom", "kaigi"]),
            gap,
        );
        assert_eq!(plain.len(), 2);
        assert_eq!(menu.len(), 2);
        assert!(menu[0].width > plain[0].width);
        assert_eq!(menu[1].x, menu[0].max_x() + gap);
        let narrow = chip_areas(
            &Fixed,
            Rect::new(0.0, 0.0, 120.0, 200.0),
            &shown(&["zoom", "会議"], &["zoom", "kaigi"]),
            gap,
        );
        assert_eq!(narrow[1].x, 0.0);
        assert!(narrow[1].y > narrow[0].y);
    }

    #[test]
    fn 試す欄にはタグの数だけ押せる部品を並べる_ボタンは置かない() {
        assert!(!chip_opens_menu(&shown(&["zoom"], &[]), 0));
        assert!(chip_opens_menu(&shown(&["zoom"], &["zoom"]), 0));
    }
}
