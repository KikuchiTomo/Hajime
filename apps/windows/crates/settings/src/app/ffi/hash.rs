//! SHA-256(Windows の CNG)．ダウンロードした配布物が latest.json に書いた SHA-256 と同じかを確かめる

use windows::Win32::Security::Cryptography::{
    BCryptCreateHash, BCryptDestroyHash, BCryptFinishHash, BCryptHashData, BCRYPT_HASH_HANDLE,
    BCRYPT_SHA256_ALG_HANDLE,
};

pub struct Sha256 {
    handle: BCRYPT_HASH_HANDLE,
}

impl Sha256 {
    pub fn new() -> Option<Self> {
        let mut handle = BCRYPT_HASH_HANDLE::default();
        // SAFETY: SHA-256 の擬似ハンドル(Windows 10 から)を使う．ハッシュの作業領域は CNG に任せる(None)
        let status =
            unsafe { BCryptCreateHash(BCRYPT_SHA256_ALG_HANDLE, &mut handle, None, None, 0) };
        status.is_ok().then_some(Self { handle })
    }

    pub fn update(&mut self, data: &[u8]) -> bool {
        // SAFETY: handle は new で作った開いているハンドル．data は呼び出しのあいだ生きている
        unsafe { BCryptHashData(self.handle, data, 0) }.is_ok()
    }

    pub fn finish(self) -> Option<[u8; 32]> {
        let mut digest = [0u8; 32];
        // SAFETY: handle は開いているハンドルで，digest は SHA-256 の大きさ(32 バイト)
        let status = unsafe { BCryptFinishHash(self.handle, &mut digest, 0) };
        status.is_ok().then_some(digest)
    }
}

impl Drop for Sha256 {
    fn drop(&mut self) {
        // SAFETY: handle は new で作ったハンドルで，ほかでは壊さない(finish のあとも壊してよい)
        let _ = unsafe { BCryptDestroyHash(self.handle) };
    }
}
