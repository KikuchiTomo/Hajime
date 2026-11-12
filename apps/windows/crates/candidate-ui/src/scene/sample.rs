#![forbid(unsafe_code)]

//! 見本の分岐図．設定の画面の外観の見本と，見た目を見比べる PNG の書き出し(デバッグビルド)で同じものを使う．
//! 設定の画面の絵文字の見本(候補の一覧)もここで作る

use ipc::{BranchColumn, BranchMap, CandidateEntry, CandidateFocus, CandidateList, KeyHint};

/// 枝を出していない文節
pub fn column(text: &str) -> BranchColumn {
    BranchColumn {
        text: text.into(),
        alternatives: vec![],
        selected_alternative: None,
        variants: vec![],
        selected_variant: None,
        is_focused: false,
        is_uncertain: false,
        is_decided: false,
        is_corrected: None,
        preview: None,
        shorter: None,
        longer: None,
        usage_note: None,
        homophone: None,
        alternative_notes: vec![],
        alternative_commands: None,
        alternative_comments: None,
        alternative_details: None,
        source_name: None,
        split: None,
    }
}

fn strings(texts: &[&str]) -> Vec<String> {
    texts.iter().map(|text| (*text).to_string()).collect()
}

fn hint(keys: &str, label: &str) -> KeyHint {
    KeyHint {
        keys: keys.into(),
        label: label.into(),
    }
}

/// 3 つの文節のうち最後の文節で候補の枝を開いた分岐図
pub fn branch() -> BranchMap {
    BranchMap {
        association: None,
        association_hint: None,
        association_key: None,
        columns: vec![
            column("私の"),
            BranchColumn {
                is_decided: true,
                is_corrected: None,
                ..column("名前は")
            },
            BranchColumn {
                alternatives: strings(&["中のです", "中野です", "仲のです", "那珂のです"]),
                selected_alternative: Some(1),
                variants: strings(&["なかのです", "ナカノデス", "ﾅｶﾉﾃﾞｽ"]),
                is_focused: true,
                is_uncertain: true,
                shorter: Some("中野で".into()),
                ..column("中野です")
            },
        ],
        position: 1,
        total: 8,
        note: None,
        hints: vec![
            hint("↓", "候補"),
            hint("↑", "文字種"),
            hint("←→", "文節"),
            hint("Alt+→", "要確認の文節"),
            hint("Shift+←→", "区切り調整"),
        ],
        meaning_placement: None,
    }
}

/// 絵文字の見本を作る設定(変換のページの「絵文字」)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EmojiSettings {
    /// 文節を絵文字に変換．オンなら「ねこ」の文節全体の絵文字，オフなら「ねこが」の語を絵文字にした候補を並べる
    pub whole: bool,
    /// 絵文字の位置(1 から数えた何番目か．第 1 候補にはしない)
    pub position: usize,
    /// 絵文字の数
    pub count: usize,
    /// 絵文字の名前を表示
    pub names: bool,
    /// 一覧の 1 ページの候補の数
    pub per_page: usize,
}

/// 見本の「ねこ」のふだんの候補(位置の上限 9 番目より前を埋める数．macOS の SamplePanels.emojiPlacementWords)
const EMOJI_WORDS: [&str; 9] = [
    "猫", "ネコ", "ねこ", "根子", "音子", "値子", "寝子", "子子", "弥固",
];
/// 「ねこが」にするときの助詞
const EMOJI_PARTICLE: &str = "が";
/// 見本の「ねこ」の絵文字と名前(数の上限 5 つ．名前は CLDR)
const EMOJI: [(&str, &str); 5] = [
    ("🐈", "ネコ"),
    ("😺", "にっこり笑う猫"),
    ("😸", "にやっと笑う猫"),
    ("😹", "嬉し泣きする猫"),
    ("😻", "目がハートの猫"),
];

/// 設定の画面の絵文字の見本(macOS の SamplePanels.emojiPlacement)．位置・数・名前の設定を変えると，その場で並びが変わる．
/// 位置と数がわかる範囲(絵文字の後ろのふだんの候補 1 つまで．1 ページに収まる分)だけを出し，
/// 先頭の候補を選んでいる(Space で変換した直後と同じ)
pub fn emoji_placement(settings: EmojiSettings) -> CandidateList {
    let tail = if settings.whole { "" } else { EMOJI_PARTICLE };
    let emoji: Vec<(String, &str)> = EMOJI
        .iter()
        .take(settings.count)
        .map(|(emoji, name)| (format!("{emoji}{tail}"), *name))
        .collect();
    let mut texts: Vec<String> = EMOJI_WORDS
        .iter()
        .map(|word| format!("{word}{tail}"))
        .collect();
    // core の EmojiPlacement と同じく，第 1 候補より前には置かず，ほかの候補が足りなければ末尾に置く
    let at = settings.position.saturating_sub(1).max(1).min(texts.len());
    texts.splice(at..at, emoji.iter().map(|(text, _)| text.clone()));
    let name = |text: &str| {
        emoji
            .iter()
            .find(|(emoji, _)| emoji == text)
            .filter(|_| settings.names)
            .map(|(_, name)| (*name).to_string())
    };
    CandidateList {
        variants: vec![],
        selected_variant: None,
        entries: texts
            .iter()
            .take(settings.per_page.min(at + emoji.len() + 1))
            .map(|text| CandidateEntry {
                text: text.clone(),
                annotation: None,
                corrected_start: None,
                corrected_length: None,
                command: None,
                has_comment: None,
                detail: name(text),
            })
            .collect(),
        selected_entry: Some(0),
        focus: CandidateFocus::Candidate,
        position: 1,
        total: texts.len() as u32,
        note: None,
        hints: None,
        association: None,
        association_hint: None,
        association_key: None,
        homophone: None,
        shows_numbers: None,
        meaning_placement: None,
        column_length: None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn shown(settings: EmojiSettings) -> Vec<(String, Option<String>)> {
        emoji_placement(settings)
            .entries
            .into_iter()
            .map(|entry| (entry.text, entry.detail))
            .collect()
    }

    const DEFAULT: EmojiSettings = EmojiSettings {
        whole: true,
        position: 4,
        count: 2,
        names: true,
        per_page: 9,
    };

    #[test]
    fn 絵文字の見本は設定の位置から設定の数だけ並べ名前を添える() {
        let entries = shown(DEFAULT);
        // 1〜6 番目(絵文字の後ろのふだんの候補 1 つまで)
        assert_eq!(entries.len(), 6);
        assert_eq!(entries[2].0, "ねこ");
        assert_eq!(entries[3], ("🐈".to_string(), Some("ネコ".to_string())));
        assert_eq!(
            entries[4],
            ("😺".to_string(), Some("にっこり笑う猫".to_string()))
        );
        assert_eq!(entries[5].0, "根子");
    }

    #[test]
    fn 文節を絵文字にしない設定では語を絵文字にした候補を並べる() {
        let entries = shown(EmojiSettings {
            whole: false,
            position: 2,
            count: 1,
            names: false,
            ..DEFAULT
        });
        assert_eq!(entries[0].0, "猫が");
        assert_eq!(entries[1], ("🐈が".to_string(), None));
        assert_eq!(entries[2].0, "ネコが");
    }

    #[test]
    fn 位置が1ページに収まらなければ見えている候補に絵文字は出ない() {
        let list = emoji_placement(EmojiSettings {
            position: 9,
            count: 5,
            ..DEFAULT
        });
        assert_eq!(list.total, 14);
        let texts: Vec<&str> = list
            .entries
            .iter()
            .map(|entry| entry.text.as_str())
            .collect();
        assert_eq!(texts[8], "🐈");
        assert!(!texts.contains(&"😺"));
    }
}
