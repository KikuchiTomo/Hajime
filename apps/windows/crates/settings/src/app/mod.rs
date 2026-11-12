//! 設定の画面のアプリ．エンジンへの接続と窓をここで組み立てる(composition root)

mod actions;
mod editor;
mod ffi;
mod page;
mod paint;
mod theme;
mod update;
mod window;
mod wizard;

use crate::catalog::{Catalog, Timing};
use crate::engine::{Engine, EngineStore};
use crate::sample::SampleEngine;
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

/// 設定の画面が頼む先．ふだんはエンジンのパイプ，--offline では見本のエンジン(書いた値は覚えるだけ)
pub enum Link {
    Pipe(Pipe),
    Sample(Box<SampleEngine>),
}

impl Engine for Link {
    fn request(&self, body: RequestBody) -> Option<ResponseBody> {
        match self {
            Link::Pipe(pipe) => pipe.request(body),
            Link::Sample(sample) => sample.request(body),
        }
    }

    fn request_file(&self, body: RequestBody) -> Option<ResponseBody> {
        match self {
            Link::Pipe(pipe) => pipe.request_file(body),
            Link::Sample(sample) => sample.request_file(body),
        }
    }
}

type Store = EngineStore<Link>;

fn connect(timing: &Timing) -> Option<Store> {
    let name = pipe_name("engine").ok()?;
    let client = EngineClient::start(name).ok()?;
    Some(EngineStore::new(Link::Pipe(Pipe {
        client,
        timeout: timing.response_timeout(),
        file_timeout: timing.file_timeout(),
    })))
}

/// エンジンにつながず，見本の値で開く(--offline．画面の確かめと見本の撮影)
fn connect_sample(_: &Timing) -> Option<Store> {
    Some(EngineStore::new(Link::Sample(Box::default())))
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
/// --theme light|dark で OS の設定によらず明暗を決め，--page <名前> で初めに開くページを決める(見本の撮影．
/// エンジンが入力メニューの「ユーザー辞書…」で --page dictionary を渡す)．
/// --offline ならエンジンにつながず，見本の値で開く．--register-word なら単語の登録の語と読みをエンジンから受け取る．
/// --check-for-updates なら情報のページで開き，情報のページの「更新を確認」を押したときと同じ確認を始める
fn options(started: std::time::Instant) -> window::Options {
    let arguments: Vec<String> = std::env::args().collect();
    parse_options(&arguments, started)
}

fn parse_options(arguments: &[String], started: std::time::Instant) -> window::Options {
    let value = |name: &str| {
        arguments
            .iter()
            .position(|argument| argument == name)
            .and_then(|index| arguments.get(index + 1))
    };
    let check_for_updates = arguments
        .iter()
        .any(|argument| argument == CHECK_FOR_UPDATES);
    let page = value("--page").and_then(|name| {
        crate::pages::Page::ALL
            .into_iter()
            .find(|page| format!("{page:?}").eq_ignore_ascii_case(name))
    });
    window::Options {
        started,
        theme: value("--theme").and_then(|theme| match theme.as_str() {
            "light" => Some(window::ForcedTheme::Light),
            "dark" => Some(window::ForcedTheme::Dark),
            "contrast" => Some(window::ForcedTheme::Contrast),
            _ => None,
        }),
        measure: value("--measure").map(std::path::PathBuf::from),
        offline: arguments.iter().any(|argument| argument == OFFLINE),
        register_word: arguments.iter().any(|argument| argument == REGISTER_WORD),
        // 「更新を確認」のボタンと進み具合はバージョンの行にあるので，ページを決めていなければ情報のページで開く
        page: page.or(check_for_updates.then_some(crate::pages::Page::About)),
        check_for_updates,
    }
}

/// 初期設定ウィザードを開く引数．--setup-if-needed は済んでいれば何もしない(ログオンのたびに起動する)
pub(crate) const SETUP: &str = "--setup";
const SETUP_IF_NEEDED: &str = "--setup-if-needed";
/// エンジンにつながずに見本の値で開く(開発用．画面の確かめと見本の撮影)
pub(crate) const OFFLINE: &str = "--offline";
/// 情報のページで開き，「更新を確認」を押したときと同じ確認を始める(入力メニューの「更新を確認」．
/// macOS の入力メニューと情報のページが同じ更新用のアプリを起動するのと同じく，両方を同じ流れにする)
pub const CHECK_FOR_UPDATES: &str = "--check-for-updates";
/// 単語の登録で開く(EngineService.settingsRegistrationArgument)．つながったら，エンジンが持っている語と読みを
/// ユーザー辞書の登録の欄に入れる．語と読みは入力内容なので引数では受け取らない
const REGISTER_WORD: &str = "--register-word";

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
        offline: arguments.iter().any(|argument| argument == OFFLINE),
    }
}

pub fn run() {
    let started = std::time::Instant::now();
    let arguments: Vec<String> = std::env::args().collect();
    // ログオンのたびの起動で，利用者の入力方式に Hajime IME を一度だけ加える(見本の値で開くときは加えない)
    if arguments.iter().any(|argument| argument == SETUP_IF_NEEDED)
        && !arguments.iter().any(|argument| argument == OFFLINE)
    {
        ffi::add_input_method_once();
    }
    let mode = mode(&arguments);
    if matches!(mode, Mode::Nothing) {
        return;
    }
    let offline = arguments.iter().any(|argument| argument == OFFLINE);
    // エンジンの起動は窓を出すのを待たせない(見本の値で開くときは起動しない)
    if !offline {
        let _ = std::thread::Builder::new()
            .name("engine-start".into())
            .spawn(start_engine);
    }
    ffi::set_dpi_aware();
    // ファイルを選ぶ窓(IFileDialog)は COM を使う
    ffi::initialize_com();
    let Ok(catalog) = Catalog::load() else {
        return;
    };
    let opened = match mode {
        Mode::Setup => wizard::open(catalog, connect, setup_options(started)).is_some(),
        _ => {
            let link = if offline { connect_sample } else { connect };
            window::open(catalog, link, options(started)).is_some()
        }
    };
    if !opened {
        return;
    }
    ffi::run_message_loop();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pages::Page;

    fn parse(arguments: &[&str]) -> window::Options {
        let arguments: Vec<String> = std::iter::once("hajime-settings.exe")
            .chain(arguments.iter().copied())
            .map(String::from)
            .collect();
        parse_options(&arguments, std::time::Instant::now())
    }

    #[test]
    fn 更新を確認の引数で情報のページを開いて確認を始める() {
        let options = parse(&[CHECK_FOR_UPDATES]);
        assert!(options.check_for_updates);
        assert_eq!(options.page, Some(Page::About));
        assert!(!options.offline);
        assert!(!options.register_word);
    }

    #[test]
    fn 引数が無ければ確認を始めない() {
        let options = parse(&[]);
        assert!(!options.check_for_updates);
        assert_eq!(options.page, None);
    }

    #[test]
    fn ページを決めていればそのページで開いて確認を始める() {
        let options = parse(&["--page", "dictionary", CHECK_FOR_UPDATES]);
        assert!(options.check_for_updates);
        assert_eq!(options.page, Some(Page::Dictionary));
    }

    #[test]
    fn 更新を確認の引数ではウィザードを開かない() {
        let arguments = vec![
            "hajime-settings.exe".to_string(),
            CHECK_FOR_UPDATES.to_string(),
        ];
        assert!(matches!(mode(&arguments), Mode::Settings));
    }

    #[test]
    fn 入力メニューと同じ引数を受け取る() {
        assert_eq!(CHECK_FOR_UPDATES, "--check-for-updates");
    }
}
