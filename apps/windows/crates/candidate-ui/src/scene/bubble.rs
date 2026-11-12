#![forbid(unsafe_code)]

//! 語の意味の吹き出し(R-08．macOS の MeaningBubble と同じ決め方)．
//!
//! 候補の窓の外に出す小さな窓で，先(三角)で選んでいる候補の行の縦の真ん中を指す．
//! - 候補の窓の右に出す．画面の右の端に入らなければ左に出す
//! - 縦は，先が選んでいる行を指す位置(先は見出しの行の高さ)にし，画面の上下の端からはみ出さないように寄せる．
//!   寄せた分だけ先の位置をずらし，行を指し続ける
//! - 地・縁・角の丸みは候補の窓と同じ決まりにし，縁の線は先まで途切れずにつなぐ
//! - 中身は語の意味の配置(card_layout)をそのまま使う．アクセントの色は使わない
//!
//! 座標は下が y の正

use super::card_layout::{self, Placement as CardPlacement};
use super::meaning::{self, Card};
use super::paint::Painter;
use super::{Draw, Figure, Frame, Look, Measure, Point, Scene, Segment};
use ipc::HomophoneNote;
use tokens::size::{bubble, part};

/// 吹き出しを候補の窓のどちら側に出すか
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Side {
    Right,
    Left,
}

/// 吹き出しの寸法
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Metrics {
    /// 本体の幅(縁を含み，先を除く)
    pub width: f32,
    pub padding: f32,
    pub radius: f32,
    pub pointer_length: f32,
    pub pointer_width: f32,
    /// 候補の窓の縁と先の頂点のあいだ
    pub gap: f32,
}

impl Metrics {
    /// rounded は角丸のテーマか(platinum と desk は角を丸めない)
    pub fn tokens(rounded: bool) -> Self {
        Self {
            width: bubble::WIDTH,
            padding: bubble::PADDING,
            radius: if rounded { bubble::RADIUS } else { 0.0 },
            pointer_length: bubble::POINTER_LENGTH,
            pointer_width: bubble::POINTER_WIDTH,
            gap: bubble::GAP,
        }
    }
}

/// 吹き出しの窓の置き方
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Placement {
    pub side: Side,
    /// 窓(本体と先)の枠．画面の座標
    pub window: Frame,
    /// 本体の枠．窓の中の座標
    pub body: Frame,
    /// 先の頂点の y．窓の中の座標
    pub pointer_y: f32,
}

/// 吹き出しの窓の置き方を決める．
/// anchor は候補の窓の本体の枠，target_y は選んでいる行の縦の真ん中，size は本体の大きさ，
/// preferred は本体の上の端から先までの長さ(見出しの行の真ん中)，screen は画面の使える範囲(どれも画面の座標)
pub fn place(
    anchor: Frame,
    target_y: f32,
    size: (f32, f32),
    preferred: f32,
    screen: Frame,
    metrics: &Metrics,
) -> Placement {
    let (width, height) = size;
    let window_width = width + metrics.pointer_length;
    let reach = metrics.gap + window_width;
    let fits_right = anchor.max_x() + reach <= screen.max_x();
    let fits_left = anchor.x - reach >= screen.x;
    // 右に入らなければ左．どちらにも入らなければ右に出し，画面の中へ寄せる
    let side = if fits_right || !fits_left {
        Side::Right
    } else {
        Side::Left
    };
    let x = match side {
        Side::Right => anchor.max_x() + metrics.gap,
        Side::Left => anchor.x - reach,
    }
    .min(screen.max_x() - window_width)
    .max(screen.x);
    // 縦: 先が行を指す位置にし，画面の上下に収める
    let y = (target_y - preferred)
        .min(screen.max_y() - height)
        .max(screen.y);
    // 先は角の丸みにかからない範囲で行を指す
    let half = metrics.pointer_width / 2.0;
    let pointer_y = (target_y - y)
        .max(metrics.radius + half)
        .min(height - metrics.radius - half);
    let body_x = match side {
        Side::Right => metrics.pointer_length,
        Side::Left => 0.0,
    };
    Placement {
        side,
        window: Frame::new(x.round(), y.round(), window_width, height),
        body: Frame::new(body_x, 0.0, width, height),
        pointer_y: pointer_y.round(),
    }
}

/// 本体と先を 1 本の線でなぞる閉じた図形．縁の線の太さ stroke の半分だけ内側を通し，線をピクセルにそろえる
pub fn outline(placement: &Placement, metrics: &Metrics, stroke: f32) -> Figure {
    let half_stroke = stroke / 2.0;
    let body = placement.body.inset(half_stroke, half_stroke);
    let radius = (metrics.radius - half_stroke).max(0.0);
    let (top, bottom) = (body.y, body.max_y());
    let (left, right) = (body.x, body.max_x());
    let y = placement.pointer_y;
    let half = metrics.pointer_width / 2.0;
    let arc = |to: Point| Segment::Arc {
        to,
        radius,
        clockwise: true,
    };
    let mut segments = vec![Segment::Line(Point::new(right - radius, top))];
    if radius > 0.0 {
        segments.push(arc(Point::new(right, top + radius)));
    }
    if placement.side == Side::Left {
        // 先は本体の右の辺
        segments.push(Segment::Line(Point::new(right, y - half)));
        segments.push(Segment::Line(Point::new(right + metrics.pointer_length, y)));
        segments.push(Segment::Line(Point::new(right, y + half)));
    }
    segments.push(Segment::Line(Point::new(right, bottom - radius)));
    if radius > 0.0 {
        segments.push(arc(Point::new(right - radius, bottom)));
    }
    segments.push(Segment::Line(Point::new(left + radius, bottom)));
    if radius > 0.0 {
        segments.push(arc(Point::new(left, bottom - radius)));
    }
    if placement.side == Side::Right {
        // 先は本体の左の辺
        segments.push(Segment::Line(Point::new(left, y + half)));
        segments.push(Segment::Line(Point::new(left - metrics.pointer_length, y)));
        segments.push(Segment::Line(Point::new(left, y - half)));
    }
    segments.push(Segment::Line(Point::new(left, top + radius)));
    if radius > 0.0 {
        segments.push(arc(Point::new(left + radius, top)));
    }
    Figure {
        start: Point::new(left + radius, top),
        segments,
    }
}

/// 中身を決めた吹き出し．width・height は本体の大きさ
pub struct Bubble {
    card: Card,
    position: CardPlacement,
    pub width: f32,
    pub height: f32,
    /// 本体の上の端から先までの長さ(見出しの行の縦の真ん中)
    pub preferred_pointer: f32,
}

/// 語の意味の吹き出しの中身．others は同音語の札に出す語
pub fn bubble(
    note: &HomophoneNote,
    others: Vec<String>,
    look: &Look,
    measure: &dyn Measure,
) -> Bubble {
    let painter = Painter::new(look, measure);
    let metrics = Metrics::tokens(look.theme.is_rounded());
    let header = card_layout::header_height(look.theme);
    let position = CardPlacement {
        left: 0.0,
        header_mid_y: header / 2.0,
    };
    let card = Card::new(
        &painter,
        note,
        others,
        metrics.width - metrics.padding * 2.0,
        position,
    );
    Bubble {
        height: card.height + metrics.padding * 2.0,
        width: metrics.width,
        preferred_pointer: metrics.padding + header / 2.0,
        card,
        position,
    }
}

/// 置き方の決まった吹き出しの窓を描く．地と縁は候補の窓と同じ色で，先まで 1 本の線で縁取る
pub fn bubble_scene(
    bubble: &Bubble,
    placement: &Placement,
    look: &Look,
    measure: &dyn Measure,
) -> Scene {
    let mut painter = Painter::new(look, measure);
    let theme = look.theme;
    let metrics = Metrics::tokens(theme.is_rounded());
    painter.draws.push(Draw::Shape {
        figure: outline(placement, &metrics, part::STROKE),
        fill: Some(theme.surface),
        stroke: Some((theme.frame, part::STROKE)),
    });
    let content = Frame::new(
        placement.body.x + metrics.padding,
        placement.body.y + metrics.padding,
        bubble.card.width,
        bubble.card.height,
    );
    meaning::draw(&mut painter, Some(&bubble.card), content, bubble.position);
    painter.finish(placement.window.width, placement.window.height)
}

#[cfg(test)]
mod tests {
    use super::*;

    const METRICS: Metrics = Metrics {
        width: 288.0,
        padding: 12.0,
        radius: 8.0,
        pointer_length: 8.0,
        pointer_width: 16.0,
        gap: 4.0,
    };
    const SCREEN: Frame = Frame {
        x: 0.0,
        y: 0.0,
        width: 1200.0,
        height: 800.0,
    };

    fn anchor(x: f32, y: f32) -> Frame {
        Frame::new(x, y, 300.0, 200.0)
    }

    #[test]
    fn 右に入れば右に出し_先は選んでいる行を指す() {
        let placed = place(
            anchor(100.0, 100.0),
            150.0,
            (288.0, 160.0),
            20.0,
            SCREEN,
            &METRICS,
        );
        assert_eq!(placed.side, Side::Right);
        // 先の頂点は候補の窓の右の縁から gap だけ離れる
        assert_eq!(placed.window.x, 100.0 + 300.0 + METRICS.gap);
        assert_eq!(placed.body.x, METRICS.pointer_length);
        assert_eq!(placed.window.y + placed.pointer_y, 150.0);
        // 先は見出しの行の高さ
        assert_eq!(placed.pointer_y, 20.0);
    }

    #[test]
    fn 画面の右の端に入らなければ左に出す() {
        let placed = place(
            anchor(800.0, 100.0),
            150.0,
            (288.0, 160.0),
            20.0,
            SCREEN,
            &METRICS,
        );
        assert_eq!(placed.side, Side::Left);
        assert_eq!(placed.window.max_x(), 800.0 - METRICS.gap);
        assert_eq!(placed.body.x, 0.0);
        assert_eq!(placed.window.y + placed.pointer_y, 150.0);
    }

    #[test]
    fn 画面の下に入らなければ上へ寄せ_先は行を指し続ける() {
        let placed = place(
            anchor(100.0, 600.0),
            780.0,
            (288.0, 160.0),
            20.0,
            SCREEN,
            &METRICS,
        );
        assert_eq!(placed.window.max_y(), SCREEN.max_y());
        assert_eq!(placed.window.y + placed.pointer_y, 780.0);
        // 先は角の丸みにかからない
        assert!(placed.pointer_y <= 160.0 - METRICS.radius - METRICS.pointer_width / 2.0);
    }

    #[test]
    fn 画面の上に入らなければ下へ寄せる() {
        let placed = place(
            anchor(100.0, 0.0),
            6.0,
            (288.0, 160.0),
            20.0,
            SCREEN,
            &METRICS,
        );
        assert_eq!(placed.window.y, SCREEN.y);
        // 行が角の丸みより上なら，先は角の丸みのすぐ下で止める
        assert_eq!(
            placed.pointer_y,
            METRICS.radius + METRICS.pointer_width / 2.0
        );
    }

    #[test]
    fn 縁の線は先まで途切れずにつながる() {
        for side in [Side::Right, Side::Left] {
            let x = if side == Side::Right { 100.0 } else { 800.0 };
            let placed = place(
                anchor(x, 100.0),
                150.0,
                (288.0, 160.0),
                20.0,
                SCREEN,
                &METRICS,
            );
            assert_eq!(placed.side, side);
            let figure = outline(&placed, &METRICS, 1.0);
            let points: Vec<Point> = figure
                .segments
                .iter()
                .map(|segment| match segment {
                    Segment::Line(to) | Segment::Arc { to, .. } => *to,
                })
                .collect();
            // 最後の点で始まりに戻る(閉じた 1 本の線)
            assert_eq!(*points.last().expect("点"), figure.start);
            // 先の頂点は窓の端
            let tip = points
                .iter()
                .copied()
                .find(|point| {
                    point.y == placed.pointer_y
                        && (point.x < 1.0 || point.x > placed.window.width - 1.0)
                })
                .expect("先の頂点");
            match side {
                Side::Right => assert_eq!(tip.x, 0.5),
                Side::Left => assert_eq!(tip.x, placed.window.width - 0.5),
            }
        }
    }
}
