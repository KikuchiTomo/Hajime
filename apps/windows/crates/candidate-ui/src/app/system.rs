//! OS の外観(ライト・ダーク・アクセントカラー・ハイコントラスト・アニメーション)を読む

use crate::theme::{accent_from_palette, SystemLook};
use windows::Win32::Foundation::ERROR_SUCCESS;
use windows::Win32::System::Registry::{
    RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_BINARY, RRF_RT_REG_DWORD,
};
use windows::Win32::UI::Accessibility::{HCF_HIGHCONTRASTON, HIGHCONTRASTW};
use windows::Win32::UI::WindowsAndMessaging::{
    SystemParametersInfoW, SPI_GETCLIENTAREAANIMATION, SPI_GETHIGHCONTRAST,
    SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS,
};
use windows_core::{w, BOOL, PCWSTR};

const PERSONALIZE: PCWSTR = w!("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize");
const ACCENT: PCWSTR = w!("Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Accent");
/// AccentPalette の長さ(4 バイトの色が 8 つ)
const ACCENT_PALETTE_BYTES: usize = 32;

/// 今の OS の外観．backdrop は，すりガラスの地を使えるかをウィンドウで確かめた結果
pub fn look(backdrop: bool) -> SystemLook {
    let dark = dword(PERSONALIZE, w!("AppsUseLightTheme")) == Some(0);
    SystemLook {
        dark,
        accent: accent_palette().and_then(|bytes| accent_from_palette(&bytes, dark)),
        increase_contrast: high_contrast(),
        backdrop,
    }
}

/// 「アニメーション効果」がオフなら true(macOS の「視差効果を減らす」に当たる)
pub fn reduce_motion() -> bool {
    let mut enabled = BOOL(1);
    // SAFETY: enabled は BOOL を書き込める領域
    let read = unsafe {
        SystemParametersInfoW(
            SPI_GETCLIENTAREAANIMATION,
            0,
            Some(&mut enabled as *mut BOOL as *mut _),
            SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
        )
    };
    read.is_ok() && !enabled.as_bool()
}

fn high_contrast() -> bool {
    let mut contrast = HIGHCONTRASTW {
        cbSize: std::mem::size_of::<HIGHCONTRASTW>() as u32,
        ..Default::default()
    };
    // SAFETY: contrast は cbSize を入れた HIGHCONTRASTW
    let read = unsafe {
        SystemParametersInfoW(
            SPI_GETHIGHCONTRAST,
            contrast.cbSize,
            Some(&mut contrast as *mut HIGHCONTRASTW as *mut _),
            SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
        )
    };
    read.is_ok() && contrast.dwFlags.0 & HCF_HIGHCONTRASTON.0 != 0
}

fn dword(key: PCWSTR, value: PCWSTR) -> Option<u32> {
    let mut data = 0u32;
    let mut size = std::mem::size_of::<u32>() as u32;
    // SAFETY: data は size バイトを書き込める領域
    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            key,
            value,
            RRF_RT_REG_DWORD,
            None,
            Some(&mut data as *mut u32 as *mut _),
            Some(&mut size),
        )
    };
    (status == ERROR_SUCCESS).then_some(data)
}

fn accent_palette() -> Option<[u8; ACCENT_PALETTE_BYTES]> {
    let mut data = [0u8; ACCENT_PALETTE_BYTES];
    let mut size = ACCENT_PALETTE_BYTES as u32;
    // SAFETY: data は size バイトを書き込める領域
    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            ACCENT,
            w!("AccentPalette"),
            RRF_RT_REG_BINARY,
            None,
            Some(data.as_mut_ptr() as *mut _),
            Some(&mut size),
        )
    };
    (status == ERROR_SUCCESS && size as usize == ACCENT_PALETTE_BYTES).then_some(data)
}
