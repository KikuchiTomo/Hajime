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
use crate::scene::{self, Look, Scene, Surround};
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
    /// モード表示の文字
    Mode(String),
}

/// 動いているフェード
#[derive(Clone, Copy)]
enum Fade {
    None,
    /// 出し始めに，第 1 候補と選んでいる候補のほかを濃くしていく
    Rest(Instant),
    /// モード表示を消していく
    ModeOut(Instant),
}

struct App {
    renderer: Renderer,
    /// 背景を色で塗る窓と，すりガラスの背景の窓(OS が影を付ける)
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
    /// 候補の窓に最後に描いた場面と濃さと拡大率．同じものを描き直さない(描くたびに画面が差し替わり，ちらつくため)．
    /// 拡大率の違う画面へ移ったときは同じ場面でも描き直す
    drawn: Option<(Scene, f32, f32)>,
    /// 語の意味の吹き出しに最後に描いた場面と濃さと拡大率
    bubble_drawn: Option<(Scene, f32, f32)>,
    /// 最後に描き直した OS の設定の世代(ライト・ダークなどの変化を受けて描き直したか)
    settings_generation: u64,
    resize: Option<motion::Resize>,
    /// あとから届いた中身を重ねて変えている途中の，前の中身と始めた時刻
    crossfade: Option<(Scene, Instant)>,
    /// 選んでいるものが同じまま中身が変わった(次の refresh で重ねて変える)
    arrived: bool,
    /// 語の意味の吹き出しの窓(候補の窓の横に出す．背景は自分で塗り，押しても受けない)
    bubble: Window,
    bubble_scene: Option<Scene>,
    /// 吹き出しの本体を置いた位置(論理ピクセル)と，選んでいる候補が変わって付いて動いている途中の動き
    bubble_at: Option<(f32, f32)>,
    /// 吹き出しを置いたときの候補の窓の本体の左上(画面のピクセル)と拡大率．窓を置き直したかを見分ける
    bubble_anchor: Option<(i32, i32, f32)>,
    bubble_glide: Option<motion::Resize>,
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
    window::set_callbacks(on_inbox, on_timer, on_paint, on_click, on_settings_changed);
    let (Ok(plain), Ok(glass), Ok(prediction_plain), Ok(prediction_glass), Ok(bubble)) = (
        Window::create(w!("hajime.candidate"), false),
        Window::create(w!("hajime.candidate.glass"), true),
        Window::create(w!("hajime.prediction"), false),
        Window::create(w!("hajime.prediction.glass"), true),
        Window::create(w!("hajime.meaning"), false),
    ) else {
        return;
    };
    // 予測の窓と吹き出しを押した位置を，候補の窓を押したものと取り違えないよう，押しても受けない
    prediction_plain.pass_clicks_through();
    prediction_glass.pass_clicks_through();
    bubble.pass_clicks_through();
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
            drawn: None,
            bubble_drawn: None,
            settings_generation: system::settings_generation(),
            resize: None,
            crossfade: None,
            arrived: false,
            bubble,
            bubble_scene: None,
            bubble_at: None,
            bubble_anchor: None,
            bubble_glide: None,
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

fn on_settings_changed() {
    with_app(App::settings_changed);
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
        // 入力位置が変わらない Move(入力欄に書くたびに届く)だけなら描き直さない
        let mut changed = false;
        for command in commands {
            if self.repeats(&command) {
                continue;
            }
            changed = true;
            self.apply(command);
        }
        if changed {
            self.refresh();
        }
        // 起こしのたびに，出している窓を最前面に付け直す(あとから出た別のアプリの最前面の窓の下にもぐらないように)．
        // 位置・大きさ・中身は変えず，描き直さない
        self.raise_windows();
    }

    /// 出している窓を最前面に付け直す．候補の窓・予測の窓・吹き出しの順(吹き出しを候補の窓の上に)
    fn raise_windows(&self) {
        self.window().raise();
        self.prediction_window().raise();
        self.bubble.raise();
    }

    /// OS の外観(ライト・ダーク・アクセントカラー・ハイコントラスト)が変わった．次のキーを待たずに今の外観で描き直す．
    /// 窓ごとに同じ知らせが届くので，同じ世代では 1 回だけ描き直す(同じ場面は描かないので，重ねて呼んでもちらつかない)
    fn settings_changed(&mut self) {
        let generation = system::settings_generation();
        if generation == self.settings_generation {
            return;
        }
        self.settings_generation = generation;
        if self.scene.is_some() || self.prediction_scene.is_some() {
            self.refresh();
        }
    }

    /// 今の状態を変えない指示か(入力位置も組み立て中の文字の位置も前と同じ Move)
    fn repeats(&self, command: &UiCommand) -> bool {
        match command {
            UiCommand::Move {
                anchor,
                composition,
            } => {
                self.anchor.as_ref() == Some(anchor)
                    && self.prediction_anchor.as_ref()
                        == Some(composition.as_ref().unwrap_or(anchor))
            }
            _ => false,
        }
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
                // 手書きの窓はすりガラスにしない(書く欄の背景が透けないように)．枠は OS のライトとダークに合わせる
                let look = self.system.look(false);
                let theme = ResolvedTheme::resolve(
                    &self.presentation.theme,
                    self.presentation.custom_theme.as_ref(),
                    &look,
                );
                crate::handwriting::ffi::show(
                    anchor.or(self.anchor.clone()),
                    recognition_delay_milliseconds,
                    recognition_timeout_milliseconds,
                    theme,
                    look.dark,
                );
            }
            UiCommand::HideHandwriting => crate::handwriting::ffi::hide(),
            UiCommand::ShowPalette { panel, anchor } => {
                // パレット(R-26)は別の窓に出す(候補・案内・モード表示に置き換わらないように)．すりガラスにはしない
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
            // 候補と知らせを消す．モード表示は残し，出しておく時間が過ぎたら消す(macOS と同じくタグは別に扱う．
            // 同じアプリの中で欄を移ったときや，前のアプリの遅れた deactivate でタグが消えないように)
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

    /// モード表示を出しておく時間が過ぎた．フェードして消す
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
        if self.resize.is_none() && self.crossfade.is_none() && self.bubble_glide.is_none() {
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
            let scale = window.scale();
            let painted = window.draw(&self.renderer, &scene, &measure, opacity);
            // 薄くしているあいだなどに描いたものも覚え，次に同じものだけを描き直さないようにする
            self.drawn = painted.is_ok().then_some((scene, opacity, scale));
        }
        if let Some(scene) = self.prediction_scene.clone() {
            let window = if self.prediction_on_glass {
                &mut self.prediction_glass
            } else {
                &mut self.prediction_plain
            };
            let _ = window.draw(&self.renderer, &scene, &measure, 1.0);
        }
        if let Some(scene) = self.bubble_scene.clone() {
            let opacity = self.opacity;
            let scale = self.bubble.scale();
            let painted = self.bubble.draw(&self.renderer, &scene, &measure, opacity);
            self.bubble_drawn = painted.is_ok().then_some((scene, opacity, scale));
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

    /// 語の意味の吹き出しを，候補の窓の横に出す・動かす・隠す．window は候補の窓の場面(影を足す前)．
    /// 吹き出しは自分で背景を塗る窓なので，すりガラスの背景を使わない見た目(backdrop なし)で描く
    fn refresh_bubble(&mut self, window: Option<&Scene>, font_size: f32, now: Instant) {
        let shown = match (&self.content, window) {
            (Content::Candidates(list), Some(window)) => scene::bubble::for_list(list, window),
            (Content::BranchMap(map), Some(window)) => scene::bubble::for_branch(map, window),
            _ => None,
        }
        .map(|(note, others, row)| (note.clone(), others, row));
        let (Some((note, others, row)), Some((body, work))) =
            (shown, self.window().body_and_work_area())
        else {
            self.hide_bubble();
            return;
        };
        let look = self.system.look(false);
        let theme = ResolvedTheme::resolve(
            &self.presentation.theme,
            self.presentation.custom_theme.as_ref(),
            &look,
        );
        let Ok(measure) = self.renderer.measure(&theme, font_size) else {
            return;
        };
        let scale = self.window().scale();
        let style = Look {
            pixel_scale: scale,
            ..Look::new(&theme, font_size)
        };
        let dips = |rect: &windows::Win32::Foundation::RECT| {
            scene::Frame::new(
                rect.left as f32 / scale,
                rect.top as f32 / scale,
                (rect.right - rect.left) as f32 / scale,
                (rect.bottom - rect.top) as f32 / scale,
            )
        };
        let anchor = dips(&body);
        let screen = dips(&work);
        // 候補の窓の場面の座標(本体が原点)を，画面の論理ピクセルに直す
        let on_screen = |frame: &scene::Frame| frame.offset(anchor.x, anchor.y);
        let mut keep_clear: Vec<scene::Frame> = window
            .map(|window| window.keep_clear.iter().map(on_screen).collect())
            .unwrap_or_default();
        // 入力中の文字の行も覆わない
        if let Some(caret) = &self.anchor {
            keep_clear.push(scene::Frame::new(
                screen.x,
                caret.y as f32 / scale,
                screen.width,
                (caret.height.max(1) as f32) / scale,
            ));
        }
        let bubble = scene::bubble::bubble(&note, others, &style, &measure);
        let placement = scene::bubble::place(
            on_screen(&row),
            anchor,
            (bubble.width, bubble.height),
            screen,
            &keep_clear,
            &scene::bubble::Metrics::tokens(theme.is_rounded()),
        );
        let drawn = scene::bubble::bubble_scene(&bubble, &placement, &style, &measure);
        // 選んでいる候補が変わったら付いて動く(視覚効果を減らす設定ならすぐ移す)．
        // 候補の窓を置き直したときは，前の場所から滑らせずに窓に付けてすぐ移す
        let target = (placement.window.x, placement.window.y);
        let anchor_now = (body.left, body.top, scale);
        let window_moved = self.bubble_anchor.is_some_and(|shown| shown != anchor_now);
        self.bubble_anchor = Some(anchor_now);
        if window_moved {
            self.bubble_glide = None;
        }
        let moving = self.bubble_glide.map(|glide| glide.to);
        if moving != Some(target)
            && motion::glides_bubble(
                self.bubble_at,
                target,
                window_moved,
                self.system.reduce_motion(),
            )
        {
            let from = self
                .bubble_glide
                .map_or(self.bubble_at.unwrap_or(target), |glide| glide.size_at(now));
            self.bubble_glide = Some(motion::Resize {
                from,
                to: target,
                start: now,
            });
            self.window().start_timer(Timer::Motion, FRAME_MILLISECONDS);
        }
        let (x, y) = match self.bubble_glide {
            Some(glide) if !glide.is_done(now) => glide.size_at(now),
            _ => {
                self.bubble_glide = None;
                target
            }
        };
        self.bubble_at = Some(target);
        self.bubble.set_chrome(false, look.dark, theme.frame);
        // 位置と大きさは候補の窓の拡大率で決める(吹き出しの窓は隠れているあいだ前の画面の拡大率のままのことがある)
        self.bubble.place_at(
            (x * scale).round() as i32,
            (y * scale).round() as i32,
            &drawn,
            scale,
        );
        let opacity = self.opacity;
        // 吹き出しの窓は置いたあとの画面の拡大率で描く
        let bubble_scale = self.bubble.scale();
        if self.bubble_drawn.as_ref() != Some(&(drawn.clone(), opacity, bubble_scale)) {
            let painted = self.bubble.draw(&self.renderer, &drawn, &measure, opacity);
            self.bubble_drawn = painted
                .is_ok()
                .then(|| (drawn.clone(), opacity, bubble_scale));
        }
        self.bubble_scene = Some(drawn);
    }

    fn hide_bubble(&mut self) {
        self.bubble.hide();
        self.bubble_scene = None;
        self.bubble_drawn = None;
        self.bubble_at = None;
        self.bubble_anchor = None;
        self.bubble_glide = None;
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
        let build = |content: &Content, style: &Look| match content {
            Content::Hidden => None,
            Content::Candidates(list) => Some(scene::candidate_list(list, style, &measure)),
            Content::BranchMap(map) => Some(scene::branch_map(map, style, &measure)),
            Content::Note(note) => Some(scene::note(note, style, &measure)),
            Content::Mode(label) => Some(scene::mode(label, style, &measure)),
        };
        let mut scene = build(&self.content, &style);
        // 候補の窓は，大きさが変わるときに枠線を滑らかに動かす(背景と枠線は途中の大きさで描き，中身は新しい配置のまま)
        let now = Instant::now();
        let is_list = matches!(self.content, Content::Candidates(_) | Content::BranchMap(_));
        // 打っているあいだの候補(どれも選んでいない一覧)は打つたびに中身が変わるので，枠線を動かさずにすぐ変える(macOS と同じ)
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
        // 吹き出しの三角で指す行は，影を足す前の場面(本体が原点)の座標で探す
        let bare = scene.clone();
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
        if self.resize.is_some() || self.crossfade.is_some() || self.bubble_glide.is_some() {
            self.window().start_timer(Timer::Motion, FRAME_MILLISECONDS);
        }
        let on_glass = theme.backdrop;
        if on_glass != self.on_glass {
            // 窓を替える．動いている時計も移す
            self.window().hide();
            self.drawn = None;
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
                let placed = self
                    .window()
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
                let scale = window.scale();
                let same = below.is_none()
                    && self.drawn.as_ref() == Some(&(scene.clone(), opacity, scale));
                if !same {
                    let painted = window.draw_over(&self.renderer, below, scene, &measure, opacity);
                    // 重ね変わりの途中に描いたものは次のコマで描き直すので覚えない
                    self.drawn = (painted.is_ok() && below.is_none())
                        .then(|| (scene.clone(), opacity, scale));
                }
                self.refresh_bubble(bare.as_ref(), font_size, now);
                // 候補の窓を置き直すと一番手前に来る．予測の窓と吹き出しを起こしのときと同じ順に付け直し，
                // 吹き出しを候補の窓の上に戻す(同じ位置の吹き出しは置き直さないので，そのままだと候補の窓の後ろに隠れる)
                if placed {
                    self.prediction_window().raise();
                    self.bubble.raise();
                }
            }
            _ => {
                self.hide_bubble();
                self.window().hide();
                self.drawn = None;
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
