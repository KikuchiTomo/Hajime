#![deny(unsafe_code)]

pub mod catalog;
pub mod demo;
pub mod dictionaries;
pub mod engine;
pub mod files;
pub mod keys;
pub mod layout;
pub mod list;
pub mod model;
pub mod notices;
pub mod options;
pub mod pages;
pub mod store;
pub mod strings;
pub mod sync;
pub mod themes;
pub mod ui;
pub mod usage;
pub mod wizard;

#[cfg(windows)]
pub mod app;
