#![forbid(unsafe_code)]

//! 設定と OS の外観から決めた，描画に使う色と書体(macOS の ResolvedTheme と同じ決め方)．
//!
//! 描き方は 2 通り．
//! - 角丸と曲線の枝(is_rounded): glass と，和紙・ネオン・端末・北欧・高コントラスト．glass だけ地をすりガラスにし，ほかは地を色で塗る
//! - 四角い枠と立体の縁: platinum と desk

use ipc::CustomTheme;
use tokens::{opacity, size, Palette, Rgb};

/// 0〜1 の色．alpha は不透明度
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Color {
    pub red: f32,
    pub green: f32,
    pub blue: f32,
    pub alpha: f32,
}

impl Color {
    pub fn rgb(rgb: Rgb) -> Self {
        Self {
            red: f32::from(rgb.red) / 255.0,
            green: f32::from(rgb.green) / 255.0,
            blue: f32::from(rgb.blue) / 255.0,
            alpha: 1.0,
        }
    }

    pub const CLEAR: Self = Self {
        red: 0.0,
        green: 0.0,
        blue: 0.0,
        alpha: 0.0,
    };

    /// 不透明度を置き換える
    pub fn with_alpha(self, alpha: f32) -> Self {
        Self { alpha, ..self }
    }

    /// 今の不透明度に掛ける(薄く出すとき)
    pub fn faded(self, factor: f32) -> Self {
        Self {
            alpha: self.alpha * factor,
            ..self
        }
    }
}

impl From<&ipc::Color> for Color {
    fn from(color: &ipc::Color) -> Self {
        Self::rgb(Rgb {
            red: color.red,
            green: color.green,
            blue: color.blue,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// すりガラスの地に角丸と曲線の枝．既定
    Glass,
    Platinum,
    Desk,
    Washi,
    Neon,
    Terminal,
    Nordic,
    Contrast,
}

impl Kind {
    /// 設定の値(ThemePreference の rawValue)から．標準(automatic)・古い native・知らない値は glass
    pub fn named(name: &str) -> Self {
        match name {
            "platinum" => Self::Platinum,
            "desk" => Self::Desk,
            "washi" => Self::Washi,
            "neon" => Self::Neon,
            "terminal" => Self::Terminal,
            "nordic" => Self::Nordic,
            "contrast" => Self::Contrast,
            _ => Self::Glass,
        }
    }

    fn token_name(self) -> &'static str {
        match self {
            Self::Glass | Self::Nordic => "nordic",
            Self::Platinum => "platinum",
            Self::Desk => "desk",
            Self::Washi => "washi",
            Self::Neon => "neon",
            Self::Terminal => "terminal",
            Self::Contrast => "contrast",
        }
    }
}

/// 書体の系統．テーマの個性を出す
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Typeface {
    System,
    /// 明朝体(和紙)
    Mincho,
    /// 等幅(端末)
    Monospaced,
    /// 丸みのある書体(ネオン)
    Rounded,
}

/// OS の外観．アプリの層(app)が OS から読んで渡す
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct SystemLook {
    pub dark: bool,
    /// 選択に使うアクセントカラー(ライトとダークで OS が使い分ける色を選んだもの)．読めなければ None
    pub accent: Option<Rgb>,
    /// 「コントラストを上げる」に当たる設定(Windows はハイコントラスト)
    pub increase_contrast: bool,
    /// 地をすりガラスにできるか(Windows 11 の DWM の背景)
    pub backdrop: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ResolvedTheme {
    pub kind: Kind,
    pub surface: Color,
    pub bevel_light: Color,
    pub bevel_shadow: Color,
    pub frame: Color,
    pub text: Color,
    pub text_muted: Color,
    pub selection: Color,
    pub selection_text: Color,
    pub correction: Color,
    /// 枝と区切りの線
    pub line: Color,
    /// 注目している文節の地(角丸のテーマ．選択より弱い色)
    pub focus_tint: Color,
    /// 番号の丸とキーキャップの地
    pub badge: Color,
    pub typeface: Typeface,
    /// 角の丸さ(角丸のテーマ)．カスタムテーマで変わる
    pub corner_radius: f32,
    /// 枝を曲線でなく直線で描く(カスタムテーマ)
    pub straight_branches: bool,
    /// 候補の書体の名前(カスタムテーマ)．None ならテーマの書体
    pub font_name: Option<String>,
    /// 地をすりガラスにする(glass で，OS が背景をぼかせるとき)
    pub backdrop: bool,
}

impl ResolvedTheme {
    /// 設定から描き方を決める．カスタムテーマを使っていれば，元のテーマの描き方に色・書体・形を重ねる
    pub fn resolve(theme: &str, custom: Option<&CustomTheme>, look: &SystemLook) -> Self {
        let Some(custom) = custom else {
            return Self::preset(Kind::named(theme), look);
        };
        let base = Self::preset(Kind::named(&custom.base), look);
        let text = Color::from(&custom.text);
        let selection = Color::from(&custom.selection);
        let line = Color::from(&custom.line);
        Self {
            kind: if base.kind == Kind::Glass {
                Kind::Nordic
            } else {
                base.kind
            },
            surface: Color::from(&custom.surface),
            frame: line,
            text,
            text_muted: Color::from(&custom.text_muted),
            selection,
            selection_text: Color::from(&custom.selection_text),
            correction: Color::from(&custom.correction),
            line,
            focus_tint: selection.with_alpha(opacity::rounded::FOCUS_TINT),
            badge: text.with_alpha(opacity::rounded::BADGE),
            corner_radius: custom.corner_radius as f32,
            straight_branches: custom.straight_branches,
            font_name: custom.font_name.clone().filter(|name| !name.is_empty()),
            backdrop: false,
            ..base
        }
    }

    fn preset(kind: Kind, look: &SystemLook) -> Self {
        let contrast = look.increase_contrast;
        match kind {
            Kind::Glass => Self::glass(look),
            Kind::Platinum | Kind::Desk => Self::bevelled(kind, contrast),
            Kind::Washi => Self::rounded(kind, Typeface::Mincho, contrast),
            Kind::Neon => Self::rounded(kind, Typeface::Rounded, contrast),
            Kind::Terminal => Self::rounded(kind, Typeface::Monospaced, contrast),
            Kind::Nordic => Self::rounded(kind, Typeface::System, contrast),
            Kind::Contrast => Self::rounded(kind, Typeface::System, true),
        }
    }

    /// glass は OS の外観(ライト・ダーク・アクセントカラー)に合わせる．
    /// 「コントラストを上げる」が有効なときは，線と弱い文字と番号の丸を 1 段濃くする
    fn glass(look: &SystemLook) -> Self {
        let palette = if look.dark {
            tokens::GLASS_DARK
        } else {
            tokens::GLASS_LIGHT
        };
        let contrast = look.increase_contrast;
        let text = Color::rgb(palette.text);
        let text_muted = if contrast {
            text
        } else {
            Color::rgb(palette.text_muted)
        };
        let selection = Color::rgb(look.accent.unwrap_or(palette.selection));
        Self {
            kind: Kind::Glass,
            surface: Color::rgb(palette.surface),
            bevel_light: Color::CLEAR,
            bevel_shadow: Color::CLEAR,
            frame: if contrast {
                Color::rgb(palette.text_muted)
            } else {
                Color::rgb(palette.frame)
            },
            text,
            text_muted,
            selection,
            selection_text: Color::rgb(palette.selection_text),
            correction: Color::rgb(palette.correction),
            line: text.with_alpha(if contrast {
                opacity::glass::LINE_CONTRAST
            } else {
                opacity::glass::LINE
            }),
            focus_tint: selection.with_alpha(if contrast {
                opacity::glass::FOCUS_TINT_CONTRAST
            } else {
                opacity::glass::FOCUS_TINT
            }),
            badge: text.with_alpha(if contrast {
                opacity::glass::BADGE_CONTRAST
            } else {
                opacity::glass::BADGE
            }),
            typeface: Typeface::System,
            corner_radius: size::glass::CORNER_RADIUS,
            straight_branches: false,
            font_name: None,
            backdrop: look.backdrop && !contrast,
        }
    }

    /// 角丸のテーマを色のトークンで塗る．線は外枠の色，番号の丸とキーキャップは文字の色を薄くしたもの
    fn rounded(kind: Kind, typeface: Typeface, contrast: bool) -> Self {
        let palette = palette(kind);
        let text = Color::rgb(palette.text);
        let selection = Color::rgb(palette.selection);
        Self {
            kind,
            surface: Color::rgb(palette.surface),
            bevel_light: Color::rgb(palette.bevel_light),
            bevel_shadow: Color::rgb(palette.bevel_shadow),
            frame: Color::rgb(palette.frame),
            text,
            text_muted: if contrast {
                text
            } else {
                Color::rgb(palette.text_muted)
            },
            selection,
            selection_text: Color::rgb(palette.selection_text),
            correction: Color::rgb(palette.correction),
            line: if contrast {
                Color::rgb(palette.text_muted)
            } else {
                Color::rgb(palette.frame)
            },
            focus_tint: selection.with_alpha(if contrast {
                opacity::rounded::FOCUS_TINT_CONTRAST
            } else {
                opacity::rounded::FOCUS_TINT
            }),
            badge: text.with_alpha(if contrast {
                opacity::rounded::BADGE_CONTRAST
            } else {
                opacity::rounded::BADGE
            }),
            typeface,
            corner_radius: size::glass::CORNER_RADIUS,
            straight_branches: false,
            font_name: None,
            backdrop: false,
        }
    }

    /// platinum と desk．「コントラストを上げる」が有効なときは，立体の縁を外枠と同じ色にする
    fn bevelled(kind: Kind, contrast: bool) -> Self {
        let palette = palette(kind);
        let frame = Color::rgb(palette.frame);
        let bevel_light = if contrast {
            frame
        } else {
            Color::rgb(palette.bevel_light)
        };
        let bevel_shadow = if contrast {
            frame
        } else {
            Color::rgb(palette.bevel_shadow)
        };
        Self {
            kind,
            surface: Color::rgb(palette.surface),
            bevel_light,
            bevel_shadow,
            frame,
            text: Color::rgb(palette.text),
            text_muted: Color::rgb(palette.text_muted),
            selection: Color::rgb(palette.selection),
            selection_text: Color::rgb(palette.selection_text),
            correction: Color::rgb(palette.correction),
            // 区画を分ける線は，platinum は影の縁，desk は暗い面なので光の縁の色
            line: if kind == Kind::Desk {
                bevel_light
            } else {
                bevel_shadow
            },
            focus_tint: Color::rgb(palette.selection),
            badge: Color::rgb(palette.surface),
            typeface: Typeface::System,
            corner_radius: 0.0,
            straight_branches: true,
            font_name: None,
            backdrop: false,
        }
    }

    /// 角丸と曲線の枝で描くか(platinum と desk のほか)
    pub fn is_rounded(&self) -> bool {
        !matches!(self.kind, Kind::Platinum | Kind::Desk)
    }

    pub fn has_drop_shadow(&self) -> bool {
        self.kind == Kind::Desk
    }

    /// 枝を曲線で描くか
    pub fn curved_branches(&self) -> bool {
        self.is_rounded() && !self.straight_branches
    }

    /// 文字の書体・太さ・大きさ
    pub fn font(&self, font: Font, font_size: f32) -> FontSpec {
        let rounded = self.is_rounded();
        let contrast = self.kind == Kind::Contrast;
        let label_size = if rounded {
            size::glass::LABEL_FONT_SIZE
        } else {
            size::candidate::LABEL_FONT_SIZE
        };
        let (face, weight, size) = match font {
            Font::Candidate => (
                self.face(),
                if contrast {
                    Weight::Medium
                } else {
                    Weight::Regular
                },
                font_size,
            ),
            Font::Trunk => (
                self.face(),
                if contrast {
                    Weight::Semibold
                } else {
                    Weight::Medium
                },
                font_size,
            ),
            Font::Label => (self.label_face(), Weight::Medium, label_size),
            Font::Note => (
                self.label_face(),
                Weight::Medium,
                size::glass::LABEL_FONT_SIZE,
            ),
            Font::Key => (
                self.key_face(),
                Weight::Semibold,
                size::glass::KEY_FONT_SIZE,
            ),
            Font::SplitKey => (
                self.key_face(),
                Weight::Semibold,
                size::branch::SPLIT_BADGE_FONT_SIZE,
            ),
            Font::Mode if rounded => (
                Face::Ui,
                Weight::Semibold,
                size::glass::MODE_INDICATOR_FONT_SIZE,
            ),
            Font::Mode => (
                self.label_face(),
                Weight::Medium,
                size::mode_indicator::FONT_SIZE,
            ),
        };
        FontSpec { face, weight, size }
    }

    fn face(&self) -> Face {
        if let Some(name) = &self.font_name {
            return Face::Named(name.clone());
        }
        match self.typeface {
            Typeface::System => Face::System,
            Typeface::Mincho => Face::Mincho,
            Typeface::Monospaced => Face::Monospaced,
            Typeface::Rounded => Face::Rounded,
        }
    }

    /// 番号・案内・札の書体．glass は欧文の UI の書体
    fn label_face(&self) -> Face {
        if self.kind == Kind::Glass {
            Face::Ui
        } else {
            self.face()
        }
    }

    /// 番号の丸とキーキャップの中の文字．システムの書体のテーマは欧文の UI の書体(数字の幅がそろう)
    fn key_face(&self) -> Face {
        if self.typeface == Typeface::System {
            Face::Ui
        } else {
            self.face()
        }
    }
}

/// Windows の AccentPalette(4 バイト [赤・緑・青・不透明度] の色が，明るいものから 8 つ)から，選択に使う色を選ぶ．
/// Windows と同じく，ライトでは 1 段暗い色(5 番目)，ダークでは 2 段明るい色(2 番目)を使う
pub fn accent_from_palette(bytes: &[u8], dark: bool) -> Option<Rgb> {
    const LIGHT_2: usize = 1;
    const DARK_1: usize = 4;
    let index = if dark { LIGHT_2 } else { DARK_1 };
    let color = bytes.get(index * 4..index * 4 + 3)?;
    Some(Rgb {
        red: color[0],
        green: color[1],
        blue: color[2],
    })
}

fn palette(kind: Kind) -> Palette {
    let name = kind.token_name();
    tokens::THEMES
        .iter()
        .find(|(theme, _)| *theme == name)
        .map_or(tokens::GLASS_LIGHT, |(_, palette)| *palette)
}

/// 描く文字の種類
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Font {
    /// 候補の文字
    Candidate,
    /// 分岐図の幹の文字．候補より少し太い
    Trunk,
    /// 番号・案内・位置
    Label,
    /// 入力位置の下の案内(どのテーマでも glass の大きさ)
    Note,
    /// 番号の丸とキーキャップの中
    Key,
    /// 文節を区切る位置の番号
    SplitKey,
    /// モードの札
    Mode,
}

/// 書体の系統．書体の名前はアプリの層が OS ごとに決める
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Face {
    /// 日本語の UI の書体
    System,
    /// 欧文の UI の書体(数字と記号)．日本語は OS が代わりの書体で描く
    Ui,
    Mincho,
    Monospaced,
    Rounded,
    /// カスタムテーマで選んだ書体
    Named(String),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Weight {
    Regular,
    Medium,
    Semibold,
}

#[derive(Debug, Clone, PartialEq)]
pub struct FontSpec {
    pub face: Face,
    pub weight: Weight,
    pub size: f32,
}

#[cfg(test)]
mod tests {
    use super::*;

    fn look() -> SystemLook {
        SystemLook::default()
    }

    fn custom(base: &str) -> CustomTheme {
        let color = |red, green, blue| ipc::Color { red, green, blue };
        CustomTheme {
            base: base.into(),
            surface: color(0x2B, 0x1B, 0x17),
            text: color(0xFF, 0xE8, 0xD6),
            text_muted: color(0xC9, 0xA6, 0x8F),
            selection: color(0xFF, 0x7A, 0x3D),
            selection_text: color(0x1A, 0x0E, 0x0A),
            correction: color(0xFF, 0xD2, 0x3F),
            line: color(0x6B, 0x4A, 0x3E),
            font_name: Some("Yu Mincho".into()),
            corner_radius: 4.0,
            straight_branches: true,
        }
    }

    #[test]
    fn 標準と知らない値は_glass() {
        for name in ["automatic", "native", "", "unknown"] {
            assert_eq!(
                ResolvedTheme::resolve(name, None, &look()).kind,
                Kind::Glass
            );
        }
        assert_eq!(
            ResolvedTheme::resolve("desk", None, &look()).kind,
            Kind::Desk
        );
    }

    #[test]
    fn glass_はアクセントカラーとダークに合わせる() {
        let accent = Rgb {
            red: 0x10,
            green: 0x20,
            blue: 0x30,
        };
        let dark = SystemLook {
            dark: true,
            accent: Some(accent),
            ..look()
        };
        let theme = ResolvedTheme::resolve("automatic", None, &dark);
        assert_eq!(theme.selection, Color::rgb(accent));
        assert_eq!(theme.text, Color::rgb(tokens::GLASS_DARK.text));
        let light = ResolvedTheme::resolve("automatic", None, &look());
        assert_eq!(light.selection, Color::rgb(tokens::GLASS_LIGHT.selection));
    }

    #[test]
    fn アクセントカラーはライトとダークで段を変える() {
        let bytes: Vec<u8> = (0..8u8)
            .flat_map(|index| [index, index * 2, index * 3, 0xFF])
            .collect();
        assert_eq!(
            accent_from_palette(&bytes, false),
            Some(Rgb {
                red: 4,
                green: 8,
                blue: 12
            })
        );
        assert_eq!(
            accent_from_palette(&bytes, true),
            Some(Rgb {
                red: 1,
                green: 2,
                blue: 3
            })
        );
        assert_eq!(accent_from_palette(&bytes[..8], false), None);
    }

    #[test]
    fn コントラストを上げると線と弱い文字を濃くする() {
        let normal = ResolvedTheme::resolve("washi", None, &look());
        let contrast = SystemLook {
            increase_contrast: true,
            ..look()
        };
        let strong = ResolvedTheme::resolve("washi", None, &contrast);
        assert_eq!(strong.text_muted, strong.text);
        assert!(strong.badge.alpha > normal.badge.alpha);
        let platinum = ResolvedTheme::resolve("platinum", None, &contrast);
        assert_eq!(platinum.bevel_light, platinum.frame);
        // ハイコントラストのときは，すりガラスにしない
        let glass = ResolvedTheme::resolve(
            "automatic",
            None,
            &SystemLook {
                backdrop: true,
                ..contrast
            },
        );
        assert!(!glass.backdrop);
    }

    #[test]
    fn カスタムテーマは元のテーマの描き方に色と形を重ねる() {
        let theme = ResolvedTheme::resolve("platinum", Some(&custom("automatic")), &look());
        // glass を元にしたら，地を色で塗る角丸のテーマにする
        assert_eq!(theme.kind, Kind::Nordic);
        assert_eq!(
            theme.surface,
            Color::rgb(Rgb {
                red: 0x2B,
                green: 0x1B,
                blue: 0x17
            })
        );
        assert_eq!(theme.frame, theme.line);
        assert_eq!(theme.corner_radius, 4.0);
        assert!(!theme.curved_branches());
        assert_eq!(
            theme.font(Font::Candidate, 15.0).face,
            Face::Named("Yu Mincho".into())
        );
        let washi = ResolvedTheme::resolve("automatic", Some(&custom("washi")), &look());
        assert_eq!(washi.kind, Kind::Washi);
        assert_eq!(washi.typeface, Typeface::Mincho);
        let desk = ResolvedTheme::resolve("automatic", Some(&custom("desk")), &look());
        assert!(!desk.is_rounded());
    }

    #[test]
    fn テーマごとの書体() {
        let washi = ResolvedTheme::resolve("washi", None, &look());
        assert_eq!(washi.font(Font::Candidate, 15.0).face, Face::Mincho);
        assert_eq!(washi.font(Font::Key, 15.0).face, Face::Mincho);
        let terminal = ResolvedTheme::resolve("terminal", None, &look());
        assert_eq!(terminal.font(Font::Trunk, 15.0).face, Face::Monospaced);
        let glass = ResolvedTheme::resolve("automatic", None, &look());
        assert_eq!(glass.font(Font::Label, 15.0).face, Face::Ui);
        assert_eq!(glass.font(Font::Trunk, 15.0).weight, Weight::Medium);
        let contrast = ResolvedTheme::resolve("contrast", None, &look());
        assert_eq!(contrast.font(Font::Candidate, 15.0).weight, Weight::Medium);
        let platinum = ResolvedTheme::resolve("platinum", None, &look());
        assert_eq!(
            platinum.font(Font::Label, 15.0).size,
            size::candidate::LABEL_FONT_SIZE
        );
    }
}
