//! OS の外観(ライト・ダーク・アクセントカラー・ハイコントラスト・アニメーション)を読む

use crate::theme::{accent_from_palette, SystemLook};
use std::sync::atomic::{AtomicU64, Ordering};
use windows::Win32::Foundation::ERROR_SUCCESS;
use windows::Win32::System::Registry::{
    RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_BINARY, RRF_RT_REG_DWORD,
};
use windows::Win32::UI::Accessibility::{HCF_HIGHCONTRASTON, HIGHCONTRASTW};
use windows::Win32::UI::WindowsAndMessaging::{
    SystemParametersInfoW, SPI_GETCLIENTAREAANIMATION, SPI_GETHIGHCONTRAST, SPI_GETSCREENREADER,
    SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS,
};
use windows_core::{w, BOOL, PCWSTR};

const PERSONALIZE: PCWSTR = w!("Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize");
const ACCENT: PCWSTR = w!("Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\Accent");
/// AccentPalette の長さ(4 バイトの色が 8 つ)
const ACCENT_PALETTE_BYTES: usize = 32;

/// 読んだ OS の外観とアニメーション効果の設定を覚えておく．打つたびやアニメーションのコマごとにレジストリを読まないように．
/// OS が設定の変化を知らせたとき(WM_SETTINGCHANGE など)と，候補の窓を消したときに忘れ，次に要るときに読み直す
#[derive(Debug, Default)]
pub struct SystemCache {
    /// 読んだ値と，読んだときの設定の世代(settings_generation)
    read: Option<(SystemLook, bool, u64)>,
}

/// OS が設定の変化を知らせた回数．覚えた値は，読んだときからこれが進んでいたら読み直す
static GENERATION: AtomicU64 = AtomicU64::new(0);

/// OS が設定の変化を知らせた(窓の手続きが WM_SETTINGCHANGE などで呼ぶ)
pub fn settings_changed() {
    GENERATION.fetch_add(1, Ordering::Relaxed);
}

/// 今の設定の世代．変化を知らせるたびに進む
pub fn settings_generation() -> u64 {
    GENERATION.load(Ordering::Relaxed)
}

impl SystemCache {
    fn read(&mut self) -> (SystemLook, bool) {
        let generation = settings_generation();
        match self.read {
            Some((look, reduce, read)) if read == generation => (look, reduce),
            _ => {
                let read = (look(false), reduce_motion());
                self.read = Some((read.0, read.1, generation));
                read
            }
        }
    }

    /// look と同じ(覚えた値を返す)
    pub fn look(&mut self, backdrop: bool) -> SystemLook {
        SystemLook {
            backdrop,
            ..self.read().0
        }
    }

    /// reduce_motion と同じ(覚えた値を返す)
    pub fn reduce_motion(&mut self) -> bool {
        self.read().1
    }

    /// 覚えた値を忘れる．次に尋ねたときに OS から読み直す
    pub fn forget(&mut self) {
        self.read = None;
    }
}

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

/// ナレーターなどの読み上げのソフトが動いているか
pub fn screen_reader() -> bool {
    let mut running = BOOL(0);
    // SAFETY: running は BOOL を書き込める領域
    let read = unsafe {
        SystemParametersInfoW(
            SPI_GETSCREENREADER,
            0,
            Some(&mut running as *mut BOOL as *mut _),
            SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
        )
    };
    read.is_ok() && running.as_bool()
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
