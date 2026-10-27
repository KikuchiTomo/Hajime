#![forbid(unsafe_code)]

//! 色．OS のアプリ モード(ライト・ダーク)と高コントラストに合わせる．
//! 色は design/tokens の settings-windows，高コントラストのときは OS の色を使う

use super::ffi;
use tokens::{settings_windows, Rgb, SettingsPalette};
use windows::Win32::Graphics::Gdi::{
    COLOR_BTNFACE, COLOR_BTNTEXT, COLOR_GRAYTEXT, COLOR_HIGHLIGHT, COLOR_HIGHLIGHTTEXT,
    COLOR_HOTLIGHT, COLOR_WINDOW, COLOR_WINDOWTEXT,
};

/// 描くときの色(0〜1 の成分と濃さ)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Color {
    pub red: f32,
    pub green: f32,
    pub blue: f32,
    pub alpha: f32,
}

impl Color {
    pub fn with_alpha(self, alpha: f32) -> Self {
        Self {
            alpha: self.alpha * alpha.clamp(0.0, 1.0),
            ..self
        }
    }

    /// self から other へ t(0〜1)だけ寄せた色
    pub fn mix(self, other: Color, t: f32) -> Self {
        let t = t.clamp(0.0, 1.0);
        let blend = |a: f32, b: f32| a + (b - a) * t;
        Self {
            red: blend(self.red, other.red),
            green: blend(self.green, other.green),
            blue: blend(self.blue, other.blue),
            alpha: blend(self.alpha, other.alpha),
        }
    }
}

impl From<Rgb> for Color {
    fn from(color: Rgb) -> Self {
        Self {
            red: f32::from(color.red) / 255.0,
            green: f32::from(color.green) / 255.0,
            blue: f32::from(color.blue) / 255.0,
            alpha: 1.0,
        }
    }
}

/// 絵の書体(Segoe Fluent Icons・Segoe MDL2 Assets)の字．2 つの書体で同じ番号
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Glyphs {
    pub chevron_down: &'static str,
    pub check: &'static str,
    pub undo: &'static str,
    pub search: &'static str,
    pub warning: &'static str,
}

pub const GLYPHS: Glyphs = Glyphs {
    chevron_down: "\u{E70D}",
    check: "\u{E73E}",
    undo: "\u{E7A7}",
    search: "\u{E721}",
    warning: "\u{E7BA}",
};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Theme {
    pub palette: SettingsPalette,
    pub dark: bool,
    pub high_contrast: bool,
    pub dpi: u32,
    pub glyphs: Glyphs,
}

impl Theme {
    /// OS の設定を読んで決める
    pub fn load(dpi: u32) -> Self {
        let high_contrast = ffi::high_contrast();
        let dark = !high_contrast && ffi::apps_use_dark();
        let palette = if high_contrast {
            system_palette()
        } else if dark {
            settings_windows::DARK
        } else {
            settings_windows::LIGHT
        };
        Self {
            palette,
            dark,
            high_contrast,
            dpi,
            glyphs: GLYPHS,
        }
    }

    /// OS の設定を読まずに決める(見本の書き出しとテスト)
    pub fn fixed(dark: bool, dpi: u32) -> Self {
        Self {
            palette: if dark {
                settings_windows::DARK
            } else {
                settings_windows::LIGHT
            },
            dark,
            high_contrast: false,
            dpi,
            glyphs: GLYPHS,
        }
    }

    /// 96dpi の値を窓の DPI のピクセルにする
    pub fn px(&self, value: f32) -> i32 {
        ffi::scale(value, self.dpi)
    }

    /// 窓の DPI のピクセルを 96dpi の値にする
    pub fn dip(&self, pixels: i32) -> f32 {
        pixels as f32 * ffi::BASE_DPI as f32 / self.dpi as f32
    }

    /// フォーカスの印の外側の線(背景と反対の色)
    pub fn focus_outer(&self) -> Color {
        Color::from(self.palette.text)
    }

    /// フォーカスの印の内側の線(背景と同じ明るさ)
    pub fn focus_inner(&self) -> Color {
        Color::from(self.palette.background)
    }
}

/// 高コントラストのときの色．OS の色をそのまま使う
fn system_palette() -> SettingsPalette {
    let window = ffi::system_color(COLOR_WINDOW);
    let text = ffi::system_color(COLOR_WINDOWTEXT);
    let highlight = ffi::system_color(COLOR_HIGHLIGHT);
    let highlight_text = ffi::system_color(COLOR_HIGHLIGHTTEXT);
    let gray = ffi::system_color(COLOR_GRAYTEXT);
    let face = ffi::system_color(COLOR_BTNFACE);
    let face_text = ffi::system_color(COLOR_BTNTEXT);
    let link = ffi::system_color(COLOR_HOTLIGHT);
    SettingsPalette {
        accent: highlight,
        accent_hover: link,
        accent_pressed: highlight,
        accent_text: highlight_text,
        background: window,
        card: window,
        card_stroke: text,
        caution: text,
        control: face,
        control_hover: face,
        control_pressed: face,
        control_stroke: face_text,
        control_strong_stroke: face_text,
        flyout: window,
        flyout_stroke: text,
        nav_hover: window,
        nav_pressed: window,
        nav_selected: highlight,
        scrollbar: text,
        switch_off: gray,
        text,
        text_disabled: gray,
        text_secondary: text,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 色を寄せる() {
        let black = Color::from(Rgb {
            red: 0,
            green: 0,
            blue: 0,
        });
        let white = Color::from(Rgb {
            red: 255,
            green: 255,
            blue: 255,
        });
        let middle = black.mix(white, 0.5);
        assert!((middle.red - 0.5).abs() < 1e-6);
        assert_eq!(black.mix(white, 2.0), white);
        assert_eq!(white.with_alpha(0.5).alpha, 0.5);
    }

    #[test]
    fn 窓の_dpi_と_96dpi_の値を行き来する() {
        let theme = Theme::fixed(true, 144);
        assert_eq!(theme.px(10.0), 15);
        assert_eq!(theme.dip(15), 10.0);
    }
}
