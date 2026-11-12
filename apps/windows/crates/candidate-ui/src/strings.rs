#![forbid(unsafe_code)]

use ipc::{InputMode, PartOfSpeech};

/// 上の枝(文字種)の丸に入れる印
pub const VARIANT_BADGE: &str = "↑";

/// 打ち間違いを直した文節の幹に添える札
pub const CORRECTED: &str = "修正";

/// コマンドの候補を読み上げるときの前置き(core の CandidatePanel.commandAnnotation)
pub const COMMAND: &str = "コマンド";

/// ユーザー辞書の語のコメントを，候補に続けて読み上げる文(macOS の UIStrings.Candidate.commentAnnouncement)
pub fn comment_announcement(text: &str, comment: &str) -> String {
    format!("{text}、コメント、{comment}")
}

pub fn mode(mode: InputMode) -> &'static str {
    match mode {
        InputMode::Japanese => "あ",
        InputMode::Direct => "A",
    }
}

/// 予測の窓を読み上げる文(macOS の UIStrings.Prediction.announcement)
pub fn prediction(text: &str) -> String {
    format!("予測 {text}")
}

pub fn position(first: u32, last: u32, total: u32) -> String {
    if first == last {
        format!("{first} / {total}")
    } else {
        format!("{first}–{last} / {total}")
    }
}

/// 文字種の行を選んでいるときの位置
pub fn variants_position(index: u32, total: u32) -> String {
    format!("文字種 {index} / {total}")
}

/// 連想の一覧の見出しの前に置く言葉(macOS の UIStrings.Association.headingPrefix)
pub const ASSOCIATION_PREFIX: &str = "連想";

/// パレットの説明の欄の項目名(macOS の UIStrings.Palette の unicodeNameLabel など)．
/// PALETTE_ENGLISH_NAME は UCD の名前の無い並び(国旗など)で代わりに出す英語の名前
pub const PALETTE_UNICODE_NAME: &str = "Unicode";
pub const PALETTE_ENGLISH_NAME: &str = "英語";
pub const PALETTE_READINGS: &str = "読み";
pub const PALETTE_SHORTCODES: &str = "ショートコード";
pub const PALETTE_CODE_POINTS: &str = "コードポイント";
/// 読みの区切り(core の PaletteStrings.readingSeparator)
pub const PALETTE_READING_SEPARATOR: &str = "、";
/// エンジンが Unicode の名前(UCD の名前)を送るときの出どころ(core の PaletteStrings.unicodeSource)．ほかは CLDR の英語の名前
pub const PALETTE_UNICODE_SOURCE: &str = "Unicode";

/// 語の意味のカードに入らなかった同音語の数(パレットの説明の欄に入らなかった読みと札の数にも使う)
pub fn more(count: usize) -> String {
    format!("+{count}")
}

/// 意味が 2 つ以上あるときの，意味の番号(macOS の UIStrings.Candidate.senseNumber．語の意味のカードの角丸の四角に入れる)
pub fn sense_number(number: usize) -> String {
    format!("{number}")
}

/// 品詞の名前(core の PartOfSpeech.name と同じ)．語の意味のカードの見出しの札と読み上げに使う
pub fn part_of_speech(part: PartOfSpeech) -> &'static str {
    match part {
        PartOfSpeech::Noun => "名詞",
        PartOfSpeech::Verb => "動詞",
        PartOfSpeech::Adjective => "形容詞",
        PartOfSpeech::AdjectivalNoun => "形容動詞",
        PartOfSpeech::Adverb => "副詞",
        PartOfSpeech::Prenominal => "連体詞",
        PartOfSpeech::Conjunction => "接続詞",
        PartOfSpeech::Interjection => "感動詞",
        PartOfSpeech::Pronoun => "代名詞",
        PartOfSpeech::Prefix => "接頭辞",
        PartOfSpeech::Suffix => "接尾辞",
    }
}

/// 連想の意味のまとまりの位置
pub fn association_position(index: u32, total: u32) -> String {
    format!("{index} / {total}")
}

pub fn dictionary_source(name: &str) -> String {
    format!("辞書: {name}")
}
