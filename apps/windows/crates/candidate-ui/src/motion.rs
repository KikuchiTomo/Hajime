#![forbid(unsafe_code)]

//! 候補の窓の動き(macOS の CandidatePanelController と同じ決まり)．OS に依らない部分
//!
//! - 出ている窓の大きさが変わるときは，縁を motion.candidate-window.resize の時間で滑らかに動かす(ease-out)
//! - 選んでいるものが同じまま中身が変わったとき(あとから届いた候補)は，motion.candidate-window.update の時間で重ねて変える
//! - アニメーション効果がオフなら，大きさはすぐ変え，重ね変わりだけにする

use ipc::{BranchMap, CandidateList};
use std::time::{Duration, Instant};

/// 選んでいる候補が同じまま中身が変わったか(あとから届いた候補)．選び直したときはすぐ見せるので false
pub fn arrived_list(shown: &CandidateList, next: &CandidateList) -> bool {
    shown != next
        && shown.selected_entry == next.selected_entry
        && shown.focus == next.focus
        && shown.selected_variant == next.selected_variant
}

/// 分岐図の文節と選んでいるものが同じまま中身が変わったか(あとから届いた文節の候補や下見)
pub fn arrived_branch(shown: &BranchMap, next: &BranchMap) -> bool {
    let key = |map: &BranchMap| {
        map.columns
            .iter()
            .map(|column| {
                (
                    column.text.clone(),
                    column.is_focused,
                    column.selected_alternative,
                    column.selected_variant,
                )
            })
            .collect::<Vec<_>>()
    };
    shown != next && key(shown) == key(next)
}

/// 窓の大きさが from から to へ変わる途中
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Resize {
    pub from: (f32, f32),
    pub to: (f32, f32),
    pub start: Instant,
}

impl Resize {
    pub fn duration() -> Duration {
        Duration::from_secs_f32(tokens::motion::candidate_window::RESIZE / 1000.0)
    }

    pub fn is_done(&self, now: Instant) -> bool {
        now.duration_since(self.start) >= Self::duration()
    }

    /// now の時点の大きさ．動き出しは速く，止まるときはゆっくり(ease-out)
    pub fn size_at(&self, now: Instant) -> (f32, f32) {
        let t = ease_out(progress(self.start, now, Self::duration()));
        (
            lerp(self.from.0, self.to.0, t).round(),
            lerp(self.from.1, self.to.1, t).round(),
        )
    }
}

/// 重ね変わりの濃さ(0〜1)．新しい中身をこの濃さで前の中身の上に描く
pub fn crossfade_opacity(start: Instant, now: Instant) -> f32 {
    ease_out(progress(start, now, crossfade_duration()))
}

pub fn crossfade_duration() -> Duration {
    Duration::from_secs_f32(tokens::motion::candidate_window::UPDATE / 1000.0)
}

fn progress(start: Instant, now: Instant, total: Duration) -> f32 {
    (now.duration_since(start).as_secs_f32() / total.as_secs_f32()).clamp(0.0, 1.0)
}

fn ease_out(t: f32) -> f32 {
    1.0 - (1.0 - t).powi(3)
}

fn lerp(from: f32, to: f32, t: f32) -> f32 {
    from + (to - from) * t
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scene::sample;

    #[test]
    fn 大きさは_ease_out_で動き_時間が過ぎたら着く() {
        let start = Instant::now();
        let resize = Resize {
            from: (100.0, 50.0),
            to: (200.0, 50.0),
            start,
        };
        assert_eq!(resize.size_at(start), (100.0, 50.0));
        let half = resize.size_at(start + Resize::duration() / 2);
        // ease-out なので，時間の半分で半分より先へ進む
        assert!(half.0 > 150.0 && half.0 < 200.0);
        assert_eq!(resize.size_at(start + Resize::duration()), (200.0, 50.0));
        assert!(resize.is_done(start + Resize::duration()));
        assert!(!resize.is_done(start));
    }

    #[test]
    fn 重ね変わりは_0_から_1_へ濃くなる() {
        let start = Instant::now();
        assert_eq!(crossfade_opacity(start, start), 0.0);
        assert_eq!(crossfade_opacity(start, start + crossfade_duration()), 1.0);
    }

    #[test]
    fn 文節の候補が届いたときだけ重ねて変え_文節を移ったときはすぐ見せる() {
        let shown = sample::branch();
        let mut arrived = shown.clone();
        arrived.columns[0].alternatives.push("届いた候補".into());
        assert!(arrived_branch(&shown, &arrived));
        let mut moved = shown.clone();
        let focused = moved
            .columns
            .iter()
            .position(|column| column.is_focused)
            .unwrap_or(0);
        moved.columns[focused].is_focused = false;
        let next = (focused + 1) % moved.columns.len();
        moved.columns[next].is_focused = true;
        assert!(!arrived_branch(&shown, &moved));
        assert!(!arrived_branch(&shown, &shown));
    }
}
