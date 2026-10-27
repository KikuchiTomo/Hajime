#![forbid(unsafe_code)]

//! 足元の案内のキー(「Shift+←」「Ctrl+Tab」「1–2」)を，キーキャップの中に並べる部品に分ける．
//! 矢印や Shift などはアイコンで描き(macOS の SF Symbols に当たる)，Ctrl・Alt・文字は文字で描く

/// キーキャップや番号の丸の中に描くアイコン．形は icon::figures が決める
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Icon {
    Up,
    Down,
    Left,
    Right,
    LeftRight,
    Shift,
    Tab,
    Space,
    Enter,
    Escape,
    Backspace,
    /// 案内の頭のアイコン．打ち間違いを直した(macOS の wand.and.stars に当たるきらめき)
    Sparkle,
    /// 案内の頭のアイコン．「もしかして」(macOS の lightbulb)
    Lightbulb,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Part {
    Icon(Icon),
    Text(String),
}

/// 名前で書くキーのうち，アイコンで描くもの
const NAMED: &[(&str, Icon)] = &[
    ("←→", Icon::LeftRight),
    ("↑", Icon::Up),
    ("↓", Icon::Down),
    ("←", Icon::Left),
    ("→", Icon::Right),
    ("Shift", Icon::Shift),
    ("Tab", Icon::Tab),
    ("Space", Icon::Space),
    ("Enter", Icon::Enter),
    ("Esc", Icon::Escape),
    ("BS", Icon::Backspace),
];

/// 1 つのキーの名前をアイコンにする．アイコンで描かないキーは None
pub fn icon(name: &str) -> Option<Icon> {
    NAMED
        .iter()
        .find(|(label, _)| *label == name)
        .map(|(_, icon)| *icon)
}

/// 「+」でつないだキーを部品に分ける．アイコンでないキーは文字のまま(「Ctrl」「F7」「変換」「1–2」)
pub fn parts(keys: &str) -> Vec<Part> {
    keys.split('+')
        .filter(|key| !key.is_empty())
        .map(|key| icon(key).map_or_else(|| Part::Text(key.to_string()), Part::Icon))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 矢印と_shift_はアイコンにする() {
        assert_eq!(
            parts("Shift+←"),
            vec![Part::Icon(Icon::Shift), Part::Icon(Icon::Left)]
        );
        assert_eq!(parts("Shift+←→").last(), Some(&Part::Icon(Icon::LeftRight)));
        assert_eq!(parts("↓"), vec![Part::Icon(Icon::Down)]);
        assert_eq!(parts("Esc"), vec![Part::Icon(Icon::Escape)]);
    }

    #[test]
    fn ctrl_と文字は文字で描く() {
        assert_eq!(
            parts("Ctrl+Tab"),
            vec![Part::Text("Ctrl".into()), Part::Icon(Icon::Tab)]
        );
        assert_eq!(parts("1–2"), vec![Part::Text("1–2".into())]);
        assert_eq!(parts("半角/全角"), vec![Part::Text("半角/全角".into())]);
        assert_eq!(
            parts("Ctrl+Alt+K"),
            vec![
                Part::Text("Ctrl".into()),
                Part::Text("Alt".into()),
                Part::Text("K".into())
            ]
        );
    }
}
