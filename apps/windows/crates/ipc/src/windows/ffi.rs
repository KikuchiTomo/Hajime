#![allow(unsafe_code)]

use std::ffi::c_void;
use windows::core::PWSTR;
use windows::Win32::Foundation::{CloseHandle, LocalFree, HANDLE, HLOCAL};
use windows::Win32::Security::Authorization::ConvertSidToStringSidW;
use windows::Win32::Security::{GetTokenInformation, TokenUser, TOKEN_QUERY, TOKEN_USER};
use windows::Win32::System::RemoteDesktop::ProcessIdToSessionId;
use windows::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};

pub fn current_session_id() -> u32 {
    let mut session = 0u32;
    match unsafe { ProcessIdToSessionId(std::process::id(), &mut session) } {
        Ok(()) => session,
        Err(_) => 0,
    }
}

pub fn current_user_sid() -> windows::core::Result<String> {
    let mut token = HANDLE::default();
    unsafe { OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token)? };
    let result = user_sid_of(token);
    let _ = unsafe { CloseHandle(token) };
    result
}

fn user_sid_of(token: HANDLE) -> windows::core::Result<String> {
    let mut needed = 0u32;
    let _ = unsafe { GetTokenInformation(token, TokenUser, None, 0, &mut needed) };
    let words = (needed as usize)
        .div_ceil(std::mem::size_of::<u64>())
        .max(1);
    let mut buffer = vec![0u64; words];
    unsafe {
        GetTokenInformation(
            token,
            TokenUser,
            Some(buffer.as_mut_ptr().cast::<c_void>()),
            (buffer.len() * std::mem::size_of::<u64>()) as u32,
            &mut needed,
        )?
    };
    let user = unsafe { &*buffer.as_ptr().cast::<TOKEN_USER>() };
    let mut text = PWSTR::null();
    unsafe { ConvertSidToStringSidW(user.User.Sid, &mut text)? };
    let sid = unsafe { text.to_string() };
    let _ = unsafe { LocalFree(Some(HLOCAL(text.0.cast::<c_void>()))) };
    sid.map_err(|_| windows::core::Error::from(windows::Win32::Foundation::E_UNEXPECTED))
}

#[cfg(test)]
pub fn test_server(name: &str) -> windows::core::Result<std::fs::File> {
    use std::os::windows::io::FromRawHandle;
    use windows::Win32::Storage::FileSystem::PIPE_ACCESS_DUPLEX;
    use windows::Win32::System::Pipes::{
        ConnectNamedPipe, CreateNamedPipeW, PIPE_READMODE_BYTE, PIPE_TYPE_BYTE, PIPE_WAIT,
    };
    let name = windows::core::HSTRING::from(name);
    let handle = unsafe {
        CreateNamedPipeW(
            &name,
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
            1,
            65_536,
            65_536,
            0,
            None,
        )
    };
    if handle.is_invalid() {
        return Err(windows::core::Error::from_thread());
    }
    let _ = unsafe { ConnectNamedPipe(handle, None) };
    Ok(unsafe { std::fs::File::from_raw_handle(handle.0) })
}
