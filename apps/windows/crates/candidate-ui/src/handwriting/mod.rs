//! 手書きで文字を探す窓(R-14)．エンジンの showHandwriting で開き，選んだ文字をエンジンに送る．
//! 線と候補の状態(`ink`)と寸法(`layout`)は描画から分けて試す．窓・描画・認識は `ffi` に置く

pub mod ink;
pub mod layout;
pub mod strings;

#[cfg(windows)]
pub mod ffi;
