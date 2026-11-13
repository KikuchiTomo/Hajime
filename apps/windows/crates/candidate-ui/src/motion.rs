#![forbid(unsafe_code)]

//! 候補の窓の動き(macOS の CandidatePanelController と同じ決まり)．OS に依らない部分
//!
//! - 出ている窓の大きさが変わるときは，枠線を motion.candidate-window.resize の時間で滑らかに動かす(ease-out)
//! - 選んでいるものが同じまま中身が変わったとき(あとから届いた候補)は，motion.candidate-window.update の時間で重ねて変える
//! - アニメーション効果がオフなら，大きさはすぐ変え，重ね変わりだけにする
//! - 分岐図は動かさず，大きさも中身もその瞬間に替える(macOS #566 と同じ．動いているあいだは候補を読めないため)

use ipc::CandidateList;
use std::time::{Duration, Instant};

/// 選んでいる候補が同じまま中身が変わったか(あとから届いた候補)．選び直したときはすぐ見せるので false
pub fn arrived_list(shown: &CandidateList, next: &CandidateList) -> bool {
    shown != next
        && shown.selected_entry == next.selected_entry
        && shown.focus == next.focus
        && shown.selected_variant == next.selected_variant
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

/// 語の意味の吹き出しを今の位置 shown から target へ滑らせて動かすか．
/// 候補の窓を置き直した(入力位置が変わった・画面や拡大率が変わった)ときは，前の場所から画面を横切らないように
/// 窓に付けてすぐ移す．滑らせるのは，同じ場所の窓の中で選んでいる候補が変わったときだけ
pub fn glides_bubble(
    shown: Option<(f32, f32)>,
    target: (f32, f32),
    window_moved: bool,
    reduce_motion: bool,
) -> bool {
    !reduce_motion && !window_moved && shown.is_some_and(|shown| shown != target)
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
    fn 吹き出しは同じ場所の窓の中で選び直したときだけ滑らせる() {
        let (shown, target) = ((100.0, 200.0), (100.0, 260.0));
        assert!(glides_bubble(Some(shown), target, false, false));
        // 候補の窓を置き直したとき(入力位置が変わった・別の画面に移った)は，すぐ移す
        assert!(!glides_bubble(Some(shown), target, true, false));
        // 初めて出すとき・同じ位置のとき・アニメーション効果がオフのとき
        assert!(!glides_bubble(None, target, false, false));
        assert!(!glides_bubble(Some(target), target, false, false));
        assert!(!glides_bubble(Some(shown), target, false, true));
    }

    #[test]
    fn 重ね変わりは_0_から_1_へ濃くなる() {
        let start = Instant::now();
        assert_eq!(crossfade_opacity(start, start), 0.0);
        assert_eq!(crossfade_opacity(start, start + crossfade_duration()), 1.0);
    }
}
