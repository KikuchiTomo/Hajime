//! TSF の DLL・候補ウィンドウと s90-engine-host のあいだのメッセージ．
//!
//! 型は protocol/schema.json から tools/protocol/generate.py が作る(generated.rs)．手で二重に書かない．
//! 区切り方は framing．設計は docs/dev/adr/0003-windows-out-of-process-engine.md と 0010-ipc-message-format.md
#![forbid(unsafe_code)]

pub mod framing;
#[rustfmt::skip]
#[allow(clippy::all)]
mod generated;

pub use generated::*;

#[cfg(test)]
mod fixture_tests;
