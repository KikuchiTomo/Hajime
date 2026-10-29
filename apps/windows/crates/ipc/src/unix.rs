#![forbid(unsafe_code)]

//! Linux(と試しの macOS)で，Unix ドメインソケットでエンジンにつなぐ．
//! 場所は Swift の UnixSocketPath と同じ: `$XDG_RUNTIME_DIR/haji.men/<役>.sock`．
//! `XDG_RUNTIME_DIR` が無ければ一時フォルダの `haji.men-<uid>/<役>.sock`．
//! フォルダはエンジンが作る．手元側は，本人のフォルダでほかの人が読み書きできないことを確かめてからつなぐ(なりすましを防ぐ)

use crate::client::EngineClient;
use std::io::{Error, ErrorKind};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::net::UnixStream;
use std::path::{Path, PathBuf};

const DIRECTORY: &str = "haji.men";

impl EngineClient {
    /// Unix ドメインソケット(path)でエンジンにつなぐ手元側を作る．つなぐたびにフォルダの持ち主と権限を確かめる
    pub fn start_unix(path: PathBuf) -> std::io::Result<Self> {
        Self::start_with(move || connect(&path))
    }
}

/// 役(engine・candidate-window)のソケットの場所
pub fn socket_path(role: &str) -> std::io::Result<PathBuf> {
    let directory = match std::env::var("XDG_RUNTIME_DIR") {
        Ok(runtime) if runtime.starts_with('/') => Path::new(&runtime).join(DIRECTORY),
        _ => std::env::temp_dir().join(format!("{DIRECTORY}-{}", current_uid()?)),
    };
    Ok(directory.join(format!("{role}.sock")))
}

/// path のソケットにつなぐ．先にフォルダが本人のもので，ほかの人が読み書きできないことを確かめる
pub fn connect(path: &Path) -> std::io::Result<UnixStream> {
    let directory = path
        .parent()
        .ok_or_else(|| Error::from(ErrorKind::InvalidInput))?;
    check_private_directory(directory, current_uid()?)?;
    UnixStream::connect(path)
}

/// 本人のフォルダ(リンクでない)で，ほかの人が読み書きできないこと
fn check_private_directory(directory: &Path, uid: u32) -> std::io::Result<()> {
    let metadata = std::fs::symlink_metadata(directory)?;
    if !metadata.is_dir() || metadata.uid() != uid || metadata.permissions().mode() & 0o077 != 0 {
        return Err(Error::from(ErrorKind::PermissionDenied));
    }
    Ok(())
}

/// このプロセスのユーザーの番号．Linux は /proc/self の持ち主，ほかは一時フォルダに作ったファイルの持ち主で知る(libc に頼らない)
fn current_uid() -> std::io::Result<u32> {
    if let Ok(metadata) = std::fs::metadata("/proc/self") {
        return Ok(metadata.uid());
    }
    let probe = std::env::temp_dir().join(format!("haji.men-uid-{}", std::process::id()));
    let file = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .open(&probe)?;
    let uid = file.metadata()?.uid();
    drop(file);
    let _ = std::fs::remove_file(&probe);
    Ok(uid)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::framing::{read_message, write_message};
    use crate::{Request, RequestBody, Response, ResponseBody, PROTOCOL_VERSION};
    use std::os::unix::net::UnixListener;
    use std::time::Duration;

    fn private_directory() -> PathBuf {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|elapsed| elapsed.as_nanos())
            .unwrap_or(0);
        // ソケットの場所の長さには上限(104 バイトほど)があるので /tmp の下に短く作る
        let directory = PathBuf::from(format!(
            "/tmp/hajime.{}.{}",
            std::process::id(),
            nanos % 1_000_000
        ));
        std::fs::create_dir(&directory).unwrap();
        std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o700)).unwrap();
        directory
    }

    fn reply(stream: &mut UnixStream, id: u32, body: ResponseBody) {
        write_message(stream, &Response { id, body }).unwrap();
    }

    #[test]
    fn 挨拶してから要求を送り同じ番号の応答を受け取る() {
        let directory = private_directory();
        let path = directory.join("engine.sock");
        let listener = UnixListener::bind(&path).unwrap();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let hello: Request = read_message(&mut stream).unwrap();
            assert!(matches!(hello.body, RequestBody::Hello { .. }));
            reply(
                &mut stream,
                hello.id,
                ResponseBody::Hello {
                    protocol_version: PROTOCOL_VERSION,
                },
            );
            let request: Request = read_message(&mut stream).unwrap();
            reply(
                &mut stream,
                request.id.wrapping_add(100),
                ResponseBody::Done,
            );
            reply(&mut stream, request.id, ResponseBody::Done);
        });
        let client = EngineClient::start_unix(path).unwrap();
        let body = client
            .send(RequestBody::OpenSession)
            .wait(Duration::from_secs(5));
        assert!(matches!(body, Some(ResponseBody::Done)));
        server.join().unwrap();
        let _ = std::fs::remove_dir_all(directory);
    }

    #[test]
    fn ほかの人も読み書きできるフォルダのソケットにはつながない() {
        let directory = private_directory();
        std::fs::set_permissions(&directory, std::fs::Permissions::from_mode(0o777)).unwrap();
        let path = directory.join("engine.sock");
        let _listener = UnixListener::bind(&path).unwrap();
        let error = connect(&path).unwrap_err();
        assert_eq!(error.kind(), ErrorKind::PermissionDenied);
        let _ = std::fs::remove_dir_all(directory);
    }

    #[test]
    fn エンジンが動いていなければ時間切れを待たずに返す() {
        let directory = private_directory();
        let client = EngineClient::start_unix(directory.join("engine.sock")).unwrap();
        let started = std::time::Instant::now();
        assert!(client
            .send(RequestBody::OpenSession)
            .wait(Duration::from_secs(5))
            .is_none());
        assert!(started.elapsed() < Duration::from_secs(5));
        let _ = std::fs::remove_dir_all(directory);
    }

    #[test]
    fn 場所は_swift_と同じ形() {
        let path = socket_path("engine").unwrap();
        assert!(path.ends_with("engine.sock"));
        let parent = path
            .parent()
            .unwrap()
            .file_name()
            .unwrap()
            .to_string_lossy()
            .into_owned();
        assert!(parent == DIRECTORY || parent.starts_with(&format!("{DIRECTORY}-")));
    }

    /// 本物のエンジン(hajime-engine-host)とつないで確かめる．HAJIME_ENGINE_SOCKET にソケットの場所を入れて
    /// `cargo test -p ipc -- --ignored` で動かす(CI ではエンジンを動かさないので飛ばす)
    #[test]
    #[ignore]
    fn 本物のエンジンで打った読みを変換して確定する() {
        use crate::{EditOperation, FieldContext, Key, KeyInput, Modifiers};
        let path = PathBuf::from(std::env::var("HAJIME_ENGINE_SOCKET").unwrap());
        let client = EngineClient::start_unix(path).unwrap();
        let timeout = Duration::from_secs(10);
        let Some(ResponseBody::SessionOpened { session, .. }) =
            client.send(RequestBody::OpenSession).wait(timeout)
        else {
            panic!("セッションを開けない");
        };
        let context = FieldContext {
            application_id: Some("org.example.editor".into()),
            is_secure: false,
            preceding_text: None,
            caret: None,
        };
        let key = |key: Key| RequestBody::Key {
            session,
            input: KeyInput {
                key,
                modifiers: Modifiers {
                    shift: false,
                    control: false,
                    alt: false,
                },
                key_label: None,
                is_keypad: false,
            },
            context: context.clone(),
        };
        for character in "kyouhaiitenkidesu".chars().map(String::from) {
            client
                .send(key(Key::Character { text: character }))
                .wait(timeout)
                .unwrap();
        }
        client.send(key(Key::Space)).wait(timeout).unwrap();
        let Some(ResponseBody::Edit { operations, .. }) =
            client.send(key(Key::Enter)).wait(timeout)
        else {
            panic!("確定の応答にならない");
        };
        assert!(
            operations.contains(&EditOperation::Commit {
                text: "今日はいい天気です".into()
            }),
            "{:?}",
            operations
                .iter()
                .filter_map(|operation| match operation {
                    EditOperation::Commit { text } => Some(
                        ["きょうはいいてんきです", "今日はいい天気です", "今日"]
                            .map(|word| text.starts_with(word))
                    ),
                    _ => None,
                })
                .collect::<Vec<_>>()
        );
    }
}
