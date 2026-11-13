#![forbid(unsafe_code)]

//! 分岐図の部品を描く(macOS の BranchMapDrawing)．線の上の丸，丸を避けて引く線，文節の境目のつまみ，続きがある印の線，
//! 窓からはみ出した幹を端へ向けて透かす描き方．
//!
//! 角丸のテーマは丸と丸い角の線，platinum と desk は四角と 1 ドットの線(デバイスのピクセルにそろえる)で描く

use super::paint::Painter;
use super::{Color, Draw, Figure, Frame, Point, Segment};
use tokens::size::{branch_map, glass, space};

/// 丸の状態
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum State {
    /// 選んでいない
    Plain,
    /// 選んだ道すじの途中にある
    Passed,
    /// 選んでいる
    Selected,
}

/// 線の上の丸．文節・候補・文字種・先の枝のどれも同じ形にする
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Stop {
    pub center: Point,
    pub state: State,
    pub opacity: f32,
}

impl Stop {
    pub fn new(center: Point, state: State) -> Self {
        Self {
            center,
            state,
            opacity: 1.0,
        }
    }

    pub fn size(&self) -> f32 {
        if self.state == State::Selected {
            branch_map::STOP_SIZE_SELECTED
        } else {
            branch_map::STOP_SIZE
        }
    }

    pub fn frame(&self) -> Frame {
        let size = self.size();
        Frame::new(
            (self.center.x - size / 2.0).round(),
            (self.center.y - size / 2.0).round(),
            size,
            size,
        )
    }
}

/// 折れ線．points を順につなぎ，角は radius で丸める(0 なら直角)．線は縦か横だけ
#[derive(Debug, Clone, PartialEq)]
pub struct Line {
    pub points: Vec<Point>,
    pub radius: f32,
    /// 点線にする(確信の低い文節の下の幹)
    pub dotted: bool,
}

impl Line {
    pub fn new(points: Vec<Point>) -> Self {
        Self {
            points,
            radius: 0.0,
            dotted: false,
        }
    }

    pub fn rounded(points: Vec<Point>, radius: f32) -> Self {
        Self {
            points,
            radius,
            dotted: false,
        }
    }
}

/// 折れ線を区間に分けたもの
#[derive(Debug, Clone, Copy, PartialEq)]
enum Piece {
    Straight(Point, Point),
    Arc {
        from: Point,
        to: Point,
        radius: f32,
        clockwise: bool,
    },
}

/// 折れ線を，角を丸めた区間の並びにする．角の半径は前後の区間の長さの半分までに縮める
fn pieces(line: &Line) -> Vec<Piece> {
    let points = &line.points;
    if points.len() < 2 {
        return Vec::new();
    }
    let mut result = Vec::new();
    let mut start = points[0];
    for index in 1..points.len() {
        let corner = points[index];
        let Some(next) = points.get(index + 1).filter(|_| line.radius > 0.0) else {
            result.push(Piece::Straight(start, corner));
            start = corner;
            continue;
        };
        let incoming = distance(start, corner);
        let outgoing = distance(corner, *next);
        let radius = line.radius.min(incoming).min(outgoing / 2.0);
        let into = direction(start, corner);
        let out = direction(corner, *next);
        if radius <= 0.0 || (into.x == out.x && into.y == out.y) {
            result.push(Piece::Straight(start, corner));
            start = corner;
            continue;
        }
        let from = Point::new(corner.x - into.x * radius, corner.y - into.y * radius);
        let to = Point::new(corner.x + out.x * radius, corner.y + out.y * radius);
        result.push(Piece::Straight(start, from));
        // y が下へ増える画面で，右へ曲がる角が時計回り
        let clockwise = into.x * out.y - into.y * out.x > 0.0;
        result.push(Piece::Arc {
            from,
            to,
            radius,
            clockwise,
        });
        start = to;
    }
    result
}

fn distance(from: Point, to: Point) -> f32 {
    ((to.x - from.x).powi(2) + (to.y - from.y).powi(2)).sqrt()
}

fn direction(from: Point, to: Point) -> Point {
    let length = distance(from, to).max(f32::EPSILON);
    Point::new((to.x - from.x) / length, (to.y - from.y) / length)
}

/// 縦か横の区間から，丸(stops)の内側を切り抜く．線を丸の内側に通さず，丸を輪で描けるようにする
fn cut(from: Point, to: Point, stops: &[Stop]) -> Vec<(Point, Point)> {
    let vertical = (from.x - to.x).abs() < (from.y - to.y).abs();
    let along: fn(Point) -> f32 = if vertical {
        |point| point.y
    } else {
        |point| point.x
    };
    let across = if vertical { from.x } else { from.y };
    let (start, end) = (along(from), along(to));
    let (low, high) = (start.min(end), start.max(end));
    let mut holes: Vec<(f32, f32)> = stops
        .iter()
        .filter_map(|stop| {
            let half = stop.size() / 2.0;
            let (center_along, center_across) = if vertical {
                (stop.center.y, stop.center.x)
            } else {
                (stop.center.x, stop.center.y)
            };
            ((center_across - across).abs() < half
                && center_along + half > low
                && center_along - half < high)
                .then_some((center_along - half, center_along + half))
        })
        .collect();
    holes.sort_by(|a, b| a.0.total_cmp(&b.0));
    let mut runs = Vec::new();
    let mut cursor = low;
    for (hole_start, hole_end) in holes {
        if hole_start > cursor {
            runs.push((cursor, hole_start));
        }
        cursor = cursor.max(hole_end);
    }
    if high > cursor {
        runs.push((cursor, high));
    }
    let point = |value: f32| {
        if vertical {
            Point::new(across, value)
        } else {
            Point::new(value, across)
        }
    };
    runs.into_iter()
        .filter(|(a, b)| b - a > 0.01)
        .map(|(a, b)| (point(a), point(b)))
        .collect()
}

/// 線の真ん中を，太さ width の線がデバイスのピクセルを埋める位置にそろえる
fn align(value: f32, width: f32, scale: f32) -> f32 {
    let scale = scale.max(1.0);
    let half = if ((width * scale).round() as i32) % 2 == 1 {
        0.5
    } else {
        0.0
    };
    ((value * scale - half).round() + half) / scale
}

/// 折れ線の点を，太さ width の線がデバイスのピクセルを埋める位置にそろえる．縦の区間の点は x を，横の区間の点は y をそろえる
fn aligned(line: &Line, width: f32, scale: f32) -> Line {
    let mut points = line.points.clone();
    for index in 1..line.points.len() {
        let (from, to) = (line.points[index - 1], line.points[index]);
        let vertical = (from.x - to.x).abs() < (from.y - to.y).abs();
        for at in [index - 1, index] {
            if vertical {
                points[at].x = align(line.points[at].x, width, scale);
            } else {
                points[at].y = align(line.points[at].y, width, scale);
            }
        }
    }
    Line {
        points,
        ..line.clone()
    }
}

/// 線を描く．丸(avoiding)の内側には線を通さない．scale は 1 ドットあたりのデバイスのピクセル数
pub fn stroke(
    painter: &mut Painter,
    lines: &[Line],
    color: Color,
    width: f32,
    avoiding: &[Stop],
    scale: f32,
) {
    let rounded = painter.theme.is_rounded();
    let mut figures: Vec<Figure> = Vec::new();
    fn flush(current: &mut Option<Figure>, figures: &mut Vec<Figure>) {
        if let Some(figure) = current.take() {
            if !figure.segments.is_empty() {
                figures.push(figure);
            }
        }
    }
    for line in lines {
        let line = aligned(line, width, scale);
        let mut current: Option<Figure> = None;
        for piece in pieces(&line) {
            match piece {
                Piece::Straight(from, to) => {
                    let mut runs = cut(from, to, avoiding);
                    // cut は小さい側から並べるので，線の向きにそろえる
                    if from.x > to.x || from.y > to.y {
                        runs.reverse();
                        for run in &mut runs {
                            *run = (run.1, run.0);
                        }
                    }
                    for (index, (a, b)) in runs.iter().enumerate() {
                        if !rounded || line.dotted {
                            flush(&mut current, &mut figures);
                            draw_straight(painter, *a, *b, color, width, rounded, line.dotted);
                            continue;
                        }
                        // 区間の始まりが前の角から続いていれば 1 本の線にする(角に切れ目を作らない)
                        let continues =
                            index == 0 && current.is_some() && distance(*a, from) < 0.01;
                        if !continues {
                            flush(&mut current, &mut figures);
                            current = Some(Figure {
                                start: *a,
                                segments: Vec::new(),
                            });
                        }
                        if let Some(figure) = current.as_mut() {
                            figure.segments.push(Segment::Line(*b));
                        }
                    }
                    // 終わりが丸で切れていれば，続く角と別の線にする
                    if !runs.last().is_some_and(|(_, b)| distance(*b, to) < 0.01) {
                        flush(&mut current, &mut figures);
                    }
                }
                Piece::Arc {
                    from,
                    to,
                    radius,
                    clockwise,
                } => {
                    let figure = current.get_or_insert_with(|| Figure {
                        start: from,
                        segments: Vec::new(),
                    });
                    figure.segments.push(Segment::Arc {
                        to,
                        radius,
                        clockwise,
                    });
                }
            }
        }
        flush(&mut current, &mut figures);
    }
    if !figures.is_empty() {
        painter.draws.push(Draw::Path {
            figures,
            color,
            width,
        });
    }
}

/// 縦か横の 1 本の線．角丸のテーマの点線は丸い点，platinum と desk は 1 ドットの四角で塗る(線をぼかさない)
fn draw_straight(
    painter: &mut Painter,
    from: Point,
    to: Point,
    color: Color,
    width: f32,
    rounded: bool,
    dotted: bool,
) {
    if rounded {
        painter.draws.push(Draw::Line {
            from,
            to,
            color,
            width,
            dot_pitch: dotted.then_some(glass::DOT_PITCH),
        });
        return;
    }
    let horizontal = (from.y - to.y).abs() < (from.x - to.x).abs();
    let min_x = from.x.min(to.x).round();
    let min_y = from.y.min(to.y).round();
    let length = if horizontal {
        (from.x - to.x).abs()
    } else {
        (from.y - to.y).abs()
    }
    .round();
    let rect = if horizontal {
        Frame::new(min_x, min_y - (width / 2.0).floor(), length, width)
    } else {
        Frame::new(min_x - (width / 2.0).floor(), min_y, width, length)
    };
    if !dotted {
        painter.rect(rect, color);
        return;
    }
    let mut x = rect.x;
    while x < rect.max_x() {
        painter.rect(Frame::new(x, rect.y, width, rect.height), color);
        x += width * 2.0;
    }
}

/// 丸を描く．選んでいる丸は選択の色で塗り，道すじの途中の丸は選択の色の輪，ほかは線の色の輪
pub fn draw_stops(painter: &mut Painter, stops: &[Stop], line_width: f32) {
    let theme = painter.theme;
    let rounded = theme.is_rounded();
    for stop in stops {
        let frame = stop.frame();
        match stop.state {
            State::Selected => {
                let color = theme.selection.faded(stop.opacity);
                if rounded {
                    painter.draws.push(Draw::Ellipse { frame, color });
                } else {
                    painter.rect(frame, color);
                }
            }
            State::Passed | State::Plain => {
                let color = if stop.state == State::Passed {
                    theme.selection
                } else {
                    theme.line
                }
                .faded(stop.opacity);
                let ring = frame.inset(line_width / 2.0, line_width / 2.0);
                painter.draws.push(Draw::RoundRect {
                    frame: ring,
                    radius: if rounded { ring.width / 2.0 } else { 0.0 },
                    fill: None,
                    stroke: Some((color, line_width)),
                });
            }
        }
    }
}

/// ページの位置を示す点．x の縦の線の下に，ページの数だけ縦に並べる．今のページの点は選択の色，ほかは線の色
pub fn page_dots(painter: &mut Painter, x: f32, top: f32, count: u32, current: u32) {
    let theme = painter.theme;
    let size = branch_map::PAGE_DOT_SIZE;
    for index in 0..count {
        let mid_y =
            top + branch_map::PAGE_DOT_PITCH * index as f32 + branch_map::PAGE_DOT_PITCH / 2.0;
        let frame = Frame::new(
            (x - size / 2.0).round(),
            (mid_y - size / 2.0).round(),
            size,
            size,
        );
        let color = if index == current {
            theme.selection
        } else {
            theme.line
        };
        if theme.is_rounded() {
            painter.draws.push(Draw::Ellipse { frame, color });
        } else {
            painter.rect(frame, color);
        }
    }
}

/// 続きがある印．from から to へ，端へ向けて透かした線を引く(畳んでいる枝)．縦か横の線
pub fn fading_line(painter: &mut Painter, from: Point, to: Point, color: Color, width: f32) {
    const STEPS: usize = 8;
    let rounded = painter.theme.is_rounded();
    for step in 0..STEPS {
        let start = step as f32 / STEPS as f32;
        let end = (step + 1) as f32 / STEPS as f32;
        let at = |t: f32| Point::new(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t);
        let alpha = 1.0 - (step as f32 + 0.5) / STEPS as f32;
        draw_straight(
            painter,
            at(start),
            at(end),
            color.faded(alpha),
            width,
            rounded,
            false,
        );
    }
}

/// 文節の境目のつまみ．縦の線と，左右の山形(境目を左右へ動かせる印)
pub fn grip(painter: &mut Painter, x: f32, mid_y: f32, height: f32) {
    let theme = painter.theme;
    let bar = glass::EDITING_CARET_WIDTH;
    painter.rect(
        Frame::new(
            (x - bar / 2.0).round(),
            (mid_y - height / 2.0).round(),
            bar,
            height.round(),
        ),
        theme.selection,
    );
    let size = branch_map::GRIP_SIZE;
    let figures = [-1.0_f32, 1.0]
        .iter()
        .map(|side| {
            let tip = x + side * (bar / 2.0 + space::FINE + size);
            Figure {
                start: Point::new(tip - side * size, mid_y - size),
                segments: vec![
                    Segment::Line(Point::new(tip, mid_y)),
                    Segment::Line(Point::new(tip - side * size, mid_y + size)),
                ],
            }
        })
        .collect();
    painter.draws.push(Draw::Path {
        figures,
        color: theme.selection,
        width: glass::LINE_WIDTH,
    });
}

/// draws(幹)を，left・right の側を端へ向けて透かして重ねる．幹が窓からはみ出していることを見せる．
/// 細い帯ごとに濃さを変えたまとまりにして描く
pub fn fading(draws: Vec<Draw>, left: bool, right: bool, bounds: Frame) -> Vec<Draw> {
    if !left && !right {
        return draws;
    }
    const STRIPES: usize = 12;
    let fade = branch_map::FADE_WIDTH.min(bounds.width / 2.0);
    let stripe = fade / STRIPES as f32;
    let mut result = Vec::new();
    let mut group = |clip: Frame, opacity: f32| {
        result.push(Draw::Group {
            clip,
            opacity,
            scale: 1.0,
            draws: draws.clone(),
        });
    };
    let middle_start = if left { bounds.x + fade } else { bounds.x };
    let middle_end = if right {
        bounds.max_x() - fade
    } else {
        bounds.max_x()
    };
    group(
        Frame::new(
            middle_start,
            bounds.y,
            middle_end - middle_start,
            bounds.height,
        ),
        1.0,
    );
    for index in 0..STRIPES {
        let opacity = (index as f32 + 0.5) / STRIPES as f32;
        if left {
            group(
                Frame::new(
                    bounds.x + stripe * index as f32,
                    bounds.y,
                    stripe,
                    bounds.height,
                ),
                opacity,
            );
        }
        if right {
            group(
                Frame::new(
                    bounds.max_x() - stripe * (index + 1) as f32,
                    bounds.y,
                    stripe,
                    bounds.height,
                ),
                opacity,
            );
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 丸の内側を線から切り抜く() {
        let stop = Stop::new(Point::new(10.0, 50.0), State::Plain);
        let runs = cut(Point::new(10.0, 0.0), Point::new(10.0, 100.0), &[stop]);
        assert_eq!(runs.len(), 2);
        assert!((runs[0].1.y - 46.0).abs() < 0.01);
        assert!((runs[1].0.y - 54.0).abs() < 0.01);
        // 線から外れた丸は切らない
        let away = Stop::new(Point::new(40.0, 50.0), State::Plain);
        assert_eq!(
            cut(Point::new(10.0, 0.0), Point::new(10.0, 100.0), &[away]).len(),
            1
        );
    }

    #[test]
    fn 角を丸めて_右へ曲がる角は時計回り() {
        let line = Line::rounded(
            vec![
                Point::new(0.0, 0.0),
                Point::new(0.0, 20.0),
                Point::new(30.0, 20.0),
            ],
            8.0,
        );
        let corner = pieces(&line);
        assert_eq!(corner.len(), 3);
        // 下へ進んで右へ曲がるのは，画面では左回り
        assert!(matches!(
            corner[1],
            Piece::Arc {
                clockwise: false,
                ..
            }
        ));
        // 角の半径は短い区間に収める
        let short = Line::rounded(
            vec![
                Point::new(0.0, 0.0),
                Point::new(0.0, 4.0),
                Point::new(30.0, 4.0),
            ],
            8.0,
        );
        assert!(matches!(pieces(&short)[1], Piece::Arc { radius, .. } if radius <= 4.0));
    }

    #[test]
    fn 線の真ん中をピクセルにそろえる() {
        assert_eq!(align(10.2, 1.0, 1.0), 10.5);
        assert_eq!(align(10.2, 2.0, 1.0), 10.0);
        assert_eq!(align(10.2, 1.0, 2.0), 10.0);
        assert_eq!(align(10.2, 1.5, 2.0), 10.25);
    }
}
