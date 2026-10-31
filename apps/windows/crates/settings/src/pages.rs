#![forbid(unsafe_code)]

//! 設定の画面のページと，その中の項目の並び．macOS の SettingsView(Group・Page・各ページの Form)と同じ並び・同じ文言にする．
//! Windows の部品の作り方はここでは決めず，app が並びに従って部品を作る

use crate::files::FileTask;
use crate::list::{Field, ListSpec};
use crate::options::{self, Choice};
use crate::strings::{
    association, choice, dictionaries, features, keys, menu, more, settings, sync,
};
use ipc::{RuleList, SymbolKind};

/// 左の一覧の見出し
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Group {
    Input,
    Dictionary,
    Appearance,
    Data,
    About,
}

impl Group {
    pub const ALL: [Group; 5] = [
        Group::Input,
        Group::Dictionary,
        Group::Appearance,
        Group::Data,
        Group::About,
    ];

    pub fn title(self) -> &'static str {
        match self {
            Group::Input => settings::INPUT_GROUP,
            Group::Dictionary => settings::DICTIONARY_GROUP,
            Group::Appearance => settings::APPEARANCE_GROUP,
            Group::Data => settings::DATA_GROUP,
            Group::About => settings::ABOUT_GROUP,
        }
    }
}

/// 左の一覧の項目．並びは左の一覧の並び
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Page {
    Input,
    Conversion,
    Correction,
    Language,
    Romaji,
    Keys,
    Apps,
    Dictionary,
    Symbols,
    Appearance,
    Usage,
    Sync,
    Backup,
    About,
}

impl Page {
    pub const ALL: [Page; 14] = [
        Page::Input,
        Page::Conversion,
        Page::Correction,
        Page::Language,
        Page::Romaji,
        Page::Keys,
        Page::Apps,
        Page::Dictionary,
        Page::Symbols,
        Page::Appearance,
        Page::Usage,
        Page::Sync,
        Page::Backup,
        Page::About,
    ];

    pub fn group(self) -> Group {
        match self {
            Page::Input
            | Page::Conversion
            | Page::Correction
            | Page::Language
            | Page::Romaji
            | Page::Keys
            | Page::Apps => Group::Input,
            Page::Dictionary | Page::Symbols => Group::Dictionary,
            Page::Appearance => Group::Appearance,
            Page::Usage | Page::Sync | Page::Backup => Group::Data,
            Page::About => Group::About,
        }
    }

    pub fn title(self) -> &'static str {
        match self {
            Page::Input => settings::INPUT_TAB,
            Page::Conversion => settings::CONVERSION_TAB,
            Page::Correction => features::CORRECTION_PAGE,
            Page::Language => features::LANGUAGE_PAGE,
            Page::Symbols => features::SYMBOLS_PAGE,
            Page::Keys => keys::TAB,
            Page::Dictionary => settings::DICTIONARY_TAB,
            Page::Romaji => settings::ROMAJI_TAB,
            Page::Apps => settings::APPS_TAB,
            Page::Appearance => settings::APPEARANCE_TAB,
            Page::Usage => settings::USAGE_TAB,
            Page::Sync => sync::PAGE,
            Page::Backup => more::BACKUP,
            Page::About => more::ABOUT,
        }
    }

    /// 左の一覧の絵．Segoe Fluent Icons(Windows 10 では Segoe MDL2 Assets)の字
    pub fn glyph(self) -> char {
        match self {
            Page::Input => '\u{E765}',      // キーボード
            Page::Conversion => '\u{E8C1}', // 文字
            Page::Correction => '\u{E70F}', // 編集
            Page::Language => '\u{E774}',   // 地球
            Page::Romaji => '\u{E80A}',     // 表
            Page::Keys => '\u{E92E}',       // キーボードの全体
            Page::Apps => '\u{ECE4}',       // 禁止
            Page::Dictionary => '\u{E82D}', // 辞書
            Page::Symbols => '\u{E8D2}',    // 記号
            Page::Appearance => '\u{E790}', // 色
            Page::Usage => '\u{E9D2}',      // グラフ
            Page::Sync => '\u{E895}',       // 同期
            Page::Backup => '\u{EDA2}',     // ドライブ
            Page::About => '\u{E946}',      // 情報
        }
    }

    /// 検索で見つけるための言葉．ページの名前に加え，そのページにある項目の名前
    pub fn keywords(self) -> Vec<&'static str> {
        match self {
            Page::Input => vec![
                choice::INPUT_STYLE,
                choice::KEYBOARD_LAYOUT,
                settings::PUNCTUATION,
                features::KEYPAD_DIRECT,
            ],
            Page::Conversion => vec![
                menu::LIVE_CONVERSION,
                choice::PRESENTATION,
                choice::INITIAL_FOCUS,
                features::OKURIGANA,
                features::PREFERS_KATAKANA,
                features::CALCULATION,
                features::POSTAL_CODE,
                features::HANDWRITING,
                settings::DATE_CONVERSION,
                settings::EMOJI_CONVERSION,
            ],
            Page::Correction => vec![
                features::EXCEPTIONS,
                features::RULES,
                features::CORRECTS_ENGLISH,
                features::MISREADINGS,
            ],
            Page::Language => vec![
                features::ENGLISH_WORDS,
                features::JAPANESE_WORDS,
                features::LANGUAGE_RULES,
                features::TRY_LANGUAGE,
                options::INPUT_STYLES[3].1,
            ],
            Page::Symbols => vec![features::SEQUENCES, features::READINGS],
            // コマンドと状態の名前でも見つける(「全角空白」「英数」「切り替え」で キー設定 を出す)
            Page::Keys => std::iter::once(keys::PRESET_MENU)
                .chain(keys::COMMANDS.iter().map(|(_, label)| *label))
                .chain(keys::STATES.iter().map(|(_, label)| *label))
                .chain(keys::PRESETS.iter().map(|(_, label)| *label))
                .collect(),
            Page::Dictionary => vec![settings::READING, settings::WORD, dictionaries::IMPORTED],
            Page::Appearance => vec![more::THEME, more::CUSTOM_THEMES, more::FONT],
            Page::Sync => vec![sync::FOLDER, sync::SCOPES, settings::DICTIONARY_TAB],
            Page::Romaji | Page::Apps | Page::Usage | Page::Backup | Page::About => vec![],
        }
    }

    /// 検索の言葉を名前か項目の名前に含むか．大文字と小文字は区別しない
    pub fn matches(self, query: &str) -> bool {
        let query = query.trim().to_lowercase();
        query.is_empty()
            || std::iter::once(self.title())
                .chain(self.keywords())
                .any(|text| text.to_lowercase().contains(&query))
    }
}

/// 左の一覧に並べる見出しとページ．pages に無いページ(まだ作っていないもの)は出さない．検索の言葉に合うページだけを出し，空の見出しは出さない
pub fn sidebar(pages: &[Page], query: &str) -> Vec<(Group, Vec<Page>)> {
    Group::ALL
        .iter()
        .filter_map(|group| {
            let matched: Vec<Page> = Page::ALL
                .iter()
                .copied()
                .filter(|page| {
                    page.group() == *group && pages.contains(page) && page.matches(query)
                })
                .collect();
            (!matched.is_empty()).then_some((*group, matched))
        })
        .collect()
}

/// 項目を出す・使えるようにする条件
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Condition {
    /// 項目の値が value のとき
    Is(&'static str, &'static str),
    /// 項目の値が value でないとき
    IsNot(&'static str, &'static str),
    /// オン・オフの項目がオンのとき
    On(&'static str),
}

/// 1 行の部品
#[derive(Debug, Clone, PartialEq)]
pub enum Control {
    /// オン・オフ
    Toggle,
    /// 列挙の値を選ぶ
    Choice(&'static [Choice]),
    /// 整数を範囲の中で選ぶ(候補の数)
    Stepper(RangeKind),
    /// 秒を範囲の中で選ぶ(0.1 秒ごと)
    Seconds(RangeKind),
    /// 注記(前の行の説明として小さい文字で出す)
    Note,
    /// エンジンに頼む操作のボタン(項目の名前をボタンに出す)
    Action(Action),
    /// 使い方の記録の値(変えられない)
    Stat(Stat),
    /// 決まりの一覧(入力欄・追加・削除・表)
    List(ListSpec, LimitKind),
    /// 英語と日本語の見分けを試す欄(打つ文・前の文字列・結果)
    Preview,
    /// アプリのバージョン(変えられない)
    Version,
    /// キー設定の表の問題(使われない行・キーの無い確定など)．無ければ出さない
    KeymapReport,
    /// キー設定のひな形を選んで読み込む
    Preset,
    /// 利用表記(THIRD_PARTY_NOTICES.md)の全文．読むだけ
    Notices,
    /// 登録した単語．数が多くなるので設定の値としてではなく，エンジンに分けて読んでもらい，1 語ずつ足す・消す
    Dictionary(ListSpec),
    /// 記号の決まり．既定の決まりに利用者の決まりを重ねた一覧をエンジンに読んでもらい，決まりを重ねる・外す・有効と無効を切り替える
    Symbols(SymbolKind, ListSpec),
    /// エンジンから読んだ値を出す(変えられない)
    Info(Info),
    /// 同期の項目ごとの範囲の表．選んだ項目の範囲を切り替える
    SyncFields(ListSpec),
    /// 取り込んだ辞書・連想の辞書の一覧．入力欄で選んだ辞書の名前などを変え，下のボタンで取り込む・並べ替える・切り替える・消す
    Dictionaries(DictionaryList, ListSpec),
    /// カスタムテーマの一覧．選んだテーマを下の行で編集し，入力欄で名前を変え，下のボタンで作る・複製する・使う・消す
    CustomThemes(ListSpec),
    /// 色を選ぶボタン(「#RRGGBB」の値．押すと色を選ぶ窓を出す)
    Color,
    /// 外観の見本(候補ウィンドウと同じ描き方の分岐図)
    ThemePreview,
    /// カスタムテーマの読みにくい組み合わせの知らせ．無ければ出さない
    ThemeReport,
}

/// 一覧の上限の種類(catalog の Limits のどれか)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LimitKind {
    CorrectionRules,
    RomajiRules,
    WordLanguageEntries,
    ProfileRules,
    UserDictionaryEntries,
    KeymapEntries,
}

impl LimitKind {
    pub fn limit(self, catalog: &crate::catalog::Catalog) -> usize {
        match self {
            LimitKind::CorrectionRules => catalog.limits.correction_rules,
            LimitKind::RomajiRules => catalog.limits.romaji_rules,
            LimitKind::WordLanguageEntries => catalog.limits.word_language_entries,
            LimitKind::ProfileRules => catalog.limits.profile_rules,
            LimitKind::UserDictionaryEntries => catalog.limits.user_dictionary_entries,
            LimitKind::KeymapEntries => catalog.limits.keymap_entries,
        }
    }
}

/// ボタンで頼む操作
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    ResetLearning,
    ResetUsage,
    RestoreDefaults,
    /// キー設定の表を標準のひな形に戻す
    RestoreKeymap,
    /// 設定のファイルを既定のアプリで開く(Windows だけ．画面にまだ無い項目を直すため)
    OpenSettingsFile,
    /// ファイルを選んで読み込む・書き出す
    File(FileTask),
    /// 同期のフォルダを選ぶ
    ChooseSyncFolder,
    /// 初期設定ウィザードを開き直す
    OpenSetup,
    /// 今すぐ同期する
    SyncNow,
}

/// 取り込んで使う辞書の一覧の種類
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DictionaryList {
    /// 取り込んだ辞書(importedDictionaries)
    Imported,
    /// 連想の辞書(associationDictionaries)
    Association,
}

impl DictionaryList {
    /// 設定のファイルの項目
    pub fn path(self) -> &'static str {
        match self {
            DictionaryList::Imported => "importedDictionaries",
            DictionaryList::Association => "associationDictionaries",
        }
    }
}

/// 使う場面(DictionaryCondition)の選択肢．値は設定のファイルの名前
pub const DICTIONARY_CONDITIONS: &[Choice] = &[
    ("always", dictionaries::ALWAYS),
    ("apps", dictionaries::APPS),
    ("context", dictionaries::CONTEXT),
];

const IMPORTED_FIELDS: &[Field] = &[
    Field::named("name", dictionaries::NAME, false),
    Field::named("field", dictionaries::FIELD, false),
    Field::choice(
        "condition",
        dictionaries::CONDITION,
        DICTIONARY_CONDITIONS,
        false,
    ),
    Field::named("apps", crate::strings::windows::DICTIONARY_APPS, false),
];

const ASSOCIATION_FIELDS: &[Field] = &[Field::named("name", dictionaries::NAME, false)];

const IMPORTED_SPEC: ListSpec = ListSpec {
    path: "importedDictionaries",
    fields: IMPORTED_FIELDS,
    empty: dictionaries::EMPTY,
    invalid: crate::strings::Text::Fixed(crate::strings::windows::INVALID_APP),
    lowercase: false,
    exclusive_with: None,
};

const ASSOCIATION_SPEC: ListSpec = ListSpec {
    path: "associationDictionaries",
    fields: ASSOCIATION_FIELDS,
    empty: association::EMPTY,
    invalid: crate::strings::Text::Fixed(""),
    lowercase: false,
    exclusive_with: None,
};

/// 一覧の入力欄の右のボタンと，表の下のボタン(並びは部品を作る順と同じ)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ListButtons {
    pub top: &'static [&'static str],
    pub bottom: &'static [&'static str],
    /// 表の下の左に検索欄を置く(行の多い一覧)
    pub search: bool,
}

impl Control {
    /// 一覧の部品のボタン．一覧でなければ None
    pub fn list_buttons(&self) -> Option<ListButtons> {
        use crate::strings::{rule_list, windows};
        const ADD_REMOVE: &[&str] = &[settings::ADD, settings::REMOVE];
        let (top, bottom): (&'static [&'static str], &'static [&'static str]) = match self {
            // キー設定はキーを押して記録する・行を複製する，除外設定はアプリのファイルを選んで足す(macOS の KeymapPage・ExclusionsPage)
            Control::List(spec, _) if spec.path == "keymap" => {
                (ADD_REMOVE, &[keys::RECORD, keys::DUPLICATE])
            }
            Control::List(spec, _) if spec.path == "profileRules" => {
                (ADD_REMOVE, &[more::ADD_APPS])
            }
            Control::List(..) | Control::Dictionary(_) => (ADD_REMOVE, &[]),
            Control::Symbols(..) => (
                &[settings::ADD, settings::REMOVE, windows::TOGGLE_ENABLED],
                &[],
            ),
            Control::SyncFields(_) => (&[windows::TOGGLE_SYNC_SCOPE], &[]),
            Control::Dictionaries(DictionaryList::Imported, _) => (
                &[rule_list::UPDATE],
                &[
                    dictionaries::IMPORT_FILE,
                    dictionaries::REIMPORT,
                    dictionaries::MOVE_UP,
                    dictionaries::MOVE_DOWN,
                    windows::TOGGLE_ENABLED,
                    settings::REMOVE,
                ],
            ),
            Control::CustomThemes(_) => (
                &[rule_list::UPDATE],
                &[
                    windows::CREATE_THEME,
                    more::DUPLICATE,
                    windows::USE_THEME,
                    more::DUPLICATE_THEME,
                    more::DELETE_THEME,
                ],
            ),
            Control::Dictionaries(DictionaryList::Association, _) => (
                &[rule_list::UPDATE],
                &[
                    association::IMPORT_FILE,
                    dictionaries::REIMPORT,
                    dictionaries::MOVE_UP,
                    dictionaries::MOVE_DOWN,
                    windows::TOGGLE_ENABLED,
                    settings::REMOVE,
                ],
            ),
            _ => return None,
        };
        let search = matches!(
            self,
            Control::List(..) | Control::Dictionary(_) | Control::Symbols(..)
        );
        Some(ListButtons {
            top,
            bottom,
            search,
        })
    }

    /// 一覧の入力欄の決まり．一覧でなければ None
    pub fn list_spec(&self) -> Option<&ListSpec> {
        match self {
            Control::List(spec, _)
            | Control::Dictionary(spec)
            | Control::Symbols(_, spec)
            | Control::SyncFields(spec)
            | Control::Dictionaries(_, spec)
            | Control::CustomThemes(spec) => Some(spec),
            _ => None,
        }
    }

    /// 表の列の名前．ふつうは入力欄と同じ列で，記号は状態の列を足す．項目ごとの同期と辞書の一覧は入力欄と別の列
    pub fn table_columns(&self) -> Vec<&'static str> {
        use crate::strings::windows;
        let fields = || {
            self.list_spec()
                .into_iter()
                .flat_map(|spec| spec.fields.iter().map(|field| field.label))
        };
        match self {
            Control::Symbols(..) => fields().chain([windows::SYMBOL_STATE]).collect(),
            Control::SyncFields(_) => vec![windows::SYNC_FIELD, windows::SYNC_SCOPE],
            Control::Dictionaries(..) => vec![
                dictionaries::NAME,
                windows::DICTIONARY_SUMMARY,
                windows::SYMBOL_STATE,
            ],
            Control::CustomThemes(_) => vec![more::THEME_NAME, windows::SYMBOL_STATE],
            _ => fields().collect(),
        }
    }
}

/// エンジンから読んで出す値の種類
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Info {
    /// 同期のフォルダの名前
    SyncFolder,
    /// 最後に同期した時刻
    LastSynced,
}

/// 使い方の記録の値の種類
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stat {
    FirstCandidateRate,
    Commits,
    ConversionsOpened,
    SegmentsChanged,
    ReadingCorrections,
    EnglishCorrections,
}

/// 範囲の種類(catalog の Ranges のどれか)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RangeKind {
    CandidatesPerPage,
    LiveConversionDelay,
    LiveConversionSkipLength,
    CorrectionDelay,
    ReviewCorrectionTimeout,
    LateCorrectionTimeout,
    ModeIndicatorDuration,
    CandidateFontSize,
    AssociationLimit,
    CustomThemeCornerRadius,
}

impl RangeKind {
    pub fn range(self, catalog: &crate::catalog::Catalog) -> crate::catalog::Range {
        let ranges = &catalog.ranges;
        match self {
            RangeKind::CandidatesPerPage => ranges.candidates_per_page,
            RangeKind::LiveConversionDelay => ranges.live_conversion_delay,
            RangeKind::LiveConversionSkipLength => ranges.live_conversion_skip_length,
            RangeKind::CorrectionDelay => ranges.correction_delay,
            RangeKind::ReviewCorrectionTimeout => ranges.review_correction_timeout,
            RangeKind::LateCorrectionTimeout => ranges.late_correction_timeout,
            RangeKind::ModeIndicatorDuration => ranges.mode_indicator_duration,
            RangeKind::CandidateFontSize => ranges.candidate_font_size,
            RangeKind::AssociationLimit => ranges.association_limit,
            RangeKind::CustomThemeCornerRadius => ranges.custom_theme_corner_radius,
        }
    }

    /// 秒の項目を選ぶ刻み．打ち間違いを探す時間の上限は範囲が広いので 1 秒ずつ
    pub fn seconds_step(self, catalog: &crate::catalog::Catalog) -> f64 {
        match self {
            RangeKind::ReviewCorrectionTimeout | RangeKind::LateCorrectionTimeout => {
                catalog.correction_timeout_step
            }
            _ => catalog.seconds_step,
        }
    }

    /// 選べる値の刻み
    pub fn step(self, catalog: &crate::catalog::Catalog) -> f64 {
        match self {
            RangeKind::AssociationLimit => catalog.association_limit_step,
            _ => 1.0,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Row {
    pub title: &'static str,
    /// 値の道筋(「correction.english」)．注記では空
    pub path: &'static str,
    pub control: Control,
    /// 満たさないときは使えなくする
    pub enabled: Option<Condition>,
    /// 満たさないときは出さない
    pub visible: Option<Condition>,
    /// 値を変えたときに一緒に空(null)にする項目(テーマを選んだらカスタムテーマを外す)
    pub clears: Option<&'static str>,
}

impl Row {
    pub fn toggle(title: &'static str, path: &'static str) -> Self {
        Self::new(title, path, Control::Toggle)
    }

    pub fn choice(title: &'static str, path: &'static str, options: &'static [Choice]) -> Self {
        Self::new(title, path, Control::Choice(options))
    }

    pub fn stepper(title: &'static str, path: &'static str, range: RangeKind) -> Self {
        Self::new(title, path, Control::Stepper(range))
    }

    pub fn seconds(title: &'static str, path: &'static str, range: RangeKind) -> Self {
        Self::new(title, path, Control::Seconds(range))
    }

    pub fn note(text: &'static str) -> Self {
        Self::new(text, "", Control::Note)
    }

    pub fn action(title: &'static str, action: Action) -> Self {
        Self::new(title, "", Control::Action(action))
    }

    pub fn stat(title: &'static str, stat: Stat) -> Self {
        Self::new(title, "", Control::Stat(stat))
    }

    pub fn list(spec: ListSpec, limit: LimitKind) -> Self {
        Self::new("", spec.path, Control::List(spec, limit))
    }

    /// 設定の値を持つ行か(既定に戻すボタンを付ける行)
    pub fn has_value(&self) -> bool {
        matches!(
            self.control,
            Control::Toggle | Control::Choice(_) | Control::Stepper(_) | Control::Seconds(_)
        )
    }

    pub fn new(title: &'static str, path: &'static str, control: Control) -> Self {
        Self {
            title,
            path,
            control,
            enabled: None,
            visible: None,
            clears: None,
        }
    }

    pub fn clearing(mut self, path: &'static str) -> Self {
        self.clears = Some(path);
        self
    }

    pub fn enabled_when(mut self, condition: Condition) -> Self {
        self.enabled = Some(condition);
        self
    }

    pub fn visible_when(mut self, condition: Condition) -> Self {
        self.visible = Some(condition);
        self
    }
}

/// 見出しの付いた行のまとまり(macOS の Form の Section)
#[derive(Debug, Clone, PartialEq)]
pub struct Section {
    pub title: Option<&'static str>,
    pub rows: Vec<Row>,
    /// まとまりの下の注記
    pub footer: Option<&'static str>,
    /// 注記に入れ替えて出すほかの文(値と文の組．キー設定のコマンドの説明)．注記の高さはいちばん長い文に合わせる
    pub footer_variants: &'static [(&'static str, &'static str)],
}

impl Section {
    fn new(title: &'static str, rows: Vec<Row>) -> Self {
        Self {
            title: Some(title),
            rows,
            footer: None,
            footer_variants: &[],
        }
    }

    fn untitled(rows: Vec<Row>) -> Self {
        Self {
            title: None,
            rows,
            footer: None,
            footer_variants: &[],
        }
    }
}

/// 作ったページ．左の一覧にはこのページだけを出す
pub const BUILT: &[Page] = &[
    Page::Input,
    Page::Conversion,
    Page::Correction,
    Page::Language,
    Page::Romaji,
    Page::Keys,
    Page::Apps,
    Page::Dictionary,
    Page::Symbols,
    Page::Appearance,
    Page::Usage,
    Page::Sync,
    Page::Backup,
    Page::About,
];

/// ページの中身．項目の並びだけで書けるページは sections を返す．None のページは app が専用の部品で組み立てる
pub fn sections(page: Page) -> Option<Vec<Section>> {
    match page {
        Page::Input => Some(input()),
        Page::Conversion => Some(conversion()),
        Page::Correction => Some(correction()),
        Page::Language => Some(language()),
        Page::Romaji => Some(romaji()),
        Page::Apps => Some(apps()),
        Page::Keys => Some(keymap()),
        Page::Dictionary => Some(dictionary()),
        Page::Symbols => Some(symbols()),
        Page::Sync => Some(sync_page()),
        Page::Appearance => Some(appearance()),
        Page::Usage => Some(usage()),
        Page::Backup => Some(backup()),
        Page::About => Some(about()),
    }
}

/// 入力のページ(macOS の InputTab)
fn input() -> Vec<Section> {
    use Condition::*;
    vec![
        Section::new(
            settings::INPUT_STYLE_SECTION,
            vec![
                Row::choice(choice::INPUT_STYLE, "inputStyle", options::INPUT_STYLES),
                Row::note(choice::ENGLISH_AUTO_NOTE).visible_when(Is("inputStyle", "englishAuto")),
                Row::toggle(
                    choice::ENGLISH_INPUT_LIVE_CONVERSION,
                    "englishInputLiveConversion",
                )
                .enabled_when(Is("inputStyle", "english")),
                Row::note(choice::ENGLISH_INPUT_LIVE_CONVERSION_NOTE)
                    .visible_when(Is("inputStyle", "english")),
                Row::choice(
                    choice::KEYBOARD_LAYOUT,
                    "keyboardLayout",
                    options::KEYBOARD_LAYOUTS,
                ),
                Row::note(choice::KEYBOARD_LAYOUT_NOTE),
            ],
        ),
        Section::new(
            settings::CHARACTERS,
            vec![
                Row::choice(settings::PUNCTUATION, "punctuation", options::PUNCTUATION),
                Row::choice(settings::BRACKETS, "brackets", options::BRACKETS),
                Row::choice(settings::SLASH, "slash", options::SLASH),
                Row::choice(choice::YEN_KEY, "yenKey", options::YEN_KEY),
                Row::choice(settings::SPACE_WIDTH, "spaceWidth", options::WIDTHS),
                Row::choice(settings::NUMBER_WIDTH, "numberWidth", options::WIDTHS),
                Row::choice(more::ALPHABET_WIDTH, "alphabetWidth", options::WIDTHS),
                Row::toggle(more::SHIFT_STARTS_ALPHABET, "shiftStartsAlphabet"),
                Row::toggle(features::KEYPAD_DIRECT, "keypadDirect"),
            ],
        ),
        Section::new(
            settings::KEYS,
            vec![
                Row::toggle(settings::PUNCTUATION_COMMITS, "punctuationCommits"),
                Row::toggle(settings::NUMBER_KEY_SELECTION, "numberKeySelection"),
                Row::toggle(settings::SHOWS_MODE_INDICATOR, "showsModeIndicator"),
                Row::seconds(
                    more::MODE_INDICATOR_DURATION,
                    "modeIndicatorDuration",
                    RangeKind::ModeIndicatorDuration,
                )
                .enabled_when(On("showsModeIndicator")),
            ],
        ),
    ]
}

/// 変換のページ(macOS の ConversionTab)
fn conversion() -> Vec<Section> {
    use Condition::*;
    vec![
        Section::new(
            settings::CONVERSION,
            vec![
                Row::toggle(menu::LIVE_CONVERSION, "liveConversion"),
                Row::choice(
                    choice::PRESENTATION,
                    "candidatePresentation",
                    options::PRESENTATIONS,
                ),
                Row::choice(
                    choice::INITIAL_FOCUS,
                    "initialFocus",
                    options::INITIAL_FOCUS,
                ),
                Row::choice(
                    choice::SUGGESTION_DISPLAY,
                    "suggestionDisplay",
                    options::SUGGESTION_DISPLAY,
                ),
                Row::toggle(choice::VARIANT_ROW, "showsVariantRow"),
                Row::toggle(choice::KEY_HINTS, "showsKeyHints"),
                Row::seconds(
                    more::LIVE_CONVERSION_DELAY,
                    "liveConversionDelay",
                    RangeKind::LiveConversionDelay,
                )
                .enabled_when(On("liveConversion")),
                Row::stepper(
                    more::LIVE_CONVERSION_SKIP_LENGTH,
                    "liveConversionSkipLength",
                    RangeKind::LiveConversionSkipLength,
                )
                .enabled_when(On("liveConversion")),
            ],
        ),
        Section::new(
            more::CANDIDATES,
            vec![
                Row::stepper(
                    more::BRANCH_CANDIDATES,
                    "branchCandidatesPerPage",
                    RangeKind::CandidatesPerPage,
                ),
                Row::stepper(
                    more::LIST_CANDIDATES,
                    "listCandidatesPerPage",
                    RangeKind::CandidatesPerPage,
                ),
            ],
        ),
        Section::new(
            more::TYPO,
            vec![
                Row::choice(
                    choice::TYPO_CORRECTION,
                    "typoCorrection",
                    options::TYPO_CORRECTION,
                ),
                Row::choice(
                    more::CORRECTION_SENSITIVITY,
                    "correctionSensitivity",
                    options::CORRECTION_SENSITIVITY,
                )
                .enabled_when(Is("typoCorrection", "standard")),
                Row::toggle(more::SHOWS_SUGGESTIONS, "showsSuggestions")
                    .enabled_when(Is("typoCorrection", "standard")),
                Row::seconds(
                    more::CORRECTION_DELAY,
                    "correctionDelay",
                    RangeKind::CorrectionDelay,
                )
                .enabled_when(Is("typoCorrection", "standard")),
                Row::seconds(
                    more::REVIEW_CORRECTION_TIMEOUT,
                    "reviewCorrectionTimeout",
                    RangeKind::ReviewCorrectionTimeout,
                )
                .enabled_when(Is("typoCorrection", "standard")),
                Row::seconds(
                    more::LATE_CORRECTION_TIMEOUT,
                    "lateCorrectionTimeout",
                    RangeKind::LateCorrectionTimeout,
                )
                .enabled_when(Is("typoCorrection", "standard")),
                Row::toggle(
                    more::REMEMBERS_REJECTED_CORRECTIONS,
                    "remembersRejectedCorrections",
                )
                .enabled_when(Is("typoCorrection", "standard")),
            ],
        ),
        Section::new(
            features::NOTATION,
            vec![
                Row::choice(features::OKURIGANA, "okuriganaStyle", options::OKURIGANA),
                Row::toggle(features::PREFERS_KATAKANA, "prefersKatakana"),
            ],
        ),
        Section::new(
            association::SECTION,
            vec![
                Row::toggle(association::ENABLED, "association"),
                Row::stepper(
                    association::LIMIT,
                    "associationLimit",
                    RangeKind::AssociationLimit,
                )
                .enabled_when(Condition::On("association")),
                Row::toggle(association::HINT, "showsAssociationHint")
                    .enabled_when(Condition::On("association")),
            ],
        ),
        Section {
            title: Some(association::DICTIONARIES),
            rows: vec![Row::new(
                "",
                "",
                Control::Dictionaries(DictionaryList::Association, ASSOCIATION_SPEC),
            )],
            footer: Some(association::NOTE),
            footer_variants: &[],
        },
        Section::new(
            settings::SPECIAL_CONVERSION,
            vec![
                Row::toggle(features::CALCULATION, "calculation"),
                Row::toggle(features::POSTAL_CODE, "postalCodeConversion"),
                Row::toggle(features::HANDWRITING, "handwriting"),
                Row::toggle(settings::DATE_CONVERSION, "dateConversion"),
                Row::toggle(settings::HOMOPHONE_NOTES, "homophoneNotes"),
                Row::toggle(settings::MISUSE_NOTES, "misuseNotes"),
                Row::toggle(settings::PROOFREADING, "proofreading"),
                Row::toggle(settings::SYMBOL_CONVERSION, "symbolConversion"),
                Row::toggle(settings::EMOJI_CONVERSION, "emojiConversion"),
            ],
        ),
        Section::new(
            settings::LEARNING,
            vec![
                Row::choice(settings::LEARNING, "learning", options::LEARNING),
                Row::action(settings::RESET_LEARNING, Action::ResetLearning),
            ],
        ),
    ]
}

const CORRECTION_RULE_FIELDS: &[Field] = &[
    Field::named("typed", features::TYPED, true),
    Field::named("word", features::REPLACEMENT, false),
];
const EXCEPTION_FIELDS: &[Field] = &[Field::text(features::EXCEPTION_PLACEHOLDER)];
const ROMAJI_FIELDS: &[Field] = &[
    Field::named("keys", settings::ROMAJI_KEYS, true),
    Field::named("kana", settings::ROMAJI_KANA, false),
];
const WORD_FIELDS: &[Field] = &[Field::text(features::WORD_PLACEHOLDER)];
const LANGUAGE_RULE_FIELDS: &[Field] = &[
    Field::named("word", features::LANGUAGE_RULE_WORD, true),
    Field::choice(
        "context",
        features::LANGUAGE_RULE_CONTEXT,
        options::WORD_CONTEXTS,
        true,
    ),
    Field::choice(
        "language",
        features::LANGUAGE_RULE_RESULT,
        options::WORD_LANGUAGES,
        false,
    ),
];

/// 補正のページ(macOS の CorrectionPage)
fn correction() -> Vec<Section> {
    use Condition::*;
    vec![
        Section::new(
            features::CORRECTION_KINDS,
            vec![
                Row::toggle(features::CORRECTS_ENGLISH, "correction.english"),
                Row::toggle(features::CORRECTS_JAPANESE, "correction.japanese"),
                Row::toggle(features::CORRECTS_REPEATED_KEYS, "correction.repeatedKeys")
                    .enabled_when(On("correction.japanese")),
                Row::toggle(features::MISREADINGS, "misreadings"),
            ],
        ),
        Section::new(
            features::RULES,
            with_files(
                Row::list(
                    ListSpec {
                        path: "correction.rules",
                        fields: CORRECTION_RULE_FIELDS,
                        empty: features::RULES_EMPTY,
                        invalid: crate::strings::Text::Limited(crate::strings::LimitedText::Rule),
                        lowercase: false,
                        exclusive_with: None,
                    },
                    LimitKind::CorrectionRules,
                ),
                RuleList::CorrectionRules,
            ),
        ),
        Section::new(
            features::EXCEPTIONS,
            with_files(
                Row::list(
                    ListSpec {
                        path: "correction.exceptions",
                        fields: EXCEPTION_FIELDS,
                        empty: features::EXCEPTIONS_EMPTY,
                        invalid: crate::strings::Text::Limited(
                            crate::strings::LimitedText::Exception,
                        ),
                        lowercase: false,
                        exclusive_with: None,
                    },
                    LimitKind::CorrectionRules,
                ),
                RuleList::Exceptions,
            ),
        ),
    ]
}

/// 英語と日本語のページ(macOS の WordLanguagePage)
fn language() -> Vec<Section> {
    let words = |path, other, empty| {
        Row::list(
            ListSpec {
                path,
                fields: WORD_FIELDS,
                empty,
                invalid: crate::strings::Text::Limited(crate::strings::LimitedText::Word),
                lowercase: true,
                exclusive_with: Some(other),
            },
            LimitKind::WordLanguageEntries,
        )
    };
    vec![
        Section {
            title: Some(features::LANGUAGE_JUDGING),
            rows: vec![
                Row::toggle(features::USES_CONTEXT, "wordLanguage.usesContext"),
                Row::toggle(features::AVOIDS_OFFENSIVE, "wordLanguage.avoidsOffensive"),
            ],
            footer: Some(features::USES_CONTEXT_NOTE),
            footer_variants: &[],
        },
        Section::new(
            features::TRY_LANGUAGE,
            vec![Row::new("", "", Control::Preview)],
        ),
        Section::new(
            features::ENGLISH_WORDS,
            with_files(
                words(
                    "wordLanguage.englishWords",
                    "wordLanguage.japaneseWords",
                    features::ENGLISH_WORDS_EMPTY,
                ),
                RuleList::EnglishWords,
            ),
        ),
        Section::new(
            features::JAPANESE_WORDS,
            with_files(
                words(
                    "wordLanguage.japaneseWords",
                    "wordLanguage.englishWords",
                    features::JAPANESE_WORDS_EMPTY,
                ),
                RuleList::JapaneseWords,
            ),
        ),
        Section {
            title: Some(features::LANGUAGE_RULES),
            rows: vec![Row::list(
                ListSpec {
                    path: "wordLanguage.rules",
                    fields: LANGUAGE_RULE_FIELDS,
                    empty: crate::strings::windows::LANGUAGE_RULES_EMPTY,
                    invalid: crate::strings::Text::Limited(crate::strings::LimitedText::Word),
                    lowercase: true,
                    exclusive_with: None,
                },
                LimitKind::WordLanguageEntries,
            )],
            footer: Some(crate::strings::windows::LANGUAGE_NOTE),
            footer_variants: &[],
        },
    ]
}

const KEYMAP_FIELDS: &[Field] = &[
    Field::choice("state", keys::STATE, keys::STATES, false),
    Field::key_notation("key", keys::KEY, false),
    Field::choice("command", keys::COMMAND, keys::COMMANDS, false),
];

/// キー設定のページ(macOS の KeymapPage)．表の行は上から順に並び，同じキーの行は下の行を使う
fn keymap() -> Vec<Section> {
    vec![
        Section::untitled(vec![Row::new("", "", Control::KeymapReport)]),
        Section {
            title: None,
            rows: vec![Row::list(
                ListSpec {
                    path: "keymap",
                    fields: KEYMAP_FIELDS,
                    empty: "",
                    invalid: crate::strings::Text::Fixed(crate::strings::windows::INVALID_KEY),
                    lowercase: false,
                    exclusive_with: None,
                },
                LimitKind::KeymapEntries,
            )],
            footer: Some(crate::strings::windows::KEY_NOTE),
            footer_variants: keys::COMMAND_HELP,
        },
        Section::untitled(vec![
            Row::new(keys::PRESET_MENU, "", Control::Preset),
            Row::action(keys::RESTORE, Action::RestoreKeymap),
        ]),
    ]
}

const APP_FIELDS: &[Field] = &[
    Field::named("applicationPrefix", more::APPS, true),
    Field::choice("profile", more::BEHAVIOR, options::APP_PROFILES, false),
];

/// 除外設定のページ(macOS の ExclusionsPage)．アプリは実行ファイルの名前(小文字)で見分ける
fn apps() -> Vec<Section> {
    vec![
        Section {
            title: None,
            rows: vec![
                Row::list(
                    ListSpec {
                        path: "profileRules",
                        fields: APP_FIELDS,
                        empty: more::EXCLUSIONS_EMPTY,
                        invalid: crate::strings::Text::Fixed(crate::strings::windows::INVALID_APP),
                        lowercase: true,
                        exclusive_with: None,
                    },
                    LimitKind::ProfileRules,
                ),
                Row::action(more::IMPORT_CSV, Action::File(FileTask::ImportProfileRules)),
                Row::action(more::EXPORT_CSV, Action::File(FileTask::ExportProfileRules)),
            ],
            footer: Some(crate::strings::windows::EXCLUSIONS_NOTE),
            footer_variants: &[],
        },
        Section::untitled(vec![
            Row::toggle(more::TERMINAL_COMMANDS, "terminalCommands"),
            Row::toggle(
                settings::ESCAPE_SWITCHES_TO_DIRECT,
                "escapeSwitchesToDirect",
            ),
            Row::toggle(
                more::RESTRAINS_LIVE_CONVERSION_IN_CODE,
                "restrainsLiveConversionInCode",
            ),
        ]),
    ]
}

const DICTIONARY_FIELDS: &[Field] = &[
    Field::named("reading", settings::READING, false),
    Field::named("word", settings::WORD, false),
];

/// ユーザー辞書のページ(macOS の DictionaryPage)．登録した単語(同じ読みに別の単語を登録できる)と取り込んだ辞書
fn dictionary() -> Vec<Section> {
    let imported = Section {
        title: Some(dictionaries::IMPORTED),
        rows: vec![Row::new(
            "",
            "",
            Control::Dictionaries(DictionaryList::Imported, IMPORTED_SPEC),
        )],
        footer: Some(dictionaries::NOTE),
        footer_variants: &[],
    };
    vec![
        Section::new(
            crate::strings::dictionaries::USER_WORDS,
            vec![
                Row::new(
                    "",
                    "",
                    Control::Dictionary(ListSpec {
                        path: "userDictionary",
                        fields: DICTIONARY_FIELDS,
                        empty: settings::DICTIONARY_EMPTY,
                        invalid: crate::strings::Text::Limited(crate::strings::LimitedText::Entry),
                        lowercase: false,
                        exclusive_with: None,
                    }),
                ),
                Row::action(
                    settings::IMPORT_DICTIONARY,
                    Action::File(FileTask::ImportUserDictionary),
                ),
                Row::action(
                    settings::EXPORT_DICTIONARY,
                    Action::File(FileTask::ExportUserDictionary),
                ),
            ],
        ),
        imported,
    ]
}

/// 記号のページ(macOS の SymbolsPage)．既定の決まりは変えず，変えた分だけを設定に重ねる
fn symbols() -> Vec<Section> {
    let section = |title, kind, fields, invalid, file| {
        let mut rows = vec![Row::new(
            "",
            "",
            Control::Symbols(
                kind,
                ListSpec {
                    path: "",
                    fields,
                    empty: features::SYMBOLS_EMPTY,
                    invalid,
                    lowercase: false,
                    exclusive_with: None,
                },
            ),
        )];
        rows.extend(file_rows(file));
        Section::new(title, rows)
    };
    vec![
        section(
            features::SEQUENCES,
            SymbolKind::Sequence,
            SEQUENCE_FIELDS,
            crate::strings::Text::Limited(crate::strings::LimitedText::Symbol),
            RuleList::SymbolSequences,
        ),
        section(
            features::READINGS,
            SymbolKind::Reading,
            READING_FIELDS,
            crate::strings::Text::Limited(crate::strings::LimitedText::ReadingSymbol),
            RuleList::SymbolReadings,
        ),
    ]
}

const SEQUENCE_FIELDS: &[Field] = &[
    Field::named("input", features::INPUT, false),
    Field::named("output", features::OUTPUT, false),
];

const READING_FIELDS: &[Field] = &[
    Field::named("input", features::READING_INPUT, false),
    Field::named("output", features::READING_OUTPUT, false),
];

/// ローマ字のページ(macOS の RomajiPage)．標準の表に重ねる綴り
fn romaji() -> Vec<Section> {
    vec![Section::untitled(with_files(
        Row::list(
            ListSpec {
                path: "customRomaji",
                fields: ROMAJI_FIELDS,
                empty: settings::ROMAJI_EMPTY,
                invalid: crate::strings::Text::Limited(crate::strings::LimitedText::Romaji),
                lowercase: false,
                exclusive_with: None,
            },
            LimitKind::RomajiRules,
        ),
        RuleList::Romaji,
    ))]
}

/// 一覧と，その一覧のファイルを読み込む・書き出すボタン(macOS の RuleListEditor のインポート・エクスポート)
fn with_files(list: Row, file: RuleList) -> Vec<Row> {
    std::iter::once(list).chain(file_rows(file)).collect()
}

fn file_rows(file: RuleList) -> [Row; 2] {
    [
        Row::action(
            settings::IMPORT_DICTIONARY,
            Action::File(FileTask::ImportRuleList(file)),
        ),
        Row::action(
            settings::EXPORT_DICTIONARY,
            Action::File(FileTask::ExportRuleList(file)),
        ),
    ]
}

const THEME_FIELDS: &[Field] = &[Field::named("name", more::THEME_NAME, false)];

/// 外観のページ(macOS の AppearancePage と CustomThemeEditor)．既成のテーマを選ぶとカスタムテーマを外す(macOS の selectTheme と同じ)．
/// カスタムテーマは一覧で選んだものを下の行で編集する(値は crate::themes の「customTheme.」の道筋)
fn appearance() -> Vec<Section> {
    use crate::themes;
    use Condition::*;
    let editing = || IsNot(themes::ID, "");
    let mut colors: Vec<Row> = themes::COLORS
        .iter()
        .map(|(path, title)| Row::new(title, path, Control::Color).visible_when(editing()))
        .collect();
    colors.push(
        Row::new(more::READABILITY, "", Control::ThemeReport)
            .visible_when(IsNot(themes::READABILITY, "")),
    );
    vec![
        Section::untitled(vec![Row::new(more::PREVIEW, "", Control::ThemePreview)]),
        Section::new(
            more::THEME,
            vec![Row::choice(more::THEME, "theme", options::THEMES).clearing("customThemeID")],
        ),
        Section::new(
            more::CUSTOM_THEMES,
            vec![Row::new(
                "",
                "",
                Control::CustomThemes(ListSpec {
                    path: "customThemes",
                    fields: THEME_FIELDS,
                    empty: more::NO_CUSTOM_THEMES,
                    invalid: crate::strings::Text::Fixed(more::INVALID_THEME),
                    lowercase: false,
                    exclusive_with: None,
                }),
            )],
        ),
        Section::new(more::COLORS, colors),
        Section::new(
            more::SHAPE,
            vec![
                Row::stepper(
                    more::CORNER_RADIUS,
                    themes::CORNER_RADIUS,
                    RangeKind::CustomThemeCornerRadius,
                )
                .visible_when(editing()),
                Row::choice(
                    more::BRANCH_STYLE,
                    themes::BRANCH_STYLE,
                    options::BRANCH_STYLES,
                )
                .visible_when(editing()),
                Row::choice(more::FONT, themes::FONT_NAME, options::THEME_FONTS)
                    .visible_when(editing()),
            ],
        ),
        Section::new(
            more::FONT,
            vec![Row::stepper(
                settings::FONT_SIZE_NAME,
                "candidateFontSize",
                RangeKind::CandidateFontSize,
            )],
        ),
    ]
}

/// 統計のページ(macOS の UsageTab)．回数はエンジンに頼んで読む
fn usage() -> Vec<Section> {
    vec![
        Section::untitled(vec![
            Row::toggle(settings::RECORDS_USAGE, "recordsUsage"),
            Row::note(settings::USAGE_NOTE),
        ]),
        Section::new(
            settings::USAGE_TAB,
            vec![
                Row::stat(settings::FIRST_CANDIDATE_RATE, Stat::FirstCandidateRate),
                Row::stat(settings::COMMITS, Stat::Commits),
                Row::stat(settings::CONVERSIONS_OPENED, Stat::ConversionsOpened),
                Row::stat(settings::SEGMENTS_CHANGED, Stat::SegmentsChanged),
                Row::stat(settings::READING_CORRECTIONS, Stat::ReadingCorrections),
                Row::stat(settings::ENGLISH_CORRECTIONS, Stat::EnglishCorrections),
            ],
        ),
        Section::untitled(vec![Row::action(settings::RESET_USAGE, Action::ResetUsage)]),
    ]
}

/// 同期のページ(macOS の SyncPage)．値は「sync.」の道筋でエンジンの同期の状態から読む(crate::sync)
fn sync_page() -> Vec<Section> {
    use Condition::*;
    let mut scopes: Vec<Row> = options::SYNC_GROUPS
        .iter()
        .map(|(group, name)| Row::choice(name, scope_path(group), options::SYNC_SCOPES))
        .collect();
    scopes.push(Row::new(
        sync::ITEMS,
        "",
        Control::SyncFields(ListSpec {
            path: "",
            fields: &[],
            empty: "",
            invalid: crate::strings::Text::Fixed(""),
            lowercase: false,
            exclusive_with: None,
        }),
    ));
    vec![
        Section {
            title: None,
            rows: vec![
                Row::toggle(sync::ENABLED, crate::sync::ENABLED)
                    .enabled_when(IsNot(crate::sync::FOLDER, "")),
                Row::new(sync::FOLDER, "", Control::Info(Info::SyncFolder)),
                Row::action(sync::CHOOSE_FOLDER, Action::ChooseSyncFolder),
                Row::new(sync::LAST_SYNCED, "", Control::Info(Info::LastSynced)),
                Row::note(sync::FAILED)
                    .visible_when(Is(crate::sync::PROBLEM, crate::sync::PROBLEM_FAILED)),
                Row::note(sync::UNREADABLE)
                    .visible_when(Is(crate::sync::PROBLEM, crate::sync::PROBLEM_UNREADABLE)),
                Row::action(sync::SYNC_NOW, Action::SyncNow).enabled_when(On(crate::sync::ENABLED)),
            ],
            footer: Some(crate::strings::windows::SYNC_NOTE),
            footer_variants: &[],
        },
        Section::new(sync::SCOPES, scopes),
    ]
}

/// まとまりの範囲の道筋．ページの行は &'static str の道筋を持つので，まとまりごとに一度だけ作って残す
fn scope_path(group: &str) -> &'static str {
    use std::collections::HashMap;
    use std::sync::{Mutex, OnceLock};
    static PATHS: OnceLock<Mutex<HashMap<String, &'static str>>> = OnceLock::new();
    let mut paths = PATHS
        .get_or_init(Default::default)
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    paths
        .entry(group.to_string())
        .or_insert_with(|| Box::leak(crate::sync::scope_path(group).into_boxed_str()))
}

/// バックアップのページ(macOS の BackupPage)．設定のファイルを開くボタンも置く(画面に無い項目を直すため)
fn backup() -> Vec<Section> {
    vec![
        Section {
            title: None,
            rows: vec![
                Row::action(
                    more::EXPORT_SETTINGS,
                    Action::File(FileTask::ExportSettings),
                ),
                Row::action(
                    more::IMPORT_SETTINGS,
                    Action::File(FileTask::ImportSettings),
                ),
            ],
            footer: Some(more::BACKUP_NOTE),
            footer_variants: &[],
        },
        Section::untitled(vec![Row::action(
            crate::strings::windows::OPEN_SETTINGS_FILE,
            Action::OpenSettingsFile,
        )]),
        Section::untitled(vec![Row::action(
            settings::RESTORE_DEFAULTS,
            Action::RestoreDefaults,
        )]),
    ]
}

/// 情報のページ(macOS の AboutPage)．謝辞は配布物に入れた THIRD_PARTY_NOTICES.md をそのまま出す
fn about() -> Vec<Section> {
    vec![
        Section::untitled(vec![
            Row::new(more::VERSION, "", Control::Version),
            Row::action(crate::strings::wizard::REDO, Action::OpenSetup),
        ]),
        Section {
            title: Some(more::ACKNOWLEDGEMENTS),
            rows: vec![Row::new(more::ACKNOWLEDGEMENTS, "", Control::Notices)],
            footer: Some(more::ACKNOWLEDGEMENTS_NOTE),
            footer_variants: &[],
        },
    ]
}

/// 条件を今の値で確かめる
pub fn holds(
    condition: Condition,
    text: impl Fn(&str) -> String,
    on: impl Fn(&str) -> bool,
) -> bool {
    match condition {
        Condition::Is(path, value) => text(path) == value,
        Condition::IsNot(path, value) => text(path) != value,
        Condition::On(path) => on(path),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 左の一覧は見出しごとに並ぶ() {
        let all = sidebar(&Page::ALL, "");
        assert_eq!(all.len(), 5);
        assert_eq!(all[0].0, Group::Input);
        assert_eq!(
            all[0].1,
            vec![
                Page::Input,
                Page::Conversion,
                Page::Correction,
                Page::Language,
                Page::Romaji,
                Page::Keys,
                Page::Apps
            ]
        );
        assert_eq!(all[3].1, vec![Page::Usage, Page::Sync, Page::Backup]);
    }

    #[test]
    fn 項目の名前でページを探す() {
        let found = sidebar(&Page::ALL, "郵便番号");
        assert_eq!(found, vec![(Group::Input, vec![Page::Conversion])]);
        let found = sidebar(&Page::ALL, "全角空白");
        assert_eq!(found, vec![(Group::Input, vec![Page::Keys])]);
    }

    #[test]
    fn 英字は大文字と小文字を区別しない() {
        assert!(Page::Keys.matches("EMACS"));
        assert!(Page::Input.matches(" テンキー "));
        assert!(!Page::Input.matches("郵便番号"));
    }

    #[test]
    fn 作っていないページは出さない() {
        let found = sidebar(&[Page::Input], "");
        assert_eq!(found, vec![(Group::Input, vec![Page::Input])]);
    }

    #[test]
    fn 条件を値で確かめる() {
        let text = |_: &str| "english".to_string();
        let on = |_: &str| false;
        assert!(holds(Condition::Is("inputStyle", "english"), text, on));
        assert!(!holds(Condition::IsNot("inputStyle", "english"), text, on));
        assert!(!holds(Condition::On("showsModeIndicator"), text, on));
    }

    #[test]
    fn 作ったページには中身がある() {
        for page in BUILT {
            assert!(
                sections(*page).is_some_and(|sections| !sections.is_empty()),
                "{page:?}"
            );
        }
    }

    #[test]
    fn 値の項目の名前は設定のファイルにある() {
        let catalog = crate::catalog::Catalog::load().unwrap();
        for page in BUILT {
            for section in sections(*page).unwrap() {
                let lists = section
                    .rows
                    .iter()
                    .filter(|row| matches!(row.control, Control::List(..)));
                for row in section
                    .rows
                    .iter()
                    .filter(|row| row.has_value())
                    .chain(lists)
                    // 同期の値と編集しているカスタムテーマの値は設定のファイルの項目ではない(crate::sync・crate::themes)
                    .filter(|row| {
                        !crate::sync::is_sync_path(row.path)
                            && !crate::themes::is_theme_path(row.path)
                    })
                {
                    let name = crate::model::field_name(row.path);
                    assert!(catalog.fields.iter().any(|field| field == name), "{name}");
                }
                for row in section.rows.iter().filter_map(|row| row.clears) {
                    assert!(catalog.fields.iter().any(|field| field == row), "{row}");
                }
            }
        }
    }

    #[test]
    fn 入力のページの並び() {
        let page = sections(Page::Input).unwrap();
        let titles: Vec<_> = page.iter().map(|section| section.title).collect();
        assert_eq!(titles, vec![Some("入力方式"), Some("文字"), Some("動作")]);
        assert_eq!(page[1].rows.len(), 9);
    }
}
