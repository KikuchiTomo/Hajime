//! 文字を打つ欄．IME・クリップボード・読み上げのために枠の無い標準の EDIT を使い，枠は Direct2D で親が描く．
//! 案内の文字(placeholder)は読める濃さで自分で描き，Tab・Enter・ホイールは親に回す

use super::win32::{colorref, Font};
use std::cell::Cell;
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, LRESULT, RECT, WPARAM};
use windows::Win32::Graphics::Gdi::{
    BeginPaint, CreateSolidBrush, DeleteObject, DrawTextW, EndPaint, SelectObject, SetBkMode,
    SetTextColor, DT_LEFT, DT_NOPREFIX, DT_SINGLELINE, DT_VCENTER, HBRUSH, HDC, HGDIOBJ,
    PAINTSTRUCT, TRANSPARENT,
};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetKeyState, MapVirtualKeyW, MAPVK_VK_TO_CHAR, VK_CONTROL, VK_ESCAPE, VK_MENU, VK_RETURN,
    VK_SHIFT, VK_TAB,
};
use windows::Win32::UI::Shell::{DefSubclassProc, RemoveWindowSubclass, SetWindowSubclass};
use windows::Win32::UI::WindowsAndMessaging::{
    GetClientRect, GetParent, GetWindowTextLengthW, PostMessageW, SendMessageW,
    SetLayeredWindowAttributes, ES_AUTOHSCROLL, LWA_ALPHA, PRF_CLIENT, PRF_ERASEBKGND,
    WINDOW_STYLE, WM_APP, WM_CHAR, WM_GETFONT, WM_KEYDOWN, WM_KILLFOCUS, WM_MOUSEWHEEL,
    WM_NCDESTROY, WM_PAINT, WM_PRINTCLIENT, WM_SETFOCUS, WM_SYSCHAR, WM_SYSKEYDOWN, WS_CHILD,
    WS_EX_LAYERED, WS_TABSTOP,
};
use windows_core::w;

/// 親に届く知らせ: Tab を押した(wparam は Shift を押していれば 1，lparam は欄)
pub const WM_FIELD_TAB: u32 = WM_APP + 1;
/// 親に届く知らせ: Enter を押した(lparam は欄)
pub const WM_FIELD_ENTER: u32 = WM_APP + 2;
/// 親に届く知らせ: フォーカスが入った・出た(wparam は入ったら 1，lparam は欄)
pub const WM_FIELD_FOCUS: u32 = WM_APP + 3;
/// 親に届く知らせ: キーを記録した(lparam は欄)
pub const WM_FIELD_RECORDED: u32 = WM_APP + 4;

const SUBCLASS: usize = 0x5391;

thread_local! {
    /// 案内の文字の色(テーマが変わったら親が変える)
    static PLACEHOLDER: Cell<COLORREF> = const { Cell::new(COLORREF(0x0080_8080)) };
}

pub fn set_placeholder_color(color: tokens::Rgb) {
    PLACEHOLDER.with(|cell| cell.set(colorref(color)));
}

/// 欄ごとに持つもの(SetWindowSubclass の参照に入れ，WM_NCDESTROY で放す)
struct FieldData {
    placeholder: Vec<u16>,
    /// キーを記録しているときの案内．記録していなければ None
    recording: Option<Vec<u16>>,
}

/// 枠の無い欄を作る(見えない状態で作る．置くときに見せる)
pub fn create(parent: HWND, id: u16, placeholder: &str, font: &Font) -> Option<HWND> {
    // 親の窓の地が Mica(透明)でも GDI で描いた欄が透けないよう，自分の面を持つ窓(子の WS_EX_LAYERED．
    // Windows 8 からで，マニフェストの宣言が要る．build.rs)にして，不透明に重ねる
    let window = super::win32::create(
        WS_EX_LAYERED,
        w!("EDIT"),
        "",
        WS_CHILD | WS_TABSTOP | WINDOW_STYLE(ES_AUTOHSCROLL as u32),
        (0, 0, 0, 0),
        Some(parent),
        id,
    )?;
    // SAFETY: window はこのスレッドの窓
    let _ = unsafe { SetLayeredWindowAttributes(window, COLORREF(0), u8::MAX, LWA_ALPHA) };
    super::win32::set_font(window, font);
    let data = Box::new(FieldData {
        placeholder: placeholder.encode_utf16().collect(),
        recording: None,
    });
    // SAFETY: window はこのスレッドの窓．data は WM_NCDESTROY で Box に戻して放す
    unsafe {
        let _ = SetWindowSubclass(
            window,
            Some(procedure),
            SUBCLASS,
            Box::into_raw(data) as usize,
        );
    }
    Some(window)
}

/// 案内の文字を変える
pub fn set_placeholder(window: HWND, placeholder: &str) {
    with_data(window, |data| {
        data.placeholder = placeholder.encode_utf16().collect();
    });
    super::win32::invalidate(window);
}

/// 次に押したキーをキー設定の書き方(crate::keys::from_key)にして入れる(キー設定の「キーを記録」)．
/// 押すまでは prompt を案内に出す．修飾キーだけを押しているあいだは待つ
pub fn record_key(window: HWND, prompt: &str) {
    with_data(window, |data| {
        data.recording = Some(prompt.encode_utf16().collect());
    });
    super::win32::set_text(window, "");
    super::win32::focus(window);
    super::win32::invalidate(window);
}

fn with_data(window: HWND, f: impl FnOnce(&mut FieldData)) {
    use windows::Win32::UI::Shell::GetWindowSubclass;
    let mut pointer = 0usize;
    // SAFETY: この欄に付けた手続きの参照を読む．付けていなければ false が返る
    let found = unsafe { GetWindowSubclass(window, Some(procedure), SUBCLASS, Some(&mut pointer)) };
    if !found.as_bool() || pointer == 0 {
        return;
    }
    // SAFETY: pointer は create で Box::into_raw した FieldData．UI スレッドだけで使い，ここでは借りるだけ
    let data = unsafe { &mut *(pointer as *mut FieldData) };
    f(data);
}

/// 入力欄の地の塗り(WM_CTLCOLOREDIT で返す)．色を変えたら作り直す
pub struct Brush(HBRUSH);

impl Brush {
    pub fn new(color: tokens::Rgb) -> Self {
        // SAFETY: 色を渡して作るだけ
        Self(unsafe { CreateSolidBrush(colorref(color)) })
    }

    pub fn handle(&self) -> isize {
        self.0 .0 as isize
    }
}

impl Drop for Brush {
    fn drop(&mut self) {
        // SAFETY: new で作った塗り
        let _ = unsafe { DeleteObject(HGDIOBJ(self.0 .0)) };
    }
}

/// WM_CTLCOLOREDIT の DC に文字と地の色を付ける
pub fn color_field(hdc: usize, text: tokens::Rgb, background: tokens::Rgb) {
    use windows::Win32::Graphics::Gdi::{SetBkColor, HDC};
    let hdc = HDC(hdc as *mut _);
    // SAFETY: WM_CTLCOLOREDIT で受けた描いている途中の DC
    unsafe {
        SetTextColor(hdc, colorref(text));
        SetBkColor(hdc, colorref(background));
    }
}

fn notify_parent(window: HWND, message: u32, wparam: usize) {
    // SAFETY: このスレッドの窓の親に知らせを置くだけ
    unsafe {
        if let Ok(parent) = GetParent(window) {
            let _ = PostMessageW(
                Some(parent),
                message,
                WPARAM(wparam),
                LPARAM(window.0 as isize),
            );
        }
    }
}

fn pressed(key: u16) -> bool {
    // SAFETY: 引数は定数のキーの番号
    unsafe { GetKeyState(i32::from(key)) < 0 }
}

extern "system" fn procedure(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
    _id: usize,
    data: usize,
) -> LRESULT {
    let result = std::panic::catch_unwind(|| handle(window, message, wparam, lparam, data));
    match result {
        Ok(Some(result)) => result,
        // SAFETY: Windows が渡した窓と引数をそのまま既定の手続きに渡す
        _ => unsafe { DefSubclassProc(window, message, wparam, lparam) },
    }
}

fn handle(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
    data: usize,
) -> Option<LRESULT> {
    // SAFETY: data は create で Box::into_raw した FieldData(WM_NCDESTROY までは生きている)
    let field = unsafe { (data as *mut FieldData).as_mut() }?;
    match message {
        WM_KEYDOWN | WM_SYSKEYDOWN if field.recording.is_some() => {
            let vk = (wparam.0 & 0xffff) as u16;
            // 修飾キーを除いたそのキーの文字(記号のキーの文字を書くため)
            // SAFETY: キーの番号を渡して文字を引くだけ
            let character =
                char::from_u32(unsafe { MapVirtualKeyW(u32::from(vk), MAPVK_VK_TO_CHAR) } & 0xffff)
                    .filter(|character| *character != '\0');
            if let Some(notation) = crate::keys::from_key(
                vk,
                character,
                pressed(VK_CONTROL.0),
                pressed(VK_MENU.0),
                pressed(VK_SHIFT.0),
            ) {
                field.recording = None;
                super::win32::set_text(window, &crate::keys::display(&notation));
                notify_parent(window, WM_FIELD_RECORDED, 0);
            }
            Some(LRESULT(0))
        }
        // 記録しているあいだは文字を入れない
        WM_CHAR | WM_SYSCHAR if field.recording.is_some() => Some(LRESULT(0)),
        WM_KEYDOWN if wparam.0 == usize::from(VK_TAB.0) => {
            notify_parent(window, WM_FIELD_TAB, usize::from(pressed(VK_SHIFT.0)));
            Some(LRESULT(0))
        }
        WM_KEYDOWN if wparam.0 == usize::from(VK_RETURN.0) => {
            notify_parent(window, WM_FIELD_ENTER, 0);
            Some(LRESULT(0))
        }
        // Tab・Enter・Esc の文字は入れない(EDIT が鳴らす音も止める)
        WM_CHAR if matches!(wparam.0, 0x09 | 0x0D | 0x1B) => Some(LRESULT(0)),
        WM_KEYDOWN if wparam.0 == usize::from(VK_ESCAPE.0) => Some(LRESULT(0)),
        WM_SETFOCUS | WM_KILLFOCUS => {
            if message == WM_KILLFOCUS {
                field.recording = None;
            }
            notify_parent(window, WM_FIELD_FOCUS, usize::from(message == WM_SETFOCUS));
            None
        }
        WM_MOUSEWHEEL => {
            // 欄の上でもページを送る
            // SAFETY: このスレッドの窓の親にそのまま渡す
            unsafe {
                if let Ok(parent) = GetParent(window) {
                    SendMessageW(parent, message, Some(wparam), Some(lparam));
                }
            }
            Some(LRESULT(0))
        }
        WM_PAINT => {
            // SAFETY: このスレッドの窓．空でなければ既定の描き方に任せる
            if unsafe { GetWindowTextLengthW(window) } != 0 {
                return Some(unsafe { DefSubclassProc(window, message, wparam, lparam) });
            }
            // 空なら，既定の描き方(WM_PRINTCLIENT)と案内の文字を同じ描画の中で描く．
            // 欄は自分の面を持つ窓なので，描画を終えたあとに DC を借りて重ねた分は画面に出ない
            let text = field
                .recording
                .as_ref()
                .unwrap_or(&field.placeholder)
                .clone();
            let mut paint = PAINTSTRUCT::default();
            // SAFETY: BeginPaint と EndPaint を対にする．hdc は描画のあいだだけ使う
            unsafe {
                let hdc = BeginPaint(window, &mut paint);
                DefSubclassProc(
                    window,
                    WM_PRINTCLIENT,
                    WPARAM(hdc.0 as usize),
                    LPARAM((PRF_CLIENT | PRF_ERASEBKGND) as isize),
                );
                paint_placeholder(window, hdc, text);
                let _ = EndPaint(window, &paint);
            }
            Some(LRESULT(0))
        }
        WM_NCDESTROY => {
            // SAFETY: create で付けた手続きを外し，Box に戻して放す
            unsafe {
                let _ = RemoveWindowSubclass(window, Some(procedure), SUBCLASS);
                drop(Box::from_raw(data as *mut FieldData));
                Some(DefSubclassProc(window, message, wparam, lparam))
            }
        }
        _ => None,
    }
}

/// 空の欄に案内の文字を描く
fn paint_placeholder(window: HWND, hdc: HDC, mut text: Vec<u16>) {
    if text.is_empty() {
        return;
    }
    // SAFETY: hdc は描画のあいだの DC．書体は選んで戻す
    unsafe {
        let font = SendMessageW(window, WM_GETFONT, None, None).0;
        let old = SelectObject(hdc, HGDIOBJ(font as *mut _));
        SetBkMode(hdc, TRANSPARENT);
        SetTextColor(hdc, PLACEHOLDER.with(Cell::get));
        let mut rect = RECT::default();
        let _ = GetClientRect(window, &mut rect);
        // EDIT の文字の左の余白(EC_LEFTMARGIN の既定)に合わせる
        rect.left += 1;
        DrawTextW(
            hdc,
            &mut text,
            &mut rect,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX,
        );
        SelectObject(hdc, old);
    }
}
