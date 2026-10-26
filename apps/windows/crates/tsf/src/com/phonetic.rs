//! 確定済みの文字の読み(再変換)を，Windows の日本語の解析(IFELanguage．MSIME.Japan)で求める．
//! 読めなければ None(エンジンは読みが無ければ再変換しない)

use windows::Win32::System::Com::{CLSIDFromProgID, CoCreateInstance, CLSCTX_INPROC_SERVER};
use windows::Win32::UI::Input::Ime::IFELanguage;
use windows_core::{w, BSTR};

/// text の読み．IFELanguage を開いて読みを求め，閉じる
pub fn reading(text: &str) -> Option<String> {
    if text.is_empty() {
        return None;
    }
    // SAFETY: COM はこのスレッド(TSF のスレッド)で初期化済み．作ったオブジェクトはこの関数の中で開いて閉じる
    unsafe {
        let clsid = CLSIDFromProgID(w!("MSIME.Japan")).ok()?;
        let language: IFELanguage = CoCreateInstance(&clsid, None, CLSCTX_INPROC_SERVER).ok()?;
        language.Open().ok()?;
        let mut phonetic = BSTR::new();
        let result = language.GetPhonetic(&BSTR::from(text), 1, -1, &mut phonetic);
        let _ = language.Close();
        result.ok()?;
        let reading = phonetic.to_string();
        (!reading.is_empty()).then_some(reading)
    }
}
