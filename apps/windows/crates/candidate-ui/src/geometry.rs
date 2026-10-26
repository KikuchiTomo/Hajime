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
