#![forbid(unsafe_code)]

//! エンジン(s90-engine-host)への要求を 1 本のスレッドで順に送り，応答を待つ手元側．
//! つなぎ方(Windows の名前付きパイプ・Unix ドメインソケット)だけを OS ごとに差し替える

use crate::framing::{read_message, write_message, FrameError};
use crate::{Request, RequestBody, Response, ResponseBody, PROTOCOL_VERSION};
use std::io::{Read, Write};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender, SyncSender};
use std::time::Duration;

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
}

impl EngineClient {
    /// connect でつなぐ手元側を作る．つながらないとき・切れたときは，次の要求でつなぎ直す
    pub fn start_with<S, C>(connect: C) -> std::io::Result<Self>
    where
        S: Read + Write,
        C: FnMut() -> std::io::Result<S> + Send + 'static,
    {
        let (jobs, receiver) = mpsc::channel::<Job>();
        std::thread::Builder::new()
            .name("s90-engine-client".into())
            .spawn(move || run(connect, receiver))?;
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

fn run<S: Read + Write>(mut connect: impl FnMut() -> std::io::Result<S>, jobs: Receiver<Job>) {
    let mut connection: Option<S> = None;
    for job in jobs {
        if connection.is_none() {
            connection = connect().map_err(FrameError::from).and_then(greet).ok();
        }
        let Some(stream) = connection.as_mut() else {
            continue;
        };
        match exchange(stream, &job.request) {
            Ok(response) => {
                let _ = job.reply.send(response);
            }
            Err(_) => {
                connection = None;
            }
        }
    }
}

/// 挨拶して，通信の形のバージョンが同じエンジンかを確かめる
fn greet<S: Read + Write>(mut stream: S) -> Result<S, FrameError> {
    let hello = Request {
        id: 0,
        body: RequestBody::Hello {
            protocol_version: PROTOCOL_VERSION,
        },
    };
    match exchange(&mut stream, &hello)?.body {
        ResponseBody::Hello { protocol_version } if protocol_version == PROTOCOL_VERSION => {
            Ok(stream)
        }
        _ => Err(FrameError::Malformed),
    }
}

fn exchange<S: Read + Write>(stream: &mut S, request: &Request) -> Result<Response, FrameError> {
    write_message(stream, request)?;
    loop {
        let response: Response = read_message(stream)?;
        if response.id == request.id {
            return Ok(response);
        }
    }
}
