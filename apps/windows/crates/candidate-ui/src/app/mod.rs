#![allow(unsafe_code)]

#[cfg(test)]
mod bench;
pub mod fonts;
pub mod preview;
pub(crate) mod render;
#[cfg(debug_assertions)]
mod snapshot;
pub(crate) mod system;
mod window;

use crate::announce::{self, Announcer};
use crate::motion;
use crate::scene::{self, CardReservation, Look, Scene, Surround};
use crate::strings;
use crate::theme::ResolvedTheme;
use ipc::framing::read_message;
use ipc::windows::{pipe_name, EngineClient};
use ipc::{Presentation, Rect, RequestBody, UiCommand, PROTOCOL_VERSION};
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
pub(crate) const FRAME_MILLISECONDS: u32 = 16;

type Inbox = Arc<Mutex<VecDeque<UiCommand>>>;

enum Content {
    Hidden,
    Candidates(ipc::CandidateList),
    BranchMap(ipc::BranchMap),
    Note(ipc::Note),
    /// モードの札の文字
    Mode(String),
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
    /// 続く語句の予測の窓(色で塗る窓とすりガラスの窓)．候補の窓とは別に，組み立て中の文字の右に出す．押しても受けない
    prediction_plain: Window,
    prediction_glass: Window,
    /// 出している予測．候補の窓を消しても消さず，showPrediction で出し入れする
    prediction: Option<ipc::Prediction>,
    /// 予測の窓を置く基準(組み立て中の文字全体の位置)
    prediction_anchor: Option<Rect>,
    prediction_on_glass: bool,
    prediction_scene: Option<Scene>,
    /// 予測が変わった(次に描いたときに読み上げる)
    prediction_changed: bool,
    backdrop: bool,
    inbox: Inbox,
    presentation: Presentation,
    content: Content,
    anchor: Option<Rect>,
    /// 描いている窓が glass か
    on_glass: bool,
    /// 押した候補をエンジンに知らせる口．初めて押したときにつなぐ
    engine: Option<EngineClient>,
    scene: Option<Scene>,
    theme: Option<ResolvedTheme>,
    rest_opacity: f32,
    opacity: f32,
    fade: Fade,
    announcer: Announcer,
    /// 出している窓の大きさ(影の分を含む)と，大きさが変わる途中の動き
    shown_size: Option<(f32, f32)>,
    resize: Option<motion::Resize>,
    /// あとから届いた中身を重ねて変えている途中の，前の中身と始めた時刻
    crossfade: Option<(Scene, Instant)>,
    /// 選んでいるものが同じまま中身が変わった(次の refresh で重ねて変える)
    arrived: bool,
    /// 候補の右に出した語の意味のカードの場所(同じ候補の並びのあいだは空けたままにする)
    meaning: CardReservation,
    /// 読んだ OS の外観とアニメーション効果の設定
    system: system::SystemCache,
}

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}

pub fn run() {
    #[cfg(debug_assertions)]
    if snapshot::run_if_requested() {
        return;
    }
    let Some(_instance) = window::single_instance() else {
        return;
    };
    window::make_dpi_aware();
    window::set_callbacks(on_inbox, on_timer, on_paint, on_click);
    let (Ok(plain), Ok(glass), Ok(prediction_plain), Ok(prediction_glass)) = (
        Window::create(w!("hajime.candidate"), false),
        Window::create(w!("hajime.candidate.glass"), true),
        Window::create(w!("hajime.prediction"), false),
        Window::create(w!("hajime.prediction.glass"), true),
    ) else {
        return;
    };
    // 予測の窓を押した位置を，候補の窓を押したものと取り違えないよう，押しても受けない
    prediction_plain.pass_clicks_through();
    prediction_glass.pass_clicks_through();
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
        .name("hajime-candidate-ui-reader".into())
        .spawn(move || read_commands(&reader_inbox, &notifier));
    if spawned.is_err() {
        return;
    }
    APP.with(|app| {
        *app.borrow_mut() = Some(App {
            renderer,
            plain,
            glass,
            prediction_plain,
            prediction_glass,
            prediction: None,
            prediction_anchor: None,
            prediction_on_glass: false,
            prediction_scene: None,
            prediction_changed: false,
            backdrop,
            inbox,
            presentation,
            content: Content::Hidden,
            anchor: None,
            on_glass: false,
            engine: None,
            scene: None,
            theme: None,
            rest_opacity: 1.0,
            opacity: 1.0,
            fade: Fade::None,
            announcer: Announcer::default(),
            shown_size: None,
            resize: None,
            crossfade: None,
            arrived: false,
            meaning: CardReservation::default(),
            system: system::SystemCache::default(),
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
                // パレットを出したセッションはもう無く，閉じる指示も届かないので消す
                queue.push_back(UiCommand::HidePalette);
                // エンジンが切れたら予測も消す(予測の窓は Hide では消えない)
                queue.push_back(UiCommand::ShowPrediction {
                    prediction: None,
                    anchor: None,
                });
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

fn on_click(x: i32, y: i32) {
    with_app(|app| app.click(x, y));
}

fn on_timer(timer: Timer) {
    with_app(|app| match timer {
        Timer::Mode => app.mode_elapsed(),
        Timer::Fade => app.step_fade(),
        Timer::Motion => app.step_motion(),
    });
}

impl App {
    /// 候補の窓を押した．押した候補をエンジンに知らせ，エンジンは入力先のセッションの次の wake でキーで選んだのと同じに処理する
    fn click(&mut self, x: i32, y: i32) {
        let Some(scene) = &self.scene else { return };
        let scale = self.window().scale();
        let Some(target) = scene.target_at(x as f32 / scale, y as f32 / scale) else {
            return;
        };
        if self.engine.is_none() {
            self.engine = pipe_name("engine")
                .ok()
                .and_then(|name| EngineClient::start(name).ok());
        }
        if let Some(engine) = &self.engine {
            let _ = engine.send(RequestBody::ChooseCandidate { target });
        }
    }

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
                self.arrived = matches!(&self.content, Content::Candidates(shown) if motion::arrived_list(shown, &list));
                self.content = Content::Candidates(list);
                self.anchor = anchor.or(self.anchor.take());
            }
            UiCommand::ShowBranchMap { map, anchor } => {
                self.arrived = matches!(&self.content, Content::BranchMap(shown) if motion::arrived_branch(shown, &map));
                self.content = Content::BranchMap(map);
                self.anchor = anchor.or(self.anchor.take());
            }
            UiCommand::ShowNote { note, anchor } => {
                self.content = Content::Note(note);
                self.anchor = anchor.or(self.anchor.take());
            }
            UiCommand::ShowPrediction { prediction, anchor } => {
                self.prediction_changed = prediction.is_some() && prediction != self.prediction;
                self.prediction = prediction;
                self.prediction_anchor = anchor.or(self.prediction_anchor.take());
            }
            UiCommand::ShowMode {
                mode,
                anchor,
                label,
            } => {
                self.content =
                    Content::Mode(label.unwrap_or_else(|| strings::mode(mode).to_string()));
                self.anchor = anchor.or(self.anchor.take());
                self.opacity = 1.0;
                self.fade = Fade::None;
                self.window().stop_timer(Timer::Fade);
                self.window()
                    .start_timer(Timer::Mode, self.presentation.mode_indicator_milliseconds);
            }
            UiCommand::ShowHandwriting {
                anchor,
                recognition_delay_milliseconds,
                recognition_timeout_milliseconds,
            } => {
                // 手書きの窓はすりガラスにしない(書く欄の地が透けないように)
                let theme = ResolvedTheme::resolve(
                    &self.presentation.theme,
                    self.presentation.custom_theme.as_ref(),
                    &self.system.look(false),
                );
                crate::handwriting::ffi::show(
                    anchor.or(self.anchor.clone()),
                    recognition_delay_milliseconds,
                    recognition_timeout_milliseconds,
                    theme,
                    self.presentation.font_size as f32,
                );
            }
            UiCommand::HideHandwriting => crate::handwriting::ffi::hide(),
            UiCommand::ShowPalette { panel, anchor } => {
                // パレット(R-26)は別の窓に出す(候補・案内・モードの札に置き換わらないように)．すりガラスにはしない
                let theme = ResolvedTheme::resolve(
                    &self.presentation.theme,
                    self.presentation.custom_theme.as_ref(),
                    &self.system.look(false),
                );
                crate::palette::ffi::show(panel, anchor.or(self.anchor.clone()), theme, ANCHOR_GAP);
            }
            UiCommand::HidePalette => crate::palette::ffi::hide(),
            UiCommand::Move {
                anchor,
                composition,
            } => {
                // 予測の窓は組み立て中の文字全体の右に置く．全体の位置を知らせない DLL では候補の窓と同じ基準にする
                self.prediction_anchor = Some(composition.unwrap_or_else(|| anchor.clone()));
                self.anchor = Some(anchor);
            }
            // 候補と知らせを消す．モードの札は残し，出しておく時間が過ぎたら消す(macOS と同じく札は別に扱う．
            // 同じアプリの中で欄を移ったときや，前のアプリの遅れた deactivate で札が消えないように)
            UiCommand::Hide => {
                if !matches!(self.content, Content::Mode(_)) {
                    self.content = Content::Hidden;
                }
            }
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
        if self.system.reduce_motion() {
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
        if self.system.reduce_motion() {
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

    /// 窓の大きさの動きと重ね変わりの 1 コマ．どちらも終わったら時計を止める
    fn step_motion(&mut self) {
        if self.resize.is_none() && self.crossfade.is_none() {
            self.window().stop_timer(Timer::Motion);
            return;
        }
        self.refresh();
    }

    /// 窓の大きさの動き．出ている窓の大きさが変わったら，前の大きさ(動いている途中ならその大きさ)から新しい大きさへ動かす．
    /// 返すのは今描く大きさ(動いていなければ None)
    fn moving_size(&mut self, natural: (f32, f32), now: Instant) -> Option<(f32, f32)> {
        let animates = self.scene.is_some() && !self.system.reduce_motion();
        if !animates {
            self.resize = None;
            return None;
        }
        if let Some(shown) = self.shown_size {
            if self.resize.map(|resize| resize.to) != Some(natural) && shown != natural {
                let from = self.resize.map_or(shown, |resize| resize.size_at(now));
                self.resize = Some(motion::Resize {
                    from,
                    to: natural,
                    start: now,
                });
            }
        }
        let resize = self.resize?;
        if resize.is_done(now) {
            self.resize = None;
            return None;
        }
        Some(resize.size_at(now))
    }

    fn repaint(&mut self) {
        let Some(theme) = self.theme.clone() else {
            return;
        };
        let Ok(measure) = self
            .renderer
            .measure(&theme, self.presentation.font_size as f32)
        else {
            return;
        };
        if let Some(scene) = self.scene.clone() {
            let opacity = self.opacity;
            let window = if self.on_glass {
                &mut self.glass
            } else {
                &mut self.plain
            };
            let _ = window.draw(&self.renderer, &scene, &measure, opacity);
        }
        if let Some(scene) = self.prediction_scene.clone() {
            let window = if self.prediction_on_glass {
                &mut self.prediction_glass
            } else {
                &mut self.prediction_plain
            };
            let _ = window.draw(&self.renderer, &scene, &measure, 1.0);
        }
    }

    fn prediction_window(&self) -> &Window {
        if self.prediction_on_glass {
            &self.prediction_glass
        } else {
            &self.prediction_plain
        }
    }

    /// 予測の窓を描き直す．候補の窓とは別の窓で，組み立て中の文字の右に置く(候補の窓の出し入れとは関わらない)
    fn refresh_prediction(
        &mut self,
        theme: &ResolvedTheme,
        dark: bool,
        measure: &render::TextMeasure,
    ) {
        let style = Look::new(theme, self.presentation.font_size as f32);
        let scene = self.prediction.as_ref().map(|prediction| {
            scene::surround(
                scene::prediction(prediction, &style, measure),
                theme,
                Surround::Shadow,
            )
        });
        if theme.backdrop != self.prediction_on_glass {
            self.prediction_window().hide();
            self.prediction_on_glass = theme.backdrop;
        }
        match (&scene, self.prediction_anchor.clone()) {
            (Some(scene), Some(anchor)) => {
                let window = if self.prediction_on_glass {
                    &mut self.prediction_glass
                } else {
                    &mut self.prediction_plain
                };
                window.set_chrome(theme.backdrop, dark, theme.frame);
                window.place_beside(&anchor, scene, tokens::size::prediction::GAP);
                let _ = window.draw(&self.renderer, scene, measure, 1.0);
                if std::mem::take(&mut self.prediction_changed) && system::screen_reader() {
                    if let Some(prediction) = &self.prediction {
                        let text = format!("{}{}", prediction.typed, prediction.completion);
                        self.prediction_window()
                            .announce(&strings::prediction(&text));
                    }
                }
            }
            _ => self.prediction_window().hide(),
        }
        self.prediction_scene = scene;
    }

    /// ナレーターが動いているときだけ，選んでいる候補・注目している文節・案内を読み上げる
    fn announce(&mut self) {
        let text = match &self.content {
            Content::Candidates(list) => announce::candidates(list),
            Content::BranchMap(map) => announce::branch_map(map),
            Content::Note(note) => Some(note.text.clone()),
            Content::Hidden | Content::Mode(_) => None,
        };
        if text.is_none() || !system::screen_reader() {
            return;
        }
        if let Some(text) = self.announcer.next(text) {
            self.window().announce(&text);
        }
    }

    fn refresh(&mut self) {
        let look = self.system.look(self.backdrop);
        let theme = ResolvedTheme::resolve(
            &self.presentation.theme,
            self.presentation.custom_theme.as_ref(),
            &look,
        );
        let font_size = self.presentation.font_size as f32;
        let Ok(measure) = self.renderer.measure(&theme, font_size) else {
            return;
        };
        self.refresh_prediction(&theme, look.dark, &measure);
        let mut style = Look::new(&theme, font_size);
        style.rest_opacity = self.rest_opacity;
        style.pixel_scale = self.window().scale();
        style.reserved_card = match &self.content {
            Content::Candidates(list) => self.meaning.list(list, &style, &measure),
            Content::BranchMap(map) => self.meaning.branch(map, &style, &measure),
            Content::Hidden | Content::Note(_) | Content::Mode(_) => self.meaning.clear(),
        };
        let build = |content: &Content, style: &Look| match content {
            Content::Hidden => None,
            Content::Candidates(list) => Some(scene::candidate_list(list, style, &measure)),
            Content::BranchMap(map) => Some(scene::branch_map(map, style, &measure)),
            Content::Note(note) => Some(scene::note(note, style, &measure)),
            Content::Mode(label) => Some(scene::mode(label, style, &measure)),
        };
        let mut scene = build(&self.content, &style);
        // 候補の窓は，大きさが変わるときに縁を滑らかに動かす(地と縁は途中の大きさで描き，中身は新しい配置のまま)
        let now = Instant::now();
        let is_list = matches!(self.content, Content::Candidates(_) | Content::BranchMap(_));
        // 打っているあいだの候補(どれも選んでいない一覧)は打つたびに中身が変わるので，縁を動かさずにすぐ変える(macOS と同じ)
        let typing =
            matches!(&self.content, Content::Candidates(list) if list.selected_entry.is_none());
        let natural = scene.as_ref().map(|scene| (scene.width, scene.height));
        if typing {
            self.resize = None;
        }
        if let (true, false, Some(natural)) = (is_list, typing, natural) {
            if let Some(size) = self.moving_size(natural, now) {
                scene = build(
                    &self.content,
                    &Look {
                        size: Some(size),
                        ..style
                    },
                );
            }
            self.shown_size = scene.as_ref().map(|scene| (scene.width, scene.height));
        } else if typing {
            self.shown_size = natural;
        } else {
            self.shown_size = None;
            self.resize = None;
        }
        let scene = scene.map(|scene| scene::surround(scene, &theme, Surround::Shadow));
        // あとから届いた中身は，前の中身の上に重ねて濃くしていく
        if std::mem::take(&mut self.arrived) && is_list {
            self.crossfade = self.scene.clone().map(|shown| (shown, now));
        }
        if self
            .crossfade
            .as_ref()
            .is_some_and(|(_, start)| now.duration_since(*start) >= motion::crossfade_duration())
        {
            self.crossfade = None;
        }
        if self.resize.is_some() || self.crossfade.is_some() {
            self.window().start_timer(Timer::Motion, FRAME_MILLISECONDS);
        }
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
                // 候補を選んでいるあいだ(一覧で選んでいるときと分岐図)は，候補が並び始める辺を動かさない．
                // 打っているあいだの一覧は入力位置に寄せて置き直す(macOS と同じ)
                self.window()
                    .place(&anchor, scene, ANCHOR_GAP, is_list && !typing);
                let opacity = self.opacity;
                let below = self
                    .crossfade
                    .as_ref()
                    .map(|(shown, start)| (shown, motion::crossfade_opacity(*start, now)));
                let window = if self.on_glass {
                    &mut self.glass
                } else {
                    &mut self.plain
                };
                let _ = window.draw_over(&self.renderer, below, scene, &measure, opacity);
            }
            _ => {
                self.window().hide();
                self.window().stop_timer(Timer::Motion);
                self.shown_size = None;
                self.resize = None;
                self.crossfade = None;
                self.rest_opacity = 1.0;
                self.announcer.reset();
                // 次に出すときに OS の外観を読み直す(設定の変化の知らせが届かなかったときにも，出し直せば今の外観にする)
                self.system.forget();
            }
        }
        self.announce();
        self.scene = scene;
        self.theme = Some(theme);
    }
}
