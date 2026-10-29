//! Fcitx 5 のアドオン(C++)から呼ぶ橋渡し．エンジン(hajime-engine-host)との通信は Windows と同じ ipc を使い，
//! C++ には C の関数(include/hajime_bridge.h)だけを見せる．C++ 側は JSON もソケットも扱わない
//!
//! 文字列はすべて UTF-8．橋渡しが返す文字列は，次に同じ橋渡しを呼ぶまで有効

pub mod session;
pub mod ui;

mod ffi;

use ipc::{FieldContext, Key, KeyInput, Modifiers, TextStyle};
use session::{Output, Session};
use std::ffi::CString;
use std::io::Read;
use std::os::unix::net::UnixStream;
use std::path::Path;
use ui::{Panel, Receiver};

/// エンジンの実行ファイルを起こし，エンジンと候補の指示の両方につなぐ
pub struct Bridge {
    session: Session,
    receiver: Receiver,
    notify: UnixStream,
    output: Output,
    commit: CString,
    preedit: Vec<(CString, TextStyle)>,
    panel: Panel,
    candidates: Vec<CString>,
    note: CString,
    hints: CString,
}

impl Bridge {
    /// engine はエンジンの実行ファイル．動いていなければ起こす(動いていれば，起こしたものはすぐ終わる)
    pub fn new(engine: Option<&Path>) -> std::io::Result<Self> {
        if let Some(engine) = engine {
            // 起こせなくても入力は続ける(あとでつながれば使う)
            let _ = std::process::Command::new(engine)
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null())
                .spawn();
        }
        let client = ipc::client::EngineClient::start_unix(ipc::unix::socket_path("engine")?)?;
        let (notify, sender) = UnixStream::pair()?;
        notify.set_nonblocking(true)?;
        sender.set_nonblocking(true)?;
        let receiver = Receiver::start(ipc::unix::socket_path("candidate-window")?, sender)?;
        Ok(Self {
            session: Session::new(client),
            receiver,
            notify,
            output: Output::default(),
            commit: CString::default(),
            preedit: Vec::new(),
            panel: Panel::default(),
            candidates: Vec::new(),
            note: CString::default(),
            hints: CString::default(),
        })
    }

    pub fn key(
        &mut self,
        key: Key,
        modifiers: Modifiers,
        is_keypad: bool,
        context: FieldContext,
    ) -> bool {
        let input = KeyInput {
            key,
            modifiers,
            key_label: None,
            is_keypad,
        };
        let output = self.session.key(input, context);
        self.store(output)
    }

    pub fn wake(&mut self, context: FieldContext) {
        let output = self.session.wake(context);
        self.store(output);
    }

    pub fn deactivate(&mut self) {
        let output = self.session.deactivate();
        self.store(output);
    }

    fn store(&mut self, output: Output) -> bool {
        self.commit = c_string(&output.commit);
        if let Some(segments) = &output.preedit {
            self.preedit = segments
                .iter()
                .map(|(text, style)| (c_string(text), *style))
                .collect();
        }
        let handled = output.handled;
        self.output = output;
        handled
    }

    /// 候補の一覧が変わったという知らせを読み捨て，今の一覧を取り込む
    pub fn load_panel(&mut self) {
        let mut buffer = [0u8; 64];
        while matches!(self.notify.read(&mut buffer), Ok(count) if count > 0) {}
        self.panel = self.receiver.panel();
        self.candidates = self
            .panel
            .candidates
            .iter()
            .map(|text| c_string(text))
            .collect();
        self.note = c_string(&self.panel.note);
        self.hints = c_string(&self.panel.hints);
    }

    /// 直前の結果の確定した文字(試すため)
    pub fn commit_text(&self) -> String {
        self.commit.to_string_lossy().into_owned()
    }

    /// 入力中の文字(試すため)．見た目と文字の組
    pub fn preedit(&self) -> Vec<(TextStyle, String)> {
        self.preedit
            .iter()
            .map(|(text, style)| (*style, text.to_string_lossy().into_owned()))
            .collect()
    }

    /// 候補の一覧を取り込んで返す(試すため)
    pub fn load_panel_now(&mut self) -> Vec<String> {
        self.load_panel();
        self.panel.candidates.clone()
    }
}

/// C に渡す文字列．途中に NUL のある文字列は C では表せないので空にする
fn c_string(text: &str) -> CString {
    CString::new(text).unwrap_or_default()
}
