#![forbid(unsafe_code)]

use ipc::{Key, KeyInput, Modifiers};

pub const VK_BACK: u16 = 0x08;
pub const VK_TAB: u16 = 0x09;
pub const VK_RETURN: u16 = 0x0D;
pub const VK_SHIFT: u16 = 0x10;
pub const VK_CONTROL: u16 = 0x11;
pub const VK_MENU: u16 = 0x12;
pub const VK_CAPITAL: u16 = 0x14;
pub const VK_KANA: u16 = 0x15;
pub const VK_KANJI: u16 = 0x19;
pub const VK_ESCAPE: u16 = 0x1B;
pub const VK_CONVERT: u16 = 0x1C;
pub const VK_NONCONVERT: u16 = 0x1D;
pub const VK_SPACE: u16 = 0x20;
pub const VK_PRIOR: u16 = 0x21;
pub const VK_NEXT: u16 = 0x22;
pub const VK_END: u16 = 0x23;
pub const VK_HOME: u16 = 0x24;
pub const VK_LEFT: u16 = 0x25;
pub const VK_UP: u16 = 0x26;
pub const VK_RIGHT: u16 = 0x27;
pub const VK_DOWN: u16 = 0x28;
pub const VK_DELETE: u16 = 0x2E;
pub const VK_LWIN: u16 = 0x5B;
pub const VK_RWIN: u16 = 0x5C;
pub const VK_NUMPAD0: u16 = 0x60;
pub const VK_DIVIDE: u16 = 0x6F;
pub const VK_F1: u16 = 0x70;
pub const VK_F24: u16 = 0x87;
pub const VK_LSHIFT: u16 = 0xA0;
pub const VK_RMENU: u16 = 0xA5;
pub const VK_OEM_5: u16 = 0xDC;
pub const VK_DBE_ALPHANUMERIC: u16 = 0xF0;
pub const VK_DBE_KATAKANA: u16 = 0xF1;
pub const VK_DBE_HIRAGANA: u16 = 0xF2;
pub const VK_DBE_SBCSCHAR: u16 = 0xF3;
pub const VK_DBE_DBCSCHAR: u16 = 0xF4;

#[derive(Clone, PartialEq)]
pub struct RawKey {
    pub vk: u16,
    pub text: Option<char>,
    pub modifiers: Modifiers,
    pub japanese_layout: bool,
    pub label: Option<char>,
}

pub fn is_modifier_only(vk: u16) -> bool {
    matches!(
        vk,
        VK_SHIFT | VK_CONTROL | VK_MENU | VK_LWIN | VK_RWIN | VK_CAPITAL
    ) || (VK_LSHIFT..=VK_RMENU).contains(&vk)
}

pub fn translate(raw: &RawKey) -> Option<KeyInput> {
    let named = match raw.vk {
        VK_BACK => Some(Key::Backspace),
        VK_TAB => Some(Key::Tab),
        VK_RETURN => Some(Key::Enter),
        VK_ESCAPE => Some(Key::Escape),
        VK_SPACE => Some(Key::Space),
        VK_PRIOR => Some(Key::PageUp),
        VK_NEXT => Some(Key::PageDown),
        VK_END => Some(Key::End),
        VK_HOME => Some(Key::Home),
        VK_LEFT => Some(Key::Left),
        VK_UP => Some(Key::Up),
        VK_RIGHT => Some(Key::Right),
        VK_DOWN => Some(Key::Down),
        VK_DELETE => Some(Key::Delete),
        VK_CONVERT => Some(Key::Henkan),
        VK_NONCONVERT => Some(Key::Muhenkan),
        VK_KANJI | VK_DBE_SBCSCHAR | VK_DBE_DBCSCHAR => Some(Key::HankakuZenkaku),
        VK_KANA | VK_DBE_HIRAGANA | VK_DBE_KATAKANA => Some(Key::Kana),
        VK_DBE_ALPHANUMERIC => Some(Key::Eisu),
        VK_OEM_5 if raw.japanese_layout => Some(Key::Yen),
        vk if (VK_F1..=VK_F24).contains(&vk) => Some(Key::Function {
            number: (vk - VK_F1 + 1) as u8,
        }),
        _ => None,
    };
    let is_keypad = (VK_NUMPAD0..=VK_DIVIDE).contains(&raw.vk);
    let key = match named {
        Some(key) => key,
        None => {
            let character = raw.text.filter(|c| !c.is_control())?;
            Key::Character {
                text: character.to_string(),
            }
        }
    };
    Some(KeyInput {
        key,
        modifiers: raw.modifiers.clone(),
        key_label: raw.label.filter(|c| !c.is_control()).map(String::from),
        is_keypad,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn raw(vk: u16, text: Option<char>) -> RawKey {
        RawKey {
            vk,
            text,
            modifiers: Modifiers {
                shift: false,
                control: false,
                alt: false,
            },
            japanese_layout: true,
            label: text,
        }
    }

    #[test]
    fn 文字のキーは配列で入る文字にする() {
        let input = translate(&raw(0x41, Some('a'))).unwrap();
        assert_eq!(input.key, Key::Character { text: "a".into() });
        assert_eq!(input.key_label.as_deref(), Some("a"));
        assert!(!input.is_keypad);
    }

    #[test]
    fn 日本語のキーボードのキー() {
        assert_eq!(
            translate(&raw(VK_KANJI, None)).unwrap().key,
            Key::HankakuZenkaku
        );
        assert_eq!(
            translate(&raw(VK_DBE_SBCSCHAR, None)).unwrap().key,
            Key::HankakuZenkaku
        );
        assert_eq!(translate(&raw(VK_CONVERT, None)).unwrap().key, Key::Henkan);
        assert_eq!(
            translate(&raw(VK_NONCONVERT, None)).unwrap().key,
            Key::Muhenkan
        );
        assert_eq!(
            translate(&raw(VK_DBE_HIRAGANA, None)).unwrap().key,
            Key::Kana
        );
        assert_eq!(
            translate(&raw(VK_DBE_ALPHANUMERIC, None)).unwrap().key,
            Key::Eisu
        );
    }

    #[test]
    fn 円記号のキーは日本語の配列のときだけ() {
        assert_eq!(translate(&raw(VK_OEM_5, Some('\\'))).unwrap().key, Key::Yen);
        let mut us = raw(VK_OEM_5, Some('\\'));
        us.japanese_layout = false;
        assert_eq!(
            translate(&us).unwrap().key,
            Key::Character { text: "\\".into() }
        );
    }

    #[test]
    fn ファンクションキーとテンキー() {
        assert_eq!(
            translate(&raw(VK_F1 + 6, None)).unwrap().key,
            Key::Function { number: 7 }
        );
        let keypad = translate(&raw(VK_NUMPAD0 + 1, Some('1'))).unwrap();
        assert!(keypad.is_keypad);
        assert_eq!(keypad.key, Key::Character { text: "1".into() });
    }

    #[test]
    fn 文字にならないキーと修飾キーだけの押下は扱わない() {
        assert!(translate(&raw(0x13, None)).is_none());
        assert!(translate(&raw(0x41, Some('\u{1}'))).is_none());
        assert!(is_modifier_only(VK_SHIFT));
        assert!(is_modifier_only(VK_RMENU));
        assert!(!is_modifier_only(VK_SPACE));
    }
}
