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
/// USB の LANG1・LANG2 のキー(Apple の JIS キーボードなどの「かな」「英数」)のスキャンコード．
/// Windows は仮想キーを 0x15・0x19 にして送り，日本語の配列ではカナ・半角/全角と同じ番号になるので，スキャンコードで見分ける
pub const SCAN_LANG1: u16 = 0xF2;
pub const SCAN_LANG2: u16 = 0xF1;

#[derive(Clone, PartialEq)]
pub struct RawKey {
    pub vk: u16,
    pub text: Option<char>,
    pub modifiers: Modifiers,
    pub japanese_layout: bool,
    pub label: Option<char>,
    /// キーの位置(スキャンコード)
    pub scan: u16,
    pub caps_lock: bool,
}

impl RawKey {
    /// 設定のキー配列で打つ文字に置き換える．Ctrl・Alt を押しているときは置き換えない(ショートカットは OS の配列のまま)
    pub fn with_layout(mut self, layout: Option<&str>) -> Self {
        let Some(layout) = layout else { return self };
        if self.modifiers.control || self.modifiers.alt {
            return self;
        }
        if let Some(text) =
            crate::layout::character(layout, self.scan, self.modifiers.shift, self.caps_lock)
        {
            self.text = Some(text);
        }
        self
    }
}

/// キーの位置(スキャンコード)から，JIS キーボードのその位置の刻印を引く．かな入力でかなを引くのに使う(core の KanaLayout)．
/// スキャンコードはキーの位置で決まり，配列の設定(US・JIS など)によらない(macOS の NSEventKeyTranslator.jisLabels と同じ表)．
/// テンキーなどの拡張キー(E0 の付くキー)は同じ番号でも別のキーなので引かない
pub fn jis_label(scan: u16, extended: bool) -> Option<char> {
    if extended {
        return None;
    }
    const LABELS: &[(u16, char)] = &[
        (0x02, '1'),
        (0x03, '2'),
        (0x04, '3'),
        (0x05, '4'),
        (0x06, '5'),
        (0x07, '6'),
        (0x08, '7'),
        (0x09, '8'),
        (0x0A, '9'),
        (0x0B, '0'),
        (0x0C, '-'),
        (0x0D, '^'),
        (0x10, 'q'),
        (0x11, 'w'),
        (0x12, 'e'),
        (0x13, 'r'),
        (0x14, 't'),
        (0x15, 'y'),
        (0x16, 'u'),
        (0x17, 'i'),
        (0x18, 'o'),
        (0x19, 'p'),
        (0x1A, '@'),
        (0x1B, '['),
        (0x1E, 'a'),
        (0x1F, 's'),
        (0x20, 'd'),
        (0x21, 'f'),
        (0x22, 'g'),
        (0x23, 'h'),
        (0x24, 'j'),
        (0x25, 'k'),
        (0x26, 'l'),
        (0x27, ';'),
        (0x28, ':'),
        (0x2B, ']'),
        (0x2C, 'z'),
        (0x2D, 'x'),
        (0x2E, 'c'),
        (0x2F, 'v'),
        (0x30, 'b'),
        (0x31, 'n'),
        (0x32, 'm'),
        (0x33, ','),
        (0x34, '.'),
        (0x35, '/'),
        (0x73, '_'),
    ];
    LABELS
        .iter()
        .find(|(code, _)| *code == scan)
        .map(|(_, label)| *label)
}

pub fn is_modifier_only(vk: u16) -> bool {
    matches!(
        vk,
        VK_SHIFT | VK_CONTROL | VK_MENU | VK_LWIN | VK_RWIN | VK_CAPITAL
    ) || (VK_LSHIFT..=VK_RMENU).contains(&vk)
}

pub fn translate(raw: &RawKey) -> Option<KeyInput> {
    let named = match raw.vk {
        _ if raw.scan == SCAN_LANG1 => Some(Key::Kana),
        _ if raw.scan == SCAN_LANG2 => Some(Key::Eisu),
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
        // ¥ のキー(JIS 配列の ¥ か \ の文字のとき)．Shift+¥ の | は配列の文字のまま使う(macOS の YenKeyPolicy と同じ)
        VK_OEM_5 if raw.japanese_layout && matches!(raw.text, Some('\\' | '¥')) => Some(Key::Yen),
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
            scan: 0,
            caps_lock: false,
        }
    }

    #[test]
    fn lang1_と_lang2_はスキャンコードでかなと英数にする() {
        // Windows は LANG2(英数)を半角/全角と同じ仮想キーにして送る
        let mut eisu = raw(VK_KANJI, None);
        eisu.scan = SCAN_LANG2;
        assert_eq!(translate(&eisu).unwrap().key, Key::Eisu);
        let mut kana = raw(VK_KANA, None);
        kana.scan = SCAN_LANG1;
        assert_eq!(translate(&kana).unwrap().key, Key::Kana);
        // ふつうの半角/全角はそのまま
        assert_eq!(
            translate(&raw(VK_KANJI, None)).unwrap().key,
            Key::HankakuZenkaku
        );
    }

    #[test]
    fn キー配列の設定で文字を置き換え_ctrl_では置き換えない() {
        let mut q = raw(0x51, Some('q'));
        q.scan = 0x10;
        assert_eq!(q.clone().with_layout(Some("dvorak")).text, Some('\''));
        assert_eq!(q.clone().with_layout(None).text, Some('q'));
        let mut control = q;
        control.modifiers.control = true;
        assert_eq!(control.with_layout(Some("dvorak")).text, Some('q'));
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
    fn shift_と円記号のキーは配列の文字のまま() {
        let mut bar = raw(VK_OEM_5, Some('|'));
        bar.modifiers.shift = true;
        assert_eq!(
            translate(&bar).unwrap().key,
            Key::Character { text: "|".into() }
        );
        assert_eq!(translate(&raw(VK_OEM_5, Some('¥'))).unwrap().key, Key::Yen);
    }

    #[test]
    fn かな入力の刻印はキーの位置で配列によらず引く() {
        assert_eq!(jis_label(0x1E, false), Some('a'));
        assert_eq!(jis_label(0x73, false), Some('_'));
        assert_eq!(jis_label(0x1A, false), Some('@'));
        assert_eq!(jis_label(0x28, false), Some(':'));
        // テンキーの / は拡張キーなので刻印にしない
        assert_eq!(jis_label(0x35, true), None);
        assert_eq!(jis_label(0x01, false), None);
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
