#![allow(unsafe_code)]

mod display_attribute;
mod edit_session;
mod exports;
mod factory;
mod guard;
mod ids;
mod keyboard;
mod langbar;
mod launch;
mod phonetic;
mod registration;
mod text_service;
mod timer;
mod user_profile;

pub use user_profile::add_to_user_input_methods;
