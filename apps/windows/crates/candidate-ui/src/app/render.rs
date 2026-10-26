use super::window::Window;
use crate::scene::{Draw, Font, Frame, Measure, Role, Scene};
use tokens::{Palette, Rgb};
use windows::Win32::Foundation::HWND;
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_ALPHA_MODE_PREMULTIPLIED, D2D1_COLOR_F, D2D1_PIXEL_FORMAT, D2D_RECT_F, D2D_SIZE_U,
};
use windows::Win32::Graphics::Direct2D::{
    D2D1CreateFactory, ID2D1Factory, ID2D1HwndRenderTarget, D2D1_DRAW_TEXT_OPTIONS_CLIP,
    D2D1_FACTORY_TYPE_SINGLE_THREADED, D2D1_HWND_RENDER_TARGET_PROPERTIES,
    D2D1_PRESENT_OPTIONS_NONE, D2D1_RENDER_TARGET_PROPERTIES,
};
use windows::Win32::Graphics::DirectWrite::{
    DWriteCreateFactory, IDWriteFactory, IDWriteTextFormat, DWRITE_FACTORY_TYPE_SHARED,
    DWRITE_FONT_STRETCH_NORMAL, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_WEIGHT_NORMAL,
    DWRITE_MEASURING_MODE_NATURAL, DWRITE_PARAGRAPH_ALIGNMENT_CENTER, DWRITE_TEXT_METRICS,
    DWRITE_WORD_WRAPPING_NO_WRAP,
};
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_B8G8R8A8_UNORM;
use windows_core::{Result, HSTRING};

const FONT_FAMILY: &str = "Yu Gothic UI";
const LOCALE: &str = "ja-JP";
const DOT_STEP: f32 = 2.0;

pub struct Renderer {
    d2d: ID2D1Factory,
    dwrite: IDWriteFactory,
    target: Option<(isize, ID2D1HwndRenderTarget)>,
}

pub struct TextMeasure {
    dwrite: IDWriteFactory,
    candidate: IDWriteTextFormat,
    label: IDWriteTextFormat,
    mode: IDWriteTextFormat,
}

impl TextMeasure {
    fn format(&self, font: Font) -> &IDWriteTextFormat {
        match font {
            Font::Candidate => &self.candidate,
            Font::Label => &self.label,
            Font::Mode => &self.mode,
        }
    }

    fn metrics(&self, text: &str, font: Font) -> Option<DWRITE_TEXT_METRICS> {
        let wide: Vec<u16> = text.encode_utf16().collect();
        let layout = unsafe {
            self.dwrite
                .CreateTextLayout(&wide, self.format(font), f32::MAX, f32::MAX)
                .ok()?
        };
        let mut metrics = DWRITE_TEXT_METRICS::default();
        unsafe { layout.GetMetrics(&mut metrics).ok()? };
        Some(metrics)
    }
}

impl Measure for TextMeasure {
    fn width(&self, text: &str, font: Font) -> f32 {
        self.metrics(text, font).map_or(0.0, |metrics| {
            metrics.widthIncludingTrailingWhitespace.ceil()
        })
    }

    fn height(&self, font: Font) -> f32 {
        self.metrics("あ", font)
            .map_or(0.0, |metrics| metrics.height.ceil())
    }
}

impl Renderer {
    pub fn new() -> Result<Self> {
        let d2d = unsafe { D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, None)? };
        let dwrite = unsafe { DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED)? };
        Ok(Self {
            d2d,
            dwrite,
            target: None,
        })
    }

    pub fn measure(&self, font_size: f32) -> Result<TextMeasure> {
        Ok(TextMeasure {
            dwrite: self.dwrite.clone(),
            candidate: self.format(font_size)?,
            label: self.format(tokens::size::candidate::LABEL_FONT_SIZE)?,
            mode: self.format(tokens::size::mode_indicator::FONT_SIZE)?,
        })
    }

    fn format(&self, size: f32) -> Result<IDWriteTextFormat> {
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
        unsafe {
            format.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER)?;
            format.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP)?;
        }
        Ok(format)
    }

    fn target(
        &mut self,
        window: &Window,
        width: u32,
        height: u32,
    ) -> Result<ID2D1HwndRenderTarget> {
        let hwnd = window.hwnd();
        let size = D2D_SIZE_U { width, height };
        if let Some((owner, target)) = &self.target {
            if *owner == hwnd.0 as isize {
                unsafe { target.Resize(&size)? };
                return Ok(target.clone());
            }
        }
        let properties = D2D1_RENDER_TARGET_PROPERTIES {
            pixelFormat: D2D1_PIXEL_FORMAT {
                format: DXGI_FORMAT_B8G8R8A8_UNORM,
                alphaMode: D2D1_ALPHA_MODE_PREMULTIPLIED,
            },
            ..Default::default()
        };
        let target = unsafe {
            self.d2d.CreateHwndRenderTarget(
                &properties,
                &D2D1_HWND_RENDER_TARGET_PROPERTIES {
                    hwnd: HWND(hwnd.0),
                    pixelSize: size,
                    presentOptions: D2D1_PRESENT_OPTIONS_NONE,
                },
            )?
        };
        self.target = Some((hwnd.0 as isize, target.clone()));
        Ok(target)
    }

    pub fn draw(
        &mut self,
        window: &Window,
        scene: &Scene,
        palette: &Palette,
        measure: &TextMeasure,
    ) -> Result<()> {
        let scale = window.scale();
        let width = (scene.width * scale).ceil() as u32;
        let height = (scene.height * scale).ceil() as u32;
        let target = self.target(window, width.max(1), height.max(1))?;
        let brush = unsafe { target.CreateSolidColorBrush(&color(palette.surface, 1.0), None)? };
        unsafe {
            target.SetDpi(96.0 * scale, 96.0 * scale);
            target.BeginDraw();
            target.Clear(Some(&color(palette.surface, 1.0)));
        }
        for draw in &scene.draws {
            match draw {
                Draw::Fill { frame, role } => unsafe {
                    brush.SetColor(&color(rgb(palette, *role), 1.0));
                    target.FillRectangle(&rect(frame), &brush);
                },
                Draw::Text {
                    frame,
                    text,
                    font,
                    role,
                    opacity,
                } => unsafe {
                    brush.SetColor(&color(rgb(palette, *role), *opacity));
                    let wide: Vec<u16> = text.encode_utf16().collect();
                    target.DrawText(
                        &wide,
                        measure.format(*font),
                        &rect(frame),
                        &brush,
                        D2D1_DRAW_TEXT_OPTIONS_CLIP,
                        DWRITE_MEASURING_MODE_NATURAL,
                    );
                },
                Draw::Dots { frame, role } => unsafe {
                    brush.SetColor(&color(rgb(palette, *role), 1.0));
                    let mut x = frame.x;
                    while x < frame.max_x() {
                        let dot = Frame::new(
                            x,
                            frame.y,
                            (DOT_STEP / 2.0).min(frame.max_x() - x),
                            frame.height,
                        );
                        target.FillRectangle(&rect(&dot), &brush);
                        x += DOT_STEP;
                    }
                },
            }
        }
        let result = unsafe { target.EndDraw(None, None) };
        if result.is_err() {
            self.target = None;
        }
        result
    }
}

fn rgb(palette: &Palette, role: Role) -> Rgb {
    match role {
        Role::Surface => palette.surface,
        Role::BevelLight => palette.bevel_light,
        Role::BevelShadow => palette.bevel_shadow,
        Role::Frame => palette.frame,
        Role::Text => palette.text,
        Role::TextMuted => palette.text_muted,
        Role::Selection => palette.selection,
        Role::SelectionText => palette.selection_text,
        Role::Correction => palette.correction,
    }
}

fn color(rgb: Rgb, alpha: f32) -> D2D1_COLOR_F {
    D2D1_COLOR_F {
        r: f32::from(rgb.red) / 255.0,
        g: f32::from(rgb.green) / 255.0,
        b: f32::from(rgb.blue) / 255.0,
        a: alpha,
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
