#![forbid(unsafe_code)]

//! 設定の画面のページと，その中の項目の並び．macOS の SettingsView(Group・Page・各ページの Form)と同じ並び・同じ文言にする．
//! Windows の部品の作り方はここでは決めず，app が並びに従って部品を作る

use crate::files::FileTask;
use crate::list::{Field, ListSpec};
use crate::options::{self, Choice};
use crate::strings::{
    association, choice, dictionaries, extras, features, keys, menu, more, palette, settings, sync,
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
    Palette,
    Commands,
    Appearance,
    Usage,
    Sync,
    Backup,
    About,
}

impl Page {
    pub const ALL: [Page; 16] = [
        Page::Input,
        Page::Conversion,
        Page::Correction,
        Page::Language,
        Page::Romaji,
        Page::Keys,
        Page::Apps,
        Page::Dictionary,
        Page::Symbols,
        Page::Palette,
        Page::Commands,
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
            Page::Dictionary | Page::Symbols | Page::Palette | Page::Commands => Group::Dictionary,
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
            Page::Palette => palette::PAGE,
            Page::Keys => keys::TAB,
            Page::Dictionary => settings::DICTIONARY_TAB,
            Page::Commands => extras::COMMANDS_PAGE,
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
            Page::Palette => '\u{E76E}',    // 絵文字
            Page::Commands => '\u{E945}',   // 稲妻
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
                settings::NUMBER_SEPARATORS,
                settings::ALPHANUMERIC_HYPHEN,
                settings::QUESTION_EXCLAMATION_COMMITS,
                settings::KEYPAD_CALCULATION,
                settings::CYCLES_LETTER_CASE,
            ],
            Page::Conversion => vec![
                menu::LIVE_CONVERSION,
                choice::PRESENTATION,
                choice::INITIAL_FOCUS,
                choice::PREDICTION_DISPLAY,
                choice::HIDDEN_PREDICTIONS,
                features::OKURIGANA,
                features::PREFERS_KATAKANA,
                features::CALCULATION,
                features::POSTAL_CODE,
                features::HANDWRITING,
                settings::DATE_CONVERSION,
                settings::EMOJI_CONVERSION,
                settings::EMOJI_WORD_CONVERSION,
                settings::EMOJI_CANDIDATE_POSITION,
                settings::EMOJI_CANDIDATE_COUNT,
                settings::SHOWS_EMOJI_NAMES,
                settings::LATEX_CONVERSION,
                settings::NUMBER_FORM_CONVERSION,
                association::ENABLED,
                association::LIMIT,
                association::DICTIONARIES,
                settings::MEANING,
                settings::SHOWS_PART_OF_SPEECH,
                settings::CANDIDATE_RERANKING,
                settings::JINEN_MODEL,
            ],
            Page::Correction => vec![
                features::EXCEPTIONS,
                features::RULES,
                features::CORRECTS_ENGLISH,
                features::MISREADINGS,
                extras::HAND_SHIFT,
                extras::LOOSE_READINGS,
                extras::PHONETIC_SPELLING,
            ],
            Page::Language => vec![
                features::ENGLISH_WORDS,
                features::JAPANESE_WORDS,
                features::LANGUAGE_RULES,
                features::TRY_LANGUAGE,
                options::INPUT_STYLES[3].1,
                extras::ENGLISH_TERMS_SECTION,
                extras::ENGLISH_TERMS,
            ],
            Page::Symbols => vec![features::SEQUENCES, features::READINGS],
            Page::Palette => vec![
                palette::ENABLED,
                palette::EMOJI_KEY,
                palette::SYMBOL_KEY,
                palette::CLOSES_AFTER_INSERT,
                palette::RECORDS_HISTORY,
                palette::CLEAR_HISTORY,
                palette::COLUMNS,
                palette::ROWS,
                palette::CELL_SIZE,
                palette::FREQUENT_ROWS,
                palette::SHOWS_PREVIEW,
                palette::SHOWS_UNICODE_NAME,
                palette::SHOWS_READINGS,
                palette::SHOWS_SHORTCODES,
                palette::SHOWS_CODE_POINTS,
            ],
            // コマンドと状態の名前でも見つける(「全角空白」「英数」「切り替え」で キー設定 を出す)
            Page::Keys => std::iter::once(keys::PRESET_MENU)
                .chain(keys::COMMANDS.iter().map(|(_, label)| *label))
                .chain(keys::STATES.iter().map(|(_, label)| *label))
                .chain(keys::PRESETS.iter().map(|(_, label)| *label))
                .collect(),
            Page::Dictionary => [
                settings::READING,
                settings::WORD,
                dictionaries::IMPORTED,
                extras::DYNAMIC_DICTIONARY,
                dictionaries::TERMS,
                crate::strings::terms::ENABLED,
            ]
            .into_iter()
            .chain(
                crate::strings::terms::FIELD_NAMES
                    .iter()
                    .map(|(_, name)| *name),
            )
            .collect(),
            Page::Commands => vec![
                extras::LAUNCHER_COMMANDS,
                extras::MACROS_SECTION,
                extras::CONVERSION_MACROS,
                extras::MACRO_SKIPS_SAME_READING,
                extras::TRY_MACROS,
            ],
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
    /// すべての条件を満たすとき
    All(&'static [Condition]),
    /// どれかの条件を満たすとき
    Any(&'static [Condition]),
}

/// カスタムテーマの書体の欄(macOS の ThemeFontPicker)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FontPart {
    /// ファミリー
    Family,
    /// ファミリーの中のスタイル(太さ・斜体など)
    Style,
}

/// 1 行の部品
#[derive(Debug, Clone, PartialEq)]
pub enum Control {
    /// オン・オフ
    Toggle,
    /// 列挙の値を選ぶ
    Choice(&'static [Choice]),
    /// カスタムテーマの書体(入っている書体から選ぶ．選択肢は OS から読む)
    ThemeFont(FontPart),
    /// 整数を範囲の中で 1 段ずつ選ぶ(候補の数．macOS の Stepper)．値を左に，減らす・増やすボタンを右に置く
    Stepper(RangeKind),
    /// 秒を範囲の中で選ぶスライダー(0.1 秒ごと．macOS の SecondsSlider)．今の値を右に出す
    Seconds(RangeKind),
    /// 値を範囲の中で選ぶスライダー．今の値は名前の後ろに出す(macOS の「候補の文字サイズ: 15」)
    Slider(RangeKind),
    /// 既成のテーマの 1 つ(値)．選ぶ印と見本の色を並べる(macOS の AppearancePage の ThemeRow)
    ThemeOption(&'static str),
    /// 1 つのカードに並べる操作のボタン(名前と操作．macOS の HStack の Button)
    Buttons(&'static [(&'static str, Action)]),
    /// 一覧を切り替える部品(path の値．macOS の segmented の Picker)．カードに入れず真ん中に置く
    Segmented(&'static [Choice]),
    /// エンジンから読んだ値と，その右の操作のボタン(ボタンの名前)．macOS の LabeledContent の中の Text と Button
    InfoAction(Info, Action, &'static str),
    /// 注記(前の行の説明として小さい文字で出す)
    Note,
    /// エンジンに頼む操作のボタン(項目の名前をボタンに出す)
    Action(Action),
    /// 使い方の記録の値(変えられない)
    Stat(Stat),
    /// 決まりの一覧(入力欄・追加・削除・表)
    List(ListSpec, LimitKind),
    /// 試す欄(2 つの入力欄と結果)．何を試すかは TryKind
    Preview(TryKind),
    /// アプリのバージョン(変えられない)と，更新を確かめるボタン
    Version,
    /// 名前の右に置く操作のボタン(ボタンの名前)．macOS の LabeledContent の中のボタン
    LabeledAction(Action, &'static str),
    /// 謝辞の 1 項目(notices::installed の番号)．名前・出どころ・開いて読むライセンスの全文
    Acknowledgement(usize),
    /// キー設定の表の問題(使われない行・キーの無い確定など)．無ければ出さない
    KeymapReport,
    /// キー設定のひな形を選んで読み込む
    Preset,
    /// 登録した単語．数が多くなるので設定の値としてではなく，エンジンに分けて読んでもらい，1 語ずつ足す・消す
    Dictionary(ListSpec),
    /// 記号の決まり．既定の決まりに利用者の決まりを重ねた一覧をエンジンに読んでもらい，決まりを重ねる・外す・有効と無効を切り替える
    Symbols(SymbolKind, ListSpec),
    /// エンジンから読んだ値を出す(変えられない)
    Info(Info),
    /// 同期の項目ごとの範囲の表．選んだ項目の範囲を切り替える
    SyncFields(ListSpec),
    /// 取り込んだ辞書・連想の辞書の一覧(macOS の ImportedDictionariesView・AssociationSection)．
    /// 辞書ごとに開いて閉じる行(オン・オフ・名前・要約・並べ替え)にし，開いた行で名前などを変える．一覧の下に取り込むボタンを置く
    Dictionaries(DictionaryList),
    /// カスタムテーマの 1 つ(一覧の番号)．既成のテーマと同じく選ぶ印・見本の色・名前を並べ，読みにくければ印を付け，
    /// 右のボタンで編集・複製・削除する(macOS の AppearancePage の CustomThemeRow)．
    /// ページを作るときに上限の数だけ並べ(with_custom_theme_rows)，今あるテーマの数だけ出す
    CustomTheme(usize),
    /// 薄い字で出す知らせ(一覧が空のとき．macOS の secondary の Text)
    Placeholder,
    /// 色を選ぶボタン(「#RRGGBB」の値．押すと色を選ぶ窓を出す)
    Color,
    /// 外観の見本(候補ウィンドウと同じ描き方の分岐図)
    ThemePreview,
    /// パレットの見本(パレットの窓と同じ描き方．列数・行数・マスの大きさは設定のとおり)
    PalettePreview,
    /// 絵文字の候補の見本(候補の窓と同じ描き方の一覧．絵文字の位置・数・名前は設定のとおり)
    EmojiPreview,
    /// カスタムテーマの読みにくい組み合わせの 1 つ(知らせの番号)．注意の印と文を並べる．無ければ出さない
    /// (macOS の CustomThemeEditor の Label)
    ThemeIssue(usize),
    /// 1 行の文字を打つ欄(カスタムテーマの名前．macOS の TextField)
    TextField,
    /// 試した結果だけを並べる欄(変換マクロ．試す語と読みの欄は一覧の上の Preview に置く．macOS の CommandsPage)
    PreviewChips(TryKind),
}

/// 書き方のチップ(macOS の TemplatePalette)を開ける一覧と，書き方を入れる欄．
/// 欄のすぐ右の「{ }」のボタンか，欄で「{」を打つと，欄の下にチップを開く(macOS の RuleListEditor の TemplateAssist)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TemplateTarget {
    /// 登録した単語の単語の欄
    Word,
    /// 変換マクロの形の欄
    Macro,
}

impl TemplateTarget {
    /// チップのまとまり．変換マクロは，選んでいる語と読みのまとまりを先に置く
    pub fn groups(self) -> &'static [crate::template_reference::Group] {
        match self {
            TemplateTarget::Word => crate::strings::templates::WORD,
            TemplateTarget::Macro => crate::strings::templates::MACRO,
        }
    }

    /// 書き方を入れる欄の番号(一覧の入力欄の中の位置)
    pub fn field(self) -> usize {
        match self {
            TemplateTarget::Word => 1,
            TemplateTarget::Macro => 0,
        }
    }

    /// チップを開いているかを覚える名前(ページごと．HKCU の Hajime IME の値)
    pub fn storage_name(self) -> &'static str {
        match self {
            TemplateTarget::Word => "TemplatesOpenDictionary",
            TemplateTarget::Macro => "TemplatesOpenMacros",
        }
    }
}

/// 試す欄で試すもの
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TryKind {
    /// 英語と日本語の見分け(打つ文・前の文字列)．結果の語をいつも英語・いつも日本語にする単語に足すボタンを置く
    Language,
    /// 変換マクロ(試す語・読み)．変換マクロの欄に形を書いている途中なら，その形だけを当てる(macOS の CommandsPage)
    Macros,
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
    Commands,
    Macros,
    EnglishTerms,
    HiddenPredictions,
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
            LimitKind::Commands => catalog.limits.commands,
            LimitKind::Macros => catalog.limits.macros,
            LimitKind::EnglishTerms => catalog.limits.english_terms,
            LimitKind::HiddenPredictions => catalog.limits.hidden_predictions,
        }
    }
}

/// ボタンで頼む操作
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    ResetLearning,
    ResetUsage,
    /// パレットで使った文字の記録を消す(R-26)
    ResetPaletteHistory,
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
    /// 新しいバージョンがあるかを確かめ，あれば尋ねてから入れる(R-19．押したときだけ通信する)
    CheckForUpdates,
    /// 今のテーマを写したカスタムテーマを編集の画面で作る(macOS の AppearancePage の「カスタムテーマを作成…」)
    CreateTheme,
    /// 今のテーマを複製してカスタムテーマにし，それを使う
    DuplicateCurrentTheme,
    /// キーの無い確定・取り消しに，標準の表のキーを足す(macOS の KeymapPage の「既定のキーを追加」)
    AddMissingKeys,
    /// キー設定のページを開く(パレットを開くキーを変えるとき)
    OpenKeys,
}

impl Action {
    /// 消す・戻す操作か(ボタンを危険の色で描く．macOS の role: .destructive)．
    /// パレットで使った文字の記録を消すボタンは，macOS と同じく普通のボタンにし，確かめる窓だけで知らせる
    pub fn is_destructive(self) -> bool {
        matches!(
            self,
            Action::ResetLearning
                | Action::ResetUsage
                | Action::RestoreDefaults
                | Action::RestoreKeymap
        )
    }
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

    /// 一覧の下の取り込むボタンの名前
    pub fn import_label(self) -> &'static str {
        match self {
            DictionaryList::Imported => dictionaries::IMPORT_FILE,
            DictionaryList::Association => association::IMPORT_FILE,
        }
    }

    /// 辞書が無いときに一覧に出す文
    pub fn empty_text(self) -> &'static str {
        match self {
            DictionaryList::Imported => dictionaries::EMPTY,
            DictionaryList::Association => association::EMPTY,
        }
    }
}

/// 使う場面(DictionaryCondition)の選択肢．値は設定のファイルの名前
pub const DICTIONARY_CONDITIONS: &[Choice] = &[
    ("always", dictionaries::ALWAYS),
    ("apps", dictionaries::APPS),
    ("context", dictionaries::CONTEXT),
];

/// 一覧の入力欄の右のボタンと，表の下のボタン(並びは部品を作る順と同じ)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ListButtons {
    pub top: &'static [&'static str],
    pub bottom: &'static [&'static str],
    /// 表の下の左に検索欄を置く(行の多い一覧)
    pub search: bool,
    /// 検索欄の右に状態で絞り込む欄を置く(キー設定．macOS の KeymapPage の状態の Picker)
    pub filter: bool,
    /// 表の下の右に置く，一覧のファイルを読み込む・書き出すボタン(macOS の RuleListEditor の下の帯)
    pub files: Option<ListFiles>,
    /// この番号の入力欄のあとに矢印を置く(打つもの → 置き換えるもの．macOS の RuleListEditor・判別ルールの前 → 結果)
    pub arrow: Option<usize>,
    /// 先頭から決まった幅にする入力欄の幅(残りの欄で残りの幅を分ける．キー設定の状態とキー)
    pub field_widths: &'static [f32],
    /// 検索欄と絞り込みを入力欄の上の帯に置く(キー設定．macOS の KeymapPage の上の帯)
    pub toolbar: bool,
    /// 表の下のボタンのうち，右に寄せる末尾のボタンの数(キー設定の既定に戻す)
    pub trailing_bottom: usize,
    /// 最後の入力欄を次の行に幅いっぱいで置く(ユーザー辞書のコメント．macOS の RuleListEditor の添え書きの欄)
    pub note_line: bool,
    /// 末尾から何個の欄を，入力欄の並びでなく表の下の帯の左(下のボタンの前)に置くか
    /// (除外設定の動作．macOS の ExclusionsPage は足すアプリの動作を表の下で選ぶ)
    pub bottom_fields: usize,
    /// 欄を一覧の上に並べず，シートで書く(コマンド．macOS の CommandsPage の CommandEditor)
    pub sheet: bool,
    /// 表の下の「優先度を上げる」「優先度を下げる」を山形の絵のボタンにする(除外設定．macOS の chevron.up・chevron.down)
    pub move_icons: bool,
    /// 入力欄と表のあいだに，打った行の確かめの文(形の誤り・上書き)の行を置く(macOS の RuleListEditor の message)
    pub message_line: bool,
    /// 入力欄のすぐ下に，入れたときの結果の行を置く(書き方を書ける単語と変換マクロの形．macOS の RuleListEditor の showingResult)．
    /// 結果のあるときだけ行を取る(layout::ListState)
    pub result: bool,
    /// この番号の入力欄のすぐ右に，書き方のチップを開け閉めする「{ }」のボタンを置く(TemplateTarget::field)
    pub template_field: Option<usize>,
}

/// 一覧のファイルを読み込む・書き出す操作
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ListFiles {
    pub import: FileTask,
    pub export: FileTask,
}

impl ListFiles {
    fn rule_list(list: RuleList) -> Self {
        Self {
            import: FileTask::ImportRuleList(list),
            export: FileTask::ExportRuleList(list),
        }
    }

    /// ボタンの名前
    pub fn labels(self) -> [&'static str; 2] {
        [settings::IMPORT_DICTIONARY, settings::EXPORT_DICTIONARY]
    }

    /// index 番目(0 は読み込む，1 は書き出す)のボタンの操作
    pub fn task(self, index: usize) -> FileTask {
        if index == 0 {
            self.import
        } else {
            self.export
        }
    }
}

impl ListButtons {
    /// 一覧の上に並べる欄の数(fields は一覧の欄の数)
    pub fn top_fields(&self, fields: usize) -> usize {
        if self.sheet {
            0
        } else {
            fields.saturating_sub(self.bottom_fields)
        }
    }

    /// 入力欄を作る欄の数(上に並べる欄と表の下に置く欄)
    pub fn input_fields(&self, fields: usize) -> usize {
        if self.sheet {
            0
        } else {
            fields
        }
    }

    /// 下のボタンを山形の絵にするか(名前は読み上げと説明の吹き出しに使う)
    pub fn is_icon(&self, label: &str) -> bool {
        self.move_icons && (label == dictionaries::MOVE_UP || label == dictionaries::MOVE_DOWN)
    }

    /// 表の下のボタンの名前(ファイルのボタンを含む．部品を作る順)
    pub fn bottom_labels(&self) -> Vec<&'static str> {
        self.bottom
            .iter()
            .copied()
            .chain(self.files.into_iter().flat_map(ListFiles::labels))
            .collect()
    }
}

/// 一覧のファイル．読み込む・書き出すことのできる一覧だけ
fn list_files(control: &Control) -> Option<ListFiles> {
    Some(match control {
        Control::List(spec, _) => match spec.path {
            "customRomaji" => ListFiles::rule_list(RuleList::Romaji),
            "correction.rules" => ListFiles::rule_list(RuleList::CorrectionRules),
            "correction.exceptions" => ListFiles::rule_list(RuleList::Exceptions),
            "wordLanguage.englishWords" => ListFiles::rule_list(RuleList::EnglishWords),
            "wordLanguage.japaneseWords" => ListFiles::rule_list(RuleList::JapaneseWords),
            "englishTerms" => ListFiles::rule_list(RuleList::EnglishTerms),
            "hiddenPredictions" => ListFiles::rule_list(RuleList::HiddenPredictions),
            _ => return None,
        },
        Control::Dictionary(_) => ListFiles {
            import: FileTask::ImportUserDictionary,
            export: FileTask::ExportUserDictionary,
        },
        Control::Symbols(SymbolKind::Sequence, _) => {
            ListFiles::rule_list(RuleList::SymbolSequences)
        }
        Control::Symbols(SymbolKind::Reading, _) => ListFiles::rule_list(RuleList::SymbolReadings),
        _ => return None,
    })
}

impl Control {
    /// 一覧の部品のボタン．一覧でなければ None
    pub fn list_buttons(&self) -> Option<ListButtons> {
        // 足す一覧は macOS の RuleListEditor と同じく，入力欄の右に追加(書き換えているあいだは更新とキャンセル)，
        // 表の下の左に削除を置く．有効・無効は表の「有効」の列で切り替える
        const ADD_CANCEL: &[&str] = &[settings::ADD, settings::CANCEL];
        let (top, bottom): (&'static [&'static str], &'static [&'static str]) = match self {
            // キー設定はキーを押して記録する・行を複製する，除外設定はアプリのファイルを選んで足す(macOS の KeymapPage・ExclusionsPage)
            // キー設定のキーは欄を押して記録する(macOS の KeyField)．macOS と同じく新しい行の右は追加だけにし，
            // 表の下に削除・複製・既定に戻すを置く
            Control::List(spec, _) if spec.path == "keymap" => (
                &[settings::ADD],
                &[settings::REMOVE, keys::DUPLICATE, keys::RESTORE],
            ),
            // 除外設定は macOS の ExclusionsPage と同じく，表の下に [動作][アプリを追加…] … [∧][∨][削除] を置く．
            // Windows は選ぶ窓に出ないアプリ(実行ファイルの名前の先頭)も書けるよう，上に名前の欄と追加を残す
            Control::List(spec, _) if spec.path == PROFILE_RULES => (
                &[settings::ADD],
                &[
                    more::ADD_APPS,
                    dictionaries::MOVE_UP,
                    dictionaries::MOVE_DOWN,
                    settings::REMOVE,
                ],
            ),
            // コマンドの表は読むだけで，足す・書き換えるはシートで行う(macOS の CommandsPage)
            Control::List(spec, _) if spec.path == COMMANDS => (
                &[],
                &[
                    extras::ADD_COMMAND,
                    extras::EDIT_COMMAND,
                    extras::REMOVE_COMMAND,
                ],
            ),
            Control::List(..) | Control::Dictionary(_) | Control::Symbols(..) => {
                (ADD_CANCEL, &[settings::REMOVE])
            }
            // 項目ごとの同期は表の「同期する」の印で切り替える(macOS の項目ごとのスイッチ)
            Control::SyncFields(_) => (&[], &[]),
            _ => return None,
        };
        // 除外設定・コマンド・判別ルールは行が少なく，macOS と同じく検索欄を置かない
        let search = matches!(
            self,
            Control::List(..) | Control::Dictionary(_) | Control::Symbols(..)
        ) && !matches!(
            self,
            Control::List(spec, _)
                if spec.path == PROFILE_RULES
                    || spec.path == COMMANDS
                    || spec.path == "wordLanguage.rules"
        );
        let filter = matches!(self, Control::List(spec, _) if spec.path == "keymap");
        // 打つもの → 置き換えるものの一覧(先頭の 2 つの欄がどちらも打つ欄)．コマンドの読みと名前は置き換えではない．
        // 判別ルールは「前」と「結果」のあいだに置く
        let replaces = matches!(
            self,
            Control::List(..) | Control::Dictionary(_) | Control::Symbols(..)
        ) && !matches!(self, Control::List(spec, _) if spec.path == COMMANDS)
            && self.list_spec().is_some_and(|spec| {
                spec.fields.len() >= 2
                    && spec.fields[..2]
                        .iter()
                        .all(|field| field.choices.is_none() && !field.notation)
            });
        let arrow = match self {
            Control::List(spec, _) if spec.path == "wordLanguage.rules" => Some(1),
            _ => replaces.then_some(0),
        };
        // キー設定の新しい行は状態とキーを決まった幅にし，コマンドに残りを渡す(macOS の KeymapPage)
        const KEYMAP_FIELD_WIDTHS: &[f32] = &[
            tokens::size::settings::KEYMAP_STATE_WIDTH,
            tokens::size::settings::KEYMAP_KEY_WIDTH,
        ];
        let field_widths: &'static [f32] = match self {
            Control::List(spec, _) if spec.path == "keymap" => KEYMAP_FIELD_WIDTHS,
            _ => &[],
        };
        let keymap = matches!(self, Control::List(spec, _) if spec.path == "keymap");
        let exclusions = matches!(self, Control::List(spec, _) if spec.path == PROFILE_RULES);
        // 除外設定の下の帯は [動作][アプリを追加…] を左に，[∧][∨][削除] を右に寄せる
        let trailing_bottom = if exclusions { 3 } else { usize::from(keymap) };
        Some(ListButtons {
            top,
            bottom,
            search,
            filter,
            files: list_files(self),
            arrow,
            field_widths,
            toolbar: keymap,
            trailing_bottom,
            note_line: matches!(self, Control::Dictionary(_)),
            bottom_fields: usize::from(exclusions),
            sheet: matches!(self, Control::List(spec, _) if spec.path == COMMANDS),
            move_icons: exclusions,
            // シートで書く一覧(コマンド)はシートの中で確かめる
            message_line: matches!(
                self,
                Control::List(..) | Control::Dictionary(_) | Control::Symbols(..)
            ) && !matches!(self, Control::List(spec, _) if spec.path == COMMANDS),
            result: matches!(self, Control::Dictionary(_))
                || matches!(self, Control::List(spec, _) if spec.path == MACROS_PATH),
            template_field: self.template_target().map(TemplateTarget::field),
        })
    }

    /// 書き方のチップを開ける一覧なら，書き方を入れる欄(登録した単語の単語の欄・変換マクロの形の欄)
    pub fn template_target(&self) -> Option<TemplateTarget> {
        match self {
            Control::Dictionary(spec) if spec.path == "userDictionary" => {
                Some(TemplateTarget::Word)
            }
            Control::List(spec, _) if spec.path == MACROS_PATH => Some(TemplateTarget::Macro),
            _ => None,
        }
    }

    /// 表の見出しを押して並べ替えられるか．除外設定は上の決まりから先に効くので，並びを変えて見せない
    pub fn sortable(&self) -> bool {
        !self.reorderable()
    }

    /// 表の下のボタンで選んだ行を上下に動かせる一覧か(除外設定)
    pub fn reorderable(&self) -> bool {
        matches!(self, Control::List(spec, _) if spec.path == PROFILE_RULES)
    }

    /// 一覧の入力欄の決まり．一覧でなければ None
    pub fn list_spec(&self) -> Option<&ListSpec> {
        match self {
            Control::List(spec, _)
            | Control::Dictionary(spec)
            | Control::Symbols(_, spec)
            | Control::SyncFields(spec) => Some(spec),
            _ => None,
        }
    }

    /// 表の列(見出し・行のどの値を出すか・幅・描き方)．macOS の RuleListEditor・KeymapPage・ExclusionsPage・CommandsPage と
    /// 同じ幅にし，打つもの(先頭の列)は等幅の文字で出す．行の値は入力欄と同じ並びで，有効の印・タグはその後ろに持つ
    pub fn table_layout(&self) -> TableLayout {
        use crate::strings::{rule_list, windows};
        use tokens::size::settings as mac;
        use ColumnWidth::{Fill, Fixed};
        let field_count = self.list_spec().map_or(0, |spec| spec.fields.len());
        let labels: Vec<&'static str> = self
            .list_spec()
            .map(|spec| spec.fields.iter().map(|field| field.label).collect())
            .unwrap_or_default();
        let label = |index: usize| labels.get(index).copied().unwrap_or("");
        let check = |source: usize| Column {
            title: rule_list::ENABLED,
            source,
            width: Fixed(mac::RULE_CHECK_COLUMN_WIDTH),
            cell: Cell::Check,
            badge: None,
        };
        let column = |source: usize, width: ColumnWidth, cell: Cell| Column {
            title: label(source),
            source,
            width,
            cell,
            badge: None,
        };
        // 決まりの一覧: 打つもの(等幅)と，あれば置き換えるもの．最後の列が残りの幅に広がる
        let rules = |count: usize| -> Vec<Column> {
            (0..count)
                .map(|index| {
                    let width = if index + 1 == count {
                        Fill
                    } else {
                        Fixed(mac::RULE_KEY_COLUMN_WIDTH)
                    };
                    let cell = if index == 0 { Cell::Mono } else { Cell::Text };
                    column(index, width, cell)
                })
                .collect()
        };
        let layout = match self {
            // 記号: 有効の印・入力(等幅)・記号とタグ(変更あり・追加)．行は入力・記号・有効の印・タグ
            Control::Symbols(..) => TableLayout {
                columns: vec![
                    check(2),
                    column(0, Fixed(mac::RULE_KEY_COLUMN_WIDTH), Cell::Mono),
                    Column {
                        badge: Some(3),
                        ..column(1, Fill, Cell::Text)
                    },
                ],
                enabled: Some(2),
            },
            // コマンド: 有効の印・読み・名前・動作・行き先(macOS の CommandsPage の列の幅)
            Control::List(spec, _) if spec.path == COMMANDS => TableLayout {
                columns: vec![
                    check(field_count),
                    column(0, Fixed(mac::COMMAND_READING_COLUMN_WIDTH), Cell::Text),
                    column(1, Fixed(mac::COMMAND_TITLE_COLUMN_WIDTH), Cell::Text),
                    column(2, Fixed(mac::COMMAND_KIND_COLUMN_WIDTH), Cell::Secondary),
                    // 行き先は長いパスや URL なので真ん中を省く(macOS の truncationMode(.middle))
                    column(3, Fill, Cell::Path),
                ],
                enabled: Some(field_count),
            },
            // 変換マクロ: 有効の印・形(等幅)・試す語と読みに当てた結果(macOS の CommandsPage)．
            // 形と結果はそれぞれの列の中で「…」で切る
            Control::List(spec, _) if spec.path == MACROS_PATH => TableLayout {
                columns: vec![
                    check(field_count),
                    column(0, Fixed(mac::RULE_KEY_COLUMN_WIDTH), Cell::Mono),
                    Column {
                        title: rule_list::RESULT,
                        ..column(field_count + 1, Fill, Cell::Secondary)
                    },
                ],
                enabled: Some(field_count),
            },
            Control::List(spec, _) if spec.has_enabled_flag() => TableLayout {
                columns: std::iter::once(check(field_count))
                    .chain(rules(field_count))
                    .collect(),
                enabled: Some(field_count),
            },
            // キー設定: 状態・キー・コマンドと，重なって使われない行などの印(macOS の KeymapPage)．
            // 行は 状態・キー・コマンド・印・使われるかの印．使われない行は薄く出す
            Control::List(spec, _) if spec.path == "keymap" => TableLayout {
                columns: vec![
                    column(0, Fixed(mac::KEYMAP_STATE_WIDTH), Cell::Text),
                    column(1, Fixed(mac::KEYMAP_KEY_WIDTH), Cell::Text),
                    column(2, Fill, Cell::Text),
                    Column {
                        title: "",
                        source: 3,
                        width: Fixed(mac::RULE_CHECK_COLUMN_WIDTH),
                        cell: Cell::Mark,
                        badge: None,
                    },
                ],
                enabled: Some(4),
            },
            // 除外設定: アプリ(真ん中を省く)・動作(行の中で選び直してすぐ書く．macOS の ExclusionsPage の Picker)
            Control::List(spec, _) if spec.path == PROFILE_RULES => TableLayout {
                columns: vec![
                    column(0, Fill, Cell::Path),
                    column(1, Fixed(mac::RULE_PROFILE_COLUMN_WIDTH), Cell::Choice),
                ],
                enabled: None,
            },
            // ユーザー辞書: 読み(等幅)・単語・品詞・コメント(macOS の RuleListEditor の種類と添え書きの列)
            Control::Dictionary(_) => TableLayout {
                columns: vec![
                    column(0, Fixed(mac::RULE_KEY_COLUMN_WIDTH), Cell::Mono),
                    column(1, Fixed(mac::RULE_VALUE_COLUMN_WIDTH), Cell::Text),
                    column(2, Fixed(mac::RULE_KIND_COLUMN_WIDTH), Cell::Secondary),
                    column(3, Fill, Cell::Secondary),
                ],
                enabled: None,
            },
            // 英語と日本語の判別ルール: 語(等幅)・前・結果．結果は行の中で選び直す(macOS の WordLanguagePage)
            Control::List(spec, _) if spec.path == "wordLanguage.rules" => TableLayout {
                columns: vec![
                    column(0, Fill, Cell::Mono),
                    column(1, Fixed(mac::RULE_KIND_COLUMN_WIDTH), Cell::Secondary),
                    column(2, Fixed(mac::RULE_PROFILE_COLUMN_WIDTH), Cell::Choice),
                ],
                enabled: None,
            },
            Control::List(..) => TableLayout {
                columns: rules(field_count),
                enabled: None,
            },
            // 項目ごとの同期: 同期するかの印・まとまり・項目(行は まとまり・項目・印)
            Control::SyncFields(_) => TableLayout {
                columns: vec![
                    Column {
                        title: crate::options::SYNC_SCOPES[0].1,
                        width: Fixed(mac::RULE_KIND_COLUMN_WIDTH),
                        ..check(2)
                    },
                    Column {
                        title: windows::SYNC_GROUP,
                        source: 0,
                        width: Fixed(mac::RULE_KEY_COLUMN_WIDTH),
                        cell: Cell::Secondary,
                        badge: None,
                    },
                    Column {
                        title: windows::SYNC_FIELD,
                        source: 1,
                        width: Fill,
                        cell: Cell::Text,
                        badge: None,
                    },
                ],
                enabled: None,
            },
            _ => TableLayout {
                columns: self
                    .table_columns()
                    .into_iter()
                    .enumerate()
                    .map(|(source, title)| Column {
                        title,
                        source,
                        width: Fill,
                        cell: Cell::Text,
                        badge: None,
                    })
                    .collect(),
                enabled: None,
            },
        };
        layout.with_titles(windows::SYMBOL_STATE)
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
            Control::List(spec, _) if spec.has_enabled_flag() => {
                fields().chain([windows::SYMBOL_STATE]).collect()
            }
            Control::SyncFields(_) => vec![windows::SYNC_FIELD, windows::SYNC_SCOPE],
            _ => fields().collect(),
        }
    }
}

/// 表の行の値で「有効」を表す印(空なら無効)．表の検索に掛からない文字にする
pub const ENABLED_CELL: &str = "\u{2713}";

/// 表の列の幅
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ColumnWidth {
    Fixed(f32),
    /// 残りの幅(Fill の列が複数あれば等しく分ける)
    Fill,
}

/// 表の列の値の描き方
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Cell {
    Text,
    /// 等幅の文字(打つもの．macOS の表の monospaced)
    Mono,
    /// 薄い文字(種類・添え書き)
    Secondary,
    /// 有効の印(値が空でなければ印を付ける．押すと有効・無効を切り替える)
    Check,
    /// 長いパスや URL．収まらなければ真ん中を「…」にする(macOS の truncationMode(.middle))
    Path,
    /// 行の中で選び直せる選択肢(値は選択肢の名前．押すと一覧を開き，選んだらすぐ書く)
    Choice,
    /// 行の問題の印(キー設定の重なり．値は KeymapMark の文字)
    Mark,
}

/// キー設定の行の印(macOS の KeymapPage の mark(for:))．表の行の値に入れる
pub mod keymap_mark {
    /// 同じキーの行があるため使われない(塗った警告の印)
    pub const HIDDEN: &str = "hidden";
    /// 一部の状態では別の行が使われる(情報の印)
    pub const PARTLY: &str = "partly";
    /// 文字を打てなくなる(線の警告の印)
    pub const BLOCKS: &str = "blocks";
}

/// 表の 1 列
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Column {
    pub title: &'static str,
    /// 行の値の何番目を出すか
    pub source: usize,
    pub width: ColumnWidth,
    pub cell: Cell,
    /// 右に寄せて小さく出すタグ(行の値の何番目か．記号の「変更あり」「追加」)
    pub badge: Option<usize>,
}

/// 表の列と，行が有効かを持つ値の番号(無効の行は薄く出す)
#[derive(Debug, Clone, PartialEq)]
pub struct TableLayout {
    pub columns: Vec<Column>,
    pub enabled: Option<usize>,
}

impl TableLayout {
    /// 名前の無い列(行の値にあって入力欄に無い列)に名前を付ける
    fn with_titles(mut self, fallback: &'static str) -> Self {
        for column in &mut self.columns {
            if column.title.is_empty() && !matches!(column.cell, Cell::Check | Cell::Mark) {
                column.title = fallback;
            }
        }
        self
    }

    /// 幅 width の表の各列の左端と幅(左の余白 padding から並べる)
    pub fn spans(&self, width: f32, padding: f32) -> Vec<(f32, f32)> {
        let fixed: f32 = self
            .columns
            .iter()
            .map(|column| match column.width {
                ColumnWidth::Fixed(width) => width,
                ColumnWidth::Fill => 0.0,
            })
            .sum();
        let fills = self
            .columns
            .iter()
            .filter(|column| column.width == ColumnWidth::Fill)
            .count()
            .max(1) as f32;
        let rest = ((width - padding - fixed) / fills).max(0.0);
        let mut left = padding;
        self.columns
            .iter()
            .map(|column| {
                let span = match column.width {
                    ColumnWidth::Fixed(width) => width,
                    ColumnWidth::Fill => rest,
                };
                let placed = (left, span);
                left += span;
                placed
            })
            .collect()
    }

    /// 行が有効か(有効かを持たない表はいつも有効)
    pub fn row_enabled(&self, cells: &[String]) -> bool {
        self.enabled
            .is_none_or(|index| cells.get(index).is_some_and(|cell| !cell.is_empty()))
    }
}

/// エンジンから読んで出す値の種類
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Info {
    /// 同期のフォルダの名前
    SyncFolder,
    /// 最後に同期した時刻
    LastSynced,
    /// パレットを開くキー(キー設定の表から引く．値はコマンドの名前)
    PaletteKeys(&'static str),
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
    CandidateGridColumns,
    LiveConversionDelay,
    LiveConversionSkipLength,
    SuggestionSkipCount,
    EnglishSkipLength,
    CorrectionDelay,
    ReviewCorrectionTimeout,
    LateCorrectionTimeout,
    ModeIndicatorDuration,
    CandidateFontSize,
    AssociationLimit,
    CustomThemeCornerRadius,
    MeaningSenseLimit,
    EmojiCandidatePosition,
    EmojiCandidateCount,
    PaletteColumns,
    PaletteRows,
    PaletteCellSize,
    PaletteFrequentRows,
}

impl RangeKind {
    pub fn range(self, catalog: &crate::catalog::Catalog) -> crate::catalog::Range {
        let ranges = &catalog.ranges;
        match self {
            RangeKind::CandidatesPerPage => ranges.candidates_per_page,
            RangeKind::CandidateGridColumns => ranges.candidate_grid_columns,
            RangeKind::LiveConversionDelay => ranges.live_conversion_delay,
            RangeKind::LiveConversionSkipLength => ranges.live_conversion_skip_length,
            RangeKind::SuggestionSkipCount => ranges.suggestion_skip_count,
            RangeKind::EnglishSkipLength => ranges.english_skip_length,
            RangeKind::CorrectionDelay => ranges.correction_delay,
            RangeKind::ReviewCorrectionTimeout => ranges.review_correction_timeout,
            RangeKind::LateCorrectionTimeout => ranges.late_correction_timeout,
            RangeKind::ModeIndicatorDuration => ranges.mode_indicator_duration,
            RangeKind::CandidateFontSize => ranges.candidate_font_size,
            RangeKind::AssociationLimit => ranges.association_limit,
            RangeKind::CustomThemeCornerRadius => ranges.custom_theme_corner_radius,
            RangeKind::MeaningSenseLimit => ranges.meaning_sense_limit,
            RangeKind::EmojiCandidatePosition => ranges.emoji_candidate_position,
            RangeKind::EmojiCandidateCount => ranges.emoji_candidate_count,
            RangeKind::PaletteColumns => ranges.palette_columns,
            RangeKind::PaletteRows => ranges.palette_rows,
            RangeKind::PaletteCellSize => ranges.palette_cell_size,
            RangeKind::PaletteFrequentRows => ranges.palette_frequent_rows,
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
            RangeKind::PaletteCellSize => catalog.palette_cell_size_step,
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
    /// 注記を危険の色(赤)で出す(同期の失敗．macOS は赤い文字)
    pub danger: bool,
    /// 値を変えたときに一緒に空(null)にする項目(テーマを選んだらカスタムテーマを外す)
    pub clears: Option<&'static str>,
    /// 名前の横にタグの形で添える，その設定で出る候補の見本(読みと候補．「びーる → 🍺」)
    pub example: Option<(&'static str, &'static str)>,
    /// 満たすときだけ見本を出す(入力方式の見本は英字入力(自動)を選んだときだけ)．None ならいつも出す
    pub example_visible: Option<Condition>,
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

    pub fn slider(title: &'static str, path: &'static str, range: RangeKind) -> Self {
        Self::new(title, path, Control::Slider(range))
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
            Control::Toggle
                | Control::Choice(_)
                | Control::ThemeFont(_)
                | Control::Stepper(_)
                | Control::Seconds(_)
                | Control::Slider(_)
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
            example: None,
            example_visible: None,
            danger: false,
        }
    }

    /// 注記を危険の色(赤)で出す
    pub fn danger(mut self) -> Self {
        self.danger = true;
        self
    }

    pub fn with_example(mut self, example: (&'static str, &'static str)) -> Self {
        self.example = Some(example);
        self
    }

    /// condition を満たすときだけ見本を出す
    pub fn example_when(mut self, condition: Condition) -> Self {
        self.example_visible = Some(condition);
        self
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

/// 作ったページ．左の一覧にはこのページだけを出す(すべてのページを作った)
pub const BUILT: &[Page] = &Page::ALL;

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
        Page::Palette => Some(palette_page()),
        Page::Commands => Some(commands()),
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
                // 英字入力(自動)を選んだときだけ，名前のすぐ後ろに打った英文が日本語になる見本を出す
                Row::choice(choice::INPUT_STYLE, "inputStyle", options::INPUT_STYLES)
                    .with_example(choice::ENGLISH_AUTO_EXAMPLE)
                    .example_when(Is("inputStyle", "englishAuto")),
                Row::toggle(
                    choice::ENGLISH_INPUT_LIVE_CONVERSION,
                    "englishInputLiveConversion",
                )
                .with_example(choice::ENGLISH_INPUT_LIVE_CONVERSION_EXAMPLE)
                .enabled_when(Is("inputStyle", "english")),
                Row::choice(
                    choice::KEYBOARD_LAYOUT,
                    "keyboardLayout",
                    options::KEYBOARD_LAYOUTS,
                ),
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
                Row::toggle(settings::NUMBER_SEPARATORS, "numberSeparators"),
                Row::toggle(settings::ALPHANUMERIC_HYPHEN, "alphanumericHyphen"),
                Row::toggle(features::KEYPAD_DIRECT, "keypadDirect"),
                Row::toggle(settings::KEYPAD_CALCULATION, "keypadCalculation"),
            ],
        ),
        Section::new(
            settings::KEYS,
            vec![
                Row::toggle(settings::PUNCTUATION_COMMITS, "punctuationCommits"),
                Row::toggle(
                    settings::QUESTION_EXCLAMATION_COMMITS,
                    "questionExclamationCommits",
                ),
                Row::toggle(settings::CYCLES_LETTER_CASE, "cyclesLetterCase"),
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
                Row::stepper(
                    more::SUGGESTION_SKIP_COUNT,
                    "suggestionSkipCount",
                    RangeKind::SuggestionSkipCount,
                )
                .enabled_when(IsNot("suggestionDisplay", "off")),
                Row::choice(
                    choice::PREDICTION_DISPLAY,
                    "predictionDisplay",
                    options::SUGGESTION_DISPLAY,
                ),
                Row::toggle(
                    choice::PREDICTION_PREFERS_HISTORY,
                    "predictionPrefersHistory",
                )
                .enabled_when(IsNot("predictionDisplay", "off")),
                Row::toggle(
                    choice::PREDICTION_FROM_CORRECTION,
                    "predictionFromCorrection",
                )
                .enabled_when(IsNot("predictionDisplay", "off")),
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
            choice::HIDDEN_PREDICTIONS,
            vec![Row::list(
                ListSpec {
                    path: "hiddenPredictions",
                    fields: HIDDEN_PREDICTION_FIELDS,
                    empty: choice::HIDDEN_PREDICTIONS_EMPTY,
                    invalid: crate::strings::Text::Limited(
                        crate::strings::LimitedText::HiddenPrediction,
                    ),
                    lowercase: false,
                    exclusive_with: None,
                },
                LimitKind::HiddenPredictions,
            )],
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
                Row::stepper(
                    more::GRID_COLUMNS,
                    "candidateGridColumns",
                    RangeKind::CandidateGridColumns,
                ),
                Row::toggle(more::EXPANDS_GRID_ON_PAGING, "expandsGridOnPaging"),
                Row::toggle(
                    more::CONTEXTUAL_SEGMENT_CANDIDATES,
                    "contextualSegmentCandidates",
                ),
                Row::toggle(more::LIST_SEGMENT_ALTERNATIVES, "listSegmentAlternatives")
                    .with_example(more::LIST_SEGMENT_ALTERNATIVES_EXAMPLE),
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
                Row::stepper(
                    more::ENGLISH_SKIP_LENGTH,
                    "englishSkipLength",
                    RangeKind::EnglishSkipLength,
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
            // 一覧についての 1 行は一覧のすぐ下に，読み込めるファイルの見本は取り込むボタンの下に置く
            rows: vec![
                Row::new("", "", Control::Dictionaries(DictionaryList::Association)),
                Row::note(association::NOTE),
            ],
            footer: Some(association::FILE_EXAMPLE),
            footer_variants: &[],
        },
        Section::new(
            settings::SPECIAL_CONVERSION,
            vec![
                Row::toggle(features::CALCULATION, "calculation"),
                Row::toggle(features::POSTAL_CODE, "postalCodeConversion"),
                Row::toggle(features::HANDWRITING, "handwriting"),
                Row::toggle(settings::DATE_CONVERSION, "dateConversion"),
                Row::toggle(settings::MISUSE_NOTES, "misuseNotes"),
                Row::toggle(settings::PROOFREADING, "proofreading"),
                Row::toggle(settings::SYMBOL_CONVERSION, "symbolConversion"),
                Row::toggle(settings::LATEX_CONVERSION, "latexConversion"),
            ],
        ),
        Section::new(
            settings::EMOJI_SECTION,
            vec![
                Row::toggle(settings::EMOJI_CONVERSION, "emojiConversion")
                    .with_example(settings::EMOJI_CONVERSION_EXAMPLE),
                Row::toggle(settings::EMOJI_WORD_CONVERSION, "emojiWordConversion")
                    .with_example(settings::EMOJI_WORD_CONVERSION_EXAMPLE),
                Row::stepper(
                    settings::EMOJI_CANDIDATE_POSITION,
                    "emojiCandidatePosition",
                    RangeKind::EmojiCandidatePosition,
                )
                .enabled_when(EMOJI_ON),
                Row::stepper(
                    settings::EMOJI_CANDIDATE_COUNT,
                    "emojiCandidateCount",
                    RangeKind::EmojiCandidateCount,
                )
                .enabled_when(EMOJI_ON),
                Row::toggle(settings::SHOWS_EMOJI_NAMES, "showsEmojiNames").enabled_when(EMOJI_ON),
                Row::new(more::PREVIEW, "", Control::EmojiPreview).visible_when(EMOJI_ON),
            ],
        ),
        Section::new(
            settings::NUMBER_FORMS,
            vec![
                Row::toggle(settings::NUMBER_FORM_CONVERSION, "numberFormConversion"),
                Row::toggle(settings::NUMBER_FORM_CIRCLED, "numberFormCircled")
                    .enabled_when(On("numberFormConversion")),
                Row::toggle(
                    settings::NUMBER_FORM_PARENTHESIZED,
                    "numberFormParenthesized",
                )
                .enabled_when(On("numberFormConversion")),
                Row::toggle(settings::NUMBER_FORM_KANJI, "numberFormKanji")
                    .enabled_when(On("numberFormConversion")),
                Row::toggle(settings::NUMBER_FORM_ROMAN, "numberFormRoman")
                    .enabled_when(On("numberFormConversion")),
            ],
        ),
        Section::new(
            settings::MEANING,
            vec![
                Row::toggle(settings::HOMOPHONE_NOTES, "homophoneNotes"),
                Row::choice(
                    settings::MEANING_PLACEMENT,
                    "meaningPlacement",
                    options::MEANING_PLACEMENTS,
                )
                .enabled_when(On("homophoneNotes")),
                Row::stepper(
                    settings::MEANING_SENSE_LIMIT,
                    "meaningSenseLimit",
                    RangeKind::MeaningSenseLimit,
                )
                .enabled_when(On("homophoneNotes")),
                Row::toggle(settings::SHOWS_PART_OF_SPEECH, "showsPartOfSpeech")
                    .enabled_when(On("homophoneNotes")),
                Row::toggle(settings::SHOWS_USAGE_EXAMPLES, "showsUsageExamples")
                    .enabled_when(On("homophoneNotes")),
                Row::toggle(settings::SHOWS_HOMOPHONES, "showsHomophones")
                    .enabled_when(On("homophoneNotes")),
            ],
        ),
        Section::new(
            settings::ZENZAI_MODEL,
            vec![
                Row::choice(
                    settings::ZENZAI_MODEL,
                    "zenzaiModel",
                    options::ZENZAI_MODELS,
                ),
                Row::note(settings::ZENZAI_COMBINED_NOTE)
                    .visible_when(Is("zenzaiModel", "combined")),
            ],
        ),
        Section::untitled(vec![Row::toggle(
            settings::CANDIDATE_RERANKING,
            "candidateReranking",
        )]),
        Section::untitled(vec![Row::choice(
            settings::JINEN_MODEL,
            "jinenModel",
            options::JINEN_MODELS,
        )]),
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
const HIDDEN_PREDICTION_FIELDS: &[Field] = &[Field::text(choice::HIDDEN_PREDICTION_PLACEHOLDER)];
const ROMAJI_FIELDS: &[Field] = &[
    Field::named("keys", settings::ROMAJI_KEYS, true),
    Field::named("kana", settings::ROMAJI_KANA, false),
];
const WORD_FIELDS: &[Field] = &[Field::text(features::WORD_PLACEHOLDER)];
const ENGLISH_TERM_FIELDS: &[Field] =
    &[Field::text(extras::ENGLISH_TERM_PLACEHOLDER).prompt(extras::ENGLISH_TERM_PROMPT)];
const LANGUAGE_RULE_FIELDS: &[Field] = &[
    Field::named("word", features::LANGUAGE_RULE_WORD, true),
    // macOS の WordLanguagePage と同じく，新しい決まりは「前: 日本語 → 日本語」から始める
    Field::choice(
        "context",
        features::LANGUAGE_RULE_CONTEXT,
        options::WORD_CONTEXTS,
        true,
    )
    .default_choice(2),
    Field::choice(
        "language",
        features::LANGUAGE_RULE_RESULT,
        options::WORD_LANGUAGES,
        false,
    )
    .default_choice(1),
];

/// 日本語のタイプミスを直すとき．修正の対象は，変換のページの「タイプミスの修正」で選んだ範囲の中でだけ効く
/// 文節全体か文節の中の語のどちらかを絵文字にする設定のとき(位置・数・名前の表示は両方に共通)
const EMOJI_ON: Condition = Condition::Any(&[
    Condition::On("emojiConversion"),
    Condition::On("emojiWordConversion"),
]);

const CORRECTS_JAPANESE: Condition = Condition::All(&[
    Condition::Is("typoCorrection", "standard"),
    Condition::On("correction.japanese"),
]);

/// 補正のページ(macOS の CorrectionPage)
fn correction() -> Vec<Section> {
    use Condition::*;
    vec![
        Section::new(
            features::CORRECTION_KINDS,
            vec![
                // 種類を選べるかは「タイプミスの修正」(変換のページと同じ設定)で決まるので，ここでも切り替えられるようにする
                Row::choice(
                    choice::TYPO_CORRECTION,
                    "typoCorrection",
                    options::TYPO_CORRECTION,
                ),
                Row::toggle(features::CORRECTS_ENGLISH, "correction.english")
                    .enabled_when(IsNot("typoCorrection", "off")),
                Row::toggle(features::CORRECTS_JAPANESE, "correction.japanese")
                    .enabled_when(Is("typoCorrection", "standard")),
                Row::toggle(features::CORRECTS_REPEATED_KEYS, "correction.repeatedKeys")
                    .enabled_when(CORRECTS_JAPANESE),
                Row::toggle(features::MISREADINGS, "misreadings"),
                Row::toggle(extras::LOOSE_READINGS, "looseReadings")
                    .with_example(extras::LOOSE_READINGS_EXAMPLE),
                Row::toggle(extras::PHONETIC_SPELLING, "phoneticSpelling")
                    .with_example(extras::PHONETIC_SPELLING_EXAMPLE),
            ],
        ),
        Section::untitled(vec![Row::toggle(extras::HAND_SHIFT, "handShiftCorrection")
            .with_example(extras::HAND_SHIFT_EXAMPLE)
            .enabled_when(CORRECTS_JAPANESE)]),
        Section::new(
            features::RULES,
            files_inline(
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
            files_inline(
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
                Row::toggle(features::USES_CONTEXT, "wordLanguage.usesContext")
                    .with_example(features::USES_CONTEXT_EXAMPLE),
                Row::toggle(features::AVOIDS_OFFENSIVE, "wordLanguage.avoidsOffensive"),
            ],
            footer: None,
            footer_variants: &[],
        },
        Section::new(
            features::TRY_LANGUAGE,
            vec![Row::new("", "", Control::Preview(TryKind::Language))],
        ),
        Section::new(
            features::ENGLISH_WORDS,
            files_inline(
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
            files_inline(
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
            footer: None,
            footer_variants: &[],
        },
        Section {
            title: Some(extras::ENGLISH_TERMS_SECTION),
            rows: vec![
                Row::toggle(extras::ENGLISH_TERM_CANDIDATES, "englishTermCandidates")
                    .with_example(extras::ENGLISH_TERM_CANDIDATES_EXAMPLE),
            ],
            footer: None,
            footer_variants: &[],
        },
        Section {
            title: Some(extras::ENGLISH_TERMS),
            rows: files_inline(
                Row::list(
                    ListSpec {
                        path: "englishTerms",
                        fields: ENGLISH_TERM_FIELDS,
                        empty: extras::ENGLISH_TERMS_EMPTY,
                        invalid: crate::strings::Text::Limited(
                            crate::strings::LimitedText::EnglishTerm,
                        ),
                        lowercase: false,
                        exclusive_with: None,
                    },
                    LimitKind::EnglishTerms,
                )
                .enabled_when(Condition::On("englishTermCandidates")),
                RuleList::EnglishTerms,
            ),
            footer: None,
            footer_variants: &[],
        },
    ]
}

const KEYMAP_FIELDS: &[Field] = &[
    Field::choice("state", keys::STATE, keys::STATES, false),
    Field::key_notation("key", keys::KEY, false).prompt(crate::strings::windows::KEY_EXAMPLE),
    Field::choice("command", keys::COMMAND, keys::COMMANDS, false),
];

/// キー設定のページ(macOS の KeymapPage)．表の行は上から順に並び，同じキーの行は下の行を使う
fn keymap() -> Vec<Section> {
    vec![
        // 既定に戻すボタンは表の下の帯に置く(macOS の KeymapPage の下の右)
        Section::untitled(vec![Row::new(keys::PRESET_MENU, "", Control::Preset)]),
        // キーの無い確定・取り消しがあれば，知らせの下に標準の表のキーを足すボタンを出す
        Section::untitled(vec![
            Row::new("", "", Control::KeymapReport),
            Row::action(keys::ADD_STANDARD_KEYS, Action::AddMissingKeys)
                .visible_when(Condition::On(KEYMAP_MISSING)),
        ]),
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
            // 選んだコマンドの説明だけを出す(キーの欄は例の値で書き方を見せる)
            footer: Some(""),
            footer_variants: keys::COMMAND_HELP,
        },
    ]
}

const APP_FIELDS: &[Field] = &[
    // 表の見出しは macOS と同じ「アプリ」．Windows は実行ファイルの名前で見分けるので，打つ欄はそれを案内する
    Field::named("applicationPrefix", more::APPS, true)
        .prompt(crate::strings::windows::APP_EXECUTABLE_PROMPT),
    // 同じアプリに入力の扱いとモードの扱い(IME をオフなど)を 1 つずつ付けられるよう，動作も行を見分ける欄にする
    Field::choice("profile", more::BEHAVIOR, options::APP_PROFILES, true),
];

/// 除外設定の一覧の項目
pub const PROFILE_RULES: &str = "profileRules";
/// コマンドの一覧の項目
pub const COMMANDS: &str = "commands";

/// 除外設定の CSV を読み込む・書き出すボタン
const EXCLUSION_FILES: &[(&str, Action)] = &[
    (more::IMPORT_CSV, Action::File(FileTask::ImportProfileRules)),
    (more::EXPORT_CSV, Action::File(FileTask::ExportProfileRules)),
];

/// 除外設定のページ(macOS の ExclusionsPage)．アプリは実行ファイルの名前(小文字)で見分ける
fn apps() -> Vec<Section> {
    vec![
        Section {
            title: None,
            rows: vec![Row::list(
                ListSpec {
                    path: PROFILE_RULES,
                    fields: APP_FIELDS,
                    empty: more::EXCLUSIONS_EMPTY,
                    invalid: crate::strings::Text::Fixed(crate::strings::windows::INVALID_APP),
                    lowercase: true,
                    exclusive_with: None,
                },
                LimitKind::ProfileRules,
            )],
            footer: Some(crate::strings::windows::EXCLUSIONS_ORDER),
            footer_variants: &[],
        },
        // CSV の読み込みと書き出しは一覧の下の別のカードに置く(macOS の ExclusionsPage)
        Section::untitled(vec![Row::new("", "", Control::Buttons(EXCLUSION_FILES))]),
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
    Field::choice(
        "wordClass",
        settings::WORD_CLASS,
        options::WORD_CLASSES,
        false,
    ),
    Field::named("comment", settings::COMMENT, false)
        .optional()
        .prompt(settings::COMMENT_PROMPT),
];

/// ユーザー辞書の注記に入れ替えて出す文(品詞の欄で選んでいる値と文)
const DICTIONARY_NOTES: &[(&str, &str)] = &[("abbreviation", settings::ABBREVIATION_NOTE)];

const COMMAND_FIELDS: &[Field] = &[
    // 同じ読みのコマンドをいくつも足せる(macOS と同じ)．書き換えるコマンドは id で見分ける
    Field::named("reading", extras::COMMAND_READING, false),
    Field::named("title", extras::COMMAND_TITLE, false),
    Field::choice("kind", extras::COMMAND_KIND, options::COMMAND_KINDS, false),
    Field::named("target", extras::COMMAND_TARGET, false),
];

const MACRO_FIELDS: &[Field] = &[Field::named("pattern", extras::MACRO_PATTERN, true)];

/// 変換マクロの一覧の項目(書いている途中の形を試す欄に渡すため，画面からも探す)
pub const MACROS_PATH: &str = "macros";

/// コマンドと変換マクロのページ(macOS の CommandsPage)．コマンドの行き先は実行ファイル・ファイルのパスか URL を打つ
fn commands() -> Vec<Section> {
    vec![
        Section {
            title: Some(extras::COMMANDS_SECTION),
            rows: vec![
                Row::toggle(extras::LAUNCHER_COMMANDS, "launcherCommands"),
                Row::list(
                    ListSpec {
                        path: COMMANDS,
                        fields: COMMAND_FIELDS,
                        empty: extras::COMMANDS_EMPTY,
                        invalid: crate::strings::Text::Fixed(extras::INVALID_COMMAND),
                        lowercase: false,
                        exclusive_with: None,
                    },
                    LimitKind::Commands,
                ),
            ],
            footer: Some(crate::strings::windows::COMMANDS_STORED_LOCALLY),
            footer_variants: &[],
        },
        Section {
            title: Some(extras::MACROS_SECTION),
            rows: vec![
                Row::toggle(extras::CONVERSION_MACROS, "conversionMacros"),
                Row::toggle(extras::MACRO_SKIPS_SAME_READING, "macroSkipsSameReading"),
                // 試す語と読み．チップの {text} と {reading} の値，形の欄の下の結果，一覧の結果の列，下の「試す」に使う
                Row::new("", "", Control::Preview(TryKind::Macros)),
                Row::list(
                    ListSpec {
                        path: MACROS_PATH,
                        fields: MACRO_FIELDS,
                        empty: extras::MACROS_EMPTY,
                        invalid: crate::strings::Text::Fixed(extras::INVALID_MACRO),
                        lowercase: false,
                        exclusive_with: None,
                    },
                    LimitKind::Macros,
                ),
            ],
            footer: None,
            footer_variants: &[],
        },
        Section {
            title: Some(extras::TRY_MACROS),
            rows: vec![Row::new("", "", Control::PreviewChips(TryKind::Macros))],
            footer: None,
            footer_variants: &[],
        },
    ]
}

/// ユーザー辞書のページ(macOS の DictionaryPage)．登録した単語(同じ読みに別の単語を登録できる)と取り込んだ辞書を切り替えて出す
fn dictionary() -> Vec<Section> {
    use Condition::*;
    let imported = || Is(DICTIONARY_TAB, DICTIONARY_TAB_IMPORTED);
    let terms = || Is(DICTIONARY_TAB, DICTIONARY_TAB_TERMS);
    let words = || {
        All(&[
            IsNot(DICTIONARY_TAB, DICTIONARY_TAB_IMPORTED),
            IsNot(DICTIONARY_TAB, DICTIONARY_TAB_TERMS),
        ])
    };
    vec![
        Section::untitled(vec![Row::new(
            "",
            DICTIONARY_TAB,
            Control::Segmented(DICTIONARY_TABS),
        )]),
        Section {
            title: None,
            rows: vec![
                Row::toggle(extras::DYNAMIC_DICTIONARY, "dynamicDictionary").visible_when(words())
            ],
            footer: None,
            footer_variants: &[],
        },
        Section {
            title: None,
            rows: vec![Row::new(
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
            )
            .visible_when(words())],
            // 注記は短縮よみを選んだときだけ出す(ふだんは空)
            footer: Some(""),
            footer_variants: DICTIONARY_NOTES,
        },
        Section {
            title: None,
            rows: vec![
                Row::new("", "", Control::Dictionaries(DictionaryList::Imported))
                    .visible_when(imported()),
            ],
            footer: Some(dictionaries::NOTE),
            footer_variants: &[],
        },
        // 専門用語の辞書(R-29)．使うかと，分野ごとのオン・オフ(macOS の TermDictionaryView)
        Section {
            title: None,
            rows: std::iter::once(Row::toggle(
                crate::strings::terms::ENABLED,
                "termDictionary",
            ))
            .chain(std::iter::once(Row::note(crate::strings::terms::FIELDS)))
            .chain(
                TERM_FIELD_PATHS
                    .iter()
                    .zip(crate::strings::terms::FIELD_NAMES)
                    .map(|(path, (_, name))| {
                        Row::toggle(name, path).enabled_when(On("termDictionary"))
                    }),
            )
            .map(|row| row.visible_when(terms()))
            .collect(),
            footer: None,
            footer_variants: &[],
        },
    ]
}

/// 専門用語の辞書の分野ごとの設定の項目(strings::terms::FIELD_NAMES と同じ並び)
const TERM_FIELD_PATHS: &[&str] = &[
    "termFields.computing",
    "termFields.medicine",
    "termFields.biology",
    "termFields.chemistry",
    "termFields.physics",
    "termFields.mathematics",
    "termFields.earth",
    "termFields.engineering",
    "termFields.architecture",
    "termFields.law",
    "termFields.economics",
    "termFields.business",
    "termFields.linguistics",
    "termFields.philosophy",
    "termFields.religion",
    "termFields.music",
    "termFields.design",
    "termFields.food",
    "termFields.sports",
    "termFields.games",
    "termFields.military",
    "termFields.agriculture",
    "termFields.performingArts",
    "termFields.history",
];

/// キーの無い確定・取り消しがあるか(画面の中だけの値．キー設定の表の問題をエンジンに確かめたときに入れる)
pub const KEYMAP_MISSING: &str = "page.keymapMissing";

/// ユーザー辞書のページで出している一覧(画面の中だけの値．設定のファイルには書かない)
pub const DICTIONARY_TAB: &str = "page.dictionaryTab";
pub const DICTIONARY_TAB_IMPORTED: &str = "imported";
/// 登録した単語の一覧(単語の登録で開くときに出す)
pub const DICTIONARY_TAB_WORDS: &str = "words";
pub const DICTIONARY_TAB_TERMS: &str = "terms";
const DICTIONARY_TABS: &[Choice] = &[
    (DICTIONARY_TAB_WORDS, dictionaries::USER_WORDS),
    (DICTIONARY_TAB_IMPORTED, dictionaries::IMPORTED),
    (DICTIONARY_TAB_TERMS, dictionaries::TERMS),
];

/// 画面の中だけの値(開いている一覧など)の道筋か
pub fn is_view_path(path: &str) -> bool {
    path.starts_with("page.")
}

/// 絵文字と記号のパレットのページ(R-26．macOS の PalettePage)．見本は設定のとおりの列数・行数・マスの大きさで描く
fn palette_page() -> Vec<Section> {
    use Condition::*;
    vec![
        Section::untitled(vec![Row::new(more::PREVIEW, "", Control::PalettePreview)]),
        Section::new(
            palette::BEHAVIOR,
            vec![
                Row::toggle(palette::ENABLED, "palette"),
                Row::new(
                    palette::EMOJI_KEY,
                    "",
                    Control::Info(Info::PaletteKeys("emojiPalette")),
                )
                .enabled_when(On("palette")),
                Row::new(
                    palette::SYMBOL_KEY,
                    "",
                    Control::Info(Info::PaletteKeys("symbolPalette")),
                )
                .enabled_when(On("palette")),
                Row::new(
                    palette::KAOMOJI_KEY,
                    "",
                    Control::Info(Info::PaletteKeys("kaomojiPalette")),
                )
                .enabled_when(On("palette")),
                Row::action(palette::OPEN_KEYS, Action::OpenKeys).enabled_when(On("palette")),
                Row::toggle(palette::CLOSES_AFTER_INSERT, "paletteClosesAfterInsert")
                    .enabled_when(On("palette")),
                Row::toggle(palette::RECORDS_HISTORY, "paletteRecordsHistory")
                    .enabled_when(On("palette")),
                Row::action(palette::CLEAR_HISTORY, Action::ResetPaletteHistory)
                    .enabled_when(On("palette")),
            ],
        ),
        Section {
            title: Some(palette::LOOK),
            rows: vec![
                Row::stepper(
                    palette::COLUMNS,
                    "paletteColumns",
                    RangeKind::PaletteColumns,
                ),
                Row::stepper(palette::ROWS, "paletteRows", RangeKind::PaletteRows),
                Row::slider(
                    palette::CELL_SIZE,
                    "paletteCellSize",
                    RangeKind::PaletteCellSize,
                ),
                Row::stepper(
                    palette::FREQUENT_ROWS,
                    "paletteFrequentRows",
                    RangeKind::PaletteFrequentRows,
                )
                .enabled_when(On("paletteRecordsHistory")),
                Row::toggle(palette::SHOWS_PREVIEW, "paletteShowsPreview"),
                Row::toggle(palette::SHOWS_UNICODE_NAME, "paletteShowsUnicodeName")
                    .enabled_when(On("paletteShowsPreview")),
                Row::toggle(palette::SHOWS_READINGS, "paletteShowsReadings")
                    .enabled_when(On("paletteShowsPreview")),
                Row::toggle(palette::SHOWS_SHORTCODES, "paletteShowsShortcodes")
                    .enabled_when(On("paletteShowsPreview")),
                Row::toggle(palette::SHOWS_CODE_POINTS, "paletteShowsCodePoints")
                    .enabled_when(On("paletteShowsPreview")),
            ],
            footer: None,
            footer_variants: &[],
        },
    ]
}

/// 記号のページ(macOS の SymbolsPage)．既定の決まりは変えず，変えた分だけを設定に重ねる．
/// ファイルを読み込む・書き出すボタンは一覧の表の下の帯に置く(pages::list_files)
fn symbols() -> Vec<Section> {
    let section = |title, kind, fields, invalid, _file: RuleList| {
        let rows = vec![Row::new(
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

/// 一覧の行．ファイルを読み込む・書き出すボタンは一覧の表の下の帯に置く(pages::list_files．macOS の RuleListEditor)
fn files_inline(list: Row, _file: RuleList) -> Vec<Row> {
    vec![list]
}

/// ローマ字のページ(macOS の RomajiPage)．標準の表に重ねる綴り
fn romaji() -> Vec<Section> {
    vec![Section::untitled(files_inline(
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

/// カスタムテーマの一覧の下のボタン(macOS の AppearancePage の HStack)
const THEME_BUTTONS: &[(&str, Action)] = &[
    (more::CREATE_THEME, Action::CreateTheme),
    (more::DUPLICATE, Action::DuplicateCurrentTheme),
];

/// カスタムテーマの行(Control::CustomTheme(0))を上限 limit の数だけ並べる．出すのは今あるテーマの数だけ(画面の側で決める)
pub fn with_custom_theme_rows(mut sections: Vec<Section>, limit: usize) -> Vec<Section> {
    for section in &mut sections {
        let Some(position) = section
            .rows
            .iter()
            .position(|row| row.control == Control::CustomTheme(0))
        else {
            continue;
        };
        let template = section.rows[position].clone();
        let rows = (1..limit).map(|index| Row {
            control: Control::CustomTheme(index),
            ..template.clone()
        });
        section.rows.splice(position + 1..position + 1, rows);
    }
    sections
}

/// 外観のページ(macOS の AppearancePage)．既成のテーマを選ぶとカスタムテーマを外す(macOS の selectTheme と同じ)．
/// カスタムテーマは行の右のボタンや一覧の下のボタンで編集の画面(theme_editor)を開いて作る・直す
fn appearance() -> Vec<Section> {
    use crate::themes;
    use Condition::*;
    let theme_rows = options::THEMES
        .iter()
        .map(|(value, name)| {
            Row::new(name, "theme", Control::ThemeOption(value)).clearing("customThemeID")
        })
        .collect();
    vec![
        Section::untitled(vec![Row::new(more::PREVIEW, "", Control::ThemePreview)]),
        Section::new(more::THEME, theme_rows),
        Section::new(
            more::CUSTOM_THEMES,
            vec![
                Row::new(more::NO_CUSTOM_THEMES, "", Control::Placeholder)
                    .visible_when(On(themes::EMPTY)),
                Row::new("", "", Control::CustomTheme(0)),
                // 上限まで作ったら作れない(macOS と同じくボタンを使えなくする)
                Row::new("", "", Control::Buttons(THEME_BUTTONS)).enabled_when(On(themes::ROOM)),
            ],
        ),
        Section::new(
            more::FONT,
            vec![Row::slider(
                settings::FONT_SIZE_NAME,
                "candidateFontSize",
                RangeKind::CandidateFontSize,
            )],
        ),
    ]
}

/// カスタムテーマを編集する画面(macOS の CustomThemeEditor)．名前・読みやすさ・色・形を並べる．
/// 値は編集している下書きの「customTheme.」の道筋(crate::themes)で，「保存」を押すまで設定のファイルに書かない．
/// 見本は画面の上に留め，ボタン(複製・キャンセル・保存)は下に留めて描く(app::window)
pub fn theme_editor() -> Vec<Section> {
    use crate::themes;
    let issues = (0..themes::CONTRAST_PAIRS)
        .map(|index| Row::new("", "", Control::ThemeIssue(index)))
        .collect();
    let colors = themes::COLORS
        .iter()
        .map(|(path, title)| Row::new(title, path, Control::Color))
        .collect();
    vec![
        Section::untitled(vec![Row::new(
            more::THEME_NAME,
            themes::NAME,
            Control::TextField,
        )]),
        // 読みにくい組み合わせが無ければ，見出しごと出さない(macOS と同じ)
        Section::new(more::READABILITY, issues),
        Section::new(more::COLORS, colors),
        Section::new(
            more::SHAPE,
            vec![
                Row::slider(
                    more::CORNER_RADIUS,
                    themes::CORNER_RADIUS,
                    RangeKind::CustomThemeCornerRadius,
                ),
                Row::choice(
                    more::BRANCH_STYLE,
                    themes::BRANCH_STYLE,
                    options::BRANCH_STYLES,
                ),
                Row::new(
                    more::FONT,
                    themes::FONT_NAME,
                    Control::ThemeFont(FontPart::Family),
                ),
                Row::new(
                    more::FONT_STYLE,
                    themes::FONT_NAME,
                    Control::ThemeFont(FontPart::Style),
                ),
            ],
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
    scopes.push(
        Row::new(
            sync::ITEMS,
            crate::sync::HAS_FIELDS,
            Control::SyncFields(ListSpec {
                path: "",
                fields: &[],
                empty: "",
                invalid: crate::strings::Text::Fixed(""),
                lowercase: false,
                exclusive_with: None,
            }),
        )
        .visible_when(On(crate::sync::HAS_FIELDS)),
    );
    vec![
        Section {
            title: None,
            rows: vec![
                Row::toggle(sync::ENABLED, crate::sync::ENABLED)
                    .enabled_when(IsNot(crate::sync::FOLDER, "")),
                Row::new(
                    sync::FOLDER,
                    "",
                    Control::InfoAction(
                        Info::SyncFolder,
                        Action::ChooseSyncFolder,
                        sync::CHOOSE_FOLDER,
                    ),
                ),
                Row::new(
                    sync::LAST_SYNCED,
                    "",
                    Control::InfoAction(Info::LastSynced, Action::SyncNow, sync::SYNC_NOW),
                )
                .enabled_when(On(crate::sync::ENABLED)),
                // 同期できなかった知らせは赤い文字で出す(macOS の SyncPage)
                Row::note(sync::FAILED)
                    .danger()
                    .visible_when(Is(crate::sync::PROBLEM, crate::sync::PROBLEM_FAILED)),
                Row::note(sync::UNREADABLE)
                    .danger()
                    .visible_when(Is(crate::sync::PROBLEM, crate::sync::PROBLEM_UNREADABLE)),
            ],
            footer: None,
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

const BACKUP_BUTTONS: &[(&str, Action)] = &[
    (
        more::EXPORT_SETTINGS,
        Action::File(FileTask::ExportSettings),
    ),
    (
        more::IMPORT_SETTINGS,
        Action::File(FileTask::ImportSettings),
    ),
];

/// バックアップのページ(macOS の BackupPage)．設定のファイルを開くボタンも置く(画面に無い項目を直すため)
fn backup() -> Vec<Section> {
    vec![
        Section {
            title: None,
            rows: vec![Row::new("", "", Control::Buttons(BACKUP_BUTTONS))],
            footer: None,
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

/// 情報のページ(macOS の AboutPage)．謝辞は配布物に入れた THIRD_PARTY_NOTICES.md を項目ごとのカードにする
fn about() -> Vec<Section> {
    let notices = crate::notices::installed();
    let rows = if notices.is_empty() {
        // 番号の無い項目は名前(読めない知らせ)だけを出す
        vec![Row::new(
            more::NOTICES_MISSING,
            "",
            Control::Acknowledgement(usize::MAX),
        )]
    } else {
        notices
            .iter()
            .enumerate()
            .map(|(index, item)| Row::new(item.name.as_str(), "", Control::Acknowledgement(index)))
            .collect()
    };
    vec![
        Section::untitled(vec![
            Row::new(more::VERSION, "", Control::Version),
            Row::new(
                crate::strings::wizard::REDO_LABEL,
                "",
                Control::LabeledAction(Action::OpenSetup, crate::strings::wizard::REDO),
            ),
        ]),
        Section {
            title: Some(more::ACKNOWLEDGEMENTS),
            rows,
            footer: None,
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
    fn check(
        condition: Condition,
        text: &dyn Fn(&str) -> String,
        on: &dyn Fn(&str) -> bool,
    ) -> bool {
        match condition {
            Condition::Is(path, value) => text(path) == value,
            Condition::IsNot(path, value) => text(path) != value,
            Condition::On(path) => on(path),
            Condition::All(conditions) => conditions
                .iter()
                .all(|condition| check(*condition, text, on)),
            Condition::Any(conditions) => conditions
                .iter()
                .any(|condition| check(*condition, text, on)),
        }
    }
    check(condition, &text, &on)
}

#[cfg(test)]
mod tests {
    #[test]
    fn 専門用語の辞書の分野の項目は名前と同じ並び() {
        assert_eq!(
            TERM_FIELD_PATHS.len(),
            crate::strings::terms::FIELD_NAMES.len()
        );
        for (path, (id, _)) in TERM_FIELD_PATHS
            .iter()
            .zip(crate::strings::terms::FIELD_NAMES)
        {
            assert_eq!(*path, format!("termFields.{id}"));
        }
    }

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
        let both = Condition::All(&[
            Condition::Is("inputStyle", "english"),
            Condition::On("liveConversion"),
        ]);
        assert!(!holds(both, text, on));
        assert!(holds(both, text, |_: &str| true));
    }

    #[test]
    fn 修正の対象はタイプミスの修正で選んだ範囲でだけ使える() {
        let rows: Vec<Row> = sections(Page::Correction)
            .unwrap()
            .into_iter()
            .flat_map(|section| section.rows)
            .collect();
        let enabled = |path: &str, level: &str, japanese: bool| {
            let row = rows.iter().find(|row| row.path == path).unwrap();
            row.enabled.is_none_or(|condition| {
                holds(
                    condition,
                    |path| {
                        if path == "typoCorrection" {
                            level.to_string()
                        } else {
                            String::new()
                        }
                    },
                    |path| path != "correction.japanese" || japanese,
                )
            })
        };
        assert!(enabled("correction.english", "conservative", true));
        assert!(!enabled("correction.english", "off", true));
        assert!(!enabled("correction.japanese", "conservative", true));
        assert!(enabled("correction.repeatedKeys", "standard", true));
        assert!(!enabled("correction.repeatedKeys", "standard", false));
        assert!(!enabled("handShiftCorrection", "conservative", true));
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
    fn 変換のページで入力中の予測と入力中の候補を表示しない件数を選べる() {
        let catalog = crate::catalog::Catalog::load().unwrap();
        let rows: Vec<_> = sections(Page::Conversion)
            .unwrap()
            .into_iter()
            .flat_map(|section| section.rows)
            .collect();
        let prediction = rows
            .iter()
            .find(|row| row.path == "predictionDisplay")
            .unwrap();
        assert!(
            matches!(prediction.control, Control::Choice(choices) if choices == options::SUGGESTION_DISPLAY)
        );
        let skip = rows
            .iter()
            .find(|row| row.path == "suggestionSkipCount")
            .unwrap();
        assert!(matches!(
            skip.control,
            Control::Stepper(RangeKind::SuggestionSkipCount)
        ));
        let range = RangeKind::SuggestionSkipCount.range(&catalog);
        assert_eq!((range.lower(), range.upper()), (0.0, 4.0));
        assert_eq!(crate::strings::more::skip_count(0.0), "オフ");
        assert_eq!(crate::strings::more::skip_count(2.0), "2 件以下");
    }

    #[test]
    fn 絵文字と記号のページを左の一覧に出す() {
        let found = sidebar(BUILT, "");
        assert_eq!(
            found[1],
            (
                Group::Dictionary,
                vec![
                    Page::Dictionary,
                    Page::Symbols,
                    Page::Palette,
                    Page::Commands
                ]
            )
        );
        assert_eq!(
            sidebar(BUILT, "記号のパレットを開くキー")[0].1,
            vec![Page::Palette]
        );
        assert!(Page::Conversion.matches("連想辞書"));
    }

    #[test]
    fn パレットのページは開くキーとマスの大きさのスライダーを出す() {
        let rows: Vec<Row> = sections(Page::Palette)
            .unwrap()
            .into_iter()
            .flat_map(|section| section.rows)
            .collect();
        assert!(rows
            .iter()
            .any(|row| row.control == Control::Info(Info::PaletteKeys("emojiPalette"))));
        assert!(rows
            .iter()
            .any(|row| row.control == Control::Slider(RangeKind::PaletteCellSize)));
        // 注記は名前の無い行の説明にしない(幅の無い説明にならない)
        assert!(!rows.iter().any(|row| row.control == Control::Note));
    }

    #[test]
    fn 消す操作は危険の色にする() {
        assert!(Action::ResetLearning.is_destructive());
        assert!(Action::RestoreDefaults.is_destructive());
        assert!(!Action::OpenSettingsFile.is_destructive());
    }

    #[test]
    fn 変換マクロの一覧は有効と形と結果の列に分ける() {
        let macros = commands()
            .into_iter()
            .flat_map(|section| section.rows)
            .find(|row| matches!(&row.control, Control::List(spec, _) if spec.path == MACROS_PATH))
            .unwrap();
        let layout = macros.control.table_layout();
        let titles: Vec<_> = layout.columns.iter().map(|column| column.title).collect();
        assert_eq!(
            titles,
            vec![
                crate::strings::rule_list::ENABLED,
                extras::MACRO_PATTERN,
                crate::strings::rule_list::RESULT
            ]
        );
        // 形の列は幅を決め，結果の列の左の端をすべての行でそろえる．結果は形の後ろ(有効の印の次)に持つ
        assert!(matches!(layout.columns[1].width, ColumnWidth::Fixed(_)));
        assert_eq!(layout.columns[2].source, MACRO_FIELDS.len() + 1);
        assert!(layout.columns.iter().all(|column| column.badge.is_none()));
    }

    #[test]
    fn 一覧のファイルのボタンは表の下の帯に置く() {
        let romaji = &sections(Page::Romaji).unwrap()[0].rows;
        assert_eq!(romaji.len(), 1);
        let buttons = romaji[0].control.list_buttons().unwrap();
        assert_eq!(
            buttons.bottom_labels(),
            vec![
                settings::REMOVE,
                settings::IMPORT_DICTIONARY,
                settings::EXPORT_DICTIONARY
            ]
        );
    }

    #[test]
    fn 除外設定は_macos_と同じく表の下に動作と並べ替えを置き_csv_は別のカードにする() {
        let page = sections(Page::Apps).unwrap();
        let list = &page[0].rows[0].control;
        let buttons = list.list_buttons().unwrap();
        // [動作][アプリを追加…] … [∧][∨][削除]
        assert_eq!(
            buttons.bottom,
            &[
                more::ADD_APPS,
                dictionaries::MOVE_UP,
                dictionaries::MOVE_DOWN,
                settings::REMOVE
            ]
        );
        assert_eq!(buttons.trailing_bottom, 3);
        assert_eq!(buttons.bottom_fields, 1);
        assert_eq!(buttons.top_fields(2), 1);
        assert!(buttons.is_icon(dictionaries::MOVE_UP));
        assert!(!buttons.is_icon(more::ADD_APPS));
        assert!(buttons.files.is_none() && !buttons.search);
        // 上の決まりから先に効くので，見出しで並べ替えず，行を動かす
        assert!(list.reorderable() && !list.sortable());
        let layout = list.table_layout();
        assert_eq!(layout.columns[0].cell, Cell::Path);
        assert_eq!(layout.columns[1].cell, Cell::Choice);
        // CSV は一覧の下の別のカード
        assert_eq!(page[1].rows[0].control, Control::Buttons(EXCLUSION_FILES));
    }

    #[test]
    fn コマンドは表を読むだけにし_足す_書き換える_消すを表の下に置く() {
        let page = sections(Page::Commands).unwrap();
        let list = &page[0].rows[1].control;
        let buttons = list.list_buttons().unwrap();
        assert!(buttons.sheet);
        assert_eq!(buttons.top, &[] as &[&str]);
        assert_eq!(buttons.top_fields(4), 0);
        assert_eq!(buttons.input_fields(4), 0);
        assert_eq!(
            buttons.bottom,
            &[
                extras::ADD_COMMAND,
                extras::EDIT_COMMAND,
                extras::REMOVE_COMMAND
            ]
        );
        // 同じ読みのコマンドをいくつも足せる(見分ける欄が無い)
        assert!(list
            .list_spec()
            .unwrap()
            .fields
            .iter()
            .all(|field| !field.key));
        assert!(list.sortable());
    }

    #[test]
    fn 入力のページの並び() {
        let page = sections(Page::Input).unwrap();
        let titles: Vec<_> = page.iter().map(|section| section.title).collect();
        assert_eq!(titles, vec![Some("入力方式"), Some("文字"), Some("動作")]);
        assert_eq!(page[1].rows.len(), 12);
    }

    #[test]
    fn カスタムテーマの行は上限の数だけ並べる() {
        let page = with_custom_theme_rows(sections(Page::Appearance).unwrap(), 3);
        let rows: Vec<&Control> = page
            .iter()
            .flat_map(|section| &section.rows)
            .map(|row| &row.control)
            .filter(|control| matches!(control, Control::CustomTheme(_)))
            .collect();
        assert_eq!(
            rows,
            vec![
                &Control::CustomTheme(0),
                &Control::CustomTheme(1),
                &Control::CustomTheme(2)
            ]
        );
        // 空のときの知らせ・行・作るボタンの順(macOS の AppearancePage と同じ)
        let custom = page
            .iter()
            .find(|section| section.title == Some(more::CUSTOM_THEMES))
            .unwrap();
        assert_eq!(custom.rows.first().unwrap().control, Control::Placeholder);
        assert!(matches!(
            custom.rows.last().unwrap().control,
            Control::Buttons(_)
        ));
    }
}
