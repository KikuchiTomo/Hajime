#![forbid(unsafe_code)]

//! 左の一覧(見出しごとのページ)の並びと位置．値は 96dpi の 1 ピクセルを 1 とし，一覧の上端からの距離にする．
//! 見出しは選べる項目と見分けやすいよう，小さい薄い文字にして上に間を取る(macOS の SettingsView のサイドバーと同じ)

use crate::pages::{self, Group, Page};
use tokens::size::settings_windows as size;

/// 一覧の 1 項目
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NavItem {
    pub page: Page,
    /// 項目の上端と高さ
    pub top: f32,
    pub height: f32,
}

/// 見出し
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct NavHeader {
    pub group: Group,
    pub top: f32,
    pub height: f32,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct NavLayout {
    pub headers: Vec<NavHeader>,
    pub items: Vec<NavItem>,
    /// 一覧の中身の高さ
    pub height: f32,
}

impl NavLayout {
    /// 検索の言葉に合うページを見出しごとに並べる
    pub fn new(query: &str) -> Self {
        let mut layout = Self::default();
        let mut y = 0.0;
        for (index, (group, pages)) in pages::sidebar(pages::BUILT, query).into_iter().enumerate() {
            if index > 0 {
                y += size::NAV_GROUP_GAP;
            }
            layout.headers.push(NavHeader {
                group,
                top: y,
                height: size::NAV_HEADER_HEIGHT,
            });
            y += size::NAV_HEADER_HEIGHT;
            for page in pages {
                layout.items.push(NavItem {
                    page,
                    top: y,
                    height: size::NAV_ITEM_HEIGHT,
                });
                y += size::NAV_ITEM_HEIGHT;
            }
        }
        layout.height = y;
        layout
    }

    /// y(一覧の上端からの距離)にある項目の番号
    pub fn hit(&self, y: f32) -> Option<usize> {
        self.items
            .iter()
            .position(|item| y >= item.top && y < item.top + item.height)
    }

    pub fn position(&self, page: Page) -> Option<usize> {
        self.items.iter().position(|item| item.page == page)
    }

    /// index から step だけ動かした項目(端で止まる)
    pub fn step(&self, index: Option<usize>, step: isize) -> Option<usize> {
        if self.items.is_empty() {
            return None;
        }
        let last = self.items.len() as isize - 1;
        let next = match index {
            None if step < 0 => last,
            None => 0,
            Some(index) => (index as isize + step).clamp(0, last),
        };
        usize::try_from(next).ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 見出しの下に項目を並べ二つ目からの見出しの上に間を取る() {
        let layout = NavLayout::new("");
        assert_eq!(layout.headers.len(), 5);
        assert_eq!(layout.headers[0].top, 0.0);
        let first = layout.items[0];
        assert_eq!(first.top, size::NAV_HEADER_HEIGHT);
        let second = layout.headers[1];
        let before = layout
            .items
            .iter()
            .filter(|item| item.top < second.top)
            .next_back()
            .unwrap();
        assert_eq!(second.top, before.top + before.height + size::NAV_GROUP_GAP);
        let last = layout.items.last().unwrap();
        assert_eq!(layout.height, last.top + last.height);
    }

    #[test]
    fn 位置から項目を引き端で止まる() {
        let layout = NavLayout::new("");
        let item = layout.items[2];
        assert_eq!(layout.hit(item.top + 1.0), Some(2));
        assert_eq!(layout.hit(0.0), None);
        assert_eq!(layout.step(Some(0), -1), Some(0));
        assert_eq!(layout.step(None, -1), Some(layout.items.len() - 1));
        assert_eq!(layout.step(Some(1), 1), Some(2));
        assert_eq!(layout.position(item.page), Some(2));
    }

    #[test]
    fn 検索で絞ると合う項目だけになる() {
        let layout = NavLayout::new("ローマ字");
        assert!(layout.items.iter().any(|item| item.page == Page::Romaji));
        assert!(layout.items.len() < NavLayout::new("").items.len());
    }
}
