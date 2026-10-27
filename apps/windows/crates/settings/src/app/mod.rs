//! 設定の画面のアプリ．エンジンへの接続と窓をここで組み立てる(composition root)

mod ffi;
mod page;
mod theme;
mod window;

use crate::catalog::{Catalog, Timing};
use crate::engine::{Engine, EngineStore};
use ipc::windows::{pipe_name, EngineClient};
use ipc::{RequestBody, ResponseBody};
use std::os::windows::process::CommandExt;
use std::process::{Command, Stdio};
use std::time::Duration;

/// 設定の画面と同じフォルダに置いたエンジン
const ENGINE_FILE: &str = "s90-engine-host.exe";
/// エンジンはコンソールのアプリなので，窓を出さずに起動する
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// 名前付きパイプでエンジンに頼む口
pub struct Pipe {
    client: EngineClient,
    /// 応答を待つ時間(DefaultSettings.settingsAppResponseTimeout)
    timeout: Duration,
    /// ファイルの読み書きを待つ時間(DefaultSettings.settingsAppFileTimeout)
    file_timeout: Duration,
}

impl Engine for Pipe {
    fn request(&self, body: RequestBody) -> Option<ResponseBody> {
        self.client.send(body).wait(self.timeout)
    }

    fn request_file(&self, body: RequestBody) -> Option<ResponseBody> {
        self.client.send(body).wait(self.file_timeout)
    }
}

type Store = EngineStore<Pipe>;

fn connect(timing: &Timing) -> Option<Store> {
    let name = pipe_name("engine").ok()?;
    let client = EngineClient::start(name).ok()?;
    Some(EngineStore::new(Pipe {
        client,
        timeout: timing.response_timeout(),
        file_timeout: timing.file_timeout(),
    }))
}

/// エンジンが落ちていても設定の画面を開けば戻るよう，同じフォルダのエンジンを起動する．
/// すでに動いていれば，起動したほうはパイプを作れずにすぐ終わる．つながるまでは窓がつなぎ直す
fn start_engine() {
    let Some(engine) = std::env::current_exe()
        .ok()
        .and_then(|exe| Some(exe.parent()?.join(ENGINE_FILE)))
    else {
        return;
    };
    if engine.is_file() {
        let _ = Command::new(engine)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .creation_flags(CREATE_NO_WINDOW)
            .spawn();
    }
}

pub fn run() {
    start_engine();
    ffi::set_dpi_aware();
    // ファイルを選ぶ窓(IFileDialog)は COM を使う
    ffi::initialize_com();
    let Ok(catalog) = Catalog::load() else {
        return;
    };
    let Some(window) = window::open(catalog, connect) else {
        return;
    };
    ffi::run_message_loop(window);
}
