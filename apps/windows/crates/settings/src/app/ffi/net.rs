//! 更新の確認(R-19)の通信．WinHTTP で https の URL を GET するだけで，何も送らない(本文・Cookie・入力の中身を付けない)．
//! 利用者が「更新を確認」を押したときだけ呼ぶ(SECURITY-MODEL.md の通信)

use std::ffi::c_void;
use std::time::{Duration, Instant};
use windows::Win32::Networking::WinHttp::{
    WinHttpCloseHandle, WinHttpConnect, WinHttpOpen, WinHttpOpenRequest, WinHttpQueryHeaders,
    WinHttpReadData, WinHttpReceiveResponse, WinHttpSendRequest, WinHttpSetOption,
    WinHttpSetTimeouts, INTERNET_DEFAULT_HTTPS_PORT, WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
    WINHTTP_FLAG_REFRESH, WINHTTP_FLAG_SECURE, WINHTTP_OPTION_REDIRECT_POLICY,
    WINHTTP_OPTION_REDIRECT_POLICY_NEVER, WINHTTP_QUERY_CONTENT_LENGTH, WINHTTP_QUERY_FLAG_NUMBER,
    WINHTTP_QUERY_STATUS_CODE,
};
use windows_core::{HSTRING, PCWSTR};

/// 一度に読む大きさ
const CHUNK: usize = 64 * 1024;
const HTTP_OK: u32 = 200;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NetError {
    /// https://<ホスト>/<道筋> の形でない
    Url,
    /// つながらない・送れない・読めない(WinHTTP の誤り．時間切れを含む)
    Connection,
    /// 200 以外が返った
    Status(u32),
    /// 上限より大きい
    TooLarge,
    /// 全体の時間の上限を超えた
    TimedOut,
    /// 受け取った側がやめた(書き込めないなど)
    Stopped,
}

/// WinHTTP のハンドル．落とすときに閉じる
struct Handle(*mut c_void);

impl Handle {
    fn new(raw: *mut c_void) -> Result<Self, NetError> {
        if raw.is_null() {
            Err(NetError::Connection)
        } else {
            Ok(Self(raw))
        }
    }
}

impl Drop for Handle {
    fn drop(&mut self) {
        // SAFETY: self.0 は WinHTTP が返した開いているハンドルで，ほかでは閉じない
        let _ = unsafe { WinHttpCloseHandle(self.0) };
    }
}

/// url(https のみ)を GET し，届いた分を順に receive(届いた分，届いた合計，全体の大きさ)に渡す．
/// 1 回の待ち(名前の解決・接続・送信・受信)は operation で，全体は total で打ち切る．limit バイトを超えたらやめる．
/// 転送は受けない(配る場所の URL は転送しない)
pub fn get(
    url: &str,
    agent: &str,
    limit: u64,
    operation: Duration,
    total: Duration,
    mut receive: impl FnMut(&[u8], u64, Option<u64>) -> bool,
) -> Result<(), NetError> {
    let started = Instant::now();
    let (host, path) = crate::update::split_https(url).ok_or(NetError::Url)?;
    let milliseconds = i32::try_from(operation.as_millis()).unwrap_or(i32::MAX);
    let agent = HSTRING::from(agent);
    let host = HSTRING::from(host);
    let path = HSTRING::from(path);
    // SAFETY: 渡す文字列は呼び出しのあいだ生きている．返ったハンドルは Handle が閉じる
    unsafe {
        let session = Handle::new(WinHttpOpen(
            &agent,
            WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
            PCWSTR::null(),
            PCWSTR::null(),
            0,
        ))?;
        WinHttpSetTimeouts(
            session.0,
            milliseconds,
            milliseconds,
            milliseconds,
            milliseconds,
        )
        .map_err(|_| NetError::Connection)?;
        let connection = Handle::new(WinHttpConnect(
            session.0,
            &host,
            INTERNET_DEFAULT_HTTPS_PORT,
            0,
        ))?;
        let request = Handle::new(WinHttpOpenRequest(
            connection.0,
            &HSTRING::from("GET"),
            &path,
            PCWSTR::null(),
            PCWSTR::null(),
            std::ptr::null(),
            WINHTTP_FLAG_SECURE | WINHTTP_FLAG_REFRESH,
        ))?;
        let never = WINHTTP_OPTION_REDIRECT_POLICY_NEVER.to_ne_bytes();
        WinHttpSetOption(
            Some(request.0),
            WINHTTP_OPTION_REDIRECT_POLICY,
            Some(&never),
        )
        .map_err(|_| NetError::Connection)?;
        WinHttpSendRequest(request.0, None, None, 0, 0, 0).map_err(|_| NetError::Connection)?;
        WinHttpReceiveResponse(request.0, std::ptr::null_mut())
            .map_err(|_| NetError::Connection)?;
        let status = query_number(&request, WINHTTP_QUERY_STATUS_CODE).unwrap_or(0);
        if status != HTTP_OK {
            return Err(NetError::Status(status));
        }
        let length = query_number(&request, WINHTTP_QUERY_CONTENT_LENGTH).map(u64::from);
        if length.is_some_and(|length| length > limit) {
            return Err(NetError::TooLarge);
        }
        let mut buffer = vec![0u8; CHUNK];
        let mut received = 0u64;
        loop {
            if started.elapsed() > total {
                return Err(NetError::TimedOut);
            }
            let mut read = 0u32;
            WinHttpReadData(
                request.0,
                buffer.as_mut_ptr().cast(),
                CHUNK as u32,
                &mut read,
            )
            .map_err(|_| NetError::Connection)?;
            if read == 0 {
                return Ok(());
            }
            received += u64::from(read);
            if received > limit {
                return Err(NetError::TooLarge);
            }
            if !receive(&buffer[..read as usize], received, length) {
                return Err(NetError::Stopped);
            }
        }
    }
}

/// 数で返る見出し(状態の番号・本文の大きさ)を読む．無ければ None
fn query_number(request: &Handle, level: u32) -> Option<u32> {
    let mut value = 0u32;
    let mut size = std::mem::size_of::<u32>() as u32;
    // SAFETY: value は 4 バイトで，size にその大きさを渡す．request は開いているハンドル
    unsafe {
        WinHttpQueryHeaders(
            request.0,
            level | WINHTTP_QUERY_FLAG_NUMBER,
            PCWSTR::null(),
            Some((&mut value as *mut u32).cast()),
            &mut size,
            std::ptr::null_mut(),
        )
    }
    .ok()?;
    Some(value)
}
