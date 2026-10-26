#![forbid(unsafe_code)]

//! 入力メニュー(タスクバーの「あ」「A」を右クリックしたときのメニュー)の項目．macOS の入力メニューと同じ項目にする．
//! 項目はよく切り替えるものだけにし，ほかの設定は設定の画面にまとめる

use ipc::{InputMode, MenuCommand, SettingsSnapshot};

pub const LIVE_CONVERSION: &str = "ライブ変換";
pub const INPUT_STYLE: &str = "入力方式";
pub const OPEN_SETTINGS: &str = "設定を開く…";

/// 入力方式の値(設定のファイルの値)と名前．並びは macOS の入力メニューと同じ
pub const INPUT_STYLES: &[(&str, &str)] = &[
    ("romaji", "ローマ字入力"),
    ("kana", "かな入力"),
    ("english", "英字入力"),
    ("englishAuto", "英字入力(自動)"),
];

/// 日本語・英数のときにタスクバーに出す字と，説明
pub const JAPANESE_ICON: &str = "あ";
pub const DIRECT_ICON: &str = "A";
pub const DESCRIPTION: &str = "入力モード";

const ID_LIVE_CONVERSION: u32 = 1;
const ID_OPEN_SETTINGS: u32 = 2;
const ID_INPUT_STYLE_BASE: u32 = 10;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Item {
    Command {
        id: u32,
        label: &'static str,
        checked: bool,
    },
    Header(&'static str),
    Separator,
}

/// 今の設定に合わせた項目．設定を読めなければ印を付けない
pub fn items(settings: Option<&SettingsSnapshot>) -> Vec<Item> {
    let mut items = vec![
        Item::Command {
            id: ID_LIVE_CONVERSION,
            label: LIVE_CONVERSION,
            checked: settings.is_some_and(|current| current.live_conversion),
        },
        Item::Separator,
        Item::Header(INPUT_STYLE),
    ];
    for (offset, (value, label)) in (0u32..).zip(INPUT_STYLES) {
        items.push(Item::Command {
            id: ID_INPUT_STYLE_BASE + offset,
            label,
            checked: settings.is_some_and(|current| current.input_style == *value),
        });
    }
    items.push(Item::Separator);
    items.push(Item::Command {
        id: ID_OPEN_SETTINGS,
        label: OPEN_SETTINGS,
        checked: false,
    });
    items
}

/// 選んだ項目の操作．知らない番号なら None
pub fn command(id: u32) -> Option<MenuCommand> {
    match id {
        ID_LIVE_CONVERSION => Some(MenuCommand::ToggleLiveConversion),
        ID_OPEN_SETTINGS => Some(MenuCommand::OpenSettings),
        _ => {
            let index = id.checked_sub(ID_INPUT_STYLE_BASE)? as usize;
            let (value, _) = INPUT_STYLES.get(index)?;
            Some(MenuCommand::SelectInputStyle {
                style: (*value).to_string(),
            })
        }
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

    fn snapshot(style: &str, live: bool) -> SettingsSnapshot {
        SettingsSnapshot {
            theme: "automatic".into(),
            input_style: style.into(),
            live_conversion: live,
            shows_mode_indicator: true,
            shows_key_hints: true,
            candidate_font_size: 15.0,
        }
    }

    fn checked(items: &[Item]) -> Vec<&'static str> {
        items
            .iter()
            .filter_map(|item| match item {
                Item::Command {
                    label,
                    checked: true,
                    ..
                } => Some(*label),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn 今の入力方式とライブ変換に印を付ける() {
        let current = snapshot("kana", true);
        assert_eq!(
            checked(&items(Some(&current))),
            vec![LIVE_CONVERSION, "かな入力"]
        );
        let other = snapshot("englishAuto", false);
        assert_eq!(checked(&items(Some(&other))), vec!["英字入力(自動)"]);
        assert!(checked(&items(None)).is_empty());
    }

    #[test]
    fn 項目の番号から操作を引く() {
        let ids: Vec<u32> = items(None)
            .iter()
            .filter_map(|item| match item {
                Item::Command { id, .. } => Some(*id),
                _ => None,
            })
            .collect();
        let commands: Vec<MenuCommand> = ids.iter().filter_map(|id| command(*id)).collect();
        assert_eq!(commands.len(), ids.len());
        assert_eq!(commands[0], MenuCommand::ToggleLiveConversion);
        assert_eq!(
            commands[2],
            MenuCommand::SelectInputStyle {
                style: "kana".into()
            }
        );
        assert_eq!(commands.last(), Some(&MenuCommand::OpenSettings));
        assert_eq!(command(0), None);
        assert_eq!(command(ID_INPUT_STYLE_BASE + 4), None);
    }

    #[test]
    fn モードで字を変える() {
        assert_eq!(icon_text(Some(InputMode::Japanese)), "あ");
        assert_eq!(icon_text(Some(InputMode::Direct)), "A");
        assert_eq!(icon_text(None), "A");
    }
}
