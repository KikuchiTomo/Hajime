#![deny(unsafe_code)]

pub mod filter;
pub mod icon;
pub mod key;
pub mod late;
pub mod layout;
pub mod menu;
pub mod plan;

#[cfg(windows)]
mod com;

#[cfg(windows)]
pub use com::add_to_user_input_methods;
