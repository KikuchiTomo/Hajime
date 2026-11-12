//! 絵文字と記号のパレットの窓(R-26)．エンジンの showPalette で開き，押した対象をエンジンに送る．
//! 何を出すかはエンジン(core の PaletteSession)が決め，ここでは描くことと押した位置を対象にすることだけをする．
//! 寸法と押した位置(`layout`)と描く部品(`scene`．説明の欄の名前・読み・札の配置は `preview`)は描画から分けて試す．窓は `ffi` に置く

pub mod emoji;
pub mod layout;
pub mod preview;
pub mod sample;
pub mod scene;

#[cfg(windows)]
pub mod ffi;
