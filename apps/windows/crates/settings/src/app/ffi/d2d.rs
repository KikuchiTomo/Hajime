//! Direct2D と DirectWrite で描く．座標は DIP(96dpi の 1 ピクセルを 1)で，描き先の DPI を窓の DPI にする．
//! 文字はグレースケールで滑らかにする(Windows 11 の XAML と同じ．ClearType の色ずれを出さない)．
//! 書体は英数字に Segoe UI Variable，日本語に Yu Gothic UI を使う(Windows 11 の設定アプリと同じ組み合わせ)

use crate::app::paint::{Align, Arc, Canvas, Measure, TextLayout, TextStyle};
use crate::app::theme::Color;
use crate::layout::Rect;
use std::cell::RefCell;
use std::collections::HashMap;
use tokens::size::settings_windows as size;
use windows::Win32::Foundation::{D2DERR_RECREATE_TARGET, HWND};
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_ALPHA_MODE_IGNORE, D2D1_ALPHA_MODE_PREMULTIPLIED, D2D1_COLOR_F, D2D1_FIGURE_BEGIN_HOLLOW,
    D2D1_FIGURE_END_OPEN, D2D1_PIXEL_FORMAT, D2D_RECT_F, D2D_SIZE_F, D2D_SIZE_U,
};
use windows::Win32::Graphics::Direct2D::{
    D2D1CreateFactory, ID2D1Bitmap, ID2D1Factory, ID2D1HwndRenderTarget, ID2D1RenderTarget,
    ID2D1SolidColorBrush, ID2D1StrokeStyle, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE, D2D1_ARC_SEGMENT,
    D2D1_ARC_SIZE_LARGE, D2D1_ARC_SIZE_SMALL, D2D1_BITMAP_INTERPOLATION_MODE_LINEAR,
    D2D1_BITMAP_PROPERTIES, D2D1_CAP_STYLE_ROUND, D2D1_DASH_STYLE_SOLID,
    D2D1_DRAW_TEXT_OPTIONS_CLIP, D2D1_ELLIPSE, D2D1_FACTORY_TYPE_SINGLE_THREADED,
    D2D1_HWND_RENDER_TARGET_PROPERTIES, D2D1_LINE_JOIN_ROUND, D2D1_PRESENT_OPTIONS_NONE,
    D2D1_RENDER_TARGET_PROPERTIES, D2D1_ROUNDED_RECT, D2D1_STROKE_STYLE_PROPERTIES,
    D2D1_SWEEP_DIRECTION_CLOCKWISE, D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE,
};
use windows::Win32::Graphics::DirectWrite::{
    DWriteCreateFactory, IDWriteFactory2, IDWriteFontCollection, IDWriteFontFallback,
    IDWriteTextFormat, IDWriteTextFormat1, IDWriteTextLayout, DWRITE_FACTORY_TYPE_SHARED,
    DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_WEIGHT,
    DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_WEIGHT_SEMI_BOLD, DWRITE_PARAGRAPH_ALIGNMENT_CENTER,
    DWRITE_PARAGRAPH_ALIGNMENT_NEAR, DWRITE_TEXT_ALIGNMENT_CENTER, DWRITE_TEXT_ALIGNMENT_LEADING,
    DWRITE_TEXT_ALIGNMENT_TRAILING, DWRITE_TEXT_METRICS, DWRITE_TRIMMING,
    DWRITE_TRIMMING_GRANULARITY_CHARACTER, DWRITE_UNICODE_RANGE, DWRITE_WORD_WRAPPING_NO_WRAP,
    DWRITE_WORD_WRAPPING_WRAP,
};
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_B8G8R8A8_UNORM;
use windows_core::{Interface, Result, BOOL, HSTRING, PCWSTR};

const LOCALE: &str = "ja-JP";
/// 日本語の書体(英数字の書体に無い字はこれで描く)
const JAPANESE_FAMILY: &str = "Yu Gothic UI";
/// 英数字の書体(Windows 11)．無ければ日本語の書体だけで描く
const TEXT_FAMILY: &str = "Segoe UI Variable Text";
const DISPLAY_FAMILY: &str = "Segoe UI Variable Display";
/// 絵の書体(Windows 11，無ければ Windows 10)
const ICON_FAMILIES: [&str; 2] = ["Segoe Fluent Icons", "Segoe MDL2 Assets"];
const BASE_DPI: f32 = 96.0;
/// 組んだ文字を覚える数の上限
const LAYOUT_CACHE_LIMIT: usize = 4096;

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
struct LayoutKey {
    text: String,
    style: TextStyle,
    layout: TextLayout,
    width: u32,
    height: u32,
}

/// Direct2D の点(windows_numerics::Vector2)を，その型の名前を出さずに作る(依存を増やさない．candidate-ui と同じ)
macro_rules! vector {
    ($x:expr, $y:expr) => {{
        let mut point = D2D1_ELLIPSE::default().point;
        point.X = $x;
        point.Y = $y;
        point
    }};
}

/// 描く道具の工場と書体．窓と開いた一覧で共有する
pub struct Graphics {
    d2d: ID2D1Factory,
    dwrite: IDWriteFactory2,
    text_family: &'static str,
    display_family: &'static str,
    icon_family: &'static str,
    fallback: Option<IDWriteFontFallback>,
    formats: RefCell<HashMap<(TextStyle, TextLayout), IDWriteTextFormat>>,
    /// 組んだ文字(同じ文字を同じ大きさで描くあいだは組み直さない)
    layouts: RefCell<HashMap<LayoutKey, IDWriteTextLayout>>,
    round: ID2D1StrokeStyle,
}

impl Graphics {
    pub fn new() -> Result<Self> {
        // SAFETY: 引数は定数
        let d2d: ID2D1Factory =
            unsafe { D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, None)? };
        // SAFETY: 引数は定数
        let dwrite: IDWriteFactory2 = unsafe { DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED)? };
        let mut collection = None;
        // SAFETY: collection は書き込める領域
        let _ = unsafe { dwrite.GetSystemFontCollection(&mut collection, false) };
        let installed = |family: &str| contains(collection.as_ref(), family);
        let text_family = if installed(TEXT_FAMILY) {
            TEXT_FAMILY
        } else {
            JAPANESE_FAMILY
        };
        let display_family = if installed(DISPLAY_FAMILY) {
            DISPLAY_FAMILY
        } else {
            text_family
        };
        let icon_family = ICON_FAMILIES
            .iter()
            .copied()
            .find(|family| installed(family))
            .unwrap_or(ICON_FAMILIES[1]);
        let fallback = japanese_fallback(&dwrite).ok();
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
        Ok(Self {
            d2d,
            dwrite,
            text_family,
            display_family,
            icon_family,
            fallback,
            formats: RefCell::new(HashMap::new()),
            layouts: RefCell::new(HashMap::new()),
            round,
        })
    }

    fn format(&self, style: TextStyle, layout: TextLayout) -> Option<IDWriteTextFormat> {
        if let Some(format) = self.formats.borrow().get(&(style, layout)) {
            return Some(format.clone());
        }
        let format = self.create_format(style, layout).ok()?;
        self.formats
            .borrow_mut()
            .insert((style, layout), format.clone());
        Some(format)
    }

    fn create_format(&self, style: TextStyle, layout: TextLayout) -> Result<IDWriteTextFormat> {
        let (family, size, weight): (&str, f32, DWRITE_FONT_WEIGHT) = match style {
            TextStyle::Title => (
                self.display_family,
                size::TITLE_FONT_SIZE,
                DWRITE_FONT_WEIGHT_SEMI_BOLD,
            ),
            TextStyle::Section => (
                self.text_family,
                size::SECTION_FONT_SIZE,
                DWRITE_FONT_WEIGHT_SEMI_BOLD,
            ),
            TextStyle::Body => (
                self.text_family,
                size::BODY_FONT_SIZE,
                DWRITE_FONT_WEIGHT_NORMAL,
            ),
            TextStyle::Caption => (
                self.text_family,
                size::CAPTION_FONT_SIZE,
                DWRITE_FONT_WEIGHT_NORMAL,
            ),
            TextStyle::NavHeader => (
                self.text_family,
                size::NAV_HEADER_FONT_SIZE,
                DWRITE_FONT_WEIGHT_SEMI_BOLD,
            ),
            TextStyle::Icon => (
                self.icon_family,
                size::ICON_FONT_SIZE,
                DWRITE_FONT_WEIGHT_NORMAL,
            ),
            TextStyle::IconSmall => (
                self.icon_family,
                size::CHEVRON_SIZE,
                DWRITE_FONT_WEIGHT_NORMAL,
            ),
        };
        // SAFETY: 文字列は呼び出しのあいだ有効
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
        // SAFETY: format は作ったばかりの COM の参照
        unsafe {
            format.SetTextAlignment(match layout.align {
                Align::Leading => DWRITE_TEXT_ALIGNMENT_LEADING,
                Align::Center => DWRITE_TEXT_ALIGNMENT_CENTER,
                Align::Trailing => DWRITE_TEXT_ALIGNMENT_TRAILING,
            })?;
            format.SetParagraphAlignment(if layout.center {
                DWRITE_PARAGRAPH_ALIGNMENT_CENTER
            } else {
                DWRITE_PARAGRAPH_ALIGNMENT_NEAR
            })?;
            if layout.wrap {
                format.SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP)?;
            } else {
                format.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP)?;
                // はみ出したら「…」にする
                let sign = self.dwrite.CreateEllipsisTrimmingSign(&format)?;
                let trimming = DWRITE_TRIMMING {
                    granularity: DWRITE_TRIMMING_GRANULARITY_CHARACTER,
                    delimiter: 0,
                    delimiterCount: 0,
                };
                format.SetTrimming(&trimming, &sign)?;
            }
            if let (Some(fallback), Ok(format1)) =
                (&self.fallback, format.cast::<IDWriteTextFormat1>())
            {
                let _ = format1.SetFontFallback(fallback);
            }
        }
        Ok(format)
    }

    /// 組んだ文字．覚えておき，次に同じ文字を同じ大きさで描くときに使う
    fn layout(
        &self,
        text: &str,
        style: TextStyle,
        layout: TextLayout,
        width: f32,
        height: f32,
    ) -> Option<IDWriteTextLayout> {
        let key = LayoutKey {
            text: text.to_string(),
            style,
            layout,
            width: width.to_bits(),
            height: height.to_bits(),
        };
        if let Some(found) = self.layouts.borrow().get(&key) {
            return Some(found.clone());
        }
        let format = self.format(style, layout)?;
        let wide: Vec<u16> = text.encode_utf16().collect();
        // SAFETY: format は生きている COM の参照で，wide は呼び出しのあいだ有効
        let created = unsafe {
            self.dwrite
                .CreateTextLayout(&wide, &format, width.max(0.0), height.max(0.0))
                .ok()?
        };
        let mut layouts = self.layouts.borrow_mut();
        // 覚える数に上限を設ける(大きさを変え続けても増え続けない)
        if layouts.len() >= LAYOUT_CACHE_LIMIT {
            layouts.clear();
        }
        layouts.insert(key, created.clone());
        Some(created)
    }

    /// 文字の大きさ．測るときに組んだ文字は覚えておき，同じ幅で描くときに使う(長い文を 2 回組まない)
    fn metrics(
        &self,
        text: &str,
        style: TextStyle,
        layout: TextLayout,
        width: f32,
    ) -> Option<DWRITE_TEXT_METRICS> {
        let text_layout = self.layout(text, style, layout, width, f32::MAX)?;
        let mut metrics = DWRITE_TEXT_METRICS::default();
        // SAFETY: metrics は書き込める領域
        unsafe { text_layout.GetMetrics(&mut metrics).ok()? };
        Some(metrics)
    }
}

impl Measure for Graphics {
    fn width(&self, text: &str, style: TextStyle) -> f32 {
        self.metrics(text, style, TextLayout::LINE, f32::MAX)
            .map_or(0.0, |metrics| metrics.widthIncludingTrailingWhitespace)
    }

    fn wrapped_height(&self, text: &str, style: TextStyle, width: f32) -> f32 {
        self.metrics(text, style, TextLayout::WRAP, width.max(1.0))
            .map_or(0.0, |metrics| metrics.height)
    }
}

/// 英数字の書体に無い字を日本語の書体で描く決まり(残りは OS の決まり)
fn japanese_fallback(dwrite: &IDWriteFactory2) -> Result<IDWriteFontFallback> {
    // SAFETY: 工場は生きている COM の参照．名前の文字列は呼び出しのあいだ有効
    unsafe {
        let builder = dwrite.CreateFontFallbackBuilder()?;
        let family = HSTRING::from(JAPANESE_FAMILY);
        let ranges = [DWRITE_UNICODE_RANGE {
            first: 0x0000,
            last: 0x10FFFF,
        }];
        let families = [family.as_ptr()];
        builder.AddMapping(
            &ranges,
            &families,
            None,
            &HSTRING::from(LOCALE),
            PCWSTR::null(),
            1.0,
        )?;
        let system = dwrite.GetSystemFontFallback()?;
        builder.AddMappings(&system)?;
        builder.CreateFontFallback()
    }
}

fn contains(collection: Option<&IDWriteFontCollection>, family: &str) -> bool {
    let Some(collection) = collection else {
        return false;
    };
    let mut index = 0;
    let mut exists = BOOL::default();
    // SAFETY: collection は生きている COM の参照で，index と exists は書き込める領域
    let found = unsafe {
        collection
            .FindFamilyName(&HSTRING::from(family), &mut index, &mut exists)
            .is_ok()
    };
    found && exists.as_bool()
}

/// 1 つの窓の描き先．窓の大きさ・DPI が変わったら合わせ，描き先を失ったら作り直す
pub struct Surface {
    window: HWND,
    target: Option<ID2D1HwndRenderTarget>,
    preview: Option<(u64, ID2D1Bitmap)>,
}

/// 外観の見本の画像(窓の DPI のピクセル．BGRA)．generation が変わったら描き先の画像を作り直す
pub struct PreviewPixels {
    pub generation: u64,
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
}

impl Surface {
    pub fn new(window: HWND) -> Self {
        Self {
            window,
            target: None,
            preview: None,
        }
    }

    fn ensure(
        &mut self,
        graphics: &Graphics,
        width: u32,
        height: u32,
        dpi: u32,
    ) -> Result<ID2D1HwndRenderTarget> {
        let size = D2D_SIZE_U {
            width: width.max(1),
            height: height.max(1),
        };
        if let Some(target) = &self.target {
            // SAFETY: target は生きている COM の参照
            unsafe {
                if target.GetPixelSize() != size {
                    target.Resize(&size)?;
                }
                target.SetDpi(dpi as f32, dpi as f32);
            }
            return Ok(target.clone());
        }
        // 地を透明で描いたところに Mica が見えるよう，アルファを持つ描き先にする
        let properties = D2D1_RENDER_TARGET_PROPERTIES {
            pixelFormat: D2D1_PIXEL_FORMAT {
                format: DXGI_FORMAT_B8G8R8A8_UNORM,
                alphaMode: D2D1_ALPHA_MODE_PREMULTIPLIED,
            },
            dpiX: dpi as f32,
            dpiY: dpi as f32,
            ..Default::default()
        };
        let hwnd_properties = D2D1_HWND_RENDER_TARGET_PROPERTIES {
            hwnd: self.window,
            pixelSize: size,
            presentOptions: D2D1_PRESENT_OPTIONS_NONE,
        };
        // SAFETY: properties と hwnd_properties は呼び出しのあいだ有効．window はこのスレッドの窓
        let target = unsafe {
            graphics
                .d2d
                .CreateHwndRenderTarget(&properties, &hwnd_properties)?
        };
        // SAFETY: 作ったばかりの描き先
        unsafe { target.SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE) };
        self.preview = None;
        self.target = Some(target.clone());
        Ok(target)
    }

    /// 描く．draw に Canvas を渡し，描き終えたら画面に出す(EndDraw は画面の更新を待つので，動きの速さは画面に揃う)
    pub fn draw(
        &mut self,
        graphics: &Graphics,
        size: (i32, i32),
        dpi: u32,
        clear: Color,
        preview: Option<&PreviewPixels>,
        draw: impl FnOnce(&mut dyn Canvas),
    ) -> Result<()> {
        let width = u32::try_from(size.0).unwrap_or(0);
        let height = u32::try_from(size.1).unwrap_or(0);
        let target = self.ensure(graphics, width, height, dpi)?;
        let bitmap = self.preview_bitmap(&target, preview, dpi);
        let render: ID2D1RenderTarget = target.cast()?;
        // SAFETY: target は生きている COM の参照．BeginDraw と EndDraw を対にする
        let brush = unsafe {
            render.BeginDraw();
            render.Clear(Some(&color(clear, 1.0)));
            render.CreateSolidColorBrush(&color(clear, 1.0), None)
        };
        if let Ok(brush) = brush {
            let mut canvas = D2dCanvas {
                graphics,
                target: &render,
                brush,
                dx: 0.0,
                dy: 0.0,
                opacity: 1.0,
                pixel: BASE_DPI / dpi as f32,
                preview: bitmap,
            };
            draw(&mut canvas);
        }
        // SAFETY: 同上
        let ended = unsafe { render.EndDraw(None, None) };
        if let Err(error) = ended {
            if error.code() == D2DERR_RECREATE_TARGET {
                // 次に描くときに作り直す
                self.target = None;
                self.preview = None;
                return Ok(());
            }
            return Err(error);
        }
        Ok(())
    }

    fn preview_bitmap(
        &mut self,
        target: &ID2D1HwndRenderTarget,
        pixels: Option<&PreviewPixels>,
        dpi: u32,
    ) -> Option<ID2D1Bitmap> {
        let pixels = pixels?;
        if let Some((generation, bitmap)) = &self.preview {
            if *generation == pixels.generation {
                return Some(bitmap.clone());
            }
        }
        let properties = D2D1_BITMAP_PROPERTIES {
            pixelFormat: D2D1_PIXEL_FORMAT {
                format: DXGI_FORMAT_B8G8R8A8_UNORM,
                alphaMode: D2D1_ALPHA_MODE_IGNORE,
            },
            dpiX: dpi as f32,
            dpiY: dpi as f32,
        };
        // SAFETY: pixels は width × height × 4 バイトで，呼び出しのあいだ有効
        let bitmap = unsafe {
            target.CreateBitmap(
                D2D_SIZE_U {
                    width: pixels.width,
                    height: pixels.height,
                },
                Some(pixels.pixels.as_ptr().cast()),
                pixels.width * 4,
                &properties,
            )
        }
        .ok()?;
        self.preview = Some((pixels.generation, bitmap.clone()));
        Some(bitmap)
    }
}

fn color(color: Color, opacity: f32) -> D2D1_COLOR_F {
    D2D1_COLOR_F {
        r: color.red,
        g: color.green,
        b: color.blue,
        a: color.alpha * opacity,
    }
}

struct D2dCanvas<'a> {
    graphics: &'a Graphics,
    target: &'a ID2D1RenderTarget,
    brush: ID2D1SolidColorBrush,
    dx: f32,
    dy: f32,
    opacity: f32,
    pixel: f32,
    preview: Option<ID2D1Bitmap>,
}

impl D2dCanvas<'_> {
    fn paint(&self, value: Color) {
        // SAFETY: brush は生きている COM の参照
        unsafe { self.brush.SetColor(&color(value, self.opacity)) };
    }

    fn rect(&self, rect: Rect) -> D2D_RECT_F {
        D2D_RECT_F {
            left: rect.x + self.dx,
            top: rect.y + self.dy,
            right: rect.max_x() + self.dx,
            bottom: rect.max_y() + self.dy,
        }
    }

    /// 線の幅の半分だけ内側に寄せ，デバイスのピクセルにそろえる(1 ピクセルの線をぼかさない)
    fn stroke_rect(&self, rect: Rect, width: f32) -> D2D_RECT_F {
        let snap = |value: f32| (value / self.pixel).round() * self.pixel;
        let inset = width / 2.0;
        D2D_RECT_F {
            left: snap(rect.x + self.dx) + inset,
            top: snap(rect.y + self.dy) + inset,
            right: snap(rect.max_x() + self.dx) - inset,
            bottom: snap(rect.max_y() + self.dy) - inset,
        }
    }
}

impl Measure for D2dCanvas<'_> {
    fn width(&self, text: &str, style: TextStyle) -> f32 {
        self.graphics.width(text, style)
    }

    fn wrapped_height(&self, text: &str, style: TextStyle, width: f32) -> f32 {
        self.graphics.wrapped_height(text, style, width)
    }
}

impl Canvas for D2dCanvas<'_> {
    fn fill_rect(&mut self, rect: Rect, value: Color) {
        if value.alpha <= 0.0 {
            return;
        }
        self.paint(value);
        // SAFETY: target と brush は生きている COM の参照
        unsafe { self.target.FillRectangle(&self.rect(rect), &self.brush) };
    }

    fn fill_round(&mut self, rect: Rect, radius: f32, value: Color) {
        if value.alpha <= 0.0 || rect.width <= 0.0 || rect.height <= 0.0 {
            return;
        }
        self.paint(value);
        let shape = D2D1_ROUNDED_RECT {
            rect: self.rect(rect),
            radiusX: radius,
            radiusY: radius,
        };
        // SAFETY: 同上
        unsafe { self.target.FillRoundedRectangle(&shape, &self.brush) };
    }

    fn stroke_round(&mut self, rect: Rect, radius: f32, width: f32, value: Color) {
        if value.alpha <= 0.0 || rect.width <= 0.0 || rect.height <= 0.0 {
            return;
        }
        self.paint(value);
        let shape = D2D1_ROUNDED_RECT {
            rect: self.stroke_rect(rect, width),
            radiusX: (radius - width / 2.0).max(0.0),
            radiusY: (radius - width / 2.0).max(0.0),
        };
        // SAFETY: 同上
        unsafe {
            self.target
                .DrawRoundedRectangle(&shape, &self.brush, width, None)
        };
    }

    fn text(&mut self, rect: Rect, text: &str, style: TextStyle, value: Color, layout: TextLayout) {
        if text.is_empty() || value.alpha <= 0.0 {
            return;
        }
        let Some(text_layout) = self
            .graphics
            .layout(text, style, layout, rect.width, rect.height)
        else {
            return;
        };
        self.paint(value);
        // SAFETY: 同上
        unsafe {
            self.target.DrawTextLayout(
                vector!(rect.x + self.dx, rect.y + self.dy),
                &text_layout,
                &self.brush,
                D2D1_DRAW_TEXT_OPTIONS_CLIP,
            )
        };
    }

    fn arc(&mut self, arc: Arc, value: Color) {
        let Arc {
            x,
            y,
            radius,
            start,
            sweep,
            width,
        } = arc;
        let point = |degrees: f32| {
            let radians = degrees.to_radians();
            (
                x + self.dx + radius * radians.sin(),
                y + self.dy - radius * radians.cos(),
            )
        };
        let sweep = sweep.clamp(1.0, 359.0);
        let (from_x, from_y) = point(start);
        let (to_x, to_y) = point(start + sweep);
        // SAFETY: factory は生きている COM の参照．sink は閉じるまでこの関数の中だけで使う
        let geometry = unsafe {
            let Ok(path) = self.graphics.d2d.CreatePathGeometry() else {
                return;
            };
            let Ok(sink) = path.Open() else {
                return;
            };
            sink.BeginFigure(vector!(from_x, from_y), D2D1_FIGURE_BEGIN_HOLLOW);
            sink.AddArc(&D2D1_ARC_SEGMENT {
                point: vector!(to_x, to_y),
                size: D2D_SIZE_F {
                    width: radius,
                    height: radius,
                },
                rotationAngle: 0.0,
                sweepDirection: D2D1_SWEEP_DIRECTION_CLOCKWISE,
                arcSize: if sweep > 180.0 {
                    D2D1_ARC_SIZE_LARGE
                } else {
                    D2D1_ARC_SIZE_SMALL
                },
            });
            sink.EndFigure(D2D1_FIGURE_END_OPEN);
            if sink.Close().is_err() {
                return;
            }
            path
        };
        self.paint(value);
        // SAFETY: 同上
        unsafe {
            self.target
                .DrawGeometry(&geometry, &self.brush, width, &self.graphics.round)
        };
    }

    fn preview(&mut self, rect: Rect) {
        let Some(bitmap) = &self.preview else {
            return;
        };
        // SAFETY: target と bitmap は生きている COM の参照
        unsafe {
            let size = bitmap.GetSize();
            // 画像は等倍で真ん中に置く(作るときに rect に収めている)
            let left = rect.x + (rect.width - size.width) / 2.0;
            let top = rect.y + (rect.height - size.height) / 2.0;
            let destination = self.rect(Rect::new(
                (left / self.pixel).round() * self.pixel,
                (top / self.pixel).round() * self.pixel,
                size.width,
                size.height,
            ));
            self.target.DrawBitmap(
                bitmap,
                Some(&destination),
                self.opacity,
                D2D1_BITMAP_INTERPOLATION_MODE_LINEAR,
                None,
            );
        }
    }

    fn push_clip(&mut self, rect: Rect) {
        // SAFETY: target は生きている COM の参照．pop_clip と対にする
        unsafe {
            self.target
                .PushAxisAlignedClip(&self.rect(rect), D2D1_ANTIALIAS_MODE_PER_PRIMITIVE)
        };
    }

    fn pop_clip(&mut self) {
        // SAFETY: push_clip と対にする
        unsafe { self.target.PopAxisAlignedClip() };
    }

    fn translate(&mut self, dx: f32, dy: f32) {
        self.dx += dx;
        self.dy += dy;
    }

    fn set_opacity(&mut self, opacity: f32) {
        self.opacity = opacity.clamp(0.0, 1.0);
    }
}

/// 外観の見本の描き方
pub struct PreviewRequest<'a> {
    pub theme: &'a candidate_ui::theme::ResolvedTheme,
    pub font_size: f32,
    pub dark: bool,
    /// 画面の DPI の倍率
    pub scale: f32,
    /// 見本の外の地
    pub background: tokens::Rgb,
}

/// 外観の見本を，窓の DPI のピクセルで width × height の画像にする(GDI の DC に描く Preview を使う)
pub fn render_preview(
    preview: &candidate_ui::app::preview::Preview,
    width: u32,
    height: u32,
    request: &PreviewRequest,
) -> Option<Vec<u8>> {
    let background = request.background;
    use windows::Win32::Foundation::RECT;
    use windows::Win32::Graphics::Gdi::{
        CreateCompatibleDC, CreateDIBSection, DeleteDC, DeleteObject, SelectObject, BITMAPINFO,
        BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS, HGDIOBJ,
    };
    if width == 0 || height == 0 {
        return None;
    }
    let info = BITMAPINFO {
        bmiHeader: BITMAPINFOHEADER {
            biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
            biWidth: i32::try_from(width).ok()?,
            // 上から下へ並べる
            biHeight: -i32::try_from(height).ok()?,
            biPlanes: 1,
            biBitCount: 32,
            biCompression: BI_RGB.0,
            ..Default::default()
        },
        ..Default::default()
    };
    // SAFETY: DC と DIB はこの関数の中で作って消す．bits は DIB を消すまで width × height × 4 バイト
    unsafe {
        let dc = CreateCompatibleDC(None);
        let mut bits = std::ptr::null_mut();
        let Ok(bitmap) = CreateDIBSection(Some(dc), &info, DIB_RGB_COLORS, &mut bits, None, 0)
        else {
            let _ = DeleteDC(dc);
            return None;
        };
        let old = SelectObject(dc, HGDIOBJ(bitmap.0));
        let length = (width * height * 4) as usize;
        let pixels = std::slice::from_raw_parts_mut(bits.cast::<u8>(), length);
        let fill = [background.blue, background.green, background.red, 0xFF];
        for (index, byte) in pixels.iter_mut().enumerate() {
            *byte = fill[index % 4];
        }
        let rect = RECT {
            left: 0,
            top: 0,
            right: width as i32,
            bottom: height as i32,
        };
        let painted = preview
            .paint(
                dc,
                rect,
                request.theme,
                request.font_size,
                request.dark,
                request.scale,
            )
            .is_ok();
        let result = painted.then(|| pixels.to_vec());
        SelectObject(dc, old);
        let _ = DeleteObject(HGDIOBJ(bitmap.0));
        let _ = DeleteDC(dc);
        result
    }
}
