#![forbid(unsafe_code)]

use crate::scene::Frame;
use tokens::size::{candidate, handwriting};

/// 手書きの窓の部品の位置(DIP)．上から 見出しの帯(題と閉じる)・正方形の書く欄・候補と消去の行
#[derive(Debug, Clone, PartialEq)]
pub struct Layout {
    pub width: f32,
    pub height: f32,
    pub header: Frame,
    pub close: Frame,
    pub canvas: Frame,
    pub clear: Frame,
    /// 候補の札．収まる数だけ．札と候補の番号
    pub chips: Vec<(Frame, usize)>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hit {
    Canvas,
    Candidate(usize),
    Clear,
    Close,
    /// 見出しの帯．押したまま動かすと窓を動かす
    Header,
    Nothing,
}

/// 文字の幅を測るもの．描画の側(DirectWrite)が実装する
pub trait TextWidth {
    fn width(&self, text: &str) -> f32;
}

impl Layout {
    /// header_height は見出しの文字の高さ．candidates は候補の文字列
    pub fn new(
        header_height: f32,
        candidates: &[String],
        clear_label: &str,
        measure: &dyn TextWidth,
    ) -> Self {
        let padding = handwriting::CANVAS_PADDING;
        let header = header_height.ceil() + candidate::SECTION_PADDING_Y * 2.0;
        let width = handwriting::WIDTH;
        let height = header + handwriting::HEIGHT;
        let canvas = Frame::new(
            padding,
            header + padding,
            handwriting::CANVAS_SIZE,
            handwriting::CANVAS_SIZE,
        );
        let row_top = canvas.max_y() + padding / 2.0;
        let row = Frame::new(
            padding,
            row_top,
            width - padding * 2.0,
            height - row_top - padding,
        );
        let clear_width = measure.width(clear_label).ceil() + candidate::PADDING_X * 2.0;
        let clear = Frame::new(row.max_x() - clear_width, row.y, clear_width, row.height);
        let gap = candidate::VARIANT_PADDING_X;
        let mut chips = Vec::new();
        let mut x = row.x;
        for (index, text) in candidates.iter().enumerate() {
            let chip_width =
                (measure.width(text).ceil() + candidate::PADDING_X * 2.0).max(row.height);
            if x + chip_width > clear.x - gap {
                break;
            }
            chips.push((Frame::new(x, row.y, chip_width, row.height), index));
            x += chip_width + gap;
        }
        Self {
            width,
            height,
            header: Frame::new(0.0, 0.0, width, header),
            close: Frame::new(width - header, 0.0, header, header),
            canvas,
            clear,
            chips,
        }
    }

    pub fn hit(&self, x: f32, y: f32) -> Hit {
        if contains(&self.close, x, y) {
            Hit::Close
        } else if contains(&self.header, x, y) {
            Hit::Header
        } else if contains(&self.canvas, x, y) {
            Hit::Canvas
        } else if contains(&self.clear, x, y) {
            Hit::Clear
        } else if let Some((_, index)) = self.chips.iter().find(|(frame, _)| contains(frame, x, y))
        {
            Hit::Candidate(*index)
        } else {
            Hit::Nothing
        }
    }

    /// 書く欄の中に収めた点(書く欄の左上が原点)．欄の外へはみ出して書いても端に留める
    pub fn canvas_point(&self, x: f32, y: f32) -> (f32, f32) {
        (
            (x - self.canvas.x).clamp(0.0, self.canvas.width),
            (y - self.canvas.y).clamp(0.0, self.canvas.height),
        )
    }

    /// 書く欄の縦と横の中心を通る破線の十字(漢字の練習帳の田の字)．線の 1 区切りずつの四角
    pub fn guide(&self) -> Vec<Frame> {
        let line = handwriting::FRAME_WIDTH;
        let dash = handwriting::GUIDE_DASH;
        let canvas = &self.canvas;
        let center_x = canvas.x + canvas.width / 2.0 - line / 2.0;
        let center_y = canvas.y + canvas.height / 2.0 - line / 2.0;
        let mut dashes = Vec::new();
        let mut offset = 0.0;
        while offset < canvas.width {
            let length = dash.min(canvas.width - offset);
            dashes.push(Frame::new(canvas.x + offset, center_y, length, line));
            offset += dash * 2.0;
        }
        let mut offset = 0.0;
        while offset < canvas.height {
            let length = dash.min(canvas.height - offset);
            dashes.push(Frame::new(center_x, canvas.y + offset, line, length));
            offset += dash * 2.0;
        }
        dashes
    }
}

fn contains(frame: &Frame, x: f32, y: f32) -> bool {
    x >= frame.x && x < frame.max_x() && y >= frame.y && y < frame.max_y()
}

/// 画面の上の四角(ピクセル)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Bounds {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

/// 窓を置く位置．入力位置の下に置き，画面の下にはみ出すなら上に置く．作業領域の外には出さない
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

    struct Fixed;

    impl TextWidth for Fixed {
        fn width(&self, text: &str) -> f32 {
            text.chars().count() as f32 * 10.0
        }
    }

    fn layout(candidates: &[&str]) -> Layout {
        let candidates: Vec<String> = candidates.iter().map(|text| text.to_string()).collect();
        Layout::new(14.0, &candidates, "消去", &Fixed)
    }

    #[test]
    fn 書く欄は正方形で見出しの下に余白を空けて置く() {
        let layout = layout(&[]);
        assert_eq!(layout.canvas.width, layout.canvas.height);
        assert_eq!(layout.canvas.width, handwriting::CANVAS_SIZE);
        assert_eq!(
            layout.canvas.y,
            layout.header.max_y() + handwriting::CANVAS_PADDING
        );
        assert_eq!(layout.height, layout.header.height + handwriting::HEIGHT);
        assert!(layout.clear.max_y() <= layout.height);
        assert!(layout.clear.y >= layout.canvas.max_y());
    }

    #[test]
    fn 候補は消去のボタンの手前に収まる数だけ並べる() {
        let many: Vec<&str> = vec!["鬱"; 20];
        let layout = layout(&many);
        assert!(!layout.chips.is_empty());
        assert!(layout.chips.len() < 20);
        let last = layout.chips.last().unwrap().0;
        assert!(last.max_x() <= layout.clear.x);
        assert_eq!(layout.chips[1].1, 1);
    }

    #[test]
    fn 押した場所で部品を見分ける() {
        let layout = layout(&["鬱", "欝"]);
        let canvas = layout.canvas;
        assert_eq!(layout.hit(canvas.x + 1.0, canvas.y + 1.0), Hit::Canvas);
        let chip = layout.chips[1].0;
        assert_eq!(layout.hit(chip.x + 1.0, chip.y + 1.0), Hit::Candidate(1));
        assert_eq!(
            layout.hit(layout.clear.x + 1.0, layout.clear.y + 1.0),
            Hit::Clear
        );
        assert_eq!(layout.hit(layout.close.x + 1.0, 1.0), Hit::Close);
        assert_eq!(layout.hit(1.0, 1.0), Hit::Header);
        assert_eq!(layout.hit(0.5, canvas.y + 1.0), Hit::Nothing);
    }

    #[test]
    fn 書く欄の外の点は端に留める() {
        let layout = layout(&[]);
        assert_eq!(
            layout.canvas_point(-50.0, layout.canvas.y + 10.0),
            (0.0, 10.0)
        );
        assert_eq!(
            layout.canvas_point(1000.0, 1000.0),
            (layout.canvas.width, layout.canvas.height)
        );
    }

    #[test]
    fn 十字の破線は中心を通り欄の中に収まる() {
        let layout = layout(&[]);
        let canvas = layout.canvas;
        let guide = layout.guide();
        assert!(!guide.is_empty());
        for dash in &guide {
            assert!(dash.x >= canvas.x && dash.max_x() <= canvas.max_x() + 0.01);
            assert!(dash.y >= canvas.y && dash.max_y() <= canvas.max_y() + 0.01);
            let on_vertical =
                (dash.x + dash.width / 2.0 - (canvas.x + canvas.width / 2.0)).abs() < 0.01;
            let on_horizontal =
                (dash.y + dash.height / 2.0 - (canvas.y + canvas.height / 2.0)).abs() < 0.01;
            assert!(on_vertical || on_horizontal);
        }
        let horizontal: Vec<_> = guide
            .iter()
            .filter(|dash| dash.width > dash.height)
            .collect();
        assert!(horizontal
            .windows(2)
            .all(|pair| pair[1].x - pair[0].max_x() >= handwriting::GUIDE_DASH - 0.01));
    }

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
