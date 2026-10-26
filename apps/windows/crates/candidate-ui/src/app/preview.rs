//! 設定の画面の外観の見本(macOS の ThemePreview)．候補ウィンドウと同じ描き方で，見本の分岐図を描く．
//! 設定の画面(s90-settings)が GDI の画面の中に描けるよう，DC に結び付ける Direct2D の描き先を使う

use super::render::Renderer;
use crate::scene::{self, sample, Look, Surround};
use crate::theme::ResolvedTheme;
use windows::Win32::Foundation::RECT;
use windows::Win32::Graphics::Direct2D::Common::{D2D1_ALPHA_MODE_IGNORE, D2D1_PIXEL_FORMAT};
use windows::Win32::Graphics::Direct2D::{
    ID2D1DCRenderTarget, ID2D1RenderTarget, D2D1_FEATURE_LEVEL_DEFAULT,
    D2D1_RENDER_TARGET_PROPERTIES, D2D1_RENDER_TARGET_TYPE_DEFAULT,
    D2D1_RENDER_TARGET_USAGE_GDI_COMPATIBLE,
};
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_B8G8R8A8_UNORM;
use windows::Win32::Graphics::Gdi::HDC;
use windows_core::{Interface, Result};

const BASE_DPI: f32 = 96.0;

pub struct Preview {
    renderer: Renderer,
    target: ID2D1DCRenderTarget,
}

impl Preview {
    pub fn new() -> Result<Self> {
        let renderer = Renderer::new()?;
        let properties = D2D1_RENDER_TARGET_PROPERTIES {
            r#type: D2D1_RENDER_TARGET_TYPE_DEFAULT,
            pixelFormat: D2D1_PIXEL_FORMAT {
                format: DXGI_FORMAT_B8G8R8A8_UNORM,
                alphaMode: D2D1_ALPHA_MODE_IGNORE,
            },
            dpiX: BASE_DPI,
            dpiY: BASE_DPI,
            usage: D2D1_RENDER_TARGET_USAGE_GDI_COMPATIBLE,
            minLevel: D2D1_FEATURE_LEVEL_DEFAULT,
        };
        // SAFETY: properties は呼び出しのあいだ有効
        let target = unsafe { renderer.factory().CreateDCRenderTarget(&properties)? };
        Ok(Self { renderer, target })
    }

    /// hdc の rect(デバイスのピクセル)の真ん中に，見本の分岐図を描く．scale は画面の DPI の倍率．
    /// 見本が rect より大きければ見本ごと縮める(macOS の ScaledPreview と同じ)
    pub fn paint(
        &self,
        hdc: HDC,
        rect: RECT,
        theme: &ResolvedTheme,
        font_size: f32,
        dark: bool,
        scale: f32,
    ) -> Result<()> {
        let measure = self.renderer.measure(theme, font_size)?;
        let look = Look::new(theme, font_size);
        let scene = scene::branch_map(&sample::branch(), &look, &measure);
        let scene = scene::surround(scene, theme, Surround::Snapshot { dark });
        let available_width = (rect.right - rect.left).max(0) as f32;
        let available_height = (rect.bottom - rect.top).max(0) as f32;
        if scene.width <= 0.0 || scene.height <= 0.0 {
            return Ok(());
        }
        let fit = (available_width / (scene.width * scale))
            .min(available_height / (scene.height * scale))
            .min(1.0);
        let shown = scale * fit;
        let width = (scene.width * shown).ceil() as i32;
        let height = (scene.height * shown).ceil() as i32;
        let left = rect.left + (rect.right - rect.left - width) / 2;
        let top = rect.top + (rect.bottom - rect.top - height) / 2;
        let bound = RECT {
            left,
            top,
            right: left + width,
            bottom: top + height,
        };
        let target: ID2D1RenderTarget = self.target.cast()?;
        // SAFETY: hdc は描いている途中の DC．BeginDraw と EndDraw を対にする
        unsafe {
            self.target.BindDC(hdc, &bound)?;
            target.SetDpi(BASE_DPI * shown, BASE_DPI * shown);
            target.BeginDraw();
        }
        let painted = self.renderer.paint(&target, &scene, &measure, shown, 1.0);
        // SAFETY: 同上
        unsafe { target.EndDraw(None, None)? };
        painted
    }
}
