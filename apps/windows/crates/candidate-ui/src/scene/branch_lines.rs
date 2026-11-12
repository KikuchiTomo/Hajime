//! 分岐図の枝の線の配置(ADR 0007．macOS は core の BranchLines と同じ決め方)．
//!
//! 幹の文節の札の端から 1 本の縦の線(幹)を伸ばし，候補ごとに同じ半径の 4 分の 1 の円で曲がって，
//! 水平の線で候補の行の手前まで伸ばす．直線の枝は半径を 0 にした同じ形(直角に曲がる)にする．
//! - 曲がり角の形と水平の線の終わりの x は，どの候補でも同じ
//! - 幹はいちばん遠い候補の曲がり角の始まりで終わる(先を飛び出させない)
//! - 曲がり角と水平の線は，隣の候補のものと重ならない．幹は 1 本だけで，候補ごとに描くのは曲がり角と水平の線だけ
//!
//! 線の縁をデバイスのピクセルの境にそろえる．太さが奇数のピクセルの線は，中心を半ピクセルずらす．y は下へ増える

use super::Point;

/// 1 つの候補への曲がり角と水平の線
#[derive(Debug, Clone, Copy, PartialEq)]
pub(crate) struct Turn {
    /// 幹から離れ始める点(幹の上)
    pub start: Point,
    /// 4 分の 1 の円の中心．直角なら end と同じ
    pub center: Point,
    /// 曲がり終えた点．ここから水平の線が始まる
    pub end: Point,
    /// 水平の線の終わり(候補の行の手前)
    pub tip: Point,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct BranchLines {
    /// 幹の根元(文節の札の端)
    pub root: Point,
    /// 幹の先(いちばん遠い候補の曲がり角の始まり)．候補が無ければ根元と同じ
    pub stem_end: Point,
    /// 曲がり角の半径．すべての候補で同じ
    pub radius: f32,
    /// 幹に近い順
    pub turns: Vec<Turn>,
}

impl BranchLines {
    /// - stem_x: 幹の x
    /// - root_y: 幹の根元の y．下へ伸ばすなら文節の札の下の端，上へ伸ばすなら上の端
    /// - row_mid_ys: 候補の行の縦の中心．幹に近い順に並べる．根元より大きければ下へ，小さければ上へ伸ばす
    /// - tip_x: 水平の線の終わりの x
    /// - radius: 曲がり角の半径．0 なら直角．根元から最初の行まで，または行と行のあいだ(線の太さの分を除く)に入らなければ縮める
    /// - line_width: 線の太さ
    /// - scale: 1 ドット(96 DPI の 1 ピクセル)あたりのデバイスのピクセル数
    pub fn new(
        stem_x: f32,
        root_y: f32,
        row_mid_ys: &[f32],
        tip_x: f32,
        radius: f32,
        line_width: f32,
        scale: f32,
    ) -> Self {
        let x = align_center(stem_x, line_width, scale);
        let root_y = align_edge(root_y, scale);
        let tip_x = align_edge(tip_x, scale);
        let mids: Vec<f32> = row_mid_ys
            .iter()
            .map(|&mid| align_center(mid, line_width, scale))
            .collect();
        let direction = if mids.first().is_some_and(|&first| first < root_y) {
            -1.0
        } else {
            1.0
        };
        // 半径は，根元から最初の行まで・行と行のあいだ(線の太さの分の隙間を残す)・水平の線の長さのどれにも収める
        let mut limit = radius.min(tip_x - x).max(0.0);
        if let Some(&first) = mids.first() {
            limit = limit.min((first - root_y).abs());
        }
        for pair in mids.windows(2) {
            limit = limit.min(((pair[1] - pair[0]).abs() - line_width).max(0.0));
        }
        let radius = (limit * scale).floor() / scale;
        let root = Point::new(x, root_y);
        let turns: Vec<Turn> = mids
            .iter()
            .map(|&mid| {
                let start_y = mid - direction * radius;
                Turn {
                    start: Point::new(x, start_y),
                    center: Point::new(x + radius, start_y),
                    end: Point::new(x + radius, mid),
                    tip: Point::new(tip_x, mid),
                }
            })
            .collect();
        let stem_end = turns.last().map_or(root, |turn| turn.start);
        Self {
            root,
            stem_end,
            radius,
            turns,
        }
    }

    /// 幹のうち，index 番目の候補の曲がり角より先の部分．index が None なら幹の全体．無ければ None．
    /// 選んでいる候補への道(根元からその曲がり角まで)を別の色で描くとき，残りの幹をこれで描く
    pub fn stem_after(&self, index: Option<usize>) -> Option<(Point, Point)> {
        let from = index.map_or(self.root, |index| self.turns[index].start);
        (from != self.stem_end).then_some((from, self.stem_end))
    }
}

/// 線の縁がデバイスのピクセルの境に来る，線の中心の座標
pub(crate) fn align_center(value: f32, line_width: f32, scale: f32) -> f32 {
    let pixels = line_width * scale;
    ((value * scale - pixels / 2.0).round() + pixels / 2.0) / scale
}

/// デバイスのピクセルの境の座標
pub(crate) fn align_edge(value: f32, scale: f32) -> f32 {
    (value * scale).round() / scale
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 下の枝: 文節の札の下の端(y = 40)から，28 ずつ離れた 5 つの行へ
    fn downward(radius: f32, line_width: f32, scale: f32) -> BranchLines {
        let mids: Vec<f32> = (0..5).map(|index| 56.0 + index as f32 * 28.0).collect();
        BranchLines::new(22.0, 40.0, &mids, 47.0, radius, line_width, scale)
    }

    /// 上の枝: 文節の札の上の端(y = 100)から，上へ 3 つの行へ
    fn upward() -> BranchLines {
        BranchLines::new(22.0, 100.0, &[84.0, 56.0, 28.0], 47.0, 8.0, 1.5, 2.0)
    }

    #[test]
    fn turns_are_quarter_circles_of_one_radius() {
        for lines in [downward(8.0, 1.5, 2.0), upward()] {
            assert_eq!(lines.radius, 8.0);
            for turn in &lines.turns {
                // 始まりは幹の上，中心は始まりから水平に半径の分，終わりは中心から縦に半径の分
                assert_eq!(turn.start.x, lines.root.x);
                assert_eq!(turn.center.x - turn.start.x, lines.radius);
                assert_eq!(turn.center.y, turn.start.y);
                assert_eq!(turn.end.x, turn.center.x);
                assert_eq!((turn.end.y - turn.center.y).abs(), lines.radius);
            }
        }
    }

    #[test]
    fn tips_end_at_one_x() {
        for lines in [downward(8.0, 1.5, 2.0), upward()] {
            let tip = lines.turns[0].tip.x;
            assert!(lines.turns.iter().all(|turn| turn.tip.x == tip));
            assert!(lines
                .turns
                .iter()
                .all(|turn| turn.tip.y == turn.end.y && turn.tip.x > turn.end.x));
        }
    }

    #[test]
    fn stem_ends_at_farthest_turn() {
        for lines in [downward(8.0, 1.5, 2.0), upward()] {
            assert_eq!(
                Some(lines.stem_end),
                lines.turns.last().map(|turn| turn.start)
            );
        }
        let down = downward(8.0, 1.5, 2.0);
        assert!(down.stem_end.y > down.root.y);
        let up = upward();
        assert!(up.stem_end.y < up.root.y);
    }

    #[test]
    fn turns_do_not_overlap() {
        for (lines, direction) in [(downward(8.0, 1.5, 2.0), 1.0), (upward(), -1.0)] {
            assert!((lines.turns[0].start.y - lines.root.y) * direction >= 0.0);
            for pair in lines.turns.windows(2) {
                // 次の曲がり角の始まりは，前の水平の線から線の太さ以上離れる
                assert!((pair[1].start.y - pair[0].end.y) * direction >= 1.5);
            }
        }
    }

    #[test]
    fn shrinks_radius_for_tight_rows() {
        let tight = BranchLines::new(22.0, 40.0, &[46.0, 56.0, 66.0], 47.0, 8.0, 1.5, 2.0);
        assert_eq!(tight.radius, 6.0);
        for pair in tight.turns.windows(2) {
            assert!(pair[1].start.y - pair[0].end.y >= 1.5);
        }
    }

    #[test]
    fn zero_radius_is_square() {
        let lines = downward(0.0, 1.5, 2.0);
        assert_eq!(lines.radius, 0.0);
        for turn in &lines.turns {
            assert_eq!(turn.start, turn.end);
            assert_eq!(turn.center, turn.end);
            assert_eq!(turn.start.x, lines.root.x);
        }
        assert_eq!(
            Some(lines.stem_end.y),
            lines.turns.last().map(|turn| turn.end.y)
        );
    }

    #[test]
    fn edges_land_on_device_pixels() {
        let on_edge = |value: f32| value == value.round();
        for (line_width, scale) in [(1.5, 2.0), (2.0, 2.0), (1.0, 1.0), (1.0, 2.0), (2.0, 1.0)] {
            let lines = downward(8.0, line_width, scale);
            let half = line_width * scale / 2.0;
            assert!(on_edge(lines.root.x * scale - half));
            assert!(on_edge(lines.root.y * scale));
            for turn in &lines.turns {
                assert!(on_edge(turn.end.y * scale - half));
                assert!(on_edge(turn.tip.x * scale));
            }
            assert!(on_edge(lines.radius * scale));
        }
        // 1 ピクセルの線は中心を半ピクセルずらす
        assert_eq!(align_center(12.0, 1.0, 1.0), 12.5);
        assert_eq!(align_center(12.0, 2.0, 1.0), 12.0);
    }

    #[test]
    fn stem_after_selection() {
        let lines = downward(8.0, 1.5, 2.0);
        assert_eq!(lines.stem_after(None).map(|stem| stem.0), Some(lines.root));
        assert_eq!(
            lines.stem_after(Some(1)),
            Some((lines.turns[1].start, lines.stem_end))
        );
        assert_eq!(lines.stem_after(Some(lines.turns.len() - 1)), None);
        let empty = BranchLines::new(22.0, 40.0, &[], 47.0, 8.0, 1.5, 2.0);
        assert!(empty.turns.is_empty());
        assert_eq!(empty.stem_after(None), None);
    }
}
