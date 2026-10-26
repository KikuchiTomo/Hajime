#![forbid(unsafe_code)]

//! キーのアイコンの形．macOS の SF Symbols(arrow.up・shift・arrow.right.to.line・escape など)に当たる線画を，
//! 正方形の枠の中の折れ線で決める．描く層は折れ線を同じ太さの線でなぞるだけにし，形をここで確かめられるようにする

use crate::geometry::{Frame, Point};
use crate::keys::Icon;
use std::f32::consts::PI;

/// 1 本の折れ線．closed なら最後の点から最初の点へ閉じる
#[derive(Debug, Clone, PartialEq)]
pub struct Figure {
    pub points: Vec<Point>,
    pub closed: bool,
}

/// 枠の 0〜1 の座標で書いた折れ線
type Unit = &'static [(f32, f32)];

const ARROW_UP: &[Unit] = &[
    &[(0.5, 0.88), (0.5, 0.14)],
    &[(0.2, 0.44), (0.5, 0.14), (0.8, 0.44)],
];
const LEFT_RIGHT: &[Unit] = &[
    &[(0.08, 0.5), (0.92, 0.5)],
    &[(0.3, 0.28), (0.08, 0.5), (0.3, 0.72)],
    &[(0.7, 0.28), (0.92, 0.5), (0.7, 0.72)],
];
/// ⇧ の形(中の空いた上向きの矢印)．閉じた折れ線
const SHIFT: Unit = &[
    (0.5, 0.1),
    (0.92, 0.52),
    (0.69, 0.52),
    (0.69, 0.9),
    (0.31, 0.9),
    (0.31, 0.52),
    (0.08, 0.52),
];
/// →| の形
const TAB: &[Unit] = &[
    &[(0.08, 0.5), (0.72, 0.5)],
    &[(0.46, 0.24), (0.72, 0.5), (0.46, 0.76)],
    &[(0.92, 0.2), (0.92, 0.8)],
];
/// ⎵ の形
const SPACE: &[Unit] = &[&[(0.06, 0.52), (0.06, 0.8), (0.94, 0.8), (0.94, 0.52)]];
/// ↵ の形
const ENTER: &[Unit] = &[
    &[(0.86, 0.16), (0.86, 0.62), (0.14, 0.62)],
    &[(0.36, 0.4), (0.14, 0.62), (0.36, 0.84)],
];
/// ⌫ の形(左を尖らせた札と ×)
const BACKSPACE_FRAME: Unit = &[
    (0.34, 0.2),
    (0.94, 0.2),
    (0.94, 0.8),
    (0.34, 0.8),
    (0.06, 0.5),
];
const BACKSPACE_CROSS: &[Unit] = &[&[(0.5, 0.36), (0.78, 0.64)], &[(0.78, 0.36), (0.5, 0.64)]];
/// ⎋ の矢印(左上へ抜ける)
const ESCAPE_ARROW: &[Unit] = &[
    &[(0.5, 0.5), (0.12, 0.12)],
    &[(0.12, 0.4), (0.12, 0.12), (0.4, 0.12)],
];
/// ⎋ の円の半径と，左上で円を切る角度(度．右が 0 で時計回り)
const ESCAPE_RADIUS: f32 = 0.38;
const ESCAPE_GAP_FROM: f32 = 195.0;
const ESCAPE_GAP_TO: f32 = 255.0;
/// 円を折れ線にするときの 1 周の分け方
const CIRCLE_STEPS: usize = 36;

pub fn figures(icon: Icon, frame: Frame) -> Vec<Figure> {
    let place =
        |(x, y): (f32, f32)| Point::new(frame.x + x * frame.width, frame.y + y * frame.height);
    let open = |lines: &[Unit], turn: fn((f32, f32)) -> (f32, f32)| {
        lines
            .iter()
            .map(|line| Figure {
                points: line.iter().map(|point| place(turn(*point))).collect(),
                closed: false,
            })
            .collect::<Vec<_>>()
    };
    match icon {
        Icon::Up => open(ARROW_UP, |p| p),
        Icon::Down => open(ARROW_UP, |(x, y)| (x, 1.0 - y)),
        Icon::Left => open(ARROW_UP, |(x, y)| (y, x)),
        Icon::Right => open(ARROW_UP, |(x, y)| (1.0 - y, x)),
        Icon::LeftRight => open(LEFT_RIGHT, |p| p),
        Icon::Shift => vec![Figure {
            points: SHIFT.iter().map(|point| place(*point)).collect(),
            closed: true,
        }],
        Icon::Tab => open(TAB, |p| p),
        Icon::Space => open(SPACE, |p| p),
        Icon::Enter => open(ENTER, |p| p),
        Icon::Backspace => {
            let mut figures = vec![Figure {
                points: BACKSPACE_FRAME.iter().map(|point| place(*point)).collect(),
                closed: true,
            }];
            figures.extend(open(BACKSPACE_CROSS, |p| p));
            figures
        }
        Icon::Escape => {
            let span = 360.0 - (ESCAPE_GAP_TO - ESCAPE_GAP_FROM);
            let arc = (0..=CIRCLE_STEPS)
                .map(|step| {
                    let degrees = ESCAPE_GAP_TO + span * step as f32 / CIRCLE_STEPS as f32;
                    let radians = degrees * PI / 180.0;
                    place((
                        0.5 + ESCAPE_RADIUS * radians.cos(),
                        0.5 + ESCAPE_RADIUS * radians.sin(),
                    ))
                })
                .collect();
            let mut figures = vec![Figure {
                points: arc,
                closed: false,
            }];
            figures.extend(open(ESCAPE_ARROW, |p| p));
            figures
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const ALL: [Icon; 11] = [
        Icon::Up,
        Icon::Down,
        Icon::Left,
        Icon::Right,
        Icon::LeftRight,
        Icon::Shift,
        Icon::Tab,
        Icon::Space,
        Icon::Enter,
        Icon::Escape,
        Icon::Backspace,
    ];

    #[test]
    fn アイコンは枠からはみ出さない() {
        let frame = Frame::new(10.0, 20.0, 11.0, 11.0);
        for icon in ALL {
            let figures = figures(icon, frame);
            assert!(!figures.is_empty());
            for point in figures.iter().flat_map(|figure| &figure.points) {
                assert!(point.x >= frame.x && point.x <= frame.max_x(), "{icon:?}");
                assert!(point.y >= frame.y && point.y <= frame.max_y(), "{icon:?}");
            }
        }
    }

    #[test]
    fn 矢印は向きのとおりに尖る() {
        let frame = Frame::new(0.0, 0.0, 10.0, 10.0);
        let tip = |icon| figures(icon, frame)[1].points[1];
        assert!(tip(Icon::Up).y < 5.0);
        assert!(tip(Icon::Down).y > 5.0);
        assert!(tip(Icon::Left).x < 5.0);
        assert!(tip(Icon::Right).x > 5.0);
    }
}
