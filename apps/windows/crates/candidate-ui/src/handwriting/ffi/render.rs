//! 手書きの窓を Direct2D で描く．枠(見出しの帯・ボタン・背景)は Windows 11 の色(settings-windows)で，
//! 書く欄は macOS と同じく候補ウィンドウのテーマの色で描く．1 ドットの線と部品の枠線はデバイスのピクセルにそろえる

use crate::handwriting::ink::Ink;
use crate::handwriting::layout::{Control, Layout, TextWidth};
use crate::handwriting::strings;
use crate::scene::Frame;
use crate::theme::{Color, ResolvedTheme};
use tokens::size::handwriting as size;
use tokens::{handwriting_windows, settings_windows, SettingsPalette};
use windows::Win32::Foundation::HWND;
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_ALPHA_MODE_PREMULTIPLIED, D2D1_COLOR_F, D2D1_FIGURE_BEGIN_HOLLOW, D2D1_FIGURE_END_OPEN,
    D2D1_GRADIENT_STOP, D2D1_PIXEL_FORMAT, D2D_RECT_F, D2D_SIZE_U,
};
use windows::Win32::Graphics::Direct2D::{
    D2D1CreateFactory, ID2D1Factory, ID2D1HwndRenderTarget, ID2D1RenderTarget,
    ID2D1SolidColorBrush, ID2D1StrokeStyle, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE,
    D2D1_CAP_STYLE_ROUND, D2D1_DRAW_TEXT_OPTIONS_CLIP, D2D1_EXTEND_MODE_CLAMP,
    D2D1_FACTORY_TYPE_SINGLE_THREADED, D2D1_GAMMA_2_2, D2D1_HWND_RENDER_TARGET_PROPERTIES,
    D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES, D2D1_LINE_JOIN_ROUND, D2D1_PRESENT_OPTIONS_NONE,
    D2D1_RENDER_TARGET_PROPERTIES, D2D1_ROUNDED_RECT, D2D1_STROKE_STYLE_PROPERTIES,
};
use windows::Win32::Graphics::DirectWrite::{
    DWriteCreateFactory, IDWriteFactory, IDWriteFontCollection, IDWriteTextFormat,
    DWRITE_FACTORY_TYPE_SHARED, DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL,
    DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_WEIGHT_SEMI_LIGHT, DWRITE_MEASURING_MODE_NATURAL,
    DWRITE_PARAGRAPH_ALIGNMENT_CENTER, DWRITE_TEXT_ALIGNMENT, DWRITE_TEXT_ALIGNMENT_CENTER,
    DWRITE_TEXT_ALIGNMENT_LEADING, DWRITE_TEXT_METRICS, DWRITE_WORD_WRAPPING_NO_WRAP,
    DWRITE_WORD_WRAPPING_WRAP,
};
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_B8G8R8A8_UNORM;
use windows_core::{Result, BOOL, HSTRING};
use windows_numerics::Vector2;

/// 日本語の UI の書体(Windows 11 の設定アプリと同じ)
const TEXT_FAMILY: &str = "Yu Gothic UI";
/// アイコンの書体．Windows 11 は Segoe Fluent Icons，Windows 10 は Segoe MDL2 Assets(同じ字の番号でアイコンを持つ)
const ICON_FAMILIES: [&str; 2] = ["Segoe Fluent Icons", "Segoe MDL2 Assets"];
/// 閉じる(ChromeClose)と 1 画戻す(Undo)のアイコンの字
const CLOSE_GLYPH: &str = "\u{E8BB}";
const UNDO_GLYPH: &str = "\u{E7A7}";
const LOCALE: &str = "ja-JP";
/// 書く欄の背景がこれより透けていれば，欄の背景を Windows の入力欄の色にする(macOS の textBackgroundColor と同じ扱い)
const OPAQUE_ENOUGH: f32 = 0.5;
/// 字の幅を測るときの枠の大きさ．f32::MAX にすると，中央にそろえる書式では幅を求められない
const MEASURE_EXTENT: f32 = 4096.0;

/// 窓の枠の色．Windows 11 の色(ライトかダーク)と，閉じるボタンの赤
#[derive(Debug, Clone, Copy)]
pub struct Chrome {
    pub palette: SettingsPalette,
    pub close_hover: Color,
    pub close_pressed: Color,
    pub close_text: Color,
}

impl Chrome {
    pub fn new(dark: bool) -> Self {
        if dark {
            Self {
                palette: settings_windows::DARK,
                close_hover: Color::rgb(handwriting_windows::dark::CLOSE_HOVER),
                close_pressed: Color::rgb(handwriting_windows::dark::CLOSE_PRESSED),
                close_text: Color::rgb(handwriting_windows::dark::CLOSE_TEXT),
            }
        } else {
            Self {
                palette: settings_windows::LIGHT,
                close_hover: Color::rgb(handwriting_windows::light::CLOSE_HOVER),
                close_pressed: Color::rgb(handwriting_windows::light::CLOSE_PRESSED),
                close_text: Color::rgb(handwriting_windows::light::CLOSE_TEXT),
            }
        }
    }

    fn color(rgb: tokens::Rgb) -> Color {
        Color::rgb(rgb)
    }
}

/// 描くときの部品の様子(ポインタを置いた・押している部品，書く欄の案内)
#[derive(Debug, Clone, Copy, Default)]
pub struct State<'a> {
    pub hovered: Option<Control>,
    pub pressed: Option<Control>,
    /// 候補の行に出す案内(認識できないとき)
    pub note: Option<&'a str>,
}

/// 書体．見出しの題・ボタンの字・候補・アイコン
pub struct Fonts {
    dwrite: IDWriteFactory,
    caption: IDWriteTextFormat,
    label: IDWriteTextFormat,
    label_leading: IDWriteTextFormat,
    candidate: IDWriteTextFormat,
    /// 候補の行の案内(2 行まで折り返す)
    note: IDWriteTextFormat,
    caption_icon: IDWriteTextFormat,
    icon: IDWriteTextFormat,
}

impl Fonts {
    fn width(&self, text: &str, format: &IDWriteTextFormat) -> f32 {
        self.metrics(text, format)
            .map_or(0.0, |metrics| metrics.widthIncludingTrailingWhitespace)
    }

    fn metrics(&self, text: &str, format: &IDWriteTextFormat) -> Option<DWRITE_TEXT_METRICS> {
        let wide: Vec<u16> = text.encode_utf16().collect();
        // SAFETY: wide と format はこの呼び出しのあいだ生きている
        let layout = unsafe {
            self.dwrite
                .CreateTextLayout(&wide, format, MEASURE_EXTENT, MEASURE_EXTENT)
                .ok()?
        };
        let mut metrics = DWRITE_TEXT_METRICS::default();
        // SAFETY: metrics は書き込める場所を指す
        unsafe { layout.GetMetrics(&mut metrics).ok()? };
        Some(metrics)
    }
}

impl TextWidth for Fonts {
    fn candidate_width(&self, text: &str) -> f32 {
        self.width(text, &self.candidate)
    }

    fn label_width(&self, text: &str) -> f32 {
        self.width(text, &self.label)
    }
}

pub struct Renderer {
    d2d: ID2D1Factory,
    dwrite: IDWriteFactory,
    round: ID2D1StrokeStyle,
    target: Option<ID2D1HwndRenderTarget>,
}

impl Renderer {
    pub fn new() -> Result<Self> {
        // SAFETY: 引数の無い作成の関数．作ったものは COM の参照で持つ
        let d2d: ID2D1Factory =
            unsafe { D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, None)? };
        // SAFETY: 同上
        let dwrite = unsafe { DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED)? };
        let properties = D2D1_STROKE_STYLE_PROPERTIES {
            startCap: D2D1_CAP_STYLE_ROUND,
            endCap: D2D1_CAP_STYLE_ROUND,
            lineJoin: D2D1_LINE_JOIN_ROUND,
            ..Default::default()
        };
        // SAFETY: properties はこの呼び出しのあいだ生きている
        let round = unsafe { d2d.CreateStrokeStyle(&properties, None)? };
        Ok(Self {
            d2d,
            dwrite,
            round,
            target: None,
        })
    }

    #[cfg(debug_assertions)]
    pub fn factory(&self) -> &ID2D1Factory {
        &self.d2d
    }

    pub fn fonts(&self) -> Result<Fonts> {
        let icon_family = self.icon_family();
        Ok(Fonts {
            dwrite: self.dwrite.clone(),
            caption: self.format(
                TEXT_FAMILY,
                size::CAPTION_FONT_SIZE,
                DWRITE_TEXT_ALIGNMENT_LEADING,
            )?,
            label: self.format(
                TEXT_FAMILY,
                size::LABEL_FONT_SIZE,
                DWRITE_TEXT_ALIGNMENT_CENTER,
            )?,
            label_leading: self.format(
                TEXT_FAMILY,
                size::LABEL_FONT_SIZE,
                DWRITE_TEXT_ALIGNMENT_LEADING,
            )?,
            candidate: self.format(
                TEXT_FAMILY,
                size::CANDIDATE_FONT_SIZE,
                DWRITE_TEXT_ALIGNMENT_CENTER,
            )?,
            note: {
                let note = self.format(
                    TEXT_FAMILY,
                    size::CAPTION_FONT_SIZE,
                    DWRITE_TEXT_ALIGNMENT_LEADING,
                )?;
                // SAFETY: 作ったばかりの書式を設定するだけ
                unsafe { note.SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP)? };
                note
            },
            caption_icon: self.format(
                icon_family,
                size::CAPTION_ICON_SIZE,
                DWRITE_TEXT_ALIGNMENT_CENTER,
            )?,
            icon: self.format(icon_family, size::ICON_SIZE, DWRITE_TEXT_ALIGNMENT_CENTER)?,
        })
    }

    /// 入っているアイコンの書体(Windows 11 の Segoe Fluent Icons が無ければ Windows 10 の Segoe MDL2 Assets)
    fn icon_family(&self) -> &'static str {
        let mut collection: Option<IDWriteFontCollection> = None;
        // SAFETY: collection は書き込める場所を指す
        let _ = unsafe { self.dwrite.GetSystemFontCollection(&mut collection, false) };
        let installed = |family: &str| {
            let Some(collection) = &collection else {
                return false;
            };
            let mut index = 0;
            let mut exists = BOOL(0);
            // SAFETY: index と exists は書き込める場所を指す
            let found = unsafe {
                collection.FindFamilyName(&HSTRING::from(family), &mut index, &mut exists)
            };
            found.is_ok() && exists.as_bool()
        };
        ICON_FAMILIES
            .into_iter()
            .find(|family| installed(family))
            .unwrap_or(ICON_FAMILIES[1])
    }

    fn format(
        &self,
        family: &str,
        size: f32,
        alignment: DWRITE_TEXT_ALIGNMENT,
    ) -> Result<IDWriteTextFormat> {
        // 見出しの題は Windows 11 のタイトルバーと同じく細めにする
        let weight = if size <= size::CAPTION_FONT_SIZE && family == TEXT_FAMILY {
            DWRITE_FONT_WEIGHT_SEMI_LIGHT
        } else {
            DWRITE_FONT_WEIGHT_NORMAL
        };
        // SAFETY: 文字列はこの呼び出しのあいだ生きている
        let format = unsafe {
            self.dwrite.CreateTextFormat(
                &HSTRING::from(family),
                None,
                weight,
                DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_STRETCH_NORMAL,
                size,
                &HSTRING::from(LOCALE),
            )?
        };
        // SAFETY: 作ったばかりの書式を設定するだけ
        unsafe {
            format.SetTextAlignment(alignment)?;
            format.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER)?;
            format.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP)?;
        }
        Ok(format)
    }

    fn target(&mut self, hwnd: HWND, width: u32, height: u32) -> Result<ID2D1HwndRenderTarget> {
        let size = D2D_SIZE_U { width, height };
        if let Some(target) = &self.target {
            // SAFETY: 描画先は窓と同じだけ生きている
            unsafe { target.Resize(&size)? };
            return Ok(target.clone());
        }
        let properties = D2D1_RENDER_TARGET_PROPERTIES {
            pixelFormat: D2D1_PIXEL_FORMAT {
                format: DXGI_FORMAT_B8G8R8A8_UNORM,
                alphaMode: D2D1_ALPHA_MODE_PREMULTIPLIED,
            },
            ..Default::default()
        };
        // SAFETY: hwnd はこの手書きの窓で，描画先より長く生きる
        let target = unsafe {
            self.d2d.CreateHwndRenderTarget(
                &properties,
                &D2D1_HWND_RENDER_TARGET_PROPERTIES {
                    hwnd,
                    pixelSize: size,
                    presentOptions: D2D1_PRESENT_OPTIONS_NONE,
                },
            )?
        };
        self.target = Some(target.clone());
        Ok(target)
    }

    /// 窓の中身を描く．scale は DIP あたりのデバイスのピクセル
    #[allow(clippy::too_many_arguments)]
    pub fn draw(
        &mut self,
        hwnd: HWND,
        scale: f32,
        layout: &Layout,
        ink: &Ink,
        state: State<'_>,
        theme: &ResolvedTheme,
        chrome: &Chrome,
        fonts: &Fonts,
    ) -> Result<()> {
        let width = (layout.width * scale).round() as u32;
        let height = (layout.height * scale).round() as u32;
        let target = self.target(hwnd, width.max(1), height.max(1))?;
        // SAFETY: SetDpi は BeginDraw の前に呼ぶ
        unsafe { target.SetDpi(96.0 * scale, 96.0 * scale) };
        let result = self.paint(&target, scale, layout, ink, state, theme, chrome, fonts);
        if result.is_err() {
            self.target = None;
        }
        result
    }

    /// target に描く(窓と，見本の PNG の両方で使う)．BeginDraw から EndDraw まで行う
    #[allow(clippy::too_many_arguments)]
    pub fn paint(
        &self,
        target: &ID2D1RenderTarget,
        scale: f32,
        layout: &Layout,
        ink: &Ink,
        state: State<'_>,
        theme: &ResolvedTheme,
        chrome: &Chrome,
        fonts: &Fonts,
    ) -> Result<()> {
        // SAFETY: 描画先の筆はこの関数の中だけで使う
        let brush = unsafe { target.CreateSolidColorBrush(&d2d(theme.text), None)? };
        let painter = Painter {
            factory: &self.d2d,
            target,
            brush: &brush,
            round: &self.round,
            scale,
            chrome,
            theme,
            fonts,
        };
        // SAFETY: BeginDraw と EndDraw の対の中で描く
        unsafe {
            target.BeginDraw();
            target.SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
            target.Clear(Some(&d2d(Chrome::color(chrome.palette.background))));
        }
        painter.paint(layout, ink, state);
        // SAFETY: BeginDraw と対にする
        unsafe { target.EndDraw(None, None) }
    }
}

struct Painter<'a> {
    factory: &'a ID2D1Factory,
    target: &'a ID2D1RenderTarget,
    brush: &'a ID2D1SolidColorBrush,
    round: &'a ID2D1StrokeStyle,
    scale: f32,
    chrome: &'a Chrome,
    theme: &'a ResolvedTheme,
    fonts: &'a Fonts,
}

/// ボタンの様子
#[derive(Clone, Copy, PartialEq, Eq)]
enum Look {
    Rest,
    Hover,
    Pressed,
    Disabled,
}

impl Painter<'_> {
    fn paint(&self, layout: &Layout, ink: &Ink, state: State<'_>) {
        let palette = &self.chrome.palette;
        let look = |control: Control, enabled: bool| {
            if !enabled {
                Look::Disabled
            } else if state.pressed == Some(control) && state.hovered == Some(control) {
                Look::Pressed
            } else if state.hovered == Some(control) && state.pressed.is_none() {
                Look::Hover
            } else {
                Look::Rest
            }
        };
        // 見出しの帯: 題と閉じるボタン(Windows 11 のツールの窓のタイトルバー)
        let title = Frame::new(
            size::CANVAS_PADDING,
            0.0,
            layout.close.x - size::CANVAS_PADDING,
            layout.title.height,
        );
        self.text(
            strings::TITLE,
            &title,
            &self.fonts.caption,
            Chrome::color(palette.text),
        );
        self.close_button(&layout.close, look(Control::Close, true));
        // 書く欄
        self.canvas(layout, ink);
        // 候補の行
        self.candidates(layout, ink, &state, &look);
        let has_ink = !ink.is_empty();
        self.button(&layout.undo, look(Control::Undo, has_ink));
        self.text(
            UNDO_GLYPH,
            &layout.undo,
            &self.fonts.icon,
            self.button_text(look(Control::Undo, has_ink)),
        );
        self.button(&layout.clear, look(Control::Clear, has_ink));
        self.text(
            strings::CLEAR,
            &layout.clear,
            &self.fonts.label,
            self.button_text(look(Control::Clear, has_ink)),
        );
    }

    fn canvas(&self, layout: &Layout, ink: &Ink) {
        let canvas = self.snap(&layout.canvas);
        let ground = self.canvas_ground();
        let radius = size::CONTROL_RADIUS;
        self.fill_rounded(&canvas, radius, ground);
        // SAFETY: BeginDraw と EndDraw の中で，生きている描画先に切り抜きを積んで下ろす
        unsafe {
            self.target
                .PushAxisAlignedClip(&rect(&canvas), D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        }
        for dash in layout.guide() {
            self.fill(&self.snap_line(&dash), self.theme.line);
        }
        if ink.is_empty() {
            self.prompt(&canvas, ground);
        }
        self.strokes(&canvas, ink);
        // SAFETY: 上の PushAxisAlignedClip と対にする
        unsafe { self.target.PopAxisAlignedClip() };
        self.outline_rounded(&canvas, radius, self.theme.line);
    }

    /// 書く欄の背景．macOS と同じくテーマの背景を使い，透ける背景(すりガラス)なら Windows の入力欄の色にする
    fn canvas_ground(&self) -> Color {
        if self.theme.surface.alpha < OPAQUE_ENOUGH {
            Chrome::color(self.chrome.palette.control)
        } else {
            self.theme.surface.with_alpha(1.0)
        }
    }

    /// 書いていないときの案内．十字の線の上に背景を敷いて読めるようにする(macOS と同じ)
    fn prompt(&self, canvas: &Frame, ground: Color) {
        let width = self
            .fonts
            .width(strings::PROMPT, &self.fonts.label_leading)
            .ceil();
        let height = self
            .fonts
            .metrics(strings::PROMPT, &self.fonts.label_leading)
            .map_or(size::LABEL_FONT_SIZE, |metrics| metrics.height)
            .ceil();
        let backing = Frame::new(
            canvas.mid_x() - width / 2.0 - size::CANVAS_PADDING,
            canvas.mid_y() - height / 2.0 - size::PROMPT_PADDING_Y,
            width + size::CANVAS_PADDING * 2.0,
            height + size::PROMPT_PADDING_Y * 2.0,
        );
        self.fill(&self.snap(&backing), ground);
        self.text(
            strings::PROMPT,
            &backing,
            &self.fonts.label,
            self.theme.text_muted,
        );
    }

    /// 線をまとめて 1 つの形にして 1 回で描く(1 画ずつ描くと，半透明の文字色で線の重なりが濃くなる．macOS と同じ)
    fn strokes(&self, canvas: &Frame, ink: &Ink) {
        if ink.is_empty() {
            return;
        }
        let point = |x: f32, y: f32| Vector2 {
            X: canvas.x + x,
            Y: canvas.y + y,
        };
        // SAFETY: 形は作ってすぐ閉じ，BeginDraw と EndDraw の中で描く
        unsafe {
            let Ok(path) = self.factory.CreatePathGeometry() else {
                return;
            };
            let Ok(sink) = path.Open() else { return };
            for stroke in ink.strokes() {
                let Some(first) = stroke.first() else {
                    continue;
                };
                sink.BeginFigure(point(first.x, first.y), D2D1_FIGURE_BEGIN_HOLLOW);
                if stroke.len() == 1 {
                    // 点を打っただけの線も丸い点として描く
                    sink.AddLine(point(first.x, first.y));
                }
                for next in &stroke[1..] {
                    sink.AddLine(point(next.x, next.y));
                }
                sink.EndFigure(D2D1_FIGURE_END_OPEN);
            }
            if sink.Close().is_err() {
                return;
            }
            self.brush.SetColor(&d2d(self.theme.text));
            self.target
                .DrawGeometry(&path, self.brush, size::STROKE_WIDTH, self.round);
        }
    }

    fn candidates(
        &self,
        layout: &Layout,
        ink: &Ink,
        state: &State<'_>,
        look: &dyn Fn(Control, bool) -> Look,
    ) {
        let strip = self.snap(&layout.strip);
        if let Some(note) = state.note {
            self.text(
                note,
                &strip,
                &self.fonts.note,
                Chrome::color(self.chrome.palette.text_secondary),
            );
            return;
        }
        // SAFETY: BeginDraw と EndDraw の中で，切り抜きを積んで下ろす
        unsafe {
            self.target
                .PushAxisAlignedClip(&rect(&strip), D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
        }
        for (index, (chip, text)) in layout.chips.iter().zip(ink.candidates()).enumerate() {
            if chip.max_x() < strip.x || chip.x > strip.max_x() {
                continue;
            }
            let chip_look = look(Control::Candidate(index), true);
            let chip = self.snap(chip);
            self.button(&chip, chip_look);
            self.text(
                text,
                &chip,
                &self.fonts.candidate,
                self.button_text(chip_look),
            );
        }
        // まだ送れる側の端を背景の色へ薄れさせ，続きがあることを示す
        let (left, right) = layout.overflows();
        let fade = size::SCROLL_FADE;
        if left {
            self.fade(&Frame::new(strip.x, strip.y, fade, strip.height), true);
        }
        if right {
            self.fade(
                &Frame::new(strip.max_x() - fade, strip.y, fade, strip.height),
                false,
            );
        }
        // SAFETY: 上の PushAxisAlignedClip と対にする
        unsafe { self.target.PopAxisAlignedClip() };
    }

    /// Windows 11 の標準のボタン(背景・1 ドットの枠線・角丸)
    fn button(&self, frame: &Frame, look: Look) {
        let palette = &self.chrome.palette;
        let ground = match look {
            Look::Rest | Look::Disabled => palette.control,
            Look::Hover => palette.control_hover,
            Look::Pressed => palette.control_pressed,
        };
        let frame = self.snap(frame);
        self.fill_rounded(&frame, size::CONTROL_RADIUS, Chrome::color(ground));
        self.outline_rounded(
            &frame,
            size::CONTROL_RADIUS,
            Chrome::color(palette.control_stroke),
        );
    }

    fn button_text(&self, look: Look) -> Color {
        let palette = &self.chrome.palette;
        Chrome::color(match look {
            Look::Disabled => palette.text_disabled,
            Look::Pressed => palette.text_secondary,
            Look::Rest | Look::Hover => palette.text,
        })
    }

    /// 閉じるボタン．ポインタを置くと赤い背景に白いアイコン(Windows 11 のキャプションボタンと同じ)
    fn close_button(&self, frame: &Frame, look: Look) {
        let frame = self.snap(frame);
        let glyph = match look {
            Look::Hover => {
                self.fill(&frame, self.chrome.close_hover);
                self.chrome.close_text
            }
            Look::Pressed => {
                self.fill(&frame, self.chrome.close_pressed);
                self.chrome.close_text
            }
            Look::Rest | Look::Disabled => Chrome::color(self.chrome.palette.text),
        };
        self.text(CLOSE_GLYPH, &frame, &self.fonts.caption_icon, glyph);
    }

    /// frame の中を背景の色へ薄れさせる．leading なら左端が濃い
    fn fade(&self, frame: &Frame, leading: bool) {
        let ground = Chrome::color(self.chrome.palette.background);
        let stops = [
            D2D1_GRADIENT_STOP {
                position: 0.0,
                color: d2d(ground.with_alpha(if leading { 1.0 } else { 0.0 })),
            },
            D2D1_GRADIENT_STOP {
                position: 1.0,
                color: d2d(ground.with_alpha(if leading { 0.0 } else { 1.0 })),
            },
        ];
        // SAFETY: stops はこの呼び出しのあいだ生きている．筆はこの関数の中だけで使う
        unsafe {
            let Ok(collection) = self.target.CreateGradientStopCollection(
                &stops,
                D2D1_GAMMA_2_2,
                D2D1_EXTEND_MODE_CLAMP,
            ) else {
                return;
            };
            let Ok(gradient) = self.target.CreateLinearGradientBrush(
                &D2D1_LINEAR_GRADIENT_BRUSH_PROPERTIES {
                    startPoint: Vector2 {
                        X: frame.x,
                        Y: frame.y,
                    },
                    endPoint: Vector2 {
                        X: frame.max_x(),
                        Y: frame.y,
                    },
                },
                None,
                &collection,
            ) else {
                return;
            };
            self.target.FillRectangle(&rect(frame), &gradient);
        }
    }

    /// 1 ドットの線の太さ(デバイスのピクセルの整数倍)
    fn hairline(&self) -> f32 {
        self.scale.round().max(1.0) / self.scale
    }

    /// 枠線をデバイスのピクセルにそろえた四角
    fn snap(&self, frame: &Frame) -> Frame {
        let snap = |value: f32| (value * self.scale).round() / self.scale;
        let x = snap(frame.x);
        let y = snap(frame.y);
        Frame::new(x, y, snap(frame.max_x()) - x, snap(frame.max_y()) - y)
    }

    /// 細い線の四角(十字の破線の 1 区切り)を，太さを 1 ドットにしてピクセルにそろえる
    fn snap_line(&self, frame: &Frame) -> Frame {
        let line = self.hairline();
        let snapped = self.snap(frame);
        if frame.width <= frame.height {
            Frame::new(snapped.x, snapped.y, line, snapped.height)
        } else {
            Frame::new(snapped.x, snapped.y, snapped.width, line)
        }
    }

    fn fill(&self, frame: &Frame, color: Color) {
        // SAFETY: BeginDraw と EndDraw の中で，生きている筆で描く
        unsafe {
            self.brush.SetColor(&d2d(color));
            self.target.FillRectangle(&rect(frame), self.brush);
        }
    }

    fn fill_rounded(&self, frame: &Frame, radius: f32, color: Color) {
        // SAFETY: BeginDraw と EndDraw の中で，生きている筆で描く
        unsafe {
            self.brush.SetColor(&d2d(color));
            self.target
                .FillRoundedRectangle(&rounded(frame, radius), self.brush);
        }
    }

    /// 内側に 1 ドットの枠線を描く(線の真ん中を半ドット内側に置き，ピクセルにそろえる)
    fn outline_rounded(&self, frame: &Frame, radius: f32, color: Color) {
        let line = self.hairline();
        let inset = frame.inset(line / 2.0, line / 2.0);
        // SAFETY: BeginDraw と EndDraw の中で，生きている筆で描く
        unsafe {
            self.brush.SetColor(&d2d(color));
            self.target.DrawRoundedRectangle(
                &rounded(&inset, (radius - line / 2.0).max(0.0)),
                self.brush,
                line,
                None,
            );
        }
    }

    fn text(&self, text: &str, frame: &Frame, format: &IDWriteTextFormat, color: Color) {
        let wide: Vec<u16> = text.encode_utf16().collect();
        // SAFETY: BeginDraw と EndDraw の中で，生きている筆と書式で描く
        unsafe {
            self.brush.SetColor(&d2d(color));
            self.target.DrawText(
                &wide,
                format,
                &rect(frame),
                self.brush,
                D2D1_DRAW_TEXT_OPTIONS_CLIP,
                DWRITE_MEASURING_MODE_NATURAL,
            );
        }
    }
}

fn d2d(color: Color) -> D2D1_COLOR_F {
    D2D1_COLOR_F {
        r: color.red,
        g: color.green,
        b: color.blue,
        a: color.alpha,
    }
}

fn rect(frame: &Frame) -> D2D_RECT_F {
    D2D_RECT_F {
        left: frame.x,
        top: frame.y,
        right: frame.max_x(),
        bottom: frame.max_y(),
    }
}

fn rounded(frame: &Frame, radius: f32) -> D2D1_ROUNDED_RECT {
    D2D1_ROUNDED_RECT {
        rect: rect(frame),
        radiusX: radius,
        radiusY: radius,
    }
}
