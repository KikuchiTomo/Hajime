//! インストール先の実行ファイルを起動する．エンジンに頼めないときに，設定の画面を直接開くために使う．
//! DLL は入力先のアプリに読み込まれているので，アプリのハンドルを引き継がせない

use super::registration::module_path;
use std::path::PathBuf;
use windows::Win32::Foundation::CloseHandle;
use windows::Win32::System::Threading::{
    CreateProcessW, CREATE_NEW_PROCESS_GROUP, PROCESS_INFORMATION, STARTUPINFOW,
};
use windows_core::{Result, HSTRING, PWSTR};

pub const SETTINGS_FILE: &str = "hajime-settings.exe";
/// 32 ビットの DLL を置くフォルダ(インストール先の下)
const X86_FOLDER: &str = "x86";

/// インストール先のフォルダ．32 ビットの DLL は x86\ にあるので 1 つ上にする
fn installation() -> Option<PathBuf> {
    let module = PathBuf::from(module_path().ok()?);
    let folder = module.parent()?;
    if folder
        .file_name()
        .is_some_and(|name| name.eq_ignore_ascii_case(X86_FOLDER))
    {
        folder.parent().map(PathBuf::from)
    } else {
        Some(folder.to_path_buf())
    }
}

/// インストール先の file を起動する
pub fn start(file: &str) -> Result<()> {
    start_with(file, "")
}

/// インストール先の file を引数 arguments で起動する
pub fn start_with(file: &str, arguments: &str) -> Result<()> {
    let folder = installation()
        .ok_or_else(|| windows_core::Error::from(windows::Win32::Foundation::E_FAIL))?;
    let path = folder.join(file);
    if !path.is_file() {
        return Err(windows::Win32::Foundation::E_FAIL.into());
    }
    let application = HSTRING::from(path.as_os_str());
    // 作業フォルダは入力先のアプリのものを引き継がず，インストール先にする
    let directory = HSTRING::from(folder.as_os_str());
    // CreateProcessW はコマンドラインを書き換えることがあるので，書き換えてよい領域を渡す
    let mut command_line: Vec<u16> = format!("\"{}\" {arguments}", path.display())
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect();
    let startup = STARTUPINFOW {
        cb: std::mem::size_of::<STARTUPINFOW>() as u32,
        ..Default::default()
    };
    let mut process = PROCESS_INFORMATION::default();
    // SAFETY: application・command_line・directory は呼び出しのあいだ生きている．ハンドルは引き継がせない．
    // 返ったプロセスとスレッドのハンドルは使わないのですぐ閉じる
    unsafe {
        CreateProcessW(
            &application,
            Some(PWSTR(command_line.as_mut_ptr())),
            None,
            None,
            false,
            CREATE_NEW_PROCESS_GROUP,
            None,
            &directory,
            &startup,
            &mut process,
        )?;
        let _ = CloseHandle(process.hThread);
        let _ = CloseHandle(process.hProcess);
    }
    Ok(())
}
