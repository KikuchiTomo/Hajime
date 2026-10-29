//! 設定の画面のアプリ．エンジンへの接続と窓をここで組み立てる(composition root)

mod actions;
mod ffi;
mod page;
mod paint;
mod theme;
mod window;
mod wizard;

use crate::catalog::{Catalog, Timing};
use crate::engine::{Engine, EngineStore};
use ipc::windows::{pipe_name, EngineClient};
use ipc::{RequestBody, ResponseBody};
use std::os::windows::process::CommandExt;
use std::process::{Command, Stdio};
use std::time::Duration;

/// 設定の画面と同じフォルダに置いたエンジン
const ENGINE_FILE: &str = "hajime-engine-host.exe";
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

/// 起動の引数．--measure <ファイル> で窓を出すまで・中身を出すまで・ページを開く・送る時間を測って書き，終える．
/// --theme light|dark で OS の設定によらず明暗を決め，--page <名前> で初めに開くページを決める(見本の撮影)
fn options(started: std::time::Instant) -> window::Options {
    let arguments: Vec<String> = std::env::args().collect();
    let value = |name: &str| {
        arguments
            .iter()
            .position(|argument| argument == name)
            .and_then(|index| arguments.get(index + 1))
    };
    window::Options {
        started,
        theme: value("--theme").and_then(|theme| match theme.as_str() {
            "light" => Some(window::ForcedTheme::Light),
            "dark" => Some(window::ForcedTheme::Dark),
            "contrast" => Some(window::ForcedTheme::Contrast),
            _ => None,
        }),
        measure: value("--measure").map(std::path::PathBuf::from),
        page: value("--page").and_then(|name| {
            crate::pages::Page::ALL
                .into_iter()
                .find(|page| format!("{page:?}").eq_ignore_ascii_case(name))
        }),
    }
}

/// 初期設定ウィザードを開く引数．--setup-if-needed は済んでいれば何もしない(ログオンのたびに起動する)
pub(crate) const SETUP: &str = "--setup";
const SETUP_IF_NEEDED: &str = "--setup-if-needed";

/// 同じ実行ファイルを arguments で起動する(ウィザードから設定の画面，設定の画面からウィザードを開く)
pub(crate) fn launch_settings(arguments: &[&str]) {
    if let Ok(exe) = std::env::current_exe() {
        let _ = Command::new(exe)
            .args(arguments)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
    }
}

/// ウィザードを開くか．--setup なら開き，--setup-if-needed なら済んでいないときだけ開く
enum Mode {
    Settings,
    Setup,
    /// 済んでいるので何もしない
    Nothing,
}

fn mode(arguments: &[String]) -> Mode {
    if arguments.iter().any(|argument| argument == SETUP) {
        Mode::Setup
    } else if arguments.iter().any(|argument| argument == SETUP_IF_NEEDED) {
        if ffi::setup_completed() {
            Mode::Nothing
        } else {
            Mode::Setup
        }
    } else {
        Mode::Settings
    }
}

/// --step <名前> で初めに開くウィザードのページを決め，--offline でエンジンにつながずに見本の値で開く(見本の撮影)
fn setup_options(started: std::time::Instant) -> wizard::Options {
    let window = options(started);
    let arguments: Vec<String> = std::env::args().collect();
    let step = arguments
        .iter()
        .position(|argument| argument == "--step")
        .and_then(|index| arguments.get(index + 1))
        .and_then(|name| {
            crate::wizard::Step::ALL
                .into_iter()
                .find(|step| format!("{step:?}").eq_ignore_ascii_case(name))
        });
    wizard::Options {
        started,
        theme: window.theme,
        step,
        offline: arguments.iter().any(|argument| argument == "--offline"),
    }
}

pub fn run() {
    let started = std::time::Instant::now();
    let arguments: Vec<String> = std::env::args().collect();
    let mode = mode(&arguments);
    if matches!(mode, Mode::Nothing) {
        return;
    }
    // エンジンの起動は窓を出すのを待たせない
    let _ = std::thread::Builder::new()
        .name("engine-start".into())
        .spawn(start_engine);
    ffi::set_dpi_aware();
    // ファイルを選ぶ窓(IFileDialog)は COM を使う
    ffi::initialize_com();
    let Ok(catalog) = Catalog::load() else {
        return;
    };
    let opened = match mode {
        Mode::Setup => wizard::open(catalog, connect, setup_options(started)).is_some(),
        _ => window::open(catalog, connect, options(started)).is_some(),
    };
    if !opened {
        return;
    }
    ffi::run_message_loop();
}
