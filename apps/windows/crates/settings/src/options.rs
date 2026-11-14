#![forbid(unsafe_code)]

//! 列挙の項目の選択肢．値は設定のファイルに書く名前(core の列挙の rawValue)，名前は macOS の画面と同じ(UIStrings.Choice ほか)．
//! 並びは core の列挙の並び(macOS の画面と同じ)

/// 値と画面に出す名前
pub type Choice = (&'static str, &'static str);

/// コマンドの動作．ショートカット App(runShortcut)は macOS だけなので出さない
pub const COMMAND_KINDS: &[Choice] = &[
    ("openApplication", "アプリを開く"),
    ("openURL", "Web ページを開く"),
    ("openFile", "ファイルを開く"),
];

/// ユーザー辞書の語の品詞(core の WordClass)．Microsoft IME の単語の登録と同じ順に並べる(macOS の DictionaryPage の品詞のポップアップ)
pub const WORD_CLASSES: &[Choice] = &[
    ("noun", "名詞"),
    ("surname", "人名(姓のみ)"),
    ("givenName", "人名(名のみ)"),
    ("personName", "人名(姓と名)"),
    ("place", "地名"),
    ("abbreviation", "短縮よみ"),
    ("symbol", "顔文字・記号"),
    ("properNoun", "固有名詞"),
    ("organization", "組織名"),
    ("suruNoun", "サ変名詞(〜する)"),
    ("adjectivalNoun", "形容動詞(〜な)"),
    ("adverb", "副詞"),
    ("interjection", "感動詞"),
];

/// 選択肢の一覧の中の組．title があれば組の見出しにする(macOS の RuleKinds.Group)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ChoiceGroup {
    pub title: Option<&'static str>,
    /// 組に入る選択肢の数(選択肢の並びの順に数える)
    pub count: usize,
}

/// 品詞の一覧の組(macOS の DictionaryPage の wordClasses)．名詞，人名，地名・短縮よみ・顔文字・記号，その他
pub const WORD_CLASS_GROUPS: &[ChoiceGroup] = &[
    ChoiceGroup {
        title: None,
        count: 1,
    },
    ChoiceGroup {
        title: Some(crate::strings::settings::PERSON_NAME_GROUP),
        count: 3,
    },
    ChoiceGroup {
        title: None,
        count: 3,
    },
    ChoiceGroup {
        title: Some(crate::strings::settings::OTHER_WORD_CLASSES),
        count: 6,
    },
];

pub const INPUT_STYLES: &[Choice] = &[
    ("romaji", "ローマ字入力"),
    ("kana", "かな入力"),
    ("english", "英字入力"),
    ("englishAuto", "英字入力(自動)"),
];

/// macOS の「Dvorak - QWERTY ⌘」は，Windows では Command の代わりに Ctrl のショートカットを QWERTY にする
pub const KEYBOARD_LAYOUTS: &[Choice] = &[
    ("system", "システムの設定に従う"),
    ("abc", "ABC"),
    ("us", "US"),
    ("dvorak", "Dvorak"),
    ("dvorakQwertyCommand", "Dvorak - QWERTY Ctrl"),
    ("colemak", "Colemak"),
];

pub const PUNCTUATION: &[Choice] = &[
    ("toutenKuten", "、。"),
    ("commaPeriod", "，．"),
    ("toutenPeriod", "、．"),
    ("commaKuten", "，。"),
];

pub const BRACKETS: &[Choice] = &[("corner", "「」"), ("square", "［］")];

pub const SLASH: &[Choice] = &[("nakaguro", "・"), ("slash", "／")];

pub const WIDTHS: &[Choice] = &[("halfwidth", "半角"), ("fullwidth", "全角")];

pub const YEN_KEY: &[Choice] = &[
    ("alwaysBackslash", "常に \\"),
    ("alwaysYen", "常に ¥"),
    ("backslashInProgramming", "エディタとターミナルだけ \\"),
];

pub const PRESENTATIONS: &[Choice] = &[
    ("automatic", "分岐図"),
    ("segmentList", "一覧"),
    ("list", "文全体の一覧"),
];

pub const BRANCH_WINDOW_WIDTHS: &[Choice] = &[("fit", "内容に合わせる"), ("fixed", "固定")];
pub const MEANING_PLACEMENTS: &[Choice] = &[("side", "吹き出し"), ("below", "候補の下")];

pub const INITIAL_FOCUS: &[Choice] = &[("start", "先頭"), ("end", "末尾"), ("automatic", "自動")];

pub const SUGGESTION_DISPLAY: &[Choice] = &[
    ("off", "オフ"),
    ("whenLiveConversionOff", "ライブ変換がオフのとき"),
    ("always", "常に"),
];

pub const TYPO_CORRECTION: &[Choice] = &[
    ("off", "オフ"),
    ("conservative", "英単語のみ"),
    ("standard", "英単語と日本語"),
];

pub const CORRECTION_SENSITIVITY: &[Choice] = &[
    ("cautious", "慎重"),
    ("standard", "標準"),
    ("aggressive", "積極的"),
];

pub const OKURIGANA: &[Choice] = &[
    ("standard", "本則"),
    ("allowed", "許容"),
    ("engine", "優先しない"),
];

/// かな漢字変換に使う Zenzai モデル(ZenzaiModelChoice)．UIStrings.Settings.label(for: ZenzaiModelChoice)
pub const ZENZAI_MODELS: &[Choice] = &[
    ("accurate", "精度を優先"),
    ("fast", "速さを優先"),
    ("combined", "併用"),
];

/// 合議に使う Jinen モデル(JinenModelChoice)．UIStrings.Settings.label(for: JinenModelChoice, automaticResult:)
pub const JINEN_MODELS: &[Choice] = &[
    ("automatic", "自動"),
    ("small", "small"),
    ("xsmall", "xsmall"),
    ("off", "オフ"),
];

pub const LEARNING: &[Choice] = &[
    ("enabled", "学習する"),
    ("readOnly", "学習結果のみ使用"),
    ("disabled", "学習しない"),
];

/// 英語と日本語(WordLanguage)．UIStrings.Features.label(for: WordLanguage)
pub const WORD_LANGUAGES: &[Choice] = &[("english", "英語"), ("japanese", "日本語")];

/// 語の前(WordLanguageContext)．UIStrings.Features.label(for: WordLanguageContext)
pub const WORD_CONTEXTS: &[Choice] = &[
    ("sentenceStart", "文頭"),
    ("afterEnglish", "英語"),
    ("afterJapanese", "日本語"),
];

/// 選択肢の値の名前(無ければ値のまま)
pub fn label_of<'a>(choices: &'a [Choice], value: &'a str) -> &'a str {
    choices
        .iter()
        .find(|(choice, _)| *choice == value)
        .map_or(value, |(_, label)| label)
}

/// カスタムテーマの枝の線(CustomTheme.BranchStyle)
pub const BRANCH_STYLES: &[Choice] = &[("curved", "曲線"), ("straight", "直線")];

/// 同期の範囲(SyncScope)．macOS の「この Mac だけ」を「この PC だけ」にする
pub const SYNC_SCOPES: &[Choice] = &[("synced", "同期する"), ("local", "この PC だけ")];

/// 同期のまとまり(SyncGroup)．並びは core の SyncGroup と同じ
pub const SYNC_GROUPS: &[Choice] = &[
    ("input", "入力"),
    ("keyboard", "キー配列"),
    ("keys", "キー設定"),
    ("conversion", "変換"),
    ("correction", "補正"),
    ("symbols", "記号"),
    ("dictionary", "ユーザー辞書"),
    ("importedDictionaries", "インポートした辞書"),
    ("associationDictionaries", "連想辞書"),
    ("appearance", "外観"),
    ("exclusions", "除外設定"),
    ("usage", "統計"),
];

/// アプリごとの扱い(AppProfile)．標準はアプリを一覧から消すのと同じなので並べない(macOS の ExclusionsPage と同じ)
pub const APP_PROFILES: &[Choice] = &[
    ("direct", "IME を使わない"),
    ("imeOff", "IME オフ"),
    ("imeOn", "IME オン"),
    ("remembersMode", "IME のオン・オフを記憶"),
    ("programming", "記号は半角"),
    ("terminal", "コマンドは英字"),
];

/// 選べる外観．native は標準と同じ見た目なので並べない(古い設定のファイルにあっても標準として読む)
pub const THEMES: &[Choice] = &[
    ("automatic", "標準"),
    ("indigo", "インディゴ"),
    ("indigoNight", "夜のインディゴ"),
    ("washi", "和紙"),
    ("nordic", "北欧"),
    ("neon", "ネオン"),
    ("terminal", "ターミナル"),
    ("contrast", "高コントラスト"),
    ("platinum", "プラチナ"),
    ("desk", "夜のデスク"),
];

/// 値の位置．古い値(テーマの native)は標準として読み，知らない値は先頭にする
pub fn index_of(options: &[Choice], value: &str) -> usize {
    let value = if value == "native" {
        "automatic"
    } else {
        value
    };
    options
        .iter()
        .position(|(candidate, _)| *candidate == value)
        .unwrap_or(0)
}

const SCALE: f64 = 1_000_000.0;

/// 範囲の中で選べる値(下限から step ごと)．0.1 を足し続けた誤差が出ないよう，段の番号から求めて 100 万分の 1 で丸める
pub fn steps(range: crate::catalog::Range, step: f64) -> Vec<f64> {
    if step <= 0.0 || range.upper() < range.lower() {
        return vec![range.lower()];
    }
    let count = ((range.upper() - range.lower()) / step + 1e-9).floor() as usize;
    (0..=count)
        .map(|index| ((range.lower() + step * index as f64) * SCALE).round() / SCALE)
        .collect()
}

/// いちばん近い値の位置
pub fn nearest(values: &[f64], value: f64) -> usize {
    values
        .iter()
        .enumerate()
        .min_by(|a, b| (a.1 - value).abs().total_cmp(&(b.1 - value).abs()))
        .map_or(0, |(index, _)| index)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 品詞の選択肢は通信の品詞をすべて一度ずつ持つ() {
        let classes: Vec<ipc::WordClass> = WORD_CLASSES
            .iter()
            .map(|(value, _)| {
                serde_json::from_value(serde_json::Value::String((*value).to_string())).unwrap()
            })
            .collect();
        let unique: std::collections::HashSet<_> = classes.iter().collect();
        assert_eq!(unique.len(), WORD_CLASSES.len());
        // 通信の品詞の数(protocol/schema.json の WordClass)
        assert_eq!(classes.len(), 13);
    }

    #[test]
    fn 品詞の組は選択肢をすべて一度ずつ分ける() {
        let counts: Vec<usize> = WORD_CLASS_GROUPS.iter().map(|group| group.count).collect();
        assert_eq!(counts.iter().sum::<usize>(), WORD_CLASSES.len());
        // 組の先頭の値(macOS の DictionaryPage の wordClasses と同じ分け方)
        let mut start = 0;
        let firsts: Vec<&str> = WORD_CLASS_GROUPS
            .iter()
            .map(|group| {
                let first = WORD_CLASSES[start].0;
                start += group.count;
                first
            })
            .collect();
        assert_eq!(firsts, ["noun", "surname", "place", "properNoun"]);
        let titles: Vec<Option<&str>> = WORD_CLASS_GROUPS.iter().map(|group| group.title).collect();
        assert_eq!(titles, [None, Some("人名"), None, Some("その他")]);
    }

    #[test]
    fn 以前の値は標準として選ぶ() {
        assert_eq!(index_of(THEMES, "native"), 0);
        assert_eq!(index_of(THEMES, "desk"), 9);
        assert_eq!(index_of(INPUT_STYLES, "unknown"), 0);
    }

    #[test]
    fn 範囲を段に分ける() {
        let values = steps(crate::catalog::Range(0.1, 1.0), 0.1);
        assert_eq!(values.len(), 10);
        assert_eq!(values[2], 0.3);
        assert_eq!(*values.last().unwrap(), 1.0);
        assert_eq!(steps(crate::catalog::Range(3.0, 9.0), 1.0).len(), 7);
    }

    #[test]
    fn 近い値を選ぶ() {
        let values = steps(crate::catalog::Range(10.0, 24.0), 1.0);
        assert_eq!(values[nearest(&values, 15.4)], 15.0);
        assert_eq!(values[nearest(&values, 100.0)], 24.0);
    }

    #[test]
    fn 選択肢の値は重ならない() {
        for options in [
            INPUT_STYLES,
            KEYBOARD_LAYOUTS,
            PUNCTUATION,
            BRACKETS,
            SLASH,
            WIDTHS,
            YEN_KEY,
            PRESENTATIONS,
            INITIAL_FOCUS,
            SUGGESTION_DISPLAY,
            TYPO_CORRECTION,
            CORRECTION_SENSITIVITY,
            OKURIGANA,
            LEARNING,
            ZENZAI_MODELS,
            JINEN_MODELS,
            THEMES,
            WORD_LANGUAGES,
            WORD_CONTEXTS,
            APP_PROFILES,
        ] {
            for (index, (value, _)) in options.iter().enumerate() {
                assert_eq!(index_of(options, value), index);
            }
        }
    }
}
