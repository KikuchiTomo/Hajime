#![forbid(unsafe_code)]

//! 描く道具(Canvas)と，部品の形(ボタン・入力欄の枠・ドロップダウン・トグル・フォーカスの印・読み込み中の輪)．
//! 座標は 96dpi の 1 ピクセルを 1 とする(Direct2D の DIP)．Canvas の中身は ffi::d2d が受け持つ

use super::theme::{Color, Theme};
use crate::layout::Rect;
use tokens::opacity::settings_windows as opacity;
use tokens::size::part;
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
    /// 初期設定の実演の入力欄の文字
    Demo,
    /// 等幅の小さい文字(ライセンスの全文)
    Mono,
    /// 本文の大きさの等幅の文字(一覧の表の打つもの．macOS の表の monospaced)
    Code,
    /// 情報のページの製品名(WinUI の Subtitle)
    Subtitle,
    /// テーマの見本の文字
    Swatch,
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
    /// 1 行目の上端からベースラインまで(書体の違う文字をベースラインでそろえる)
    fn baseline(&self, text: &str, style: TextStyle) -> f32;
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
    /// slot 番目の画像を (x, y) を左上にして等倍で描く(初期設定の実演．作れなければ何もしない)
    fn preview_at(&mut self, slot: usize, x: f32, y: f32) {
        let _ = (slot, x, y);
    }
    /// area の中に，(x, y) を中心に半径 radius まで color から透明へにじませる(初期設定の実演の舞台)
    fn radial_glow(&mut self, area: Rect, x: f32, y: f32, radius: f32, color: Color) {
        let _ = (area, x, y, radius, color);
    }
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
    /// 背景の無い小さいボタン(既定に戻す)
    Subtle,
    /// 消す・戻す操作のボタン(背景はふつうのボタンと同じで，文字を危険の色にする)
    Destructive,
    /// 背景の無い小さい絵のボタン(数を 1 段ずつ変える)．絵は文字の色
    Quiet,
    /// 背景と枠のある絵だけのボタン(除外設定の優先度を上げる・下げる)．背景はふつうのボタンと同じ
    Icon,
}

/// 省いたところに入れる字
const ELLIPSIS: char = '\u{2026}';

/// width に収まらない文字を，真ん中を「…」にして縮める(macOS の truncationMode(.middle)．長いパスの両端を残す)
pub fn truncate_middle(
    measure: &(impl Measure + ?Sized),
    text: &str,
    style: TextStyle,
    width: f32,
) -> String {
    if measure.width(text, style) <= width {
        return text.to_string();
    }
    let chars: Vec<char> = text.chars().collect();
    // 残す字を 1 つずつ減らし，収まったところで止める(前を 1 字多く残す)
    for kept in (0..chars.len()).rev() {
        let head = kept.div_ceil(2);
        let tail = kept - head;
        let candidate: String = chars[..head]
            .iter()
            .chain(std::iter::once(&ELLIPSIS))
            .chain(&chars[chars.len() - tail..])
            .collect();
        if measure.width(&candidate, style) <= width {
            return candidate;
        }
    }
    ELLIPSIS.to_string()
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
    let line = part::STROKE;
    let inner = Rect::new(
        rect.x - line,
        rect.y - line,
        rect.width + line * 2.0,
        rect.height + line * 2.0,
    );
    canvas.stroke_round(inner, radius + line, line, theme.focus_inner());
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
            Color::from(palette.control_strong_stroke).with_alpha(opacity::ACCENT_DISABLED),
            Color::from(palette.text_disabled),
        ),
        (ButtonKind::Standard | ButtonKind::Destructive | ButtonKind::Icon, enabled) => {
            let base = Color::from(palette.control);
            let fill = if state.pressed && enabled {
                Color::from(palette.control_pressed)
            } else {
                mix(base, Color::from(palette.control_hover), state.hover)
            };
            let text = match (kind, enabled) {
                (_, false) => palette.text_disabled,
                (ButtonKind::Destructive, true) => palette.danger,
                _ => palette.text,
            };
            (fill, Color::from(text))
        }
        (ButtonKind::Quiet, enabled) => {
            let fill = if state.pressed && enabled {
                Color::from(palette.nav_pressed)
            } else {
                Color::from(palette.nav_hover).with_alpha(state.hover)
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
    if matches!(
        kind,
        ButtonKind::Standard | ButtonKind::Destructive | ButtonKind::Icon
    ) {
        canvas.stroke_round(rect, radius, 1.0, Color::from(palette.control_stroke));
    }
    let style = match kind {
        ButtonKind::Subtle => TextStyle::Icon,
        ButtonKind::Quiet | ButtonKind::Icon => TextStyle::IconSmall,
        _ => TextStyle::Body,
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
            Color::from(palette.background).with_alpha(opacity::DISABLED_OVERLAY),
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
    // 右の端に開く印を置き，印と名前のあいだにも同じ余白をとる
    let chevron_left = rect.max_x() - padding - chevron;
    let label_rect = Rect::new(
        rect.x + padding,
        rect.y,
        (chevron_left - padding - (rect.x + padding)).max(0.0),
        rect.height,
    );
    canvas.text(
        label_rect,
        label,
        TextStyle::Body,
        Color::from(text),
        TextLayout::LINE,
    );
    let chevron_rect = Rect::new(chevron_left, rect.y, chevron, rect.height);
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
    let knob_off = size::SWITCH_KNOB_OFF;
    let knob_on = size::SWITCH_KNOB_ON;
    let knob = knob_off + (knob_on - knob_off) * progress;
    let knob = if state.pressed && state.enabled {
        knob + size::SWITCH_KNOB_PRESSED
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
        (rect.width - width - size::CONTROL_GAP).max(0.0),
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

/// スライダー(WinUI の Slider)．progress は値の位置(0〜1)．溝の左を値までアクセントの色で塗り，丸いつまみを置く
pub fn slider(canvas: &mut dyn Canvas, theme: &Theme, rect: Rect, progress: f32, state: State) {
    let palette = &theme.palette;
    let thumb = size::SLIDER_THUMB_SIZE;
    let track = size::SLIDER_TRACK_HEIGHT;
    let middle = rect.y + rect.height / 2.0;
    let left = rect.x + thumb / 2.0;
    let width = (rect.width - thumb).max(0.0);
    let x = left + width * progress.clamp(0.0, 1.0);
    let rest = if state.enabled {
        Color::from(palette.control_strong_stroke)
    } else {
        Color::from(palette.text_disabled).with_alpha(opacity::SLIDER_TRACK_DISABLED)
    };
    canvas.fill_round(
        Rect::new(left, middle - track / 2.0, width, track),
        track / 2.0,
        rest,
    );
    let fill = if state.enabled {
        Color::from(palette.accent)
    } else {
        Color::from(palette.text_disabled)
    };
    canvas.fill_round(
        Rect::new(left, middle - track / 2.0, x - left, track),
        track / 2.0,
        fill,
    );
    let outer = Rect::new(x - thumb / 2.0, middle - thumb / 2.0, thumb, thumb);
    canvas.fill_round(outer, thumb / 2.0, Color::from(palette.control));
    canvas.stroke_round(outer, thumb / 2.0, 1.0, Color::from(palette.control_stroke));
    let inner = if state.pressed && state.enabled {
        size::SLIDER_THUMB_INNER
    } else {
        size::SLIDER_THUMB_INNER
            + (size::SLIDER_THUMB_INNER_HOVER - size::SLIDER_THUMB_INNER) * state.hover
    };
    canvas.fill_round(
        Rect::new(x - inner / 2.0, middle - inner / 2.0, inner, inner),
        inner / 2.0,
        fill,
    );
    if state.focus_visible {
        focus_ring(canvas, theme, outer, thumb / 2.0);
    }
}

/// 数を 1 段ずつ変える部品の枠と値(ボタンは呼ぶ側が button の Quiet で描く)．値は左に寄せる
pub fn stepper_frame(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    value: &str,
    enabled: bool,
) {
    let palette = &theme.palette;
    let radius = size::CONTROL_RADIUS;
    canvas.fill_round(rect, radius, Color::from(palette.control));
    canvas.stroke_round(rect, radius, 1.0, Color::from(palette.control_stroke));
    let text = if enabled {
        palette.text
    } else {
        palette.text_disabled
    };
    let buttons = size::STEPPER_BUTTON_WIDTH * 2.0;
    canvas.text(
        Rect::new(
            rect.x + size::FIELD_PADDING_X,
            rect.y,
            (rect.width - size::FIELD_PADDING_X - buttons).max(0.0),
            rect.height,
        ),
        value,
        TextStyle::Body,
        Color::from(text),
        TextLayout::LINE,
    );
}

/// 選ぶ印(ラジオボタン．WinUI の RadioButton)．選んでいれば背景をアクセントの色にし，真ん中に点を置く
pub fn radio(canvas: &mut dyn Canvas, theme: &Theme, rect: Rect, selected: bool, state: State) {
    let palette = &theme.palette;
    let radius = rect.width / 2.0;
    if selected {
        let fill = if state.enabled {
            mix(
                Color::from(palette.accent),
                Color::from(palette.accent_hover),
                state.hover,
            )
        } else {
            Color::from(palette.text_disabled)
        };
        canvas.fill_round(rect, radius, fill);
        let dot = size::RADIO_DOT;
        canvas.fill_round(
            Rect::new(
                rect.x + (rect.width - dot) / 2.0,
                rect.y + (rect.height - dot) / 2.0,
                dot,
                dot,
            ),
            dot / 2.0,
            Color::from(palette.accent_text),
        );
    } else {
        let fill = mix(
            Color::from(palette.control),
            Color::from(palette.control_hover),
            state.hover,
        );
        canvas.fill_round(rect, radius, fill);
        let stroke = if state.enabled {
            palette.switch_off
        } else {
            palette.text_disabled
        };
        canvas.stroke_round(rect, radius, 1.0, Color::from(stroke));
    }
}

/// 一覧を切り替える部品の 1 つの欄．選んだ欄は背景を付け，下にアクセントの色の短い線を引く(WinUI の SelectorBar)
pub fn segment(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    rect: Rect,
    label: &str,
    selected: bool,
    state: State,
) {
    let palette = &theme.palette;
    let radius = size::CONTROL_RADIUS;
    // 選んだところは溝の中で浮かせたタグにする(macOS の segmented の Picker)．ほかはポインターを載せたときだけ薄く塗る
    let inset = size::SEGMENT_INSET;
    let face = Rect::new(
        rect.x + inset,
        rect.y + inset,
        (rect.width - inset * 2.0).max(0.0),
        (rect.height - inset * 2.0).max(0.0),
    );
    if selected {
        canvas.fill_round(face, radius, Color::from(palette.control));
        canvas.stroke_round(face, radius, 1.0, Color::from(palette.control_stroke));
    } else if state.pressed {
        canvas.fill_round(face, radius, Color::from(palette.nav_pressed));
    } else {
        canvas.fill_round(
            face,
            radius,
            Color::from(palette.nav_hover).with_alpha(state.hover),
        );
    }
    let text = if selected {
        palette.text
    } else {
        palette.text_secondary
    };
    canvas.text(
        rect,
        label,
        TextStyle::Body,
        Color::from(text),
        TextLayout::CENTER,
    );
    if state.focus_visible {
        focus_ring(canvas, theme, rect, radius);
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
        fn baseline(&self, _: &str, _: TextStyle) -> f32 {
            15.0
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
    fn 収まらない文字は真ん中を省く() {
        let canvas = Recorder::default();
        // 1 字 10 の幅で数える
        assert_eq!(
            truncate_middle(&canvas, "abc", TextStyle::Body, 30.0),
            "abc"
        );
        assert_eq!(
            truncate_middle(&canvas, "C:/Windows/notepad.exe", TextStyle::Body, 70.0),
            format!("C:/{ELLIPSIS}exe")
        );
        assert_eq!(
            truncate_middle(&canvas, "abcdef", TextStyle::Body, 5.0),
            ELLIPSIS.to_string()
        );
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
