use super::ids::{CLSID_TEXT_SERVICE, GUID_PROFILE, LANGID_JAPANESE, SERVICE_NAME};
use windows::Win32::Foundation::{ERROR_FILE_NOT_FOUND, HMODULE};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_INPROC_SERVER};
use windows::Win32::System::Com::{CoInitializeEx, CoUninitialize, COINIT_APARTMENTTHREADED};
use windows::Win32::System::LibraryLoader::{GetModuleFileNameW, GetModuleHandleExW};
use windows::Win32::System::Registry::{
    RegCloseKey, RegCreateKeyExW, RegDeleteTreeW, RegGetValueW, RegSetValueExW, HKEY,
    HKEY_CLASSES_ROOT, HKEY_CURRENT_USER, KEY_WRITE, REG_OPTION_NON_VOLATILE, REG_SZ,
    RRF_RT_REG_SZ,
};
use windows::Win32::UI::Input::KeyboardAndMouse::HKL;
use windows::Win32::UI::TextServices::TF_PROFILETYPE_INPUTPROCESSOR;
use windows::Win32::UI::TextServices::{
    CLSID_TF_CategoryMgr, CLSID_TF_InputProcessorProfiles, ITfCategoryMgr,
    ITfInputProcessorProfileMgr, GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
    GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT, GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
    GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT, GUID_TFCAT_TIP_KEYBOARD,
};
use windows_core::{Result, GUID, HSTRING, PCWSTR};

const CATEGORIES: [GUID; 5] = [
    GUID_TFCAT_TIP_KEYBOARD,
    GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
    GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
    GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
    GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
];

const FROM_ADDRESS: u32 = 0x4;
const UNCHANGED_REFCOUNT: u32 = 0x2;

pub fn register() -> Result<()> {
    let path = module_path()?;
    register_class(&path)?;
    let profiles: ITfInputProcessorProfileMgr =
        unsafe { CoCreateInstance(&CLSID_TF_InputProcessorProfiles, None, CLSCTX_INPROC_SERVER)? };
    let name: Vec<u16> = SERVICE_NAME.encode_utf16().collect();
    let icon: Vec<u16> = path.encode_utf16().collect();
    unsafe {
        profiles.RegisterProfile(
            &CLSID_TEXT_SERVICE,
            LANGID_JAPANESE,
            &GUID_PROFILE,
            &name,
            &icon,
            0,
            HKL::default(),
            0,
            true,
            0,
        )?
    };
    let categories: ITfCategoryMgr =
        unsafe { CoCreateInstance(&CLSID_TF_CategoryMgr, None, CLSCTX_INPROC_SERVER)? };
    for category in &CATEGORIES {
        unsafe { categories.RegisterCategory(&CLSID_TEXT_SERVICE, category, &CLSID_TEXT_SERVICE)? };
    }
    Ok(())
}

/// 日本語の既定の入力方式(HKCU の CTF\Assemblies\0x00000411 の Default)が Hajime IME なら，このセッションの入力方式を
/// Hajime IME に戻す．上書きで入れ直すあいだに登録が一度外れると，Windows がほかの入力方式に替え，入れ終わっても戻さないため．
/// 利用者がほかの入力方式を既定にしているときは何もしない
pub fn restore_profile() -> Result<()> {
    if !is_default_profile() {
        return Ok(());
    }
    // SAFETY: このスレッドで COM を使う．終わったら下で CoUninitialize する
    let initialized = unsafe { CoInitializeEx(None, COINIT_APARTMENTTHREADED) }.is_ok();
    let result = (|| {
        let profiles: ITfInputProcessorProfileMgr = unsafe {
            CoCreateInstance(&CLSID_TF_InputProcessorProfiles, None, CLSCTX_INPROC_SERVER)?
        };
        // SAFETY: GUID はこの呼び出しのあいだ生きている
        unsafe {
            profiles.ActivateProfile(
                TF_PROFILETYPE_INPUTPROCESSOR,
                LANGID_JAPANESE,
                &CLSID_TEXT_SERVICE,
                &GUID_PROFILE,
                HKL::default(),
                TF_IPPMF_FORSESSION,
            )
        }
    })();
    if initialized {
        // SAFETY: 上の CoInitializeEx に対になる呼び出し
        unsafe { CoUninitialize() };
    }
    result
}

/// このセッションのすべてのアプリに入力方式を替える(TF_IPPMF_FORSESSION)
const TF_IPPMF_FORSESSION: u32 = 0x2000_0000;

/// 日本語の既定の入力方式が Hajime IME か
fn is_default_profile() -> bool {
    let mut buffer = [0u16; 64];
    let mut size = std::mem::size_of_val(&buffer) as u32;
    // SAFETY: buffer と size は呼び出しのあいだ生きている．size は buffer のバイト数
    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            windows_core::w!("Software\\Microsoft\\CTF\\Assemblies\\0x00000411\\{34745C63-B2F0-4784-8B67-5E12C8701A31}"),
            windows_core::w!("Default"),
            RRF_RT_REG_SZ,
            None,
            Some(buffer.as_mut_ptr().cast()),
            Some(&mut size),
        )
    };
    if status.is_err() {
        return false;
    }
    let length = buffer
        .iter()
        .position(|unit| *unit == 0)
        .unwrap_or(buffer.len());
    let value = String::from_utf16_lossy(&buffer[..length]);
    is_text_service(&value)
}

/// レジストリに書かれた CLSID の文字列(中かっこ付き)が Hajime IME のものか
fn is_text_service(value: &str) -> bool {
    let trimmed = value.trim().trim_start_matches('{').trim_end_matches('}');
    trimmed.eq_ignore_ascii_case(&format!("{CLSID_TEXT_SERVICE:?}"))
}

pub fn unregister() -> Result<()> {
    let mut last = Ok(());
    match unsafe {
        CoCreateInstance::<_, ITfCategoryMgr>(&CLSID_TF_CategoryMgr, None, CLSCTX_INPROC_SERVER)
    } {
        Ok(categories) => {
            for category in &CATEGORIES {
                if let Err(error) = unsafe {
                    categories.UnregisterCategory(
                        &CLSID_TEXT_SERVICE,
                        category,
                        &CLSID_TEXT_SERVICE,
                    )
                } {
                    last = Err(error);
                }
            }
        }
        Err(error) => last = Err(error),
    }
    match unsafe {
        CoCreateInstance::<_, ITfInputProcessorProfileMgr>(
            &CLSID_TF_InputProcessorProfiles,
            None,
            CLSCTX_INPROC_SERVER,
        )
    } {
        Ok(profiles) => {
            if let Err(error) = unsafe {
                profiles.UnregisterProfile(&CLSID_TEXT_SERVICE, LANGID_JAPANESE, &GUID_PROFILE, 0)
            } {
                last = Err(error);
            }
        }
        Err(error) => last = Err(error),
    }
    let key = HSTRING::from(class_key());
    let deleted = unsafe { RegDeleteTreeW(HKEY_CLASSES_ROOT, &key) };
    if deleted != ERROR_FILE_NOT_FOUND {
        if let Err(error) = deleted.ok() {
            last = Err(error);
        }
    }
    last
}

fn class_key() -> String {
    format!("CLSID\\{{{CLSID_TEXT_SERVICE:?}}}")
}

fn register_class(path: &str) -> Result<()> {
    let class = create_key(&class_key())?;
    let result = set_string(class, None, SERVICE_NAME);
    close(class);
    result?;
    let server = create_key(&format!("{}\\InprocServer32", class_key()))?;
    let result = set_string(server, None, path)
        .and_then(|()| set_string(server, Some("ThreadingModel"), "Apartment"));
    close(server);
    result
}

fn create_key(path: &str) -> Result<HKEY> {
    let path = HSTRING::from(path);
    let mut key = HKEY::default();
    unsafe {
        RegCreateKeyExW(
            HKEY_CLASSES_ROOT,
            &path,
            None,
            PCWSTR::null(),
            REG_OPTION_NON_VOLATILE,
            KEY_WRITE,
            None,
            &mut key,
            None,
        )
        .ok()?
    };
    Ok(key)
}

fn set_string(key: HKEY, name: Option<&str>, value: &str) -> Result<()> {
    let name = name.map(HSTRING::from);
    let bytes: Vec<u8> = value
        .encode_utf16()
        .chain(std::iter::once(0))
        .flat_map(u16::to_le_bytes)
        .collect();
    let name = name
        .as_ref()
        .map_or(PCWSTR::null(), |name| PCWSTR(name.as_ptr()));
    unsafe { RegSetValueExW(key, name, None, REG_SZ, Some(&bytes)).ok() }
}

fn close(key: HKEY) {
    let _ = unsafe { RegCloseKey(key) };
}

pub(super) fn module_path() -> Result<String> {
    let mut module = HMODULE::default();
    let address = module_path as *const () as *const u16;
    unsafe {
        GetModuleHandleExW(
            FROM_ADDRESS | UNCHANGED_REFCOUNT,
            PCWSTR(address),
            &mut module,
        )?
    };
    let mut buffer = vec![0u16; 32_768];
    let length = unsafe { GetModuleFileNameW(Some(module), &mut buffer) } as usize;
    if length == 0 || length >= buffer.len() {
        return Err(windows_core::Error::from_thread());
    }
    Ok(String::from_utf16_lossy(&buffer[..length]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 既定の入力方式が_hajime_ime_かを中かっこと大文字小文字によらず見分ける() {
        assert!(is_text_service("{EB1C48DA-A029-48BC-8F14-9AB36D3F1FBC}"));
        assert!(is_text_service("{eb1c48da-a029-48bc-8f14-9ab36d3f1fbc}"));
        assert!(!is_text_service("{03B5835F-F03C-411B-9CE2-AA23E1171E36}"));
        assert!(!is_text_service(""));
    }
}
