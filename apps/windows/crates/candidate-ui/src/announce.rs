#![forbid(unsafe_code)]

//! ナレーターに読み上げてもらう文(macOS の CandidatePanelController が VoiceOver に渡すものと同じ)．
//! 候補の一覧は選んでいる候補か文字種，分岐図は注目している文節，案内はその文

use ipc::{BranchMap, CandidateFocus, CandidateList, HomophoneNote};

/// 使い分けを 1 行の文にしたもの(macOS の HomophoneNote.text)．「撮る: 撮影する。例「写真を撮る」　ほかに 取る・採る」
fn homophone(note: &HomophoneNote) -> String {
    let example = note
        .example
        .as_deref()
        .map_or(String::new(), |text| format!("。例「{text}」"));
    format!(
        "{}: {}{example}　ほかに {}",
        note.word,
        note.meaning,
        note.others.join("・")
    )
}

/// 選んでいるものの文に，使い分けがあれば続ける
fn with_homophone(text: String, note: Option<&HomophoneNote>) -> String {
    match note {
        Some(note) => format!("{text}、{}", homophone(note)),
        None => text,
    }
}

pub fn candidates(list: &CandidateList) -> Option<String> {
    match list.focus {
        CandidateFocus::Candidate => list
            .selected_entry
            .and_then(|index| list.entries.get(index as usize))
            .map(|entry| with_homophone(entry.text.clone(), list.homophone.as_ref())),
        CandidateFocus::Variants => list
            .selected_variant
            .and_then(|index| list.variants.get(index as usize))
            .map(|variant| variant.label.clone()),
    }
}

pub fn branch_map(map: &BranchMap) -> Option<String> {
    map.columns
        .iter()
        .find(|column| column.is_focused)
        .map(|column| with_homophone(column.text.clone(), column.homophone.as_ref()))
}

/// 同じ文を続けて読ませない．出したものを覚えておき，窓を消したら忘れる
#[derive(Debug, Default)]
pub struct Announcer {
    last: Option<String>,
}

impl Announcer {
    /// 読み上げる文．前と同じなら None
    pub fn next(&mut self, text: Option<String>) -> Option<String> {
        let text = text.filter(|text| !text.is_empty())?;
        if self.last.as_ref() == Some(&text) {
            return None;
        }
        self.last = Some(text.clone());
        Some(text)
    }

    pub fn reset(&mut self) {
        self.last = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ipc::{BranchColumn, CandidateEntry, CandidateVariant};

    fn list(focus: CandidateFocus) -> CandidateList {
        CandidateList {
            association: None,
            association_hint: None,
            homophone: None,
            variants: vec![CandidateVariant {
                label: "カタカナ".into(),
                is_available: true,
            }],
            selected_variant: Some(0),
            entries: vec![
                CandidateEntry {
                    text: "変換".into(),
                    annotation: None,
                    corrected_start: None,
                    corrected_length: None,
                },
                CandidateEntry {
                    text: "返還".into(),
                    annotation: None,
                    corrected_start: None,
                    corrected_length: None,
                },
            ],
            selected_entry: Some(1),
            focus,
            position: 2,
            total: 2,
            note: None,
        }
    }

    #[test]
    fn 選んでいる候補か文字種を読む() {
        assert_eq!(
            candidates(&list(CandidateFocus::Candidate)).as_deref(),
            Some("返還")
        );
        assert_eq!(
            candidates(&list(CandidateFocus::Variants)).as_deref(),
            Some("カタカナ")
        );
    }

    #[test]
    fn 使い分けがあれば候補に続けて読む() {
        let mut list = list(CandidateFocus::Candidate);
        list.homophone = Some(HomophoneNote {
            word: "返還".into(),
            meaning: "元の持ち主に返す".into(),
            example: Some("領土を返還する".into()),
            others: vec!["変換".into(), "偏官".into()],
        });
        assert_eq!(
            candidates(&list).as_deref(),
            Some("返還、返還: 元の持ち主に返す。例「領土を返還する」　ほかに 変換・偏官")
        );
    }

    #[test]
    fn 分岐図は注目している文節を読む() {
        let column = |text: &str, focused: bool| BranchColumn {
            text: text.into(),
            alternatives: vec![],
            selected_alternative: None,
            variants: vec![],
            selected_variant: None,
            is_focused: focused,
            is_uncertain: false,
            is_decided: false,
            is_corrected: None,
            preview: None,
            shorter: None,
            longer: None,
            usage_note: None,
            homophone: None,
            alternative_notes: vec![],
            source_name: None,
            split: None,
        };
        let map = BranchMap {
            association: None,
            association_hint: None,
            columns: vec![column("今日は", false), column("晴れ", true)],
            position: 1,
            total: 1,
            note: None,
            hints: vec![],
        };
        assert_eq!(branch_map(&map).as_deref(), Some("晴れ"));
    }

    #[test]
    fn 同じ文は続けて読まず_消したら忘れる() {
        let mut announcer = Announcer::default();
        assert_eq!(announcer.next(Some("返還".into())).as_deref(), Some("返還"));
        assert_eq!(announcer.next(Some("返還".into())), None);
        assert_eq!(announcer.next(Some("変換".into())).as_deref(), Some("変換"));
        announcer.reset();
        assert_eq!(announcer.next(Some("変換".into())).as_deref(), Some("変換"));
        assert_eq!(announcer.next(None), None);
    }
}
