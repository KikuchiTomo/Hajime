#![forbid(unsafe_code)]

//! なめらかなスクロールと，重ねて描く細いスクロールバー．値は 96dpi の 1 ピクセルを 1 とする．
//! ホイールでは目標の位置を動かし，今の位置を目標へ補間する．スクロールバーは操作のあいだだけ出して，止まると消す

use super::anim::{Easing, Tween};
use tokens::motion::settings_windows as motion;
use tokens::size::settings_windows as size;

#[derive(Debug, Clone, PartialEq)]
pub struct Scroller {
    position: Tween,
    content: f32,
    viewport: f32,
    /// 最後にスクロールした(または出す理由があった)時刻
    active_at: f64,
    /// スクロールバーの上にポインターがある
    hover: bool,
    /// つまみをつかんでいる(つかんだ点のつまみの上端からの距離)
    grab: Option<f32>,
    /// スクロールバーの太さの動き(0 は細い，1 は太い)
    width: Tween,
}

impl Default for Scroller {
    fn default() -> Self {
        Self {
            position: Tween::fixed(0.0),
            content: 0.0,
            viewport: 0.0,
            active_at: f64::NEG_INFINITY,
            hover: false,
            grab: None,
            width: Tween::fixed(0.0),
        }
    }
}

/// スクロールバーのつまみの位置(トラックの中の上端と高さ)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Thumb {
    pub top: f32,
    pub height: f32,
}

impl Scroller {
    /// 中身と見えている高さを決める．位置は収まるよう詰める
    pub fn set_extent(&mut self, content: f32, viewport: f32) {
        self.content = content.max(0.0);
        self.viewport = viewport.max(0.0);
        let max = self.max();
        if self.position.target() > max {
            self.position.snap(max);
        }
    }

    pub fn max(&self) -> f32 {
        (self.content - self.viewport).max(0.0)
    }

    pub fn can_scroll(&self) -> bool {
        self.max() > 0.0
    }

    /// 今の位置(描くときの位置)
    pub fn offset(&self, now: f64) -> f32 {
        self.position.value(now).clamp(0.0, self.max())
    }

    /// 目標の位置
    pub fn target(&self) -> f32 {
        self.position.target()
    }

    /// 目標を delta だけ動かし，なめらかに送る
    pub fn scroll_by(&mut self, delta: f32, now: f64) {
        let target = (self.position.target() + delta).clamp(0.0, self.max());
        self.scroll_to(target, now);
    }

    /// target までなめらかに送る
    pub fn scroll_to(&mut self, target: f32, now: f64) {
        let target = target.clamp(0.0, self.max());
        self.active_at = now;
        if target == self.position.target() {
            return;
        }
        self.position = Tween::new(
            self.offset(now),
            target,
            now,
            f64::from(motion::SCROLL),
            Easing::DECELERATE,
        );
    }

    /// すぐに position にする(ページを開き直したとき・つまみをつかんで動かすとき)
    pub fn jump_to(&mut self, position: f32) {
        self.position.snap(position.clamp(0.0, self.max()));
    }

    /// rect(中身の座標)が見えるよう送る．見えていれば動かさない
    pub fn reveal(&mut self, top: f32, bottom: f32, now: f64) {
        let current = self.position.target();
        if top < current {
            self.scroll_to(top, now);
        } else if bottom > current + self.viewport {
            self.scroll_to(bottom - self.viewport, now);
        }
    }

    /// 送っている途中か(フレームを回し続けるか)
    pub fn animating(&self, now: f64) -> bool {
        self.position.running(now)
            || self.width.running(now)
            || (self.can_scroll() && self.bar_opacity(now) > 0.0 && !self.bar_steady(now))
    }

    /// スクロールバーの濃さが変わらない状態か(出しきっているか，消えきっている)
    fn bar_steady(&self, now: f64) -> bool {
        let opacity = self.bar_opacity(now);
        opacity == 0.0 || (opacity == 1.0 && (self.hover || self.grab.is_some()))
    }

    /// スクロールバーの濃さ(0〜1)．操作が止まって motion::SCROLLBAR_IDLE たつと消し始める
    pub fn bar_opacity(&self, now: f64) -> f32 {
        if !self.can_scroll() {
            return 0.0;
        }
        if self.hover || self.grab.is_some() {
            return 1.0;
        }
        let idle = now - self.active_at - f64::from(motion::SCROLLBAR_IDLE);
        if idle <= 0.0 {
            return 1.0;
        }
        (1.0 - idle / f64::from(motion::SCROLLBAR_FADE)).clamp(0.0, 1.0) as f32
    }

    /// スクロールバーの太さ
    pub fn bar_width(&self, now: f64) -> f32 {
        let wide = self.width.value(now);
        size::SCROLLBAR_THIN + (size::SCROLLBAR_WIDE - size::SCROLLBAR_THIN) * wide
    }

    /// ポインターがスクロールバーの上に来た・離れた
    pub fn set_hover(&mut self, hover: bool, now: f64) {
        if self.hover == hover {
            return;
        }
        self.hover = hover;
        self.active_at = now;
        let wide = if hover || self.grab.is_some() {
            1.0
        } else {
            0.0
        };
        self.width.retarget(
            wide,
            now,
            f64::from(motion::HOVER) * 2.0,
            Easing::DECELERATE,
        );
    }

    pub fn hover(&self) -> bool {
        self.hover
    }

    /// track_height のトラックの中のつまみ
    pub fn thumb(&self, track_height: f32, now: f64) -> Option<Thumb> {
        if !self.can_scroll() || track_height <= 0.0 || self.content <= 0.0 {
            return None;
        }
        let height = (track_height * self.viewport / self.content)
            .max(size::SCROLLBAR_MIN_THUMB)
            .min(track_height);
        let travel = track_height - height;
        let top = travel * self.offset(now) / self.max();
        Some(Thumb { top, height })
    }

    /// トラックの y(上からの距離)でボタンを押した．つまみの上ならつかみ，外ならそこへ送る
    pub fn press(&mut self, y: f32, track_height: f32, now: f64) {
        let Some(thumb) = self.thumb(track_height, now) else {
            return;
        };
        if y >= thumb.top && y <= thumb.top + thumb.height {
            self.grab = Some(y - thumb.top);
        } else {
            // つまみの真ん中がそこに来るよう送る
            self.grab = Some(thumb.height / 2.0);
            self.drag(y, track_height, now);
        }
        self.active_at = now;
    }

    /// つかんだまま y まで動かした
    pub fn drag(&mut self, y: f32, track_height: f32, now: f64) {
        let (Some(grab), Some(thumb)) = (self.grab, self.thumb(track_height, now)) else {
            return;
        };
        let travel = track_height - thumb.height;
        if travel <= 0.0 {
            return;
        }
        let ratio = ((y - grab) / travel).clamp(0.0, 1.0);
        self.jump_to(ratio * self.max());
        self.active_at = now;
    }

    /// つまみを放した(つかんでいなければ何もしない)
    pub fn release(&mut self, now: f64) {
        if self.grab.take().is_some() {
            self.active_at = now;
        }
    }

    pub fn grabbing(&self) -> bool {
        self.grab.is_some()
    }
}

/// ホイールの回した量(WHEEL_DELTA の倍数)を送る量にする．下へ回すと正
pub fn wheel_delta(delta: i32, wheel_delta: i32) -> f32 {
    if wheel_delta == 0 {
        return 0.0;
    }
    -(delta as f32) / wheel_delta as f32 * size::WHEEL_STEP
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scroller() -> Scroller {
        let mut scroller = Scroller::default();
        scroller.set_extent(1000.0, 400.0);
        scroller
    }

    #[test]
    fn ホイールで目標まで補間して送り端で止まる() {
        let mut scroller = scroller();
        scroller.scroll_by(100.0, 0.0);
        assert_eq!(scroller.target(), 100.0);
        let middle = scroller.offset(f64::from(motion::SCROLL) / 2.0);
        assert!(middle > 0.0 && middle < 100.0);
        assert_eq!(scroller.offset(1000.0), 100.0);
        scroller.scroll_by(10_000.0, 1000.0);
        assert_eq!(scroller.target(), 600.0);
        scroller.scroll_by(-10_000.0, 2000.0);
        assert_eq!(scroller.target(), 0.0);
    }

    #[test]
    fn 中身が縮んだら位置を詰める() {
        let mut scroller = scroller();
        scroller.jump_to(600.0);
        scroller.set_extent(500.0, 400.0);
        assert_eq!(scroller.offset(0.0), 100.0);
        scroller.set_extent(300.0, 400.0);
        assert!(!scroller.can_scroll());
        assert_eq!(scroller.offset(0.0), 0.0);
    }

    #[test]
    fn スクロールバーは操作のあとしばらくして消える() {
        let mut scroller = scroller();
        assert_eq!(scroller.bar_opacity(0.0), 0.0);
        scroller.scroll_by(50.0, 0.0);
        assert_eq!(scroller.bar_opacity(100.0), 1.0);
        let fading = f64::from(motion::SCROLLBAR_IDLE + motion::SCROLLBAR_FADE / 2.0);
        let opacity = scroller.bar_opacity(fading);
        assert!(opacity > 0.0 && opacity < 1.0);
        assert!(scroller.animating(fading));
        let gone = f64::from(motion::SCROLLBAR_IDLE + motion::SCROLLBAR_FADE) + 1.0;
        assert_eq!(scroller.bar_opacity(gone), 0.0);
        assert!(!scroller.animating(gone));
        // ポインターを載せているあいだは消さない
        scroller.set_hover(true, gone);
        assert_eq!(scroller.bar_opacity(gone + 10_000.0), 1.0);
    }

    #[test]
    fn つまみは見えている割合の長さで位置に合わせて動く() {
        let mut scroller = scroller();
        let thumb = scroller.thumb(400.0, 0.0).unwrap();
        assert_eq!(thumb.top, 0.0);
        assert!((thumb.height - 160.0).abs() < 1e-3);
        scroller.jump_to(600.0);
        let thumb = scroller.thumb(400.0, 0.0).unwrap();
        assert!((thumb.top + thumb.height - 400.0).abs() < 1e-3);
        // つまみをつかんで上端まで動かす
        scroller.press(thumb.top + 10.0, 400.0, 0.0);
        scroller.drag(10.0, 400.0, 0.0);
        assert_eq!(scroller.offset(0.0), 0.0);
        scroller.release(0.0);
        assert!(!scroller.grabbing());
    }

    #[test]
    fn トラックを押すとそこへ送る() {
        let mut scroller = scroller();
        scroller.press(400.0, 400.0, 0.0);
        assert_eq!(scroller.offset(0.0), 600.0);
    }

    #[test]
    fn 見せたい範囲が外にあれば送る() {
        let mut scroller = scroller();
        scroller.reveal(450.0, 500.0, 0.0);
        assert_eq!(scroller.target(), 100.0);
        scroller.reveal(150.0, 200.0, 0.0);
        assert_eq!(scroller.target(), 100.0);
        scroller.reveal(50.0, 80.0, 0.0);
        assert_eq!(scroller.target(), 50.0);
    }

    #[test]
    fn ホイールの回した量を送る量にする() {
        assert_eq!(wheel_delta(-120, 120), size::WHEEL_STEP);
        assert_eq!(wheel_delta(240, 120), -2.0 * size::WHEEL_STEP);
        assert_eq!(wheel_delta(120, 0), 0.0);
    }
}
