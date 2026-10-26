//! タスクバーの入力モードの表示(「あ」「A」)と入力メニュー．TSF の言語バーの項目(GUID_LBI_INPUTMODE)として出す．
//! 左クリックで日本語と英数を切り替え，右クリックのメニューでライブ変換・設定を開くを選ぶ(macOS の入力メニューと同じ項目．crate::menu)

use super::guard::guard;
use super::ids::CLSID_TEXT_SERVICE;
use crate::menu::{self, Item};
use ipc::InputMode;
use std::cell::{Cell, RefCell};
use windows::Win32::Foundation::{COLORREF, POINT, RECT};
use windows::Win32::Graphics::Gdi::{
    CreateBitmap, CreateCompatibleDC, CreateDIBSection, CreateFontW, DeleteDC, DeleteObject,
    DrawTextW, SelectObject, SetBkMode, SetTextColor, BITMAPINFO, BITMAPINFOHEADER, BI_RGB,
    CLEARTYPE_QUALITY, CLIP_DEFAULT_PRECIS, DEFAULT_CHARSET, DIB_RGB_COLORS, DT_CENTER,
    DT_NOPREFIX, DT_SINGLELINE, DT_VCENTER, FF_DONTCARE, FW_NORMAL, HBITMAP, HGDIOBJ,
    OUT_DEFAULT_PRECIS, TRANSPARENT,
};
use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_DWORD};
use windows::Win32::UI::TextServices::{
    ITfLangBarItem, ITfLangBarItemButton, ITfLangBarItemButton_Impl, ITfLangBarItemSink,
    ITfLangBarItem_Impl, ITfMenu, ITfSource, ITfSource_Impl, TfLBIClick, GUID_LBI_INPUTMODE,
    TF_LANGBARITEMINFO, TF_LBI_CLK_LEFT, TF_LBI_ICON, TF_LBI_STYLE_BTN_BUTTON,
    TF_LBI_STYLE_SHOWNINTRAY, TF_LBI_TEXT, TF_LBI_TOOLTIP, TF_LBMENUF_CHECKED,
    TF_LBMENUF_SEPARATOR,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateIconIndirect, GetSystemMetrics, HICON, ICONINFO, SM_CXSMICON, SM_CYSMICON,
};
use windows_core::{implement, w, IUnknown, Interface, Ref, Result, BOOL, BSTR, GUID, PCWSTR};

/// 言語バーの項目に知らせてもらう相手(言語バー)の受け付け番号．相手は 1 つだけ
const SINK_COOKIE: u32 = 1;
const ICON_FONT: PCWSTR = w!("Yu Gothic UI");
/// 字の高さをアイコンの何割にするか
const ICON_TEXT_SCALE: f32 = 0.85;

/// 項目で選んだことを文字入力のサービスに頼む口
pub trait Actions {
    fn menu_settings(&self) -> Option<ipc::SettingsSnapshot>;
    fn run(&self, command: ipc::MenuCommand);
    /// 手書きの窓を開く(組み立て中の文字を確定してから)
    fn open_handwriting(&self);
    fn toggle_mode(&self);
}

#[implement(ITfLangBarItemButton, ITfLangBarItem, ITfSource)]
pub struct InputModeItem {
    sink: RefCell<Option<ITfLangBarItemSink>>,
    mode: Cell<Option<InputMode>>,
    actions: Box<dyn Actions>,
}

impl InputModeItem {
    pub fn new(actions: Box<dyn Actions>) -> Self {
        Self {
            sink: RefCell::new(None),
            mode: Cell::new(None),
            actions,
        }
    }

    /// モードが変わったら，タスクバーの字を描き直してもらう
    pub fn set_mode(&self, mode: Option<InputMode>) {
        if self.mode.replace(mode) == mode {
            return;
        }
        let sink = self.sink.borrow().clone();
        if let Some(sink) = sink {
            let _ = unsafe { sink.OnUpdate(TF_LBI_ICON | TF_LBI_TEXT | TF_LBI_TOOLTIP) };
        }
    }
}

impl ITfLangBarItem_Impl for InputModeItem_Impl {
    fn GetInfo(&self, pinfo: *mut TF_LANGBARITEMINFO) -> Result<()> {
        guard(|| {
            if pinfo.is_null() {
                return Err(windows::Win32::Foundation::E_INVALIDARG.into());
            }
            let mut info = TF_LANGBARITEMINFO {
                clsidService: CLSID_TEXT_SERVICE,
                guidItem: GUID_LBI_INPUTMODE,
                dwStyle: TF_LBI_STYLE_BTN_BUTTON | TF_LBI_STYLE_SHOWNINTRAY,
                ulSort: 0,
                szDescription: [0; 32],
            };
            for (slot, unit) in info
                .szDescription
                .iter_mut()
                .zip(menu::DESCRIPTION.encode_utf16().take(31))
            {
                *slot = unit;
            }
            // SAFETY: pinfo は呼び出し側が用意した TF_LANGBARITEMINFO を指す(null でないことは上で確かめた)
            unsafe { pinfo.write(info) };
            Ok(())
        })
    }

    fn GetStatus(&self) -> Result<u32> {
        Ok(0)
    }

    fn Show(&self, _fshow: BOOL) -> Result<()> {
        Ok(())
    }

    fn GetTooltipString(&self) -> Result<BSTR> {
        Ok(BSTR::from(menu::DESCRIPTION))
    }
}

impl ITfLangBarItemButton_Impl for InputModeItem_Impl {
    fn OnClick(&self, click: TfLBIClick, _pt: &POINT, _prcarea: *const RECT) -> Result<()> {
        guard(|| {
            if click == TF_LBI_CLK_LEFT {
                self.actions.toggle_mode();
            }
            Ok(())
        })
    }

    fn InitMenu(&self, pmenu: Ref<ITfMenu>) -> Result<()> {
        guard(|| {
            let target = pmenu.ok()?;
            let settings = self.actions.menu_settings();
            for item in menu::items(settings.as_ref()) {
                let (id, flags, label) = match item {
                    Item::Command { id, label, checked } => {
                        (id, if checked { TF_LBMENUF_CHECKED } else { 0 }, label)
                    }
                    Item::Separator => (0, TF_LBMENUF_SEPARATOR, ""),
                };
                let text: Vec<u16> = label.encode_utf16().collect();
                // SAFETY: text は呼び出しのあいだ生きている．子のメニューは受け取らない
                unsafe {
                    target.AddMenuItem(
                        id,
                        flags,
                        HBITMAP::default(),
                        HBITMAP::default(),
                        &text,
                        std::ptr::null_mut(),
                    )?;
                }
            }
            Ok(())
        })
    }

    fn OnMenuSelect(&self, wid: u32) -> Result<()> {
        guard(|| {
            match menu::selection(wid) {
                Some(menu::Selection::Command(command)) => self.actions.run(command),
                Some(menu::Selection::Handwriting) => self.actions.open_handwriting(),
                None => {}
            }
            Ok(())
        })
    }

    fn GetIcon(&self) -> Result<HICON> {
        guard(|| text_icon(menu::icon_text(self.mode.get())))
    }

    fn GetText(&self) -> Result<BSTR> {
        Ok(BSTR::from(menu::icon_text(self.mode.get())))
    }
}

impl ITfSource_Impl for InputModeItem_Impl {
    fn AdviseSink(&self, riid: *const GUID, punk: Ref<IUnknown>) -> Result<u32> {
        guard(|| {
            // SAFETY: riid は呼び出し側が渡す GUID を指す(null は断る)
            if riid.is_null() || unsafe { *riid } != ITfLangBarItemSink::IID {
                return Err(windows::Win32::System::Ole::CONNECT_E_CANNOTCONNECT.into());
            }
            if self.sink.borrow().is_some() {
                return Err(windows::Win32::System::Ole::CONNECT_E_ADVISELIMIT.into());
            }
            let sink: ITfLangBarItemSink = punk.ok()?.cast()?;
            *self.sink.borrow_mut() = Some(sink);
            Ok(SINK_COOKIE)
        })
    }

    fn UnadviseSink(&self, dwcookie: u32) -> Result<()> {
        guard(|| {
            if dwcookie != SINK_COOKIE || self.sink.borrow_mut().take().is_none() {
                return Err(windows::Win32::System::Ole::CONNECT_E_NOCONNECTION.into());
            }
            Ok(())
        })
    }
}

/// タスクバーの色(ライトかダークか)に合わせた字の色．読めなければダーク(白い字)にする
fn text_color() -> (u8, u8, u8) {
    let mut light = 0u32;
    let mut size = std::mem::size_of::<u32>() as u32;
    // SAFETY: light と size は呼び出しのあいだ生きている 4 バイトの値
    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            w!("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize"),
            w!("SystemUsesLightTheme"),
            RRF_RT_REG_DWORD,
            None,
            Some(&mut light as *mut u32 as *mut _),
            Some(&mut size),
        )
    };
    if status.is_ok() && light != 0 {
        (0, 0, 0)
    } else {
        (0xFF, 0xFF, 0xFF)
    }
}

/// 字 1 つを描いたアイコン．呼び出し側(言語バー)が消す
fn text_icon(text: &str) -> Result<HICON> {
    // SAFETY: GDI のオブジェクトはこの関数の中で作って消す．DIB の画素は width × height の 32 ビットで，
    // CreateDIBSection が返した bits を DeleteObject の前だけ読み書きする
    unsafe {
        let width = GetSystemMetrics(SM_CXSMICON).max(16);
        let height = GetSystemMetrics(SM_CYSMICON).max(16);
        let header = BITMAPINFOHEADER {
            biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
            biWidth: width,
            biHeight: -height,
            biPlanes: 1,
            biBitCount: 32,
            biCompression: BI_RGB.0,
            ..Default::default()
        };
        let info = BITMAPINFO {
            bmiHeader: header,
            ..Default::default()
        };
        let dc = CreateCompatibleDC(None);
        let mut bits = std::ptr::null_mut();
        let color = CreateDIBSection(Some(dc), &info, DIB_RGB_COLORS, &mut bits, None, 0)?;
        let mask = CreateBitmap(width, height, 1, 1, None);
        let font = CreateFontW(
            -((height as f32 * ICON_TEXT_SCALE) as i32),
            0,
            0,
            0,
            FW_NORMAL.0 as i32,
            0,
            0,
            0,
            DEFAULT_CHARSET,
            OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS,
            CLEARTYPE_QUALITY,
            FF_DONTCARE.0 as u32,
            ICON_FONT,
        );
        let old_bitmap = SelectObject(dc, HGDIOBJ(color.0));
        let old_font = SelectObject(dc, HGDIOBJ(font.0));
        // 黒の地に白で描き，明るさを不透明度にして，字の色で塗り直す
        SetBkMode(dc, TRANSPARENT);
        SetTextColor(dc, COLORREF(0x00FF_FFFF));
        let mut rect = RECT {
            left: 0,
            top: 0,
            right: width,
            bottom: height,
        };
        let mut wide: Vec<u16> = text.encode_utf16().collect();
        DrawTextW(
            dc,
            &mut wide,
            &mut rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX,
        );
        let (red, green, blue) = text_color();
        if !bits.is_null() {
            let pixels =
                std::slice::from_raw_parts_mut(bits as *mut u32, (width * height) as usize);
            for pixel in pixels.iter_mut() {
                let coverage = ((*pixel >> 16) & 0xFF)
                    .max((*pixel >> 8) & 0xFF)
                    .max(*pixel & 0xFF);
                *pixel = (coverage << 24)
                    | (u32::from(red) << 16)
                    | (u32::from(green) << 8)
                    | u32::from(blue);
            }
        }
        SelectObject(dc, old_font);
        SelectObject(dc, old_bitmap);
        let icon = CreateIconIndirect(&ICONINFO {
            fIcon: true.into(),
            xHotspot: 0,
            yHotspot: 0,
            hbmMask: mask,
            hbmColor: color,
        });
        let _ = DeleteObject(HGDIOBJ(font.0));
        let _ = DeleteObject(HGDIOBJ(color.0));
        let _ = DeleteObject(HGDIOBJ(mask.0));
        let _ = DeleteDC(dc);
        icon
    }
}

/// 項目を作って言語バーに載せる
pub fn add(
    thread_mgr: &windows::Win32::UI::TextServices::ITfThreadMgr,
    item: &ITfLangBarItem,
) -> Result<()> {
    let manager: windows::Win32::UI::TextServices::ITfLangBarItemMgr = thread_mgr.cast()?;
    // SAFETY: item は生きている COM のオブジェクト
    unsafe { manager.AddItem(item) }
}

pub fn remove(thread_mgr: &windows::Win32::UI::TextServices::ITfThreadMgr, item: &ITfLangBarItem) {
    if let Ok(manager) = thread_mgr.cast::<windows::Win32::UI::TextServices::ITfLangBarItemMgr>() {
        // SAFETY: item は add で載せたもの
        let _ = unsafe { manager.RemoveItem(item) };
    }
}
