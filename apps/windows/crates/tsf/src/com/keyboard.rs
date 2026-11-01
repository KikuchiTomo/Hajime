use crate::key::{RawKey, VK_CONTROL, VK_MENU, VK_SHIFT};
use ipc::Modifiers;
use windows::Win32::Foundation::{LPARAM, WPARAM};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, GetKeyboardLayout, GetKeyboardState, ToUnicodeEx, HKL,
};

const VK_CAPITAL: usize = 0x14;
const VK_LSHIFT: usize = 0xA0;
const VK_RSHIFT: usize = 0xA1;
const VK_LCONTROL: usize = 0xA2;
const VK_RCONTROL: usize = 0xA3;
const VK_LMENU: usize = 0xA4;
const VK_RMENU: usize = 0xA5;
const TO_UNICODE_KEEP_STATE: u32 = 0x4;
const PRESSED: u8 = 0x80;
const LANGID_JAPANESE: usize = 0x0411;

pub fn read(wparam: WPARAM, lparam: LPARAM) -> Option<RawKey> {
    let vk = u16::try_from(wparam.0).ok()?;
    let scan = ((lparam.0 >> 16) & 0xff) as u32;
    // 拡張キー(E0 の付くキー．テンキーの / や矢印など)
    let extended = (lparam.0 >> 24) & 1 != 0;
    let mut state = [0u8; 256];
    unsafe { GetKeyboardState(&mut state).ok()? };
    // 修飾キーは今のキーボードの状態からも読む．Windows 11 のメモ帳など(XAML のアプリ)では，入力のスレッドから見た
    // キーの状態に Shift・Ctrl・Alt が入らず，Shift+← などが ← として届いていた
    for modifier in [
        VK_SHIFT as usize,
        VK_LSHIFT,
        VK_RSHIFT,
        VK_CONTROL as usize,
        VK_LCONTROL,
        VK_RCONTROL,
        VK_MENU as usize,
        VK_LMENU,
        VK_RMENU,
    ] {
        // SAFETY: 引数は仮想キーの番号だけ．上の位(負)が今押されていること
        if unsafe { GetAsyncKeyState(modifier as i32) } < 0 {
            state[modifier] |= PRESSED;
        }
    }
    let pressed = |vk: u16| state[vk as usize] & PRESSED != 0;
    let modifiers = Modifiers {
        shift: pressed(VK_SHIFT),
        control: pressed(VK_CONTROL),
        alt: pressed(VK_MENU),
    };
    let layout = unsafe { GetKeyboardLayout(0) };
    let japanese_layout = (layout.0 as usize & 0xffff) == LANGID_JAPANESE;

    let mut without_control = state;
    for index in [
        VK_CONTROL as usize,
        VK_LCONTROL,
        VK_RCONTROL,
        VK_MENU as usize,
        VK_LMENU,
        VK_RMENU,
    ] {
        without_control[index] = 0;
    }
    let text = character(vk, scan, &without_control, layout);
    let label = crate::key::jis_label(scan as u16, extended);
    Some(RawKey {
        vk,
        text,
        modifiers,
        japanese_layout,
        label,
        scan: scan as u16,
        caps_lock: state[VK_CAPITAL] & 1 != 0,
    })
}

fn character(vk: u16, scan: u32, state: &[u8; 256], layout: HKL) -> Option<char> {
    let mut buffer = [0u16; 8];
    let count = unsafe {
        ToUnicodeEx(
            u32::from(vk),
            scan,
            state,
            &mut buffer,
            TO_UNICODE_KEEP_STATE,
            Some(layout),
        )
    };
    let length = usize::try_from(count)
        .ok()
        .filter(|count| (1..=2).contains(count))?;
    let mut decoded = char::decode_utf16(buffer[..length].iter().copied());
    let first = decoded.next()?.ok()?;
    decoded.next().is_none().then_some(first)
}
