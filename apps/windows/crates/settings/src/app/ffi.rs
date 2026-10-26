#![allow(unsafe_code)]

//! Win32 の呼び出し．unsafe はこのモジュールだけに置き，ほかのモジュールは安全な関数として使う．
//! ここで扱う HWND・HDC・GDI のオブジェクトは，すべてこのプロセスの UI スレッドで作ったもの

use crate::layout::Rect;
use tokens::Rgb;
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, POINT, RECT, WPARAM};
use windows::Win32::Graphics::Dwm::{DwmSetWindowAttribute, DWMWA_USE_IMMERSIVE_DARK_MODE};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, CreateFontIndirectW, CreatePen, CreateSolidBrush, DeleteObject, DrawTextW,
    EndPaint, FillRect, FrameRect, GetDC, GetSysColor, GetTextFaceW, InvalidateRect, ReleaseDC,
    RoundRect, SelectObject, SetBkColor, SetBkMode, SetTextColor, DRAW_TEXT_FORMAT, DT_CALCRECT,
    DT_NOPREFIX, DT_WORDBREAK, FW_NORMAL, FW_SEMIBOLD, HBRUSH, HDC, HFONT, HGDIOBJ, LOGFONTW,
    PAINTSTRUCT, PS_SOLID, SYS_COLOR_INDEX, TRANSPARENT,
};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_DWORD};
use windows::Win32::UI::Accessibility::{HCF_HIGHCONTRASTON, HIGHCONTRASTW};
use windows::Win32::UI::Controls::{
    SetScrollInfo, SetWindowTheme, CDIS_DISABLED, CDIS_FOCUS, CDIS_HOT, CDIS_SELECTED,
    DRAWITEMSTRUCT, EMF_CENTERED, LVCF_TEXT, LVCF_WIDTH, LVCOLUMNW, LVIF_TEXT, LVITEMW,
    LVM_DELETEALLITEMS, LVM_GETNEXTITEM, LVM_INSERTCOLUMNW, LVM_INSERTITEMW, LVM_SETBKCOLOR,
    LVM_SETCOLUMNWIDTH, LVM_SETEXTENDEDLISTVIEWSTYLE, LVM_SETITEMTEXTW, LVM_SETTEXTBKCOLOR,
    LVM_SETTEXTCOLOR, LVNI_SELECTED, LVS_EX_DOUBLEBUFFER, LVS_EX_FULLROWSELECT, MEASUREITEMSTRUCT,
    NMCUSTOMDRAW, NMHDR, NMLVEMPTYMARKUP, ODS_FOCUS, ODS_SELECTED,
};
use windows::Win32::UI::HiDpi::{
    GetDpiForWindow, GetSystemMetricsForDpi, SetProcessDpiAwarenessContext,
    DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2,
};
use windows::Win32::UI::Input::KeyboardAndMouse::EnableWindow;
use windows::Win32::UI::Shell::ShellExecuteW;
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DestroyWindow, DispatchMessageW, GetClientRect, GetMessageW,
    GetWindowTextW, IsDialogMessageW, KillTimer, LoadCursorW, MessageBoxW, PostQuitMessage,
    RegisterClassExW, SendMessageW, SetTimer, SetWindowPos, SetWindowTextW, ShowWindow,
    SystemParametersInfoW, TranslateMessage, CS_HREDRAW, CS_VREDRAW, HMENU, IDC_ARROW, IDOK,
    MB_ICONINFORMATION, MB_ICONQUESTION, MB_ICONWARNING, MB_OK, MB_OKCANCEL, MINMAXINFO, MSG,
    SB_VERT, SCROLLINFO, SIF_PAGE, SIF_POS, SIF_RANGE, SM_CXVSCROLL, SPI_GETHIGHCONTRAST,
    SWP_NOACTIVATE, SWP_NOMOVE, SWP_NOZORDER, SW_HIDE, SW_SHOW, SW_SHOWNORMAL,
    SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS, WINDOW_EX_STYLE, WINDOW_STYLE, WM_SETFONT, WNDCLASSEXW,
    WNDPROC,
};
use windows_core::{w, BOOL, HSTRING, PCWSTR, PWSTR};

pub use windows::Win32::Foundation::HWND as Window;

/// 96dpi のときの 1 ピクセル
pub const BASE_DPI: u32 = 96;

pub fn colorref(color: Rgb) -> COLORREF {
    COLORREF(u32::from(color.red) | (u32::from(color.green) << 8) | (u32::from(color.blue) << 16))
}

pub fn system_color(index: SYS_COLOR_INDEX) -> Rgb {
    // SAFETY: 引数は定数の色の番号だけで，戻り値を読むだけ
    let value = unsafe { GetSysColor(index) };
    Rgb {
        red: (value & 0xff) as u8,
        green: ((value >> 8) & 0xff) as u8,
        blue: ((value >> 16) & 0xff) as u8,
    }
}

pub fn set_dpi_aware() {
    // SAFETY: プロセスの最初に一度だけ呼ぶ．失敗しても既定の扱いのまま動く
    let _ = unsafe { SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) };
}

/// 縦の送りの幅
pub fn scrollbar_width(dpi: u32) -> i32 {
    // SAFETY: 定数を渡して戻り値を読むだけ
    unsafe { GetSystemMetricsForDpi(SM_CXVSCROLL, dpi) }
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

/// 窓の種類を登録する．同じ名前を二度登録したときの失敗は無視する(窓を作るときに分かる)
pub fn register_class(name: PCWSTR, procedure: WNDPROC) {
    // SAFETY: 名前は静的な文字列，手続きは extern "system" の関数
    unsafe {
        let Ok(instance) = GetModuleHandleW(None) else {
            return;
        };
        let class = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            style: CS_HREDRAW | CS_VREDRAW,
            lpfnWndProc: procedure,
            hInstance: instance.into(),
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
            parent.map(|_| HMENU(usize::from(id) as *mut _)),
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

/// lparam に文字列を渡すメッセージ(CB_ADDSTRING・LB_ADDSTRING・EM_SETCUEBANNER)
pub fn send_text(window: HWND, message: u32, wparam: usize, text: &str) -> isize {
    let text = HSTRING::from(text);
    // SAFETY: text は呼び出しの間生きていて，相手は同期して読む
    unsafe {
        SendMessageW(
            window,
            message,
            Some(WPARAM(wparam)),
            Some(LPARAM(text.as_ptr() as isize)),
        )
    }
    .0
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
    let mut buffer = [0u16; 256];
    // SAFETY: buffer はこの関数の中の値で，長さを渡す
    let length = unsafe { GetWindowTextW(window, &mut buffer) };
    String::from_utf16_lossy(&buffer[..usize::try_from(length).unwrap_or(0).min(buffer.len())])
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

pub fn enable(window: HWND, enabled: bool) {
    // SAFETY: このスレッドの窓
    let _ = unsafe { EnableWindow(window, enabled) };
}

pub fn destroy(window: HWND) {
    // SAFETY: このスレッドの窓．子の窓も一緒に消える
    let _ = unsafe { DestroyWindow(window) };
}

pub fn invalidate(window: HWND) {
    // SAFETY: このスレッドの窓
    let _ = unsafe { InvalidateRect(Some(window), None, true) };
}

pub fn client_size(window: HWND) -> (i32, i32) {
    let mut rect = RECT::default();
    // SAFETY: rect はこの関数の中の値
    let _ = unsafe { GetClientRect(window, &mut rect) };
    (rect.right - rect.left, rect.bottom - rect.top)
}

pub fn set_theme(window: HWND, name: Option<&str>) {
    let name = name.map(HSTRING::from);
    // SAFETY: このスレッドの窓．name は呼び出しの間生きている
    let _ = unsafe {
        match &name {
            Some(name) => SetWindowTheme(window, name, PCWSTR::null()),
            None => SetWindowTheme(window, PCWSTR::null(), PCWSTR::null()),
        }
    };
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

/// アプリをダークで描くか(設定 > 個人用設定 > 色 > アプリ モード)
pub fn apps_use_dark() -> bool {
    let mut value = 1u32;
    let mut size = std::mem::size_of::<u32>() as u32;
    // SAFETY: value と size はこの関数の中の値で，DWORD を 1 つ受ける大きさ
    let result = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            w!("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
            w!("AppsUseLightTheme"),
            RRF_RT_REG_DWORD,
            None,
            Some((&raw mut value).cast()),
            Some(&mut size),
        )
    };
    result.is_ok() && value == 0
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

pub fn set_vertical_scroll(window: HWND, range: i32, page: i32, position: i32) {
    let info = SCROLLINFO {
        cbSize: std::mem::size_of::<SCROLLINFO>() as u32,
        fMask: SIF_RANGE | SIF_PAGE | SIF_POS,
        nMin: 0,
        nMax: range.max(0),
        nPage: page.max(0) as u32,
        nPos: position,
        nTrackPos: 0,
    };
    // SAFETY: info はこの関数の中の値
    unsafe { SetScrollInfo(window, SB_VERT, &info, true) };
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

/// WM_MEASUREITEM の項目の番号
pub fn measure_item_index(lparam: LPARAM) -> Option<usize> {
    // SAFETY: WM_MEASUREITEM の lparam は MEASUREITEMSTRUCT を指す
    unsafe { (lparam.0 as *const MEASUREITEMSTRUCT).as_ref() }.map(|item| item.itemID as usize)
}

pub fn set_measured_height(lparam: LPARAM, height: u32) {
    // SAFETY: WM_MEASUREITEM の lparam は MEASUREITEMSTRUCT を指す
    if let Some(item) = unsafe { (lparam.0 as *mut MEASUREITEMSTRUCT).as_mut() } {
        item.itemHeight = height;
    }
}

/// 自分で描く部品の，描く場所と状態
pub struct DrawTarget {
    pub window: HWND,
    pub hdc: HDC,
    pub rect: (i32, i32, i32, i32),
    pub index: Option<usize>,
    pub selected: bool,
    pub focused: bool,
    pub hot: bool,
    pub pressed: bool,
    pub disabled: bool,
}

/// WM_DRAWITEM(左の一覧)
pub fn draw_item(lparam: LPARAM) -> Option<DrawTarget> {
    // SAFETY: WM_DRAWITEM の lparam は DRAWITEMSTRUCT を指す
    let item = unsafe { (lparam.0 as *const DRAWITEMSTRUCT).as_ref() }?;
    let rect = item.rcItem;
    Some(DrawTarget {
        window: item.hwndItem,
        hdc: item.hDC,
        rect: (rect.left, rect.top, rect.right, rect.bottom),
        index: (item.itemID != u32::MAX).then_some(item.itemID as usize),
        selected: (item.itemState.0 & ODS_SELECTED.0) != 0,
        focused: (item.itemState.0 & ODS_FOCUS.0) != 0,
        hot: false,
        pressed: false,
        disabled: false,
    })
}

/// WM_NOTIFY の送り手と知らせの種類
pub fn notify_header(lparam: LPARAM) -> Option<(HWND, u32)> {
    // SAFETY: WM_NOTIFY の lparam は NMHDR を指す
    unsafe { (lparam.0 as *const NMHDR).as_ref() }.map(|header| (header.hwndFrom, header.code))
}

/// NM_CUSTOMDRAW の描く段階と場所．stage は CDDS_* の値
pub fn custom_draw(lparam: LPARAM) -> Option<(u32, DrawTarget)> {
    // SAFETY: NM_CUSTOMDRAW の lparam は NMCUSTOMDRAW を指す
    let draw = unsafe { (lparam.0 as *const NMCUSTOMDRAW).as_ref() }?;
    let rect = draw.rc;
    let state = draw.uItemState;
    Some((
        draw.dwDrawStage.0,
        DrawTarget {
            window: draw.hdr.hwndFrom,
            hdc: draw.hdc,
            rect: (rect.left, rect.top, rect.right, rect.bottom),
            index: None,
            selected: false,
            focused: (state.0 & CDIS_FOCUS.0) != 0,
            hot: (state.0 & CDIS_HOT.0) != 0,
            pressed: (state.0 & CDIS_SELECTED.0) != 0,
            disabled: (state.0 & CDIS_DISABLED.0) != 0,
        },
    ))
}

pub fn run_message_loop(dialog: HWND) {
    let mut message = MSG::default();
    // SAFETY: このスレッドのメッセージを受けて配る．dialog はこのスレッドの窓
    unsafe {
        while GetMessageW(&mut message, None, 0, 0).as_bool() {
            if IsDialogMessageW(dialog, &message).as_bool() {
                continue;
            }
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

/// 一覧(ListView)の列を作り直す．widths は列の幅
pub fn list_set_columns(list: HWND, titles: &[&str], widths: &[i32]) {
    for (index, (title, width)) in titles.iter().zip(widths).enumerate() {
        let mut text: Vec<u16> = title.encode_utf16().chain(std::iter::once(0)).collect();
        let column = LVCOLUMNW {
            mask: LVCF_TEXT | LVCF_WIDTH,
            cx: *width,
            pszText: PWSTR(text.as_mut_ptr()),
            ..Default::default()
        };
        // SAFETY: column と text は呼び出しの間生きていて，一覧は同期して写す
        unsafe {
            SendMessageW(
                list,
                LVM_INSERTCOLUMNW,
                Some(WPARAM(index)),
                Some(LPARAM((&raw const column) as isize)),
            )
        };
    }
}

pub fn list_set_column_width(list: HWND, index: usize, width: i32) {
    send(list, LVM_SETCOLUMNWIDTH, index, width as isize);
}

/// 一覧の行をすべて入れ替える．rows の各行は列ごとの文字
pub fn list_set_rows(list: HWND, rows: &[Vec<String>]) {
    send(list, LVM_DELETEALLITEMS, 0, 0);
    for (index, row) in rows.iter().enumerate() {
        for (column, cell) in row.iter().enumerate() {
            let mut text: Vec<u16> = cell.encode_utf16().chain(std::iter::once(0)).collect();
            let item = LVITEMW {
                mask: LVIF_TEXT,
                iItem: index as i32,
                iSubItem: column as i32,
                pszText: PWSTR(text.as_mut_ptr()),
                ..Default::default()
            };
            let message = if column == 0 {
                LVM_INSERTITEMW
            } else {
                LVM_SETITEMTEXTW
            };
            // SAFETY: item と text は呼び出しの間生きていて，一覧は同期して写す
            unsafe {
                SendMessageW(
                    list,
                    message,
                    Some(WPARAM(index)),
                    Some(LPARAM((&raw const item) as isize)),
                )
            };
        }
    }
}

/// 選んでいる行の番号
pub fn list_selected(list: HWND) -> Vec<usize> {
    let mut result = Vec::new();
    let mut from: isize = -1;
    loop {
        let next = send(list, LVM_GETNEXTITEM, from as usize, LVNI_SELECTED as isize);
        let Ok(index) = usize::try_from(next) else {
            break;
        };
        result.push(index);
        from = next;
    }
    result
}

pub fn list_set_colors(list: HWND, text: Rgb, background: Rgb) {
    send(list, LVM_SETBKCOLOR, 0, colorref(background).0 as isize);
    send(list, LVM_SETTEXTBKCOLOR, 0, colorref(background).0 as isize);
    send(list, LVM_SETTEXTCOLOR, 0, colorref(text).0 as isize);
    send(
        list,
        LVM_SETEXTENDEDLISTVIEWSTYLE,
        (LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER) as usize,
        (LVS_EX_FULLROWSELECT | LVS_EX_DOUBLEBUFFER) as isize,
    );
}

/// LVN_GETEMPTYMARKUP に，一覧が空のときの文を書く
pub fn set_empty_markup(lparam: LPARAM, text: &str) {
    // SAFETY: LVN_GETEMPTYMARKUP の lparam は NMLVEMPTYMARKUP を指す
    if let Some(markup) = unsafe { (lparam.0 as *mut NMLVEMPTYMARKUP).as_mut() } {
        markup.dwFlags = EMF_CENTERED;
        let limit = markup.szMarkup.len() - 1;
        for (slot, unit) in markup
            .szMarkup
            .iter_mut()
            .zip(text.encode_utf16().take(limit))
        {
            *slot = unit;
        }
        markup.szMarkup[text.encode_utf16().count().min(limit)] = 0;
    }
}

/// 窓を消すときに一緒に消す書体
pub struct Font(HFONT);

impl Font {
    pub fn new(face: &str, height: i32, semibold: bool) -> Option<Self> {
        let mut name = [0u16; 32];
        for (slot, unit) in name.iter_mut().zip(face.encode_utf16().take(31)) {
            *slot = unit;
        }
        // SAFETY: LOGFONTW はこの関数の中の値
        let font = unsafe {
            CreateFontIndirectW(&LOGFONTW {
                lfHeight: -height,
                lfWeight: if semibold { FW_SEMIBOLD.0 } else { FW_NORMAL.0 } as i32,
                lfFaceName: name,
                ..Default::default()
            })
        };
        (!font.is_invalid()).then_some(Self(font))
    }

    /// 書体が入っていれば作る(入っていなければ OS が別の書体に置き換えるので，名前で確かめる)
    pub fn installed(window: HWND, face: &str, height: i32) -> Option<Self> {
        let font = Self::new(face, height, false)?;
        // SAFETY: DC はこの関数の中で借りて返す．選んだ書体は戻す
        let actual = unsafe {
            let hdc = GetDC(Some(window));
            let old = SelectObject(hdc, HGDIOBJ(font.0 .0));
            let mut name = [0u16; 64];
            let length = GetTextFaceW(hdc, Some(&mut name));
            SelectObject(hdc, old);
            ReleaseDC(Some(window), hdc);
            String::from_utf16_lossy(
                &name[..usize::try_from(length)
                    .unwrap_or(0)
                    .saturating_sub(1)
                    .min(name.len())],
            )
        };
        actual.eq_ignore_ascii_case(face).then_some(font)
    }
}

impl Drop for Font {
    fn drop(&mut self) {
        // SAFETY: 自分で作った書体で，ほかに持ち主はいない(部品には窓を消す前に別の書体を渡し直す)
        let _ = unsafe { DeleteObject(HGDIOBJ(self.0 .0)) };
    }
}

/// 窓を消すときに一緒に消す塗り
pub struct Brush(HBRUSH);

impl Brush {
    pub fn new(color: Rgb) -> Self {
        // SAFETY: 色を渡すだけ
        Self(unsafe { CreateSolidBrush(colorref(color)) })
    }

    pub fn handle(&self) -> isize {
        self.0 .0 as isize
    }
}

impl Drop for Brush {
    fn drop(&mut self) {
        // SAFETY: 自分で作った塗りで，ほかに持ち主はいない
        let _ = unsafe { DeleteObject(HGDIOBJ(self.0 .0)) };
    }
}

/// WM_CTLCOLOR* の DC に文字の色と地の色を入れる
pub fn color_control(hdc: usize, text: Rgb, background: Rgb) {
    let hdc = HDC(hdc as *mut _);
    // SAFETY: WM_CTLCOLOR* の wparam は描いている DC
    unsafe {
        SetTextColor(hdc, colorref(text));
        SetBkColor(hdc, colorref(background));
    }
}

/// 窓の WM_PAINT の間だけ使う描画
pub struct Paint {
    window: HWND,
    paint: PAINTSTRUCT,
    hdc: HDC,
}

impl Paint {
    pub fn begin(window: HWND) -> Self {
        let mut paint = PAINTSTRUCT::default();
        // SAFETY: WM_PAINT の中で呼び，drop で EndPaint を呼ぶ
        let hdc = unsafe { BeginPaint(window, &mut paint) };
        Self { window, paint, hdc }
    }

    pub fn canvas(&self) -> Canvas {
        Canvas(self.hdc)
    }
}

impl Drop for Paint {
    fn drop(&mut self) {
        // SAFETY: begin で始めた描画を終える
        let _ = unsafe { EndPaint(self.window, &self.paint) };
    }
}

/// DC に描く．DC は WM_PAINT・NM_CUSTOMDRAW・WM_DRAWITEM で受けたもの
#[derive(Clone, Copy)]
pub struct Canvas(HDC);

impl Canvas {
    pub fn of(target: &DrawTarget) -> Self {
        Self(target.hdc)
    }

    pub fn fill(&self, rect: (i32, i32, i32, i32), color: Rgb) {
        let brush = Brush::new(color);
        let rect = RECT {
            left: rect.0,
            top: rect.1,
            right: rect.2,
            bottom: rect.3,
        };
        // SAFETY: brush はこの関数の中で作って drop で消す
        unsafe { FillRect(self.0, &rect, brush.0) };
    }

    /// 角の丸い四角．stroke が None なら縁を描かない
    pub fn round_rect(
        &self,
        rect: (i32, i32, i32, i32),
        radius: i32,
        fill: Rgb,
        stroke: Option<Rgb>,
    ) {
        let brush = Brush::new(fill);
        // SAFETY: ペンと塗りはこの関数の中で作って選び，戻してから消す
        unsafe {
            let pen = CreatePen(PS_SOLID, 1, colorref(stroke.unwrap_or(fill)));
            let old_pen = SelectObject(self.0, HGDIOBJ(pen.0));
            let old_brush = SelectObject(self.0, HGDIOBJ(brush.0 .0));
            let _ = RoundRect(
                self.0,
                rect.0,
                rect.1,
                rect.2,
                rect.3,
                radius * 2,
                radius * 2,
            );
            SelectObject(self.0, old_brush);
            SelectObject(self.0, old_pen);
            let _ = DeleteObject(HGDIOBJ(pen.0));
        }
    }

    /// 1 ピクセルの枠(キーボードで選んでいる部品の印)
    pub fn frame(&self, rect: (i32, i32, i32, i32), color: Rgb) {
        let brush = Brush::new(color);
        let rect = RECT {
            left: rect.0,
            top: rect.1,
            right: rect.2,
            bottom: rect.3,
        };
        // SAFETY: brush はこの関数の中で作って drop で消す
        unsafe { FrameRect(self.0, &rect, brush.0) };
    }

    pub fn text(
        &self,
        rect: (i32, i32, i32, i32),
        text: &str,
        font: &Font,
        color: Rgb,
        format: DRAW_TEXT_FORMAT,
    ) {
        let mut units: Vec<u16> = text.encode_utf16().collect();
        let mut rect = RECT {
            left: rect.0,
            top: rect.1,
            right: rect.2,
            bottom: rect.3,
        };
        // SAFETY: 書体は選んで戻す．units と rect はこの関数の中の値
        unsafe {
            let old = SelectObject(self.0, HGDIOBJ(font.0 .0));
            SetBkMode(self.0, TRANSPARENT);
            SetTextColor(self.0, colorref(color));
            DrawTextW(self.0, &mut units, &mut rect, format | DT_NOPREFIX);
            SelectObject(self.0, old);
        }
    }
}

/// 文を幅に収めて折り返したときの高さ
pub fn text_height(window: HWND, font: &Font, text: &str, width: i32) -> i32 {
    let mut units: Vec<u16> = text.encode_utf16().collect();
    let mut rect = RECT {
        left: 0,
        top: 0,
        right: width.max(1),
        bottom: 0,
    };
    // SAFETY: DC はこの関数の中で借りて返す．選んだ書体は戻す
    unsafe {
        let hdc = GetDC(Some(window));
        let old = SelectObject(hdc, HGDIOBJ(font.0 .0));
        DrawTextW(
            hdc,
            &mut units,
            &mut rect,
            DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX,
        );
        SelectObject(hdc, old);
        ReleaseDC(Some(window), hdc);
    }
    rect.bottom - rect.top
}

/// 96dpi の値を窓の DPI の値にする
pub fn scale(value: f32, dpi: u32) -> i32 {
    (value * dpi as f32 / BASE_DPI as f32).round() as i32
}

/// 96dpi の四角を窓の DPI の四角(左・上・右・下)にし，上に dy ずらす
pub fn scaled_rect(rect: Rect, dpi: u32, dy: i32) -> (i32, i32, i32, i32) {
    let left = scale(rect.x, dpi);
    let top = scale(rect.y, dpi) - dy;
    (
        left,
        top,
        left + scale(rect.width, dpi),
        top + scale(rect.height, dpi),
    )
}
