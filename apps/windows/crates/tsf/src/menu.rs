#![forbid(unsafe_code)]

//! 入力メニュー(タスクバーの「あ」「A」を右クリックしたときと，キーで入力位置に出すときのメニュー)の項目．macOS の入力メニューと同じ項目にする．
//! 項目は「ライブ変換」「手書き入力」「絵文字と記号」(この 2 つは使う設定のときだけ)，区切りの線，「単語の登録…」「ユーザー辞書…」
//! 「設定を開く…」「更新を確認」にし，入力方式などほかの設定は設定の画面とキーで変える

use ipc::{InputMode, MenuCommand, SettingsSnapshot};

pub const LIVE_CONVERSION: &str = "ライブ変換";
pub const HANDWRITING: &str = "手書き入力";
pub const PALETTE: &str = "絵文字と記号";
pub const REGISTER_WORD: &str = "単語の登録…";
pub const USER_DICTIONARY: &str = "ユーザー辞書…";
pub const OPEN_SETTINGS: &str = "設定を開く…";
pub const CHECK_FOR_UPDATES: &str = "更新を確認";
/// 「更新を確認」で設定の画面の実行ファイルに渡す引数(最新のリリースのページを開いて終える)
pub const CHECK_FOR_UPDATES_ARGUMENT: &str = "--check-for-updates";
/// エンジンが受けなかったときに，設定の画面をユーザー辞書の登録した単語のページで直接開く引数(EngineService.settingsDictionaryArguments と同じ)
pub const USER_DICTIONARY_ARGUMENTS: &str = "--page dictionary";
/// 単語の登録で，設定の画面を直接開く引数．設定の画面は読みの欄に入力位置を置く(語はエンジンが持っているときだけ入る．
/// 入力内容なので引数には入れない)
pub const REGISTER_WORD_ARGUMENTS: &str = "--page dictionary --register-word";

/// 日本語・英数のときにタスクバーに出す字と，説明
pub const JAPANESE_ICON: &str = "あ";
pub const DIRECT_ICON: &str = "A";
pub const DESCRIPTION: &str = "入力モード";
/// エンジンにつながっていないときのツールチップ．設定の画面を開くとエンジンを起動し直す
pub const ENGINE_UNAVAILABLE: &str =
    "入力モード(変換エンジンに接続できません．設定を開くと起動し直します)";

const ID_LIVE_CONVERSION: u32 = 1;
const ID_OPEN_SETTINGS: u32 = 2;
const ID_HANDWRITING: u32 = 3;
const ID_CHECK_FOR_UPDATES: u32 = 4;
const ID_PALETTE: u32 = 5;
const ID_REGISTER_WORD: u32 = 6;
const ID_USER_DICTIONARY: u32 = 7;

/// 選んだ項目の扱い
#[derive(Debug, Clone, PartialEq)]
pub enum Selection {
    /// エンジンに操作を頼む
    Command(MenuCommand),
    /// 手書きの窓を開く(組み立て中の文字を確定するので，文書を書き換えられる要求で頼む)
    Handwriting,
    /// 絵文字と記号のパレットを前に見ていた種類で開く(R-26．組み立て中の文字を確定するので，手書きと同じく文書を書き換えられる要求で頼む)
    Palette,
    /// 単語の登録．入力先で選んでいる文字を読み，エンジンに設定の画面のユーザー辞書の登録で開いてもらう(キーの「単語の登録」と同じ)
    RegisterWord,
    /// 最新のリリースのページを開く(入力先のアプリから起動するので，ブラウザーが前に出る)
    CheckForUpdates,
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
    // 絵文字と記号も設定で使うときだけ，手書き入力の次に出す(macOS の入力メニューと同じ)
    if settings.is_some_and(|current| current.palette == Some(true)) {
        items.push(Item::Command {
            id: ID_PALETTE,
            label: PALETTE,
            checked: false,
        });
    }
    items.extend([
        Item::Separator,
        Item::Command {
            id: ID_REGISTER_WORD,
            label: REGISTER_WORD,
            checked: false,
        },
        Item::Command {
            id: ID_USER_DICTIONARY,
            label: USER_DICTIONARY,
            checked: false,
        },
        Item::Command {
            id: ID_OPEN_SETTINGS,
            label: OPEN_SETTINGS,
            checked: false,
        },
        Item::Command {
            id: ID_CHECK_FOR_UPDATES,
            label: CHECK_FOR_UPDATES,
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
        ID_PALETTE => Some(Selection::Palette),
        ID_REGISTER_WORD => Some(Selection::RegisterWord),
        ID_USER_DICTIONARY => Some(Selection::Command(MenuCommand::OpenUserDictionary)),
        ID_CHECK_FOR_UPDATES => Some(Selection::CheckForUpdates),
        _ => None,
    }
}

/// エンジンが受けなかったときに設定の画面を直接開く引数(エンジンが動いていなくても開けるようにする．設定の画面がエンジンを起動し直す)．
/// 設定の画面を開かないコマンドは None
pub fn settings_arguments(command: &MenuCommand) -> Option<&'static str> {
    match command {
        MenuCommand::OpenSettings => Some(""),
        MenuCommand::OpenUserDictionary => Some(USER_DICTIONARY_ARGUMENTS),
        MenuCommand::ToggleLiveConversion => None,
    }
}

/// タスクバーの表示のツールチップ
pub fn tooltip(connected: bool) -> &'static str {
    if connected {
        DESCRIPTION
    } else {
        ENGINE_UNAVAILABLE
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
            palette: None,
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

    /// 区切りの線の下の，いつも出す項目
    const FIXED: [(&str, bool); 4] = [
        (REGISTER_WORD, false),
        (USER_DICTIONARY, false),
        (OPEN_SETTINGS, false),
        (CHECK_FOR_UPDATES, false),
    ];

    /// head のあとにいつも出す項目を続けた並び
    fn then_fixed(head: &[(&'static str, bool)]) -> Vec<(&'static str, bool)> {
        head.iter().copied().chain(FIXED).collect()
    }

    #[test]
    fn 項目はライブ変換と単語の登録とユーザー辞書と設定を開くと更新を確認() {
        assert_eq!(
            labels(&items(Some(&snapshot(true)))),
            then_fixed(&[(LIVE_CONVERSION, true)])
        );
        assert_eq!(
            labels(&items(None)),
            then_fixed(&[(LIVE_CONVERSION, false)])
        );
    }

    #[test]
    fn 区切りの線は単語の登録の上に引く() {
        let mut all = snapshot(false);
        all.handwriting = Some(true);
        all.palette = Some(true);
        for settings in [None, Some(&all)] {
            let items = items(settings);
            let separator = items
                .iter()
                .position(|item| *item == Item::Separator)
                .unwrap();
            assert_eq!(
                items.get(separator + 1),
                Some(&Item::Command {
                    id: ID_REGISTER_WORD,
                    label: REGISTER_WORD,
                    checked: false
                })
            );
            assert_eq!(
                items
                    .iter()
                    .filter(|item| **item == Item::Separator)
                    .count(),
                1
            );
        }
    }

    #[test]
    fn 手書き入力は使う設定のときだけ出す() {
        let mut on = snapshot(false);
        on.handwriting = Some(true);
        assert_eq!(
            labels(&items(Some(&on))),
            then_fixed(&[(LIVE_CONVERSION, false), (HANDWRITING, false)])
        );
        on.handwriting = Some(false);
        assert_eq!(
            labels(&items(Some(&on))),
            then_fixed(&[(LIVE_CONVERSION, false)])
        );
    }

    #[test]
    fn 絵文字と記号は使う設定のときだけ手書き入力の次に出す() {
        let mut on = snapshot(false);
        on.palette = Some(true);
        assert_eq!(
            labels(&items(Some(&on))),
            then_fixed(&[(LIVE_CONVERSION, false), (PALETTE, false)])
        );
        on.handwriting = Some(true);
        assert_eq!(
            labels(&items(Some(&on))),
            then_fixed(&[
                (LIVE_CONVERSION, false),
                (HANDWRITING, false),
                (PALETTE, false)
            ])
        );
        on.palette = Some(false);
        assert!(!labels(&items(Some(&on))).contains(&(PALETTE, false)));
        // パレットを知らない古いエンジン(palette が無い)では出さない
        on.palette = None;
        assert!(!labels(&items(Some(&on))).contains(&(PALETTE, false)));
        assert!(!labels(&items(None)).contains(&(PALETTE, false)));
    }

    #[test]
    fn 項目の番号は重ならない() {
        let mut all = snapshot(true);
        all.handwriting = Some(true);
        all.palette = Some(true);
        let mut ids: Vec<u32> = items(Some(&all))
            .iter()
            .filter_map(|item| match item {
                Item::Command { id, .. } => Some(*id),
                Item::Separator => None,
            })
            .collect();
        let count = ids.len();
        ids.sort_unstable();
        ids.dedup();
        assert_eq!(ids.len(), count);
        assert!(ids.iter().all(|id| selection(*id).is_some()));
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
        assert_eq!(selection(ID_PALETTE), Some(Selection::Palette));
        assert_eq!(selection(ID_REGISTER_WORD), Some(Selection::RegisterWord));
        assert_eq!(
            selection(ID_USER_DICTIONARY),
            Some(Selection::Command(MenuCommand::OpenUserDictionary))
        );
        assert_eq!(
            selection(ID_CHECK_FOR_UPDATES),
            Some(Selection::CheckForUpdates)
        );
        assert_eq!(selection(0), None);
        assert_eq!(selection(10), None);
    }

    #[test]
    fn 設定の画面を開くコマンドはエンジンが受けなければ直接開く() {
        assert_eq!(settings_arguments(&MenuCommand::OpenSettings), Some(""));
        assert_eq!(
            settings_arguments(&MenuCommand::OpenUserDictionary),
            Some("--page dictionary")
        );
        assert_eq!(settings_arguments(&MenuCommand::ToggleLiveConversion), None);
        // 単語の登録はユーザー辞書のページを開き，登録の欄に入力位置を置く
        assert!(REGISTER_WORD_ARGUMENTS.starts_with(USER_DICTIONARY_ARGUMENTS));
        assert!(REGISTER_WORD_ARGUMENTS.ends_with(" --register-word"));
    }

    #[test]
    fn エンジンにつながっていないことをツールチップで知らせる() {
        assert_eq!(tooltip(true), DESCRIPTION);
        assert_eq!(tooltip(false), ENGINE_UNAVAILABLE);
    }

    #[test]
    fn モードで字を変える() {
        assert_eq!(icon_text(Some(InputMode::Japanese)), "あ");
        assert_eq!(icon_text(Some(InputMode::Direct)), "A");
        assert_eq!(icon_text(None), "A");
    }
}
