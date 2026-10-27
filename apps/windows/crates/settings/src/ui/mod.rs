#![forbid(unsafe_code)]

//! 設定の画面の OS に依存しない部分(動き・スクロール・表の選び方・左の一覧の並び)．
//! 描き方と OS の呼び出しは app が受け持つ．ここは macOS でもテストできる

pub mod anim;
pub mod nav;
pub mod scroll;
pub mod table;

/// 0..count の中で current から次(back なら前)の位置．端を越えたら反対の端に回る
pub fn cycle(current: Option<usize>, count: usize, back: bool) -> Option<usize> {
    if count == 0 {
        return None;
    }
    Some(match (current, back) {
        (None, false) => 0,
        (None, true) => count - 1,
        (Some(index), false) => (index + 1) % count,
        (Some(index), true) => (index + count - 1) % count,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 端を越えたら反対の端に回る() {
        assert_eq!(cycle(None, 3, false), Some(0));
        assert_eq!(cycle(None, 3, true), Some(2));
        assert_eq!(cycle(Some(2), 3, false), Some(0));
        assert_eq!(cycle(Some(0), 3, true), Some(2));
        assert_eq!(cycle(Some(0), 0, false), None);
    }
}
