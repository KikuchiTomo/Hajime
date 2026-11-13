#![forbid(unsafe_code)]

//! 見本の分岐図．設定の画面の外観の見本と，見た目を見比べる PNG の書き出し(デバッグビルド)で同じものを使う．
//! 設定の画面の絵文字の見本(候補の一覧)もここで作る

use ipc::{
    BranchColumn, BranchHints, BranchMap, CandidateEntry, CandidateFocus, CandidateList, KeyHint,
};

/// 枝を出していない文節
pub fn column(text: &str) -> BranchColumn {
    BranchColumn {
        is_editing: None,
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
        jump_key: None,
        variant_keys: None,
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

/// 標準のキー設定の表で，文節へ移るキー(1〜8 番目)
const JUMP_KEYS: [&str; 8] = [
    "Alt+A", "Alt+S", "Alt+D", "Alt+F", "Alt+J", "Alt+K", "Alt+L", "Alt+;",
];
/// 標準のキー設定の表で，ひらがな・カタカナ・半角カタカナにするキー
const VARIANT_KEYS: [&str; 3] = ["F6", "F7", "F8"];

/// 分岐図の見本に，標準のキー設定の表の文節へ移るキー・文字種にするキー・置き場所ごとの案内を入れる(macOS の SamplePanels.withKeys)
pub fn with_keys(mut map: BranchMap) -> BranchMap {
    for (index, column) in map.columns.iter_mut().enumerate() {
        column.jump_key = JUMP_KEYS.get(index).map(|key| (*key).to_string());
        if column.is_focused {
            column.variant_keys = Some(
                (0..column.variants.len())
                    .map(|index| VARIANT_KEYS.get(index).map(|key| (*key).to_string()))
                    .collect(),
            );
        }
    }
    // 1 ページの数は，注目している文節の候補の数(候補が無ければ知らせない)
    map.page_size = map
        .columns
        .iter()
        .find(|column| column.is_focused)
        .map(|column| column.alternatives.len() as u32)
        .filter(|count| *count > 0);
    map.placed_hints = Some(BranchHints {
        boundary: vec![hint("Shift+←→", "区切り"), hint("Shift+↓", "分割")],
        variant: Some(hint("Shift+Space", "文字種")),
        candidates: vec![hint("Shift+BS", "再入力"), hint("Alt+↓", "表形式")],
        expand: map
            .association_key
            .as_ref()
            .map(|key| hint(key, "展開"))
            .or_else(|| (map.collapses_detail == Some(true)).then(|| hint("Alt+↑", "展開"))),
    });
    map
}

/// 3 つの文節のうち最後の文節で候補の枝を開いた分岐図
pub fn branch() -> BranchMap {
    with_keys(BranchMap {
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
        collapses_variants: None,
        collapses_detail: None,
        placed_hints: None,
        trunk_focused: None,
        page_size: None,
        hints_on_hold: None,
        group_start: None,
        continues_before: None,
        continues_after: None,
        keeps_width: None,
    })
}

/// 矢印で木をたどっていて，幹の上(文節)にいる分岐図(macOS の branch-trunk)
pub fn trunk_branch() -> BranchMap {
    BranchMap {
        trunk_focused: Some(true),
        ..branch()
    }
}

/// 表示項目を減らす設定の分岐図．文字種と先の枝を畳み，続きがある印の線を出す(macOS の fewerItemsLattice)
pub fn fewer_branch() -> BranchMap {
    let mut map = branch();
    for column in &mut map.columns {
        if column.is_focused {
            column.variants = Vec::new();
            column.variant_keys = None;
            column.homophone = None;
        }
    }
    map.association_hint = None;
    map.association_key = None;
    map.collapses_variants = Some(true);
    map.collapses_detail = Some(true);
    with_keys(map)
}

/// 窓の幅の上限を超える長い文の分岐図．focus の文節に注目する(macOS の longLatticeView)
pub fn long_branch(focus: usize) -> BranchMap {
    const SENTENCE: [&str; 14] = [
        "今日は",
        "朝から",
        "とても",
        "良い",
        "天気だったので",
        "近所の",
        "公園まで",
        "散歩に",
        "出かけて",
        "久しぶりに",
        "友達と",
        "ゆっくり",
        "話を",
        "しました",
    ];
    let columns = SENTENCE
        .iter()
        .enumerate()
        .map(|(index, text)| {
            if index == focus {
                BranchColumn {
                    alternatives: vec![
                        (*text).to_string(),
                        format!("{text}候補"),
                        format!("ひらがなの{text}"),
                    ],
                    selected_alternative: Some(0),
                    is_focused: true,
                    ..column(text)
                }
            } else {
                column(text)
            }
        })
        .collect();
    with_keys(BranchMap {
        association: None,
        association_hint: None,
        association_key: None,
        columns,
        position: 1,
        total: 3,
        note: None,
        hints: Vec::new(),
        meaning_placement: None,
        collapses_variants: None,
        collapses_detail: None,
        placed_hints: None,
        trunk_focused: None,
        page_size: None,
        hints_on_hold: None,
        group_start: None,
        continues_before: None,
        continues_after: None,
        keeps_width: None,
    })
}

/// 長い文を 8 文節ずつのまとまりに区切り，focus の文節が入っているまとまりだけを出した分岐図(macOS の branch-group)
pub fn group_branch(focus: usize) -> BranchMap {
    const PER_GROUP: usize = 8;
    let mut map = long_branch(focus);
    let total = map.columns.len();
    let start = focus / PER_GROUP * PER_GROUP;
    let end = (start + PER_GROUP).min(total);
    map.columns = map.columns[start..end].to_vec();
    map.group_start = (start > 0).then_some(start as u32);
    map.continues_before = (start > 0).then_some(true);
    map.continues_after = (end < total).then_some(true);
    with_keys(map)
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
        is_editing: None,
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
