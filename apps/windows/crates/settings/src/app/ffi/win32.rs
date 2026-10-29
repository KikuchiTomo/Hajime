//! Win32 の呼び出し(窓・メッセージ・OS の設定・標準の窓(ファイル・色・知らせ))．
//! ここで扱う HWND は，すべてこのプロセスの UI スレッドで作ったもの

use windows::Win32::Foundation::{
    COLORREF, HWND, LPARAM, LRESULT, POINT, RECT, SYSTEMTIME, WPARAM,
};
use windows::Win32::Graphics::Dwm::{
    DwmExtendFrameIntoClientArea, DwmSetWindowAttribute, DWMSBT_MAINWINDOW, DWMSBT_NONE,
    DWMWA_SYSTEMBACKDROP_TYPE, DWMWA_USE_IMMERSIVE_DARK_MODE, DWMWA_WINDOW_CORNER_PREFERENCE,
    DWMWCP_ROUND,
};
use windows::Win32::Graphics::Gdi::{
    ClientToScreen, CreateFontIndirectW, DeleteObject, GetMonitorInfoW, GetSysColor,
    InvalidateRect, MonitorFromWindow, ScreenToClient, ANTIALIASED_QUALITY, FONT_QUALITY,
    FW_NORMAL, HFONT, HGDIOBJ, LOGFONTW, MONITORINFO, MONITOR_DEFAULTTONEAREST, SYS_COLOR_INDEX,
};
use windows::Win32::System::Com::{
    CoCreateInstance, CoInitializeEx, CoTaskMemFree, CLSCTX_INPROC_SERVER, COINIT_APARTMENTTHREADED,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Registry::{
    RegGetValueW, RegSetKeyValueW, HKEY_CURRENT_USER, REG_DWORD, RRF_RT_REG_DWORD,
};
use windows::Win32::System::Time::SystemTimeToTzSpecificLocalTime;
use windows::Win32::UI::Accessibility::{HCF_HIGHCONTRASTON, HIGHCONTRASTW};
use windows::Win32::UI::Controls::MARGINS;
use windows::Win32::UI::HiDpi::{
    GetDpiForWindow, SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    EnableWindow, GetFocus, GetKeyState, ReleaseCapture, SetCapture, SetFocus, TrackMouseEvent,
    TME_LEAVE, TRACKMOUSEEVENT, VK_CONTROL, VK_SHIFT,
};
use windows::Win32::UI::Shell::Common::COMDLG_FILTERSPEC;
use windows::Win32::UI::Shell::{
    FileOpenDialog, FileSaveDialog, IFileDialog, ShellExecuteW, FILEOPENDIALOGOPTIONS,
    FOS_FORCEFILESYSTEM, FOS_PICKFOLDERS, SIGDN_FILESYSPATH,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, FindWindowW, GetClientRect,
    GetMessageW, GetWindowTextLengthW, GetWindowTextW, KillTimer, LoadCursorW, LoadIconW,
    MessageBoxW, PostMessageW, PostQuitMessage, RegisterClassExW, SendMessageW, SetTimer,
    SetWindowPos, SetWindowTextW, ShowWindow, SystemParametersInfoW, TranslateMessage, CS_DBLCLKS,
    CS_DROPSHADOW, CS_HREDRAW, CS_VREDRAW, HMENU, IDC_ARROW, IDOK, MB_ICONINFORMATION,
    MB_ICONQUESTION, MB_ICONWARNING, MB_OK, MB_OKCANCEL, MINMAXINFO, MSG,
    SPI_GETCLIENTAREAANIMATION, SPI_GETHIGHCONTRAST, SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOZORDER,
    SW_HIDE, SW_SHOW, SW_SHOWNA, SW_SHOWNORMAL, SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS,
    WINDOW_EX_STYLE, WINDOW_STYLE, WM_SETFONT, WNDCLASSEXW, WNDPROC,
};
use windows_core::{w, BOOL, HSTRING, PCWSTR};

pub use windows::Win32::Foundation::HWND as Window;

/// 96dpi のときの 1 ピクセル
pub const BASE_DPI: u32 = 96;

pub fn system_color(index: SYS_COLOR_INDEX) -> tokens::Rgb {
    // SAFETY: 引数は定数の色の番号だけで，戻り値を読むだけ
    let value = unsafe { GetSysColor(index) };
    tokens::Rgb {
        red: (value & 0xff) as u8,
        green: ((value >> 8) & 0xff) as u8,
        blue: ((value >> 16) & 0xff) as u8,
    }
}

pub fn colorref(color: tokens::Rgb) -> COLORREF {
    COLORREF(u32::from(color.red) | (u32::from(color.green) << 8) | (u32::from(color.blue) << 16))
}

pub fn set_dpi_aware() {
    // SAFETY: プロセスの最初に一度だけ呼ぶ．失敗しても既定の扱いのまま動く
    let _ = unsafe { SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) };
}

pub fn dpi(window: HWND) -> u32 {
    // SAFETY: このスレッドで作った窓
    let dpi = unsafe { GetDpiForWindow(window) };
    if dpi == 0 {
        BASE_DPI
    } else {
        dpi
    }
}

/// 96dpi の値を窓の DPI の値にする
pub fn scale(value: f32, dpi: u32) -> i32 {
    (value * dpi as f32 / BASE_DPI as f32).round() as i32
}

/// 窓の種類を登録する．同じ名前を二度登録したときの失敗は無視する(窓を作るときに分かる)．
/// アイコンは実行ファイルのリソースの 1 番(無ければ既定)．shadow は影を落とす窓(開いた一覧)
pub fn register_class(name: PCWSTR, procedure: WNDPROC, shadow: bool) {
    // SAFETY: 名前は静的な文字列，手続きは extern "system" の関数
    unsafe {
        let Ok(instance) = GetModuleHandleW(None) else {
            return;
        };
        // 1 番のアイコン(MAKEINTRESOURCE(1))
        let icon = LoadIconW(
            Some(instance.into()),
            PCWSTR(std::ptr::without_provenance(1)),
        )
        .unwrap_or_default();
        let mut style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
        if shadow {
            style |= CS_DROPSHADOW;
        }
        let class = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            style,
            lpfnWndProc: procedure,
            hInstance: instance.into(),
            hIcon: icon,
            hIconSm: icon,
            hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
            lpszClassName: name,
            ..Default::default()
        };
        RegisterClassExW(&class);
    }
}

#[allow(clippy::too_many_arguments)]
pub fn create(
    ex_style: WINDOW_EX_STYLE,
    class: PCWSTR,
    text: &str,
    style: WINDOW_STYLE,
    rect: (i32, i32, i32, i32),
    parent: Option<HWND>,
    id: u16,
) -> Option<HWND> {
    let (x, y, width, height) = rect;
    let child = style.contains(windows::Win32::UI::WindowsAndMessaging::WS_CHILD);
    // SAFETY: class は登録済みか標準の部品の名前．親はこのスレッドの窓．id は子の窓だけに使う
    unsafe {
        let instance = GetModuleHandleW(None).ok()?;
        CreateWindowExW(
            ex_style,
            class,
            &HSTRING::from(text),
            style,
            x,
            y,
            width,
            height,
            parent,
            (child && parent.is_some()).then(|| HMENU(usize::from(id) as *mut _)),
            Some(instance.into()),
            None,
        )
        .ok()
    }
}

pub fn send(window: HWND, message: u32, wparam: usize, lparam: isize) -> isize {
    // SAFETY: 送る値はポインタを含まない(文字列を送るときは send_text を使う)
    unsafe { SendMessageW(window, message, Some(WPARAM(wparam)), Some(LPARAM(lparam))) }.0
}

/// 自分の窓にメッセージを置く(手続きの外で処理させる)
pub fn post(window: HWND, message: u32, wparam: usize, lparam: isize) {
    // SAFETY: 送る値はポインタを含まない
    let _ = unsafe { PostMessageW(Some(window), message, WPARAM(wparam), LPARAM(lparam)) };
}

pub fn default_procedure(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    // SAFETY: 窓の手続きが受けたものをそのまま渡す
    unsafe { DefWindowProcW(window, message, wparam, lparam) }
}

pub fn set_font(window: HWND, font: &Font) {
    send(window, WM_SETFONT, font.0 .0 as usize, 1);
}

pub fn set_text(window: HWND, text: &str) {
    // SAFETY: このスレッドの窓
    let _ = unsafe { SetWindowTextW(window, &HSTRING::from(text)) };
}

pub fn window_text(window: HWND) -> String {
    // SAFETY: このスレッドの窓
    let length = unsafe { GetWindowTextLengthW(window) };
    let mut buffer = vec![0u16; usize::try_from(length).unwrap_or(0) + 1];
    // SAFETY: buffer はこの関数の中の値で，長さを渡す
    let copied = unsafe { GetWindowTextW(window, &mut buffer) };
    String::from_utf16_lossy(&buffer[..usize::try_from(copied).unwrap_or(0).min(buffer.len())])
}

pub fn place(window: HWND, x: i32, y: i32, width: i32, height: i32) {
    // SAFETY: このスレッドの窓
    let _ = unsafe {
        SetWindowPos(
            window,
            None,
            x,
            y,
            width,
            height,
            SWP_NOZORDER | SWP_NOACTIVATE,
        )
    };
}

/// 位置を変えずに大きさだけを変える
pub fn resize(window: HWND, width: i32, height: i32) {
    // SAFETY: このスレッドの窓
    let _ = unsafe {
        SetWindowPos(
            window,
            None,
            0,
            0,
            width,
            height,
            SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE,
        )
    };
}

pub fn show(window: HWND, visible: bool) {
    // SAFETY: このスレッドの窓
    let _ = unsafe { ShowWindow(window, if visible { SW_SHOW } else { SW_HIDE }) };
}

/// 起動した側が決めた見せ方で見せる(最初に見せるとき)
pub fn show_default(window: HWND) {
    // SAFETY: このスレッドの窓
    let _ = unsafe {
        ShowWindow(
            window,
            windows::Win32::UI::WindowsAndMessaging::SW_SHOWDEFAULT,
        )
    };
}

/// 前に出さずに見せる(開いた一覧)
pub fn show_inactive(window: HWND) {
    // SAFETY: このスレッドの窓
    let _ = unsafe { ShowWindow(window, SW_SHOWNA) };
}

pub fn enable(window: HWND, enabled: bool) {
    // SAFETY: このスレッドの窓
    let _ = unsafe { EnableWindow(window, enabled) };
}

pub fn destroy(window: HWND) {
    // SAFETY: このスレッドの窓．子の窓も一緒に消える
    let _ = unsafe { DestroyWindow(window) };
}

pub fn invalidate(window: HWND) {
    // SAFETY: このスレッドの窓．地は自分で塗るので消さない
    let _ = unsafe { InvalidateRect(Some(window), None, false) };
}

/// 描き直しの求めを済んだことにする(WM_PAINT の中で自分で描いたあと)
pub fn validate(window: HWND) {
    // SAFETY: このスレッドの窓
    let _ = unsafe { windows::Win32::Graphics::Gdi::ValidateRect(Some(window), None) };
}

pub fn client_size(window: HWND) -> (i32, i32) {
    let mut rect = RECT::default();
    // SAFETY: rect はこの関数の中の値
    let _ = unsafe { GetClientRect(window, &mut rect) };
    (rect.right - rect.left, rect.bottom - rect.top)
}

/// 窓の中の点を画面の点にする
pub fn to_screen(window: HWND, x: i32, y: i32) -> (i32, i32) {
    let mut point = POINT { x, y };
    // SAFETY: point はこの関数の中の値
    let _ = unsafe { ClientToScreen(window, &mut point) };
    (point.x, point.y)
}

/// 画面の点を窓の中の点にする
pub fn to_client(window: HWND, x: i32, y: i32) -> (i32, i32) {
    let mut point = POINT { x, y };
    // SAFETY: point はこの関数の中の値
    let _ = unsafe { ScreenToClient(window, &mut point) };
    (point.x, point.y)
}

/// 窓のある画面の作業領域(左・上・右・下)
pub fn work_area(window: HWND) -> (i32, i32, i32, i32) {
    let mut info = MONITORINFO {
        cbSize: std::mem::size_of::<MONITORINFO>() as u32,
        ..Default::default()
    };
    // SAFETY: info はこの関数の中の値で，cbSize を正しく入れている
    unsafe {
        let monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
        let _ = GetMonitorInfoW(monitor, &mut info);
    }
    let rect = info.rcWork;
    (rect.left, rect.top, rect.right, rect.bottom)
}

pub fn set_dark_title_bar(window: HWND, dark: bool) {
    let value = BOOL::from(dark);
    // SAFETY: value はこの関数の中の値で，大きさを正しく渡す
    let _ = unsafe {
        DwmSetWindowAttribute(
            window,
            DWMWA_USE_IMMERSIVE_DARK_MODE,
            (&raw const value).cast(),
            std::mem::size_of::<BOOL>() as u32,
        )
    };
}

/// 窓の地を Windows 11 の Mica にする(on が偽なら戻す)．枠を窓の中まで広げ，地を透明で描いたところに Mica が見える．
/// Mica を使えない Windows(22H2 より前)では偽を返し，枠も広げない
pub fn set_mica(window: HWND, on: bool) -> bool {
    let backdrop = if on { DWMSBT_MAINWINDOW } else { DWMSBT_NONE };
    // SAFETY: backdrop はこの関数の中の値で，大きさを正しく渡す
    let applied = unsafe {
        DwmSetWindowAttribute(
            window,
            DWMWA_SYSTEMBACKDROP_TYPE,
            (&raw const backdrop).cast(),
            std::mem::size_of_val(&backdrop) as u32,
        )
    }
    .is_ok();
    let extend = on && applied;
    let margin = if extend { -1 } else { 0 };
    let margins = MARGINS {
        cxLeftWidth: margin,
        cxRightWidth: margin,
        cyTopHeight: margin,
        cyBottomHeight: margin,
    };
    // SAFETY: margins はこの関数の中の値
    let _ = unsafe { DwmExtendFrameIntoClientArea(window, &margins) };
    extend
}

/// 窓を画面に出さずに隠しておく(true)・出す(false)．出したあと最初に描くまでの白いコマを見せないため，
/// 隠したまま見せて 1 枚描いてから出す
pub fn cloak(window: HWND, on: bool) {
    let value = windows_core::BOOL::from(on);
    // SAFETY: value はこの関数の中の値で，大きさを正しく渡す
    let _ = unsafe {
        DwmSetWindowAttribute(
            window,
            windows::Win32::Graphics::Dwm::DWMWA_CLOAK,
            (&raw const value).cast(),
            std::mem::size_of_val(&value) as u32,
        )
    };
}

/// 次の画面の合成まで待つ(動きのフレームを画面の更新に揃える)
pub fn wait_for_compositor() {
    // SAFETY: 引数なし．合成が止まっていればすぐ戻る
    let _ = unsafe { windows::Win32::Graphics::Dwm::DwmFlush() };
}

/// 窓の角を丸める(Windows 11．開いた一覧)
pub fn set_round_corners(window: HWND) {
    let corner = DWMWCP_ROUND;
    // SAFETY: corner はこの関数の中の値で，大きさを正しく渡す
    let _ = unsafe {
        DwmSetWindowAttribute(
            window,
            DWMWA_WINDOW_CORNER_PREFERENCE,
            (&raw const corner).cast(),
            std::mem::size_of_val(&corner) as u32,
        )
    };
}

fn registry_dword(name: PCWSTR) -> Option<u32> {
    let mut value = 0u32;
    let mut size = std::mem::size_of::<u32>() as u32;
    // SAFETY: value と size はこの関数の中の値で，DWORD を 1 つ受ける大きさ
    let result = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            w!("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
            name,
            RRF_RT_REG_DWORD,
            None,
            Some((&raw mut value).cast()),
            Some(&mut size),
        )
    };
    result.is_ok().then_some(value)
}

/// 初期設定ウィザードを済ませたかを書く場所(利用者ごと．エンジンの設定のファイルには書かない)
const SETUP_KEY: PCWSTR = w!("Software\\haji.men\\IME");
const SETUP_VALUE: PCWSTR = w!("SetupCompleted");

/// 初期設定ウィザードを済ませたか
pub fn setup_completed() -> bool {
    let mut value = 0u32;
    let mut size = std::mem::size_of::<u32>() as u32;
    // SAFETY: value と size はこの関数の中の値で，DWORD を 1 つ受ける大きさ
    let result = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            SETUP_KEY,
            SETUP_VALUE,
            RRF_RT_REG_DWORD,
            None,
            Some((&raw mut value).cast()),
            Some(&mut size),
        )
    };
    result.is_ok() && value != 0
}

/// 初期設定ウィザードを済ませたことを書く
pub fn set_setup_completed() -> bool {
    let value = 1u32;
    // SAFETY: value はこの関数の中の値で，大きさを正しく渡す．キーが無ければ作る
    let result = unsafe {
        RegSetKeyValueW(
            HKEY_CURRENT_USER,
            SETUP_KEY,
            SETUP_VALUE,
            REG_DWORD.0,
            Some((&raw const value).cast()),
            std::mem::size_of::<u32>() as u32,
        )
    };
    result.is_ok()
}

/// この利用者の画面に class の窓がもうあるか(二重に開かない)
pub fn window_exists(class: PCWSTR) -> bool {
    // SAFETY: class は静的な文字列
    unsafe { FindWindowW(class, PCWSTR::null()) }.is_ok_and(|window| !window.is_invalid())
}

/// アプリをダークで描くか(設定 > 個人用設定 > 色 > アプリ モード)
pub fn apps_use_dark() -> bool {
    registry_dword(w!("AppsUseLightTheme")) == Some(0)
}

pub fn high_contrast() -> bool {
    let mut info = HIGHCONTRASTW {
        cbSize: std::mem::size_of::<HIGHCONTRASTW>() as u32,
        ..Default::default()
    };
    // SAFETY: info はこの関数の中の値で，cbSize を正しく入れている
    let result = unsafe {
        SystemParametersInfoW(
            SPI_GETHIGHCONTRAST,
            info.cbSize,
            Some((&raw mut info).cast()),
            SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
        )
    };
    result.is_ok() && info.dwFlags.contains(HCF_HIGHCONTRASTON)
}

/// 動きを見せるか(設定 > アクセシビリティ > 視覚効果 > アニメーション効果)
pub fn animations_enabled() -> bool {
    let mut enabled = BOOL::from(true);
    // SAFETY: enabled はこの関数の中の値
    let result = unsafe {
        SystemParametersInfoW(
            SPI_GETCLIENTAREAANIMATION,
            0,
            Some((&raw mut enabled).cast()),
            SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
        )
    };
    result.is_err() || enabled.as_bool()
}

/// Ctrl・Shift を押しているか
pub fn modifiers() -> (bool, bool) {
    // SAFETY: 引数は定数のキーの番号
    unsafe {
        (
            GetKeyState(i32::from(VK_CONTROL.0)) < 0,
            GetKeyState(i32::from(VK_SHIFT.0)) < 0,
        )
    }
}

/// ポインターが窓から出たら WM_MOUSELEAVE が届くようにする
pub fn track_leave(window: HWND) {
    let mut track = TRACKMOUSEEVENT {
        cbSize: std::mem::size_of::<TRACKMOUSEEVENT>() as u32,
        dwFlags: TME_LEAVE,
        hwndTrack: window,
        dwHoverTime: 0,
    };
    // SAFETY: track はこの関数の中の値
    let _ = unsafe { TrackMouseEvent(&mut track) };
}

pub fn capture(window: HWND) {
    // SAFETY: このスレッドの窓
    unsafe { SetCapture(window) };
}

pub fn release_capture() {
    // SAFETY: 引数なし
    let _ = unsafe { ReleaseCapture() };
}

pub fn focus(window: HWND) {
    // SAFETY: このスレッドの窓
    let _ = unsafe { SetFocus(Some(window)) };
}

pub fn focused() -> Option<HWND> {
    // SAFETY: 引数なし
    let window = unsafe { GetFocus() };
    (!window.is_invalid()).then_some(window)
}

/// この(画面の)スレッドで COM を使えるようにする．失敗したらファイルを選ぶ窓が出ないだけで，ほかは動く
pub fn initialize_com() {
    // SAFETY: プロセスの最初に画面のスレッドで一度だけ呼ぶ
    let _ = unsafe { CoInitializeEx(None, COINIT_APARTMENTTHREADED) };
}

/// ファイルを選ぶ窓(開く・保存)を出し，選んだファイルの場所を返す．キャンセルしたら None
pub fn choose_file(
    owner: HWND,
    open: bool,
    name: &str,
    filter_name: &str,
    pattern: &str,
) -> Option<String> {
    let filter_name = HSTRING::from(filter_name);
    let pattern = HSTRING::from(pattern);
    let filters = [COMDLG_FILTERSPEC {
        pszName: PCWSTR(filter_name.as_ptr()),
        pszSpec: PCWSTR(pattern.as_ptr()),
    }];
    let class = if open {
        &FileOpenDialog
    } else {
        &FileSaveDialog
    };
    // SAFETY: 引数は定数だけ
    let dialog: IFileDialog =
        unsafe { CoCreateInstance(class, None, CLSCTX_INPROC_SERVER) }.ok()?;
    // SAFETY: filters の文字列は呼び出しの間生きている
    unsafe { dialog.SetFileTypes(&filters) }.ok()?;
    if !open && !name.is_empty() {
        // SAFETY: 文字列は呼び出しの間生きている
        unsafe { dialog.SetFileName(&HSTRING::from(name)) }.ok()?;
        if let Some((_, extension)) = name.rsplit_once('.') {
            // SAFETY: 同上
            unsafe { dialog.SetDefaultExtension(&HSTRING::from(extension)) }.ok()?;
        }
    }
    show_dialog(&dialog, owner, FOS_FORCEFILESYSTEM)
}

/// フォルダを選ぶ窓を出し，選んだフォルダの場所を返す．キャンセルしたら None
pub fn choose_folder(owner: HWND) -> Option<String> {
    // SAFETY: 引数は定数だけ
    let dialog: IFileDialog =
        unsafe { CoCreateInstance(&FileOpenDialog, None, CLSCTX_INPROC_SERVER) }.ok()?;
    show_dialog(&dialog, owner, FOS_FORCEFILESYSTEM | FOS_PICKFOLDERS)
}

/// 窓を出して選んだ場所を返す．返された場所の文字列は CoTaskMemFree で放す
fn show_dialog(
    dialog: &IFileDialog,
    owner: HWND,
    options: FILEOPENDIALOGOPTIONS,
) -> Option<String> {
    // SAFETY: dialog はこの関数の間生きている COM のオブジェクト．owner はこのスレッドの窓
    unsafe {
        let current = dialog.GetOptions().ok()?;
        dialog.SetOptions(current | options).ok()?;
        // キャンセルは Err で返る
        dialog.Show(Some(owner)).ok()?;
        let item = dialog.GetResult().ok()?;
        let path = item.GetDisplayName(SIGDN_FILESYSPATH).ok()?;
        let text = path.to_string().ok();
        CoTaskMemFree(Some(path.0 as *const _));
        text
    }
}

/// 色を選ぶ窓を出し，選んだ色を返す．キャンセルしたら None
pub fn choose_color(owner: HWND, current: Option<(u8, u8, u8)>) -> Option<(u8, u8, u8)> {
    use windows::Win32::UI::Controls::Dialogs::{
        ChooseColorW, CC_FULLOPEN, CC_RGBINIT, CHOOSECOLORW,
    };
    thread_local! {
        /// 窓の「作成した色」(窓を開き直しても残す)
        static CUSTOM: std::cell::RefCell<[COLORREF; 16]> = const { std::cell::RefCell::new([COLORREF(0x00FF_FFFF); 16]) };
    }
    let (red, green, blue) = current.unwrap_or((0, 0, 0));
    CUSTOM.with(|custom| {
        let mut custom = custom.borrow_mut();
        let mut dialog = CHOOSECOLORW {
            lStructSize: std::mem::size_of::<CHOOSECOLORW>() as u32,
            hwndOwner: owner,
            rgbResult: COLORREF(u32::from(red) | (u32::from(green) << 8) | (u32::from(blue) << 16)),
            lpCustColors: custom.as_mut_ptr(),
            Flags: CC_FULLOPEN | CC_RGBINIT,
            ..Default::default()
        };
        // SAFETY: dialog と custom は呼び出しのあいだ生きている
        let chosen = unsafe { ChooseColorW(&mut dialog) }.as_bool();
        chosen.then(|| {
            let value = dialog.rgbResult.0;
            (
                (value & 0xff) as u8,
                ((value >> 8) & 0xff) as u8,
                ((value >> 16) & 0xff) as u8,
            )
        })
    })
}

/// UTC の年・月・日・時・分・秒を，この PC の地方時にする
pub fn local_time([year, month, day, hour, minute, second]: [u16; 6]) -> Option<[u16; 6]> {
    let universal = SYSTEMTIME {
        wYear: year,
        wMonth: month,
        wDay: day,
        wHour: hour,
        wMinute: minute,
        wSecond: second,
        ..Default::default()
    };
    let mut local = SYSTEMTIME::default();
    // SAFETY: 2 つの値はこの関数の中の値で，呼び出しの間生きている
    unsafe { SystemTimeToTzSpecificLocalTime(None, &universal, &mut local) }.ok()?;
    Some([
        local.wYear,
        local.wMonth,
        local.wDay,
        local.wHour,
        local.wMinute,
        local.wSecond,
    ])
}

/// ファイルを既定のアプリで開く
pub fn open_with_default_app(path: &std::path::Path) {
    let path = HSTRING::from(path.as_os_str());
    // SAFETY: path は呼び出しの間生きている
    unsafe {
        ShellExecuteW(None, w!("open"), &path, None, None, SW_SHOWNORMAL);
    }
}

/// 確かめる窓(OK とキャンセル)．OK なら true
pub fn confirm(owner: HWND, title: &str, text: &str) -> bool {
    // SAFETY: owner はこのスレッドの窓．文字列は呼び出しの間生きている
    let result = unsafe {
        MessageBoxW(
            Some(owner),
            &HSTRING::from(text),
            &HSTRING::from(title),
            MB_OKCANCEL | MB_ICONQUESTION,
        )
    };
    result == IDOK
}

pub fn message(owner: HWND, title: &str, text: &str, warning: bool) {
    let icon = if warning {
        MB_ICONWARNING
    } else {
        MB_ICONINFORMATION
    };
    // SAFETY: owner はこのスレッドの窓．文字列は呼び出しの間生きている
    unsafe {
        MessageBoxW(
            Some(owner),
            &HSTRING::from(text),
            &HSTRING::from(title),
            MB_OK | icon,
        )
    };
}

/// 最小の大きさを WM_GETMINMAXINFO に書く
pub fn set_min_size(lparam: LPARAM, width: i32, height: i32) {
    // SAFETY: WM_GETMINMAXINFO の lparam は MINMAXINFO を指す
    if let Some(info) = unsafe { (lparam.0 as *mut MINMAXINFO).as_mut() } {
        info.ptMinTrackSize = POINT {
            x: width,
            y: height,
        };
    }
}

/// WM_DPICHANGED の lparam が指す，窓の新しい位置
pub fn suggested_rect(lparam: LPARAM) -> Option<(i32, i32, i32, i32)> {
    // SAFETY: WM_DPICHANGED の lparam は RECT を指す
    unsafe { (lparam.0 as *const RECT).as_ref() }.map(|rect| {
        (
            rect.left,
            rect.top,
            rect.right - rect.left,
            rect.bottom - rect.top,
        )
    })
}

pub fn run_message_loop() {
    let mut message = MSG::default();
    // SAFETY: このスレッドのメッセージを受けて配る
    unsafe {
        while GetMessageW(&mut message, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&message);
            DispatchMessageW(&message);
        }
    }
}

/// 窓に時計を付ける(WM_TIMER が届く)．同じ番号なら置き換える
pub fn set_timer(window: HWND, id: usize, milliseconds: u32) {
    // SAFETY: このスレッドの窓．手続きは窓のものを使う
    unsafe { SetTimer(Some(window), id, milliseconds, None) };
}

pub fn kill_timer(window: HWND, id: usize) {
    // SAFETY: このスレッドの窓
    let _ = unsafe { KillTimer(Some(window), id) };
}

pub fn quit() {
    // SAFETY: このスレッドのメッセージの繰り返しを終える
    unsafe { PostQuitMessage(0) };
}

/// 標準の入力欄に付ける書体．画面のほかの文字(Direct2D のグレースケール)と揃えるため，色ずれのしない滑らかさにする
pub struct Font(HFONT);

impl Font {
    pub fn new(face: &str, height: i32) -> Option<Self> {
        let mut name = [0u16; 32];
        for (slot, unit) in name.iter_mut().zip(face.encode_utf16().take(31)) {
            *slot = unit;
        }
        // SAFETY: LOGFONTW はこの関数の中の値
        let font = unsafe {
            CreateFontIndirectW(&LOGFONTW {
                lfHeight: -height,
                lfWeight: FW_NORMAL.0 as i32,
                lfQuality: FONT_QUALITY(ANTIALIASED_QUALITY.0),
                lfFaceName: name,
                ..Default::default()
            })
        };
        (!font.is_invalid()).then_some(Self(font))
    }
}

impl Drop for Font {
    fn drop(&mut self) {
        // SAFETY: new で作った書体．選んでいる部品は先に消える(窓を消してから書体を消す)
        let _ = unsafe { DeleteObject(HGDIOBJ(self.0 .0)) };
    }
}
