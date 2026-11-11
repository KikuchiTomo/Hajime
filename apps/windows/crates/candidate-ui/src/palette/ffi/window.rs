//! パレットの窓(Win32)．候補の窓と同じく入力先のアプリからフォーカスを奪わず，いちばん上に出す．
//! 押した・ポインタを動かした・ホイールを回したことを，窓の中の DIP の座標で Controller に知らせる

use crate::app::render::{Renderer, TextMeasure};
use crate::geometry::Bounds;
use crate::scene::Scene;
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, POINT, RECT, WPARAM};
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_ALPHA_MODE_PREMULTIPLIED, D2D1_PIXEL_FORMAT, D2D_SIZE_U,
};
use windows::Win32::Graphics::Direct2D::{
    ID2D1HwndRenderTarget, D2D1_HWND_RENDER_TARGET_PROPERTIES, D2D1_PRESENT_OPTIONS_NONE,
    D2D1_RENDER_TARGET_PROPERTIES,
};
use windows::Win32::Graphics::Dwm::{
    DwmExtendFrameIntoClientArea, DwmSetWindowAttribute, DWMWA_BORDER_COLOR, DWMWA_COLOR_NONE,
    DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_DONOTROUND, DWMWINDOWATTRIBUTE,
};
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_B8G8R8A8_UNORM;
use windows::Win32::Graphics::Gdi::{
    BeginPaint, EndPaint, GetMonitorInfoW, MonitorFromRect, ScreenToClient, MONITORINFO,
    MONITOR_DEFAULTTONEAREST, PAINTSTRUCT,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::Accessibility::{
    NotificationKind_ActionCompleted, NotificationProcessing_ImportantMostRecent,
    UiaHostProviderFromHwnd, UiaRaiseNotificationEvent,
};
use windows::Win32::UI::Controls::{MARGINS, WM_MOUSELEAVE};
use windows::Win32::UI::HiDpi::GetDpiForWindow;
use windows::Win32::UI::Input::KeyboardAndMouse::{TrackMouseEvent, TME_LEAVE, TRACKMOUSEEVENT};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, GetCursorPos, LoadCursorW, RegisterClassExW, SetWindowPos,
    ShowWindow, HWND_TOPMOST, IDC_ARROW, MA_NOACTIVATE, SWP_NOACTIVATE, SWP_SHOWWINDOW, SW_HIDE,
    WHEEL_DELTA, WM_LBUTTONDOWN, WM_MOUSEACTIVATE, WM_MOUSEMOVE, WM_MOUSEWHEEL, WM_PAINT,
    WNDCLASSEXW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_POPUP,
};
use windows_core::{w, Result, BSTR, PCWSTR};

const CLASS: PCWSTR = w!("hajime.palette");
const BASE_DPI: f32 = 96.0;
/// 読み上げの種類の名前．同じ名前の読み上げは新しいものが前のものを置き換える
const ANNOUNCEMENT_ID: &str = "hajime.palette";

/// 窓に届いたことのうち，パレットが扱うもの．座標は窓の中の DIP
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Event {
    Press(f32, f32),
    Move(f32, f32),
    /// ポインタが窓の外に出た
    Leave,
    /// ホイールを回した目盛りの数(奥へ回すと正．細かく回せるホイールは端数になる)
    Wheel(f32),
    Paint,
}

pub type Handler = fn(Event);

static HANDLER: std::sync::OnceLock<Handler> = std::sync::OnceLock::new();

pub struct Window {
    hwnd: HWND,
    target: Option<ID2D1HwndRenderTarget>,
}

/// DWM の属性を書く
fn set_attribute<T>(hwnd: HWND, attribute: DWMWINDOWATTRIBUTE, value: &T) {
    // SAFETY: value は size_of::<T>() バイトの読める値
    let _ = unsafe {
        DwmSetWindowAttribute(
            hwnd,
            attribute,
            value as *const T as *const _,
            std::mem::size_of::<T>() as u32,
        )
    };
}

impl Window {
    pub fn create(handler: Handler) -> Result<Self> {
        let _ = HANDLER.set(handler);
        // SAFETY: 自分の実行ファイルのハンドルを得るだけ
        let instance = unsafe { GetModuleHandleW(None)? };
        let class = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            lpfnWndProc: Some(procedure),
            hInstance: instance.into(),
            lpszClassName: CLASS,
            // SAFETY: OS の標準のカーソルを読むだけ
            hCursor: unsafe { LoadCursorW(None, IDC_ARROW) }.unwrap_or_default(),
            ..Default::default()
        };
        // SAFETY: class はこの呼び出しのあいだ生きている
        unsafe { RegisterClassExW(&class) };
        // SAFETY: 登録した窓のクラスで，親を持たない窓を作る．押しても前に出ない(WS_EX_NOACTIVATE)
        let hwnd = unsafe {
            CreateWindowExW(
                WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
                CLASS,
                PCWSTR::null(),
                WS_POPUP,
                0,
                0,
                1,
                1,
                None,
                None,
                Some(instance.into()),
                None,
            )?
        };
        // 窓の全体を DWM の合成に任せ，描かなかったところ(角丸の外・影の外)を透けさせる(候補の窓と同じ)
        let margins = MARGINS {
            cxLeftWidth: -1,
            cxRightWidth: -1,
            cyTopHeight: -1,
            cyBottomHeight: -1,
        };
        // SAFETY: hwnd は作ったばかりの窓
        let _ = unsafe { DwmExtendFrameIntoClientArea(hwnd, &margins) };
        // 角の丸みと縁は中身の側(scene)が描く
        set_attribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &DWMWCP_DONOTROUND);
        set_attribute(hwnd, DWMWA_BORDER_COLOR, &COLORREF(DWMWA_COLOR_NONE));
        Ok(Self { hwnd, target: None })
    }

    /// 1 DIP のデバイスピクセル数
    pub fn scale(&self) -> f32 {
        scale_of(self.hwnd)
    }

    /// caret(ピクセル)のある画面の作業領域
    pub fn work_area(caret: Bounds) -> Bounds {
        let rect = RECT {
            left: caret.left,
            top: caret.top,
            right: caret.right,
            bottom: caret.bottom,
        };
        // SAFETY: rect と info はこの呼び出しのあいだ生きている
        let monitor = unsafe { MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST) };
        let mut info = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        // SAFETY: 同上
        if unsafe { GetMonitorInfoW(monitor, &mut info) }.as_bool() {
            Bounds {
                left: info.rcWork.left,
                top: info.rcWork.top,
                right: info.rcWork.right,
                bottom: info.rcWork.bottom,
            }
        } else {
            Bounds {
                left: i32::MIN / 2,
                top: i32::MIN / 2,
                right: i32::MAX / 2,
                bottom: i32::MAX / 2,
            }
        }
    }

    /// マウスの位置(入力位置が分からないときに窓を置く目安)
    pub fn cursor() -> Bounds {
        let mut point = POINT::default();
        // SAFETY: point は書き込める場所を指す
        let _ = unsafe { GetCursorPos(&mut point) };
        Bounds {
            left: point.x,
            top: point.y,
            right: point.x + 1,
            bottom: point.y + 1,
        }
    }

    /// 今のポインタの位置(窓の中の DIP)
    pub fn pointer(&self) -> (f32, f32) {
        let mut point = POINT::default();
        // SAFETY: point は書き込める場所を指し，hwnd はこの窓
        unsafe {
            let _ = GetCursorPos(&mut point);
            let _ = ScreenToClient(self.hwnd, &mut point);
        }
        let scale = self.scale();
        (point.x as f32 / scale, point.y as f32 / scale)
    }

    /// 窓を (x, y)(画面のピクセル)に width × height で出す．前面のアプリは変えない
    pub fn show_at(&self, x: i32, y: i32, width: i32, height: i32) {
        // SAFETY: 自分の窓を動かして出す
        let _ = unsafe {
            SetWindowPos(
                self.hwnd,
                Some(HWND_TOPMOST),
                x,
                y,
                width.max(1),
                height.max(1),
                SWP_NOACTIVATE | SWP_SHOWWINDOW,
            )
        };
    }

    pub fn hide(&self) {
        // SAFETY: 自分の窓を隠すだけ
        let _ = unsafe { ShowWindow(self.hwnd, SW_HIDE) };
    }

    fn target(
        &mut self,
        renderer: &Renderer,
        width: u32,
        height: u32,
    ) -> Result<ID2D1HwndRenderTarget> {
        let size = D2D_SIZE_U { width, height };
        if let Some(target) = &self.target {
            // SAFETY: target はこの窓の描き先
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
        // SAFETY: properties は呼び出しのあいだ有効．hwnd はこの窓で，描き先より長く生きる
        let target = unsafe {
            renderer.factory().CreateHwndRenderTarget(
                &properties,
                &D2D1_HWND_RENDER_TARGET_PROPERTIES {
                    hwnd: self.hwnd,
                    pixelSize: size,
                    presentOptions: D2D1_PRESENT_OPTIONS_NONE,
                },
            )?
        };
        self.target = Some(target.clone());
        Ok(target)
    }

    /// scene をこの窓に描く
    pub fn draw(
        &mut self,
        renderer: &Renderer,
        scene: &Scene,
        measure: &TextMeasure,
    ) -> Result<()> {
        let scale = self.scale();
        let width = ((scene.width * scale).ceil() as u32).max(1);
        let height = ((scene.height * scale).ceil() as u32).max(1);
        let target = self.target(renderer, width, height)?;
        // SAFETY: target はこの窓の描き先．BeginDraw と EndDraw を対にする
        unsafe {
            target.SetDpi(BASE_DPI * scale, BASE_DPI * scale);
            target.BeginDraw();
        }
        let painted = renderer.paint(&target, scene, measure, scale, 1.0);
        // SAFETY: BeginDraw と対にする
        let ended = unsafe { target.EndDraw(None, None) };
        if ended.is_err() {
            // 描き先が使えなくなった(画面の設定が変わったなど)．次に作り直す
            self.target = None;
        }
        painted.and(ended)
    }

    /// ナレーターに text を読み上げてもらう．前の読み上げを打ち切り，今の選択を読む
    pub fn announce(&self, text: &str) {
        // SAFETY: hwnd はこの窓．OS が窓に対応する UI オートメーションの要素を返す
        let Ok(provider) = (unsafe { UiaHostProviderFromHwnd(self.hwnd) }) else {
            return;
        };
        // SAFETY: provider と文字列は呼び出しのあいだ有効
        let _ = unsafe {
            UiaRaiseNotificationEvent(
                &provider,
                NotificationKind_ActionCompleted,
                NotificationProcessing_ImportantMostRecent,
                &BSTR::from(text),
                &BSTR::from(ANNOUNCEMENT_ID),
            )
        };
    }
}

fn scale_of(hwnd: HWND) -> f32 {
    // SAFETY: 窓の DPI を尋ねるだけ
    let dpi = unsafe { GetDpiForWindow(hwnd) };
    if dpi == 0 {
        1.0
    } else {
        dpi as f32 / BASE_DPI
    }
}

/// lparam に入っている窓の中の座標(下位が x，上位が y．符号付き)を DIP にする
fn dip(hwnd: HWND, lparam: LPARAM) -> (f32, f32) {
    let x = (lparam.0 & 0xFFFF) as u16 as i16 as f32;
    let y = ((lparam.0 >> 16) & 0xFFFF) as u16 as i16 as f32;
    let scale = scale_of(hwnd);
    (x / scale, y / scale)
}

/// ホイールを回した目盛りの数(wparam の上位の符号付きの値を 1 目盛りの量で割る)
fn notches(wparam: WPARAM) -> f32 {
    let delta = ((wparam.0 >> 16) & 0xFFFF) as u16 as i16;
    f32::from(delta) / WHEEL_DELTA as f32
}

/// ポインタが窓の外に出たら WM_MOUSELEAVE を受け取る
fn track_leave(hwnd: HWND) {
    let mut track = TRACKMOUSEEVENT {
        cbSize: std::mem::size_of::<TRACKMOUSEEVENT>() as u32,
        dwFlags: TME_LEAVE,
        hwndTrack: hwnd,
        dwHoverTime: 0,
    };
    // SAFETY: track は cbSize を入れた TRACKMOUSEEVENT で，呼び出しのあいだ有効
    let _ = unsafe { TrackMouseEvent(&mut track) };
}

fn handle(event: Event) {
    if let Some(handler) = HANDLER.get() {
        handler(event);
    }
}

unsafe extern "system" fn procedure(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let handled = std::panic::catch_unwind(|| match message {
        // 押しても前に出ない．入力先のアプリはフォーカスを持ったまま
        WM_MOUSEACTIVATE => Some(LRESULT(MA_NOACTIVATE as isize)),
        WM_LBUTTONDOWN => {
            let (x, y) = dip(hwnd, lparam);
            handle(Event::Press(x, y));
            Some(LRESULT(0))
        }
        WM_MOUSEMOVE => {
            track_leave(hwnd);
            let (x, y) = dip(hwnd, lparam);
            handle(Event::Move(x, y));
            Some(LRESULT(0))
        }
        WM_MOUSELEAVE => {
            handle(Event::Leave);
            Some(LRESULT(0))
        }
        WM_MOUSEWHEEL => {
            handle(Event::Wheel(notches(wparam)));
            Some(LRESULT(0))
        }
        WM_PAINT => {
            let mut paint = PAINTSTRUCT::default();
            // SAFETY: BeginPaint と EndPaint を対にする
            unsafe { BeginPaint(hwnd, &mut paint) };
            handle(Event::Paint);
            // SAFETY: 同上
            let _ = unsafe { EndPaint(hwnd, &paint) };
            Some(LRESULT(0))
        }
        _ => None,
    });
    match handled {
        Ok(Some(result)) => result,
        // SAFETY: 扱わない知らせは既定の手続きに渡す
        _ => unsafe { DefWindowProcW(hwnd, message, wparam, lparam) },
    }
}
