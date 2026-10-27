//! エンジンに来てもらう(wake)・遅れた返事を反映するための時計．入力先のアプリのスレッドごとに，見えないメッセージ専用の窓を 1 つ持ち，
//! その窓に時計を付ける．
//!
//! 窓の無い時計(SetTimer(None, …))の知らせは宛先の窓を持たないので，アプリのメッセージの処理によっては配られない
//! (WinUI などのアプリ)．配られないと，Space の変換の遅れた返事・打鍵が止まったときの変換・打ち間違いの見直しが画面に出ない

use super::ids::SERVICE_NAME;
use std::cell::Cell;
use windows::Win32::Foundation::{HMODULE, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::GetModuleHandleExW;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, KillTimer, RegisterClassExW, SetTimer,
    HWND_MESSAGE, WINDOW_EX_STYLE, WINDOW_STYLE, WM_TIMER, WNDCLASSEXW,
};
use windows_core::{w, PCWSTR};

const CLASS: PCWSTR = w!("s90.tokyo-ime.tsf.timer");
/// 時計の番号(窓ごとに 1 つだけ使う)
const TIMER_ID: usize = 1;
/// GetModuleHandleExW の FROM_ADDRESS | UNCHANGED_REFCOUNT
const FROM_ADDRESS: u32 = 0x4 | 0x2;

thread_local! {
    static WINDOW: Cell<Option<HWND>> = const { Cell::new(None) };
    /// 時計が鳴ったときに呼ぶもの(このスレッドの文字入力のサービス)
    static HANDLER: Cell<Option<fn()>> = const { Cell::new(None) };
}

/// milliseconds 後に handler を一度呼ぶ(前に頼んだものは取り消す)
pub fn schedule(milliseconds: u32, handler: fn()) {
    let Some(window) = window() else { return };
    HANDLER.with(|cell| cell.set(Some(handler)));
    // SAFETY: このスレッドで作った窓に付ける．同じ番号で頼み直すと前の時計を置き換える
    unsafe { SetTimer(Some(window), TIMER_ID, milliseconds.max(1), None) };
}

pub fn cancel() {
    if let Some(window) = WINDOW.with(Cell::get) {
        // SAFETY: このスレッドで作った窓
        let _ = unsafe { KillTimer(Some(window), TIMER_ID) };
    }
}

/// 窓を消す(文字入力のサービスがこのスレッドで止まるとき)
pub fn close() {
    if let Some(window) = WINDOW.with(Cell::take) {
        // SAFETY: このスレッドで作った窓．時計も一緒に消える
        let _ = unsafe { DestroyWindow(window) };
    }
    HANDLER.with(|cell| cell.set(None));
}

/// このスレッドの窓．無ければ作る
fn window() -> Option<HWND> {
    if let Some(window) = WINDOW.with(Cell::get) {
        return Some(window);
    }
    let mut module = HMODULE::default();
    let address = window as *const () as *const u16;
    // SAFETY: この DLL の中の関数の場所から，DLL のハンドルを得る(参照の数は変えない)
    unsafe { GetModuleHandleExW(FROM_ADDRESS, PCWSTR(address), &mut module).ok()? };
    let class = WNDCLASSEXW {
        cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
        lpfnWndProc: Some(procedure),
        hInstance: module.into(),
        lpszClassName: CLASS,
        ..Default::default()
    };
    // SAFETY: class はこの呼び出しのあいだ生きている．登録済みなら失敗するだけで，作るのには使える
    unsafe { RegisterClassExW(&class) };
    // SAFETY: 登録した種類で，メッセージ専用の窓(見えない・前に出ない)を作る
    let window = unsafe {
        CreateWindowExW(
            WINDOW_EX_STYLE::default(),
            CLASS,
            &windows_core::HSTRING::from(SERVICE_NAME),
            WINDOW_STYLE::default(),
            0,
            0,
            0,
            0,
            Some(HWND_MESSAGE),
            None,
            Some(module.into()),
            None,
        )
    }
    .ok()?;
    WINDOW.with(|cell| cell.set(Some(window)));
    Some(window)
}

unsafe extern "system" fn procedure(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    if message == WM_TIMER && wparam.0 == TIMER_ID {
        let _ = std::panic::catch_unwind(|| {
            // SAFETY: このスレッドの窓の時計．一度だけ鳴らす
            let _ = unsafe { KillTimer(Some(window), TIMER_ID) };
            if let Some(handler) = HANDLER.with(Cell::get) {
                handler();
            }
        });
        return LRESULT(0);
    }
    // SAFETY: ほかのメッセージは既定の扱いに任せる
    unsafe { DefWindowProcW(window, message, wparam, lparam) }
}
