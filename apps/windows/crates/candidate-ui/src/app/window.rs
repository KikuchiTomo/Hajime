use ipc::Rect;
use std::sync::OnceLock;
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, EndPaint, GetMonitorInfoW, MonitorFromRect, MONITORINFO, MONITOR_DEFAULTTONEAREST,
    PAINTSTRUCT,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::HiDpi::{
    GetDpiForWindow, SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DispatchMessageW, GetMessageW, KillTimer, PostMessageW,
    RegisterClassExW, SetTimer, SetWindowPos, ShowWindow, TranslateMessage, HWND_TOPMOST,
    MA_NOACTIVATE, MSG, SWP_NOACTIVATE, SWP_NOSIZE, SWP_SHOWWINDOW, SW_HIDE, WM_APP,
    WM_MOUSEACTIVATE, WM_PAINT, WM_TIMER, WNDCLASSEXW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
    WS_EX_TOPMOST, WS_POPUP,
};
use windows_core::{w, Result};

const WM_INBOX: u32 = WM_APP + 1;
const MODE_TIMER: usize = 1;
const BASE_DPI: f32 = 96.0;

struct Callbacks {
    inbox: fn(),
    timer: fn(),
    paint: fn(),
}

static CALLBACKS: OnceLock<Callbacks> = OnceLock::new();

pub struct Window {
    hwnd: HWND,
}

pub struct Notifier {
    hwnd: isize,
}

impl Notifier {
    pub fn notify(&self) {
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
    let _ = unsafe { SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) };
}

pub fn run_message_loop() {
    let mut message = MSG::default();
    while unsafe { GetMessageW(&mut message, None, 0, 0) }.as_bool() {
        unsafe {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
}

impl Window {
    pub fn create(inbox: fn(), timer: fn(), paint: fn()) -> Result<Self> {
        let _ = CALLBACKS.set(Callbacks {
            inbox,
            timer,
            paint,
        });
        let instance = unsafe { GetModuleHandleW(None)? };
        let class = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            lpfnWndProc: Some(procedure),
            hInstance: instance.into(),
            lpszClassName: w!("s90.tokyo-ime.candidate"),
            ..Default::default()
        };
        unsafe { RegisterClassExW(&class) };
        let hwnd = unsafe {
            CreateWindowExW(
                WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
                w!("s90.tokyo-ime.candidate"),
                w!(""),
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
        let dpi = unsafe { GetDpiForWindow(self.hwnd) };
        if dpi == 0 {
            1.0
        } else {
            dpi as f32 / BASE_DPI
        }
    }

    pub fn start_timer(&self, milliseconds: u32) {
        unsafe {
            let _ = KillTimer(Some(self.hwnd), MODE_TIMER);
            SetTimer(Some(self.hwnd), MODE_TIMER, milliseconds.max(1), None);
        }
    }

    pub fn place(&self, anchor: &Rect, width: f32, height: f32, gap: i32) {
        let anchor_rect = RECT {
            left: anchor.x,
            top: anchor.y,
            right: anchor.x + anchor.width.max(1),
            bottom: anchor.y + anchor.height.max(1),
        };
        let _ = unsafe {
            SetWindowPos(
                self.hwnd,
                Some(HWND_TOPMOST),
                anchor_rect.left,
                anchor_rect.bottom + gap,
                0,
                0,
                SWP_NOACTIVATE | SWP_NOSIZE,
            )
        };
        let scale = self.scale();
        let pixel_width = (width * scale).ceil() as i32;
        let pixel_height = (height * scale).ceil() as i32;
        let monitor = unsafe { MonitorFromRect(&anchor_rect, MONITOR_DEFAULTTONEAREST) };
        let mut info = MONITORINFO {
            cbSize: std::mem::size_of::<MONITORINFO>() as u32,
            ..Default::default()
        };
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
        let (x, y) = position(&anchor_rect, &work, pixel_width, pixel_height, gap);
        let _ = unsafe {
            SetWindowPos(
                self.hwnd,
                Some(HWND_TOPMOST),
                x,
                y,
                pixel_width,
                pixel_height,
                SWP_NOACTIVATE | SWP_SHOWWINDOW,
            )
        };
    }

    pub fn hide(&self) {
        let _ = unsafe { ShowWindow(self.hwnd, SW_HIDE) };
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
        WM_TIMER if wparam.0 == MODE_TIMER => {
            let _ = unsafe { KillTimer(Some(hwnd), MODE_TIMER) };
            if let Some(callbacks) = CALLBACKS.get() {
                (callbacks.timer)();
            }
            Some(LRESULT(0))
        }
        WM_PAINT => {
            let mut paint = PAINTSTRUCT::default();
            unsafe { BeginPaint(hwnd, &mut paint) };
            if let Some(callbacks) = CALLBACKS.get() {
                (callbacks.paint)();
            }
            let _ = unsafe { EndPaint(hwnd, &paint) };
            Some(LRESULT(0))
        }
        WM_MOUSEACTIVATE => Some(LRESULT(MA_NOACTIVATE as isize)),
        _ => None,
    });
    match handled {
        Ok(Some(result)) => result,
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
}
