#![forbid(unsafe_code)]

//! 見本の分岐図．設定の画面の外観の見本と，見た目を見比べる PNG の書き出し(デバッグビルド)で同じものを使う

use ipc::{BranchColumn, BranchMap, KeyHint};

fn column(text: &str) -> BranchColumn {
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
            hint("Alt+→", "誤りやすい文節"),
            hint("Shift+←→", "区切り調整"),
        ],
    }
}
