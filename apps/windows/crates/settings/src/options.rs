#![forbid(unsafe_code)]

//! 列挙の項目の選択肢．値は設定のファイルに書く名前(core の列挙の rawValue)，名前は macOS の画面と同じ(UIStrings.Choice ほか)．
//! 並びは core の列挙の並び(macOS の画面と同じ)

/// 値と画面に出す名前
pub type Choice = (&'static str, &'static str);

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

pub const PRESENTATIONS: &[Choice] = &[("automatic", "分岐図"), ("list", "一覧")];

pub const INITIAL_FOCUS: &[Choice] = &[("start", "先頭"), ("end", "末尾"), ("automatic", "自動")];

pub const SUGGESTION_DISPLAY: &[Choice] = &[
    ("off", "表示しない"),
    ("whenLiveConversionOff", "ライブ変換がオフのとき"),
    ("always", "常に表示"),
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
    ("engine", "変換の順のまま"),
];

pub const LEARNING: &[Choice] = &[
    ("enabled", "学習する"),
    ("readOnly", "学習結果を使うが、新しく学習しない"),
    ("disabled", "学習しない"),
];

/// 英語と日本語(WordLanguage)．UIStrings.Features.label(for: WordLanguage)
pub const WORD_LANGUAGES: &[Choice] = &[("english", "英語"), ("japanese", "日本語")];

/// 語の前(WordLanguageContext)．UIStrings.Features.label(for: WordLanguageContext)
pub const WORD_CONTEXTS: &[Choice] = &[
    ("sentenceStart", "文の頭"),
    ("afterEnglish", "英語"),
    ("afterJapanese", "日本語"),
];

/// アプリごとの扱い(AppProfile)．標準はアプリを一覧から消すのと同じなので並べない(macOS の ExclusionsPage と同じ)
pub const APP_PROFILES: &[Choice] = &[
    ("direct", "IME を使わない"),
    ("programming", "記号を半角"),
    ("terminal", "コマンドを英字"),
];

/// 選べる外観．native は標準と同じ見た目なので並べない(古い設定のファイルにあっても標準として読む)
pub const THEMES: &[Choice] = &[
    ("automatic", "標準"),
    ("washi", "和紙"),
    ("nordic", "北欧"),
    ("neon", "ネオン"),
    ("terminal", "端末"),
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
    fn 以前の値は標準として選ぶ() {
        assert_eq!(index_of(THEMES, "native"), 0);
        assert_eq!(index_of(THEMES, "desk"), 7);
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
