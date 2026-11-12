#![forbid(unsafe_code)]

//! 語の意味の吹き出し(R-08．macOS の MeaningBubble と同じ決め方)．
//!
//! 候補の窓の外に出す小さな窓で，三角で選んでいる候補の行の縦の真ん中を指す．
//! - 候補の窓の右に出す．画面の右の端に入らなければ左に出す
//! - 縦は，吹き出しの上の端を候補の窓の上の端にそろえ，三角だけを動かして行を指す(候補を移っても吹き出しは動かない)．
//!   三角が行に届かないときだけ，届くところまで下げる．画面の上下の端からはみ出さないように寄せる
//! - 背景・枠線・角の丸みは候補の窓と同じ決まりにし，枠線は三角まで途切れずにつなぐ
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
    /// 本体の幅(枠線を含み，三角を除く)
    pub width: f32,
    pub padding: f32,
    pub radius: f32,
    pub pointer_length: f32,
    pub pointer_width: f32,
    /// 候補の窓の枠線と三角の頂点のあいだ
    pub gap: f32,
    /// 画面の端に寄せたときの，吹き出しの端と画面の端のあいだ
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
    /// 窓(本体と三角)の枠．画面の座標
    pub window: Frame,
    /// 本体の枠．窓の中の座標
    pub body: Frame,
    /// 三角の頂点の y．窓の中の座標
    pub pointer_y: f32,
}

/// 吹き出しの窓の置き方を決める(core の MeaningBubbleLayout と同じ決め方)．
/// 三角の頂点は選んでいる行 row の右の端から gap(inline)の所に置き，行の縦の真ん中を指す．
/// 候補の窓 window の空いている所に重ねてよいが，obstacles(ほかの候補・幹の文節・足元の案内・入力中の文字)は覆わない．
/// 覆ってしまう物があれば上か下へ寄せ，行の横に置けなければ候補の窓の右の外，それも無理なら窓の左の外に置く．
/// 上の端は候補の窓の上の端にそろえ，三角が行に届かないときだけ下げる．
/// size は本体の大きさ，screen は画面の使える範囲(どれも画面の座標)
pub fn place(
    row: Frame,
    window: Frame,
    size: (f32, f32),
    screen: Frame,
    obstacles: &[Frame],
    metrics: &Metrics,
) -> Placement {
    let (width, height) = size;
    // 画面の端から screen_margin の内側に収める
    let screen = screen.inset(metrics.screen_margin, metrics.screen_margin);
    let window_width = width + metrics.pointer_length;
    let target = row.mid_y();
    let half = metrics.pointer_width / 2.0;
    let (lowest, highest) = (metrics.radius + half, height - metrics.radius - half);
    // 上の端は候補の窓の上の端．三角が行に届かなければ，届くところまで下げる
    let preferred_y = window.y.max(target - highest);
    // 窓の左の端を x に置いたときの縦の位置と三角の位置．覆う物があれば上か下へ寄せる．置けなければ None
    let vertical = |x: f32| -> Option<(f32, f32)> {
        if x < screen.x || x + window_width > screen.max_x() {
            return None;
        }
        let (mut top, mut bottom) = (screen.y.max(window.y), screen.max_y());
        // 候補の窓の上の端より上にある物(入力中の文字の行など)は，上の端にそろえるだけで覆わないので見ない．
        // 見ると，窓と入力中の文字のあいだが gap より狭いときに，吹き出しだけが窓の上の端より下がる
        for obstacle in obstacles.iter().filter(|obstacle| {
            obstacle.x < x + window_width && x < obstacle.max_x() && obstacle.max_y() > window.y
        }) {
            if obstacle.y >= target {
                bottom = bottom.min(obstacle.y - metrics.gap);
            } else if obstacle.max_y() <= target {
                top = top.max(obstacle.max_y() + metrics.gap);
            } else {
                return None;
            }
        }
        if bottom - top < height {
            return None;
        }
        let y = preferred_y.max(top).min(bottom - height);
        let pointer = target - y;
        (lowest..=highest)
            .contains(&pointer)
            .then_some((y, pointer))
    };
    let beside_row = (Side::Right, row.max_x() + metrics.gap);
    let outside_right = (Side::Right, window.max_x() + metrics.gap);
    let outside_left = (Side::Left, window.x - metrics.gap - window_width);
    let found = [beside_row, outside_right, outside_left]
        .into_iter()
        .find_map(|(side, x)| vertical(x).map(|(y, pointer)| (side, x, y, pointer)));
    // どこにも置けなければ，候補の窓の右の外に置いて画面の中へ寄せる(三角は角の丸みにかけない範囲で行を指す)
    let (side, x, y, pointer) = found.unwrap_or_else(|| {
        let x = outside_right
            .1
            .min(screen.max_x() - window_width)
            .max(screen.x);
        let y = preferred_y.min(screen.max_y() - height).max(screen.y);
        (Side::Right, x, y, (target - y).max(lowest).min(highest))
    });
    let body_x = match side {
        Side::Right => metrics.pointer_length,
        Side::Left => 0.0,
    };
    Placement {
        side,
        window: Frame::new(x.round(), y.round(), window_width, height),
        body: Frame::new(body_x, 0.0, width, height),
        pointer_y: pointer.round(),
    }
}

/// 本体と三角を 1 本の線でなぞる閉じた図形．枠線の太さ stroke の半分だけ内側を通し，線をピクセルにそろえる
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
        // 三角は本体の右の辺
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
        // 三角は本体の左の辺
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
}

/// 語の意味の吹き出しの中身．others は同音語のタグに出す語
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
        card,
    }
}

/// 一覧で吹き出しに出す語の意味と同音語のタグの語，三角で指す行(候補の窓の場面の座標)．
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

/// 分岐図で吹き出しに出す語の意味と同音語のタグの語(枝に出ていない語だけ)，三角で指す枝の行．
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

/// 置き方の決まった吹き出しの窓を描く．背景と枠線は候補の窓と同じ色で，三角まで 1 本の線で枠線を引く．
/// 角丸のテーマは，候補の窓(scene::surround)と同じぼかした影を本体の下に付け，そのぶん窓のまわりを空ける．
/// 返す場面の body が吹き出し(本体と三角)の枠なので，窓は placement.window の左上から body の分だけずらして置く
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
        row,
        window.body,
        (shown.width, shown.height),
        Frame::new(-10000.0, -10000.0, 20000.0, 20000.0),
        &window.keep_clear,
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
        keep_clear: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const METRICS: Metrics = Metrics {
        width: 288.0,
        padding: 12.0,
        radius: 12.0,
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

    /// 窓・選んでいる行・覆わない物
    type Setup = (Frame, Frame, Vec<Frame>);

    /// 一覧の窓(幅 300)．行の背景は窓の左右の余白 12 の内側
    fn list(x: f32, y: f32, selected: usize) -> Setup {
        let window = Frame::new(x, y, 300.0, 200.0);
        let rows: Vec<Frame> = (0..4)
            .map(|index| Frame::new(x + 12.0, y + 12.0 + 28.0 * index as f32, 276.0, 24.0))
            .collect();
        let footer = Frame::new(x + 12.0, y + 160.0, 276.0, 28.0);
        let mut obstacles: Vec<Frame> = (0..4)
            .filter(|index| *index != selected)
            .map(|index| rows[index])
            .collect();
        obstacles.push(footer);
        (window, rows[selected], obstacles)
    }

    /// 足元の案内が長くて横に広い分岐図の窓(幅 800)．枝の行は左に寄り，足元は窓の幅いっぱい
    fn wide_branch(selected: usize) -> Setup {
        let window = Frame::new(100.0, 100.0, 800.0, 220.0);
        let rows: Vec<Frame> = (0..4)
            .map(|index| Frame::new(220.0, 140.0 + 28.0 * index as f32, 120.0, 24.0))
            .collect();
        let mut obstacles = vec![
            Frame::new(112.0, 112.0, 60.0, 24.0),
            Frame::new(180.0, 112.0, 60.0, 24.0),
        ];
        obstacles.extend(
            (0..4)
                .filter(|index| *index != selected)
                .map(|index| rows[index]),
        );
        obstacles.push(Frame::new(112.0, 270.0, 776.0, 38.0));
        (window, rows[selected], obstacles)
    }

    fn placed(setup: &Setup, size: (f32, f32), screen: Frame) -> Placement {
        place(setup.1, setup.0, size, screen, &setup.2, &METRICS)
    }

    fn body(placement: &Placement) -> Frame {
        Frame::new(
            placement.window.x + placement.body.x,
            placement.window.y,
            placement.body.width,
            placement.body.height,
        )
    }

    /// 三角の頂点(画面の座標)
    fn tip(placement: &Placement) -> Point {
        let x = match placement.side {
            Side::Right => placement.window.x,
            Side::Left => placement.window.max_x(),
        };
        Point::new(x, placement.window.y + placement.pointer_y)
    }

    fn intersects(a: Frame, b: Frame) -> bool {
        a.x < b.max_x() && b.x < a.max_x() && a.y < b.max_y() && b.y < a.max_y()
    }

    #[test]
    fn 三角の頂点は選んでいる行の右の端から_inline_の所で行の縦の真ん中を指す() {
        let setup = list(100.0, 100.0, 1);
        let placement = placed(&setup, (288.0, 160.0), SCREEN);
        assert_eq!(placement.side, Side::Right);
        assert_eq!(tip(&placement).x - setup.1.max_x(), METRICS.gap);
        assert_eq!(tip(&placement).y, setup.1.mid_y());
        assert_eq!(placement.window.y, setup.0.y);
    }

    #[test]
    fn 広い窓でも三角は選んでいる行のすぐ横で_ほかの候補と幹と足元を覆わない() {
        for selected in 0..4 {
            let setup = wide_branch(selected);
            let placement = placed(&setup, (288.0, 110.0), SCREEN);
            assert_eq!(
                tip(&placement).x - setup.1.max_x(),
                METRICS.gap,
                "{selected}"
            );
            assert_eq!(tip(&placement).y, setup.1.mid_y(), "{selected}");
            for obstacle in &setup.2 {
                assert!(
                    !intersects(body(&placement), *obstacle),
                    "{selected}: {obstacle:?}"
                );
            }
        }
    }

    #[test]
    fn 足元を覆う高さなら上へ寄せ_三角は行を指したまま() {
        let setup = wide_branch(3);
        let placement = placed(&setup, (288.0, 110.0), SCREEN);
        let footer = *setup.2.last().expect("足元");
        assert!(body(&placement).max_y() <= footer.y - METRICS.gap);
        assert_eq!(tip(&placement).y, setup.1.mid_y());
    }

    #[test]
    fn 行の横に入らなければ窓の外の右_画面に入らなければ左に出す() {
        let tall = placed(
            &wide_branch(1),
            (288.0, 400.0),
            Frame::new(0.0, 0.0, 1400.0, 800.0),
        );
        assert_eq!(tall.side, Side::Right);
        assert_eq!(tall.window.x, 100.0 + 800.0 + METRICS.gap);
        let near_edge = placed(&list(880.0, 100.0, 0), (288.0, 160.0), SCREEN);
        assert_eq!(near_edge.side, Side::Left);
        assert_eq!(near_edge.window.max_x(), 880.0 - METRICS.gap);
        assert_eq!(tip(&near_edge).y, 100.0 + 12.0 + 12.0);
    }

    #[test]
    fn 画面の下に入らなければ上へ寄せ_画面の端とのあいだを空ける() {
        // 窓の上の端にそろえると画面の下に入らない
        let setup = list(100.0, 650.0, 3);
        let placement = placed(&setup, (288.0, 160.0), SCREEN);
        assert!(placement.window.max_y() <= SCREEN.max_y() - METRICS.screen_margin);
        assert_eq!(tip(&placement).y, setup.1.mid_y());
    }

    #[test]
    fn 吹き出しの上の端は候補の窓の上の端にそろえ_候補を移っても三角だけが動く() {
        for selected in 0..4 {
            let setup = list(100.0, 100.0, selected);
            let placement = placed(&setup, (288.0, 160.0), SCREEN);
            assert_eq!(placement.window.y, setup.0.y, "{selected}");
            assert_eq!(tip(&placement).y, setup.1.mid_y(), "{selected}");
        }
    }

    #[test]
    fn 入力中の文字の行が窓のすぐ上にあっても吹き出しの上の端は窓の上の端にそろう() {
        // 入力位置と候補の窓のあいだは ANCHOR_GAP の 2(gap の 4 より狭い)
        let mut setup = list(100.0, 100.0, 1);
        setup.2.push(Frame::new(0.0, 80.0, 1200.0, 18.0));
        let placement = placed(&setup, (288.0, 160.0), SCREEN);
        assert_eq!(placement.window.y, setup.0.y);
        assert_eq!(tip(&placement).y, setup.1.mid_y());
    }

    #[test]
    fn 三角が行に届かないときだけ届くところまで下げる() {
        let setup = list(100.0, 100.0, 3);
        let short = placed(&setup, (288.0, 100.0), SCREEN);
        assert!(short.window.y > setup.0.y);
        assert_eq!(
            short.pointer_y,
            100.0 - METRICS.radius - METRICS.pointer_width / 2.0
        );
        assert_eq!(tip(&short).y, setup.1.mid_y());
    }

    #[test]
    fn 候補の窓より高い吹き出しも窓の上の端にそろえる() {
        let setup = list(100.0, 100.0, 1);
        let placement = placed(&setup, (288.0, 260.0), SCREEN);
        assert_eq!(placement.window.y, setup.0.y);
        assert_eq!(tip(&placement).y, setup.1.mid_y());
    }

    #[test]
    fn 枠線は三角まで途切れずにつながる() {
        for x in [100.0, 880.0] {
            let placement = placed(&list(x, 100.0, 1), (288.0, 160.0), SCREEN);
            let figure = outline(&placement, &METRICS, 1.0);
            let points: Vec<Point> = figure
                .segments
                .iter()
                .map(|segment| match segment {
                    Segment::Line(to) | Segment::Arc { to, .. } => *to,
                })
                .collect();
            assert_eq!(*points.last().expect("点"), figure.start);
            let tip_x = match placement.side {
                Side::Right => 0.5,
                Side::Left => placement.window.width - 0.5,
            };
            assert!(points
                .iter()
                .any(|point| point.x == tip_x && point.y == placement.pointer_y));
        }
    }
}
