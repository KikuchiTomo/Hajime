use super::ids::{CLSID_TEXT_SERVICE, GUID_PROFILE, LANGID_JAPANESE};
use windows::Win32::System::LibraryLoader::{
    GetProcAddress, LoadLibraryExW, LOAD_LIBRARY_SEARCH_SYSTEM32,
};
use windows_core::{s, w, BOOL, PCWSTR};

/// input.dll の InstallLayoutOrTip(windows クレートに無いので，実行時に引く)
type InstallLayoutOrTip = unsafe extern "system" fn(PCWSTR, u32) -> BOOL;

/// この利用者の入力方式(設定 > 時刻と言語 > 言語と地域 の日本語のキーボード)に Hajime を加える．
/// RegisterProfile だけでは入力の切り替え(Win+Space)には出ても，利用者の一覧に入らず，
/// 既定の入力方式の上書きの一覧に出ない(Microsoft の IME の要件)．利用者として動くプロセスから呼ぶ
pub fn add_to_user_input_methods() -> bool {
    let profile = format!("{LANGID_JAPANESE:04x}:{{{CLSID_TEXT_SERVICE:?}}}{{{GUID_PROFILE:?}}}");
    let profile: Vec<u16> = profile.encode_utf16().chain(std::iter::once(0)).collect();
    // SAFETY: input.dll は System32 からだけ読む．引いた関数は文書どおりの形(LPCWSTR, DWORD) -> BOOL で，
    // profile は呼び出しのあいだ有効な NUL で終わる文字列
    unsafe {
        let Ok(module) = LoadLibraryExW(w!("input.dll"), None, LOAD_LIBRARY_SEARCH_SYSTEM32) else {
            return false;
        };
        let Some(function) = GetProcAddress(module, s!("InstallLayoutOrTip")) else {
            return false;
        };
        let install: InstallLayoutOrTip = std::mem::transmute(function);
        install(PCWSTR(profile.as_ptr()), 0).as_bool()
    }
}
