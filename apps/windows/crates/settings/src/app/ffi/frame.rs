//! 窓の枠．Windows 11 の設定アプリと同じく，タイトルバーを窓の中に入れて本文と同じ地(Mica)に描く．
//! 最小化・最大化・閉じるのボタンは DWM が描き，押す・ポインターを載せるも DWM に任せる(DwmDefWindowProc)．
//! OS の「タイトルバーにアクセントカラーを表示する」がオンでも，タイトルバーだけ色が変わらない．
//! タイトルバーの高さ(ピクセル)は窓の属性に持つ．窓の手続きは App を借りている最中にも呼ばれる(SetWindowPos から
//! WM_NCCALCSIZE が来る)ので，App の外に置く．0 なら OS の枠のまま(Mica を使えない・高コントラスト)

use windows::Win32::Foundation::{HANDLE, HWND, LPARAM, LRESULT, POINT, RECT, WPARAM};
use windows::Win32::Graphics::Dwm::{
    DwmDefWindowProc, DwmGetWindowAttribute, DWMWA_CAPTION_BUTTON_BOUNDS,
};
use windows::Win32::Graphics::Gdi::ScreenToClient;
use windows::Win32::UI::HiDpi::{GetDpiForWindow, GetSystemMetricsForDpi};
use windows::Win32::UI::WindowsAndMessaging::{
    DefWindowProcW, GetPropW, IsZoomed, RemovePropW, SetPropW, SetWindowPos, HTCAPTION, HTCLIENT,
    HTTOP, HTTOPLEFT, HTTOPRIGHT, NCCALCSIZE_PARAMS, SM_CXPADDEDBORDER, SM_CYFRAME,
    SWP_FRAMECHANGED, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOSIZE, SWP_NOZORDER, WM_NCCALCSIZE,
    WM_NCHITTEST,
};
use windows_core::w;

/// タイトルバーの高さを持つ窓の属性の名前
const TITLE_BAR: windows_core::PCWSTR = w!("Hajime.TitleBar");

/// タイトルバーの高さ(ピクセル)．0 なら OS の枠のまま
pub fn title_bar(window: HWND) -> i32 {
    // SAFETY: このスレッドの窓の属性を読むだけ
    let value = unsafe { GetPropW(window, TITLE_BAR) };
    i32::try_from(value.0 as isize).unwrap_or(0)
}

/// タイトルバーを窓の中に入れる(height はピクセル．0 なら OS の枠に戻す)．閉じるボタンより低くはしない
pub fn set_title_bar(window: HWND, height: i32) {
    let height = if height > 0 {
        height.max(caption_button_bottom(window))
    } else {
        0
    };
    if height == title_bar(window) {
        return;
    }
    // SAFETY: このスレッドの窓の属性．値はポインタとして使わない
    unsafe {
        if height > 0 {
            let _ = SetPropW(window, TITLE_BAR, Some(HANDLE(height as isize as *mut _)));
        } else {
            let _ = RemovePropW(window, TITLE_BAR);
        }
    }
    // 枠の大きさを測り直させる(WM_NCCALCSIZE)
    // SAFETY: このスレッドの窓
    let _ = unsafe {
        SetWindowPos(
            window,
            None,
            0,
            0,
            0,
            0,
            SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE,
        )
    };
}

/// 窓を消す前に属性を外す
pub fn remove_title_bar(window: HWND) {
    // SAFETY: このスレッドの窓の属性
    let _ = unsafe { RemovePropW(window, TITLE_BAR) };
}

/// DWM の閉じるボタンなどの下端(窓の上端からのピクセル．窓の中の上端から測る)
fn caption_button_bottom(window: HWND) -> i32 {
    let mut bounds = RECT::default();
    // SAFETY: bounds はこの関数の中の値で，大きさを正しく渡す
    let read = unsafe {
        DwmGetWindowAttribute(
            window,
            DWMWA_CAPTION_BUTTON_BOUNDS,
            (&raw mut bounds).cast(),
            std::mem::size_of::<RECT>() as u32,
        )
    };
    if read.is_ok() {
        bounds.bottom
    } else {
        0
    }
}

/// 最大化したときに画面の外へはみ出す枠の太さ(ピクセル)
fn resize_border(window: HWND) -> i32 {
    // SAFETY: このスレッドの窓の DPI と，定数の番号の値を読むだけ
    unsafe {
        let dpi = GetDpiForWindow(window);
        GetSystemMetricsForDpi(SM_CYFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi)
    }
}

fn maximized(window: HWND) -> bool {
    // SAFETY: このスレッドの窓
    unsafe { IsZoomed(window) }.as_bool()
}

/// タイトルバーを窓の中に入れているときの枠のメッセージ．処理しないものは None
pub fn message(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
    let height = title_bar(window);
    if height == 0 {
        return None;
    }
    // 閉じるボタンなどは DWM が処理する
    let mut result = LRESULT(0);
    // SAFETY: 窓の手続きが受けたものをそのまま渡す．result はこの関数の中の値
    if unsafe { DwmDefWindowProc(window, message, wparam, lparam, &mut result) }.as_bool() {
        return Some(result);
    }
    match message {
        WM_NCCALCSIZE if wparam.0 != 0 => {
            // 左・右・下の枠は OS のまま残し，上の枠(タイトルバー)だけを窓の中に入れる
            // SAFETY: wparam が真のとき lparam は NCCALCSIZE_PARAMS を指す(Win32 の約束)
            let params = unsafe { &mut *(lparam.0 as *mut NCCALCSIZE_PARAMS) };
            let top = params.rgrc[0].top;
            // SAFETY: 窓の手続きが受けたものをそのまま渡す
            unsafe { DefWindowProcW(window, message, wparam, lparam) };
            // SAFETY: 上と同じ
            let params = unsafe { &mut *(lparam.0 as *mut NCCALCSIZE_PARAMS) };
            // 最大化した窓は枠の分だけ画面の外へはみ出すので，その分を下げる
            params.rgrc[0].top = top
                + if maximized(window) {
                    resize_border(window)
                } else {
                    0
                };
            Some(LRESULT(0))
        }
        WM_NCHITTEST => {
            // SAFETY: 窓の手続きが受けたものをそのまま渡す
            let hit = unsafe { DefWindowProcW(window, message, wparam, lparam) };
            if hit.0 != HTCLIENT as isize {
                return Some(hit);
            }
            let mut point = POINT {
                x: (lparam.0 & 0xffff) as i16 as i32,
                y: ((lparam.0 >> 16) & 0xffff) as i16 as i32,
            };
            // SAFETY: point はこの関数の中の値
            let _ = unsafe { ScreenToClient(window, &mut point) };
            let border = resize_border(window);
            let hit = if !maximized(window) && point.y < border {
                // 上の枠は窓の中に入れたので，大きさを変えるところを自分で決める
                if point.x < border {
                    HTTOPLEFT
                } else if point.x >= client_width(window) - border {
                    HTTOPRIGHT
                } else {
                    HTTOP
                }
            } else if point.y < height {
                HTCAPTION
            } else {
                HTCLIENT
            };
            Some(LRESULT(hit as isize))
        }
        _ => None,
    }
}

fn client_width(window: HWND) -> i32 {
    super::client_size(window).0
}
