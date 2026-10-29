#![forbid(unsafe_code)]

//! 初期設定ウィザードの窓．設定の画面と同じ描き方(Direct2D・トークンの色・Mica・DPI・高コントラスト・読み上げ)で，
//! 左に選ぶもの，右に実演を出す．実演は台本(demo)を時間で進め，候補の窓は candidate-ui の描き方で描く．
//! 止まっているコマのあいだは時計で次のコマを待ち，CPU を使わない．動きを減らす設定のときは結果のコマだけを出す．
//! 値はページを離れるときにエンジンに書く．済んだことは HKCU に書く(ffi::set_setup_completed)

use super::ffi::d2d::{self, Graphics, PreviewPixels, Surface};
use super::ffi::uia;
use super::ffi::{self, Window};
use super::paint::{self, ButtonKind, Canvas, Measure, State, TextLayout, TextStyle};
use super::theme::{Color, Theme};
use super::window::ForcedTheme;
use super::Store;
use crate::catalog::{Catalog, Timing};
use crate::demo::{self, Frame, Mode, Popup, Script, Style, Today};
use crate::layout::Rect;
use crate::model::SettingsModel;
use crate::strings::wizard as text;
use crate::ui::anim::{Easing, Tween};
use crate::wizard::{self, Choices, Field, Group, GroupKind, Step};
use std::cell::RefCell;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokens::motion::settings_windows as motion;
use tokens::size::settings_windows as size;
use windows::Win32::Foundation::{HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::UI::Controls::WM_MOUSELEAVE;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    VK_DOWN, VK_ESCAPE, VK_LEFT, VK_RETURN, VK_RIGHT, VK_SPACE, VK_TAB, VK_UP,
};
use windows::Win32::UI::WindowsAndMessaging::{
    CW_USEDEFAULT, WINDOW_EX_STYLE, WM_APP, WM_CAPTURECHANGED, WM_DESTROY, WM_DPICHANGED,
    WM_ERASEBKGND, WM_GETOBJECT, WM_KEYDOWN, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MOUSEMOVE, WM_PAINT,
    WM_SETTINGCHANGE, WM_SYSCOLORCHANGE, WM_THEMECHANGED, WM_TIMER, WS_CAPTION, WS_MINIMIZEBOX,
    WS_OVERLAPPED, WS_SYSMENU,
};
use windows_core::{w, PCWSTR};

pub const CLASS: PCWSTR = w!("hajime.setup");
/// 実演の次のコマを待つ時計
const DEMO_TIMER: usize = 1;
/// エンジンにつなぎ直す時計
const RECONNECT_TIMER: usize = 2;
/// 読み込みのスレッドが終わった
const WM_LOADED: u32 = WM_APP + 1;

/// 読み上げの要素の番号
const NODE_OPTION: i32 = 1000;
const NODE_TOGGLE: i32 = 2000;
const NODE_BUTTON: i32 = 3000;
const NODE_DEMO: i32 = 4000;

type Model = SettingsModel<Store>;
type Loaded = Arc<Mutex<Option<Option<Model>>>>;

/// 下の帯のボタン
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Button {
    Later,
    Back,
    Next,
    OpenSettings,
    Finish,
}

impl Button {
    fn label(self) -> &'static str {
        match self {
            Button::Later => text::LATER,
            Button::Back => text::BACK,
            Button::Next => text::NEXT,
            Button::OpenSettings => text::OPEN_SETTINGS,
            Button::Finish => text::FINISH,
        }
    }
}

/// 押せるもの
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Target {
    /// group 番目のまとまりの index 番目の選択肢
    Option(usize, usize),
    Toggle(usize),
    Button(Button),
}

/// キーボードで選んでいるもの(選択肢のまとまりは 1 つとして Tab で移る)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Focus {
    Group(usize),
    Button(Button),
}

/// 窓の中の置き場所(DIP)
struct Layout {
    counter: Rect,
    title: Rect,
    description: Rect,
    groups: Vec<GroupLayout>,
    demo: Rect,
    buttons: Vec<(Button, Rect)>,
}

struct GroupLayout {
    group: Group,
    title: Option<Rect>,
    /// 選択肢(Radio)か，オン・オフの行(Toggle．1 つ)
    rows: Vec<Rect>,
}

pub struct Options {
    pub started: Instant,
    pub theme: Option<ForcedTheme>,
    /// 初めに開くページ(見本の撮影)
    pub step: Option<Step>,
    /// エンジンにつながずに見本の値で開く(見本の撮影．値は書かない)
    pub offline: bool,
}

struct Wizard {
    window: Window,
    graphics: Graphics,
    surface: Surface,
    theme: Theme,
    forced_theme: Option<ForcedTheme>,
    mica: bool,
    animations: bool,
    catalog: Catalog,
    connect: fn(&Timing) -> Option<Store>,
    /// エンジンにつながず，見本の値で開いた(書き込まない)
    offline: bool,
    model: Option<Model>,
    loaded: Loaded,
    loading: bool,
    step: Step,
    choices: Choices,
    script: Script,
    /// 実演を始めた時(ミリ秒)
    demo_started: f64,
    today: Today,
    /// ページを替える動き(0 から 1)と向き
    enter: Tween,
    direction: f32,
    /// 進み具合の帯
    progress: Tween,
    focus: Focus,
    focus_visible: bool,
    hover: Option<Target>,
    pressed: Option<Target>,
    error: Option<&'static str>,
    preview: Option<candidate_ui::app::preview::Preview>,
    popup_pixels: Option<(String, PreviewPixels)>,
    started: Instant,
}

thread_local! {
    static WIZARD: RefCell<Option<Wizard>> = const { RefCell::new(None) };
}

fn with_wizard<T>(f: impl FnOnce(&mut Wizard) -> T) -> Option<T> {
    WIZARD.with(|cell| {
        let mut borrowed = cell.try_borrow_mut().ok()?;
        borrowed.as_mut().map(f)
    })
}

/// ウィザードの窓を開く．すでに開いていれば開かない
pub fn open(
    catalog: Catalog,
    connect: fn(&Timing) -> Option<Store>,
    options: Options,
) -> Option<Window> {
    if ffi::window_exists(CLASS) {
        return None;
    }
    ffi::register_class(CLASS, Some(procedure), false);
    let window = ffi::create(
        WINDOW_EX_STYLE::default(),
        CLASS,
        text::WINDOW_TITLE,
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        (CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT),
        None,
        0,
    )?;
    let dpi = ffi::dpi(window);
    let theme = match options.theme {
        Some(forced) => forced.theme(dpi),
        None => Theme::load(dpi),
    };
    let today = Today::from_fields(now_fields());
    let step = options.step.unwrap_or(Step::Welcome);
    let choices = Choices::default();
    let wizard = Wizard {
        window,
        graphics: Graphics::new().ok()?,
        surface: Surface::new(window),
        theme,
        forced_theme: options.theme,
        mica: false,
        animations: ffi::animations_enabled(),
        catalog,
        connect,
        model: None,
        loaded: Arc::new(Mutex::new(None)),
        loading: false,
        step,
        offline: options.offline,
        script: demo::script(step, &choices, today),
        choices,
        demo_started: 0.0,
        today,
        enter: Tween::fixed(1.0),
        direction: 1.0,
        progress: Tween::fixed(progress_of(step)),
        focus: Focus::Button(Button::Next),
        focus_visible: false,
        hover: None,
        pressed: None,
        error: None,
        preview: None,
        popup_pixels: None,
        started: options.started,
    };
    WIZARD.with(|cell| *cell.borrow_mut() = Some(wizard));
    uia::install(uia::Hooks {
        nodes: accessibility_nodes,
        act: accessibility_act,
    });
    with_wizard(|wizard| {
        wizard.apply_theme();
        wizard.fit_window();
        if wizard.offline {
            wizard.choices = Choices::load(&Sample::new());
            wizard.restart_demo();
        } else {
            wizard.start_loading();
        }
    });
    // 最初の 1 枚を描いてから出す(白いコマを見せない)
    ffi::cloak(window, true);
    ffi::show_default(window);
    with_wizard(Wizard::paint);
    ffi::cloak(window, false);
    Some(window)
}

/// エンジンにつながずに開くときの値(見本の撮影)．推奨の無い項目はエンジンの既定と同じにする
struct Sample(serde_json::Value);

impl Sample {
    fn new() -> Self {
        Self(serde_json::json!({
            "inputStyle": "romaji",
            "punctuation": "toutenKuten",
            "liveConversion": true,
            "typoCorrection": "standard",
            "correctionSensitivity": "standard",
            "remembersRejectedCorrections": false,
            "association": true,
            "calculation": true,
            "postalCodeConversion": true,
            "dateConversion": true,
            "theme": "automatic",
        }))
    }
}

impl wizard::Read for Sample {
    fn value(&self, path: &str) -> Option<&serde_json::Value> {
        self.0.get(path)
    }

    fn is_default(&self, _: &str) -> bool {
        true
    }
}

/// 今の UTC の時刻を地方時の年・月・日・時・分・秒にする
fn now_fields() -> [u16; 6] {
    let seconds = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_secs());
    let universal = demo::utc_fields(seconds);
    ffi::local_time(universal).unwrap_or(universal)
}

fn progress_of(step: Step) -> f32 {
    (step.index() + 1) as f32 / Step::ALL.len() as f32
}

impl Wizard {
    fn now(&self) -> f64 {
        self.started.elapsed().as_secs_f64() * 1000.0
    }

    fn duration(&self, milliseconds: f32) -> f64 {
        if self.animations {
            f64::from(milliseconds)
        } else {
            0.0
        }
    }

    fn size(&self) -> (f32, f32) {
        let (width, height) = ffi::client_size(self.window);
        (self.theme.dip(width), self.theme.dip(height))
    }

    /// 中の大きさがトークンの大きさになるよう，窓の大きさを決める
    fn fit_window(&self) {
        let width = self.theme.px(size::WIZARD_WIDTH);
        let height = self.theme.px(size::WIZARD_HEIGHT);
        ffi::resize(self.window, width, height);
        let (client_width, client_height) = ffi::client_size(self.window);
        ffi::resize(
            self.window,
            width * 2 - client_width,
            height * 2 - client_height,
        );
    }

    fn apply_theme(&mut self) {
        ffi::set_dark_title_bar(self.window, self.theme.dark);
        self.mica = ffi::set_mica(self.window, !self.theme.high_contrast);
        self.popup_pixels = None;
    }

    fn reload_theme(&mut self, dpi: u32) {
        self.theme = match self.forced_theme {
            Some(forced) => forced.theme(dpi),
            None => Theme::load(dpi),
        };
        self.animations = ffi::animations_enabled();
        self.apply_theme();
        ffi::invalidate(self.window);
    }

    // MARK: - 読み込み

    fn start_loading(&mut self) {
        if self.loading {
            return;
        }
        self.loading = true;
        let connect = self.connect;
        let catalog = self.catalog.clone();
        let loaded = Arc::clone(&self.loaded);
        let window = self.window.0 as isize;
        let spawned = std::thread::Builder::new()
            .name("setup-loader".into())
            .spawn(move || {
                let model = connect(&catalog.timing)
                    .and_then(|store| SettingsModel::load(store, &catalog).ok());
                if let Ok(mut slot) = loaded.lock() {
                    *slot = Some(model);
                }
                ffi::post(HWND(window as *mut _), WM_LOADED, 0, 0);
            });
        if spawned.is_err() {
            self.loading = false;
        }
    }

    fn finish_loading(&mut self) {
        self.loading = false;
        let Some(model) = self.loaded.lock().ok().and_then(|mut slot| slot.take()) else {
            return;
        };
        match model {
            Some(model) => {
                self.choices = Choices::load(&model);
                self.model = Some(model);
                ffi::kill_timer(self.window, RECONNECT_TIMER);
                self.restart_demo();
            }
            None => {
                let interval = self.catalog.timing.reconnect_interval().as_millis();
                ffi::set_timer(
                    self.window,
                    RECONNECT_TIMER,
                    u32::try_from(interval).unwrap_or(u32::MAX),
                );
            }
        }
        ffi::invalidate(self.window);
    }

    /// 選ぶものを出せるか(エンジンから値を読んだ)
    fn ready(&self) -> bool {
        self.model.is_some() || self.offline
    }

    // MARK: - ページ

    fn restart_demo(&mut self) {
        self.script = demo::script(self.step, &self.choices, self.today);
        self.demo_started = self.now();
        self.popup_pixels = None;
        ffi::kill_timer(self.window, DEMO_TIMER);
        ffi::invalidate(self.window);
    }

    /// 選んだ値をエンジンに書く．書けなければ誤りを出して false
    fn save(&mut self) -> bool {
        let Some(model) = &mut self.model else {
            return true;
        };
        let changes = self.choices.changes(self.step, model);
        if changes.is_empty() {
            return true;
        }
        match model.set_all(&changes) {
            Ok(()) => {
                self.error = None;
                true
            }
            Err(_) => {
                self.error = Some(text::SAVE_FAILED);
                ffi::invalidate(self.window);
                false
            }
        }
    }

    fn go(&mut self, step: Step) {
        let now = self.now();
        self.direction = if step.index() >= self.step.index() {
            1.0
        } else {
            -1.0
        };
        self.step = step;
        self.enter = Tween::new(
            0.0,
            1.0,
            now,
            self.duration(motion::WIZARD_PAGE),
            Easing::DECELERATE,
        );
        self.progress.retarget(
            progress_of(step),
            now,
            self.duration(motion::WIZARD_PAGE),
            Easing::DECELERATE,
        );
        self.hover = None;
        self.focus = Focus::Button(if step == Step::Done {
            Button::Finish
        } else {
            Button::Next
        });
        self.restart_demo();
        uia::focus_changed(self.window, self.focus_node());
    }

    fn activate(&mut self, button: Button) {
        match button {
            Button::Back => {
                if let Some(previous) = self.step.previous() {
                    self.save();
                    self.go(previous);
                }
            }
            Button::Next => {
                if !self.button_enabled(Button::Next) || !self.save() {
                    return;
                }
                if let Some(next) = self.step.next() {
                    self.go(next);
                }
            }
            Button::Later => {
                self.save();
                ffi::destroy(self.window);
            }
            Button::OpenSettings | Button::Finish => {
                self.save();
                if !self.offline {
                    ffi::set_setup_completed();
                }
                if button == Button::OpenSettings {
                    super::launch_settings(&[]);
                }
                ffi::destroy(self.window);
            }
        }
    }

    fn buttons(&self) -> Vec<Button> {
        match self.step {
            Step::Done => vec![Button::Back, Button::OpenSettings, Button::Finish],
            _ => vec![Button::Later, Button::Back, Button::Next],
        }
    }

    fn button_enabled(&self, button: Button) -> bool {
        match button {
            Button::Back => self.step.previous().is_some(),
            // 選ぶもののあるページは，値を読むまで先に進めない
            Button::Next => self.ready() || self.step.groups().is_empty(),
            _ => true,
        }
    }

    fn select(&mut self, group: usize, index: usize) {
        let groups = self.step.groups();
        let Some(group) = groups.get(group) else {
            return;
        };
        if let GroupKind::Radio(choices) = group.kind {
            if let Some((value, _)) = choices.get(index) {
                if self.choices.value(group.field) != *value {
                    self.choices.select(group.field, value);
                    self.restart_demo();
                }
            }
        }
    }

    fn toggle(&mut self, group: usize) {
        let groups = self.step.groups();
        if let Some(Group {
            field: Field::Path(path),
            kind: GroupKind::Toggle,
            ..
        }) = groups.get(group)
        {
            let on = self.choices.is_on(path);
            self.choices.set_toggle(path, !on);
            self.restart_demo();
        }
    }

    fn press(&mut self, target: Target) {
        if !self.ready() && !matches!(target, Target::Button(_)) {
            return;
        }
        match target {
            Target::Option(group, index) => {
                self.focus = Focus::Group(group);
                self.select(group, index);
            }
            Target::Toggle(group) => {
                self.focus = Focus::Group(group);
                self.toggle(group);
            }
            Target::Button(button) => {
                if self.button_enabled(button) {
                    self.activate(button);
                }
            }
        }
    }

    // MARK: - 置き場所

    fn layout(&self) -> Layout {
        let (width, height) = self.size();
        let padding = size::WIZARD_PADDING;
        let measure: &dyn Measure = &self.graphics;
        let x = padding;
        let column = size::WIZARD_TEXT_WIDTH;
        let mut y = size::WIZARD_STEP_BAR + padding;
        let counter = Rect::new(x, y, column, size::NOTE_LINE_HEIGHT);
        y += size::NOTE_LINE_HEIGHT + size::CARD_GAP;
        let title = Rect::new(x, y, column, size::TITLE_HEIGHT);
        y += size::TITLE_HEIGHT;
        let description_height =
            measure.wrapped_height(self.step.description(), TextStyle::Body, column);
        let description = Rect::new(x, y, column, description_height);
        y += description_height + size::SECTION_GAP / 2.0;
        let mut groups = Vec::new();
        for group in self.step.groups() {
            let title = match (group.title, group.kind) {
                (Some(_), GroupKind::Radio(_)) => {
                    let rect = Rect::new(x, y, column, size::SECTION_TITLE_HEIGHT);
                    y += size::SECTION_TITLE_HEIGHT;
                    Some(rect)
                }
                _ => None,
            };
            let mut rows = Vec::new();
            match group.kind {
                GroupKind::Radio(choices) => {
                    let notes = choices
                        .iter()
                        .any(|(value, _)| wizard::choice_note(group.field, value).is_some());
                    // 説明の無い選択肢が多いときは 2 列に並べる
                    let columns = if !notes && choices.len() >= 4 { 2 } else { 1 };
                    let gap = size::WIZARD_OPTION_GAP;
                    if columns == 1 {
                        // 1 列なら，説明のある行だけを高くする
                        for (value, _) in choices {
                            let row_height = if wizard::choice_note(group.field, value).is_some() {
                                size::WIZARD_OPTION_NOTE_HEIGHT
                            } else {
                                size::WIZARD_OPTION_HEIGHT
                            };
                            rows.push(Rect::new(x, y, column, row_height));
                            y += row_height + gap;
                        }
                    } else {
                        let row_height = size::WIZARD_OPTION_HEIGHT;
                        let cell = (column - gap * (columns - 1) as f32) / columns as f32;
                        for index in 0..choices.len() {
                            rows.push(Rect::new(
                                x + (index % columns) as f32 * (cell + gap),
                                y + (index / columns) as f32 * (row_height + gap),
                                cell,
                                row_height,
                            ));
                        }
                        y += choices.len().div_ceil(columns) as f32 * (row_height + gap);
                    }
                }
                GroupKind::Toggle => {
                    let row_height = size::WIZARD_OPTION_NOTE_HEIGHT;
                    rows.push(Rect::new(x, y, column, row_height));
                    y += row_height + size::WIZARD_OPTION_GAP;
                }
            }
            y += size::CONTROL_GAP;
            groups.push(GroupLayout { group, title, rows });
        }
        let footer = height - size::WIZARD_FOOTER_HEIGHT;
        let demo_x = padding * 2.0 + column;
        let demo = Rect::new(
            demo_x,
            size::WIZARD_STEP_BAR + padding,
            (width - padding - demo_x).max(0.0),
            (footer - size::WIZARD_STEP_BAR - padding).max(0.0),
        );
        let button_y = footer + (size::WIZARD_FOOTER_HEIGHT - size::CONTROL_HEIGHT) / 2.0;
        let mut buttons = Vec::new();
        let mut right = width - padding;
        for button in self.buttons().into_iter().rev() {
            let rect = if button == Button::Later {
                Rect::new(padding, button_y, size::BUTTON_WIDTH, size::CONTROL_HEIGHT)
            } else {
                right -= size::BUTTON_WIDTH;
                let rect = Rect::new(right, button_y, size::BUTTON_WIDTH, size::CONTROL_HEIGHT);
                right -= size::CONTROL_GAP;
                rect
            };
            buttons.push((button, rect));
        }
        buttons.reverse();
        Layout {
            counter,
            title,
            description,
            groups,
            demo,
            buttons,
        }
    }

    fn target_at(&self, x: f32, y: f32) -> Option<Target> {
        let layout = self.layout();
        let inside =
            |rect: &Rect| x >= rect.x && x < rect.max_x() && y >= rect.y && y < rect.max_y();
        for (button, rect) in &layout.buttons {
            if inside(rect) {
                return Some(Target::Button(*button));
            }
        }
        for (group_index, group) in layout.groups.iter().enumerate() {
            for (index, rect) in group.rows.iter().enumerate() {
                if inside(rect) {
                    return Some(match group.group.kind {
                        GroupKind::Radio(_) => Target::Option(group_index, index),
                        GroupKind::Toggle => Target::Toggle(group_index),
                    });
                }
            }
        }
        None
    }

    // MARK: - 描く

    /// 実演の今のコマ．動きを減らす設定なら結果のコマ
    fn demo_frame(&self, now: f64) -> Option<(&Frame, Option<demo::Position>)> {
        if !self.animations {
            return self.script.result().map(|frame| (frame, None));
        }
        let position = self.script.position(now - self.demo_started)?;
        self.script
            .frame(position.beat)
            .map(|frame| (frame, Some(position)))
    }

    /// 候補の窓の画像を，今のコマに合わせて作る
    fn update_popup(&mut self, rect: Option<Rect>, now: f64) {
        let Some(rect) = rect else {
            self.popup_pixels = None;
            return;
        };
        let Some((frame, _)) = self.demo_frame(now) else {
            return;
        };
        let Some(popup) = frame.popup.clone() else {
            self.popup_pixels = None;
            return;
        };
        let theme_name = match self.choices.value(Field::Path("theme")) {
            "" => "automatic".to_string(),
            name => name.to_string(),
        };
        let width = u32::try_from(self.theme.px(rect.width)).unwrap_or(0);
        let height = u32::try_from(self.theme.px(rect.height)).unwrap_or(0);
        let key = format!(
            "{:?}|{}|{}|{theme_name}|{}|{}|{width}x{height}",
            self.step, frame.popup_id, self.demo_started, self.theme.dark, self.theme.dpi
        );
        if self
            .popup_pixels
            .as_ref()
            .is_some_and(|(current, _)| *current == key)
        {
            return;
        }
        if self.preview.is_none() {
            self.preview = candidate_ui::app::preview::Preview::new().ok();
        }
        let Some(preview) = &self.preview else { return };
        let look = candidate_ui::theme::SystemLook {
            dark: self.theme.dark,
            accent: None,
            increase_contrast: ffi::high_contrast(),
            backdrop: false,
        };
        let resolved = candidate_ui::theme::ResolvedTheme::resolve(&theme_name, None, &look);
        let font_size = self
            .model
            .as_ref()
            .and_then(|model| model.value("candidateFontSize"))
            .and_then(serde_json::Value::as_f64)
            .map_or(tokens::size::candidate::FONT_SIZE, |size| size as f32);
        let shown = match &popup {
            Popup::Branch(map) => candidate_ui::app::preview::Shown::Branch(map),
            Popup::List(list) => candidate_ui::app::preview::Shown::List(list),
        };
        let request = d2d::PreviewRequest {
            theme: &resolved,
            font_size,
            dark: self.theme.dark,
            scale: self.theme.dpi as f32 / ffi::BASE_DPI as f32,
            background: self.theme.palette.card,
            shown,
            placement: candidate_ui::app::preview::Placement::TopLeft {
                ground: self.theme.palette.card,
            },
        };
        let Some(pixels) = d2d::render_preview(preview, width, height, &request) else {
            return;
        };
        let generation = self
            .popup_pixels
            .as_ref()
            .map_or(1, |(_, pixels)| pixels.generation + 1);
        self.popup_pixels = Some((
            key,
            PreviewPixels {
                generation,
                width,
                height,
                pixels,
            },
        ));
    }

    fn paint(&mut self) {
        let now = self.now();
        let layout = self.layout();
        let popup_rect = popup_rect(
            &layout.demo,
            self.demo_frame(now).map(|(frame, _)| frame),
            &self.graphics,
        );
        self.update_popup(popup_rect, now);
        let theme = self.theme;
        let clear = if self.mica {
            Color::from(theme.palette.background).with_alpha(0.0)
        } else {
            Color::from(theme.palette.background)
        };
        let size = ffi::client_size(self.window);
        // 描き先は描くあいだだけ借りる(ほかの状態は描く関数が読む)
        let mut surface = std::mem::replace(&mut self.surface, Surface::new(self.window));
        let pixels = self.popup_pixels.as_ref().map(|(_, pixels)| pixels);
        let demo = self.demo_frame(now);
        let previous = demo
            .and_then(|(_, position)| position)
            .and_then(|position| position.beat.checked_sub(1))
            .and_then(|beat| self.script.frame(beat));
        let state = PaintState {
            wizard: self,
            layout: &layout,
            now,
            demo,
            previous,
            popup: popup_rect,
        };
        let _ = surface.draw(&self.graphics, size, theme.dpi, clear, pixels, |canvas| {
            paint_window(canvas, &state);
        });
        self.surface = surface;
        self.schedule(now);
    }

    /// 次に描く時を決める．動いているあいだは画面の更新に合わせ，止まっているコマでは次のコマまで時計で待つ
    fn schedule(&self, now: f64) {
        let tweens = self.enter.running(now) || self.progress.running(now);
        let loading = !self.ready() && !self.step.groups().is_empty();
        let demo = self.demo_frame(now);
        let moving = demo.is_some_and(|(frame, position)| {
            let Some(position) = position else {
                return false;
            };
            let changed = frame.mode
                != self
                    .script
                    .frame(position.beat.wrapping_sub(1))
                    .map_or(frame.mode, |previous| previous.mode);
            frame.key.is_some()
                || frame.waiting
                || (position.elapsed < f64::from(motion::FLYOUT)
                    && self.popup_changed(position.beat))
                || (position.elapsed < f64::from(motion::TOGGLE) && changed)
        });
        if tweens || loading || moving {
            ffi::wait_for_compositor();
            ffi::invalidate(self.window);
            return;
        }
        if let Some((_, Some(position))) = demo {
            let wait = position.remaining.ceil().max(1.0) as u32;
            ffi::set_timer(self.window, DEMO_TIMER, wait);
        }
    }

    /// beat で候補の窓が出た・変わったか
    fn popup_changed(&self, beat: usize) -> bool {
        let current = self.script.frame(beat);
        let previous = beat.checked_sub(1).and_then(|beat| self.script.frame(beat));
        match (current, previous) {
            (Some(current), Some(previous)) => {
                current.popup.is_some() && current.popup_id != previous.popup_id
            }
            (Some(current), None) => current.popup.is_some(),
            _ => false,
        }
    }

    // MARK: - キーボード

    fn focusables(&self) -> Vec<Focus> {
        let mut focusables: Vec<Focus> = if self.ready() {
            (0..self.step.groups().len()).map(Focus::Group).collect()
        } else {
            Vec::new()
        };
        focusables.extend(
            self.buttons()
                .into_iter()
                .filter(|button| self.button_enabled(*button))
                .map(Focus::Button),
        );
        focusables
    }

    fn key(&mut self, key: u16) -> bool {
        let groups = self.step.groups();
        match key {
            key if key == VK_TAB.0 => {
                let (_, shift) = ffi::modifiers();
                let focusables = self.focusables();
                if focusables.is_empty() {
                    return true;
                }
                let current = focusables.iter().position(|focus| *focus == self.focus);
                let count = focusables.len();
                let next = match (current, shift) {
                    (Some(index), false) => (index + 1) % count,
                    (Some(index), true) => (index + count - 1) % count,
                    (None, false) => 0,
                    (None, true) => count - 1,
                };
                self.focus = focusables[next];
            }
            key if [VK_UP.0, VK_DOWN.0, VK_LEFT.0, VK_RIGHT.0].contains(&key) => {
                let forward = key == VK_DOWN.0 || key == VK_RIGHT.0;
                match self.focus {
                    Focus::Group(index) => {
                        if let Some(Group {
                            field,
                            kind: GroupKind::Radio(choices),
                            ..
                        }) = groups.get(index)
                        {
                            let current = self.choices.value(*field);
                            let position = choices
                                .iter()
                                .position(|(value, _)| *value == current)
                                .unwrap_or(0);
                            let next = if forward {
                                (position + 1).min(choices.len() - 1)
                            } else {
                                position.saturating_sub(1)
                            };
                            self.select(index, next);
                        }
                    }
                    Focus::Button(_) => {
                        let buttons: Vec<Button> = self
                            .buttons()
                            .into_iter()
                            .filter(|button| self.button_enabled(*button))
                            .collect();
                        if let Some(position) = buttons
                            .iter()
                            .position(|button| Focus::Button(*button) == self.focus)
                        {
                            let next = if forward {
                                (position + 1).min(buttons.len() - 1)
                            } else {
                                position.saturating_sub(1)
                            };
                            self.focus = Focus::Button(buttons[next]);
                        }
                    }
                }
            }
            key if key == VK_SPACE.0 => match self.focus {
                Focus::Group(index) => {
                    if matches!(
                        groups.get(index).map(|group| group.kind),
                        Some(GroupKind::Toggle)
                    ) {
                        self.toggle(index);
                    }
                }
                Focus::Button(button) => self.activate(button),
            },
            key if key == VK_RETURN.0 => match self.focus {
                Focus::Button(button) => self.activate(button),
                // 選択肢の上で Enter なら既定のボタン(次へ・完了)
                Focus::Group(_) => self.activate(if self.step == Step::Done {
                    Button::Finish
                } else {
                    Button::Next
                }),
            },
            key if key == VK_ESCAPE.0 => self.activate(Button::Later),
            _ => return false,
        }
        if WIZARD_ALIVE.with(|alive| alive.get()) {
            self.focus_visible = true;
            uia::focus_changed(self.window, self.focus_node());
            ffi::invalidate(self.window);
        }
        true
    }

    // MARK: - ポインター

    fn point(&self, lparam: LPARAM) -> (f32, f32) {
        let x = (lparam.0 & 0xffff) as i16 as i32;
        let y = ((lparam.0 >> 16) & 0xffff) as i16 as i32;
        (self.theme.dip(x), self.theme.dip(y))
    }

    fn mouse_move(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        let hover = self.target_at(x, y);
        if hover != self.hover {
            self.hover = hover;
            ffi::track_leave(self.window);
            ffi::invalidate(self.window);
        }
    }

    fn mouse_down(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        self.pressed = self.target_at(x, y);
        self.focus_visible = false;
        if self.pressed.is_some() {
            ffi::capture(self.window);
        }
        ffi::invalidate(self.window);
    }

    fn mouse_up(&mut self, lparam: LPARAM) {
        let (x, y) = self.point(lparam);
        let pressed = self.pressed.take();
        ffi::release_capture();
        if let Some(target) = pressed.filter(|target| self.target_at(x, y) == Some(*target)) {
            self.press(target);
        }
        if WIZARD_ALIVE.with(|alive| alive.get()) {
            ffi::invalidate(self.window);
        }
    }

    // MARK: - 読み上げ

    fn focus_node(&self) -> i32 {
        match self.focus {
            Focus::Group(index) => match self.step.groups().get(index).map(|group| group.kind) {
                Some(GroupKind::Radio(choices)) => {
                    let field = self.step.groups()[index].field;
                    let current = self.choices.value(field);
                    let position = choices
                        .iter()
                        .position(|(value, _)| *value == current)
                        .unwrap_or(0);
                    NODE_OPTION + (index * 100 + position) as i32
                }
                _ => NODE_TOGGLE + index as i32,
            },
            Focus::Button(button) => {
                NODE_BUTTON
                    + self
                        .buttons()
                        .iter()
                        .position(|candidate| *candidate == button)
                        .unwrap_or(0) as i32
            }
        }
    }

    fn nodes(&self) -> Vec<uia::Node> {
        let layout = self.layout();
        let focused = self.focus_node();
        let pixels = |rect: &Rect| {
            (
                self.theme.px(rect.x),
                self.theme.px(rect.y),
                self.theme.px(rect.width),
                self.theme.px(rect.height),
            )
        };
        let node = |id: i32, role: uia::Role, name: String, rect: &Rect| uia::Node {
            id,
            role,
            name,
            rect: pixels(rect),
            enabled: true,
            focused: id == focused,
            toggled: None,
            expanded: None,
            value: None,
            selected: None,
            host: None,
        };
        let mut nodes = Vec::new();
        if self.ready() {
            for (index, group) in layout.groups.iter().enumerate() {
                match group.group.kind {
                    GroupKind::Radio(choices) => {
                        let current = self.choices.value(group.group.field);
                        for (position, ((value, label), rect)) in
                            choices.iter().zip(&group.rows).enumerate()
                        {
                            let mut name = (*label).to_string();
                            if wizard::recommended(group.group.field) == Some(value) {
                                name = format!("{name} {}", text::RECOMMENDED);
                            }
                            nodes.push(uia::Node {
                                selected: Some(*value == current),
                                ..node(
                                    NODE_OPTION + (index * 100 + position) as i32,
                                    uia::Role::ListItem,
                                    name,
                                    rect,
                                )
                            });
                        }
                    }
                    GroupKind::Toggle => {
                        if let (Field::Path(path), Some(rect)) =
                            (group.group.field, group.rows.first())
                        {
                            nodes.push(uia::Node {
                                toggled: Some(self.choices.is_on(path)),
                                ..node(
                                    NODE_TOGGLE + index as i32,
                                    uia::Role::CheckBox,
                                    group.group.title.unwrap_or_default().to_string(),
                                    rect,
                                )
                            });
                        }
                    }
                }
            }
        }
        for (position, (button, rect)) in layout.buttons.iter().enumerate() {
            nodes.push(uia::Node {
                enabled: self.button_enabled(*button),
                ..node(
                    NODE_BUTTON + position as i32,
                    uia::Role::Button,
                    button.label().to_string(),
                    rect,
                )
            });
        }
        // 実演は今の説明を名前にする(見本の文字だけで，利用者の入力は含まない)
        let caption = self
            .demo_frame(self.now())
            .and_then(|(frame, _)| frame.caption)
            .unwrap_or(text::DEMO);
        nodes.push(node(
            NODE_DEMO,
            uia::Role::Document,
            format!("{} {caption}", text::DEMO),
            &layout.demo,
        ));
        nodes
    }

    fn accessibility_act(&mut self, id: i32, act: uia::Act) {
        let target = match id {
            id if (NODE_OPTION..NODE_TOGGLE).contains(&id) => {
                let offset = (id - NODE_OPTION) as usize;
                Target::Option(offset / 100, offset % 100)
            }
            id if (NODE_TOGGLE..NODE_BUTTON).contains(&id) => {
                Target::Toggle((id - NODE_TOGGLE) as usize)
            }
            id if (NODE_BUTTON..NODE_DEMO).contains(&id) => {
                match self.buttons().get((id - NODE_BUTTON) as usize) {
                    Some(button) => Target::Button(*button),
                    None => return,
                }
            }
            _ => return,
        };
        match act {
            uia::Act::Focus => {
                self.focus = match target {
                    Target::Option(group, _) | Target::Toggle(group) => Focus::Group(group),
                    Target::Button(button) => Focus::Button(button),
                };
                ffi::invalidate(self.window);
            }
            _ => self.press(target),
        }
    }
}

thread_local! {
    /// 窓がまだあるか(ボタンで窓を閉じたあとに描かない)
    static WIZARD_ALIVE: std::cell::Cell<bool> = const { std::cell::Cell::new(true) };
}

/// 文書の欄の置き場所
fn document_rect(demo: &Rect) -> Rect {
    let padding = size::WIZARD_PADDING * 0.75;
    let y = demo.y + padding + size::WIZARD_MODE_SIZE + size::CONTROL_GAP * 2.0;
    Rect::new(
        demo.x + padding,
        y,
        (demo.width - padding * 2.0).max(0.0),
        size::WIZARD_DEMO_LINE_HEIGHT + size::CONTROL_GAP * 2.0,
    )
}

/// 打っている文字の始まり(確定した文字の後ろ)の x
fn composition_x(frame: &Frame, document: &Rect, measure: &dyn Measure) -> f32 {
    let committed: String = frame
        .runs
        .iter()
        .filter(|run| run.style == Style::Plain)
        .map(|run| run.text.as_str())
        .collect();
    document.x + size::FIELD_PADDING_X + measure.width(&committed, TextStyle::Demo)
}

/// 候補の窓を描く場所．候補の窓を出さないコマは None
fn popup_rect(demo: &Rect, frame: Option<&Frame>, measure: &dyn Measure) -> Option<Rect> {
    let frame = frame?;
    frame.popup.as_ref()?;
    let document = document_rect(demo);
    let padding = size::WIZARD_PADDING * 0.75;
    let minimum = size::CONTROL_WIDTH;
    let x = composition_x(frame, &document, measure)
        .min(demo.max_x() - padding - minimum)
        .max(demo.x + padding);
    let y = document.max_y() + size::CONTROL_GAP;
    let bottom = demo.max_y()
        - padding
        - size::WIZARD_KEYCAP_HEIGHT
        - size::NOTE_LINE_HEIGHT
        - size::CONTROL_GAP * 2.0;
    let width = demo.max_x() - padding - x;
    let height = bottom - y;
    (width > 0.0 && height > 0.0).then(|| Rect::new(x, y, width, height))
}

struct PaintState<'a> {
    wizard: &'a Wizard,
    layout: &'a Layout,
    now: f64,
    demo: Option<(&'a Frame, Option<demo::Position>)>,
    previous: Option<&'a Frame>,
    popup: Option<Rect>,
}

fn paint_window(canvas: &mut dyn Canvas, state: &PaintState) {
    let wizard = state.wizard;
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let (width, height) = wizard.size();
    // 進み具合の帯
    canvas.fill_rect(
        Rect::new(0.0, 0.0, width, size::WIZARD_STEP_BAR),
        Color::from(palette.control_stroke),
    );
    canvas.fill_rect(
        Rect::new(
            0.0,
            0.0,
            width * wizard.progress.value(state.now),
            size::WIZARD_STEP_BAR,
        ),
        Color::from(palette.accent),
    );
    // 下の帯
    let footer = height - size::WIZARD_FOOTER_HEIGHT;
    canvas.fill_rect(
        Rect::new(0.0, footer, width, size::WIZARD_FOOTER_HEIGHT),
        Color::from(palette.card).with_alpha(0.6),
    );
    canvas.fill_rect(
        Rect::new(0.0, footer, width, 1.0),
        Color::from(palette.card_stroke),
    );
    for (button, rect) in &state.layout.buttons {
        let target = Target::Button(*button);
        let kind = match button {
            Button::Next | Button::Finish => ButtonKind::Accent,

            _ => ButtonKind::Standard,
        };
        let control = State {
            enabled: wizard.button_enabled(*button),
            hover: if wizard.hover == Some(target) {
                1.0
            } else {
                0.0
            },
            pressed: wizard.pressed == Some(target),
            focus_visible: wizard.focus_visible && wizard.focus == Focus::Button(*button),
        };
        paint::button(canvas, theme, *rect, button.label(), kind, control);
        if control.focus_visible {
            paint::focus_ring(canvas, theme, *rect, size::CONTROL_RADIUS);
        }
    }
    if let Some(error) = wizard.error {
        let left = state
            .layout
            .buttons
            .iter()
            .find(|(button, _)| *button == Button::Later)
            .map_or(size::WIZARD_PADDING, |(_, rect)| {
                rect.max_x() + size::CONTROL_GAP
            });
        let right = state
            .layout
            .buttons
            .iter()
            .filter(|(button, _)| *button != Button::Later)
            .map(|(_, rect)| rect.x)
            .fold(width, f32::min);
        canvas.text(
            Rect::new(
                left,
                footer,
                (right - left - size::CONTROL_GAP).max(0.0),
                size::WIZARD_FOOTER_HEIGHT,
            ),
            error,
            TextStyle::Caption,
            Color::from(palette.caution),
            TextLayout::LINE,
        );
    }
    // ページを替える動き(横に少し動かしながら濃くする)
    let enter = wizard.enter.value(state.now);
    let offset = (1.0 - enter) * size::PAGE_ENTER_OFFSET * 2.0 * wizard.direction;
    canvas.translate(offset, 0.0);
    canvas.set_opacity(enter);
    paint_text_column(canvas, state);
    paint_demo(canvas, state);
    canvas.set_opacity(1.0);
    canvas.translate(-offset, 0.0);
}

fn paint_text_column(canvas: &mut dyn Canvas, state: &PaintState) {
    let wizard = state.wizard;
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let layout = state.layout;
    let step = wizard.step;
    canvas.text(
        layout.counter,
        &text::step(step.index() + 1, Step::ALL.len()),
        TextStyle::Caption,
        Color::from(palette.text_secondary),
        TextLayout::LINE,
    );
    canvas.text(
        layout.title,
        step.title(),
        TextStyle::Title,
        Color::from(palette.text),
        TextLayout::LINE,
    );
    canvas.text(
        layout.description,
        step.description(),
        TextStyle::Body,
        Color::from(palette.text_secondary),
        TextLayout::WRAP,
    );
    if !wizard.ready() && !layout.groups.is_empty() {
        let y = layout.description.max_y() + size::SECTION_GAP;
        paint::progress_ring(
            canvas,
            theme,
            layout.description.x + size::PROGRESS_RING_SIZE / 2.0,
            y + size::PROGRESS_RING_SIZE / 2.0,
            ((state.now % f64::from(motion::PROGRESS_RING)) / f64::from(motion::PROGRESS_RING))
                as f32,
        );
        canvas.text(
            Rect::new(
                layout.description.x + size::PROGRESS_RING_SIZE + size::CONTROL_GAP,
                y,
                layout.description.width,
                size::PROGRESS_RING_SIZE,
            ),
            text::LOADING,
            TextStyle::Body,
            Color::from(palette.text_secondary),
            TextLayout::LINE,
        );
        return;
    }
    for (index, group) in layout.groups.iter().enumerate() {
        if let (Some(rect), Some(title)) = (group.title, group.group.title) {
            canvas.text(
                rect,
                title,
                TextStyle::Section,
                Color::from(palette.text),
                TextLayout::LINE,
            );
        }
        let focused = wizard.focus_visible && wizard.focus == Focus::Group(index);
        match group.group.kind {
            GroupKind::Radio(choices) => {
                let current = wizard.choices.value(group.group.field);
                for (position, ((value, label), rect)) in
                    choices.iter().zip(&group.rows).enumerate()
                {
                    let selected = *value == current;
                    let target = Target::Option(index, position);
                    paint_option(
                        canvas,
                        theme,
                        *rect,
                        OptionLook {
                            label,
                            note: wizard::choice_note(group.group.field, value),
                            recommended: wizard::recommended(group.group.field) == Some(value),
                            selected,
                            hover: wizard.hover == Some(target),
                            pressed: wizard.pressed == Some(target),
                        },
                    );
                    if focused && selected {
                        paint::focus_ring(canvas, theme, *rect, size::CARD_RADIUS);
                    }
                }
            }
            GroupKind::Toggle => {
                let (Field::Path(path), Some(rect)) = (group.group.field, group.rows.first())
                else {
                    continue;
                };
                let target = Target::Toggle(index);
                let hover = wizard.hover == Some(target);
                let fill = if hover {
                    palette.control_hover
                } else {
                    palette.card
                };
                canvas.fill_round(*rect, size::CARD_RADIUS, Color::from(fill));
                canvas.stroke_round(
                    *rect,
                    size::CARD_RADIUS,
                    1.0,
                    Color::from(palette.card_stroke),
                );
                let inner = Rect::new(
                    rect.x + size::CARD_PADDING_X,
                    rect.y,
                    rect.width
                        - size::CARD_PADDING_X * 2.0
                        - size::TOGGLE_WIDTH
                        - size::CONTROL_GAP,
                    rect.height,
                );
                paint_label(
                    canvas,
                    theme,
                    inner,
                    group.group.title.unwrap_or_default(),
                    toggle_note(path),
                    false,
                );
                let on = wizard.choices.is_on(path);
                paint::toggle(
                    canvas,
                    theme,
                    Rect::new(
                        rect.max_x() - size::CARD_PADDING_X - size::TOGGLE_WIDTH,
                        rect.y,
                        size::TOGGLE_WIDTH,
                        rect.height,
                    ),
                    on,
                    if on { 1.0 } else { 0.0 },
                    crate::strings::windows::ON,
                    crate::strings::windows::OFF,
                    State {
                        enabled: true,
                        hover: if hover { 1.0 } else { 0.0 },
                        pressed: wizard.pressed == Some(target),
                        focus_visible: false,
                    },
                );
                if focused {
                    paint::focus_ring(canvas, theme, *rect, size::CARD_RADIUS);
                }
            }
        }
    }
}

fn toggle_note(path: &str) -> Option<&'static str> {
    match path {
        "remembersRejectedCorrections" => Some(text::REMEMBERS_REJECTED_NOTE),
        "association" => Some(text::ASSOCIATION_NOTE),
        "calculation" => Some(text::CALCULATION_NOTE),
        "postalCodeConversion" => Some(text::POSTAL_CODE_NOTE),
        "dateConversion" => Some(text::DATE_NOTE),
        _ => None,
    }
}

struct OptionLook<'a> {
    label: &'a str,
    note: Option<&'a str>,
    recommended: bool,
    selected: bool,
    hover: bool,
    pressed: bool,
}

/// 選択肢の行(丸・名前・推奨の札・説明)
fn paint_option(canvas: &mut dyn Canvas, theme: &Theme, rect: Rect, look: OptionLook) {
    let palette = &theme.palette;
    let fill = match (look.pressed, look.hover) {
        (true, _) => palette.control_pressed,
        (false, true) => palette.control_hover,
        _ => palette.card,
    };
    canvas.fill_round(rect, size::CARD_RADIUS, Color::from(fill));
    let (stroke, stroke_width) = if look.selected {
        (palette.accent, size::FOCUS_STROKE)
    } else {
        (palette.card_stroke, 1.0)
    };
    canvas.stroke_round(rect, size::CARD_RADIUS, stroke_width, Color::from(stroke));
    // 丸
    let radio = size::WIZARD_RADIO_SIZE;
    let circle = Rect::new(
        rect.x + size::CARD_PADDING_X,
        rect.y + (rect.height - radio) / 2.0,
        radio,
        radio,
    );
    if look.selected {
        canvas.fill_round(circle, radio / 2.0, Color::from(palette.accent));
        let dot = radio * 0.4;
        canvas.fill_round(
            Rect::new(
                circle.x + (radio - dot) / 2.0,
                circle.y + (radio - dot) / 2.0,
                dot,
                dot,
            ),
            dot / 2.0,
            Color::from(palette.accent_text),
        );
    } else {
        canvas.stroke_round(
            circle,
            radio / 2.0,
            1.0,
            Color::from(palette.control_strong_stroke),
        );
    }
    let x = circle.max_x() + size::CONTROL_GAP + size::CARD_GAP;
    let inner = Rect::new(
        x,
        rect.y,
        rect.max_x() - size::CARD_PADDING_X - x,
        rect.height,
    );
    paint_label(
        canvas,
        theme,
        inner,
        look.label,
        look.note,
        look.recommended,
    );
}

/// 名前(と推奨の札)と説明を，行の上下の真ん中に置く
fn paint_label(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    label: &str,
    note: Option<&str>,
    recommended: bool,
) {
    let palette = &theme.palette;
    let line = size::BODY_LINE_HEIGHT;
    let note_height = note.map_or(0.0, |note| {
        canvas
            .wrapped_height(note, TextStyle::Caption, rect.width)
            .min(size::NOTE_LINE_HEIGHT * 2.0)
    });
    let top = rect.y + (rect.height - line - note_height) / 2.0;
    let label_width = canvas.width(label, TextStyle::Body).min(rect.width);
    canvas.text(
        Rect::new(rect.x, top, rect.width, line),
        label,
        TextStyle::Body,
        Color::from(palette.text),
        TextLayout::LINE,
    );
    if recommended {
        let badge_text = canvas.width(text::RECOMMENDED, TextStyle::Caption);
        let badge = Rect::new(
            rect.x + label_width + size::CONTROL_GAP,
            top + 1.0,
            badge_text + size::CONTROL_GAP * 2.0,
            line - 2.0,
        );
        canvas.fill_round(badge, badge.height / 2.0, Color::from(palette.accent));
        canvas.text(
            badge,
            text::RECOMMENDED,
            TextStyle::Caption,
            Color::from(palette.accent_text),
            TextLayout::CENTER,
        );
    }
    if let Some(note) = note {
        canvas.text(
            Rect::new(rect.x, top + line, rect.width, note_height),
            note,
            TextStyle::Caption,
            Color::from(palette.text_secondary),
            TextLayout::WRAP,
        );
    }
}

/// 右の実演
fn paint_demo(canvas: &mut dyn Canvas, state: &PaintState) {
    let wizard = state.wizard;
    let theme = &wizard.theme;
    let palette = &theme.palette;
    let demo = state.layout.demo;
    canvas.fill_round(demo, size::FLYOUT_RADIUS, Color::from(palette.card));
    canvas.stroke_round(
        demo,
        size::FLYOUT_RADIUS,
        1.0,
        Color::from(palette.card_stroke),
    );
    if wizard.step == Step::Done {
        paint_done(canvas, state);
        return;
    }
    let Some((frame, position)) = state.demo else {
        return;
    };
    let padding = size::WIZARD_PADDING * 0.75;
    let progress = position.map_or(1.0, |position| position.progress);
    let elapsed = position.map_or(f64::MAX, |position| position.elapsed);
    // 入力モードの札(変わったら重ねて入れ替える)
    let mode_rect = Rect::new(
        demo.max_x() - padding - size::WIZARD_MODE_SIZE,
        demo.y + padding,
        size::WIZARD_MODE_SIZE,
        size::WIZARD_MODE_SIZE,
    );
    let mode_changed = state
        .previous
        .is_some_and(|previous| previous.mode != frame.mode);
    let swap = if mode_changed {
        (elapsed / f64::from(motion::TOGGLE)).min(1.0) as f32
    } else {
        1.0
    };
    let japanese = frame.mode == Mode::Japanese;
    canvas.fill_round(
        mode_rect,
        size::CONTROL_RADIUS,
        Color::from(if japanese {
            palette.accent
        } else {
            palette.control
        }),
    );
    canvas.stroke_round(
        mode_rect,
        size::CONTROL_RADIUS,
        1.0,
        Color::from(palette.control_stroke),
    );
    canvas.set_opacity(swap);
    canvas.text(
        mode_rect,
        if japanese { "あ" } else { "A" },
        TextStyle::Body,
        Color::from(if japanese {
            palette.accent_text
        } else {
            palette.text
        }),
        TextLayout::CENTER,
    );
    canvas.set_opacity(wizard.enter.value(state.now));
    canvas.text(
        Rect::new(
            demo.x + padding,
            demo.y + padding,
            demo.width - padding * 3.0 - size::WIZARD_MODE_SIZE,
            size::WIZARD_MODE_SIZE,
        ),
        wizard.step.title(),
        TextStyle::Section,
        Color::from(palette.text_secondary),
        TextLayout::LINE,
    );
    // 文書の欄
    let document = document_rect(&demo);
    canvas.fill_round(document, size::CONTROL_RADIUS, Color::from(palette.control));
    canvas.stroke_round(
        document,
        size::CONTROL_RADIUS,
        1.0,
        Color::from(palette.control_stroke),
    );
    let line_top = document.y + size::CONTROL_GAP;
    let line_height = size::WIZARD_DEMO_LINE_HEIGHT;
    let underline_y = line_top + line_height - size::CARD_GAP;
    let mut x = document.x + size::FIELD_PADDING_X;
    canvas.push_clip(document);
    for run in &frame.runs {
        let width = canvas.width(&run.text, TextStyle::Demo);
        canvas.text(
            Rect::new(x, line_top, width + 1.0, line_height),
            &run.text,
            TextStyle::Demo,
            Color::from(palette.text),
            TextLayout::LINE,
        );
        match run.style {
            Style::Plain => {}
            Style::Typing | Style::Converted => canvas.fill_rect(
                Rect::new(x + 1.0, underline_y, (width - 2.0).max(0.0), 1.0),
                Color::from(palette.text),
            ),
            Style::Focused => canvas.fill_rect(
                Rect::new(x + 1.0, underline_y - 1.0, (width - 2.0).max(0.0), 2.5),
                Color::from(palette.accent),
            ),
            Style::Corrected => {
                let dash: f32 = 2.0;
                let mut dash_x = x + 1.0;
                while dash_x < x + width - 1.0 {
                    canvas.fill_rect(
                        Rect::new(dash_x, underline_y, dash.min(x + width - 1.0 - dash_x), 1.5),
                        Color::from(palette.caution),
                    );
                    dash_x += dash * 2.0;
                }
            }
        }
        x += width;
    }
    // 文字の後ろの入力位置
    canvas.fill_rect(
        Rect::new(
            x + 1.0,
            line_top + size::CARD_GAP * 1.5,
            1.5,
            line_height - size::CARD_GAP * 3.0,
        ),
        Color::from(palette.text),
    );
    canvas.pop_clip();
    // ライブ変換が待っている時間の帯
    if frame.waiting {
        let bar = Rect::new(
            document.x,
            document.max_y() + size::CARD_GAP,
            document.width,
            2.0,
        );
        canvas.fill_rect(bar, Color::from(palette.control_stroke));
        canvas.fill_rect(
            Rect::new(bar.x, bar.y, bar.width * progress, bar.height),
            Color::from(palette.accent),
        );
    }
    // 候補の窓(出たときは少しずつ濃くする)
    if let Some(rect) = state.popup {
        let fade = match position {
            Some(position) if wizard.popup_changed(position.beat) => {
                (elapsed / f64::from(motion::FLYOUT)).min(1.0) as f32
            }
            _ => 1.0,
        };
        canvas.set_opacity(fade * wizard.enter.value(state.now));
        canvas.translate(0.0, (1.0 - fade) * -size::CARD_GAP * 2.0);
        canvas.preview(rect);
        canvas.translate(0.0, (1.0 - fade) * size::CARD_GAP * 2.0);
        canvas.set_opacity(wizard.enter.value(state.now));
    }
    // 説明
    let key_top = demo.max_y() - padding - size::WIZARD_KEYCAP_HEIGHT;
    if let Some(caption) = frame.caption {
        canvas.text(
            Rect::new(
                demo.x + padding,
                key_top - size::NOTE_LINE_HEIGHT - size::CONTROL_GAP,
                demo.width - padding * 2.0,
                size::NOTE_LINE_HEIGHT,
            ),
            caption,
            TextStyle::Caption,
            Color::from(palette.text_secondary),
            TextLayout::CENTER,
        );
    }
    // 押しているキー(押し下げてから消える)
    if let Some(label) = frame.key {
        let width = (canvas.width(label, TextStyle::Body) + size::BUTTON_PADDING_X * 2.0)
            .max(size::WIZARD_KEYCAP_MIN_WIDTH);
        let press = (progress / 0.35).min(1.0);
        let fade = 1.0 - ((progress - 0.75) / 0.25).clamp(0.0, 1.0);
        let depth = size::CARD_GAP;
        let cap = Rect::new(
            demo.x + (demo.width - width) / 2.0,
            key_top + depth * press,
            width,
            size::WIZARD_KEYCAP_HEIGHT - depth,
        );
        canvas.set_opacity(fade * wizard.enter.value(state.now));
        canvas.fill_round(
            Rect::new(
                cap.x,
                key_top + depth,
                width,
                size::WIZARD_KEYCAP_HEIGHT - depth,
            ),
            size::CONTROL_RADIUS,
            Color::from(palette.control_strong_stroke),
        );
        canvas.fill_round(
            cap,
            size::CONTROL_RADIUS,
            Color::from(palette.control).mix(Color::from(palette.control_pressed), press),
        );
        canvas.stroke_round(
            cap,
            size::CONTROL_RADIUS,
            1.0,
            Color::from(palette.control_strong_stroke),
        );
        canvas.text(
            cap,
            label,
            TextStyle::Body,
            Color::from(palette.text),
            TextLayout::CENTER,
        );
        canvas.set_opacity(wizard.enter.value(state.now));
    }
}

/// 最後のページ: 大きなチェックの印を広げて出す
fn paint_done(canvas: &mut dyn Canvas, state: &PaintState) {
    let wizard = state.wizard;
    let palette = &wizard.theme.palette;
    let demo = state.layout.demo;
    let grow = wizard.enter.value(state.now);
    let hero = size::WIZARD_HERO_SIZE * (0.6 + 0.4 * grow);
    let circle = Rect::new(
        demo.x + (demo.width - hero) / 2.0,
        demo.y + (demo.height - hero) / 2.0 - size::SECTION_GAP,
        hero,
        hero,
    );
    canvas.fill_round(circle, hero / 2.0, Color::from(palette.accent));
    canvas.text(
        circle,
        wizard.theme.glyphs.check,
        TextStyle::Hero,
        Color::from(palette.accent_text),
        TextLayout::CENTER,
    );
    canvas.text(
        Rect::new(
            demo.x,
            circle.max_y() + size::SECTION_GAP / 2.0,
            demo.width,
            size::TITLE_HEIGHT,
        ),
        text::DONE_TITLE,
        TextStyle::Section,
        Color::from(palette.text),
        TextLayout::CENTER,
    );
}

fn accessibility_nodes() -> Vec<uia::Node> {
    with_wizard(|wizard| wizard.nodes()).unwrap_or_default()
}

fn accessibility_act(id: i32, act: uia::Act) {
    with_wizard(|wizard| wizard.accessibility_act(id, act));
}

fn low_word(value: usize) -> u32 {
    (value & 0xffff) as u32
}

fn high_word(value: usize) -> u32 {
    ((value >> 16) & 0xffff) as u32
}

extern "system" fn procedure(
    window: HWND,
    message: u32,
    wparam: WPARAM,
    lparam: LPARAM,
) -> LRESULT {
    let handled = std::panic::catch_unwind(|| handle(window, message, wparam, lparam));
    match handled {
        Ok(Some(result)) => result,
        _ => ffi::default_procedure(window, message, wparam, lparam),
    }
}

fn handle(window: HWND, message: u32, wparam: WPARAM, lparam: LPARAM) -> Option<LRESULT> {
    match message {
        WM_ERASEBKGND => Some(LRESULT(1)),
        WM_PAINT => {
            // 描く前に済んだことにする(描く中で頼んだ次のフレームを打ち消さない)
            ffi::validate(window);
            with_wizard(Wizard::paint);
            Some(LRESULT(0))
        }
        WM_LOADED => {
            with_wizard(Wizard::finish_loading);
            Some(LRESULT(0))
        }
        WM_TIMER if wparam.0 == DEMO_TIMER => {
            ffi::kill_timer(window, DEMO_TIMER);
            ffi::invalidate(window);
            Some(LRESULT(0))
        }
        WM_TIMER if wparam.0 == RECONNECT_TIMER => {
            ffi::kill_timer(window, RECONNECT_TIMER);
            with_wizard(Wizard::start_loading);
            Some(LRESULT(0))
        }
        WM_MOUSEMOVE => {
            with_wizard(|wizard| wizard.mouse_move(lparam));
            Some(LRESULT(0))
        }
        WM_MOUSELEAVE => {
            with_wizard(|wizard| {
                wizard.hover = None;
                ffi::invalidate(wizard.window);
            });
            Some(LRESULT(0))
        }
        WM_LBUTTONDOWN => {
            with_wizard(|wizard| wizard.mouse_down(lparam));
            Some(LRESULT(0))
        }
        WM_LBUTTONUP => {
            with_wizard(|wizard| wizard.mouse_up(lparam));
            Some(LRESULT(0))
        }
        WM_CAPTURECHANGED => {
            with_wizard(|wizard| wizard.pressed = None);
            None
        }
        WM_KEYDOWN => {
            let key = low_word(wparam.0) as u16;
            with_wizard(|wizard| wizard.key(key))
                .unwrap_or(false)
                .then_some(LRESULT(0))
        }
        WM_SETTINGCHANGE | WM_SYSCOLORCHANGE | WM_THEMECHANGED => {
            with_wizard(|wizard| wizard.reload_theme(wizard.theme.dpi));
            None
        }
        WM_DPICHANGED => {
            let dpi = high_word(wparam.0);
            with_wizard(|wizard| wizard.reload_theme(dpi));
            if let Some((x, y, width, height)) = ffi::suggested_rect(lparam) {
                ffi::place(window, x, y, width, height);
            }
            Some(LRESULT(0))
        }
        WM_GETOBJECT => uia::get_object(window, wparam, lparam),
        WM_DESTROY => {
            WIZARD_ALIVE.with(|alive| alive.set(false));
            uia::disconnect(window);
            ffi::kill_timer(window, DEMO_TIMER);
            ffi::kill_timer(window, RECONNECT_TIMER);
            // 借りている途中(ボタンで閉じた)なら，手続きを返したあとに片付ける
            WIZARD.with(|cell| {
                if let Ok(mut wizard) = cell.try_borrow_mut() {
                    wizard.take();
                }
            });
            ffi::quit();
            Some(LRESULT(0))
        }
        _ => None,
    }
}
