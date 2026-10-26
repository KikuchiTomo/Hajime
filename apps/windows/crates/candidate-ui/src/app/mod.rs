#![allow(unsafe_code)]

mod render;
mod window;

use crate::scene::{self, Metrics, Scene};
use ipc::framing::read_message;
use ipc::windows::pipe_name;
use ipc::{InputMode, Presentation, Rect, UiCommand, PROTOCOL_VERSION};
use render::Renderer;
use std::cell::RefCell;
use std::collections::VecDeque;
use std::fs::OpenOptions;
use std::os::windows::fs::OpenOptionsExt;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use window::Window;

const SECURITY_IDENTIFICATION: u32 = 0x0001_0000;
const RECONNECT_INTERVAL: Duration = Duration::from_secs(1);
const ANCHOR_GAP: i32 = 2;

type Inbox = Arc<Mutex<VecDeque<UiCommand>>>;

enum Content {
    Hidden,
    Candidates(ipc::CandidateList),
    BranchMap(ipc::BranchMap),
    Note(String),
    Mode(InputMode),
}

struct App {
    window: Window,
    renderer: Renderer,
    inbox: Inbox,
    presentation: Presentation,
    content: Content,
    anchor: Option<Rect>,
    scene: Option<Scene>,
}

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}

pub fn run() {
    window::make_dpi_aware();
    let Ok(window) = Window::create(on_inbox, on_timer, on_paint) else {
        return;
    };
    let Ok(renderer) = Renderer::new() else {
        return;
    };
    let inbox: Inbox = Arc::new(Mutex::new(VecDeque::new()));
    let presentation = Presentation {
        theme: String::new(),
        font_size: f64::from(tokens::size::candidate::FONT_SIZE),
        mode_indicator_milliseconds: tokens::motion::mode_indicator::VISIBLE as u32,
    };
    let notifier = window.notifier();
    let reader_inbox = inbox.clone();
    let spawned = std::thread::Builder::new()
        .name("s90-candidate-ui-reader".into())
        .spawn(move || read_commands(&reader_inbox, &notifier));
    if spawned.is_err() {
        return;
    }
    APP.with(|app| {
        *app.borrow_mut() = Some(App {
            window,
            renderer,
            inbox,
            presentation,
            content: Content::Hidden,
            anchor: None,
            scene: None,
        })
    });
    window::run_message_loop();
}

fn read_commands(inbox: &Inbox, notifier: &window::Notifier) {
    loop {
        if let Some(mut pipe) = pipe_name("ui").ok().and_then(|name| {
            OpenOptions::new()
                .read(true)
                .write(true)
                .security_qos_flags(SECURITY_IDENTIFICATION)
                .open(name)
                .ok()
        }) {
            while let Ok(command) = read_message::<_, UiCommand>(&mut pipe) {
                if let Ok(mut queue) = inbox.lock() {
                    queue.push_back(command);
                }
                notifier.notify();
            }
            if let Ok(mut queue) = inbox.lock() {
                queue.push_back(UiCommand::Hide);
            }
            notifier.notify();
        }
        std::thread::sleep(RECONNECT_INTERVAL);
    }
}

fn on_inbox() {
    APP.with(|app| {
        if let Ok(mut app) = app.try_borrow_mut() {
            if let Some(app) = app.as_mut() {
                app.drain();
            }
        }
    });
}

fn on_paint() {
    APP.with(|app| {
        if let Ok(mut app) = app.try_borrow_mut() {
            if let Some(app) = app.as_mut() {
                app.repaint();
            }
        }
    });
}

fn on_timer() {
    APP.with(|app| {
        if let Ok(mut app) = app.try_borrow_mut() {
            if let Some(app) = app.as_mut() {
                if matches!(app.content, Content::Mode(_)) {
                    app.content = Content::Hidden;
                    app.refresh();
                }
            }
        }
    });
}

impl App {
    fn drain(&mut self) {
        let commands: Vec<UiCommand> = match self.inbox.lock() {
            Ok(mut queue) => queue.drain(..).collect(),
            Err(_) => return,
        };
        for command in commands {
            self.apply(command);
        }
        self.refresh();
    }

    fn apply(&mut self, command: UiCommand) {
        match command {
            UiCommand::Hello { protocol_version } => {
                if protocol_version != PROTOCOL_VERSION {
                    self.content = Content::Hidden;
                }
            }
            UiCommand::SetPresentation { presentation } => self.presentation = presentation,
            UiCommand::ShowCandidates { list, anchor } => {
                self.content = Content::Candidates(list);
                self.anchor = anchor.or(self.anchor.take());
            }
            UiCommand::ShowBranchMap { map, anchor } => {
                self.content = Content::BranchMap(map);
                self.anchor = anchor.or(self.anchor.take());
            }
            UiCommand::ShowNote { text, anchor } => {
                self.content = Content::Note(text);
                self.anchor = anchor.or(self.anchor.take());
            }
            UiCommand::ShowMode { mode, anchor } => {
                self.content = Content::Mode(mode);
                self.anchor = anchor.or(self.anchor.take());
                self.window
                    .start_timer(self.presentation.mode_indicator_milliseconds);
            }
            UiCommand::Move { anchor } => self.anchor = Some(anchor),
            UiCommand::Hide => self.content = Content::Hidden,
        }
    }

    fn repaint(&mut self) {
        let Some(scene) = self.scene.clone() else {
            return;
        };
        let palette = tokens::palette(&self.presentation.theme);
        if let Ok(measure) = self.renderer.measure(self.presentation.font_size as f32) {
            let _ = self.renderer.draw(&self.window, &scene, &palette, &measure);
        }
    }

    fn refresh(&mut self) {
        let palette = tokens::palette(&self.presentation.theme);
        let font_size = self.presentation.font_size as f32;
        let measure = match self.renderer.measure(font_size) {
            Ok(measure) => measure,
            Err(_) => return,
        };
        let metrics = Metrics::new(font_size, &measure);
        let scene = match &self.content {
            Content::Hidden => None,
            Content::Candidates(list) => Some(scene::candidate_list(list, &metrics, &measure)),
            Content::BranchMap(map) => Some(scene::branch_map(map, &metrics, &measure)),
            Content::Note(text) => Some(scene::note(text, &metrics, &measure)),
            Content::Mode(mode) => Some(scene::mode(*mode, &metrics, &measure)),
        };
        match (&scene, self.anchor.clone()) {
            (Some(scene), Some(anchor)) => {
                self.window
                    .place(&anchor, scene.width, scene.height, ANCHOR_GAP);
                let _ = self.renderer.draw(&self.window, scene, &palette, &measure);
            }
            _ => self.window.hide(),
        }
        self.scene = scene;
    }
}
