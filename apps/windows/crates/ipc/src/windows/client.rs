#![forbid(unsafe_code)]

use crate::framing::{read_message, write_message, FrameError};
use crate::{Request, RequestBody, Response, ResponseBody, PROTOCOL_VERSION};
use std::fs::{File, OpenOptions};
use std::os::windows::fs::OpenOptionsExt;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender, SyncSender, TryRecvError};
use std::time::Duration;

const SECURITY_IDENTIFICATION: u32 = 0x0001_0000;

struct Job {
    request: Request,
    reply: SyncSender<Response>,
}

pub struct EngineClient {
    jobs: Sender<Job>,
    next_id: AtomicU32,
}

pub struct Pending {
    receiver: Receiver<Response>,
}

pub enum Outcome {
    Reply(ResponseBody),
    TimedOut,
    Unavailable,
}

impl Pending {
    pub fn wait(&self, timeout: Duration) -> Option<ResponseBody> {
        match self.outcome(timeout) {
            Outcome::Reply(body) => Some(body),
            Outcome::TimedOut | Outcome::Unavailable => None,
        }
    }

    pub fn outcome(&self, timeout: Duration) -> Outcome {
        match self.receiver.recv_timeout(timeout) {
            Ok(response) => Outcome::Reply(response.body),
            Err(RecvTimeoutError::Timeout) => Outcome::TimedOut,
            Err(RecvTimeoutError::Disconnected) => Outcome::Unavailable,
        }
    }

    pub fn try_take(self) -> Result<Option<ResponseBody>, Self> {
        match self.receiver.try_recv() {
            Ok(response) => Ok(Some(response.body)),
            Err(TryRecvError::Disconnected) => Ok(None),
            Err(TryRecvError::Empty) => Err(self),
        }
    }
}

impl EngineClient {
    pub fn start(pipe_name: String) -> std::io::Result<Self> {
        let (jobs, receiver) = mpsc::channel::<Job>();
        std::thread::Builder::new()
            .name("s90-engine-client".into())
            .spawn(move || run(&pipe_name, receiver))?;
        Ok(Self {
            jobs,
            next_id: AtomicU32::new(1),
        })
    }

    pub fn send(&self, body: RequestBody) -> Pending {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (reply, receiver) = mpsc::sync_channel(1);
        let _ = self.jobs.send(Job {
            request: Request { id, body },
            reply,
        });
        Pending { receiver }
    }
}

fn run(pipe_name: &str, jobs: Receiver<Job>) {
    let mut connection: Option<File> = None;
    for job in jobs {
        if connection.is_none() {
            connection = connect(pipe_name).ok();
        }
        let Some(file) = connection.as_mut() else {
            continue;
        };
        match exchange(file, &job.request) {
            Ok(response) => {
                let _ = job.reply.send(response);
            }
            Err(_) => {
                connection = None;
            }
        }
    }
}

fn connect(pipe_name: &str) -> Result<File, FrameError> {
    let mut file = OpenOptions::new()
        .read(true)
        .write(true)
        .security_qos_flags(SECURITY_IDENTIFICATION)
        .open(pipe_name)?;
    let hello = Request {
        id: 0,
        body: RequestBody::Hello {
            protocol_version: PROTOCOL_VERSION,
        },
    };
    match exchange(&mut file, &hello)?.body {
        ResponseBody::Hello { protocol_version } if protocol_version == PROTOCOL_VERSION => {
            Ok(file)
        }
        _ => Err(FrameError::Malformed),
    }
}

fn exchange(file: &mut File, request: &Request) -> Result<Response, FrameError> {
    write_message(file, request)?;
    loop {
        let response: Response = read_message(file)?;
        if response.id == request.id {
            return Ok(response);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{FieldContext, InputMode, Key, KeyInput, Modifiers, SessionState};

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
