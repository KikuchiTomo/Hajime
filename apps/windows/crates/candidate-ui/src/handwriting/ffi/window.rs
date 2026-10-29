use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, POINT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, EndPaint, GetMonitorInfoW, MonitorFromRect, ScreenToClient, MONITORINFO,
    MONITOR_DEFAULTTONEAREST, PAINTSTRUCT,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::HiDpi::GetDpiForWindow;
use windows::Win32::UI::Input::KeyboardAndMouse::{ReleaseCapture, SetCapture};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, GetCursorPos, KillTimer, PostMessageW, RegisterClassExW,
    SetTimer, SetWindowPos, ShowWindow, HTCAPTION, HTCLIENT, HWND_TOPMOST, MA_NOACTIVATE,
    SWP_NOACTIVATE, SWP_SHOWWINDOW, SW_HIDE, WM_APP, WM_CAPTURECHANGED, WM_LBUTTONDOWN,
    WM_LBUTTONUP, WM_MOUSEACTIVATE, WM_MOUSEMOVE, WM_NCHITTEST, WM_PAINT, WM_TIMER, WNDCLASSEXW,
    WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_POPUP,
};
use windows_core::{w, Result};

use crate::handwriting::layout::Bounds;

const CLASS: windows_core::PCWSTR = w!("hajime.handwriting");
const WM_RECOGNIZED: u32 = WM_APP + 2;
const RECOGNIZE_TIMER: usize = 1;
const BASE_DPI: f32 = 96.0;

/// 窓に届いたことのうち，手書きの窓が扱うもの．座標は窓の中の DIP
pub enum Event {
    Press(f32, f32),
    Move(f32, f32),
    Release,
    /// 押したまま窓の外で離したなど，押していた状態が切れた
    CaptureLost,
    /// 見出しの帯かどうかを尋ねる(窓を動かせるようにする)
    IsHeader(f32, f32),
    RecognizeNow,
    Recognized,
    Paint,
}

/// 窓の手続きから呼ぶ口．見出しの帯かを尋ねられたときだけ答えを返す
pub type Handler = fn(&Event) -> bool;

static HANDLER: std::sync::OnceLock<Handler> = std::sync::OnceLock::new();

/// フォーカスを奪わない手書きの窓．書いても押しても，入力先のアプリからフォーカスを移さない
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
            hCursor: unsafe {
                windows::Win32::UI::WindowsAndMessaging::LoadCursorW(
                    None,
                    windows::Win32::UI::WindowsAndMessaging::IDC_ARROW,
                )
            }
            .unwrap_or_default(),
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
        Ok(Self { hwnd })
    }

    pub fn hwnd(&self) -> HWND {
        self.hwnd
    }

    pub fn notifier(&self) -> Notifier {
        Notifier {
            hwnd: self.hwnd.0 as isize,
        }
    }

    pub fn scale(&self) -> f32 {
        // SAFETY: 自分の窓の DPI を尋ねるだけ
        let dpi = unsafe { GetDpiForWindow(self.hwnd) };
        if dpi == 0 {
            1.0
        } else {
            dpi as f32 / BASE_DPI
        }
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

/// lparam に入っている座標(下位が x，上位が y．符号付き)
fn coordinates(lparam: LPARAM) -> (i32, i32) {
    let x = (lparam.0 & 0xFFFF) as u16 as i16 as i32;
    let y = ((lparam.0 >> 16) & 0xFFFF) as u16 as i16 as i32;
    (x, y)
}

/// 窓の中のピクセルを DIP にする
fn dip(hwnd: HWND, x: i32, y: i32) -> (f32, f32) {
    // SAFETY: 自分の窓の DPI を尋ねるだけ
    let dpi = unsafe { GetDpiForWindow(hwnd) };
    let scale = if dpi == 0 { 1.0 } else { dpi as f32 / BASE_DPI };
    (x as f32 / scale, y as f32 / scale)
}

fn handle(event: &Event) -> bool {
    HANDLER.get().is_some_and(|handler| handler(event))
}

unsafe extern "system" fn procedure(
    hwnd: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let handled = std::panic::catch_unwind(|| match message {
        WM_MOUSEACTIVATE => Some(LRESULT(MA_NOACTIVATE as isize)),
        WM_NCHITTEST => {
            // SAFETY: 既定の手続きに渡すだけ
            let hit = unsafe { DefWindowProcW(hwnd, message, wparam, lparam) };
            if hit.0 != HTCLIENT as isize {
                return Some(hit);
            }
            let (x, y) = coordinates(lparam);
            let mut point = POINT { x, y };
            // SAFETY: point は書き込める場所を指す
            let _ = unsafe { ScreenToClient(hwnd, &mut point) };
            let (x, y) = dip(hwnd, point.x, point.y);
            if handle(&Event::IsHeader(x, y)) {
                Some(LRESULT(HTCAPTION as isize))
            } else {
                Some(hit)
            }
        }
        WM_LBUTTONDOWN => {
            let (x, y) = coordinates(lparam);
            let (x, y) = dip(hwnd, x, y);
            handle(&Event::Press(x, y));
            Some(LRESULT(0))
        }
        WM_MOUSEMOVE => {
            let (x, y) = coordinates(lparam);
            let (x, y) = dip(hwnd, x, y);
            handle(&Event::Move(x, y));
            Some(LRESULT(0))
        }
        WM_LBUTTONUP => {
            handle(&Event::Release);
            Some(LRESULT(0))
        }
        WM_CAPTURECHANGED => {
            handle(&Event::CaptureLost);
            Some(LRESULT(0))
        }
        WM_TIMER if wparam.0 == RECOGNIZE_TIMER => {
            // SAFETY: 自分の窓のタイマー
            let _ = unsafe { KillTimer(Some(hwnd), RECOGNIZE_TIMER) };
            handle(&Event::RecognizeNow);
            Some(LRESULT(0))
        }
        WM_RECOGNIZED => {
            handle(&Event::Recognized);
            Some(LRESULT(0))
        }
        WM_PAINT => {
            let mut paint = PAINTSTRUCT::default();
            // SAFETY: BeginPaint と EndPaint を対にする
            unsafe { BeginPaint(hwnd, &mut paint) };
            handle(&Event::Paint);
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
