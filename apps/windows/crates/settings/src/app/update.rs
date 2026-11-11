//! 「更新を確認」(R-19)の流れ．利用者が押したときだけ通信する(SECURITY-MODEL.md の通信)．
//!
//! 1. 別のスレッドで latest.json を取り，今のバージョンより新しい配布物があるかを決める(crate::update)
//! 2. あれば確かめる窓で変更点を見せて尋ね，はいなら別のスレッドで MSI を %LOCALAPPDATA%\haji.men\IME\updates に取る
//! 3. latest.json の SHA-256 と同じなら msiexec で入れる(/passive /norestart．UAC は msiexec が出す)
//!
//! MSI にはまだ署名していないので，確かめられるのは HTTPS で取った latest.json の SHA-256 と同じかだけ．
//! 署名するようになったら WinVerifyTrust で発行元も確かめる．
//! スレッドは結果を受け箱に置いて窓に WM_UPDATE を送り，窓の手続きが受け取って画面と確かめる窓を出す

use super::ffi::{self, hash::Sha256, net, Window};
use super::window::{with_app, App};
use crate::catalog::Catalog;
use crate::strings::update as text;
use crate::update::{self, Check, Offer};
use std::collections::VecDeque;
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use windows::Win32::UI::WindowsAndMessaging::WM_APP;

/// 受け箱に結果が届いた知らせ
pub(super) const WM_UPDATE: u32 = WM_APP + 25;
/// ダウンロードした配布物を置くフォルダ(%LOCALAPPDATA% の下．設定と同じ haji.men\IME)
const DOWNLOAD_FOLDER: [&str; 3] = ["haji.men", "IME", "updates"];
/// ダウンロードの途中のファイルに付ける拡張子(確かめてから外す)
const PARTIAL_EXTENSION: &str = "part";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Stage {
    Idle,
    Checking,
    Downloading(Option<u8>),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Failure {
    Check,
    Download,
    Verify,
    Install,
}

enum Message {
    Checked(Result<Check, Failure>),
    Progress(Option<u8>),
    Downloaded(Result<PathBuf, Failure>),
}

pub struct Updater {
    stage: Stage,
    inbox: Arc<Mutex<VecDeque<Message>>>,
}

impl Default for Updater {
    fn default() -> Self {
        Self {
            stage: Stage::Idle,
            inbox: Arc::new(Mutex::new(VecDeque::new())),
        }
    }
}

impl Updater {
    /// バージョンの行に出す今の状態(何もしていなければ None でバージョンを出す)
    pub fn status(&self) -> Option<String> {
        match self.stage {
            Stage::Idle => None,
            Stage::Checking => Some(text::CHECKING.to_string()),
            Stage::Downloading(percent) => Some(text::downloading(percent)),
        }
    }
}

fn agent() -> String {
    format!("Hajime/{} (Windows)", env!("CARGO_PKG_VERSION"))
}

/// 受け箱に置いて窓に知らせる(別のスレッドから呼ぶ)
fn deliver(inbox: &Mutex<VecDeque<Message>>, window: isize, message: Message) {
    if let Ok(mut queue) = inbox.lock() {
        queue.push_back(message);
    }
    ffi::post(Window(window as *mut _), WM_UPDATE, 0, 0);
}

/// 「更新を確認」を押した．確かめている途中なら何もしない
pub(super) fn start_check(app: &mut App) {
    if app.update.stage != Stage::Idle {
        return;
    }
    let catalog = app.catalog.clone();
    let inbox = Arc::clone(&app.update.inbox);
    let window = app.window.0 as isize;
    let spawned = std::thread::Builder::new()
        .name("update-check".into())
        .spawn(move || {
            let result = fetch_manifest(&catalog).and_then(|body| {
                update::check(
                    &body,
                    env!("CARGO_PKG_VERSION"),
                    &catalog.update.download_base_url,
                    catalog.update.notes_length,
                )
                .map_err(|_| Failure::Check)
            });
            deliver(&inbox, window, Message::Checked(result));
        });
    if spawned.is_ok() {
        set_stage(app, Stage::Checking);
    }
}

fn fetch_manifest(catalog: &Catalog) -> Result<Vec<u8>, Failure> {
    let settings = &catalog.update;
    let mut body = Vec::new();
    net::get(
        &settings.manifest_url,
        &agent(),
        settings.manifest_bytes,
        settings.manifest_timeout(),
        settings.manifest_timeout(),
        |chunk, _, _| {
            body.extend_from_slice(chunk);
            true
        },
    )
    .map_err(|_| Failure::Check)?;
    Ok(body)
}

fn start_download(app: &mut App, offer: Offer) {
    let catalog = app.catalog.clone();
    let inbox = Arc::clone(&app.update.inbox);
    let window = app.window.0 as isize;
    let spawned = std::thread::Builder::new()
        .name("update-download".into())
        .spawn(move || {
            let result = download(&catalog, &offer, |percent| {
                deliver(&inbox, window, Message::Progress(percent));
            });
            deliver(&inbox, window, Message::Downloaded(result));
        });
    if spawned.is_ok() {
        set_stage(app, Stage::Downloading(None));
    } else {
        set_stage(app, Stage::Idle);
    }
}

fn download_folder() -> Option<PathBuf> {
    let base = PathBuf::from(std::env::var_os("LOCALAPPDATA")?);
    Some(
        DOWNLOAD_FOLDER
            .iter()
            .fold(base, |path, part| path.join(part)),
    )
}

/// 配布物を取り，SHA-256 を確かめてから正しい名前にする．前に取った配布物は消す
fn download(
    catalog: &Catalog,
    offer: &Offer,
    progress: impl Fn(Option<u8>),
) -> Result<PathBuf, Failure> {
    let settings = &catalog.update;
    let folder = download_folder().ok_or(Failure::Download)?;
    std::fs::create_dir_all(&folder).map_err(|_| Failure::Download)?;
    remove_previous(&folder);
    let target = folder.join(&offer.file_name);
    let partial = target.with_extension(PARTIAL_EXTENSION);
    let mut file = std::fs::File::create(&partial).map_err(|_| Failure::Download)?;
    let mut hash = Sha256::new().ok_or(Failure::Download)?;
    let mut last = None;
    let fetched = net::get(
        &offer.url,
        &agent(),
        settings.package_bytes,
        settings.manifest_timeout(),
        settings.download_timeout(),
        |chunk, received, total| {
            if file.write_all(chunk).is_err() || !hash.update(chunk) {
                return false;
            }
            let percent = total
                .filter(|total| *total > 0)
                .map(|total| (received.min(total) * 100 / total) as u8);
            if percent != last {
                last = percent;
                progress(percent);
            }
            true
        },
    );
    let written = fetched.is_ok() && file.flush().is_ok() && file.sync_all().is_ok();
    drop(file);
    if !written {
        let _ = std::fs::remove_file(&partial);
        return Err(Failure::Download);
    }
    let digest = hash.finish().map(|digest| update::hex(&digest));
    if digest.as_deref() != Some(offer.sha256.as_str()) {
        let _ = std::fs::remove_file(&partial);
        return Err(Failure::Verify);
    }
    let _ = std::fs::remove_file(&target);
    std::fs::rename(&partial, &target).map_err(|_| Failure::Download)?;
    Ok(target)
}

/// 前に取った配布物と途中のファイルを消す(このフォルダには配布物しか置かない)
fn remove_previous(folder: &std::path::Path) {
    let Ok(entries) = std::fs::read_dir(folder) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        let ours = path
            .extension()
            .is_some_and(|extension| extension == "msi" || extension == PARTIAL_EXTENSION);
        if ours && path.is_file() {
            let _ = std::fs::remove_file(path);
        }
    }
}

fn set_stage(app: &mut App, stage: Stage) {
    app.update.stage = stage;
    app.view.set_version_status(app.update.status());
    ffi::invalidate(app.window);
}

/// WM_UPDATE を受けた．確かめる窓は状態を借りずに出す(窓が開いているあいだも手続きが呼ばれるため)
pub(super) fn receive(window: Window) {
    loop {
        let Some(Some(message)) = with_app(|app| {
            app.update
                .inbox
                .lock()
                .ok()
                .and_then(|mut queue| queue.pop_front())
        }) else {
            return;
        };
        match message {
            Message::Progress(percent) => {
                with_app(|app| {
                    if matches!(app.update.stage, Stage::Downloading(_)) {
                        set_stage(app, Stage::Downloading(percent));
                    }
                });
            }
            Message::Checked(Ok(Check::UpToDate)) => {
                with_app(|app| set_stage(app, Stage::Idle));
                ffi::message(
                    window,
                    text::TITLE,
                    &text::up_to_date(env!("CARGO_PKG_VERSION")),
                    false,
                );
            }
            Message::Checked(Ok(Check::Available(offer))) => {
                let question = text::available(
                    &offer.version.to_string(),
                    env!("CARGO_PKG_VERSION"),
                    &offer.notes,
                );
                if ffi::ask(window, text::TITLE, &question) {
                    with_app(|app| start_download(app, offer));
                } else {
                    with_app(|app| set_stage(app, Stage::Idle));
                }
            }
            Message::Checked(Err(failure)) | Message::Downloaded(Err(failure)) => {
                fail(window, failure);
            }
            Message::Downloaded(Ok(path)) => {
                if ffi::run_installer(&path) {
                    // 入れ始めるとインストーラーがこの画面を閉じる(hajime.wxs の StopRunning)．
                    // UAC で取り消したときに表示が残らないよう，バージョンの表示に戻しておく
                    with_app(|app| set_stage(app, Stage::Idle));
                } else {
                    fail(window, Failure::Install);
                }
            }
        }
    }
}

/// 失敗を知らせ，ブラウザでダウンロードのページを開くかを尋ねる
fn fail(window: Window, failure: Failure) {
    let url = with_app(|app| {
        set_stage(app, Stage::Idle);
        app.catalog.latest_release_url.clone()
    });
    let reason = match failure {
        Failure::Check => text::CHECK_FAILED,
        Failure::Download => text::DOWNLOAD_FAILED,
        Failure::Verify => text::VERIFY_FAILED,
        Failure::Install => text::INSTALL_FAILED,
    };
    let question = format!("{reason}\n{}", text::OPEN_DOWNLOAD_PAGE);
    if ffi::ask(window, text::TITLE, &question) {
        if let Some(url) = url {
            ffi::open_url(&url);
        }
    }
}
