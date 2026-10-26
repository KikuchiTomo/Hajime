//! 設定の画面のアプリ．エンジンへの接続と窓をここで組み立てる(composition root)

mod ffi;
mod page;
mod theme;
mod window;

use crate::catalog::Catalog;
use crate::engine::{Engine, EngineStore};
use ipc::windows::{pipe_name, EngineClient};
use ipc::{RequestBody, ResponseBody};
use std::time::Duration;

/// エンジンの応答を待つ時間．設定の画面は入力を止めないので，DLL より長く待つ
const TIMEOUT: Duration = Duration::from_secs(2);

/// 名前付きパイプでエンジンに頼む口
pub struct Pipe {
    client: EngineClient,
}

impl Engine for Pipe {
    fn request(&self, body: RequestBody) -> Option<ResponseBody> {
        self.client.send(body).wait(TIMEOUT)
    }
}

type Store = EngineStore<Pipe>;

fn connect() -> Option<Store> {
    let name = pipe_name("engine").ok()?;
    let client = EngineClient::start(name).ok()?;
    Some(EngineStore::new(Pipe { client }))
}

pub fn run() {
    ffi::set_dpi_aware();
    let Ok(catalog) = Catalog::load() else {
        return;
    };
    let Some(window) = window::open(catalog, connect) else {
        return;
    };
    ffi::run_message_loop(window);
}
