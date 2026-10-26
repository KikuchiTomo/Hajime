#![allow(unsafe_code)]

mod render;
#[cfg(debug_assertions)]
mod snapshot;
mod system;
mod window;

use crate::scene::{self, Look, Scene, Surround};
use crate::theme::ResolvedTheme;
use ipc::framing::read_message;
use ipc::windows::pipe_name;
use ipc::{InputMode, Presentation, Rect, UiCommand, PROTOCOL_VERSION};
use render::Renderer;
use std::cell::RefCell;
use std::collections::VecDeque;
use std::fs::OpenOptions;
use std::os::windows::fs::OpenOptionsExt;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use window::{Timer, Window};
use windows_core::w;

const SECURITY_IDENTIFICATION: u32 = 0x0001_0000;
const RECONNECT_INTERVAL: Duration = Duration::from_secs(1);
const ANCHOR_GAP: i32 = 2;
/// フェードの 1 コマの長さ(60 コマ毎秒)
const FRAME_MILLISECONDS: u32 = 16;

type Inbox = Arc<Mutex<VecDeque<UiCommand>>>;

enum Content {
    Hidden,
    Candidates(ipc::CandidateList),
    BranchMap(ipc::BranchMap),
    Note(String),
    Mode(InputMode),
}

/// 動いているフェード
#[derive(Clone, Copy)]
enum Fade {
    None,
    /// 出し始めに，第 1 候補と選んでいる候補のほかを濃くしていく
    Rest(Instant),
    /// モードの札を消していく
    ModeOut(Instant),
}

struct App {
    renderer: Renderer,
    /// 地を色で塗る窓と，すりガラスの地の窓(OS が影を付ける)
    plain: Window,
    glass: Window,
    backdrop: bool,
    inbox: Inbox,
    presentation: Presentation,
    content: Content,
    anchor: Option<Rect>,
    /// 描いている窓が glass か
    on_glass: bool,
    scene: Option<Scene>,
    theme: Option<ResolvedTheme>,
    rest_opacity: f32,
    opacity: f32,
    fade: Fade,
}

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}

pub fn run() {
    #[cfg(debug_assertions)]
    if snapshot::run_if_requested() {
        return;
    }
    window::make_dpi_aware();
    window::set_callbacks(on_inbox, on_timer, on_paint);
    let (Ok(plain), Ok(glass)) = (
        Window::create(w!("s90.tokyo-ime.candidate"), false),
        Window::create(w!("s90.tokyo-ime.candidate.glass"), true),
    ) else {
        return;
    };
    let Ok(renderer) = Renderer::new() else {
        return;
    };
    let backdrop = glass.supports_backdrop();
    let inbox: Inbox = Arc::new(Mutex::new(VecDeque::new()));
    let presentation = Presentation {
        theme: String::new(),
        font_size: f64::from(tokens::size::candidate::FONT_SIZE),
        mode_indicator_milliseconds: tokens::motion::mode_indicator::VISIBLE as u32,
        custom_theme: None,
    };
    let notifier = plain.notifier();
    let reader_inbox = inbox.clone();
    let spawned = std::thread::Builder::new()
        .name("s90-candidate-ui-reader".into())
        .spawn(move || read_commands(&reader_inbox, &notifier));
    if spawned.is_err() {
        return;
    }
    APP.with(|app| {
        *app.borrow_mut() = Some(App {
            renderer,
            plain,
            glass,
            backdrop,
            inbox,
            presentation,
            content: Content::Hidden,
            anchor: None,
            on_glass: false,
            scene: None,
            theme: None,
            rest_opacity: 1.0,
            opacity: 1.0,
            fade: Fade::None,
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

fn with_app(action: impl FnOnce(&mut App)) {
    APP.with(|app| {
        if let Ok(mut app) = app.try_borrow_mut() {
            if let Some(app) = app.as_mut() {
                action(app);
            }
        }
    });
}

fn on_inbox() {
    with_app(App::drain);
}

fn on_paint() {
    with_app(App::repaint);
}

fn on_timer(timer: Timer) {
    with_app(|app| match timer {
        Timer::Mode => app.mode_elapsed(),
        Timer::Fade => app.step_fade(),
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
        let was_list = matches!(self.content, Content::Candidates(_) | Content::BranchMap(_));
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
                self.opacity = 1.0;
                self.fade = Fade::None;
                self.window().stop_timer(Timer::Fade);
                self.window()
                    .start_timer(Timer::Mode, self.presentation.mode_indicator_milliseconds);
            }
            UiCommand::Move { anchor } => self.anchor = Some(anchor),
            UiCommand::Hide => self.content = Content::Hidden,
        }
        let is_list = matches!(self.content, Content::Candidates(_) | Content::BranchMap(_));
        if is_list && !was_list {
            self.start_rest_fade();
        }
    }

    fn window(&self) -> &Window {
        if self.on_glass {
            &self.glass
        } else {
            &self.plain
        }
    }

    /// 候補を出した瞬間は，第 1 候補と選んでいる候補だけを濃く描き，残りを位置を変えずに濃くしていく．
    /// アニメーション効果がオフなら最初から濃く出す
    fn start_rest_fade(&mut self) {
        if system::reduce_motion() {
            self.rest_opacity = 1.0;
            self.fade = Fade::None;
            return;
        }
        self.rest_opacity = 0.0;
        self.fade = Fade::Rest(Instant::now());
        self.window().start_timer(Timer::Fade, FRAME_MILLISECONDS);
    }

    /// モードの札を出しておく時間が過ぎた．フェードして消す
    fn mode_elapsed(&mut self) {
        self.window().stop_timer(Timer::Mode);
        if !matches!(self.content, Content::Mode(_)) {
            return;
        }
        if system::reduce_motion() {
            self.content = Content::Hidden;
            self.refresh();
            return;
        }
        self.fade = Fade::ModeOut(Instant::now());
        self.window().start_timer(Timer::Fade, FRAME_MILLISECONDS);
    }

    fn step_fade(&mut self) {
        let progress =
            |start: Instant, total: f32| (start.elapsed().as_secs_f32() * 1000.0 / total).min(1.0);
        match self.fade {
            Fade::None => self.window().stop_timer(Timer::Fade),
            Fade::Rest(start) => {
                self.rest_opacity = progress(start, tokens::motion::candidate_rest::FADE_IN);
                if self.rest_opacity >= 1.0 {
                    self.fade = Fade::None;
                }
                self.refresh();
            }
            Fade::ModeOut(start) => {
                let done = progress(start, tokens::motion::mode_indicator::FADE);
                // ease-out で薄くする
                self.opacity = (1.0 - done).powi(2);
                if done >= 1.0 {
                    self.fade = Fade::None;
                    self.opacity = 1.0;
                    self.content = Content::Hidden;
                    self.refresh();
                } else {
                    self.repaint();
                }
            }
        }
        if matches!(self.fade, Fade::None) {
            self.window().stop_timer(Timer::Fade);
        }
    }

    fn repaint(&mut self) {
        let (Some(scene), Some(theme)) = (self.scene.clone(), self.theme.clone()) else {
            return;
        };
        let Ok(measure) = self
            .renderer
            .measure(&theme, self.presentation.font_size as f32)
        else {
            return;
        };
        let opacity = self.opacity;
        let window = if self.on_glass {
            &mut self.glass
        } else {
            &mut self.plain
        };
        let _ = window.draw(&self.renderer, &scene, &measure, opacity);
    }

    fn refresh(&mut self) {
        let look = system::look(self.backdrop);
        let theme = ResolvedTheme::resolve(
            &self.presentation.theme,
            self.presentation.custom_theme.as_ref(),
            &look,
        );
        let font_size = self.presentation.font_size as f32;
        let Ok(measure) = self.renderer.measure(&theme, font_size) else {
            return;
        };
        let mut style = Look::new(&theme, font_size);
        style.rest_opacity = self.rest_opacity;
        let scene = match &self.content {
            Content::Hidden => None,
            Content::Candidates(list) => Some(scene::candidate_list(list, &style, &measure)),
            Content::BranchMap(map) => Some(scene::branch_map(map, &style, &measure)),
            Content::Note(text) => Some(scene::note(text, &style, &measure)),
            Content::Mode(mode) => Some(scene::mode(*mode, &style, &measure)),
        }
        .map(|scene| scene::surround(scene, &theme, Surround::Shadow));
        let on_glass = theme.backdrop;
        if on_glass != self.on_glass {
            // 窓を替える．動いている時計も移す
            self.window().hide();
            self.window().stop_timer(Timer::Fade);
            self.window().stop_timer(Timer::Mode);
            self.on_glass = on_glass;
            if !matches!(self.fade, Fade::None) {
                self.window().start_timer(Timer::Fade, FRAME_MILLISECONDS);
            }
            if matches!(self.content, Content::Mode(_)) && matches!(self.fade, Fade::None) {
                self.window()
                    .start_timer(Timer::Mode, self.presentation.mode_indicator_milliseconds);
            }
        }
        match (&scene, self.anchor.clone()) {
            (Some(scene), Some(anchor)) => {
                self.window()
                    .set_chrome(theme.backdrop, look.dark, theme.frame);
                self.window().place(&anchor, scene, ANCHOR_GAP);
                let opacity = self.opacity;
                let window = if self.on_glass {
                    &mut self.glass
                } else {
                    &mut self.plain
                };
                let _ = window.draw(&self.renderer, scene, &measure, opacity);
            }
            _ => {
                self.window().hide();
                self.rest_opacity = 1.0;
            }
        }
        self.scene = scene;
        self.theme = Some(theme);
    }
}
