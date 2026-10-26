#![forbid(unsafe_code)]

pub const THEMES: &[(&str, &str)] = &[
    ("automatic", "標準"),
    ("washi", "和紙"),
    ("nordic", "北欧"),
    ("neon", "ネオン"),
    ("terminal", "端末"),
    ("contrast", "高コントラスト"),
    ("platinum", "プラチナ"),
    ("desk", "夜のデスク"),
];

pub const INPUT_STYLES: &[(&str, &str)] = &[
    ("romaji", "ローマ字入力"),
    ("kana", "かな入力"),
    ("english", "英字入力"),
];

pub const TITLE: &str = "s90.tokyo IME の設定";
pub const THEME: &str = "テーマ";
pub const INPUT_STYLE: &str = "入力方式";
pub const FONT_SIZE: &str = "文字の大きさ";
pub const LIVE_CONVERSION: &str = "ライブ変換";
pub const MODE_INDICATOR: &str = "入力モードの切り替えを表示";
pub const KEY_HINTS: &str = "キーの案内を表示";
pub const OPEN_FILE: &str = "設定ファイルを開く";
pub const ENGINE_UNAVAILABLE: &str = "変換エンジンが動いていません";

pub fn font_sizes() -> Vec<u32> {
    let min = tokens::size::candidate::FONT_SIZE_MIN as u32;
    let max = tokens::size::candidate::FONT_SIZE_MAX as u32;
    (min..=max).collect()
}

pub fn index_of(options: &[(&str, &str)], id: &str) -> usize {
    let id = if id == "native" { "automatic" } else { id };
    options
        .iter()
        .position(|(value, _)| *value == id)
        .unwrap_or(0)
}

pub fn nearest_font_size(sizes: &[u32], size: f64) -> usize {
    sizes
        .iter()
        .enumerate()
        .min_by(|a, b| {
            let da = (f64::from(*a.1) - size).abs();
            let db = (f64::from(*b.1) - size).abs();
            da.total_cmp(&db)
        })
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
    fn 文字の大きさは近いものを選ぶ() {
        let sizes = font_sizes();
        assert_eq!(sizes[nearest_font_size(&sizes, 15.4)], 15);
        assert_eq!(
            sizes[nearest_font_size(&sizes, 100.0)],
            *sizes.last().unwrap()
        );
    }
}
