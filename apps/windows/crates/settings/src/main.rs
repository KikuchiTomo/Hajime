#![cfg_attr(windows, windows_subsystem = "windows")]
#![forbid(unsafe_code)]

fn main() {
    #[cfg(windows)]
    settings::app::run();
}
