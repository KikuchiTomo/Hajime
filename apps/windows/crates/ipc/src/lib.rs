#![deny(unsafe_code)]

pub mod framing;
#[rustfmt::skip]
#[allow(clippy::all)]
mod generated;
#[cfg(windows)]
pub mod windows;

pub use generated::*;

#[cfg(test)]
mod fixture_tests;
