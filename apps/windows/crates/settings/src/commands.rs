#![forbid(unsafe_code)]

//! 読みで呼び出すコマンドを足す・書き換えるシートの中身(macOS の CommandsPage の CommandDraft と CommandEditor)．
//! 形の確かめは core の LauncherCommand.isValid に合わせる．長さの上限と id はエンジンが確かめ，
//! 残らなければ画面が知らせる

use crate::list::Item;
use crate::options::COMMAND_KINDS;
use crate::strings::extras;

/// URL のコマンドに使える scheme(core の DefaultSettings.commandURLSchemes)
const URL_SCHEMES: &[&str] = &["https", "http"];
const OPEN_APPLICATION: &str = "openApplication";
const OPEN_URL: &str = "openURL";
const OPEN_FILE: &str = "openFile";

/// 編集しているコマンド．id は書き換えるコマンド(新しく足すときは None．id はエンジンが振る)
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandDraft {
    pub id: Option<String>,
    pub reading: String,
    pub title: String,
    /// 動作(options::COMMAND_KINDS の番号)
    pub kind: usize,
    pub target: String,
}

impl Default for CommandDraft {
    /// 新しいコマンド(macOS と同じくアプリを開く)
    fn default() -> Self {
        Self {
            id: None,
            reading: String::new(),
            title: String::new(),
            kind: kind_index(OPEN_APPLICATION),
            target: String::new(),
        }
    }
}

impl CommandDraft {
    /// 一覧の行(読み・名前・動作・行き先．動作は設定のファイルに書く値)から作る
    pub fn from_item(id: Option<String>, item: &Item) -> Self {
        let value = |index: usize| item.get(index).cloned().unwrap_or_default();
        Self {
            id,
            reading: value(0),
            title: value(1),
            kind: kind_index(&value(2)),
            target: value(3),
        }
    }

    /// 動作の値(設定のファイルに書く名前)
    pub fn kind_value(&self) -> &'static str {
        COMMAND_KINDS
            .get(self.kind)
            .map_or(OPEN_APPLICATION, |(value, _)| value)
    }

    /// 一覧の行(前後の空白を除く)
    pub fn item(&self) -> Item {
        vec![
            self.reading.trim().to_string(),
            self.title.trim().to_string(),
            self.kind_value().to_string(),
            self.target.trim().to_string(),
        ]
    }

    /// 形の正しいコマンドか(保存のボタンを使えるか)
    pub fn is_valid(&self) -> bool {
        is_reading(self.reading.trim())
            && is_title(self.title.trim())
            && is_target(self.target.trim(), self.kind_value())
    }

    /// 確かめる文を出すか(何か書いてあって，形が正しくないとき．macOS と同じく空のシートでは出さない)
    pub fn shows_problem(&self) -> bool {
        !self.is_valid()
            && [&self.reading, &self.title, &self.target]
                .iter()
                .any(|text| !text.trim().is_empty())
    }

    /// 行き先の欄の案内(URL だけ「https://」)
    pub fn target_prompt(&self) -> &'static str {
        if self.kind_value() == OPEN_URL {
            extras::TARGET_PLACEHOLDER_U_R_L
        } else {
            ""
        }
    }

    /// 行き先を選ぶボタンの名前(URL は選ばないので None)
    pub fn choose_label(&self) -> Option<&'static str> {
        match self.kind_value() {
            OPEN_APPLICATION => Some(extras::CHOOSE_APPLICATION),
            OPEN_FILE => Some(extras::CHOOSE_FILE),
            _ => None,
        }
    }

    /// 選ぶ窓で選んだアプリかファイルを行き先にする．名前が空なら拡張子を除いたファイルの名前にする(macOS と同じ)
    pub fn choose(&mut self, path: &str) {
        self.target = path.to_string();
        if self.title.trim().is_empty() {
            self.title = std::path::Path::new(path)
                .file_stem()
                .map(|stem| stem.to_string_lossy().to_string())
                .unwrap_or_default();
        }
    }

    /// アプリを選ぶか(実行ファイルだけを出す)
    pub fn chooses_application(&self) -> bool {
        self.kind_value() == OPEN_APPLICATION
    }
}

fn kind_index(value: &str) -> usize {
    COMMAND_KINDS
        .iter()
        .position(|(raw, _)| *raw == value)
        .unwrap_or(0)
}

/// 読みとして使えるか(core の ReadingNormalization: ひらがな・カタカナ・長音か，英字を含む英数字と「-」)
fn is_reading(reading: &str) -> bool {
    if reading.is_empty() {
        return false;
    }
    let kana = reading
        .chars()
        .all(|c| matches!(c, '\u{3041}'..='\u{3096}' | '\u{30A1}'..='\u{30F6}' | 'ー'));
    let romaji = reading
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '-')
        && reading.chars().any(|c| c.is_ascii_alphabetic());
    kana || romaji
}

/// 名前として使えるか(空でなく，改行とタブを含まない)
fn is_title(title: &str) -> bool {
    !title.is_empty() && !title.contains(['\n', '\r', '\t'])
}

/// 行き先として使えるか(空でなく，制御文字を含まない．URL は http・https で，ホストがある)
fn is_target(target: &str, kind: &str) -> bool {
    if target.is_empty() || target.chars().any(char::is_control) {
        return false;
    }
    if kind != OPEN_URL {
        return true;
    }
    let Some((scheme, rest)) = target.split_once("://") else {
        return false;
    };
    let host = rest.split(['/', '?', '#']).next().unwrap_or("");
    URL_SCHEMES.contains(&scheme.to_lowercase().as_str())
        && !host.is_empty()
        && !target.contains(char::is_whitespace)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn draft(reading: &str, title: &str, kind: &str, target: &str) -> CommandDraft {
        CommandDraft {
            id: None,
            reading: reading.into(),
            title: title.into(),
            kind: kind_index(kind),
            target: target.into(),
        }
    }

    #[test]
    fn 読み_名前_行き先がそろえば保存できる() {
        assert!(draft("めも", "メモ帳", OPEN_APPLICATION, "notepad.exe").is_valid());
        assert!(draft("memo", "メモ帳", OPEN_APPLICATION, "notepad.exe").is_valid());
        assert!(draft("メモ", "メモ帳", OPEN_FILE, "C:\\a.txt").is_valid());
        assert!(!draft("めも1あ", "メモ帳", OPEN_APPLICATION, "x").is_valid());
        assert!(!draft("123", "数", OPEN_APPLICATION, "x").is_valid());
        assert!(!draft("めも", " ", OPEN_APPLICATION, "x").is_valid());
        assert!(!draft("めも", "a\tb", OPEN_APPLICATION, "x").is_valid());
        assert!(!draft("めも", "メモ帳", OPEN_APPLICATION, "").is_valid());
    }

    #[test]
    fn url_は_http_と_https_だけ() {
        assert!(draft("どきゅ", "文書", OPEN_URL, "https://haji.men/docs/").is_valid());
        assert!(draft("どきゅ", "文書", OPEN_URL, "HTTP://example.com").is_valid());
        assert!(!draft("どきゅ", "文書", OPEN_URL, "file:///C:/a").is_valid());
        assert!(!draft("どきゅ", "文書", OPEN_URL, "https://").is_valid());
        assert!(!draft("どきゅ", "文書", OPEN_URL, "haji.men").is_valid());
    }

    #[test]
    fn 空のシートでは確かめる文を出さない() {
        assert!(!CommandDraft::default().shows_problem());
        assert!(draft("めも", "", OPEN_APPLICATION, "").shows_problem());
        assert!(!draft("めも", "メモ帳", OPEN_APPLICATION, "notepad.exe").shows_problem());
    }

    #[test]
    fn 動作で案内と選ぶボタンが変わる() {
        let app = draft("", "", OPEN_APPLICATION, "");
        assert_eq!(app.choose_label(), Some(extras::CHOOSE_APPLICATION));
        assert_eq!(app.target_prompt(), "");
        let url = draft("", "", OPEN_URL, "");
        assert_eq!(url.choose_label(), None);
        assert_eq!(url.target_prompt(), extras::TARGET_PLACEHOLDER_U_R_L);
        assert_eq!(
            draft("", "", OPEN_FILE, "").choose_label(),
            Some(extras::CHOOSE_FILE)
        );
    }

    #[test]
    fn 行の値と行き来する() {
        let item: Item = ["めも", "メモ帳", OPEN_URL, "https://a.example"]
            .iter()
            .map(|text| text.to_string())
            .collect();
        let draft = CommandDraft::from_item(Some("id".into()), &item);
        assert_eq!(draft.kind_value(), OPEN_URL);
        assert_eq!(draft.item(), item);
        let mut padded = draft.clone();
        padded.reading = " めも ".into();
        assert_eq!(padded.item(), item);
    }

    #[test]
    fn 選んだファイルの名前を名前の欄に入れる() {
        let mut draft = CommandDraft::default();
        // 区切りは Linux の検査でも読める「/」で書く(Windows はどちらの区切りも読む)
        draft.choose("C:/Windows/notepad.exe");
        assert_eq!(draft.target, "C:/Windows/notepad.exe");
        assert_eq!(draft.title, "notepad");
        draft.choose("C:/Windows/regedit.exe");
        assert_eq!(draft.title, "notepad");
    }
}
