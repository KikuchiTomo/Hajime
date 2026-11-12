#![forbid(unsafe_code)]

use ipc::{InputMode, PartOfSpeech};

/// 上の枝(文字種)の丸に入れる印
pub const VARIANT_BADGE: &str = "↑";

/// 打ち間違いを直した文節の幹に添える札
pub const CORRECTED: &str = "修正";

/// コマンドの候補を読み上げるときの前置き(core の CandidatePanel.commandAnnotation)
pub const COMMAND: &str = "コマンド";

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

/// 語の意味のカードで，同音語の札の前に置く名前(macOS の UIStrings.Candidate.homophoneOthers)
pub const HOMOPHONE_OTHERS: &str = "同音語";

/// 語の意味のカードに入らなかった同音語の数
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
