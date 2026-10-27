#![allow(unsafe_code)]

//! OS の呼び出し．unsafe はこのモジュールの中だけに置き，ほかのモジュールは安全な関数として使う

pub mod d2d;
pub mod edit;
pub mod uia;
mod win32;

pub use win32::*;
