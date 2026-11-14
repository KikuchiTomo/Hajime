#![forbid(unsafe_code)]

//! キー設定の表のキーの書き方と，表の問題(使われない行・文字を打てなくなる行・キーの無い確定と取り消し)の文．
//! キーの書き方は core の KeyStroke(notation:) と同じ決まりで読み，同じ形(修飾キーは Ctrl・Option・Shift・Cmd の順)に整える．
//! 画面では Option を Windows の名前の Alt で出す

use crate::strings::keys::{COMMANDS, STATES};
use ipc::{KeymapMissing, KeymapReport};
use serde_json::{json, Value};

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

/// キーの無い確定・取り消し(missing)に，standard の表でそのコマンド(か代わりのコマンド)に使うキーを 1 つずつ足した表．
/// その状態の行を先に，無ければ いつでも の行から選ぶ．変換中の取り消しは，直前の変更の取り消しでも足りる
/// (core の Keymap.addMissingEssentials)．足すものが無ければ None
pub fn with_missing(keymap: &Value, missing: &[KeymapMissing], standard: &Value) -> Option<Value> {
    let rows = standard.as_array()?;
    let text = |row: &Value, name: &str| row.get(name).and_then(Value::as_str).map(str::to_string);
    let found = |state: &str, command: &str| {
        let substitutes: &[&str] = if state == "converting" && command == "cancel" {
            &["cancel", "undoConversionEdit"]
        } else {
            &[command]
        };
        [state, "anywhere"].iter().find_map(|wanted| {
            substitutes.iter().find_map(|substitute| {
                rows.iter()
                    .find(|row| {
                        text(row, "state").as_deref() == Some(*wanted)
                            && text(row, "command").as_deref() == Some(*substitute)
                    })
                    .and_then(|row| Some((text(row, "key")?, substitute.to_string())))
            })
        })
    };
    let added: Vec<Value> = missing
        .iter()
        .filter_map(|item| {
            let (key, command) = found(&item.state, &item.command)?;
            Some(json!({"state": item.state, "key": key, "command": command}))
        })
        .collect();
    if added.is_empty() {
        return None;
    }
    let mut entries = keymap.as_array().cloned().unwrap_or_default();
    entries.extend(added);
    Some(Value::Array(entries))
}

/// 文字を打つ状態(修飾キーの無い文字のキーを置くと，その文字を打てなくなる状態．core の KeymapEntry.blocksTyping)
const TYPING_STATES: &[&str] = &["anywhere", "idle", "composing"];

/// 修飾キーの無い文字のキーを，文字を打つ状態に置いた行か(core の KeymapEntry.blocksTyping と KeyStroke.isPlainCharacter)．
/// Shift だけを押した文字のキーも，その文字を打てなくなる
pub fn blocks_typing(state: &str, key: &str) -> bool {
    let Some(notation) = canonical(key) else {
        return false;
    };
    let mut parts: Vec<&str> = notation.split(' ').collect();
    let character = parts.pop().is_some_and(|key| key.chars().count() == 1);
    character && parts.iter().all(|part| *part == "Shift") && TYPING_STATES.contains(&state)
}

/// 足す前の新しい行に添える知らせ(macOS の KeymapPage の draftNote)
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DraftNote {
    /// 同じ状態・同じキーの行があり，新しい行がその行より優先される(その行を示す文)
    Overrides(String),
    /// 書き換えている行より下に同じ状態・同じキーの行があり，書き換えた行は使われない(下の行を示す文)
    Hidden(String),
    /// その文字を打てなくなる
    PlainCharacter,
}

impl DraftNote {
    /// 入力欄の下に出す文
    pub fn text(&self) -> String {
        match self {
            DraftNote::Overrides(row) => crate::strings::keys::duplicate_warning(row),
            DraftNote::Hidden(row) => crate::strings::keys::hidden(row),
            DraftNote::PlainCharacter => crate::strings::keys::PLAIN_CHARACTER.to_string(),
        }
    }
}

/// 新しい行(state・key)を足す前の知らせ．entries は今の表の行(状態・キー・コマンド)，replacing は書き換えている行．
/// 同じ状態・同じキーの行(いちばん下のもの)があればそれを知らせ，無ければ文字を打てなくなるキーを知らせる．
/// 同じキーの行は下の行を使うので，足す行(表の最後に入る)と，下の行を書き換えるときは新しい行が優先される
pub fn draft_note(
    state: &str,
    key: &str,
    entries: &[(String, String, String)],
    replacing: Option<usize>,
) -> Option<DraftNote> {
    let notation = canonical(key)?;
    let existing = entries.iter().enumerate().rev().find(|(index, entry)| {
        Some(*index) != replacing
            && entry.0 == state
            && canonical(&entry.1).as_deref() == Some(notation.as_str())
    });
    if let Some((index, _)) = existing {
        let row = describe(entries, index as u32);
        return Some(if replacing.is_some_and(|replacing| index > replacing) {
            DraftNote::Hidden(row)
        } else {
            DraftNote::Overrides(row)
        });
    }
    blocks_typing(state, &notation).then_some(DraftNote::PlainCharacter)
}

/// 表に出している行(状態・キー・コマンドの名前)を，設定のファイルの値(状態・キーの書き方・コマンド)に戻す．
/// 読めないキーは空にする(どの行とも重ならない)
pub fn entry_of(cells: &[String]) -> (String, String, String) {
    let value = |choices: &[(&str, &str)], index: usize| {
        let cell = cells.get(index).map_or("", String::as_str);
        choices
            .iter()
            .find(|(_, label)| *label == cell)
            .map_or_else(|| cell.to_string(), |(raw, _)| (*raw).to_string())
    };
    (
        value(STATES, 0),
        cells
            .get(1)
            .and_then(|cell| canonical(cell))
            .unwrap_or_default(),
        value(COMMANDS, 2),
    )
}

/// 表の問題を 1 行ずつの文にする．entries は表の行(状態・キー・コマンド)
pub fn report_lines(report: &KeymapReport, entries: &[(String, String, String)]) -> Vec<String> {
    use crate::strings::keys::{missing, PLAIN_CHARACTER};
    let mut lines: Vec<String> = report
        .missing
        .iter()
        .map(|item| missing(&label(STATES, &item.state), &label(COMMANDS, &item.command)))
        .collect();
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
            lines[1],
            "入力中・Enter・確定: 同じキーの行があるため無効: 入力中・Enter・取り消し"
        );
    }

    fn entry(state: &str, key: &str, command: &str) -> (String, String, String) {
        (state.to_string(), key.to_string(), command.to_string())
    }

    #[test]
    fn 足す前に同じ状態と同じキーの行を知らせる() {
        let entries = vec![
            entry("composing", "Enter", "commit"),
            entry("composing", "Ctrl Space", "cancel"),
            entry("converting", "Ctrl Space", "commit"),
            entry("composing", "Ctrl Space", "commit"),
        ];
        // 同じ行がいくつもあれば，いちばん下(いま使われている行)を示す
        assert_eq!(
            draft_note("composing", "Ctrl+Space", &entries, None),
            Some(DraftNote::Overrides("入力中・Ctrl+Space・確定".into()))
        );
        assert_eq!(
            draft_note("composing", "ctrl space", &entries, None).map(|note| note.text()),
            Some("同じキーの行より優先します: 入力中・Ctrl+Space・確定".into())
        );
        // 状態かキーが違えば知らせない
        assert_eq!(draft_note("idle", "Ctrl Space", &entries, None), None);
        assert_eq!(draft_note("composing", "Space", &entries, None), None);
        // 読めないキーは知らせない(形の誤りは別に知らせる)
        assert_eq!(draft_note("composing", "Hyper k", &entries, None), None);
    }

    #[test]
    fn 書き換えている行は自分と比べず_下に同じキーの行があれば使われないと知らせる() {
        let entries = vec![
            entry("composing", "Enter", "commit"),
            entry("composing", "Ctrl Space", "cancel"),
            entry("composing", "Tab", "commit"),
        ];
        assert_eq!(draft_note("composing", "Enter", &entries, Some(0)), None);
        assert_eq!(
            draft_note("composing", "Ctrl Space", &entries, Some(0)),
            Some(DraftNote::Hidden("入力中・Ctrl+Space・取り消し".into()))
        );
        assert_eq!(
            draft_note("composing", "Ctrl Space", &entries, Some(2)),
            Some(DraftNote::Overrides("入力中・Ctrl+Space・取り消し".into()))
        );
    }

    #[test]
    fn 足す前に文字を打てなくなるキーを知らせる() {
        for state in ["anywhere", "idle", "composing"] {
            assert_eq!(
                draft_note(state, "k", &[], None),
                Some(DraftNote::PlainCharacter),
                "{state}"
            );
        }
        assert_eq!(
            draft_note("composing", "Shift k", &[], None),
            Some(DraftNote::PlainCharacter)
        );
        // 文字を打たない状態，修飾キーのあるキー，文字でないキーは知らせない
        assert_eq!(draft_note("converting", "k", &[], None), None);
        assert_eq!(draft_note("direct", "k", &[], None), None);
        assert_eq!(draft_note("composing", "Ctrl k", &[], None), None);
        assert_eq!(draft_note("composing", "Space", &[], None), None);
        assert_eq!(draft_note("composing", "F1", &[], None), None);
        // 同じキーの行があれば，そちらを知らせる
        assert_eq!(
            draft_note("idle", "k", &[entry("idle", "k", "commit")], None),
            Some(DraftNote::Overrides("未入力・K・確定".into()))
        );
    }

    #[test]
    fn 表に出している行を設定の値に戻す() {
        let cells: Vec<String> = ["入力中", "Ctrl+Alt+K", "確定", "", "1"]
            .iter()
            .map(|cell| (*cell).to_string())
            .collect();
        assert_eq!(
            entry_of(&cells),
            entry("composing", "Ctrl Option k", "commit")
        );
    }

    #[test]
    fn キーの無い確定と取り消しに標準の表のキーを足す() {
        let standard = serde_json::json!([
            {"state": "anywhere", "key": "Enter", "command": "commit"},
            {"state": "anywhere", "key": "Escape", "command": "cancel"},
            {"state": "converting", "key": "Ctrl Enter", "command": "commit"},
            {"state": "converting", "key": "Escape", "command": "undoConversionEdit"},
        ]);
        let keymap =
            serde_json::json!([{"state": "idle", "key": "F12", "command": "emojiPalette"}]);
        let missing = |state: &str, command: &str| KeymapMissing {
            state: state.into(),
            command: command.into(),
        };
        let added = with_missing(
            &keymap,
            &[
                missing("composing", "commit"),
                missing("converting", "commit"),
                missing("converting", "cancel"),
            ],
            &standard,
        )
        .unwrap();
        assert_eq!(
            added,
            serde_json::json!([
                {"state": "idle", "key": "F12", "command": "emojiPalette"},
                {"state": "composing", "key": "Enter", "command": "commit"},
                {"state": "converting", "key": "Ctrl Enter", "command": "commit"},
                {"state": "converting", "key": "Escape", "command": "undoConversionEdit"},
            ])
        );
        assert_eq!(with_missing(&keymap, &[], &standard), None);
        assert_eq!(
            with_missing(&keymap, &[missing("composing", "openMenu")], &standard),
            None
        );
    }
}
