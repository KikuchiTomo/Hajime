//! scene の部品を Direct2D と DirectWrite で描く．配置と色は scene が決めるので，ここは部品をなぞるだけにする

use crate::geometry::Frame;
use crate::icon;
use crate::scene::{Draw, Measure, Scene};
use crate::theme::{Color, Face, Font, FontSpec, ResolvedTheme, Weight};
use std::collections::HashMap;
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_BEZIER_SEGMENT, D2D1_COLOR_F, D2D1_FIGURE_BEGIN_HOLLOW, D2D1_FIGURE_END_CLOSED,
    D2D1_FIGURE_END_OPEN, D2D_RECT_F,
};
use windows::Win32::Graphics::Direct2D::{
    D2D1CreateFactory, ID2D1Factory, ID2D1Geometry, ID2D1RenderTarget, ID2D1SolidColorBrush,
    ID2D1StrokeStyle, D2D1_CAP_STYLE_ROUND, D2D1_DASH_STYLE_CUSTOM, D2D1_DASH_STYLE_SOLID,
    D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT, D2D1_ELLIPSE, D2D1_FACTORY_TYPE_SINGLE_THREADED,
    D2D1_LINE_JOIN_ROUND, D2D1_ROUNDED_RECT, D2D1_STROKE_STYLE_PROPERTIES,
};
use windows::Win32::Graphics::DirectWrite::{
    DWriteCreateFactory, IDWriteFactory, IDWriteFactory5, IDWriteFontCollection, IDWriteTextFormat,
    DWRITE_FACTORY_TYPE_SHARED, DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL,
    DWRITE_FONT_WEIGHT, DWRITE_FONT_WEIGHT_MEDIUM, DWRITE_FONT_WEIGHT_NORMAL,
    DWRITE_FONT_WEIGHT_SEMI_BOLD, DWRITE_MEASURING_MODE_NATURAL, DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
    DWRITE_TEXT_METRICS, DWRITE_WORD_WRAPPING_NO_WRAP,
};
use windows_core::{Interface, Result, BOOL, HSTRING};

const LOCALE: &str = "ja-JP";
/// 角丸のテーマの影をぼかすときに重ねる層の数(1 ドットに 1 層)
const SHADOW_LAYERS_PER_DOT: f32 = 1.0;

/// 配布物に入れた書体のディレクトリ(実行ファイルと同じディレクトリの中)とファイル．
/// Kiwi Maru(SIL OFL 1.1．LICENSES/OFL-1.1-KiwiMaru.txt)．data/fonts/ を tools/fonts/update.sh で取ってくる
const BUNDLED_FONT_DIRECTORY: &str = "fonts";
const BUNDLED_FONT_FILES: &[&str] = &["KiwiMaru-Regular.ttf", "KiwiMaru-Medium.ttf"];

/// 書体の系統ごとの Windows の書体(docs/dev/DESIGN-SYSTEM.md の「書体」)．前から順に，入っている最初のものを使う．
/// 日本語の UI の書体と丸みのある書体は，配布物に入れた Kiwi Maru を先に使う(入っていなければ Yu Gothic UI)
fn families(face: &Face) -> &'static [&'static str] {
    match face {
        Face::System | Face::Rounded => &["Kiwi Maru", "Yu Gothic UI"],
        Face::Named(_) => &["Yu Gothic UI"],
        Face::Ui => &["Segoe UI"],
        Face::Mincho => &["Yu Mincho"],
        Face::Monospaced => &["BIZ UDGothic", "MS Gothic"],
    }
}

fn weight(weight: Weight) -> DWRITE_FONT_WEIGHT {
    match weight {
        Weight::Regular => DWRITE_FONT_WEIGHT_NORMAL,
        Weight::Medium => DWRITE_FONT_WEIGHT_MEDIUM,
        Weight::Semibold => DWRITE_FONT_WEIGHT_SEMI_BOLD,
    }
}

/// Direct2D の点(windows_numerics::Vector2)を，その型の名前を出さずに作る(windows クレートが再公開しない型のために依存を増やさない)
macro_rules! vector {
    ($x:expr, $y:expr) => {{
        let mut point = D2D1_ELLIPSE::default().point;
        point.X = $x;
        point.Y = $y;
        point
    }};
}

pub struct Renderer {
    d2d: ID2D1Factory,
    dwrite: IDWriteFactory,
    fonts: Option<IDWriteFontCollection>,
    /// 配布物に入れた書体の集まり．読めなければ None(OS の書体だけで描く)
    bundled: Option<IDWriteFontCollection>,
    round: ID2D1StrokeStyle,
}

/// テーマと文字の大きさを決めた書体の組．文字の幅を測り，描くときにも使う
pub struct TextMeasure {
    dwrite: IDWriteFactory,
    formats: HashMap<Font, IDWriteTextFormat>,
}

const FONTS: [Font; 7] = [
    Font::Candidate,
    Font::Trunk,
    Font::Label,
    Font::Note,
    Font::Key,
    Font::SplitKey,
    Font::Mode,
];

impl TextMeasure {
    fn format(&self, font: Font) -> Option<&IDWriteTextFormat> {
        self.formats.get(&font)
    }

    fn metrics(&self, text: &str, font: Font) -> Option<DWRITE_TEXT_METRICS> {
        let wide: Vec<u16> = text.encode_utf16().collect();
        let format = self.format(font)?;
        // SAFETY: format は生きている COM の参照で，wide は呼び出しのあいだ有効
        let layout = unsafe {
            self.dwrite
                .CreateTextLayout(&wide, format, f32::MAX, f32::MAX)
                .ok()?
        };
        let mut metrics = DWRITE_TEXT_METRICS::default();
        // SAFETY: metrics は書き込める領域
        unsafe { layout.GetMetrics(&mut metrics).ok()? };
        Some(metrics)
    }
}

impl Measure for TextMeasure {
    fn width(&self, text: &str, font: Font) -> f32 {
        self.metrics(text, font)
            .map_or(0.0, |metrics| metrics.widthIncludingTrailingWhitespace)
    }

    fn height(&self, font: Font) -> f32 {
        self.metrics("あ", font)
            .map_or(0.0, |metrics| metrics.height)
    }
}

/// 書体の集まりに family があるか
fn contains(collection: Option<&IDWriteFontCollection>, family: &str) -> bool {
    let Some(collection) = collection else {
        return false;
    };
    let mut index = 0;
    let mut exists = BOOL(0);
    // SAFETY: index と exists は書き込める領域
    let found =
        unsafe { collection.FindFamilyName(&HSTRING::from(family), &mut index, &mut exists) };
    found.is_ok() && exists.as_bool()
}

/// 配布物に入れた書体を読み込んだ書体の集まり．OS に入れずにこのプロセスだけで使う(DirectWrite の書体の組．Windows 10 1703 から)．
/// 書体のファイルが無い・読めないときは None
fn bundled_fonts(dwrite: &IDWriteFactory) -> Option<IDWriteFontCollection> {
    let directory = std::env::current_exe()
        .ok()?
        .parent()?
        .join(BUNDLED_FONT_DIRECTORY);
    let factory: IDWriteFactory5 = dwrite.cast().ok()?;
    // SAFETY: 作ったばかりの COM の参照を使う．ファイルの場所の文字列は呼び出しのあいだ有効
    unsafe {
        let builder = factory.CreateFontSetBuilder().ok()?;
        let mut added = false;
        for name in BUNDLED_FONT_FILES {
            let path = directory.join(name);
            if !path.is_file() {
                continue;
            }
            let file = dwrite
                .CreateFontFileReference(&HSTRING::from(path.as_os_str()), None)
                .ok()?;
            added |= builder.AddFontFile(&file).is_ok();
        }
        if !added {
            return None;
        }
        let set = builder.CreateFontSet().ok()?;
        factory
            .CreateFontCollectionFromFontSet(&set)
            .ok()?
            .cast()
            .ok()
    }
}

impl Renderer {
    pub fn new() -> Result<Self> {
        // SAFETY: 引数は定数
        let d2d: ID2D1Factory =
            unsafe { D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, None)? };
        // SAFETY: 引数は定数
        let dwrite: IDWriteFactory = unsafe { DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED)? };
        let mut fonts = None;
        // SAFETY: fonts は書き込める領域
        let _ = unsafe { dwrite.GetSystemFontCollection(&mut fonts, false) };
        let properties = D2D1_STROKE_STYLE_PROPERTIES {
            startCap: D2D1_CAP_STYLE_ROUND,
            endCap: D2D1_CAP_STYLE_ROUND,
            dashCap: D2D1_CAP_STYLE_ROUND,
            lineJoin: D2D1_LINE_JOIN_ROUND,
            miterLimit: 1.0,
            dashStyle: D2D1_DASH_STYLE_SOLID,
            dashOffset: 0.0,
        };
        // SAFETY: properties は呼び出しのあいだ有効
        let round = unsafe { d2d.CreateStrokeStyle(&properties, None)? };
        let bundled = bundled_fonts(&dwrite);
        Ok(Self {
            d2d,
            dwrite,
            fonts,
            bundled,
            round,
        })
    }

    pub fn factory(&self) -> &ID2D1Factory {
        &self.d2d
    }

    /// テーマの書体で，文字を測り描くための書体の組を作る
    pub fn measure(&self, theme: &ResolvedTheme, font_size: f32) -> Result<TextMeasure> {
        let mut formats = HashMap::new();
        for font in FONTS {
            formats.insert(font, self.format(&theme.font(font, font_size))?);
        }
        Ok(TextMeasure {
            dwrite: self.dwrite.clone(),
            formats,
        })
    }

    fn installed(&self, family: &str) -> bool {
        contains(self.fonts.as_ref(), family) || contains(self.bundled.as_ref(), family)
    }

    /// 書体の名前を決める．カスタムテーマの書体が入っていなければ，日本語の UI の書体にする
    fn family(&self, face: &Face) -> String {
        if let Face::Named(name) = face {
            if self.installed(name) {
                return name.clone();
            }
        }
        let candidates = families(face);
        candidates
            .iter()
            .find(|family| self.installed(family))
            .or(candidates.first())
            .map_or_else(String::new, |family| (*family).to_string())
    }

    fn format(&self, spec: &FontSpec) -> Result<IDWriteTextFormat> {
        let family = self.family(&spec.face);
        // 配布物の書体は OS の書体の集まりに無いので，その集まりを渡す
        let collection = self.bundled.as_ref().filter(|bundled| {
            !contains(self.fonts.as_ref(), &family) && contains(Some(bundled), &family)
        });
        // SAFETY: 文字列は呼び出しのあいだ有効
        let format = unsafe {
            self.dwrite.CreateTextFormat(
                &HSTRING::from(family),
                collection,
                weight(spec.weight),
                DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_STRETCH_NORMAL,
                spec.size,
                &HSTRING::from(LOCALE),
            )?
        };
        // SAFETY: format は作ったばかりの COM の参照
        unsafe {
            format.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER)?;
            format.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP)?;
        }
        Ok(format)
    }

    /// target に scene を描く．BeginDraw と EndDraw は呼ぶ側が受け持つ．
    /// scale は 1 ドットのデバイスピクセル数，opacity は全体の濃さ(モードの札のフェード)
    pub fn paint(
        &self,
        target: &ID2D1RenderTarget,
        scene: &Scene,
        measure: &TextMeasure,
        scale: f32,
        opacity: f32,
    ) -> Result<()> {
        let clear = D2D1_COLOR_F::default();
        // SAFETY: target は描いている途中の COM の参照
        unsafe { target.Clear(Some(&clear)) };
        self.paint_over(target, scene, measure, scale, opacity)
    }

    /// 前に描いたものを消さずに，その上に scene を opacity の濃さで描く(重ね変わり)
    pub fn paint_over(
        &self,
        target: &ID2D1RenderTarget,
        scene: &Scene,
        measure: &TextMeasure,
        scale: f32,
        opacity: f32,
    ) -> Result<()> {
        let clear = D2D1_COLOR_F::default();
        // SAFETY: target は描いている途中の COM の参照
        let brush = unsafe { target.CreateSolidColorBrush(&clear, None)? };
        let painter = Painter {
            renderer: self,
            target,
            brush: &brush,
            measure,
            scale,
            opacity,
        };
        for draw in &scene.draws {
            painter.draw(draw)?;
        }
        Ok(())
    }
}

struct Painter<'a> {
    renderer: &'a Renderer,
    target: &'a ID2D1RenderTarget,
    brush: &'a ID2D1SolidColorBrush,
    measure: &'a TextMeasure,
    scale: f32,
    opacity: f32,
}

impl Painter<'_> {
    fn color(&self, color: Color) {
        let color = D2D1_COLOR_F {
            r: color.red,
            g: color.green,
            b: color.blue,
            a: color.alpha * self.opacity,
        };
        // SAFETY: brush は生きている COM の参照
        unsafe { self.brush.SetColor(&color) };
    }

    /// 1 ドットの線をぼかさないよう，長方形の辺をデバイスのピクセルにそろえる
    fn snapped(&self, frame: &Frame) -> D2D_RECT_F {
        let snap = |value: f32| (value * self.scale).round() / self.scale;
        D2D_RECT_F {
            left: snap(frame.x),
            top: snap(frame.y),
            right: snap(frame.max_x()),
            bottom: snap(frame.max_y()),
        }
    }

    fn stroke_style(&self, dot_pitch: Option<f32>, width: f32) -> Result<ID2D1StrokeStyle> {
        let Some(pitch) = dot_pitch else {
            return Ok(self.renderer.round.clone());
        };
        let properties = D2D1_STROKE_STYLE_PROPERTIES {
            startCap: D2D1_CAP_STYLE_ROUND,
            endCap: D2D1_CAP_STYLE_ROUND,
            dashCap: D2D1_CAP_STYLE_ROUND,
            lineJoin: D2D1_LINE_JOIN_ROUND,
            miterLimit: 1.0,
            dashStyle: D2D1_DASH_STYLE_CUSTOM,
            dashOffset: 0.0,
        };
        // 長さ 0 の線と丸い端で丸い点にする．間隔は線の太さを 1 とした長さで渡す
        let dashes = [0.0, pitch / width.max(f32::EPSILON)];
        // SAFETY: properties と dashes は呼び出しのあいだ有効
        unsafe {
            self.renderer
                .d2d
                .CreateStrokeStyle(&properties, Some(&dashes))
        }
    }

    fn draw(&self, draw: &Draw) -> Result<()> {
        match draw {
            Draw::Rect { frame, color } => {
                self.color(*color);
                // SAFETY: target・brush は生きている COM の参照
                unsafe { self.target.FillRectangle(&self.snapped(frame), self.brush) };
            }
            Draw::RoundRect {
                frame,
                radius,
                fill,
                stroke,
            } => {
                let shape = D2D1_ROUNDED_RECT {
                    rect: rect(frame),
                    radiusX: *radius,
                    radiusY: *radius,
                };
                if let Some(color) = fill {
                    self.color(*color);
                    // SAFETY: 同上
                    unsafe { self.target.FillRoundedRectangle(&shape, self.brush) };
                }
                if let Some((color, width)) = stroke {
                    self.color(*color);
                    // SAFETY: 同上
                    unsafe {
                        self.target
                            .DrawRoundedRectangle(&shape, self.brush, *width, None)
                    };
                }
            }
            Draw::Ellipse { frame, color } => {
                self.color(*color);
                let ellipse = D2D1_ELLIPSE {
                    point: vector!(frame.mid_x(), frame.mid_y()),
                    radiusX: frame.width / 2.0,
                    radiusY: frame.height / 2.0,
                };
                // SAFETY: 同上
                unsafe { self.target.FillEllipse(&ellipse, self.brush) };
            }
            Draw::Curve {
                from,
                control1,
                control2,
                to,
                color,
                width,
            } => {
                // SAFETY: factory は生きている COM の参照．sink は閉じるまでこの関数の中だけで使う
                let geometry = unsafe {
                    let path = self.renderer.d2d.CreatePathGeometry()?;
                    let sink = path.Open()?;
                    sink.BeginFigure(vector!(from.x, from.y), D2D1_FIGURE_BEGIN_HOLLOW);
                    sink.AddBezier(&D2D1_BEZIER_SEGMENT {
                        point1: vector!(control1.x, control1.y),
                        point2: vector!(control2.x, control2.y),
                        point3: vector!(to.x, to.y),
                    });
                    sink.EndFigure(D2D1_FIGURE_END_OPEN);
                    sink.Close()?;
                    path
                };
                self.stroke(&geometry.into(), *color, *width, None)?;
            }
            Draw::Line {
                from,
                to,
                color,
                width,
                dot_pitch,
            } => {
                self.color(*color);
                let style = self.stroke_style(*dot_pitch, *width)?;
                // SAFETY: 同上
                unsafe {
                    self.target.DrawLine(
                        vector!(from.x, from.y),
                        vector!(to.x, to.y),
                        self.brush,
                        *width,
                        &style,
                    )
                };
            }
            Draw::Icon {
                icon,
                frame,
                color,
                width,
            } => {
                let figures = icon::figures(*icon, *frame);
                // SAFETY: 同上
                let geometry = unsafe {
                    let path = self.renderer.d2d.CreatePathGeometry()?;
                    let sink = path.Open()?;
                    for figure in &figures {
                        let Some((first, rest)) = figure.points.split_first() else {
                            continue;
                        };
                        sink.BeginFigure(vector!(first.x, first.y), D2D1_FIGURE_BEGIN_HOLLOW);
                        let rest: Vec<_> =
                            rest.iter().map(|point| vector!(point.x, point.y)).collect();
                        sink.AddLines(&rest);
                        sink.EndFigure(if figure.closed {
                            D2D1_FIGURE_END_CLOSED
                        } else {
                            D2D1_FIGURE_END_OPEN
                        });
                    }
                    sink.Close()?;
                    path
                };
                self.stroke(&geometry.into(), *color, *width, None)?;
            }
            Draw::Text {
                frame,
                text,
                font,
                color,
            } => {
                let Some(format) = self.measure.format(*font) else {
                    return Ok(());
                };
                self.color(*color);
                let wide: Vec<u16> = text.encode_utf16().collect();
                // 測った幅に少し余裕を持たせ，最後の字が折り返したり切れたりしないようにする
                let layout = D2D_RECT_F {
                    left: frame.x,
                    top: frame.y,
                    right: frame.max_x() + frame.height,
                    bottom: frame.max_y(),
                };
                // SAFETY: 同上．wide は呼び出しのあいだ有効
                unsafe {
                    self.target.DrawText(
                        &wide,
                        format,
                        &layout,
                        self.brush,
                        D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT,
                        DWRITE_MEASURING_MODE_NATURAL,
                    )
                };
            }
            Draw::Shadow {
                frame,
                radius,
                blur,
                color,
            } => {
                // 角丸の形を少しずつ広げて薄く重ね，ぼかした影に見せる
                let layers = (blur * SHADOW_LAYERS_PER_DOT).ceil().max(1.0);
                self.color(color.with_alpha(color.alpha / layers));
                let mut layer = 0.0;
                while layer < layers {
                    let spread = blur * (1.0 - layer / layers);
                    let shape = D2D1_ROUNDED_RECT {
                        rect: rect(&frame.inset(-spread, -spread)),
                        radiusX: radius + spread,
                        radiusY: radius + spread,
                    };
                    // SAFETY: 同上
                    unsafe { self.target.FillRoundedRectangle(&shape, self.brush) };
                    layer += 1.0;
                }
            }
        }
        Ok(())
    }

    fn stroke(
        &self,
        geometry: &ID2D1Geometry,
        color: Color,
        width: f32,
        dot_pitch: Option<f32>,
    ) -> Result<()> {
        self.color(color);
        let style = self.stroke_style(dot_pitch, width)?;
        // SAFETY: 同上
        unsafe {
            self.target
                .DrawGeometry(geometry, self.brush, width, &style)
        };
        Ok(())
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
