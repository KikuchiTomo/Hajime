#![forbid(unsafe_code)]

use ipc::InputMode;

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

pub fn dictionary_source(name: &str) -> String {
    format!("辞書: {name}")
}
