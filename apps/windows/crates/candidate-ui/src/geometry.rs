#![forbid(unsafe_code)]

/// 位置(1 ドット = 96 DPI の 1 ピクセル)
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point {
    pub x: f32,
    pub y: f32,
}

impl Point {
    pub fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }

    pub fn offset(self, dx: f32, dy: f32) -> Self {
        Self::new(self.x + dx, self.y + dy)
    }
}

/// 長方形．y は下へ増える
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Frame {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl Frame {
    pub fn new(x: f32, y: f32, width: f32, height: f32) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    pub fn max_x(&self) -> f32 {
        self.x + self.width
    }

    pub fn max_y(&self) -> f32 {
        self.y + self.height
    }

    pub fn mid_x(&self) -> f32 {
        self.x + self.width / 2.0
    }

    pub fn mid_y(&self) -> f32 {
        self.y + self.height / 2.0
    }

    /// 縦横を dx・dy ずつ内側に縮める(負なら広げる)
    pub fn inset(&self, dx: f32, dy: f32) -> Self {
        Self::new(
            self.x + dx,
            self.y + dy,
            self.width - dx * 2.0,
            self.height - dy * 2.0,
        )
    }

    pub fn offset(&self, dx: f32, dy: f32) -> Self {
        Self::new(self.x + dx, self.y + dy, self.width, self.height)
    }

    /// 中心と一辺の長さから正方形を作る
    pub fn square(center: Point, side: f32) -> Self {
        Self::new(center.x - side / 2.0, center.y - side / 2.0, side, side)
    }
}

/// 画面の上の四角(ピクセル)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Bounds {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

/// 窓を置く位置(手書きの窓とパレットの窓)．入力位置の下に置き，画面の下にはみ出すなら上に置く．作業領域の外には出さない
pub fn origin(caret: Bounds, work: Bounds, width: i32, height: i32, gap: i32) -> (i32, i32) {
    let below = caret.bottom + gap;
    let y = if below + height > work.bottom && caret.top - gap - height >= work.top {
        caret.top - gap - height
    } else {
        below
    };
    let x = caret.left.min(work.right - width).max(work.left);
    (x, y.min(work.bottom - height).max(work.top))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 入力位置の下に置き下にはみ出すなら上に置く() {
        let work = Bounds {
            left: 0,
            top: 0,
            right: 1920,
            bottom: 1080,
        };
        let caret = Bounds {
            left: 100,
            top: 100,
            right: 102,
            bottom: 120,
        };
        assert_eq!(origin(caret, work, 300, 400, 4), (100, 124));
        let low = Bounds {
            left: 1800,
            top: 900,
            right: 1802,
            bottom: 920,
        };
        assert_eq!(origin(low, work, 300, 400, 4), (1620, 496));
    }

    #[test]
    fn 上にも下にも収まらなければ作業領域の中に留める() {
        let work = Bounds {
            left: 0,
            top: 0,
            right: 800,
            bottom: 500,
        };
        let caret = Bounds {
            left: 10,
            top: 200,
            right: 12,
            bottom: 220,
        };
        assert_eq!(origin(caret, work, 300, 400, 4), (10, 100));
    }
}
