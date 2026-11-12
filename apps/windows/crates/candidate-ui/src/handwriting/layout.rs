#![forbid(unsafe_code)]

//! 手書きの窓の部品の位置(DIP)．macOS の HandwritingView と同じ並び: 上に見出しの帯(題と閉じる)，
//! その下の場所の真ん中に正方形の書く欄，いちばん下に横に送れる候補の行と，1 画戻す・消去のボタン．
//! 窓を広げると書く欄も大きくなる(正方形のまま真ん中に置く)

use crate::scene::Frame;
use tokens::size::handwriting as size;

/// 窓のいちばん小さい大きさ(DIP)．macOS の contentMinSize に見出しの帯を足したもの
pub fn minimum_size() -> (f32, f32) {
    (size::WIDTH, size::TITLE_HEIGHT + size::HEIGHT)
}

/// 窓の枠線のうち，押して大きさを変える辺
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Edge {
    Left,
    Right,
    Top,
    Bottom,
    TopLeft,
    TopRight,
    BottomLeft,
    BottomRight,
}

/// 押せる部品．ポインタを置いた・押したものを覚えて，色を変えるのに使う
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Control {
    Close,
    Undo,
    Clear,
    Candidate(usize),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hit {
    /// 枠線．押したまま動かすと窓の大きさを変える
    Edge(Edge),
    /// 見出しの帯．押したまま動かすと窓を動かす
    Title,
    Canvas,
    Control(Control),
    Nothing,
}

/// 文字の幅を測るもの．描画の側(DirectWrite)が実装する
pub trait TextWidth {
    /// 候補の字の幅
    fn candidate_width(&self, text: &str) -> f32;
    /// ボタンの字の幅(消去)
    fn label_width(&self, text: &str) -> f32;
}

#[derive(Debug, Clone, PartialEq)]
pub struct Layout {
    pub width: f32,
    pub height: f32,
    pub title: Frame,
    pub close: Frame,
    pub canvas: Frame,
    /// 候補を並べる場所(この中だけに描く)．はみ出した分は横に送る
    pub strip: Frame,
    /// 候補のタグ．送った分を引いた位置(strip の外にはみ出すことがある)
    pub chips: Vec<Frame>,
    pub undo: Frame,
    pub clear: Frame,
    /// 送った量と，送れるいちばん大きい量
    pub scroll: f32,
    pub max_scroll: f32,
}

impl Layout {
    /// width と height は窓の大きさ(DIP)．小さすぎれば minimum_size に広げる．scroll は候補の行を送った量
    pub fn new(
        width: f32,
        height: f32,
        candidates: &[String],
        clear_label: &str,
        scroll: f32,
        measure: &dyn TextWidth,
    ) -> Self {
        let (minimum_width, minimum_height) = minimum_size();
        let width = width.max(minimum_width);
        let height = height.max(minimum_height);
        let padding = size::CANVAS_PADDING;
        let gap = size::CANDIDATE_GAP;
        let title = Frame::new(0.0, 0.0, width, size::TITLE_HEIGHT);
        let close = Frame::new(
            width - size::CAPTION_BUTTON_WIDTH,
            0.0,
            size::CAPTION_BUTTON_WIDTH,
            size::TITLE_HEIGHT,
        );
        // 候補の行(macOS は左右と下に余白)
        let row = Frame::new(
            padding,
            height - padding - size::CONTROL_HEIGHT,
            width - padding * 2.0,
            size::CONTROL_HEIGHT,
        );
        let clear_width = measure.label_width(clear_label).ceil() + size::CONTROL_PADDING_X * 2.0;
        let clear = Frame::new(row.max_x() - clear_width, row.y, clear_width, row.height);
        let undo = Frame::new(
            clear.x - gap - size::ICON_BUTTON_WIDTH,
            row.y,
            size::ICON_BUTTON_WIDTH,
            row.height,
        );
        let strip = Frame::new(row.x, row.y, (undo.x - gap - row.x).max(0.0), row.height);
        // 書く欄は，見出しの帯と候補の行のあいだの場所の真ん中に，正方形で置く(macOS の GeometryReader と同じ)
        let area = Frame::new(0.0, title.max_y(), width, row.y - title.max_y());
        let side = (area.width.min(area.height) - padding * 2.0)
            .max(0.0)
            .floor();
        let canvas = Frame::new(
            (area.x + (area.width - side) / 2.0).round(),
            (area.y + (area.height - side) / 2.0).round(),
            side,
            side,
        );
        let widths: Vec<f32> = candidates
            .iter()
            .map(|text| {
                (measure.candidate_width(text).ceil() + size::CONTROL_PADDING_X * 2.0)
                    .max(size::CONTROL_HEIGHT)
            })
            .collect();
        let content = widths.iter().sum::<f32>() + gap * widths.len().saturating_sub(1) as f32;
        let max_scroll = (content - strip.width).max(0.0);
        let scroll = scroll.clamp(0.0, max_scroll);
        let mut chips = Vec::with_capacity(widths.len());
        let mut x = strip.x - scroll;
        for chip_width in widths {
            chips.push(Frame::new(x, strip.y, chip_width, strip.height));
            x += chip_width + gap;
        }
        Self {
            width,
            height,
            title,
            close,
            canvas,
            strip,
            chips,
            undo,
            clear,
            scroll,
            max_scroll,
        }
    }

    /// 窓の中の点(DIP)にある部品．枠線は見出しの帯や部品より先に見る(Windows 11 の窓と同じく，枠線は窓のどこでもつかめる)
    pub fn hit(&self, x: f32, y: f32) -> Hit {
        if let Some(edge) = self.edge(x, y) {
            return Hit::Edge(edge);
        }
        if contains(&self.close, x, y) {
            Hit::Control(Control::Close)
        } else if contains(&self.title, x, y) {
            Hit::Title
        } else if contains(&self.canvas, x, y) {
            Hit::Canvas
        } else if contains(&self.undo, x, y) {
            Hit::Control(Control::Undo)
        } else if contains(&self.clear, x, y) {
            Hit::Control(Control::Clear)
        } else if contains(&self.strip, x, y) {
            self.chips
                .iter()
                .position(|chip| contains(chip, x, y))
                .map_or(Hit::Nothing, |index| {
                    Hit::Control(Control::Candidate(index))
                })
        } else {
            Hit::Nothing
        }
    }

    fn edge(&self, x: f32, y: f32) -> Option<Edge> {
        let border = size::RESIZE_BORDER;
        if x < 0.0 || y < 0.0 || x >= self.width || y >= self.height {
            return None;
        }
        let left = x < border;
        let right = x >= self.width - border;
        let top = y < border;
        let bottom = y >= self.height - border;
        match (left, right, top, bottom) {
            (true, _, true, _) => Some(Edge::TopLeft),
            (_, true, true, _) => Some(Edge::TopRight),
            (true, _, _, true) => Some(Edge::BottomLeft),
            (_, true, _, true) => Some(Edge::BottomRight),
            (true, _, _, _) => Some(Edge::Left),
            (_, true, _, _) => Some(Edge::Right),
            // 上の辺は閉じるボタンの上では閉じるを優先する(Windows 11 と同じ)
            (_, _, true, _) if !contains(&self.close, x, y) => Some(Edge::Top),
            (_, _, _, true) => Some(Edge::Bottom),
            _ => None,
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
        let line = size::FRAME_WIDTH;
        let dash = size::GUIDE_DASH;
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

    /// 候補の行の左と右に，まだ送れる続きがあるか(端を薄くして示す)
    pub fn overflows(&self) -> (bool, bool) {
        (self.scroll > 0.5, self.scroll < self.max_scroll - 0.5)
    }
}

fn contains(frame: &Frame, x: f32, y: f32) -> bool {
    x >= frame.x && x < frame.max_x() && y >= frame.y && y < frame.max_y()
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fixed;

    impl TextWidth for Fixed {
        fn candidate_width(&self, text: &str) -> f32 {
            text.chars().count() as f32 * 18.0
        }

        fn label_width(&self, text: &str) -> f32 {
            text.chars().count() as f32 * 14.0
        }
    }

    fn layout(candidates: &[&str], width: f32, height: f32, scroll: f32) -> Layout {
        let candidates: Vec<String> = candidates.iter().map(|text| text.to_string()).collect();
        Layout::new(width, height, &candidates, "消去", scroll, &Fixed)
    }

    fn smallest(candidates: &[&str]) -> Layout {
        let (width, height) = minimum_size();
        layout(candidates, width, height, 0.0)
    }

    #[test]
    fn いちばん小さい窓では書く欄をmacの既定と同じ大きさにする() {
        let layout = smallest(&[]);
        assert_eq!(layout.canvas.width, layout.canvas.height);
        assert_eq!(layout.canvas.width, size::CANVAS_SIZE);
        assert!(layout.canvas.y >= layout.title.max_y() + size::CANVAS_PADDING);
        assert!(layout.canvas.max_y() <= layout.strip.y - size::CANVAS_PADDING);
        assert_eq!(layout.strip.max_y(), layout.height - size::CANVAS_PADDING);
        assert_eq!(layout.clear.max_x(), layout.width - size::CANVAS_PADDING);
        assert!(layout.undo.max_x() <= layout.clear.x);
        assert!(layout.strip.max_x() <= layout.undo.x);
    }

    #[test]
    fn 窓を広げると書く欄も正方形のまま大きくなり真ん中に置く() {
        let layout = layout(&[], 500.0, 600.0, 0.0);
        assert_eq!(layout.canvas.width, layout.canvas.height);
        assert_eq!(layout.canvas.width, 500.0 - size::CANVAS_PADDING * 2.0);
        let middle = layout.title.max_y() + (layout.strip.y - layout.title.max_y()) / 2.0;
        assert!((layout.canvas.mid_y() - middle).abs() <= 1.0);
        assert!((layout.canvas.mid_x() - 250.0).abs() <= 1.0);
    }

    #[test]
    fn 小さすぎる大きさはいちばん小さい窓に広げる() {
        let layout = layout(&[], 10.0, 10.0, 0.0);
        assert_eq!((layout.width, layout.height), minimum_size());
    }

    #[test]
    fn 候補は横に並べはみ出した分は送れる() {
        let many = vec!["鬱"; 12];
        let layout = smallest(&many);
        assert_eq!(layout.chips.len(), 12);
        assert!(layout.max_scroll > 0.0);
        assert_eq!(layout.overflows(), (false, true));
        for pair in layout.chips.windows(2) {
            assert_eq!(pair[1].x - pair[0].max_x(), size::CANDIDATE_GAP);
        }
        let (width, height) = minimum_size();
        let end = layout_end(&many, width, height);
        assert_eq!(end.scroll, end.max_scroll);
        assert_eq!(end.overflows(), (true, false));
        assert!((end.chips.last().unwrap().max_x() - end.strip.max_x()).abs() < 0.01);
    }

    fn layout_end(candidates: &[&str], width: f32, height: f32) -> Layout {
        layout(candidates, width, height, f32::MAX)
    }

    #[test]
    fn タグは字が短くても正方形より細くしない() {
        let layout = smallest(&["", "鬱"]);
        assert!(layout
            .chips
            .iter()
            .all(|chip| chip.width >= size::CONTROL_HEIGHT));
    }

    #[test]
    fn 押した場所で部品を見分ける() {
        let layout = smallest(&["鬱", "欝"]);
        let canvas = layout.canvas;
        assert_eq!(layout.hit(canvas.x + 1.0, canvas.y + 1.0), Hit::Canvas);
        let chip = layout.chips[1];
        assert_eq!(
            layout.hit(chip.x + 1.0, chip.y + 1.0),
            Hit::Control(Control::Candidate(1))
        );
        assert_eq!(
            layout.hit(layout.clear.x + 1.0, layout.clear.y + 1.0),
            Hit::Control(Control::Clear)
        );
        assert_eq!(
            layout.hit(layout.undo.x + 1.0, layout.undo.y + 1.0),
            Hit::Control(Control::Undo)
        );
        assert_eq!(
            layout.hit(layout.close.x + 10.0, 10.0),
            Hit::Control(Control::Close)
        );
        assert_eq!(layout.hit(100.0, 16.0), Hit::Title);
        assert_eq!(layout.hit(1.0, 100.0), Hit::Edge(Edge::Left));
        assert_eq!(layout.hit(100.0, 1.0), Hit::Edge(Edge::Top));
        assert_eq!(
            layout.hit(layout.width - 1.0, layout.height - 1.0),
            Hit::Edge(Edge::BottomRight)
        );
        // 閉じるボタンの上の辺は閉じるを優先する
        assert_eq!(
            layout.hit(layout.close.x + 10.0, 1.0),
            Hit::Control(Control::Close)
        );
    }

    #[test]
    fn 行の外に送った候補は押せない() {
        let many = vec!["鬱"; 12];
        let layout = smallest(&many);
        let hidden = layout
            .chips
            .iter()
            .position(|chip| chip.x >= layout.strip.max_x())
            .unwrap();
        let chip = layout.chips[hidden];
        assert_ne!(
            layout.hit(chip.x + 1.0, chip.y + 1.0),
            Hit::Control(Control::Candidate(hidden))
        );
    }

    #[test]
    fn 書く欄の外の点は端に留める() {
        let layout = smallest(&[]);
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
        let layout = smallest(&[]);
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
    }
}
