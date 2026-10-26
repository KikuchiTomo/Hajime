use crate::handwriting::ink::Ink;
use crate::handwriting::layout::{Layout, TextWidth};
use crate::handwriting::strings;
use crate::scene::Frame;
use tokens::size::{candidate, handwriting};
use tokens::{Palette, Rgb};
use windows::Win32::Foundation::HWND;
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_ALPHA_MODE_PREMULTIPLIED, D2D1_COLOR_F, D2D1_PIXEL_FORMAT, D2D_RECT_F, D2D_SIZE_U,
};
use windows::Win32::Graphics::Direct2D::{
    D2D1CreateFactory, ID2D1Factory, ID2D1HwndRenderTarget, ID2D1SolidColorBrush, ID2D1StrokeStyle,
    D2D1_CAP_STYLE_ROUND, D2D1_DRAW_TEXT_OPTIONS_CLIP, D2D1_ELLIPSE,
    D2D1_FACTORY_TYPE_SINGLE_THREADED, D2D1_HWND_RENDER_TARGET_PROPERTIES, D2D1_LINE_JOIN_ROUND,
    D2D1_PRESENT_OPTIONS_NONE, D2D1_RENDER_TARGET_PROPERTIES, D2D1_STROKE_STYLE_PROPERTIES,
};
use windows::Win32::Graphics::DirectWrite::{
    DWriteCreateFactory, IDWriteFactory, IDWriteTextFormat, DWRITE_FACTORY_TYPE_SHARED,
    DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_WEIGHT_NORMAL,
    DWRITE_MEASURING_MODE_NATURAL, DWRITE_PARAGRAPH_ALIGNMENT_CENTER, DWRITE_TEXT_ALIGNMENT,
    DWRITE_TEXT_ALIGNMENT_CENTER, DWRITE_TEXT_ALIGNMENT_LEADING, DWRITE_TEXT_METRICS,
    DWRITE_WORD_WRAPPING_NO_WRAP,
};
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_B8G8R8A8_UNORM;
use windows_core::{Result, HSTRING};
use windows_numerics::Vector2;

const FONT_FAMILY: &str = "Yu Gothic UI";
const LOCALE: &str = "ja-JP";

/// 書体．見出しと案内は小さい字，候補とボタンは候補ウィンドウと同じ大きさ
pub struct Fonts {
    dwrite: IDWriteFactory,
    label: IDWriteTextFormat,
    label_centered: IDWriteTextFormat,
    candidate: IDWriteTextFormat,
}

impl Fonts {
    pub fn label_height(&self) -> f32 {
        self.metrics("あ", &self.label)
            .map_or(candidate::LABEL_FONT_SIZE, |metrics| metrics.height)
    }

    fn metrics(&self, text: &str, format: &IDWriteTextFormat) -> Option<DWRITE_TEXT_METRICS> {
        let wide: Vec<u16> = text.encode_utf16().collect();
        // SAFETY: wide と format はこの呼び出しのあいだ生きている
        let layout = unsafe {
            self.dwrite
                .CreateTextLayout(&wide, format, f32::MAX, f32::MAX)
                .ok()?
        };
        let mut metrics = DWRITE_TEXT_METRICS::default();
        // SAFETY: metrics は書き込める場所を指す
        unsafe { layout.GetMetrics(&mut metrics).ok()? };
        Some(metrics)
    }
}

impl TextWidth for Fonts {
    fn width(&self, text: &str) -> f32 {
        self.metrics(text, &self.candidate)
            .map_or(0.0, |metrics| metrics.widthIncludingTrailingWhitespace)
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

    pub fn fonts(&self, font_size: f32) -> Result<Fonts> {
        Ok(Fonts {
            dwrite: self.dwrite.clone(),
            label: self.format(candidate::LABEL_FONT_SIZE, DWRITE_TEXT_ALIGNMENT_LEADING)?,
            label_centered: self
                .format(candidate::LABEL_FONT_SIZE, DWRITE_TEXT_ALIGNMENT_CENTER)?,
            candidate: self.format(font_size, DWRITE_TEXT_ALIGNMENT_CENTER)?,
        })
    }

    fn format(&self, size: f32, alignment: DWRITE_TEXT_ALIGNMENT) -> Result<IDWriteTextFormat> {
        // SAFETY: 文字列はこの呼び出しのあいだ生きている
        let format = unsafe {
            self.dwrite.CreateTextFormat(
                &HSTRING::from(FONT_FAMILY),
                None,
                DWRITE_FONT_WEIGHT_NORMAL,
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

    /// 窓の中身を描く．note は候補の行に出す案内(認識できないときなど)
    #[allow(clippy::too_many_arguments)]
    pub fn draw(
        &mut self,
        hwnd: HWND,
        scale: f32,
        layout: &Layout,
        ink: &Ink,
        note: Option<&str>,
        palette: &Palette,
        fonts: &Fonts,
    ) -> Result<()> {
        let width = (layout.width * scale).ceil() as u32;
        let height = (layout.height * scale).ceil() as u32;
        let target = self.target(hwnd, width.max(1), height.max(1))?;
        // SAFETY: 描画先と筆はこの関数の中だけで使う
        let brush = unsafe { target.CreateSolidColorBrush(&color(palette.surface), None)? };
        let painter = Painter {
            target: &target,
            brush: &brush,
            round: &self.round,
        };
        // SAFETY: BeginDraw と EndDraw の対の中で描く
        unsafe {
            target.SetDpi(96.0 * scale, 96.0 * scale);
            target.BeginDraw();
            target.Clear(Some(&color(palette.surface)));
        }
        painter.paint(layout, ink, note, palette, fonts);
        // SAFETY: BeginDraw と対にする
        let result = unsafe { target.EndDraw(None, None) };
        if result.is_err() {
            self.target = None;
        }
        result
    }
}

struct Painter<'a> {
    target: &'a ID2D1HwndRenderTarget,
    brush: &'a ID2D1SolidColorBrush,
    round: &'a ID2D1StrokeStyle,
}

impl Painter<'_> {
    fn paint(
        &self,
        layout: &Layout,
        ink: &Ink,
        note: Option<&str>,
        palette: &Palette,
        fonts: &Fonts,
    ) {
        let line = handwriting::FRAME_WIDTH;
        let whole = Frame::new(0.0, 0.0, layout.width, layout.height);
        self.outline(&whole, palette.frame, candidate::FRAME_WIDTH);
        // 見出しの帯
        let title = Frame::new(
            candidate::PADDING_X,
            0.0,
            layout.close.x - candidate::PADDING_X,
            layout.header.height,
        );
        self.text(strings::TITLE, &title, &fonts.label, palette.text);
        self.text(
            strings::CLOSE,
            &layout.close,
            &fonts.label_centered,
            palette.text,
        );
        self.fill(
            &Frame::new(0.0, layout.header.max_y() - line, layout.width, line),
            palette.bevel_shadow,
        );
        // 書く欄．実線の枠と，破線の十字
        self.outline(&layout.canvas, palette.text_muted, line);
        for dash in layout.guide() {
            self.fill(&dash, palette.text_muted);
        }
        if ink.is_empty() {
            self.text(
                strings::PROMPT,
                &layout.canvas,
                &fonts.label_centered,
                palette.text_muted,
            );
        }
        self.strokes(layout, ink, palette.text);
        // 候補と消去
        for (frame, index) in &layout.chips {
            if let Some(text) = ink.candidates().get(*index) {
                self.outline(frame, palette.bevel_shadow, line);
                self.text(text, frame, &fonts.candidate, palette.text);
            }
        }
        if let Some(note) = note {
            let row = Frame::new(
                layout.canvas.x,
                layout.clear.y,
                layout.clear.x - layout.canvas.x,
                layout.clear.height,
            );
            self.text(note, &row, &fonts.label, palette.text_muted);
        }
        self.outline(&layout.clear, palette.bevel_shadow, line);
        self.text(
            strings::CLEAR,
            &layout.clear,
            &fonts.candidate,
            palette.text,
        );
    }

    fn strokes(&self, layout: &Layout, ink: &Ink, rgb: Rgb) {
        let width = handwriting::STROKE_WIDTH;
        let origin = |x: f32, y: f32| Vector2 {
            X: layout.canvas.x + x,
            Y: layout.canvas.y + y,
        };
        // SAFETY: BeginDraw と EndDraw の中で，生きている筆で描く
        unsafe {
            self.brush.SetColor(&color(rgb));
            for stroke in ink.strokes() {
                if let [only] = stroke.as_slice() {
                    let ellipse = D2D1_ELLIPSE {
                        point: origin(only.x, only.y),
                        radiusX: width / 2.0,
                        radiusY: width / 2.0,
                    };
                    self.target.FillEllipse(&ellipse, self.brush);
                    continue;
                }
                for pair in stroke.windows(2) {
                    self.target.DrawLine(
                        origin(pair[0].x, pair[0].y),
                        origin(pair[1].x, pair[1].y),
                        self.brush,
                        width,
                        self.round,
                    );
                }
            }
        }
    }

    fn fill(&self, frame: &Frame, rgb: Rgb) {
        // SAFETY: BeginDraw と EndDraw の中で，生きている筆で描く
        unsafe {
            self.brush.SetColor(&color(rgb));
            self.target.FillRectangle(&rect(frame), self.brush);
        }
    }

    fn outline(&self, frame: &Frame, rgb: Rgb, width: f32) {
        let inset = Frame::new(
            frame.x + width / 2.0,
            frame.y + width / 2.0,
            frame.width - width,
            frame.height - width,
        );
        // SAFETY: BeginDraw と EndDraw の中で，生きている筆で描く
        unsafe {
            self.brush.SetColor(&color(rgb));
            self.target
                .DrawRectangle(&rect(&inset), self.brush, width, None);
        }
    }

    fn text(&self, text: &str, frame: &Frame, format: &IDWriteTextFormat, rgb: Rgb) {
        let wide: Vec<u16> = text.encode_utf16().collect();
        // SAFETY: BeginDraw と EndDraw の中で，生きている筆と書式で描く
        unsafe {
            self.brush.SetColor(&color(rgb));
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

fn color(rgb: Rgb) -> D2D1_COLOR_F {
    D2D1_COLOR_F {
        r: f32::from(rgb.red) / 255.0,
        g: f32::from(rgb.green) / 255.0,
        b: f32::from(rgb.blue) / 255.0,
        a: 1.0,
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
