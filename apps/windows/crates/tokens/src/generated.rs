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
        pub const THEME_EDITOR_WIDTH: f32 = 640.0;
        pub const THEME_EDITOR_HEIGHT: f32 = 720.0;
        pub const USER_DICTIONARY_TABLE_HEIGHT: f32 = 330.0;
        pub const PREVIEW_PADDING: f32 = 24.0;
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
    }
    pub mod handwriting {
        pub const WIDTH: f32 = 360.0;
        pub const HEIGHT: f32 = 330.0;
        pub const CANVAS_HEIGHT: f32 = 260.0;
        pub const STROKE_WIDTH: f32 = 5.0;
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
}
