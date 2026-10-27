#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Rgb {
    pub red: u8,
    pub green: u8,
    pub blue: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Palette {
    pub bevel_light: Rgb,
    pub bevel_shadow: Rgb,
    pub correction: Rgb,
    pub frame: Rgb,
    pub prediction: Rgb,
    pub selection: Rgb,
    pub selection_text: Rgb,
    pub surface: Rgb,
    pub text: Rgb,
    pub text_muted: Rgb,
}

pub const THEMES: &[(&str, Palette)] = &[
    ("standard", Palette {
        bevel_light: Rgb { red: 0x1E, green: 0x1E, blue: 0x1E },
        bevel_shadow: Rgb { red: 0x1E, green: 0x1E, blue: 0x1E },
        correction: Rgb { red: 0xFF, green: 0x37, blue: 0x5F },
        frame: Rgb { red: 0xA9, green: 0xA8, blue: 0xB6 },
        prediction: Rgb { red: 0xA9, green: 0xA8, blue: 0xB6 },
        selection: Rgb { red: 0x01, green: 0x69, blue: 0xFF },
        selection_text: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        surface: Rgb { red: 0x1E, green: 0x1E, blue: 0x1E },
        text: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        text_muted: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
    }),
    ("platinum", Palette {
        bevel_light: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        bevel_shadow: Rgb { red: 0x99, green: 0x99, blue: 0x99 },
        correction: Rgb { red: 0xCC, green: 0x33, blue: 0x66 },
        frame: Rgb { red: 0x00, green: 0x00, blue: 0x00 },
        prediction: Rgb { red: 0x66, green: 0x66, blue: 0x66 },
        selection: Rgb { red: 0x33, green: 0x66, blue: 0x99 },
        selection_text: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        surface: Rgb { red: 0xDD, green: 0xDD, blue: 0xDD },
        text: Rgb { red: 0x00, green: 0x00, blue: 0x00 },
        text_muted: Rgb { red: 0x55, green: 0x55, blue: 0x55 },
    }),
    ("desk", Palette {
        bevel_light: Rgb { red: 0x44, green: 0x22, blue: 0x77 },
        bevel_shadow: Rgb { red: 0x11, green: 0x00, blue: 0x22 },
        correction: Rgb { red: 0x33, green: 0xFF, blue: 0xCC },
        frame: Rgb { red: 0x00, green: 0x00, blue: 0x00 },
        prediction: Rgb { red: 0x99, green: 0x77, blue: 0xBB },
        selection: Rgb { red: 0xFF, green: 0x33, blue: 0x99 },
        selection_text: Rgb { red: 0x22, green: 0x00, blue: 0x44 },
        surface: Rgb { red: 0x22, green: 0x00, blue: 0x44 },
        text: Rgb { red: 0xFF, green: 0xCC, blue: 0x66 },
        text_muted: Rgb { red: 0x99, green: 0x77, blue: 0xBB },
    }),
    ("washi", Palette {
        bevel_light: Rgb { red: 0xFF, green: 0xFB, blue: 0xF2 },
        bevel_shadow: Rgb { red: 0xD8, green: 0xCD, blue: 0xB8 },
        correction: Rgb { red: 0x1D, green: 0x4E, blue: 0x89 },
        frame: Rgb { red: 0xC9, green: 0xBC, blue: 0xA3 },
        prediction: Rgb { red: 0x6B, green: 0x5F, blue: 0x53 },
        selection: Rgb { red: 0xB3, green: 0x26, blue: 0x2D },
        selection_text: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        surface: Rgb { red: 0xF5, green: 0xEF, blue: 0xE3 },
        text: Rgb { red: 0x2A, green: 0x24, blue: 0x20 },
        text_muted: Rgb { red: 0x6B, green: 0x5F, blue: 0x53 },
    }),
    ("neon", Palette {
        bevel_light: Rgb { red: 0x2B, green: 0x24, blue: 0x59 },
        bevel_shadow: Rgb { red: 0x1C, green: 0x17, blue: 0x40 },
        correction: Rgb { red: 0x2E, green: 0xE6, blue: 0xFF },
        frame: Rgb { red: 0x3D, green: 0x34, blue: 0x80 },
        prediction: Rgb { red: 0xA6, green: 0x9E, blue: 0xDB },
        selection: Rgb { red: 0xFF, green: 0x2E, blue: 0x93 },
        selection_text: Rgb { red: 0x14, green: 0x00, blue: 0x1F },
        surface: Rgb { red: 0x0E, green: 0x0B, blue: 0x22 },
        text: Rgb { red: 0xF1, green: 0xEE, blue: 0xFF },
        text_muted: Rgb { red: 0xA6, green: 0x9E, blue: 0xDB },
    }),
    ("terminal", Palette {
        bevel_light: Rgb { red: 0x1E, green: 0x35, blue: 0x22 },
        bevel_shadow: Rgb { red: 0x15, green: 0x26, blue: 0x1A },
        correction: Rgb { red: 0xFF, green: 0xD4, blue: 0x4D },
        frame: Rgb { red: 0x2E, green: 0x55, blue: 0x34 },
        prediction: Rgb { red: 0x5D, green: 0xB8, blue: 0x6C },
        selection: Rgb { red: 0x86, green: 0xF5, blue: 0x9A },
        selection_text: Rgb { red: 0x0A, green: 0x11, blue: 0x0B },
        surface: Rgb { red: 0x0A, green: 0x11, blue: 0x0B },
        text: Rgb { red: 0x86, green: 0xF5, blue: 0x9A },
        text_muted: Rgb { red: 0x5D, green: 0xB8, blue: 0x6C },
    }),
    ("nordic", Palette {
        bevel_light: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        bevel_shadow: Rgb { red: 0xD7, green: 0xDE, blue: 0xE1 },
        correction: Rgb { red: 0xB5, green: 0x57, blue: 0x3A },
        frame: Rgb { red: 0xC5, green: 0xCF, blue: 0xD4 },
        prediction: Rgb { red: 0x5D, green: 0x6C, blue: 0x77 },
        selection: Rgb { red: 0x41, green: 0x70, blue: 0x9C },
        selection_text: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        surface: Rgb { red: 0xF4, green: 0xF6, blue: 0xF6 },
        text: Rgb { red: 0x24, green: 0x30, blue: 0x3A },
        text_muted: Rgb { red: 0x5D, green: 0x6C, blue: 0x77 },
    }),
    ("contrast", Palette {
        bevel_light: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        bevel_shadow: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        correction: Rgb { red: 0x00, green: 0xE5, blue: 0xFF },
        frame: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        prediction: Rgb { red: 0xE6, green: 0xE6, blue: 0xE6 },
        selection: Rgb { red: 0xFF, green: 0xE6, blue: 0x00 },
        selection_text: Rgb { red: 0x00, green: 0x00, blue: 0x00 },
        surface: Rgb { red: 0x00, green: 0x00, blue: 0x00 },
        text: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        text_muted: Rgb { red: 0xE6, green: 0xE6, blue: 0xE6 },
    }),
];

pub const GLASS_LIGHT: Palette = Palette {
    bevel_light: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
    bevel_shadow: Rgb { red: 0xE5, green: 0xE5, blue: 0xE5 },
    correction: Rgb { red: 0xD6, green: 0x00, blue: 0x5A },
    frame: Rgb { red: 0xE5, green: 0xE5, blue: 0xE5 },
    prediction: Rgb { red: 0x5D, green: 0x5D, blue: 0x5D },
    selection: Rgb { red: 0x00, green: 0x5F, blue: 0xB8 },
    selection_text: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
    surface: Rgb { red: 0xF9, green: 0xF9, blue: 0xF9 },
    text: Rgb { red: 0x1A, green: 0x1A, blue: 0x1A },
    text_muted: Rgb { red: 0x5D, green: 0x5D, blue: 0x5D },
};

pub const GLASS_DARK: Palette = Palette {
    bevel_light: Rgb { red: 0x3B, green: 0x3B, blue: 0x3B },
    bevel_shadow: Rgb { red: 0x1F, green: 0x1F, blue: 0x1F },
    correction: Rgb { red: 0xFF, green: 0x6F, blue: 0xA5 },
    frame: Rgb { red: 0x45, green: 0x45, blue: 0x45 },
    prediction: Rgb { red: 0xC5, green: 0xC5, blue: 0xC5 },
    selection: Rgb { red: 0x60, green: 0xCD, blue: 0xFF },
    selection_text: Rgb { red: 0x00, green: 0x00, blue: 0x00 },
    surface: Rgb { red: 0x2C, green: 0x2C, blue: 0x2C },
    text: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
    text_muted: Rgb { red: 0xC5, green: 0xC5, blue: 0xC5 },
};

pub const GLASS_SHADOW: Rgb = Rgb { red: 0x00, green: 0x00, blue: 0x00 };

pub const GLASS_SNAPSHOT_LIGHT: Rgb = Rgb { red: 0x9F, green: 0x9F, blue: 0x9F };

pub const GLASS_SNAPSHOT_DARK: Rgb = Rgb { red: 0x26, green: 0x26, blue: 0x26 };

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SettingsPalette {
    pub accent: Rgb,
    pub accent_hover: Rgb,
    pub accent_pressed: Rgb,
    pub accent_text: Rgb,
    pub background: Rgb,
    pub card: Rgb,
    pub card_stroke: Rgb,
    pub caution: Rgb,
    pub control: Rgb,
    pub control_hover: Rgb,
    pub control_pressed: Rgb,
    pub control_stroke: Rgb,
    pub control_strong_stroke: Rgb,
    pub flyout: Rgb,
    pub flyout_stroke: Rgb,
    pub nav_hover: Rgb,
    pub nav_pressed: Rgb,
    pub nav_selected: Rgb,
    pub scrollbar: Rgb,
    pub switch_off: Rgb,
    pub text: Rgb,
    pub text_disabled: Rgb,
    pub text_secondary: Rgb,
}

pub mod settings_windows {
    use super::{Rgb, SettingsPalette};

    pub const LIGHT: SettingsPalette = SettingsPalette {
        accent: Rgb { red: 0x00, green: 0x5F, blue: 0xB8 },
        accent_hover: Rgb { red: 0x1A, green: 0x6F, blue: 0xBF },
        accent_pressed: Rgb { red: 0x33, green: 0x83, blue: 0xCA },
        accent_text: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        background: Rgb { red: 0xF3, green: 0xF3, blue: 0xF3 },
        card: Rgb { red: 0xFB, green: 0xFB, blue: 0xFB },
        card_stroke: Rgb { red: 0xE5, green: 0xE5, blue: 0xE5 },
        caution: Rgb { red: 0x9D, green: 0x5D, blue: 0x00 },
        control: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        control_hover: Rgb { red: 0xF9, green: 0xF9, blue: 0xF9 },
        control_pressed: Rgb { red: 0xF5, green: 0xF5, blue: 0xF5 },
        control_stroke: Rgb { red: 0xC4, green: 0xC4, blue: 0xC4 },
        control_strong_stroke: Rgb { red: 0x8A, green: 0x8A, blue: 0x8A },
        flyout: Rgb { red: 0xF9, green: 0xF9, blue: 0xF9 },
        flyout_stroke: Rgb { red: 0xD9, green: 0xD9, blue: 0xD9 },
        nav_hover: Rgb { red: 0xED, green: 0xED, blue: 0xED },
        nav_pressed: Rgb { red: 0xE5, green: 0xE5, blue: 0xE5 },
        nav_selected: Rgb { red: 0xEA, green: 0xEA, blue: 0xEA },
        scrollbar: Rgb { red: 0x8A, green: 0x8A, blue: 0x8A },
        switch_off: Rgb { red: 0x7A, green: 0x7A, blue: 0x7A },
        text: Rgb { red: 0x1B, green: 0x1B, blue: 0x1B },
        text_disabled: Rgb { red: 0xA0, green: 0xA0, blue: 0xA0 },
        text_secondary: Rgb { red: 0x5F, green: 0x5F, blue: 0x5F },
    };
    pub const DARK: SettingsPalette = SettingsPalette {
        accent: Rgb { red: 0x60, green: 0xCD, blue: 0xFF },
        accent_hover: Rgb { red: 0x57, green: 0xBF, blue: 0xEB },
        accent_pressed: Rgb { red: 0x4E, green: 0xAA, blue: 0xD3 },
        accent_text: Rgb { red: 0x00, green: 0x00, blue: 0x00 },
        background: Rgb { red: 0x20, green: 0x20, blue: 0x20 },
        card: Rgb { red: 0x2B, green: 0x2B, blue: 0x2B },
        card_stroke: Rgb { red: 0x1D, green: 0x1D, blue: 0x1D },
        caution: Rgb { red: 0xFC, green: 0xE1, blue: 0x00 },
        control: Rgb { red: 0x37, green: 0x37, blue: 0x37 },
        control_hover: Rgb { red: 0x3C, green: 0x3C, blue: 0x3C },
        control_pressed: Rgb { red: 0x32, green: 0x32, blue: 0x32 },
        control_stroke: Rgb { red: 0x4A, green: 0x4A, blue: 0x4A },
        control_strong_stroke: Rgb { red: 0x9A, green: 0x9A, blue: 0x9A },
        flyout: Rgb { red: 0x2C, green: 0x2C, blue: 0x2C },
        flyout_stroke: Rgb { red: 0x3D, green: 0x3D, blue: 0x3D },
        nav_hover: Rgb { red: 0x29, green: 0x29, blue: 0x29 },
        nav_pressed: Rgb { red: 0x26, green: 0x26, blue: 0x26 },
        nav_selected: Rgb { red: 0x2D, green: 0x2D, blue: 0x2D },
        scrollbar: Rgb { red: 0x9F, green: 0x9F, blue: 0x9F },
        switch_off: Rgb { red: 0x9A, green: 0x9A, blue: 0x9A },
        text: Rgb { red: 0xFF, green: 0xFF, blue: 0xFF },
        text_disabled: Rgb { red: 0x78, green: 0x78, blue: 0x78 },
        text_secondary: Rgb { red: 0xCF, green: 0xCF, blue: 0xCF },
    };
}

pub mod size {
    pub mod candidate {
        pub const ROW_HEIGHT: f32 = 22.0;
        pub const FONT_SIZE: f32 = 15.0;
        pub const FONT_SIZE_MIN: f32 = 12.0;
        pub const FONT_SIZE_MAX: f32 = 24.0;
        pub const INDEX_WIDTH: f32 = 18.0;
        pub const PADDING_X: f32 = 8.0;
        pub const FRAME_WIDTH: f32 = 1.0;
        pub const BEVEL_WIDTH: f32 = 1.0;
        pub const MAX_VISIBLE: f32 = 9.0;
        pub const SHADOW_OFFSET: f32 = 2.0;
        pub const LABEL_FONT_SIZE: f32 = 11.0;
        pub const VARIANT_PADDING_X: f32 = 6.0;
        pub const SECTION_PADDING_Y: f32 = 3.0;
        pub const MIN_WIDTH: f32 = 180.0;
        pub const VARIANT_INSET_Y: f32 = 1.0;
    }
    pub mod mode_indicator {
        pub const FONT_SIZE: f32 = 14.0;
        pub const PADDING_X: f32 = 10.0;
        pub const PADDING_Y: f32 = 3.0;
    }
    pub mod branch {
        pub const TRUNK_GAP: f32 = 10.0;
        pub const BRANCH_INDENT: f32 = 14.0;
        pub const BRANCH_STEM_X: f32 = 5.0;
        pub const LINE_WIDTH: f32 = 1.0;
        pub const LINE_WIDTH_SELECTED: f32 = 2.0;
        pub const UNDERLINE_OFFSET: f32 = 2.0;
        pub const SPLIT_BADGE_SIZE: f32 = 13.0;
        pub const SPLIT_BADGE_FONT_SIZE: f32 = 9.0;
        pub const SPLIT_BADGE_GAP: f32 = 2.0;
    }
    pub mod settings {
        pub const WINDOW_WIDTH: f32 = 820.0;
        pub const WINDOW_HEIGHT: f32 = 580.0;
        pub const SIDEBAR_WIDTH: f32 = 190.0;
        pub const KEYMAP_STATE_WIDTH: f32 = 120.0;
        pub const KEYMAP_KEY_WIDTH: f32 = 150.0;
        pub const KEYMAP_MARK_WIDTH: f32 = 22.0;
        pub const KEYMAP_CAPTURE_HEIGHT: f32 = 22.0;
        pub const RULE_TABLE_HEIGHT: f32 = 220.0;
        pub const RULE_SEARCH_WIDTH: f32 = 160.0;
        pub const RULE_CHECK_COLUMN_WIDTH: f32 = 40.0;
        pub const RULE_KEY_COLUMN_WIDTH: f32 = 160.0;
        pub const RULE_PROFILE_COLUMN_WIDTH: f32 = 170.0;
        pub const TABLE_HEADER_INSET: f32 = 10.0;
        pub const TABLE_COLUMN_SPACING: f32 = 17.0;
        pub const TABLE_POPUP_TEXT_INSET: f32 = 21.0;
        pub const THEME_EDITOR_WIDTH: f32 = 640.0;
        pub const THEME_EDITOR_HEIGHT: f32 = 720.0;
        pub const USER_DICTIONARY_TABLE_HEIGHT: f32 = 330.0;
        pub const PREVIEW_PADDING: f32 = 24.0;
        pub const KEY_FILTER_RADIUS: f32 = 5.0;
        pub const FONT_SLIDER_WIDTH: f32 = 220.0;
        pub const SECONDS_SLIDER_WIDTH: f32 = 180.0;
        pub const SECONDS_LABEL_WIDTH: f32 = 52.0;
        pub const THEME_SWATCH_WIDTH: f32 = 40.0;
        pub const THEME_SWATCH_HEIGHT: f32 = 20.0;
        pub const THEME_SWATCH_GAP: f32 = 3.0;
        pub const THEME_SWATCH_FONT_SIZE: f32 = 11.0;
        pub const THEME_SWATCH_SELECTION_WIDTH: f32 = 12.0;
        pub const THEME_SWATCH_SELECTION_HEIGHT: f32 = 10.0;
        pub const THEME_SWATCH_RADIUS: f32 = 6.0;
    }
    pub mod glass {
        pub const CORNER_RADIUS: f32 = 12.0;
        pub const PADDING: f32 = 10.0;
        pub const ROW_HEIGHT: f32 = 28.0;
        pub const LABEL_FONT_SIZE: f32 = 11.5;
        pub const KEY_FONT_SIZE: f32 = 10.5;
        pub const BADGE_SIZE: f32 = 17.0;
        pub const SELECTION_RADIUS: f32 = 7.0;
        pub const KEYCAP_RADIUS: f32 = 4.0;
        pub const KEYCAP_PADDING_X: f32 = 5.0;
        pub const KEYCAP_HEIGHT: f32 = 17.0;
        pub const HINT_GAP: f32 = 10.0;
        pub const FOOTER_HEIGHT: f32 = 28.0;
        pub const TRUNK_GAP: f32 = 6.0;
        pub const BRANCH_INDENT: f32 = 28.0;
        pub const BRANCH_STEM_X: f32 = 12.0;
        pub const LINE_WIDTH: f32 = 1.5;
        pub const LINE_WIDTH_SELECTED: f32 = 2.0;
        pub const UNDERLINE_OFFSET: f32 = 4.0;
        pub const MODE_INDICATOR_SIZE: f32 = 34.0;
        pub const MODE_INDICATOR_FONT_SIZE: f32 = 17.0;
        pub const SELECTION_INSET_Y: f32 = 2.0;
        pub const VARIANT_INSET_Y: f32 = 4.0;
        pub const CURVE_START_OVERLAP: f32 = 2.0;
        pub const CURVE_END_GAP: f32 = 3.0;
        pub const CURVE_BEND: f32 = 0.35;
        pub const DOT_PITCH: f32 = 5.0;
        pub const KEYCAP_PART_GAP: f32 = 1.0;
        pub const SHADOW_RADIUS: f32 = 12.0;
        pub const SHADOW_OFFSET_Y: f32 = 3.0;
        pub const TAG_HEIGHT: f32 = 16.0;
        pub const TAG_PADDING_X: f32 = 6.0;
        pub const TAG_RADIUS: f32 = 8.0;
        pub const NOTE_ICON_SIZE: f32 = 18.0;
        pub const NOTE_GAP: f32 = 6.0;
    }
    pub mod handwriting {
        pub const WIDTH: f32 = 284.0;
        pub const HEIGHT: f32 = 332.0;
        pub const CANVAS_SIZE: f32 = 260.0;
        pub const CANVAS_PADDING: f32 = 12.0;
        pub const STROKE_WIDTH: f32 = 5.0;
        pub const FRAME_WIDTH: f32 = 1.0;
        pub const GUIDE_DASH: f32 = 4.0;
        pub const ANCHOR_GAP: f32 = 4.0;
        pub const CANDIDATE_GAP: f32 = 6.0;
        pub const CANDIDATE_FONT_SIZE: f32 = 18.0;
    }
    pub mod snapshot {
        pub const MARGIN: f32 = 16.0;
        pub const SCALE: f32 = 2.0;
    }
    pub mod settings_windows {
        pub const PAGE_PADDING_X: f32 = 36.0;
        pub const SCROLL_LINE: f32 = 40.0;
        pub const LIST_HEIGHT: f32 = 220.0;
        pub const BUTTON_WIDTH: f32 = 96.0;
        pub const PREVIEW_HEIGHT: f32 = 240.0;
        pub const BUTTON_PADDING_X: f32 = 12.0;
        pub const PAGE_PADDING_TOP: f32 = 20.0;
        pub const TITLE_FONT_SIZE: f32 = 28.0;
        pub const SECTION_FONT_SIZE: f32 = 14.0;
        pub const BODY_FONT_SIZE: f32 = 14.0;
        pub const CAPTION_FONT_SIZE: f32 = 12.0;
        pub const ICON_FONT_SIZE: f32 = 16.0;
        pub const SECTION_GAP: f32 = 28.0;
        pub const SECTION_TITLE_HEIGHT: f32 = 28.0;
        pub const CARD_GAP: f32 = 4.0;
        pub const CARD_RADIUS: f32 = 4.0;
        pub const CARD_PADDING_X: f32 = 16.0;
        pub const ROW_HEIGHT: f32 = 52.0;
        pub const CONTROL_HEIGHT: f32 = 32.0;
        pub const DROPDOWN_HEIGHT: f32 = 384.0;
        pub const CONTROL_WIDTH: f32 = 240.0;
        pub const SWITCH_WIDTH: f32 = 40.0;
        pub const SWITCH_HEIGHT: f32 = 20.0;
        pub const RESET_SIZE: f32 = 28.0;
        pub const NAV_ITEM_HEIGHT: f32 = 36.0;
        pub const NAV_HEADER_HEIGHT: f32 = 32.0;
        pub const NAV_PADDING_X: f32 = 12.0;
        pub const NAV_INDICATOR_WIDTH: f32 = 3.0;
        pub const NAV_INDICATOR_HEIGHT: f32 = 16.0;
        pub const NAV_ICON_GAP: f32 = 12.0;
        pub const SEARCH_HEIGHT: f32 = 32.0;
        pub const NOTE_LINE_HEIGHT: f32 = 18.0;
        pub const TITLE_HEIGHT: f32 = 52.0;
        pub const BODY_LINE_HEIGHT: f32 = 20.0;
        pub const CONTENT_MAX_WIDTH: f32 = 1000.0;
        pub const CONTROL_GAP: f32 = 8.0;
        pub const TOGGLE_WIDTH: f32 = 96.0;
        pub const STEPPER_WIDTH: f32 = 96.0;
        pub const SECONDS_LABEL_WIDTH: f32 = 56.0;
        pub const NAV_WIDTH: f32 = 280.0;
        pub const WINDOW_WIDTH: f32 = 1000.0;
        pub const WINDOW_HEIGHT: f32 = 700.0;
        pub const WINDOW_MIN_WIDTH: f32 = 640.0;
        pub const WINDOW_MIN_HEIGHT: f32 = 480.0;
        pub const NAV_GROUP_GAP: f32 = 12.0;
        pub const NAV_HEADER_FONT_SIZE: f32 = 12.0;
        pub const CONTROL_RADIUS: f32 = 4.0;
        pub const FIELD_PADDING_X: f32 = 11.0;
        pub const FOCUS_STROKE: f32 = 2.0;
        pub const CHEVRON_SIZE: f32 = 12.0;
        pub const FLYOUT_PADDING: f32 = 4.0;
        pub const FLYOUT_ITEM_HEIGHT: f32 = 32.0;
        pub const FLYOUT_RADIUS: f32 = 8.0;
        pub const TABLE_ROW_HEIGHT: f32 = 30.0;
        pub const TABLE_HEADER_HEIGHT: f32 = 32.0;
        pub const SCROLLBAR_THIN: f32 = 2.0;
        pub const SCROLLBAR_WIDE: f32 = 6.0;
        pub const SCROLLBAR_MARGIN: f32 = 3.0;
        pub const SCROLLBAR_HIT: f32 = 14.0;
        pub const SCROLLBAR_MIN_THUMB: f32 = 24.0;
        pub const PROGRESS_RING_SIZE: f32 = 32.0;
        pub const PROGRESS_RING_STROKE: f32 = 3.0;
        pub const PAGE_ENTER_OFFSET: f32 = 12.0;
        pub const WHEEL_STEP: f32 = 48.0;
    }
    pub mod standard_theme {
        pub const CORNER_RADIUS: f32 = 12.0;
    }
    pub mod onboarding {
        pub const WIDTH: f32 = 900.0;
        pub const HEIGHT: f32 = 600.0;
        pub const STAGE_WIDTH: f32 = 440.0;
        pub const PADDING: f32 = 36.0;
        pub const STAGE_PADDING: f32 = 28.0;
        pub const CARD_RADIUS: f32 = 12.0;
        pub const CARD_PADDING: f32 = 14.0;
        pub const CARD_GAP: f32 = 10.0;
        pub const DOT_SIZE: f32 = 7.0;
        pub const DOT_GAP: f32 = 6.0;
        pub const FIELD_HEIGHT: f32 = 46.0;
        pub const FIELD_RADIUS: f32 = 10.0;
        pub const FIELD_FONT_SIZE: f32 = 19.0;
        pub const DEMO_GAP: f32 = 14.0;
        pub const BADGE_RADIUS: f32 = 6.0;
    }
}

pub mod motion {
    pub mod mode_indicator {
        pub const VISIBLE: f32 = 800.0;
        pub const FADE: f32 = 120.0;
    }
    pub mod correction_underline {
        pub const APPEAR: f32 = 80.0;
    }
    pub mod candidate_rest {
        pub const FADE_IN: f32 = 250.0;
    }
    pub mod settings_windows {
        pub const PAGE_ENTER: f32 = 167.0;
        pub const HOVER: f32 = 83.0;
        pub const TOGGLE: f32 = 167.0;
        pub const FLYOUT: f32 = 167.0;
        pub const NAV_INDICATOR: f32 = 167.0;
        pub const SCROLL: f32 = 200.0;
        pub const SCROLLBAR_IDLE: f32 = 1200.0;
        pub const SCROLLBAR_FADE: f32 = 250.0;
        pub const PROGRESS_RING: f32 = 1400.0;
    }
    pub mod onboarding {
        pub const KEYSTROKE: f32 = 85.0;
        pub const HOLD: f32 = 1400.0;
        pub const PAGE: f32 = 220.0;
    }
}

pub mod opacity {
    pub mod glass {
        pub const LINE: f32 = 0.26;
        pub const LINE_CONTRAST: f32 = 0.5;
        pub const BADGE: f32 = 0.1;
        pub const BADGE_CONTRAST: f32 = 0.26;
        pub const FOCUS_TINT: f32 = 0.16;
        pub const FOCUS_TINT_CONTRAST: f32 = 0.3;
        pub const CORRECTION_TAG: f32 = 0.16;
        pub const CORRECTION_TAG_CONTRAST: f32 = 0.3;
    }
    pub mod rounded {
        pub const BADGE: f32 = 0.12;
        pub const BADGE_CONTRAST: f32 = 0.25;
        pub const FOCUS_TINT: f32 = 0.2;
        pub const FOCUS_TINT_CONTRAST: f32 = 0.35;
    }
    pub mod badge {
        pub const SELECTED: f32 = 0.25;
    }
    pub mod variant {
        pub const UNAVAILABLE: f32 = 0.4;
    }
    pub mod keycap {
        pub const DESK_FILL: f32 = 0.12;
        pub const DESK_STROKE: f32 = 0.6;
    }
    pub mod shadow {
        pub const WINDOW: f32 = 0.22;
    }
    pub mod settings {
        pub const KEY_FILTER: f32 = 0.15;
        pub const SUBTLE_SELECTED: f32 = 0.08;
        pub const SUBTLE_HOVER: f32 = 0.05;
    }
    pub mod onboarding {
        pub const STAGE_GLOW: f32 = 0.32;
        pub const STAGE_GLOW_SECONDARY: f32 = 0.18;
        pub const CARD_SELECTED: f32 = 0.12;
        pub const CARD_IDLE: f32 = 0.05;
        pub const FIELD: f32 = 0.82;
    }
}
