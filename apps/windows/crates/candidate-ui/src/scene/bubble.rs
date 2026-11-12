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
use super::{Color, Draw, Figure, Frame, Look, Measure, Point, Scene, Segment};
use ipc::HomophoneNote;
use tokens::size::{bubble, glass, part};

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
    /// 画面の端に寄せたときの，吹き出しの縁と画面の端のあいだ
    pub screen_margin: f32,
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
            screen_margin: bubble::SCREEN_MARGIN,
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
    // 画面の端から screen_margin の内側に収める
    let screen = screen.inset(metrics.screen_margin, metrics.screen_margin);
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
    }
}

/// 一覧で吹き出しに出す語の意味と同音語の札の語，先で指す行(候補の窓の場面の座標)．
/// 候補の右(吹き出し)に出す設定で，候補を選んでいて意味があるときだけ
pub fn for_list<'a>(
    list: &'a ipc::CandidateList,
    scene: &Scene,
) -> Option<(&'a HomophoneNote, Vec<String>, Frame)> {
    if meaning::placement(list.meaning_placement) != ipc::MeaningPlacement::Side
        || list.focus != ipc::CandidateFocus::Candidate
    {
        return None;
    }
    let note = list.homophone.as_ref()?;
    let index = list.selected_entry?;
    let row = target_row(scene, &ipc::PointerTarget::Entry { index })?;
    Some((note, note.others.clone(), row))
}

/// 分岐図で吹き出しに出す語の意味と同音語の札の語(枝に出ていない語だけ)，先で指す枝の行．
/// 候補の右(吹き出し)に出す設定で，注目している文節で候補を選んでいて意味があり，区切っていないときだけ
pub fn for_branch<'a>(
    map: &'a ipc::BranchMap,
    scene: &Scene,
) -> Option<(&'a HomophoneNote, Vec<String>, Frame)> {
    if meaning::placement(map.meaning_placement) != ipc::MeaningPlacement::Side {
        return None;
    }
    let column = map.columns.iter().find(|column| column.is_focused)?;
    if column.split.is_some() {
        return None;
    }
    let note = column.homophone.as_ref()?;
    let index = column.selected_alternative?;
    let row = target_row(scene, &ipc::PointerTarget::Alternative { index })?;
    Some((note, meaning::branch_others(note, column), row))
}

/// 押せる範囲から，選んでいる行の枠を探す(押せる範囲は行と同じ高さ)
fn target_row(scene: &Scene, target: &ipc::PointerTarget) -> Option<Frame> {
    scene
        .hits
        .iter()
        .find(|hit| &hit.target == target)
        .map(|hit| hit.frame)
}

/// 置き方の決まった吹き出しの窓を描く．地と縁は候補の窓と同じ色で，先まで 1 本の線で縁取る．
/// 角丸のテーマは，候補の窓(scene::surround)と同じぼかした影を本体の下に付け，そのぶん窓のまわりを空ける．
/// 返す場面の body が吹き出し(本体と先)の枠なので，窓は placement.window の左上から body の分だけずらして置く
pub fn bubble_scene(
    bubble: &Bubble,
    placement: &Placement,
    look: &Look,
    measure: &dyn Measure,
) -> Scene {
    let mut painter = Painter::new(look, measure);
    let theme = look.theme;
    let metrics = Metrics::tokens(theme.is_rounded());
    let (margin, offset) = if theme.is_rounded() {
        (glass::SHADOW_RADIUS, glass::SHADOW_OFFSET_Y)
    } else {
        (0.0, 0.0)
    };
    let shift = |frame: Frame| frame.offset(margin, margin);
    if theme.is_rounded() {
        painter.draws.push(Draw::Shadow {
            frame: shift(placement.body).offset(0.0, offset),
            radius: metrics.radius,
            blur: margin,
            color: Color::rgb(tokens::GLASS_SHADOW).with_alpha(tokens::opacity::shadow::WINDOW),
        });
    }
    let shape = outline(placement, &metrics, part::STROKE);
    painter.draws.push(
        Draw::Shape {
            figure: shape,
            fill: Some(theme.surface),
            stroke: Some((theme.frame, part::STROKE)),
        }
        .offset(margin, margin),
    );
    let content = shift(Frame::new(
        placement.body.x + metrics.padding,
        placement.body.y + metrics.padding,
        bubble.card.width,
        bubble.card.height,
    ));
    meaning::draw(&mut painter, &bubble.card, content);
    let mut scene = painter.finish(
        placement.window.width + margin * 2.0,
        placement.window.height + margin * 2.0 + offset,
    );
    scene.body = Frame::new(
        margin,
        margin,
        placement.window.width,
        placement.window.height,
    );
    scene
}

/// 候補の窓の場面 window の横に，row(window の座標)を指す吹き出しを並べた 1 つの場面(画像への書き出しに使う．
/// 画面は十分に広いとみなして右に出す)
pub fn beside(
    window: Scene,
    note: &HomophoneNote,
    others: Vec<String>,
    row: Frame,
    look: &Look,
    measure: &dyn Measure,
) -> Scene {
    let shown = bubble(note, others, look, measure);
    let placement = place(
        window.body,
        row.mid_y(),
        (shown.width, shown.height),
        shown.preferred_pointer,
        Frame::new(-10000.0, -10000.0, 20000.0, 20000.0),
        &Metrics::tokens(look.theme.is_rounded()),
    );
    let drawn = bubble_scene(&shown, &placement, look, measure);
    let x = placement.window.x - drawn.body.x;
    let y = placement.window.y - drawn.body.y;
    // 吹き出しが窓の上にはみ出すときは，全体を下へずらす
    let shift = (-y).max(0.0);
    let mut draws: Vec<Draw> = window
        .draws
        .into_iter()
        .map(|draw| draw.offset(0.0, shift))
        .collect();
    draws.extend(
        drawn
            .draws
            .into_iter()
            .map(|draw| draw.offset(x, y + shift)),
    );
    let width = window.width.max(x + drawn.width);
    let height = (window.height + shift).max(y + shift + drawn.height);
    Scene {
        width,
        height,
        body: Frame::new(0.0, 0.0, width, height),
        draws,
        hits: Vec::new(),
    }
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
        screen_margin: 12.0,
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
            anchor(100.0, 580.0),
            760.0,
            (288.0, 160.0),
            20.0,
            SCREEN,
            &METRICS,
        );
        // 画面の下の端から screen_margin だけ離す
        assert_eq!(
            placed.window.max_y(),
            SCREEN.max_y() - METRICS.screen_margin
        );
        assert_eq!(placed.window.y + placed.pointer_y, 760.0);
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
        assert_eq!(placed.window.y, SCREEN.y + METRICS.screen_margin);
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
