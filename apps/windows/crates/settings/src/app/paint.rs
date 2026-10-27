#![forbid(unsafe_code)]

//! 描く道具(Canvas)と，部品の形(ボタン・入力欄の枠・ドロップダウン・トグル・フォーカスの印・読み込み中の輪)．
//! 座標は 96dpi の 1 ピクセルを 1 とする(Direct2D の DIP)．Canvas の中身は ffi::d2d が受け持つ

use super::theme::{Color, Theme};
use crate::layout::Rect;
use tokens::size::settings_windows as size;

/// 文字の種類(書体と大きさと太さ)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum TextStyle {
    /// ページの題
    Title,
    /// 節の題
    Section,
    Body,
    Caption,
    /// 左の一覧の見出し
    NavHeader,
    /// 絵の書体(Segoe Fluent Icons)の大きさ
    Icon,
    /// 小さい絵(山形の印・チェック)
    IconSmall,
    /// 初期設定ウィザードの実演の文書の文字
    Demo,
    /// 初期設定ウィザードの最初と最後のページの大きな絵
    Hero,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Align {
    Leading,
    Center,
    Trailing,
}

/// 文字の置き方
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TextLayout {
    pub align: Align,
    /// 折り返す(しなければ 1 行にして，はみ出したら「…」にする)
    pub wrap: bool,
    /// 上下の真ん中に置く(しなければ上に寄せる)
    pub center: bool,
}

impl TextLayout {
    pub const LINE: TextLayout = TextLayout {
        align: Align::Leading,
        wrap: false,
        center: true,
    };
    pub const CENTER: TextLayout = TextLayout {
        align: Align::Center,
        wrap: false,
        center: true,
    };
    pub const TRAILING: TextLayout = TextLayout {
        align: Align::Trailing,
        wrap: false,
        center: true,
    };
    pub const WRAP: TextLayout = TextLayout {
        align: Align::Leading,
        wrap: true,
        center: false,
    };
}

/// 文字の大きさを測る
pub trait Measure {
    /// 1 行にしたときの幅
    fn width(&self, text: &str, style: TextStyle) -> f32;
    /// width で折り返したときの高さ
    fn wrapped_height(&self, text: &str, style: TextStyle, width: f32) -> f32;
}

pub trait Canvas: Measure {
    fn fill_rect(&mut self, rect: Rect, color: Color);
    fn fill_round(&mut self, rect: Rect, radius: f32, color: Color);
    /// 角の丸い枠．線は rect の内側に描く
    fn stroke_round(&mut self, rect: Rect, radius: f32, width: f32, color: Color);
    fn text(&mut self, rect: Rect, text: &str, style: TextStyle, color: Color, layout: TextLayout);
    fn arc(&mut self, arc: Arc, color: Color);
    /// 外観の見本の画像を rect に描く(作れなければ何もしない)
    fn preview(&mut self, rect: Rect);
    /// rect の外に描かないようにする(pop_clip と対にする)
    fn push_clip(&mut self, rect: Rect);
    fn pop_clip(&mut self);
    /// これから描くものを (dx, dy) ずらす(元に戻すときは -dx, -dy を足す)
    fn translate(&mut self, dx: f32, dy: f32);
    /// これから描くものの濃さ(0〜1)
    fn set_opacity(&mut self, opacity: f32);
}

/// 円弧．中心 (x, y)・半径 radius．start と sweep は角度(度．時計回り，上が 0)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Arc {
    pub x: f32,
    pub y: f32,
    pub radius: f32,
    pub start: f32,
    pub sweep: f32,
    pub width: f32,
}

/// 部品の状態(色を決める)
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct State {
    pub enabled: bool,
    /// ポインターを載せている(0〜1 の動き)
    pub hover: f32,
    pub pressed: bool,
    /// キーボードで選んでいて，印を出す
    pub focus_visible: bool,
}

impl State {
    pub fn enabled() -> Self {
        Self {
            enabled: true,
            ..Default::default()
        }
    }
}

/// ボタンの種類
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ButtonKind {
    Standard,
    /// 主な操作(アクセントの色)
    Accent,
    /// 地の無い小さいボタン(既定に戻す)
    Subtle,
}

fn mix(a: Color, b: Color, t: f32) -> Color {
    a.mix(b, t)
}

/// キーボードで選んでいる部品の印(部品の外側の 2 本の線．WinUI のフォーカスの印と同じ)
pub fn focus_ring(canvas: &mut dyn Canvas, theme: &Theme, rect: Rect, radius: f32) {
    let stroke = size::FOCUS_STROKE;
    let outer = Rect::new(
        rect.x - stroke - 1.0,
        rect.y - stroke - 1.0,
        rect.width + (stroke + 1.0) * 2.0,
        rect.height + (stroke + 1.0) * 2.0,
    );
    canvas.stroke_round(outer, radius + stroke + 1.0, stroke, theme.focus_outer());
    let inner = Rect::new(
        rect.x - 1.0,
        rect.y - 1.0,
        rect.width + 2.0,
        rect.height + 2.0,
    );
    canvas.stroke_round(inner, radius + 1.0, 1.0, theme.focus_inner());
}

/// ボタン
pub fn button(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    label: &str,
    kind: ButtonKind,
    state: State,
) {
    let palette = &theme.palette;
    let radius = size::CONTROL_RADIUS;
    let (fill, text) = match (kind, state.enabled) {
        (ButtonKind::Accent, true) => {
            let base = Color::from(palette.accent);
            let fill = if state.pressed {
                Color::from(palette.accent_pressed)
            } else {
                mix(base, Color::from(palette.accent_hover), state.hover)
            };
            (fill, Color::from(palette.accent_text))
        }
        (ButtonKind::Accent, false) => (
            Color::from(palette.control_strong_stroke).with_alpha(0.35),
            Color::from(palette.text_disabled),
        ),
        (ButtonKind::Standard, enabled) => {
            let base = Color::from(palette.control);
            let fill = if state.pressed && enabled {
                Color::from(palette.control_pressed)
            } else {
                mix(base, Color::from(palette.control_hover), state.hover)
            };
            let text = if enabled {
                palette.text
            } else {
                palette.text_disabled
            };
            (fill, Color::from(text))
        }
        (ButtonKind::Subtle, enabled) => {
            let fill = if state.pressed && enabled {
                Color::from(palette.nav_pressed)
            } else {
                Color::from(palette.nav_hover).with_alpha(state.hover)
            };
            let text = if enabled {
                palette.accent
            } else {
                palette.text_disabled
            };
            (fill, Color::from(text))
        }
    };
    canvas.fill_round(rect, radius, fill);
    if kind == ButtonKind::Standard {
        canvas.stroke_round(rect, radius, 1.0, Color::from(palette.control_stroke));
    }
    let style = if kind == ButtonKind::Subtle {
        TextStyle::Icon
    } else {
        TextStyle::Body
    };
    canvas.text(rect, label, style, text, TextLayout::CENTER);
    if state.focus_visible {
        focus_ring(canvas, theme, rect, radius);
    }
}

/// 入力欄の枠(中の文字は標準の EDIT が描く)．フォーカスがあれば下にアクセントの太い線を引く
pub fn field_frame(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    focused: bool,
    state: State,
) {
    let palette = &theme.palette;
    let radius = size::CONTROL_RADIUS;
    let fill = if focused {
        Color::from(palette.control)
    } else {
        mix(
            Color::from(palette.control),
            Color::from(palette.control_hover),
            state.hover,
        )
    };
    canvas.fill_round(rect, radius, fill);
    canvas.stroke_round(rect, radius, 1.0, Color::from(palette.control_stroke));
    // 下の線は角の丸みの内側だけに引く
    let (line, color) = if focused {
        (size::FOCUS_STROKE, Color::from(palette.accent))
    } else {
        (1.0, Color::from(palette.control_strong_stroke))
    };
    canvas.push_clip(Rect::new(rect.x, rect.max_y() - line, rect.width, line));
    canvas.fill_round(rect, radius, color);
    canvas.pop_clip();
    if !state.enabled {
        canvas.fill_round(
            rect,
            radius,
            Color::from(palette.background).with_alpha(0.4),
        );
    }
}

/// 閉じたドロップダウン(選んでいる名前と山形の印)
pub fn dropdown(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    label: &str,
    open: bool,
    state: State,
) {
    let palette = &theme.palette;
    let radius = size::CONTROL_RADIUS;
    let fill = if (state.pressed || open) && state.enabled {
        Color::from(palette.control_pressed)
    } else {
        mix(
            Color::from(palette.control),
            Color::from(palette.control_hover),
            state.hover,
        )
    };
    canvas.fill_round(rect, radius, fill);
    canvas.stroke_round(rect, radius, 1.0, Color::from(palette.control_stroke));
    let text = if state.enabled {
        palette.text
    } else {
        palette.text_disabled
    };
    let padding = size::FIELD_PADDING_X;
    let chevron = size::CHEVRON_SIZE;
    let label_rect = Rect::new(
        rect.x + padding,
        rect.y,
        (rect.width - padding * 3.0 - chevron).max(0.0),
        rect.height,
    );
    canvas.text(
        label_rect,
        label,
        TextStyle::Body,
        Color::from(text),
        TextLayout::LINE,
    );
    let chevron_rect = Rect::new(
        rect.max_x() - padding - chevron,
        rect.y,
        chevron,
        rect.height,
    );
    let secondary = if state.enabled {
        palette.text_secondary
    } else {
        palette.text_disabled
    };
    canvas.text(
        chevron_rect,
        theme.glyphs.chevron_down,
        TextStyle::IconSmall,
        Color::from(secondary),
        TextLayout::CENTER,
    );
    if state.focus_visible {
        focus_ring(canvas, theme, rect, radius);
    }
}

/// トグルスイッチ．progress はつまみの位置(0 はオフ，1 はオン)．左に「オン」「オフ」を書く
#[allow(clippy::too_many_arguments)]
pub fn toggle(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    on: bool,
    progress: f32,
    on_label: &str,
    off_label: &str,
    state: State,
) {
    let palette = &theme.palette;
    let width = size::SWITCH_WIDTH;
    let height = size::SWITCH_HEIGHT;
    let switch = Rect::new(
        rect.max_x() - width,
        rect.y + (rect.height - height) / 2.0,
        width,
        height,
    );
    let off_fill = mix(
        Color::from(palette.control).with_alpha(0.0),
        Color::from(palette.control_hover),
        state.hover,
    );
    let on_fill = if state.enabled {
        mix(
            Color::from(palette.accent),
            Color::from(palette.accent_hover),
            state.hover,
        )
    } else {
        Color::from(palette.text_disabled)
    };
    let fill = mix(off_fill, on_fill, progress);
    canvas.fill_round(switch, height / 2.0, fill);
    if progress < 1.0 {
        let stroke = if state.enabled {
            palette.switch_off
        } else {
            palette.text_disabled
        };
        canvas.stroke_round(
            switch,
            height / 2.0,
            1.0,
            Color::from(stroke).with_alpha(1.0 - progress),
        );
    }
    // つまみはオフで小さく，オンで少し大きい(WinUI と同じ)
    let knob_off = height * 0.6;
    let knob_on = height * 0.7;
    let knob = knob_off + (knob_on - knob_off) * progress;
    let knob = if state.pressed && state.enabled {
        knob + 2.0
    } else {
        knob
    };
    let inset = (height - knob) / 2.0;
    let travel = width - height;
    let left = switch.x + (height - knob) / 2.0 + travel * progress;
    let off_knob = if state.enabled {
        palette.switch_off
    } else {
        palette.text_disabled
    };
    let knob_color = mix(
        Color::from(off_knob),
        Color::from(palette.accent_text),
        progress,
    );
    canvas.fill_round(
        Rect::new(left, switch.y + inset, knob, knob),
        knob / 2.0,
        knob_color,
    );
    let text = if state.enabled {
        palette.text
    } else {
        palette.text_disabled
    };
    let label_rect = Rect::new(
        rect.x,
        rect.y,
        (rect.width - width - size::CONTROL_GAP * 1.5).max(0.0),
        rect.height,
    );
    canvas.text(
        label_rect,
        if on { on_label } else { off_label },
        TextStyle::Body,
        Color::from(text),
        TextLayout::TRAILING,
    );
    if state.focus_visible {
        focus_ring(canvas, theme, switch, height / 2.0);
    }
}

/// 読み込み中の輪(回る円弧)．phase は 0〜1 の回った割合
pub fn progress_ring(canvas: &mut dyn Canvas, theme: &Theme, x: f32, y: f32, phase: f32) {
    let radius = (size::PROGRESS_RING_SIZE - size::PROGRESS_RING_STROKE) / 2.0;
    // 円弧の長さも伸び縮みさせる(WinUI の ProgressRing と同じ見え方)
    let stretch = (phase * std::f32::consts::TAU).sin().abs();
    let sweep = 60.0 + 200.0 * stretch;
    let start = phase * 720.0;
    canvas.arc(
        Arc {
            x,
            y,
            radius,
            start,
            sweep,
            width: size::PROGRESS_RING_STROKE,
        },
        Color::from(theme.palette.accent),
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::theme::Theme;

    /// 描いたものを覚えるだけの Canvas
    #[derive(Default)]
    pub struct Recorder {
        pub rounds: Vec<(Rect, Color)>,
        pub texts: Vec<(String, Color)>,
        pub strokes: usize,
        opacity: f32,
    }

    impl Measure for Recorder {
        fn width(&self, text: &str, _: TextStyle) -> f32 {
            text.chars().count() as f32 * 10.0
        }
        fn wrapped_height(&self, _: &str, _: TextStyle, _: f32) -> f32 {
            20.0
        }
    }

    impl Canvas for Recorder {
        fn fill_rect(&mut self, rect: Rect, color: Color) {
            self.rounds.push((rect, color));
        }
        fn fill_round(&mut self, rect: Rect, _: f32, color: Color) {
            self.rounds.push((rect, color));
        }
        fn stroke_round(&mut self, _: Rect, _: f32, _: f32, _: Color) {
            self.strokes += 1;
        }
        fn text(&mut self, _: Rect, text: &str, _: TextStyle, color: Color, _: TextLayout) {
            self.texts.push((text.to_string(), color));
        }
        fn arc(&mut self, _: Arc, _: Color) {}
        fn preview(&mut self, _: Rect) {}
        fn push_clip(&mut self, _: Rect) {}
        fn pop_clip(&mut self) {}
        fn translate(&mut self, _: f32, _: f32) {}
        fn set_opacity(&mut self, opacity: f32) {
            self.opacity = opacity;
        }
    }

    fn theme() -> Theme {
        Theme::fixed(false, 96)
    }

    #[test]
    fn トグルのつまみはオンで右に寄る() {
        let theme = theme();
        let rect = Rect::new(0.0, 0.0, 96.0, 32.0);
        let knob_left = |progress: f32| {
            let mut canvas = Recorder::default();
            toggle(
                &mut canvas,
                &theme,
                rect,
                progress > 0.5,
                progress,
                "オン",
                "オフ",
                State::enabled(),
            );
            // 最後に塗った丸がつまみ
            canvas.rounds.last().unwrap().0.x
        };
        assert!(knob_left(1.0) > knob_left(0.0));
        let middle = knob_left(0.5);
        assert!(middle > knob_left(0.0) && middle < knob_left(1.0));
    }

    #[test]
    fn 使えない部品は弱い文字の色で描く() {
        let theme = theme();
        let mut canvas = Recorder::default();
        let state = State {
            enabled: false,
            ..Default::default()
        };
        dropdown(
            &mut canvas,
            &theme,
            Rect::new(0.0, 0.0, 200.0, 32.0),
            "ローマ字入力",
            false,
            state,
        );
        let label = canvas
            .texts
            .iter()
            .find(|(text, _)| text == "ローマ字入力")
            .unwrap();
        assert_eq!(label.1, Color::from(theme.palette.text_disabled));
    }

    #[test]
    fn フォーカスの印は見えるときだけ描く() {
        let theme = theme();
        let rect = Rect::new(0.0, 0.0, 100.0, 32.0);
        let mut plain = Recorder::default();
        button(
            &mut plain,
            &theme,
            rect,
            "追加",
            ButtonKind::Standard,
            State::enabled(),
        );
        let mut focused = Recorder::default();
        let state = State {
            focus_visible: true,
            ..State::enabled()
        };
        button(
            &mut focused,
            &theme,
            rect,
            "追加",
            ButtonKind::Standard,
            state,
        );
        assert_eq!(focused.strokes, plain.strokes + 2);
    }
}
