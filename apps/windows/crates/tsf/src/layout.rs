#![forbid(unsafe_code)]

//! 設定の「キー配列」(ABC・US・Dvorak・Colemak)で英字を打つための表．
//! macOS は OS の配列を入力先に対して切り替える(overrideKeyboard)が，Windows で配列を読み込むと利用者の配列の一覧が変わるので，
//! キーの位置(スキャンコード．US 配列の位置)から文字を引く表を持つ

/// 1 行ぶんのキー．先頭のスキャンコードから続くキーの，Shift なしと Shift ありの文字
struct Row {
    first_scan: u16,
    plain: &'static str,
    shifted: &'static str,
}

struct Layout {
    rows: &'static [Row],
}

const fn row(first_scan: u16, plain: &'static str, shifted: &'static str) -> Row {
    Row {
        first_scan,
        plain,
        shifted,
    }
}

const US: Layout = Layout {
    rows: &[
        row(0x02, "1234567890-=", "!@#$%^&*()_+"),
        row(0x10, "qwertyuiop[]", "QWERTYUIOP{}"),
        row(0x1E, "asdfghjkl;'`", "ASDFGHJKL:\"~"),
        row(0x2B, "\\zxcvbnm,./", "|ZXCVBNM<>?"),
    ],
};

const DVORAK: Layout = Layout {
    rows: &[
        row(0x02, "1234567890[]", "!@#$%^&*(){}"),
        row(0x10, "',.pyfgcrl/=", "\"<>PYFGCRL?+"),
        row(0x1E, "aoeuidhtns-`", "AOEUIDHTNS_~"),
        row(0x2B, "\\;qjkxbmwvz", "|:QJKXBMWVZ"),
    ],
};

const COLEMAK: Layout = Layout {
    rows: &[
        row(0x02, "1234567890-=", "!@#$%^&*()_+"),
        row(0x10, "qwfpgjluy;[]", "QWFPGJLUY:{}"),
        row(0x1E, "arstdhneio'`", "ARSTDHNEIO\"~"),
        row(0x2B, "\\zxcvbkm,./", "|ZXCVBKM<>?"),
    ],
};

/// 設定の値(KeyboardLayout の rawValue)の表．知らない値なら None(OS の配列のまま)
fn layout(name: &str) -> Option<&'static Layout> {
    match name {
        "abc" | "us" => Some(&US),
        "dvorak" | "dvorakQwertyCommand" => Some(&DVORAK),
        "colemak" => Some(&COLEMAK),
        _ => None,
    }
}

/// キーの位置で打つ文字．表に無いキー(Space・テンキー・JIS 配列だけにあるキーなど)は None．
/// Caps Lock は英字にだけ効く
pub fn character(name: &str, scan: u16, shift: bool, caps_lock: bool) -> Option<char> {
    let table = layout(name)?;
    table.rows.iter().find_map(|row| {
        let index = usize::from(scan.checked_sub(row.first_scan)?);
        let plain = row.plain.chars().nth(index)?;
        let shifted = row.shifted.chars().nth(index)?;
        let upper = shift != (caps_lock && plain.is_ascii_alphabetic());
        Some(if upper { shifted } else { plain })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const Q: u16 = 0x10;
    const A: u16 = 0x1E;
    const Z: u16 = 0x2C;
    const MINUS: u16 = 0x0C;

    #[test]
    fn キーの位置から配列の文字を引く() {
        assert_eq!(character("us", Q, false, false), Some('q'));
        assert_eq!(character("dvorak", Q, false, false), Some('\''));
        assert_eq!(character("dvorak", A + 1, false, false), Some('o'));
        assert_eq!(character("colemak", A + 1, false, false), Some('r'));
        assert_eq!(character("dvorak", Z, false, false), Some(';'));
        assert_eq!(character("dvorak", MINUS, true, false), Some('{'));
    }

    #[test]
    fn caps_lock_は英字にだけ効く() {
        assert_eq!(character("colemak", A, false, true), Some('A'));
        assert_eq!(character("colemak", A, true, true), Some('a'));
        assert_eq!(character("dvorak", Q, false, true), Some('\''));
    }

    #[test]
    fn os_の配列のままか表に無いキーなら引かない() {
        assert_eq!(character("system", Q, false, false), None);
        assert_eq!(character("dvorak", 0x39, false, false), None);
        assert_eq!(character("dvorak", 0x73, false, false), None);
    }

    #[test]
    fn 表の行は_shift_なしとありで同じ数() {
        for table in [&US, &DVORAK, &COLEMAK] {
            for row in table.rows {
                assert_eq!(row.plain.chars().count(), row.shifted.chars().count());
            }
        }
    }
}
