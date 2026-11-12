use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, POINT, RECT, WPARAM};
use windows::Win32::Graphics::Dwm::{
    DwmSetWindowAttribute, DWMWA_USE_IMMERSIVE_DARK_MODE, DWMWA_WINDOW_CORNER_PREFERENCE,
    DWMWCP_ROUND, DWMWINDOWATTRIBUTE,
};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, EndPaint, GetMonitorInfoW, MonitorFromRect, ScreenToClient, MONITORINFO,
    MONITOR_DEFAULTTONEAREST, PAINTSTRUCT,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::Controls::WM_MOUSELEAVE;
use windows::Win32::UI::HiDpi::GetDpiForWindow;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    ReleaseCapture, SetCapture, TrackMouseEvent, TME_LEAVE, TRACKMOUSEEVENT,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, GetCursorPos, KillTimer, LoadCursorW, PostMessageW,
    RegisterClassExW, SetTimer, SetWindowPos, ShowWindow, HTBOTTOM, HTBOTTOMLEFT, HTBOTTOMRIGHT,
    HTCAPTION, HTCLIENT, HTLEFT, HTRIGHT, HTTOP, HTTOPLEFT, HTTOPRIGHT, HWND_TOPMOST, IDC_ARROW,
    MA_NOACTIVATE, MINMAXINFO, SWP_NOACTIVATE, SWP_NOZORDER, SWP_SHOWWINDOW, SW_HIDE, WHEEL_DELTA,
    WM_APP, WM_CAPTURECHANGED, WM_DPICHANGED, WM_GETMINMAXINFO, WM_LBUTTONDOWN, WM_LBUTTONUP,
    WM_MOUSEACTIVATE, WM_MOUSEHWHEEL, WM_MOUSEMOVE, WM_MOUSEWHEEL, WM_NCCALCSIZE, WM_NCHITTEST,
    WM_PAINT, WM_SIZE, WM_TIMER, WNDCLASSEXW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST,
    WS_POPUP, WS_THICKFRAME,
};
use windows_core::{w, Result, BOOL};

use crate::geometry::Bounds;
use crate::handwriting::layout::{Edge, Hit};

const CLASS: windows_core::PCWSTR = w!("hajime.handwriting");
const WM_RECOGNIZED: u32 = WM_APP + 2;
const RECOGNIZE_TIMER: usize = 1;
const BASE_DPI: f32 = 96.0;

/// 窓に届いたことのうち，手書きの窓が扱うもの．座標は窓の中の DIP
pub enum Event {
    Press(f32, f32),
    Move(f32, f32),
    Release(f32, f32),
    /// ポインタが窓の外に出た
    Leave,
    /// 押したまま窓の外で離したなど，押していた状態が切れた
    CaptureLost,
    /// ホイールを回した(上に回すと正．縦のホイールでも横のホイールでも候補の行を横に送る)
    Wheel {
        delta: f32,
    },
    /// 窓の大きさが変わった(DPI が変わったときも)
    Resized,
    RecognizeNow,
    Recognized,
    Paint,
}

/// 窓の手続きから呼ぶ口．窓のどこを押したかを尋ねる口と，起きたことを知らせる口
pub struct Handlers {
    pub hit: fn(f32, f32) -> Hit,
    pub event: fn(&Event),
}

static HANDLERS: std::sync::OnceLock<Handlers> = std::sync::OnceLock::new();

/// フォーカスを奪わない手書きの窓．書いても押しても動かしても大きさを変えても，入力先のアプリからフォーカスを移さない．
/// 枠(WS_THICKFRAME)は持つが中身で覆い，Windows 11 の縁・影・角丸は DWM に描かせる
pub struct Window {
    hwnd: HWND,
}

/// 認識のスレッドから窓に知らせる口
#[derive(Clone, Copy)]
pub struct Notifier {
    hwnd: isize,
}

impl Notifier {
    pub fn recognized(&self) {
        // SAFETY: 窓の識別子を送るだけ．窓が無くなっていれば何も起きない
        let _ = unsafe {
            PostMessageW(
                Some(HWND(self.hwnd as *mut _)),
                WM_RECOGNIZED,
                WPARAM(0),
                LPARAM(0),
            )
        };
    }
}

impl Window {
    pub fn create(handlers: Handlers) -> Result<Self> {
        let _ = HANDLERS.set(handlers);
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
        // SAFETY: 登録した窓のクラスで，親を持たない窓を作る
        let hwnd = unsafe {
            CreateWindowExW(
                WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
                CLASS,
                &windows_core::HSTRING::from(crate::handwriting::strings::TITLE),
                WS_POPUP | WS_THICKFRAME,
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
        let window = Self { hwnd };
        // Windows 11 の角丸(ポップアップの窓は既定で角を丸めない)
        window.set_attribute(DWMWA_WINDOW_CORNER_PREFERENCE, &DWMWCP_ROUND);
        Ok(window)
    }

    pub fn hwnd(&self) -> HWND {
        self.hwnd
    }

    pub fn notifier(&self) -> Notifier {
        Notifier {
            hwnd: self.hwnd.0 as isize,
        }
    }

    /// DWM の縁と影をダークかライトに合わせる
    pub fn set_dark(&self, dark: bool) {
        self.set_attribute(DWMWA_USE_IMMERSIVE_DARK_MODE, &BOOL::from(dark));
    }

    fn set_attribute<T>(&self, attribute: DWMWINDOWATTRIBUTE, value: &T) {
        // SAFETY: value は size_of::<T>() バイトの読める値
        let _ = unsafe {
            DwmSetWindowAttribute(
                self.hwnd,
                attribute,
                value as *const T as *const _,
                std::mem::size_of::<T>() as u32,
            )
        };
    }

    pub fn scale(&self) -> f32 {
        scale(self.hwnd)
    }

    /// 窓の中の大きさ(DIP)
    pub fn size(&self) -> (f32, f32) {
        let mut rect = RECT::default();
        // SAFETY: rect は書き込める場所を指す
        let _ =
            unsafe { windows::Win32::UI::WindowsAndMessaging::GetClientRect(self.hwnd, &mut rect) };
        let scale = self.scale();
        (
            (rect.right - rect.left) as f32 / scale,
            (rect.bottom - rect.top) as f32 / scale,
        )
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

    /// 置く前に，置く先の画面の DPI に合わせるため，いったん見せずにそこへ動かす
    pub fn move_to(&self, x: i32, y: i32) {
        // SAFETY: 自分の窓を動かすだけ．見せない・前面のアプリは変えない
        let _ = unsafe { SetWindowPos(self.hwnd, None, x, y, 1, 1, SWP_NOACTIVATE | SWP_NOZORDER) };
    }

    pub fn show_at(&self, x: i32, y: i32, width: i32, height: i32) {
        // SAFETY: 自分の窓を動かして出す．前面のアプリは変えない
        let _ = unsafe {
            SetWindowPos(
                self.hwnd,
                Some(HWND_TOPMOST),
                x,
                y,
                width,
                height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW,
            )
        };
    }

    pub fn hide(&self) {
        self.stop_timer();
        // SAFETY: 自分の窓を隠すだけ
        let _ = unsafe { ShowWindow(self.hwnd, SW_HIDE) };
    }

    pub fn start_timer(&self, milliseconds: u32) {
        // SAFETY: 自分の窓のタイマー
        unsafe {
            SetTimer(Some(self.hwnd), RECOGNIZE_TIMER, milliseconds.max(1), None);
        }
    }

    pub fn stop_timer(&self) {
        // SAFETY: 自分の窓のタイマー
        let _ = unsafe { KillTimer(Some(self.hwnd), RECOGNIZE_TIMER) };
    }

    pub fn capture(&self) {
        // SAFETY: 自分の窓でマウスを受け続ける
        unsafe { SetCapture(self.hwnd) };
    }

    pub fn release(&self) {
        // SAFETY: SetCapture と対にする
        let _ = unsafe { ReleaseCapture() };
    }
}

fn scale(hwnd: HWND) -> f32 {
    // SAFETY: 自分の窓の DPI を尋ねるだけ
    let dpi = unsafe { GetDpiForWindow(hwnd) };
    if dpi == 0 {
        1.0
    } else {
        dpi as f32 / BASE_DPI
    }
}

/// lparam に入っている座標(下位が x，上位が y．符号付き)
fn coordinates(lparam: LPARAM) -> (i32, i32) {
    let x = (lparam.0 & 0xFFFF) as u16 as i16 as i32;
    let y = ((lparam.0 >> 16) & 0xFFFF) as u16 as i16 as i32;
    (x, y)
}

/// 窓の中のピクセルを DIP にする
fn dip(hwnd: HWND, x: i32, y: i32) -> (f32, f32) {
    let scale = scale(hwnd);
    (x as f32 / scale, y as f32 / scale)
}

/// 画面の座標(lparam)を窓の中の DIP にする
fn screen_dip(hwnd: HWND, lparam: LPARAM) -> (f32, f32) {
    let (x, y) = coordinates(lparam);
    let mut point = POINT { x, y };
    // SAFETY: point は書き込める場所を指す
    let _ = unsafe { ScreenToClient(hwnd, &mut point) };
    dip(hwnd, point.x, point.y)
}

fn send(event: &Event) {
    if let Some(handlers) = HANDLERS.get() {
        (handlers.event)(event);
    }
}

fn hit(x: f32, y: f32) -> Hit {
    HANDLERS
        .get()
        .map_or(Hit::Nothing, |handlers| (handlers.hit)(x, y))
}

/// 窓の外に出たことを 1 度知らせてもらう
fn track_leave(hwnd: HWND) {
    let mut track = TRACKMOUSEEVENT {
        cbSize: std::mem::size_of::<TRACKMOUSEEVENT>() as u32,
        dwFlags: TME_LEAVE,
        hwndTrack: hwnd,
        dwHoverTime: 0,
    };
    // SAFETY: track はこの呼び出しのあいだ生きている
    let _ = unsafe { TrackMouseEvent(&mut track) };
}

fn edge_code(edge: Edge) -> u32 {
    match edge {
        Edge::Left => HTLEFT,
        Edge::Right => HTRIGHT,
        Edge::Top => HTTOP,
        Edge::Bottom => HTBOTTOM,
        Edge::TopLeft => HTTOPLEFT,
        Edge::TopRight => HTTOPRIGHT,
        Edge::BottomLeft => HTBOTTOMLEFT,
        Edge::BottomRight => HTBOTTOMRIGHT,
    }
}

unsafe extern "system" fn procedure(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let handled = std::panic::catch_unwind(|| match message {
        // 押しても前に出ない(入力先のアプリからフォーカスを移さない)
        WM_MOUSEACTIVATE => Some(LRESULT(MA_NOACTIVATE as isize)),
        // 枠の分を取らず，窓の全体を中身にする(縁と影は DWM が描く)
        WM_NCCALCSIZE if wparam.0 != 0 => Some(LRESULT(0)),
        WM_NCHITTEST => {
            let (x, y) = screen_dip(hwnd, lparam);
            let code = match hit(x, y) {
                Hit::Edge(edge) => edge_code(edge),
                Hit::Title => HTCAPTION,
                _ => HTCLIENT,
            };
            Some(LRESULT(code as isize))
        }
        WM_GETMINMAXINFO => {
            let (width, height) = crate::handwriting::layout::minimum_size();
            let scale = scale(hwnd);
            // SAFETY: WM_GETMINMAXINFO の lparam は書き込める MINMAXINFO を指す
            if let Some(info) = unsafe { (lparam.0 as *mut MINMAXINFO).as_mut() } {
                info.ptMinTrackSize.x = (width * scale).round() as i32;
                info.ptMinTrackSize.y = (height * scale).round() as i32;
            }
            Some(LRESULT(0))
        }
        WM_DPICHANGED => {
            // 画面をまたいだら，OS が勧める大きさと位置にする(DIP の大きさを保つ)
            // SAFETY: WM_DPICHANGED の lparam は勧める位置の RECT を指す
            if let Some(rect) = unsafe { (lparam.0 as *const RECT).as_ref() } {
                // SAFETY: 自分の窓を動かすだけ
                let _ = unsafe {
                    SetWindowPos(
                        hwnd,
                        None,
                        rect.left,
                        rect.top,
                        rect.right - rect.left,
                        rect.bottom - rect.top,
                        SWP_NOACTIVATE | SWP_NOZORDER,
                    )
                };
            }
            send(&Event::Resized);
            Some(LRESULT(0))
        }
        WM_SIZE => {
            send(&Event::Resized);
            Some(LRESULT(0))
        }
        WM_LBUTTONDOWN => {
            let (x, y) = coordinates(lparam);
            let (x, y) = dip(hwnd, x, y);
            send(&Event::Press(x, y));
            Some(LRESULT(0))
        }
        WM_MOUSEMOVE => {
            track_leave(hwnd);
            let (x, y) = coordinates(lparam);
            let (x, y) = dip(hwnd, x, y);
            send(&Event::Move(x, y));
            Some(LRESULT(0))
        }
        WM_MOUSELEAVE => {
            send(&Event::Leave);
            Some(LRESULT(0))
        }
        WM_LBUTTONUP => {
            let (x, y) = coordinates(lparam);
            let (x, y) = dip(hwnd, x, y);
            send(&Event::Release(x, y));
            Some(LRESULT(0))
        }
        WM_CAPTURECHANGED => {
            send(&Event::CaptureLost);
            Some(LRESULT(0))
        }
        WM_MOUSEWHEEL | WM_MOUSEHWHEEL => {
            let raw = ((wparam.0 >> 16) & 0xFFFF) as u16 as i16;
            let delta = f32::from(raw) / WHEEL_DELTA as f32;
            // 横のホイールは右に回すと正なので，上に回したのと同じ向き(行を左へ戻す)にそろえる
            let delta = if message == WM_MOUSEHWHEEL {
                -delta
            } else {
                delta
            };
            send(&Event::Wheel { delta });
            Some(LRESULT(0))
        }
        WM_TIMER if wparam.0 == RECOGNIZE_TIMER => {
            // SAFETY: 自分の窓のタイマー
            let _ = unsafe { KillTimer(Some(hwnd), RECOGNIZE_TIMER) };
            send(&Event::RecognizeNow);
            Some(LRESULT(0))
        }
        WM_RECOGNIZED => {
            send(&Event::Recognized);
            Some(LRESULT(0))
        }
        WM_PAINT => {
            let mut paint = PAINTSTRUCT::default();
            // SAFETY: BeginPaint と EndPaint を対にする
            unsafe { BeginPaint(hwnd, &mut paint) };
            send(&Event::Paint);
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
