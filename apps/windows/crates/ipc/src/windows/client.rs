#![forbid(unsafe_code)]

use crate::client::EngineClient;
use std::fs::OpenOptions;
use std::os::windows::fs::OpenOptionsExt;

const SECURITY_IDENTIFICATION: u32 = 0x0001_0000;

impl EngineClient {
    /// 名前付きパイプでエンジンにつなぐ手元側を作る
    pub fn start(pipe_name: String) -> std::io::Result<Self> {
        Self::start_with(move || {
            OpenOptions::new()
                .read(true)
                .write(true)
                .security_qos_flags(SECURITY_IDENTIFICATION)
                .open(&pipe_name)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::framing::{read_message, write_message};
    use crate::{FieldContext, InputMode, Key, KeyInput, Modifiers, SessionState};
    use crate::{Request, RequestBody, Response, ResponseBody, PROTOCOL_VERSION};
    use std::time::Duration;

    fn unique_name() -> String {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|elapsed| elapsed.as_nanos())
            .unwrap_or(0);
        format!(
            r"\\.\pipe\s90.tokyo-ime.test.{}.{nanos}",
            std::process::id()
        )
    }

    fn key() -> RequestBody {
        RequestBody::Key {
            session: 1,
            input: KeyInput {
                key: Key::Space,
                modifiers: Modifiers {
                    shift: false,
                    control: false,
                    alt: false,
                },
                key_label: None,
                is_keypad: false,
            },
            context: FieldContext {
                application_id: None,
                is_secure: false,
                preceding_text: None,
                caret: None,
            },
        }
    }

    #[test]
    fn 挨拶してから要求を送り同じ番号の応答を受け取る() {
        let name = unique_name();
        let server_name = name.clone();
        let server = std::thread::spawn(move || {
            let mut pipe = super::super::ffi::test_server(&server_name).unwrap();
            let hello: Request = read_message(&mut pipe).unwrap();
            assert!(matches!(hello.body, RequestBody::Hello { .. }));
            let reply = ResponseBody::Hello {
                protocol_version: PROTOCOL_VERSION,
            };
            write_message(
                &mut pipe,
                &Response {
                    id: hello.id,
                    body: reply,
                },
            )
            .unwrap();
            let request: Request = read_message(&mut pipe).unwrap();
            let stale = Response {
                id: request.id.wrapping_add(100),
                body: ResponseBody::Done,
            };
            write_message(&mut pipe, &stale).unwrap();
            let state = SessionState {
                mode: InputMode::Japanese,
                is_composing: true,
                consumed_keys: vec![],
                wake_after_milliseconds: None,
                preceding_text_length: None,
                keyboard_layout: None,
            };
            let edit = ResponseBody::Edit {
                handled: true,
                operations: vec![],
                state,
            };
            write_message(
                &mut pipe,
                &Response {
                    id: request.id,
                    body: edit,
                },
            )
            .unwrap();
        });
        std::thread::sleep(Duration::from_millis(300));
        let client = EngineClient::start(name).unwrap();
        let body = client.send(key()).wait(Duration::from_secs(5));
        assert!(matches!(
            body,
            Some(ResponseBody::Edit { handled: true, .. })
        ));
        server.join().unwrap();
    }

    #[test]
    fn エンジンが動いていなければ時間切れを待たずに返す() {
        let client = EngineClient::start(unique_name()).unwrap();
        let started = std::time::Instant::now();
        assert!(client.send(key()).wait(Duration::from_secs(5)).is_none());
        assert!(started.elapsed() < Duration::from_secs(5));
    }
}
