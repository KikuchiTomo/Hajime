#![forbid(unsafe_code)]

#[rustfmt::skip]
mod generated;

pub use generated::*;

pub fn palette(theme: &str) -> Palette {
    THEMES
        .iter()
        .find(|(name, _)| *name == theme)
        .unwrap_or(&THEMES[0])
        .1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 名前でテーマの色を引く() {
        let (name, desk) = THEMES[1];
        assert_eq!(palette(name), desk);
    }

    #[test]
    fn 知らないテーマは最初のテーマにする() {
        assert_eq!(palette("automatic"), THEMES[0].1);
        assert_eq!(palette("native"), THEMES[0].1);
    }
}
