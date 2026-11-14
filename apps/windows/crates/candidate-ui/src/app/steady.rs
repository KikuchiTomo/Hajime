//! 分岐図で同じ文節を選んでいるあいだ，候補を移っても窓の位置と幅を動かさないための覚え書き．
//!
//! 候補を移ると，組み立て中の文字が替わる(「カレンダー」と絵文字など)．絵文字にすると入力先の行の矩形が数ピクセル高くなり，
//! 窓がその下端に付いて上下していた．先の枝の丸の数と幹の文字の幅でも，窓の幅が候補ごとに変わっていた．
//! 選んでいる文節・文節の数・出しているまとまりが変わったら，決め直す．

use ipc::{BranchMap, Rect};

/// 選んでいる文節を見分けるもの(選んでいる文節の位置，文節の数，出しているまとまりの先頭)
type Key = (Option<usize>, usize, Option<u32>);

#[derive(Default)]
pub struct Steady {
    key: Option<Key>,
    /// 窓の位置を決めた基準
    anchor: Option<Rect>,
    /// 同じ文節にいるあいだに出した窓の幅のうち，いちばん広いもの
    width: f32,
}

impl Steady {
    fn key(map: &BranchMap) -> Key {
        (
            map.columns.iter().position(|column| column.is_focused),
            map.columns.len(),
            map.group_start,
        )
    }

    /// 分岐図を出すときに呼ぶ．選んでいる文節が前と違えば，位置と幅を決め直す
    pub fn show(&mut self, map: &BranchMap) {
        let key = Self::key(map);
        if self.key != Some(key) {
            *self = Self {
                key: Some(key),
                ..Self::default()
            };
        }
    }

    /// 分岐図を出していないときに呼ぶ
    pub fn reset(&mut self) {
        *self = Self::default();
    }

    /// 届いた基準から，窓の位置を決める基準を返す．同じ文節にいるあいだは，入力位置が実際に動いたとき
    /// (x が変わった，または y の差が 1 行の高さ以上)だけ取り替える．行の矩形が数ピクセル高くなる変化は無視する
    pub fn anchor(&mut self, new: Rect) -> Rect {
        if self.key.is_none() {
            return new;
        }
        match &self.anchor {
            Some(old) if !moved(old, &new) => old.clone(),
            _ => {
                self.anchor = Some(new.clone());
                new
            }
        }
    }

    /// 窓の幅の下限(同じ文節にいるあいだは，広がるだけで狭めない)
    pub fn min_width(&self) -> f32 {
        self.width
    }

    /// 出した窓の幅を覚える
    pub fn shown(&mut self, width: f32) {
        if self.key.is_some() {
            self.width = self.width.max(width);
        }
    }
}

/// 入力位置が実際に動いたか
fn moved(old: &Rect, new: &Rect) -> bool {
    let line = old.height.max(1);
    old.x != new.x || (old.y - new.y).abs() >= line
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::scene::sample;

    fn rect(x: i32, y: i32, height: i32) -> Rect {
        Rect {
            x,
            y,
            width: 1,
            height,
        }
    }

    #[test]
    fn keeps_anchor_while_the_same_segment_is_focused() {
        let map = sample::branch();
        let mut steady = Steady::default();
        steady.show(&map);
        assert_eq!(steady.anchor(rect(100, 200, 20)), rect(100, 200, 20));
        // 絵文字で行の矩形が高くなっただけなら，取り替えない
        steady.show(&map);
        assert_eq!(steady.anchor(rect(100, 197, 25)), rect(100, 200, 20));
        // 入力位置が動いた(x が変わった・1 行以上ずれた)ら取り替える
        assert_eq!(steady.anchor(rect(140, 200, 20)), rect(140, 200, 20));
        assert_eq!(steady.anchor(rect(140, 220, 20)), rect(140, 220, 20));
    }

    #[test]
    fn widens_but_never_narrows_until_the_segment_changes() {
        let mut map = sample::branch();
        let mut steady = Steady::default();
        steady.show(&map);
        steady.shown(300.0);
        steady.shown(260.0);
        assert_eq!(steady.min_width(), 300.0);
        // 文節を移ったら決め直す
        let focused = map
            .columns
            .iter()
            .position(|column| column.is_focused)
            .unwrap();
        let next = (focused + 1) % map.columns.len();
        map.columns[focused].is_focused = false;
        map.columns[next].is_focused = true;
        steady.show(&map);
        assert_eq!(steady.min_width(), 0.0);
        assert_eq!(steady.anchor(rect(100, 197, 25)), rect(100, 197, 25));
    }

    #[test]
    fn does_nothing_when_no_branch_map_is_shown() {
        let mut steady = Steady::default();
        assert_eq!(steady.anchor(rect(1, 2, 3)), rect(1, 2, 3));
        assert_eq!(steady.anchor(rect(1, 4, 3)), rect(1, 4, 3));
        steady.shown(300.0);
        assert_eq!(steady.min_width(), 0.0);
    }
}
