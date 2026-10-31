use super::render::{Renderer, TextMeasure};
use crate::scene::Scene;
use crate::theme::Color;
use ipc::Rect;
use std::sync::OnceLock;
use windows::Win32::Foundation::{CloseHandle, GetLastError, ERROR_ALREADY_EXISTS, HANDLE};
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_ALPHA_MODE_PREMULTIPLIED, D2D1_PIXEL_FORMAT, D2D_SIZE_U,
};
use windows::Win32::Graphics::Direct2D::{
    ID2D1HwndRenderTarget, D2D1_HWND_RENDER_TARGET_PROPERTIES, D2D1_PRESENT_OPTIONS_NONE,
    D2D1_RENDER_TARGET_PROPERTIES,
};
use windows::Win32::Graphics::Dwm::{
    DwmExtendFrameIntoClientArea, DwmSetWindowAttribute, DWMSBT_NONE, DWMSBT_TRANSIENTWINDOW,
    DWMWA_BORDER_COLOR, DWMWA_COLOR_NONE, DWMWA_SYSTEMBACKDROP_TYPE, DWMWA_USE_IMMERSIVE_DARK_MODE,
    DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_DONOTROUND, DWMWCP_ROUND, DWMWINDOWATTRIBUTE,
};
use windows::Win32::Graphics::Dxgi::Common::DXGI_FORMAT_B8G8R8A8_UNORM;
use windows::Win32::Graphics::Gdi::{
    BeginPaint, EndPaint, GetMonitorInfoW, MonitorFromRect, MONITORINFO, MONITOR_DEFAULTTONEAREST,
    PAINTSTRUCT,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Threading::CreateMutexW;
use windows::Win32::UI::Accessibility::{
    NotificationKind_ActionCompleted, NotificationProcessing_ImportantMostRecent,
    UiaHostProviderFromHwnd, UiaRaiseNotificationEvent,
};
use windows::Win32::UI::Controls::MARGINS;
use windows::Win32::UI::HiDpi::{
    GetDpiForWindow, SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DispatchMessageW, GetMessageW, KillTimer, LoadCursorW,
    PostMessageW, RegisterClassExW, SetTimer, SetWindowPos, ShowWindow, TranslateMessage,
    CS_DROPSHADOW, HWND_TOPMOST, IDC_ARROW, MA_NOACTIVATE, MSG, SWP_NOACTIVATE, SWP_SHOWWINDOW,
    SW_HIDE, WM_APP, WM_LBUTTONDOWN, WM_MOUSEACTIVATE, WM_PAINT, WM_TIMER, WNDCLASSEXW,
    WNDCLASS_STYLES, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_POPUP,
};
use windows_core::{w, Result, BOOL, BSTR, PCWSTR};

const WM_INBOX: u32 = WM_APP + 1;
const BASE_DPI: f32 = 96.0;
/// 読み上げの種類の名前．同じ名前の読み上げは新しいものが前のものを置き換える
const ANNOUNCEMENT_ID: &str = "hajime.candidate";

/// 時計の種類
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Timer {
    /// モードの札を出しておく時間
    Mode = 1,
    /// フェード(出し始めの濃さ・モードの札を消す)の 1 コマ
    Fade = 2,
    /// 窓の大きさの動きと，あとから届いた中身の重ね変わりの 1 コマ
    Motion = 3,
}

struct Callbacks {
    inbox: fn(),
    timer: fn(Timer),
    paint: fn(),
    /// 窓の中を押した(窓の中のピクセルの座標)
    click: fn(i32, i32),
}

static CALLBACKS: OnceLock<Callbacks> = OnceLock::new();

pub fn set_callbacks(inbox: fn(), timer: fn(Timer), paint: fn(), click: fn(i32, i32)) {
    let _ = CALLBACKS.set(Callbacks {
        click,
        inbox,
        timer,
        paint,
    });
}

pub struct Window {
    hwnd: HWND,
    target: Option<ID2D1HwndRenderTarget>,
}

pub struct Notifier {
    hwnd: isize,
}

impl Notifier {
    pub fn notify(&self) {
        // SAFETY: 窓が無くなっていれば PostMessageW が失敗を返すだけ
        let _ = unsafe {
            PostMessageW(
                Some(HWND(self.hwnd as *mut _)),
                WM_INBOX,
                WPARAM(0),
                LPARAM(0),
            )
        };
    }
}

pub fn make_dpi_aware() {
    // SAFETY: 引数は定数
    let _ = unsafe { SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) };
}

/// 同じログオンのセッションで候補ウィンドウを 1 つだけ動かす印(名前付きのミューテックス)．
/// エンジンは候補ウィンドウを起動し，新しくつないできた候補ウィンドウに切り替えて前の接続を閉じる．
/// エンジンが起動し直すなどで候補ウィンドウが 2 つ動くと，毎秒つなぎ直すたびに互いの接続を閉じ，出している候補が消える．
/// すでにほかの候補ウィンドウが動いていれば None(このプロセスは終わる)．返した印はプロセスが終わるまで持つ
pub fn single_instance() -> Option<HANDLE> {
    // SAFETY: 名前は定数．ハンドルはプロセスが終わるまで持つ(OS が閉じる)
    unsafe {
        let handle = CreateMutexW(None, false, w!(r"Local\hajime.candidate-ui")).ok()?;
        if GetLastError() == ERROR_ALREADY_EXISTS {
            let _ = CloseHandle(handle);
            return None;
        }
        Some(handle)
    }
}

pub fn run_message_loop() {
    let mut message = MSG::default();
    // SAFETY: message はこのスレッドの MSG
    while unsafe { GetMessageW(&mut message, None, 0, 0) }.as_bool() {
        // SAFETY: GetMessageW が書いた MSG
        unsafe {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
}

/// DWM の属性を書く．書けたら true
fn set_attribute<T>(hwnd: HWND, attribute: DWMWINDOWATTRIBUTE, value: &T) -> bool {
    // SAFETY: value は size_of::<T>() バイトの読める値
    unsafe {
        DwmSetWindowAttribute(
            hwnd,
            attribute,
            value as *const T as *const _,
            std::mem::size_of::<T>() as u32,
        )
    }
    .is_ok()
}

fn colorref(color: Color) -> COLORREF {
    let channel = |value: f32| (value.clamp(0.0, 1.0) * 255.0).round() as u32;
    COLORREF(channel(color.red) | channel(color.green) << 8 | channel(color.blue) << 16)
}

impl Window {
    /// class は窓の種類の名前．shadow なら OS が窓の影を付ける(すりガラスの地の窓)
    pub fn create(class: PCWSTR, shadow: bool) -> Result<Self> {
        // SAFETY: 自分のプロセスのモジュール
        let instance = unsafe { GetModuleHandleW(None)? };
        let description = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            style: if shadow {
                CS_DROPSHADOW
            } else {
                WNDCLASS_STYLES(0)
            },
            lpfnWndProc: Some(procedure),
            hInstance: instance.into(),
            lpszClassName: class,
            // 矢印にする．決めないと窓の上で前のカーソル(読み込み中の形など)が残る
            // SAFETY: OS の標準のカーソルを読むだけ
            hCursor: unsafe { LoadCursorW(None, IDC_ARROW) }.unwrap_or_default(),
            ..Default::default()
        };
        // SAFETY: description は有効な WNDCLASSEXW
        unsafe { RegisterClassExW(&description) };
        // SAFETY: 登録した窓の種類で作る
        let hwnd = unsafe {
            CreateWindowExW(
                WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
                class,
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
        // 窓の全体を DWM の合成に任せ，描かなかったところ(角丸の外・影の外)を透けさせる
        let margins = MARGINS {
            cxLeftWidth: -1,
            cxRightWidth: -1,
            cyTopHeight: -1,
            cyBottomHeight: -1,
        };
        // SAFETY: hwnd は作ったばかりの窓
        let _ = unsafe { DwmExtendFrameIntoClientArea(hwnd, &margins) };
        Ok(Self { hwnd, target: None })
    }

    pub fn notifier(&self) -> Notifier {
        Notifier {
            hwnd: self.hwnd.0 as isize,
        }
    }

    pub fn scale(&self) -> f32 {
        // SAFETY: hwnd はこの窓
        let dpi = unsafe { GetDpiForWindow(self.hwnd) };
        if dpi == 0 {
            1.0
        } else {
            dpi as f32 / BASE_DPI
        }
    }

    /// 地をすりガラス(Windows 11 の DWM の背景)にできるか確かめる
    pub fn supports_backdrop(&self) -> bool {
        let supported = set_attribute(
            self.hwnd,
            DWMWA_SYSTEMBACKDROP_TYPE,
            &DWMSBT_TRANSIENTWINDOW,
        );
        let _ = set_attribute(self.hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &DWMSBT_NONE);
        supported
    }

    /// 窓の地と角と縁．backdrop なら地をすりガラスにして角を OS の丸みで丸め，縁を border の色で OS に描かせる．
    /// そうでなければ OS は何も描かず，角丸の形も影も中身の側(scene)が描く
    pub fn set_chrome(&self, backdrop: bool, dark: bool, border: Color) {
        let dark = BOOL::from(dark);
        let _ = set_attribute(self.hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark);
        if backdrop {
            let _ = set_attribute(
                self.hwnd,
                DWMWA_SYSTEMBACKDROP_TYPE,
                &DWMSBT_TRANSIENTWINDOW,
            );
            let _ = set_attribute(self.hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &DWMWCP_ROUND);
            let _ = set_attribute(self.hwnd, DWMWA_BORDER_COLOR, &colorref(border));
        } else {
            let _ = set_attribute(self.hwnd, DWMWA_SYSTEMBACKDROP_TYPE, &DWMSBT_NONE);
            let _ = set_attribute(
                self.hwnd,
                DWMWA_WINDOW_CORNER_PREFERENCE,
                &DWMWCP_DONOTROUND,
            );
            let _ = set_attribute(self.hwnd, DWMWA_BORDER_COLOR, &COLORREF(DWMWA_COLOR_NONE));
        }
    }

    pub fn start_timer(&self, timer: Timer, milliseconds: u32) {
        // SAFETY: hwnd はこの窓
        unsafe {
            let _ = KillTimer(Some(self.hwnd), timer as usize);
            SetTimer(Some(self.hwnd), timer as usize, milliseconds.max(1), None);
        }
    }

    pub fn stop_timer(&self, timer: Timer) {
        // SAFETY: hwnd はこの窓
        let _ = unsafe { KillTimer(Some(self.hwnd), timer as usize) };
    }

    /// 本体(scene.body)を入力位置の下(入らなければ上)に置く．影や余白はそのまわりにはみ出す
    pub fn place(&self, anchor: &Rect, scene: &Scene, gap: i32) {
        let scale = self.scale();
        let anchor_rect = RECT {
            left: anchor.x,
            top: anchor.y,
            right: anchor.x + anchor.width.max(1),
            bottom: anchor.y + anchor.height.max(1),
        };
        // SAFETY: anchor_rect は有効な RECT
        let monitor = unsafe { MonitorFromRect(&anchor_rect, MONITOR_DEFAULTTONEAREST) };
        let mut info = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
        // SAFETY: info は cbSize を入れた MONITORINFO
        let work = if unsafe { GetMonitorInfoW(monitor, &mut info) }.as_bool() {
            info.rcWork
        } else {
            RECT {
                left: i32::MIN / 2,
                top: i32::MIN / 2,
                right: i32::MAX / 2,
                bottom: i32::MAX / 2,
            }
        };
        let pixels = |value: f32| (value * scale).round() as i32;
        let (x, y) = position(
            &anchor_rect,
            &work,
            pixels(scene.body.width),
            pixels(scene.body.height),
            gap,
        );
        // SAFETY: hwnd はこの窓
        let _ = unsafe {
            SetWindowPos(
                self.hwnd,
                Some(HWND_TOPMOST),
                x - pixels(scene.body.x),
                y - pixels(scene.body.y),
                (scene.width * scale).ceil() as i32,
                (scene.height * scale).ceil() as i32,
                SWP_NOACTIVATE | SWP_SHOWWINDOW,
            )
        };
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

    pub fn hide(&self) {
        // SAFETY: hwnd はこの窓
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
        // SAFETY: properties は呼び出しのあいだ有効
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

    /// scene をこの窓に描く．opacity は全体の濃さ
    pub fn draw(
        &mut self,
        renderer: &Renderer,
        scene: &Scene,
        measure: &TextMeasure,
        opacity: f32,
    ) -> Result<()> {
        self.draw_over(renderer, None, scene, measure, opacity)
    }

    /// 前の中身 below を描き，その上に scene を重ねて描く(あとから届いた候補の重ね変わり)．
    /// below の濃さは opacity，scene の濃さは below があれば (opacity × その濃さ)
    pub fn draw_over(
        &mut self,
        renderer: &Renderer,
        below: Option<(&Scene, f32)>,
        scene: &Scene,
        measure: &TextMeasure,
        opacity: f32,
    ) -> Result<()> {
        let scale = self.scale();
        let width = ((scene.width * scale).ceil() as u32).max(1);
        let height = ((scene.height * scale).ceil() as u32).max(1);
        let target = self.target(renderer, width, height)?;
        // SAFETY: target はこの窓の描き先
        unsafe {
            target.SetDpi(BASE_DPI * scale, BASE_DPI * scale);
            target.BeginDraw();
        }
        let painted = match below {
            Some((under, strength)) => renderer
                .paint(&target, under, measure, scale, opacity)
                .and_then(|()| {
                    renderer.paint_over(&target, scene, measure, scale, opacity * strength)
                }),
            None => renderer.paint(&target, scene, measure, scale, opacity),
        };
        // SAFETY: BeginDraw と対にする
        let ended = unsafe { target.EndDraw(None, None) };
        if ended.is_err() {
            // 描き先が使えなくなった(画面の設定が変わったなど)．次に作り直す
            self.target = None;
        }
        painted.and(ended)
    }
}

fn position(anchor: &RECT, work: &RECT, width: i32, height: i32, gap: i32) -> (i32, i32) {
    let below = anchor.bottom + gap;
    let y = if below + height > work.bottom && anchor.top - gap - height >= work.top {
        anchor.top - gap - height
    } else {
        below
    };
    let x = anchor.left.min(work.right - width).max(work.left);
    (x, y)
}

unsafe extern "system" fn procedure(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let handled = std::panic::catch_unwind(|| match message {
        WM_INBOX => {
            if let Some(callbacks) = CALLBACKS.get() {
                (callbacks.inbox)();
            }
            Some(LRESULT(0))
        }
        WM_TIMER => {
            let timer = match wparam.0 {
                id if id == Timer::Mode as usize => Some(Timer::Mode),
                id if id == Timer::Fade as usize => Some(Timer::Fade),
                _ => None,
            };
            let callbacks = CALLBACKS.get();
            match (timer, callbacks) {
                (Some(timer), Some(callbacks)) => {
                    (callbacks.timer)(timer);
                    Some(LRESULT(0))
                }
                _ => None,
            }
        }
        WM_PAINT => {
            let mut paint = PAINTSTRUCT::default();
            // SAFETY: WM_PAINT の中で BeginPaint と EndPaint を対にする
            unsafe { BeginPaint(hwnd, &mut paint) };
            if let Some(callbacks) = CALLBACKS.get() {
                (callbacks.paint)();
            }
            // SAFETY: 同上
            let _ = unsafe { EndPaint(hwnd, &paint) };
            Some(LRESULT(0))
        }
        WM_MOUSEACTIVATE => Some(LRESULT(MA_NOACTIVATE as isize)),
        // 候補を押して選ぶ．窓は前に出ない(WM_MOUSEACTIVATE で MA_NOACTIVATE)ので，入力先のアプリはフォーカスを持ったまま
        WM_LBUTTONDOWN => {
            let x = (lparam.0 & 0xFFFF) as u16 as i16 as i32;
            let y = ((lparam.0 >> 16) & 0xFFFF) as u16 as i16 as i32;
            if let Some(callbacks) = CALLBACKS.get() {
                (callbacks.click)(x, y);
            }
            Some(LRESULT(0))
        }
        _ => None,
    });
    match handled {
        Ok(Some(result)) => result,
        // SAFETY: 受け取った引数をそのまま渡す
        _ => unsafe { DefWindowProcW(hwnd, message, wparam, lparam) },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rect(left: i32, top: i32, right: i32, bottom: i32) -> RECT {
        RECT {
            left,
            top,
            right,
            bottom,
        }
    }

    #[test]
    fn 入力位置の下に出す() {
        let work = rect(0, 0, 1920, 1080);
        assert_eq!(
            position(&rect(100, 100, 102, 120), &work, 200, 150, 2),
            (100, 122)
        );
    }

    #[test]
    fn 画面の下にはみ出すなら上に出す() {
        let work = rect(0, 0, 1920, 1080);
        assert_eq!(
            position(&rect(100, 1000, 102, 1020), &work, 200, 150, 2),
            (100, 848)
        );
    }

    #[test]
    fn 画面の右にはみ出さない() {
        let work = rect(0, 0, 1920, 1080);
        assert_eq!(
            position(&rect(1900, 100, 1902, 120), &work, 200, 150, 2).0,
            1720
        );
    }

    #[test]
    fn 縁の色は_colorref_の並び() {
        let color = Color {
            red: 1.0,
            green: 0.0,
            blue: 0.5,
            alpha: 1.0,
        };
        assert_eq!(colorref(color), COLORREF(0x80_00_FF));
    }
}
