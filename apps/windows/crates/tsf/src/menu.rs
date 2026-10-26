#![forbid(unsafe_code)]

//! 入力メニュー(タスクバーの「あ」「A」を右クリックしたときのメニュー)の項目．macOS の入力メニューと同じ項目にする．
//! 項目は「ライブ変換」「手書き入力」(使う設定のときだけ)「設定を開く…」にし，入力方式などほかの設定は設定の画面とキーで変える

use ipc::{InputMode, MenuCommand, SettingsSnapshot};

pub const LIVE_CONVERSION: &str = "ライブ変換";
pub const HANDWRITING: &str = "手書き入力";
pub const OPEN_SETTINGS: &str = "設定を開く…";

/// 日本語・英数のときにタスクバーに出す字と，説明
pub const JAPANESE_ICON: &str = "あ";
pub const DIRECT_ICON: &str = "A";
pub const DESCRIPTION: &str = "入力モード";

const ID_LIVE_CONVERSION: u32 = 1;
const ID_OPEN_SETTINGS: u32 = 2;
const ID_HANDWRITING: u32 = 3;

/// 選んだ項目の扱い
#[derive(Debug, Clone, PartialEq)]
pub enum Selection {
    /// エンジンに操作を頼む
    Command(MenuCommand),
    /// 手書きの窓を開く(組み立て中の文字を確定するので，文書を書き換えられる要求で頼む)
    Handwriting,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Item {
    Command {
        id: u32,
        label: &'static str,
        checked: bool,
    },
    Separator,
}

/// 今の設定に合わせた項目．設定を読めなければ印を付けない
pub fn items(settings: Option<&SettingsSnapshot>) -> Vec<Item> {
    let mut items = vec![Item::Command {
        id: ID_LIVE_CONVERSION,
        label: LIVE_CONVERSION,
        checked: settings.is_some_and(|current| current.live_conversion),
    }];
    // 手書き入力は設定で使うときだけ出す(macOS の入力メニューと同じ)
    if settings.is_some_and(|current| current.handwriting == Some(true)) {
        items.push(Item::Command {
            id: ID_HANDWRITING,
            label: HANDWRITING,
            checked: false,
        });
    }
    items.extend([
        Item::Separator,
        Item::Command {
            id: ID_OPEN_SETTINGS,
            label: OPEN_SETTINGS,
            checked: false,
        },
    ]);
    items
}

/// 選んだ項目の操作．知らない番号なら None
pub fn selection(id: u32) -> Option<Selection> {
    match id {
        ID_LIVE_CONVERSION => Some(Selection::Command(MenuCommand::ToggleLiveConversion)),
        ID_OPEN_SETTINGS => Some(Selection::Command(MenuCommand::OpenSettings)),
        ID_HANDWRITING => Some(Selection::Handwriting),
        _ => None,
    }
}

/// タスクバーに出す字
pub fn icon_text(mode: Option<InputMode>) -> &'static str {
    match mode {
        Some(InputMode::Japanese) => JAPANESE_ICON,
        _ => DIRECT_ICON,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot(live: bool) -> SettingsSnapshot {
        SettingsSnapshot {
            handwriting: None,
            theme: "automatic".into(),
            input_style: "romaji".into(),
            live_conversion: live,
            shows_mode_indicator: true,
            shows_key_hints: true,
            candidate_font_size: 15.0,
        }
    }

    fn labels(items: &[Item]) -> Vec<(&'static str, bool)> {
        items
            .iter()
            .filter_map(|item| match item {
                Item::Command { label, checked, .. } => Some((*label, *checked)),
                Item::Separator => None,
            })
            .collect()
    }

    #[test]
    fn 項目はライブ変換と設定を開くだけ() {
        assert_eq!(
            labels(&items(Some(&snapshot(true)))),
            vec![(LIVE_CONVERSION, true), (OPEN_SETTINGS, false)]
        );
        assert_eq!(
            labels(&items(None)),
            vec![(LIVE_CONVERSION, false), (OPEN_SETTINGS, false)]
        );
    }

    #[test]
    fn 手書き入力は使う設定のときだけ出す() {
        let mut on = snapshot(false);
        on.handwriting = Some(true);
        assert_eq!(
            labels(&items(Some(&on))),
            vec![
                (LIVE_CONVERSION, false),
                (HANDWRITING, false),
                (OPEN_SETTINGS, false)
            ]
        );
        on.handwriting = Some(false);
        assert_eq!(
            labels(&items(Some(&on))),
            vec![(LIVE_CONVERSION, false), (OPEN_SETTINGS, false)]
        );
    }

    #[test]
    fn 項目の番号から操作を引く() {
        assert_eq!(
            selection(ID_LIVE_CONVERSION),
            Some(Selection::Command(MenuCommand::ToggleLiveConversion))
        );
        assert_eq!(
            selection(ID_OPEN_SETTINGS),
            Some(Selection::Command(MenuCommand::OpenSettings))
        );
        assert_eq!(selection(ID_HANDWRITING), Some(Selection::Handwriting));
        assert_eq!(selection(0), None);
        assert_eq!(selection(10), None);
    }

    #[test]
    fn モードで字を変える() {
        assert_eq!(icon_text(Some(InputMode::Japanese)), "あ");
        assert_eq!(icon_text(Some(InputMode::Direct)), "A");
        assert_eq!(icon_text(None), "A");
    }
}
