#![forbid(unsafe_code)]

use ipc::{InputMode, KeyHint};

/// 上の枝(文字種)の丸に入れる印
pub const VARIANT_BADGE: &str = "↑";

pub fn mode(mode: InputMode) -> &'static str {
    match mode {
        InputMode::Japanese => "あ",
        InputMode::Direct => "A",
    }
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

pub fn dictionary_source(name: &str) -> String {
    format!("辞書: {name}")
}

fn hint(keys: &str, label: &str) -> KeyHint {
    KeyHint {
        keys: keys.into(),
        label: label.into(),
    }
}

/// 候補の一覧の足元の案内
pub fn candidates_hints() -> Vec<KeyHint> {
    vec![hint("↑", "文字種")]
}

/// 文字種の行を選んでいるときの足元の案内
pub fn variants_hints() -> Vec<KeyHint> {
    vec![hint("←→", "選ぶ"), hint("↓", "候補")]
}
