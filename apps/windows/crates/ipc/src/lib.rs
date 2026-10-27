#![deny(unsafe_code)]

pub mod client;
pub mod framing;
#[rustfmt::skip]
#[allow(clippy::all)]
mod generated;
#[cfg(unix)]
pub mod unix;
#[cfg(windows)]
pub mod windows;

pub use generated::*;

#[cfg(test)]
mod fixture_tests;
