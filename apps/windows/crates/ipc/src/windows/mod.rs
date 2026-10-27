#![deny(unsafe_code)]

mod client;
mod ffi;

pub use crate::client::{EngineClient, Outcome, Pending};

pub fn pipe_name(role: &str) -> windows::core::Result<String> {
    Ok(format_pipe_name(
        &ffi::current_user_sid()?,
        ffi::current_session_id(),
        role,
    ))
}

pub(crate) fn format_pipe_name(sid: &str, session: u32, role: &str) -> String {
    format!(r"\\.\pipe\s90.tokyo-ime.{sid}.{session}.{role}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn パイプの名前は_swift_と同じ形() {
        assert_eq!(
            format_pipe_name("S-1-5-21-1", 2, "engine"),
            r"\\.\pipe\s90.tokyo-ime.S-1-5-21-1.2.engine"
        );
    }

    #[test]
    fn 今のユーザーの_sid_を読める() {
        let name = pipe_name("engine").unwrap();
        assert!(name.starts_with(r"\\.\pipe\s90.tokyo-ime.S-1-"));
    }
}
