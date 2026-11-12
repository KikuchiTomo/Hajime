#![forbid(unsafe_code)]

//! キー設定の表のキーの書き方と，表の問題(使われない行・文字を打てなくなる行・キーの無い確定と取り消し)の文．
//! キーの書き方は core の KeyStroke(notation:) と同じ決まりで読み，同じ形(修飾キーは Ctrl・Option・Shift・Cmd の順)に整える．
//! 画面では Option を Windows の名前の Alt で出す

use crate::strings::keys::{COMMANDS, STATES};
use ipc::KeymapReport;

/// 名前で書くキー(KeyStroke.names)
const NAMES: &[&str] = &[
    "Space",
    "Enter",
    "Tab",
    "Backspace",
    "Delete",
    "Escape",
    "Up",
    "Down",
    "Left",
    "Right",
    "Home",
    "End",
    "PageUp",
    "PageDown",
    "Eisu",
    "Kana",
    "Hankaku/Zenkaku",
    "Henkan",
    "Muhenkan",
];

/// 読むときだけ受け付ける別名(KeyStroke.aliases と，画面に出す Windows の名前)
const ALIASES: &[(&str, &str)] = &[
    ("esc", "Escape"),
    ("return", "Enter"),
    ("kanji", "Hankaku/Zenkaku"),
    ("del", "Delete"),
    ("bs", "Backspace"),
    ("pgup", "PageUp"),
    ("pgdn", "PageDown"),
    ("↑", "Up"),
    ("↓", "Down"),
    ("←", "Left"),
    ("→", "Right"),
    ("英数", "Eisu"),
    ("かな", "Kana"),
    ("半角/全角", "Hankaku/Zenkaku"),
    ("変換", "Henkan"),
    ("無変換", "Muhenkan"),
];

/// 画面に出すキーの名前(core の KeyStroke.label(style: .windows) と同じ)
const LABELS: &[(&str, &str)] = &[
    ("Backspace", "BS"),
    ("Delete", "Del"),
    ("Escape", "Esc"),
    ("Up", "↑"),
    ("Down", "↓"),
    ("Left", "←"),
    ("Right", "→"),
    ("PageUp", "PgUp"),
    ("PageDown", "PgDn"),
    ("Eisu", "英数"),
    ("Kana", "かな"),
    ("Hankaku/Zenkaku", "半角/全角"),
    ("Henkan", "変換"),
    ("Muhenkan", "無変換"),
];

/// ファンクションキーの番号の範囲(KeyStroke.functionKeys)
const FUNCTION_KEYS: std::ops::RangeInclusive<u32> = 1..=20;

/// 「ctrl alt space」「Ctrl+Alt+Space」のような書き方を「Ctrl Option Space」に整える．読めなければ None
pub fn canonical(text: &str) -> Option<String> {
    let text = text.trim();
    // 画面の書き方(「+」でつなぐ)も読む．「Ctrl++」は「+」のキー
    let parts: Vec<&str> = if text.contains('+') && text != "+" {
        let (body, plus) = match text.strip_suffix("++") {
            Some(body) => (body, true),
            None => (text, false),
        };
        let mut parts: Vec<&str> = body
            .split(['+', ' '])
            .filter(|part| !part.is_empty())
            .collect();
        if plus {
            parts.push("+");
        }
        parts
    } else {
        text.split(' ').filter(|part| !part.is_empty()).collect()
    };
    let (last, modifiers) = parts.split_last()?;
    let (mut control, mut option, mut shift, mut command) = (false, false, false, false);
    for modifier in modifiers {
        match modifier.to_lowercase().as_str() {
            "ctrl" | "control" => control = true,
            "option" | "alt" => option = true,
            "shift" => shift = true,
            "cmd" | "command" | "win" => command = true,
            _ => return None,
        }
    }
    let lowered = last.to_lowercase();
    let key = if let Some(name) = NAMES.iter().find(|name| name.to_lowercase() == lowered) {
        (*name).to_string()
    } else if let Some((_, name)) = ALIASES.iter().find(|(alias, _)| *alias == lowered) {
        (*name).to_string()
    } else if let Some(number) = function_number(&lowered) {
        format!("F{number}")
    } else {
        let mut characters = last.chars();
        let character = characters.next()?;
        if characters.next().is_some() || character.is_whitespace() {
            return None;
        }
        // 文字でない記号のキーの Shift は打つ文字に含まれるので外す
        if !character.is_alphabetic() {
            shift = false;
        }
        lowered
    };
    let mut result = Vec::new();
    if control {
        result.push("Ctrl".to_string());
    }
    if option {
        result.push("Option".to_string());
    }
    if shift {
        result.push("Shift".to_string());
    }
    if command {
        result.push("Cmd".to_string());
    }
    result.push(key);
    Some(result.join(" "))
}

/// 名前で書くキーの仮想キーの番号(Windows の VK_*)
const VIRTUAL_KEYS: &[(u16, &str)] = &[
    (0x20, "Space"),
    (0x0D, "Enter"),
    (0x09, "Tab"),
    (0x08, "Backspace"),
    (0x2E, "Delete"),
    (0x1B, "Escape"),
    (0x26, "Up"),
    (0x28, "Down"),
    (0x25, "Left"),
    (0x27, "Right"),
    (0x24, "Home"),
    (0x23, "End"),
    (0x21, "PageUp"),
    (0x22, "PageDown"),
    (0x1C, "Henkan"),
    (0x1D, "Muhenkan"),
    (0x15, "Kana"),
    (0xF2, "Kana"),
    (0xF0, "Eisu"),
    (0x19, "Hankaku/Zenkaku"),
    (0xF3, "Hankaku/Zenkaku"),
    (0xF4, "Hankaku/Zenkaku"),
];
/// USB の LANG1・LANG2 のキー(Apple の JIS キーボードなどの「かな」「英数」)のスキャンコード．
/// Windows は仮想キーを 0x15・0x19 にして送り，日本語の配列ではカナ・半角/全角と同じ番号になるので，スキャンコードで見分ける
/// (IME の DLL の crates/tsf/src/key.rs と同じ)
const SCAN_KEYS: &[(u16, &str)] = &[(0xF2, "Kana"), (0xF1, "Eisu")];
/// F1 の仮想キーの番号(F2 からは 1 ずつ増える)
const VK_F1: u16 = 0x70;
/// 修飾キーだけの仮想キー(Shift・Ctrl・Alt と左右の別，Windows キー)
const MODIFIER_KEYS: &[u16] = &[
    0x10, 0x11, 0x12, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C,
];

/// 押したキーをキーの書き方(「Ctrl Option Space」)にする(キー設定の「キーを記録」)．
/// scan はキーの位置(スキャンコード)，character はそのキーで打てる文字(修飾キーを除いた文字)．修飾キーだけ・書けないキーは None
pub fn from_key(
    vk: u16,
    scan: u16,
    character: Option<char>,
    control: bool,
    alt: bool,
    shift: bool,
) -> Option<String> {
    if MODIFIER_KEYS.contains(&vk) {
        return None;
    }
    let key = if let Some((_, name)) = SCAN_KEYS.iter().find(|(code, _)| *code == scan) {
        (*name).to_string()
    } else if let Some((_, name)) = VIRTUAL_KEYS.iter().find(|(code, _)| *code == vk) {
        (*name).to_string()
    } else if (VK_F1..VK_F1 + *FUNCTION_KEYS.end() as u16).contains(&vk) {
        format!("F{}", vk - VK_F1 + 1)
    } else {
        character
            .filter(|character| !character.is_control())?
            .to_lowercase()
            .to_string()
    };
    let mut parts = Vec::new();
    if control {
        parts.push("ctrl");
    }
    if alt {
        parts.push("alt");
    }
    if shift {
        parts.push("shift");
    }
    parts.push(&key);
    canonical(&parts.join(" "))
}

fn function_number(lowered: &str) -> Option<u32> {
    let digits = lowered.strip_prefix('f')?;
    if digits.is_empty() {
        return None;
    }
    let number: u32 = digits.parse().ok()?;
    FUNCTION_KEYS.contains(&number).then_some(number)
}

/// 画面に出す書き方．Option を Alt にし，英字を大文字にする
pub fn display(notation: &str) -> String {
    // core の KeyStroke.label(style: .windows) と同じく「Ctrl+Alt+K」の形にし，日本語のキーは日本語の名前で出す
    notation
        .split(' ')
        .map(|part| match part {
            "Option" => "Alt".to_string(),
            "Cmd" => "Win".to_string(),
            part if part.chars().count() == 1 => part.to_uppercase(),
            part => LABELS
                .iter()
                .find(|(name, _)| *name == part)
                .map_or_else(|| part.to_string(), |(_, label)| (*label).to_string()),
        })
        .collect::<Vec<_>>()
        .join("+")
}

/// command に割り当てたキー(入力していないときに効く行．状態が「どこでも」か「入力していないとき」)を「、」で並べる．
/// 無ければ「なし」(macOS の PalettePage の keys(for:))
pub fn assigned(keymap: Option<&serde_json::Value>, command: &str) -> String {
    let mut keys: Vec<String> = Vec::new();
    for row in keymap
        .and_then(serde_json::Value::as_array)
        .into_iter()
        .flatten()
    {
        let text = |name: &str| row.get(name).and_then(serde_json::Value::as_str);
        if text("command") != Some(command) || !matches!(text("state"), Some("anywhere" | "idle")) {
            continue;
        }
        if let Some(key) = text("key").map(display) {
            if !keys.contains(&key) {
                keys.push(key);
            }
        }
    }
    if keys.is_empty() {
        crate::strings::palette::NO_KEY.to_string()
    } else {
        keys.join("、")
    }
}

fn label(choices: &[(&str, &'static str)], value: &str) -> String {
    choices
        .iter()
        .find(|(raw, _)| *raw == value)
        .map_or_else(|| value.to_string(), |(_, label)| (*label).to_string())
}

/// 行を 1 行の文にする(UIStrings.Keys.describe)
fn describe(entries: &[(String, String, String)], row: u32) -> String {
    entries
        .get(row as usize)
        .map_or_else(String::new, |(state, key, command)| {
            format!(
                "{}・{}・{}",
                label(STATES, state),
                display(key),
                label(COMMANDS, command)
            )
        })
}

/// 表の問題を 1 行ずつの文にする．entries は表の行(状態・キー・コマンド)
pub fn report_lines(report: &KeymapReport, entries: &[(String, String, String)]) -> Vec<String> {
    use crate::strings::keys::{missing, MISSING_NOTE, PLAIN_CHARACTER};
    let mut lines: Vec<String> = report
        .missing
        .iter()
        .map(|item| missing(&label(STATES, &item.state), &label(COMMANDS, &item.command)))
        .collect();
    if !lines.is_empty() {
        lines.push(MISSING_NOTE.to_string());
    }
    for issue in &report.rows {
        let row = describe(entries, issue.row);
        let winners = issue
            .hidden_by
            .iter()
            .map(|winner| describe(entries, *winner))
            .collect::<Vec<_>>()
            .join("、");
        if !issue.hidden_by.is_empty() && issue.hidden_states.is_empty() {
            lines.push(format!("{row}: {}", crate::strings::keys::hidden(&winners)));
        } else if !issue.hidden_by.is_empty() {
            let states = issue
                .hidden_states
                .iter()
                .map(|state| label(STATES, state))
                .collect::<Vec<_>>()
                .join("・");
            lines.push(format!(
                "{row}: {}",
                crate::strings::keys::partly_hidden(&states, &winners)
            ));
        }
        if issue.blocks_typing {
            lines.push(format!("{row}: {PLAIN_CHARACTER}"));
        }
    }
    lines
}

#[cfg(test)]
mod tests {
    #[test]
    fn コマンドに割り当てたキーを並べる() {
        let keymap = serde_json::json!([
            {"state": "anywhere", "key": "Ctrl Option e", "command": "emojiPalette"},
            {"state": "converting", "key": "Ctrl e", "command": "emojiPalette"},
            {"state": "idle", "key": "F12", "command": "emojiPalette"},
        ]);
        assert_eq!(
            super::assigned(Some(&keymap), "emojiPalette"),
            "Ctrl+Alt+E、F12"
        );
        assert_eq!(super::assigned(Some(&keymap), "symbolPalette"), "なし");
    }

    #[test]
    fn 押したキーを書き方にする() {
        assert_eq!(
            super::from_key(0x20, 0, Some(' '), true, false, true).as_deref(),
            Some("Ctrl Shift Space")
        );
        assert_eq!(
            super::from_key(0x4B, 0, Some('k'), true, true, false).as_deref(),
            Some("Ctrl Option k")
        );
        assert_eq!(
            super::from_key(0x71, 0, None, false, false, false).as_deref(),
            Some("F2")
        );
        assert_eq!(
            super::from_key(0x1C, 0, None, false, false, false).as_deref(),
            Some("Henkan")
        );
        // 記号の Shift は打つ文字に含まれる
        assert_eq!(
            super::from_key(0xBA, 0, Some(':'), false, false, true).as_deref(),
            Some(":")
        );
        assert_eq!(super::from_key(0x10, 0, None, false, false, true), None);
        // LANG2(英数)は半角/全角と同じ仮想キーで来るので，スキャンコードで見分ける
        assert_eq!(
            super::from_key(0x19, 0xF1, None, false, false, false).as_deref(),
            Some("Eisu")
        );
        assert_eq!(
            super::from_key(0x15, 0xF2, None, false, false, false).as_deref(),
            Some("Kana")
        );
        assert_eq!(
            super::from_key(0x19, 0x29, None, false, false, false).as_deref(),
            Some("Hankaku/Zenkaku")
        );
    }

    use super::*;
    use ipc::{KeymapMissing, KeymapRowIssue};

    #[test]
    fn 書き方を整える() {
        assert_eq!(
            canonical("ctrl  alt space").as_deref(),
            Some("Ctrl Option Space")
        );
        assert_eq!(
            canonical("Shift Control k").as_deref(),
            Some("Ctrl Shift k")
        );
        assert_eq!(canonical("esc").as_deref(), Some("Escape"));
        assert_eq!(canonical("f12").as_deref(), Some("F12"));
        assert_eq!(canonical("Shift /").as_deref(), Some("/"));
        assert_eq!(canonical("kanji").as_deref(), Some("Hankaku/Zenkaku"));
    }

    #[test]
    fn 読めない書き方() {
        assert_eq!(canonical(""), None);
        assert_eq!(canonical("Hyper k"), None);
        assert_eq!(canonical("F21"), None);
        assert_eq!(canonical("ab"), None);
    }

    #[test]
    fn 画面では_windows_の書き方で出す() {
        assert_eq!(display("Ctrl Option k"), "Ctrl+Alt+K");
        assert_eq!(display("Shift Space"), "Shift+Space");
        assert_eq!(display("Eisu"), "英数");
        assert_eq!(display("Ctrl Henkan"), "Ctrl+変換");
        assert_eq!(display("Shift Backspace"), "Shift+BS");
        assert_eq!(display("Cmd Up"), "Win+↑");
        // 画面の書き方から元の書き方に戻せる(表の行を入力欄に写して書き換える)
        for notation in [
            "Ctrl Option k",
            "Shift Space",
            "Eisu",
            "Kana",
            "Hankaku/Zenkaku",
            "Ctrl Henkan",
            "Muhenkan",
            "Shift Backspace",
            "Delete",
            "Escape",
            "Shift Up",
            "Ctrl PageDown",
            "F12",
            "Ctrl ,",
            "Ctrl +",
        ] {
            assert_eq!(
                canonical(&display(notation)).as_deref(),
                Some(notation),
                "{notation}"
            );
        }
    }

    #[test]
    fn 問題を文にする() {
        let entries = vec![
            (
                "composing".to_string(),
                "Enter".to_string(),
                "commit".to_string(),
            ),
            (
                "composing".to_string(),
                "Enter".to_string(),
                "cancel".to_string(),
            ),
        ];
        let report = KeymapReport {
            rows: vec![KeymapRowIssue {
                row: 0,
                hidden_by: vec![1],
                hidden_states: Vec::new(),
                blocks_typing: false,
            }],
            missing: vec![KeymapMissing {
                state: "converting".into(),
                command: "commit".into(),
            }],
        };
        let lines = report_lines(&report, &entries);
        assert_eq!(lines[0], "変換中に「確定」のキーがありません");
        assert_eq!(
            lines[2],
            "入力中・Enter・確定: 同じキーの行があるため使われません: 入力中・Enter・取り消し"
        );
    }
}
