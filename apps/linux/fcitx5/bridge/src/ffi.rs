//! C の関数(include/s90_bridge.h)．ポインタを受け取るところだけが unsafe で，中身は Bridge の安全な関数に渡す．
//! panic は C++ をまたがせない(Cargo.toml の panic = "abort")

#![allow(unsafe_code)]

use crate::Bridge;
use ipc::{FieldContext, Key, Modifiers, TextStyle};
use std::ffi::{c_char, c_int, CStr};
use std::os::fd::AsRawFd;
use std::path::Path;
use std::ptr;

/// s90_bridge.h の S90KeyKind と同じ順
fn key(kind: u32, text: Option<String>, number: u32) -> Option<Key> {
    Some(match kind {
        0 => Key::Character { text: text? },
        1 => Key::Space,
        2 => Key::Enter,
        3 => Key::Backspace,
        4 => Key::Delete,
        5 => Key::Escape,
        6 => Key::Tab,
        7 => Key::Up,
        8 => Key::Down,
        9 => Key::Left,
        10 => Key::Right,
        11 => Key::Home,
        12 => Key::End,
        13 => Key::PageUp,
        14 => Key::PageDown,
        15 => Key::Eisu,
        16 => Key::Kana,
        17 => Key::Yen,
        18 => Key::Function {
            number: u8::try_from(number).ok()?,
        },
        19 => Key::HankakuZenkaku,
        20 => Key::Henkan,
        21 => Key::Muhenkan,
        _ => return None,
    })
}

/// s90_bridge.h の S90Style と同じ値
fn style(style: TextStyle) -> u32 {
    match style {
        TextStyle::Reading => 0,
        TextStyle::Converted => 1,
        TextStyle::Focused => 2,
        TextStyle::Correction => 3,
    }
}

/// SAFETY: text は NULL か，NUL で終わる文字列を指すこと
unsafe fn string(text: *const c_char) -> Option<String> {
    if text.is_null() {
        return None;
    }
    // SAFETY: 呼ぶ側が NUL で終わる文字列を渡す(s90_bridge.h の約束)
    unsafe { CStr::from_ptr(text) }
        .to_str()
        .ok()
        .map(str::to_owned)
}

/// SAFETY: application_id は NULL か NUL で終わる文字列
unsafe fn context(application_id: *const c_char, secure: c_int) -> FieldContext {
    FieldContext {
        // SAFETY: 呼ぶ側の約束どおり
        application_id: unsafe { string(application_id) }.filter(|id| !id.is_empty()),
        is_secure: secure != 0,
        preceding_text: None,
        caret: None,
    }
}

/// SAFETY: bridge は s90_bridge_new が返し，まだ s90_bridge_free していないもの
unsafe fn bridge<'a>(bridge: *mut Bridge) -> Option<&'a mut Bridge> {
    // SAFETY: 呼ぶ側の約束どおり．Fcitx 5 は 1 本のスレッドで呼ぶので，同時に借りない
    unsafe { bridge.as_mut() }
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_new(engine_path: *const c_char) -> *mut Bridge {
    // SAFETY: engine_path は NULL か NUL で終わる文字列
    let engine = unsafe { string(engine_path) };
    match Bridge::new(engine.as_deref().map(Path::new)) {
        Ok(bridge) => Box::into_raw(Box::new(bridge)),
        Err(_) => ptr::null_mut(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_free(bridge: *mut Bridge) {
    if !bridge.is_null() {
        // SAFETY: s90_bridge_new が Box から作ったもので，1 回だけ放す
        drop(unsafe { Box::from_raw(bridge) });
    }
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_notify_fd(bridge: *mut Bridge) -> c_int {
    // SAFETY: 呼ぶ側の約束どおり
    unsafe { self::bridge(bridge) }.map_or(-1, |bridge| bridge.notify.as_raw_fd())
}

#[no_mangle]
#[allow(clippy::too_many_arguments)]
pub unsafe extern "C" fn s90_bridge_key(
    bridge: *mut Bridge,
    kind: u32,
    text: *const c_char,
    number: u32,
    modifiers: u32,
    keypad: c_int,
    application_id: *const c_char,
    secure: c_int,
) -> c_int {
    // SAFETY: 呼ぶ側の約束どおり
    let (Some(bridge), Some(key)) = (
        unsafe { self::bridge(bridge) },
        key(kind, unsafe { string(text) }, number),
    ) else {
        return 0;
    };
    let modifiers = Modifiers {
        shift: modifiers & 1 != 0,
        control: modifiers & 2 != 0,
        alt: modifiers & 4 != 0,
    };
    // SAFETY: 呼ぶ側の約束どおり
    let context = unsafe { context(application_id, secure) };
    c_int::from(bridge.key(key, modifiers, keypad != 0, context))
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_wake(
    bridge: *mut Bridge,
    application_id: *const c_char,
    secure: c_int,
) {
    // SAFETY: 呼ぶ側の約束どおり
    if let Some(bridge) = unsafe { self::bridge(bridge) } {
        // SAFETY: 呼ぶ側の約束どおり
        bridge.wake(unsafe { context(application_id, secure) });
    }
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_deactivate(bridge: *mut Bridge) {
    // SAFETY: 呼ぶ側の約束どおり
    if let Some(bridge) = unsafe { self::bridge(bridge) } {
        bridge.deactivate();
    }
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_commit(bridge: *mut Bridge) -> *const c_char {
    // SAFETY: 呼ぶ側の約束どおり
    unsafe { self::bridge(bridge) }.map_or(ptr::null(), |bridge| bridge.commit.as_ptr())
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_preedit_count(bridge: *mut Bridge) -> usize {
    // SAFETY: 呼ぶ側の約束どおり
    unsafe { self::bridge(bridge) }.map_or(0, |bridge| bridge.preedit.len())
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_preedit_text(
    bridge: *mut Bridge,
    index: usize,
    style_out: *mut u32,
) -> *const c_char {
    // SAFETY: 呼ぶ側の約束どおり
    let Some((text, segment_style)) =
        unsafe { self::bridge(bridge) }.and_then(|bridge| bridge.preedit.get(index))
    else {
        return ptr::null();
    };
    if !style_out.is_null() {
        // SAFETY: style_out は NULL か，書ける u32 を指す
        unsafe { style_out.write(style(*segment_style)) };
    }
    text.as_ptr()
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_is_composing(bridge: *mut Bridge) -> c_int {
    // SAFETY: 呼ぶ側の約束どおり
    unsafe { self::bridge(bridge) }.map_or(0, |bridge| c_int::from(bridge.output.is_composing))
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_wake_after(bridge: *mut Bridge) -> u32 {
    // SAFETY: 呼ぶ側の約束どおり
    unsafe { self::bridge(bridge) }
        .and_then(|bridge| bridge.output.wake_after)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_load_panel(bridge: *mut Bridge) {
    // SAFETY: 呼ぶ側の約束どおり
    if let Some(bridge) = unsafe { self::bridge(bridge) } {
        bridge.load_panel();
    }
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_candidate_count(bridge: *mut Bridge) -> usize {
    // SAFETY: 呼ぶ側の約束どおり
    unsafe { self::bridge(bridge) }.map_or(0, |bridge| bridge.candidates.len())
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_candidate(bridge: *mut Bridge, index: usize) -> *const c_char {
    // SAFETY: 呼ぶ側の約束どおり
    unsafe { self::bridge(bridge) }
        .and_then(|bridge| bridge.candidates.get(index))
        .map_or(ptr::null(), |text| text.as_ptr())
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_selected(bridge: *mut Bridge) -> i32 {
    // SAFETY: 呼ぶ側の約束どおり
    unsafe { self::bridge(bridge) }
        .and_then(|bridge| bridge.panel.selected)
        .and_then(|index| i32::try_from(index).ok())
        .unwrap_or(-1)
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_note(bridge: *mut Bridge) -> *const c_char {
    // SAFETY: 呼ぶ側の約束どおり
    unsafe { self::bridge(bridge) }.map_or(ptr::null(), |bridge| bridge.note.as_ptr())
}

#[no_mangle]
pub unsafe extern "C" fn s90_bridge_hints(bridge: *mut Bridge) -> *const c_char {
    // SAFETY: 呼ぶ側の約束どおり
    unsafe { self::bridge(bridge) }.map_or(ptr::null(), |bridge| bridge.hints.as_ptr())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn キーの番号は見出しのファイルと同じ順() {
        assert!(matches!(
            key(0, Some("a".into()), 0),
            Some(Key::Character { .. })
        ));
        assert!(key(0, None, 0).is_none());
        assert!(matches!(key(1, None, 0), Some(Key::Space)));
        assert!(matches!(
            key(18, None, 5),
            Some(Key::Function { number: 5 })
        ));
        assert!(matches!(key(21, None, 0), Some(Key::Muhenkan)));
        assert!(key(22, None, 0).is_none());
    }
}
