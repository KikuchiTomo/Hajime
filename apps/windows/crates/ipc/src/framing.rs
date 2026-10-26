#![forbid(unsafe_code)]
//! メッセージの区切り方．4 バイトの長さ(リトルエンディアン)のあとに，UTF-8 の JSON を置く
//! (docs/dev/adr/0010-ipc-message-format.md)．Swift の側は core/Sources/S90IPC/MessageFraming.swift

use crate::generated::MAXIMUM_MESSAGE_BYTES;
use serde::de::DeserializeOwned;
use serde::Serialize;
use std::io::{ErrorKind, Read, Write};

/// 長さを表すバイト数
pub const LENGTH_BYTES: usize = 4;

/// 読み書きの失敗．入力の中身を含めない(serde_json のエラーは値の一部を含むことがあるので持たない)
#[derive(Debug, thiserror::Error)]
pub enum FrameError {
    #[error("メッセージが上限より大きい({0} バイト)")]
    TooLarge(usize),
    #[error("メッセージの形が protocol/schema.json の定義と合わない")]
    Malformed,
    #[error("接続が閉じた")]
    Closed,
    #[error("読み書きに失敗した: {0}")]
    Io(#[from] std::io::Error),
}

/// メッセージを，長さを前に付けたバイト列にする
pub fn encode<T: Serialize>(message: &T) -> Result<Vec<u8>, FrameError> {
    let body = serde_json::to_vec(message).map_err(|_| FrameError::Malformed)?;
    if body.len() > MAXIMUM_MESSAGE_BYTES {
        return Err(FrameError::TooLarge(body.len()));
    }
    let length = u32::try_from(body.len()).map_err(|_| FrameError::TooLarge(body.len()))?;
    let mut frame = Vec::with_capacity(LENGTH_BYTES + body.len());
    frame.extend_from_slice(&length.to_le_bytes());
    frame.extend_from_slice(&body);
    Ok(frame)
}

/// 長さを除いた本体を読む
pub fn decode<T: DeserializeOwned>(body: &[u8]) -> Result<T, FrameError> {
    if body.len() > MAXIMUM_MESSAGE_BYTES {
        return Err(FrameError::TooLarge(body.len()));
    }
    serde_json::from_slice(body).map_err(|_| FrameError::Malformed)
}

/// メッセージを 1 つ書く．1 回の write_all で送り，途中で別のメッセージが割り込まないようにする
pub fn write_message<W: Write, T: Serialize>(
    writer: &mut W,
    message: &T,
) -> Result<(), FrameError> {
    let frame = encode(message)?;
    writer.write_all(&frame)?;
    writer.flush()?;
    Ok(())
}

/// メッセージを 1 つ読む．長さが上限を超えていたら，本体を読まずに断る
pub fn read_message<R: Read, T: DeserializeOwned>(reader: &mut R) -> Result<T, FrameError> {
    let mut length = [0u8; LENGTH_BYTES];
    match reader.read_exact(&mut length) {
        Ok(()) => {}
        Err(error) if error.kind() == ErrorKind::UnexpectedEof => return Err(FrameError::Closed),
        Err(error) => return Err(FrameError::Io(error)),
    }
    let length = u32::from_le_bytes(length) as usize;
    if length > MAXIMUM_MESSAGE_BYTES {
        return Err(FrameError::TooLarge(length));
    }
    let mut body = vec![0u8; length];
    reader.read_exact(&mut body)?;
    decode(&body)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::generated::*;
    use std::io::Cursor;

    fn key_request() -> Request {
        Request {
            id: 7,
            body: RequestBody::Key {
                session: 1,
                input: KeyInput {
                    key: Key::Character { text: "k".into() },
                    modifiers: Modifiers {
                        shift: false,
                        control: false,
                        alt: false,
                    },
                    key_label: Some("k".into()),
                    is_keypad: false,
                },
                context: FieldContext {
                    application_id: Some("notepad.exe".into()),
                    is_secure: false,
                    preceding_text: None,
                    caret: Some(Rect {
                        x: 10,
                        y: 20,
                        width: 1,
                        height: 18,
                    }),
                },
            },
        }
    }

    #[test]
    fn 書いたメッセージを読み戻せる() {
        let mut buffer = Vec::new();
        write_message(&mut buffer, &key_request()).unwrap();
        write_message(
            &mut buffer,
            &Request {
                id: 8,
                body: RequestBody::OpenSession,
            },
        )
        .unwrap();
        let mut reader = Cursor::new(buffer);
        assert_eq!(
            read_message::<_, Request>(&mut reader).unwrap(),
            key_request()
        );
        assert_eq!(
            read_message::<_, Request>(&mut reader).unwrap(),
            Request {
                id: 8,
                body: RequestBody::OpenSession
            }
        );
        assert!(matches!(
            read_message::<_, Request>(&mut reader),
            Err(FrameError::Closed)
        ));
    }

    #[test]
    fn 上限を超える長さは本体を読まずに断る() {
        let mut frame = ((MAXIMUM_MESSAGE_BYTES + 1) as u32).to_le_bytes().to_vec();
        frame.extend_from_slice(b"{}");
        let result = read_message::<_, Request>(&mut Cursor::new(frame));
        assert!(matches!(result, Err(FrameError::TooLarge(_))));
    }

    #[test]
    fn 定義に無い種類は断る() {
        let body = br#"{"id":1,"body":{"type":"runCommand"}}"#;
        assert!(matches!(
            decode::<Request>(body),
            Err(FrameError::Malformed)
        ));
    }

    #[test]
    fn ログに出すときは入力の中身を伏せる() {
        let text = format!("{:?}", key_request());
        assert!(!text.contains("notepad"));
        assert!(!text.contains("\"k\""));
        assert!(text.contains("<伏せた>"));
    }
}
