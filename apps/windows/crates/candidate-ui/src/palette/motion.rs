#![forbid(unsafe_code)]

//! パレットの窓の動き(macOS の PaletteMotionState)．core が添えた動き(PalettePanel.motion)から，
//! 滑る印・送る中身・弾む部品の動きを作り，時刻ごとの途中の位置と濃さ(Tween)を返す．
//! 動いているあいだは Controller が 1 コマごとに Tween で窓の中身を作り直して描く

use super::layout::Layout;
use crate::geometry::Frame;
use ipc::{PaletteContentMotion, PalettePanel};
use std::time::Instant;
use tokens::motion::palette as duration;

/// 印が from から今の位置へ滑る動き
#[derive(Debug, Clone, Copy, PartialEq)]
struct Slide {
    from: Frame,
    start: Instant,
    /// 長さ(ミリ秒)
    duration: f32,
}

/// 部品が弾む・浮かび上がる動き
#[derive(Debug, Clone, Copy, PartialEq)]
struct Pop {
    start: Instant,
    duration: f32,
}

/// マス目の中身を送る動き．前の中身を出ていかせ，今の中身を入れる
#[derive(Debug, Clone)]
struct Swap {
    previous: PalettePanel,
    layout: Layout,
    direction: PaletteContentMotion,
    start: Instant,
    duration: f32,
}

/// 動いている部品
#[derive(Debug, Clone, Default)]
pub struct Motion {
    selection: Option<Slide>,
    mode: Option<Slide>,
    tab: Option<Slide>,
    content: Option<Swap>,
    picker: Option<Pop>,
    pin: Option<Pop>,
}

/// ある時刻の動きの途中の形．None の部品は止まっている(今の内容のとおりに描く)
#[derive(Debug, Clone, Copy, Default)]
pub struct Tween<'a> {
    /// 選択の枠の位置
    pub selection: Option<Frame>,
    /// 種類の切り替えの印の位置
    pub mode: Option<Frame>,
    /// まとまりのタブの印の位置
    pub tab: Option<Frame>,
    /// マス目の中身を送るところ．前の内容・前の配置・向き・進み具合(速さの変わり方を当てたもの)
    pub content: Option<(&'a PalettePanel, &'a Layout, PaletteContentMotion, f32)>,
    /// 肌の色の帯が浮かび上がる進み具合(0〜1．速さの変わり方は当てていない)
    pub picker: Option<f32>,
    /// ピンが弾む進み具合(0〜1)
    pub pin: Option<f32>,
}

/// 0 から 1 までの進み具合．長さが 0 なら終わっている
pub fn progress(start: Instant, duration: f32, now: Instant) -> f32 {
    if duration <= 0.0 {
        return 1.0;
    }
    (now.saturating_duration_since(start).as_secs_f32() * 1000.0 / duration).clamp(0.0, 1.0)
}

/// 速く動き出して静かに止まる(選択の枠・中身を送る)
pub fn ease_out(t: f32) -> f32 {
    1.0 - (1.0 - t).powi(3)
}

/// 静かに動き出して静かに止まる(種類の切り替えとタブの印)
pub fn ease_in_out(t: f32) -> f32 {
    if t < 0.5 {
        4.0 * t * t * t
    } else {
        1.0 - (-2.0 * t + 2.0).powi(3) / 2.0
    }
}

/// 少し行き過ぎてから戻る(肌の色の帯が浮かび上がる)
pub fn overshoot(t: f32) -> f32 {
    let c1 = 1.70158;
    let c3 = c1 + 1.0;
    1.0 + c3 * (t - 1.0).powi(3) + c1 * (t - 1.0).powi(2)
}

/// 0 から 1 へ上がって 0 に戻る(ピンが弾む)
pub fn bounce(t: f32) -> f32 {
    (std::f32::consts::PI * t).sin()
}

fn lerp(from: Frame, to: Frame, t: f32) -> Frame {
    Frame::new(
        from.x + (to.x - from.x) * t,
        from.y + (to.y - from.y) * t,
        from.width + (to.width - from.width) * t,
        from.height + (to.height - from.height) * t,
    )
}

/// 滑っている印の今の位置．滑り終えていれば None
fn slid(slide: &Option<Slide>, to: Frame, now: Instant, easing: fn(f32) -> f32) -> Option<Frame> {
    let slide = slide.as_ref()?;
    let t = progress(slide.start, slide.duration, now);
    (t < 1.0).then(|| lerp(slide.from, to, easing(t)))
}

/// 選択の枠の位置．選んでいる行が見えていなければ None
fn selected_frame(panel: &PalettePanel, layout: &Layout) -> Option<Frame> {
    super::layout::visible_selection(panel)
        .map(|position| layout.cell_frame(position.row, position.column))
}

fn selected_mode(panel: &PalettePanel, layout: &Layout) -> Option<Frame> {
    let index = panel.modes.iter().position(|mode| mode.is_selected)?;
    layout.modes.get(index).copied()
}

fn selected_tab(panel: &PalettePanel, layout: &Layout) -> Option<Frame> {
    let index = panel.tabs.iter().position(|tab| tab.is_selected)?;
    layout.tabs.get(index).copied()
}

impl Motion {
    /// 前の内容(old と old_layout)から今の内容への動きを始める．滑っている途中で次へ動いたら，今の位置から滑らせ直す
    pub fn start(
        &mut self,
        old: &PalettePanel,
        old_layout: &Layout,
        panel: &PalettePanel,
        layout: &Layout,
        now: Instant,
    ) {
        // スクロールの位置が変わったら，滑っている選択の枠を止める(滑り始めの位置は前のスクロールの位置のマスなので，
        // 続けると枠がマスからずれる)
        let scrolled = old.first_row != panel.first_row;
        let Some(changes) = &panel.motion else {
            // 動きが添えられていない(同じ内容を出し直した)．選択が変わったなら滑らせない
            if old.selection != panel.selection || scrolled {
                self.selection = None;
            }
            return;
        };
        if let (Some(from), Some(_)) = (&changes.selection_from, selected_frame(panel, layout)) {
            let current = selected_frame(old, old_layout)
                .and_then(|previous| slid(&self.selection, previous, now, ease_out));
            self.selection = Some(Slide {
                from: current.unwrap_or_else(|| layout.cell_frame(from.row, from.column)),
                start: now,
                duration: duration::SELECTION,
            });
        } else if old.selection != panel.selection || changes.content.is_some() || scrolled {
            self.selection = None;
        }
        if let Some(from) = changes.mode_from {
            if let Some(frame) = panel
                .modes
                .iter()
                .position(|mode| mode.kind == from)
                .and_then(|index| layout.modes.get(index))
            {
                let current = selected_mode(old, old_layout)
                    .and_then(|previous| slid(&self.mode, previous, now, ease_in_out));
                self.mode = Some(Slide {
                    from: current.unwrap_or(*frame),
                    start: now,
                    duration: duration::INDICATOR,
                });
            }
        }
        let same_tabs = old
            .tabs
            .iter()
            .map(|tab| &tab.section)
            .eq(panel.tabs.iter().map(|tab| &tab.section));
        if let Some(from) = &changes.tab_from {
            if let Some(frame) = panel
                .tabs
                .iter()
                .position(|tab| &tab.section == from)
                .and_then(|index| layout.tabs.get(index))
            {
                let current = selected_tab(old, old_layout)
                    .and_then(|previous| slid(&self.tab, previous, now, ease_in_out));
                self.tab = Some(Slide {
                    from: current.unwrap_or(*frame),
                    start: now,
                    duration: duration::INDICATOR,
                });
            }
        } else if !same_tabs {
            self.tab = None;
        }
        if let Some(direction) = changes.content {
            self.content = Some(Swap {
                previous: old.clone(),
                layout: old_layout.clone(),
                direction,
                start: now,
                duration: duration::CONTENT,
            });
        }
        if changes.opens_picker {
            self.picker = Some(Pop {
                start: now,
                duration: duration::POP,
            });
        } else if panel.skin_tone_picker.is_none() {
            self.picker = None;
        }
        if changes.toggles_pin {
            self.pin = Some(Pop {
                start: now,
                duration: duration::POP,
            });
        }
    }

    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// まだ動いている部品があるか
    pub fn is_active(&self, now: Instant) -> bool {
        let running = |start: Instant, duration: f32| progress(start, duration, now) < 1.0;
        [&self.selection, &self.mode, &self.tab]
            .iter()
            .any(|slide| slide.is_some_and(|slide| running(slide.start, slide.duration)))
            || self
                .content
                .as_ref()
                .is_some_and(|swap| running(swap.start, swap.duration))
            || [&self.picker, &self.pin]
                .iter()
                .any(|pop| pop.is_some_and(|pop| running(pop.start, pop.duration)))
    }

    /// now の時点の途中の形
    pub fn tween<'a>(&'a self, panel: &PalettePanel, layout: &Layout, now: Instant) -> Tween<'a> {
        let popping = |pop: &Option<Pop>| {
            pop.and_then(|pop| {
                let t = progress(pop.start, pop.duration, now);
                (t < 1.0).then_some(t)
            })
        };
        Tween {
            selection: selected_frame(panel, layout)
                .and_then(|to| slid(&self.selection, to, now, ease_out)),
            mode: selected_mode(panel, layout)
                .and_then(|to| slid(&self.mode, to, now, ease_in_out)),
            tab: selected_tab(panel, layout).and_then(|to| slid(&self.tab, to, now, ease_in_out)),
            content: self.content.as_ref().and_then(|swap| {
                let t = progress(swap.start, swap.duration, now);
                (t < 1.0).then(|| (&swap.previous, &swap.layout, swap.direction, ease_out(t)))
            }),
            picker: popping(&self.picker),
            pin: popping(&self.pin),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::sample;
    use super::*;
    use crate::scene::testing::{theme, Fixed};
    use ipc::{PaletteKind, PaletteMotion, PalettePosition};
    use std::time::Duration;

    fn layout(panel: &PalettePanel) -> Layout {
        Layout::new(panel, &theme("automatic"), &Fixed)
    }

    fn moved(panel: &PalettePanel, motion: PaletteMotion) -> PalettePanel {
        PalettePanel {
            motion: Some(motion),
            ..panel.clone()
        }
    }

    /// 何も動かない動き(ここから動くものだけを書き換える)
    fn still() -> PaletteMotion {
        PaletteMotion {
            selection_from: None,
            mode_from: None,
            tab_from: None,
            content: None,
            opens_picker: false,
            toggles_pin: false,
        }
    }

    fn after(start: Instant, milliseconds: f32) -> Instant {
        start + Duration::from_secs_f32(milliseconds / 1000.0)
    }

    #[test]
    fn 速さの変わり方はどれも0で始まり1で終わる() {
        for easing in [ease_out, ease_in_out, overshoot] {
            assert!(easing(0.0).abs() < 1e-5);
            assert!((easing(1.0) - 1.0).abs() < 1e-5);
        }
        assert!(bounce(0.5) > 0.99);
        assert!(bounce(1.0).abs() < 1e-5);
        // 帯は少し行き過ぎてから戻る
        assert!((0..10)
            .map(|step| overshoot(step as f32 / 10.0 + 0.05))
            .any(|value| value > 1.0));
    }

    #[test]
    fn 選択の枠は前のマスから滑り_終わったら止まる() {
        let old = sample::emoji();
        let mut panel = moved(
            &old,
            PaletteMotion {
                selection_from: old.selection.clone(),
                ..still()
            },
        );
        panel.selection = Some(PalettePosition { row: 3, column: 6 });
        let (old_layout, layout) = (layout(&old), layout(&panel));
        let start = Instant::now();
        let mut motion = Motion::default();
        motion.start(&old, &old_layout, &panel, &layout, start);
        let from = old_layout.cell_frame(1, 2);
        let to = layout.cell_frame(3, 6);
        assert_eq!(motion.tween(&panel, &layout, start).selection, Some(from));
        let middle = motion
            .tween(&panel, &layout, after(start, duration::SELECTION / 2.0))
            .selection
            .expect("滑っている途中");
        assert!(middle.x > from.x && middle.x < to.x);
        assert!(middle.y > from.y && middle.y < to.y);
        let end = after(start, duration::SELECTION + 1.0);
        assert_eq!(motion.tween(&panel, &layout, end).selection, None);
        assert!(!motion.is_active(end));
        assert!(motion.is_active(after(start, 1.0)));
    }

    #[test]
    fn 種類を切り替えたら印を滑らせ前の内容を送る() {
        let old = sample::emoji();
        let panel = moved(
            &sample::symbol(),
            PaletteMotion {
                mode_from: Some(PaletteKind::Emoji),
                content: Some(PaletteContentMotion::Next),
                ..still()
            },
        );
        let (old_layout, layout) = (layout(&old), layout(&panel));
        let start = Instant::now();
        let mut motion = Motion::default();
        motion.start(&old, &old_layout, &panel, &layout, start);
        let tween = motion.tween(&panel, &layout, after(start, duration::CONTENT / 2.0));
        let mode = tween.mode.expect("印が滑っている");
        assert!(mode.x > layout.modes[0].x && mode.x < layout.modes[1].x);
        let (previous, _, direction, t) = tween.content.expect("中身を送っている");
        assert_eq!(previous, &old);
        assert_eq!(direction, PaletteContentMotion::Next);
        assert!(t > 0.0 && t < 1.0);
        // 選択の枠は滑らせない
        assert_eq!(tween.selection, None);
    }

    #[test]
    fn 動きが添えられていなければ動かさず_選択が変わったら滑っている枠を止める() {
        let old = sample::emoji();
        let mut panel = moved(
            &old,
            PaletteMotion {
                selection_from: old.selection.clone(),
                ..still()
            },
        );
        panel.selection = Some(PalettePosition { row: 2, column: 0 });
        let (old_layout, layout) = (layout(&old), layout(&panel));
        let start = Instant::now();
        let mut motion = Motion::default();
        motion.start(&old, &old_layout, &panel, &layout, start);
        let mut jumped = panel.clone();
        jumped.motion = None;
        jumped.selection = Some(PalettePosition { row: 5, column: 0 });
        motion.start(&panel, &layout, &jumped, &layout, after(start, 10.0));
        assert_eq!(
            motion.tween(&jumped, &layout, after(start, 20.0)).selection,
            None
        );
    }

    #[test]
    fn 滑っている途中でスクロールしたら滑っている枠を止める() {
        let old = sample::emoji();
        let mut panel = moved(
            &old,
            PaletteMotion {
                selection_from: old.selection.clone(),
                ..still()
            },
        );
        panel.selection = Some(PalettePosition { row: 4, column: 6 });
        let (old_layout, layout) = (layout(&old), layout(&panel));
        let start = Instant::now();
        let mut motion = Motion::default();
        motion.start(&old, &old_layout, &panel, &layout, start);
        // ホイールでスクロールした(選択は同じ．core は動きを添えない)
        let mut scrolled = moved(&panel, still());
        scrolled.first_row = 1;
        let scrolled_layout = Layout::new(&scrolled, &theme("automatic"), &Fixed);
        motion.start(
            &panel,
            &layout,
            &scrolled,
            &scrolled_layout,
            after(start, 10.0),
        );
        assert_eq!(
            motion
                .tween(&scrolled, &scrolled_layout, after(start, 20.0))
                .selection,
            None
        );
    }

    #[test]
    fn 肌の色の帯とピンは開いたあいだだけ動く() {
        let old = sample::search();
        let panel = moved(
            &old,
            PaletteMotion {
                opens_picker: true,
                toggles_pin: true,
                ..still()
            },
        );
        let (old_layout, layout) = (layout(&old), layout(&panel));
        let start = Instant::now();
        let mut motion = Motion::default();
        motion.start(&old, &old_layout, &panel, &layout, start);
        let tween = motion.tween(&panel, &layout, after(start, duration::POP / 2.0));
        assert!(tween.picker.is_some_and(|t| t > 0.4 && t < 0.6));
        assert!(tween.pin.is_some());
        assert!(motion
            .tween(&panel, &layout, after(start, duration::POP + 1.0))
            .picker
            .is_none());
    }
}
