#![forbid(unsafe_code)]

//! 色と書体．OS のアプリ モード(ライト・ダーク)と高コントラストに合わせる．
//! 色は design/tokens の settings-windows，高コントラストのときは OS の色を使う

use super::ffi::{self, Brush, Font, Window};
use tokens::size::settings_windows as size;
use tokens::{settings_windows, SettingsPalette};
use windows::Win32::Graphics::Gdi::{
    COLOR_BTNFACE, COLOR_BTNTEXT, COLOR_GRAYTEXT, COLOR_HIGHLIGHT, COLOR_HIGHLIGHTTEXT,
    COLOR_WINDOW, COLOR_WINDOWTEXT,
};

const TEXT_FACE: &str = "Yu Gothic UI";
/// Windows 11 の絵の書体．無ければ Windows 10 の書体
const ICON_FACES: [&str; 2] = ["Segoe Fluent Icons", "Segoe MDL2 Assets"];

pub struct Fonts {
    pub title: Font,
    pub section: Font,
    pub body: Font,
    pub caption: Font,
    pub icon: Option<Font>,
}

pub struct Theme {
    pub palette: SettingsPalette,
    pub dark: bool,
    pub high_contrast: bool,
    pub background: Brush,
    pub card: Brush,
    pub control: Brush,
    pub fonts: Fonts,
    pub dpi: u32,
}

impl Theme {
    pub fn load(window: Window, dpi: u32) -> Option<Self> {
        let high_contrast = ffi::high_contrast();
        let dark = !high_contrast && ffi::apps_use_dark();
        let palette = if high_contrast {
            system_palette()
        } else if dark {
            settings_windows::DARK
        } else {
            settings_windows::LIGHT
        };
        let px = |value: f32| ffi::scale(value, dpi);
        let fonts = Fonts {
            title: Font::new(TEXT_FACE, px(size::TITLE_FONT_SIZE), true)?,
            section: Font::new(TEXT_FACE, px(size::SECTION_FONT_SIZE), true)?,
            body: Font::new(TEXT_FACE, px(size::BODY_FONT_SIZE), false)?,
            caption: Font::new(TEXT_FACE, px(size::CAPTION_FONT_SIZE), false)?,
            icon: ICON_FACES
                .iter()
                .find_map(|face| Font::installed(window, face, px(size::ICON_FONT_SIZE))),
        };
        Some(Self {
            background: Brush::new(palette.background),
            card: Brush::new(palette.card),
            control: Brush::new(palette.control),
            palette,
            dark,
            high_contrast,
            fonts,
            dpi,
        })
    }

    pub fn px(&self, value: f32) -> i32 {
        ffi::scale(value, self.dpi)
    }

    /// 標準の部品(一覧・ボタン・入力欄)に付ける見た目の名前．ダークのときだけ暗い見た目にする
    pub fn control_theme(&self, combo_or_edit: bool) -> Option<&'static str> {
        match (self.dark, combo_or_edit) {
            (false, _) => None,
            (true, true) => Some("DarkMode_CFD"),
            (true, false) => Some("DarkMode_Explorer"),
        }
    }
}

/// 高コントラストのときの色．OS の色をそのまま使う
fn system_palette() -> SettingsPalette {
    let window = ffi::system_color(COLOR_WINDOW);
    let text = ffi::system_color(COLOR_WINDOWTEXT);
    let highlight = ffi::system_color(COLOR_HIGHLIGHT);
    SettingsPalette {
        accent: highlight,
        accent_text: ffi::system_color(COLOR_HIGHLIGHTTEXT),
        background: window,
        card: window,
        card_stroke: text,
        caution: text,
        control: ffi::system_color(COLOR_BTNFACE),
        control_stroke: ffi::system_color(COLOR_BTNTEXT),
        nav_selected: highlight,
        switch_off: ffi::system_color(COLOR_GRAYTEXT),
        text,
        text_secondary: text,
    }
}
