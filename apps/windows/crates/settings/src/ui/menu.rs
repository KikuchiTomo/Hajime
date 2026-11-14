#![forbid(unsafe_code)]

//! 開いた一覧(ドロップダウンとメニュー)の行の並び．選べる項目のほかに，組の見出しと区切りの線を並べる
//! (macOS のポップアップの Section)．見出しと線は選べないので，選ぶ番号は項目だけを数える
//! (見出しを足しても，番号と設定に書く値の対応は変わらない)．
//! 値は 96dpi の 1 ピクセルを 1 とし，一覧の中身の上端からの距離にする

use crate::options::ChoiceGroup;
use tokens::size::part;
use tokens::size::settings_windows as size;

/// 行の種類
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MenuRowKind {
    /// 選べる項目(項目だけを数えた番号)
    Item(usize),
    /// 組の見出し(選べない)
    Heading(&'static str),
    /// 組のあいだの区切りの線(選べない)
    Divider,
}

/// 一覧の 1 行
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MenuRow {
    pub kind: MenuRowKind,
    /// 行の上端と高さ
    pub top: f32,
    pub height: f32,
}

/// 矢印・Home・End での動き
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MenuMove {
    Up,
    Down,
    First,
    Last,
}

/// 一覧の行の並び
#[derive(Debug, Clone, Default, PartialEq)]
pub struct MenuLayout {
    rows: Vec<MenuRow>,
    /// 項目の数
    count: usize,
    /// 中身の高さ
    height: f32,
}

impl MenuLayout {
    /// count 個の項目を groups の組に分けて並べる．組のあいだに線を引き，題のある組は線の下に見出しを置く．
    /// groups が空なら項目だけを並べる．組に入らなかった残りの項目は，組に分けずに後ろに並べる
    pub fn new(count: usize, groups: &[ChoiceGroup]) -> Self {
        let mut layout = Self {
            rows: Vec::new(),
            count,
            height: 0.0,
        };
        let mut next = 0;
        for group in groups {
            let end = (next + group.count).min(count);
            if end == next {
                continue;
            }
            if next > 0 {
                layout.push(MenuRowKind::Divider);
            }
            if let Some(title) = group.title {
                layout.push(MenuRowKind::Heading(title));
            }
            for index in next..end {
                layout.push(MenuRowKind::Item(index));
            }
            next = end;
        }
        for index in next..count {
            layout.push(MenuRowKind::Item(index));
        }
        layout
    }

    fn push(&mut self, kind: MenuRowKind) {
        let height = match kind {
            MenuRowKind::Item(_) | MenuRowKind::Heading(_) => size::FLYOUT_ITEM_HEIGHT,
            // 線の上下に，一覧の端と同じ余白をとる
            MenuRowKind::Divider => size::FLYOUT_PADDING * 2.0 + part::STROKE,
        };
        self.rows.push(MenuRow {
            kind,
            top: self.height,
            height,
        });
        self.height += height;
    }

    pub fn rows(&self) -> &[MenuRow] {
        &self.rows
    }

    /// 中身の高さ
    pub fn height(&self) -> f32 {
        self.height
    }

    /// 項目の数(見出しと線は数えない)
    pub fn count(&self) -> usize {
        self.count
    }

    /// 見出しの文字(幅を測る)
    pub fn headings(&self) -> impl Iterator<Item = &'static str> + '_ {
        self.rows.iter().filter_map(|row| match row.kind {
            MenuRowKind::Heading(title) => Some(title),
            _ => None,
        })
    }

    /// y(中身の上端から)にある項目の番号．見出しと線の上は None(載せても押しても何もしない)
    pub fn item_at(&self, y: f32) -> Option<usize> {
        self.rows
            .iter()
            .find(|row| y >= row.top && y < row.top + row.height)
            .and_then(|row| match row.kind {
                MenuRowKind::Item(index) => Some(index),
                _ => None,
            })
    }

    /// 項目の上端と下端
    pub fn item_span(&self, index: usize) -> Option<(f32, f32)> {
        self.rows
            .iter()
            .find(|row| row.kind == MenuRowKind::Item(index))
            .map(|row| (row.top, row.top + row.height))
    }

    /// 項目を見せるために送る範囲．組の先頭の項目は，すぐ上の見出しと線も入れる
    /// (上に動いたとき，見出しが隠れたままにならない)
    pub fn reveal_span(&self, index: usize) -> Option<(f32, f32)> {
        let position = self
            .rows
            .iter()
            .position(|row| row.kind == MenuRowKind::Item(index))?;
        let first = self.rows[..position]
            .iter()
            .rposition(|row| matches!(row.kind, MenuRowKind::Item(_)))
            .map_or(0, |item| item + 1);
        let row = &self.rows[position];
        Some((self.rows[first].top, row.top + row.height))
    }

    /// current から動いた先の項目の番号．項目だけを数えるので，見出しと線は飛ばす．端では止まる
    pub fn moved(&self, current: Option<usize>, movement: MenuMove) -> Option<usize> {
        let last = self.count.checked_sub(1)?;
        Some(match (movement, current) {
            (MenuMove::First, _) | (MenuMove::Down, None) => 0,
            (MenuMove::Last, _) | (MenuMove::Up, None) => last,
            (MenuMove::Up, Some(index)) => index.saturating_sub(1).min(last),
            (MenuMove::Down, Some(index)) => (index + 1).min(last),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::options::{WORD_CLASSES, WORD_CLASS_GROUPS};

    fn word_classes() -> MenuLayout {
        MenuLayout::new(WORD_CLASSES.len(), WORD_CLASS_GROUPS)
    }

    #[test]
    fn 組が無ければ項目だけを同じ高さで並べる() {
        let layout = MenuLayout::new(3, &[]);
        assert_eq!(
            layout.rows().iter().map(|row| row.kind).collect::<Vec<_>>(),
            [
                MenuRowKind::Item(0),
                MenuRowKind::Item(1),
                MenuRowKind::Item(2)
            ]
        );
        assert_eq!(layout.height(), size::FLYOUT_ITEM_HEIGHT * 3.0);
        assert_eq!(layout.item_at(size::FLYOUT_ITEM_HEIGHT * 1.5), Some(1));
        assert_eq!(layout.item_at(layout.height()), None);
        assert_eq!(layout.item_at(-1.0), None);
    }

    #[test]
    fn 品詞は組のあいだに線を引き_題のある組に見出しを置く() {
        use MenuRowKind::{Divider, Heading, Item};
        let layout = word_classes();
        let kinds: Vec<MenuRowKind> = layout.rows().iter().map(|row| row.kind).collect();
        assert_eq!(
            kinds,
            [
                Item(0),
                Divider,
                Heading("人名"),
                Item(1),
                Item(2),
                Item(3),
                Divider,
                Item(4),
                Item(5),
                Item(6),
                Divider,
                Heading("その他"),
                Item(7),
                Item(8),
                Item(9),
                Item(10),
                Item(11),
                Item(12),
            ]
        );
        // 行は上から重ねずに並ぶ
        for pair in layout.rows().windows(2) {
            assert_eq!(pair[1].top, pair[0].top + pair[0].height);
        }
    }

    #[test]
    fn 項目の番号は選択肢の並びのままで_設定に書く値は変わらない() {
        let layout = word_classes();
        let items: Vec<usize> = layout
            .rows()
            .iter()
            .filter_map(|row| match row.kind {
                MenuRowKind::Item(index) => Some(index),
                _ => None,
            })
            .collect();
        assert_eq!(items, (0..WORD_CLASSES.len()).collect::<Vec<_>>());
        assert_eq!(layout.count(), WORD_CLASSES.len());
        // 「人名」の見出しのすぐ下の項目は姓のみ
        let (top, _) = layout.item_span(1).unwrap();
        assert_eq!(WORD_CLASSES[layout.item_at(top).unwrap()].0, "surname");
    }

    #[test]
    fn 見出しと線の上は項目にならない() {
        let layout = word_classes();
        for row in layout.rows() {
            let middle = row.top + row.height / 2.0;
            match row.kind {
                MenuRowKind::Item(index) => assert_eq!(layout.item_at(middle), Some(index)),
                _ => assert_eq!(layout.item_at(middle), None),
            }
        }
    }

    #[test]
    fn 矢印は見出しと線を飛ばして隣の項目に動き_端で止まる() {
        let layout = word_classes();
        // 名詞の下は(線と見出しを飛ばして)姓のみ，その上は名詞
        assert_eq!(layout.moved(Some(0), MenuMove::Down), Some(1));
        assert_eq!(layout.moved(Some(1), MenuMove::Up), Some(0));
        assert_eq!(layout.moved(Some(6), MenuMove::Down), Some(7));
        assert_eq!(layout.moved(Some(0), MenuMove::Up), Some(0));
        assert_eq!(layout.moved(Some(12), MenuMove::Down), Some(12));
        assert_eq!(layout.moved(None, MenuMove::Down), Some(0));
        assert_eq!(layout.moved(None, MenuMove::Up), Some(12));
        assert_eq!(layout.moved(Some(5), MenuMove::First), Some(0));
        assert_eq!(layout.moved(Some(5), MenuMove::Last), Some(12));
        assert_eq!(MenuLayout::new(0, &[]).moved(None, MenuMove::Down), None);
    }

    #[test]
    fn 組の先頭の項目を見せるときは見出しと線も見せる() {
        let layout = word_classes();
        let divider = layout.rows()[1];
        let (_, bottom) = layout.item_span(1).unwrap();
        assert_eq!(layout.reveal_span(1), Some((divider.top, bottom)));
        assert_eq!(layout.reveal_span(2), layout.item_span(2));
        assert_eq!(layout.reveal_span(0), layout.item_span(0));
    }

    #[test]
    fn 組に入らない項目は後ろに並べ_空の組は出さない() {
        let groups = [
            ChoiceGroup {
                title: Some("見出し"),
                count: 0,
            },
            ChoiceGroup {
                title: None,
                count: 1,
            },
        ];
        let layout = MenuLayout::new(3, &groups);
        assert_eq!(
            layout.rows().iter().map(|row| row.kind).collect::<Vec<_>>(),
            [
                MenuRowKind::Item(0),
                MenuRowKind::Item(1),
                MenuRowKind::Item(2)
            ]
        );
    }
}
