use super::ids::{CLSID_TEXT_SERVICE, GUID_PROFILE, LANGID_JAPANESE, SERVICE_NAME};
use windows::Win32::Foundation::{ERROR_FILE_NOT_FOUND, HMODULE};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_INPROC_SERVER};
use windows::Win32::System::LibraryLoader::{GetModuleFileNameW, GetModuleHandleExW};
use windows::Win32::System::Registry::{
    RegCloseKey, RegCreateKeyExW, RegDeleteTreeW, RegSetValueExW, HKEY, HKEY_CLASSES_ROOT,
    KEY_WRITE, REG_OPTION_NON_VOLATILE, REG_SZ,
};
use windows::Win32::UI::Input::KeyboardAndMouse::HKL;
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

fn module_path() -> Result<String> {
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
