#![forbid(unsafe_code)]

//! 時間で変わる値(動き)．時刻はミリ秒の数で渡し，OS の時計に頼らずに確かめられるようにする．
//! 曲線は Windows 11(WinUI)の動きと同じ 3 次ベジェ曲線にする

/// 動きの曲線(3 次ベジェ曲線の 2 つの制御点)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Easing {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,
}

impl Easing {
    /// 速く始まってゆっくり止まる(WinUI の FastOutSlowIn．出てくるもの・移るもの)
    pub const DECELERATE: Easing = Easing::new(0.0, 0.0, 0.0, 1.0);
    /// ゆっくり始まりゆっくり止まる(WinUI の標準の曲線．位置の移り変わり)
    pub const STANDARD: Easing = Easing::new(0.55, 0.55, 0.0, 1.0);
    /// 一定の速さ(色の移り変わり)
    pub const LINEAR: Easing = Easing::new(0.0, 0.0, 1.0, 1.0);

    pub const fn new(x1: f32, y1: f32, x2: f32, y2: f32) -> Self {
        Self { x1, y1, x2, y2 }
    }

    /// 経過の割合 t(0〜1)での進み具合
    pub fn apply(&self, t: f32) -> f32 {
        let t = t.clamp(0.0, 1.0);
        if t <= 0.0 || t >= 1.0 {
            return t;
        }
        // x(s) = t となる s を二分法で求め，y(s) を返す(単調なので必ず見つかる)
        let (mut low, mut high) = (0.0f32, 1.0f32);
        let mut s = t;
        for _ in 0..24 {
            let x = bezier(s, self.x1, self.x2);
            if (x - t).abs() < 1e-5 {
                break;
            }
            if x < t {
                low = s;
            } else {
                high = s;
            }
            s = (low + high) / 2.0;
        }
        bezier(s, self.y1, self.y2)
    }
}

/// 始点 0・終点 1 の 3 次ベジェ曲線の s での値
fn bezier(s: f32, p1: f32, p2: f32) -> f32 {
    let inverse = 1.0 - s;
    3.0 * inverse * inverse * s * p1 + 3.0 * inverse * s * s * p2 + s * s * s
}

/// from から to へ duration ミリ秒で移る値
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Tween {
    from: f32,
    to: f32,
    start: f64,
    duration: f64,
    easing: Easing,
}

impl Tween {
    /// 動かずに value にとどまる値
    pub fn fixed(value: f32) -> Self {
        Self {
            from: value,
            to: value,
            start: 0.0,
            duration: 0.0,
            easing: Easing::LINEAR,
        }
    }

    pub fn new(from: f32, to: f32, now: f64, duration: f64, easing: Easing) -> Self {
        Self {
            from,
            to,
            start: now,
            duration: duration.max(0.0),
            easing,
        }
    }

    pub fn value(&self, now: f64) -> f32 {
        if self.duration <= 0.0 {
            return self.to;
        }
        let t = ((now - self.start) / self.duration) as f32;
        self.from + (self.to - self.from) * self.easing.apply(t)
    }

    pub fn target(&self) -> f32 {
        self.to
    }

    /// まだ動いているか
    pub fn running(&self, now: f64) -> bool {
        self.duration > 0.0 && now < self.start + self.duration && self.from != self.to
    }

    /// 今の値から to へ動き直す．すでに to へ向かっていれば何もしない
    pub fn retarget(&mut self, to: f32, now: f64, duration: f64, easing: Easing) {
        if self.to == to {
            return;
        }
        *self = Self::new(self.value(now), to, now, duration, easing);
    }

    /// 動かさずに value にする
    pub fn snap(&mut self, value: f32) {
        *self = Self::fixed(value);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 曲線は端で0と1になり単調に増える() {
        for easing in [Easing::DECELERATE, Easing::STANDARD, Easing::LINEAR] {
            assert_eq!(easing.apply(0.0), 0.0);
            assert_eq!(easing.apply(1.0), 1.0);
            let mut last = 0.0;
            for step in 1..=20 {
                let value = easing.apply(step as f32 / 20.0);
                assert!(value + 1e-4 >= last, "{easing:?} が減った");
                last = value;
            }
        }
        // 減速の曲線は前半で大きく進む
        assert!(Easing::DECELERATE.apply(0.25) > 0.6);
        assert!((Easing::LINEAR.apply(0.5) - 0.5).abs() < 1e-3);
    }

    #[test]
    fn 値は時間で目標に着き動きが止まる() {
        let tween = Tween::new(0.0, 10.0, 100.0, 200.0, Easing::LINEAR);
        assert_eq!(tween.value(100.0), 0.0);
        assert!((tween.value(200.0) - 5.0).abs() < 1e-3);
        assert_eq!(tween.value(300.0), 10.0);
        assert_eq!(tween.value(1000.0), 10.0);
        assert!(tween.running(250.0));
        assert!(!tween.running(300.0));
    }

    #[test]
    fn 途中で目標を変えると今の値から動き直す() {
        let mut tween = Tween::new(0.0, 10.0, 0.0, 100.0, Easing::LINEAR);
        tween.retarget(0.0, 50.0, 100.0, Easing::LINEAR);
        assert!((tween.value(50.0) - 5.0).abs() < 1e-3);
        assert_eq!(tween.value(150.0), 0.0);
        tween.snap(3.0);
        assert_eq!(tween.value(0.0), 3.0);
        assert!(!tween.running(0.0));
    }
}
