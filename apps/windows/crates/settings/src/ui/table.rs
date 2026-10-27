#![forbid(unsafe_code)]

//! 表(一覧の行)の状態．検索の言葉で絞って出す行と，選んでいる行を持つ．
//! 行の番号は 2 種類ある: rows の番号(全体)と，出している行の中の位置(shown の番号)

use std::collections::BTreeSet;

/// 表の上での選び方の操作(キーボード)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Move {
    Up,
    Down,
    PageUp(usize),
    PageDown(usize),
    Home,
    End,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct Table {
    rows: Vec<Vec<String>>,
    /// 出している行(rows の番号)
    shown: Vec<usize>,
    /// 選んでいる行(shown の中の位置)
    selected: BTreeSet<usize>,
    /// Shift で範囲を選ぶときの起点(shown の中の位置)
    anchor: Option<usize>,
    /// キーボードで動かす行(shown の中の位置)
    cursor: Option<usize>,
    query: String,
}

impl Table {
    /// 行を入れ替える．選んでいた行は外す(並びが変わるため)
    pub fn set_rows(&mut self, rows: Vec<Vec<String>>) {
        self.rows = rows;
        self.clear_selection();
        self.refilter();
    }

    pub fn rows(&self) -> &[Vec<String>] {
        &self.rows
    }

    /// 検索の言葉を含む行だけを出す(大文字と小文字を区別しない)．選んでいた行は外す
    pub fn filter(&mut self, query: &str) {
        let query = query.to_lowercase();
        if query == self.query {
            return;
        }
        self.query = query;
        self.clear_selection();
        self.refilter();
    }

    fn refilter(&mut self) {
        let query = &self.query;
        self.shown = (0..self.rows.len())
            .filter(|index| {
                query.is_empty()
                    || self.rows[*index]
                        .iter()
                        .any(|cell| cell.to_lowercase().contains(query.as_str()))
            })
            .collect();
    }

    /// 出している行の数
    pub fn len(&self) -> usize {
        self.shown.len()
    }

    pub fn is_empty(&self) -> bool {
        self.shown.is_empty()
    }

    /// 出している行の position 番目の中身
    pub fn shown_row(&self, position: usize) -> Option<&[String]> {
        self.shown
            .get(position)
            .and_then(|index| self.rows.get(*index))
            .map(Vec::as_slice)
    }

    pub fn is_selected(&self, position: usize) -> bool {
        self.selected.contains(&position)
    }

    pub fn cursor(&self) -> Option<usize> {
        self.cursor
    }

    /// 選んでいる行(出している行の中の位置)
    pub fn selected_positions(&self) -> Vec<usize> {
        self.selected.iter().copied().collect()
    }

    /// 選んでいる行(rows の番号)
    pub fn selected_rows(&self) -> Vec<usize> {
        self.selected
            .iter()
            .filter_map(|position| self.shown.get(*position).copied())
            .collect()
    }

    pub fn clear_selection(&mut self) {
        self.selected.clear();
        self.anchor = None;
        self.cursor = None;
    }

    /// 行を押した．Ctrl で足し引き，Shift で起点からの範囲を選ぶ．選びが変わったら true
    pub fn click(&mut self, position: usize, control: bool, shift: bool) -> bool {
        if position >= self.shown.len() {
            return false;
        }
        let before = self.selected.clone();
        match (control, shift, self.anchor) {
            (_, true, Some(anchor)) => {
                if !control {
                    self.selected.clear();
                }
                let (low, high) = (anchor.min(position), anchor.max(position));
                self.selected.extend(low..=high);
            }
            (true, _, _) => {
                if !self.selected.remove(&position) {
                    self.selected.insert(position);
                }
                self.anchor = Some(position);
            }
            _ => {
                self.selected.clear();
                self.selected.insert(position);
                self.anchor = Some(position);
            }
        }
        self.cursor = Some(position);
        before != self.selected
    }

    /// キーボードで選ぶ行を動かす．Shift で範囲を選ぶ．選びが変わったら true
    pub fn move_cursor(&mut self, movement: Move, shift: bool) -> bool {
        if self.shown.is_empty() {
            return false;
        }
        let last = self.shown.len() - 1;
        let next = match (self.cursor, movement) {
            (None, Move::Up | Move::End) => last,
            (None, _) => 0,
            (Some(cursor), Move::Up) => cursor.saturating_sub(1),
            (Some(cursor), Move::Down) => (cursor + 1).min(last),
            (Some(cursor), Move::PageUp(page)) => cursor.saturating_sub(page.max(1)),
            (Some(cursor), Move::PageDown(page)) => (cursor + page.max(1)).min(last),
            (Some(_), Move::Home) => 0,
            (Some(_), Move::End) => last,
        };
        self.click(next, false, shift)
    }

    /// 選んでいる行を 1 つだけにして position にする(入力欄から書き換えるときなど)
    pub fn select_only(&mut self, position: usize) {
        self.click(position, false, false);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn table() -> Table {
        let mut table = Table::default();
        table.set_rows(
            ["kyou", "Kyouto", "ashita", "asa"]
                .iter()
                .map(|cell| vec![(*cell).to_string(), "x".into()])
                .collect(),
        );
        table
    }

    #[test]
    fn 検索の言葉で絞り大文字と小文字を区別しない() {
        let mut table = table();
        table.filter("KYOU");
        assert_eq!(table.len(), 2);
        assert_eq!(table.shown_row(1).unwrap()[0], "Kyouto");
        table.filter("");
        assert_eq!(table.len(), 4);
        table.filter("zzz");
        assert!(table.is_empty());
    }

    #[test]
    fn 絞った行を選ぶと全体の番号で返す() {
        let mut table = table();
        table.filter("as");
        assert!(table.click(1, false, false));
        assert_eq!(table.selected_positions(), vec![1]);
        assert_eq!(table.selected_rows(), vec![3]);
        // 絞り直すと選びを外す
        table.filter("a");
        assert!(table.selected_rows().is_empty());
    }

    #[test]
    fn コントロールとシフトで複数を選ぶ() {
        let mut table = table();
        table.click(0, false, false);
        table.click(2, true, false);
        assert_eq!(table.selected_positions(), vec![0, 2]);
        table.click(2, true, false);
        assert_eq!(table.selected_positions(), vec![0]);
        table.click(1, false, false);
        table.click(3, false, true);
        assert_eq!(table.selected_positions(), vec![1, 2, 3]);
        assert!(!table.click(9, false, false));
    }

    #[test]
    fn キーボードで選ぶ行を動かす() {
        let mut table = table();
        assert!(table.move_cursor(Move::Down, false));
        assert_eq!(table.selected_positions(), vec![0]);
        table.move_cursor(Move::Down, false);
        table.move_cursor(Move::Down, true);
        assert_eq!(table.selected_positions(), vec![1, 2]);
        table.move_cursor(Move::End, false);
        assert_eq!(table.selected_positions(), vec![3]);
        assert!(!table.move_cursor(Move::Down, false));
        table.move_cursor(Move::PageUp(2), false);
        assert_eq!(table.cursor(), Some(1));
        table.move_cursor(Move::Home, false);
        assert_eq!(table.selected_positions(), vec![0]);
    }

    #[test]
    fn 行を入れ替えると選びを外す() {
        let mut table = table();
        table.click(1, false, false);
        table.set_rows(vec![vec!["a".into()]]);
        assert!(table.selected_positions().is_empty());
        assert_eq!(table.cursor(), None);
    }
}
