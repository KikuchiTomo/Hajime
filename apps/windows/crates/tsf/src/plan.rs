#![forbid(unsafe_code)]

use ipc::{TextSegment, TextStyle};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StyledRange {
    pub start: i32,
    pub length: i32,
    pub style: TextStyle,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompositionPlan {
    pub text: Vec<u16>,
    pub ranges: Vec<StyledRange>,
    /// 入力位置(先頭からの UTF-16 の単位の数)．None なら末尾
    pub caret: Option<i32>,
}

impl CompositionPlan {
    pub fn new(segments: &[TextSegment]) -> Self {
        let mut text = Vec::new();
        let mut ranges = Vec::new();
        for segment in segments {
            let start = text.len();
            text.extend(segment.text.encode_utf16());
            let length = text.len() - start;
            if length > 0 {
                ranges.push(StyledRange {
                    start: clamp(start),
                    length: clamp(length),
                    style: segment.style,
                });
            }
        }
        Self {
            text,
            ranges,
            caret: None,
        }
    }

    /// 入力位置を置く．文字の長さを超えるときは末尾にする
    pub fn with_caret(mut self, caret: Option<u32>) -> Self {
        self.caret = caret
            .map(|caret| clamp(caret as usize))
            .filter(|caret| *caret < clamp(self.text.len()));
        self
    }

    pub fn is_empty(&self) -> bool {
        self.text.is_empty()
    }
}

/// 候補の窓をそろえる字(組み立て中の文字の頭からの UTF-16 の位置)を覚える．
/// エンジンは候補の一覧を出す返事にだけそろえる字を添え，wake の返事などで同じ組み立て中の文字を書き直すときは添えない．
/// 添えない返事で組み立て中の文字全体にそろえ直すと，候補の窓の基準(エンジンに送る入力位置)が字と全体のあいだを行き来し，
/// 候補の窓と語の意味の吹き出しが動き続ける．組み立て中の文字が同じあいだは，覚えた字にそろえ続ける
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PanelAnchor {
    last: Option<(Vec<u16>, u32)>,
}

impl PanelAnchor {
    /// 返事の書き換えのあとにそろえる字．written は書き換えた組み立て中の文字(書き換えなければ None)，
    /// anchor はエンジンが添えた字
    pub fn resolve(&mut self, written: Option<&[u16]>, anchor: Option<u32>) -> Option<u32> {
        match (written, anchor) {
            (Some(text), Some(anchor)) => {
                self.last = Some((text.to_vec(), anchor));
                Some(anchor)
            }
            (Some(text), None) => {
                let kept = self
                    .last
                    .as_ref()
                    .filter(|(last, _)| last.as_slice() == text)
                    .map(|(_, anchor)| *anchor);
                if kept.is_none() {
                    self.last = None;
                }
                kept
            }
            // 組み立て中の文字を書き換えない返事(モードを変えるだけなど)は，前の字のまま
            (None, anchor) => anchor.or_else(|| self.last.as_ref().map(|(_, anchor)| *anchor)),
        }
    }

    /// 組み立てを終えた(次の組み立てに前の字を持ち越さない)
    pub fn reset(&mut self) {
        self.last = None;
    }
}

fn clamp(value: usize) -> i32 {
    i32::try_from(value).unwrap_or(i32::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn utf16(text: &str) -> Vec<u16> {
        text.encode_utf16().collect()
    }

    #[test]
    fn そろえる字を添えない書き換えでも組み立て中の文字が同じあいだは前の字にそろえる() {
        let mut anchor = PanelAnchor::default();
        let text = utf16("写真を撮る");
        // キーの返事: 候補の一覧を出し，「撮る」の頭(3)にそろえる
        assert_eq!(anchor.resolve(Some(&text), Some(3)), Some(3));
        // wake の返事: 同じ文字を書き直すが，そろえる字を添えない
        assert_eq!(anchor.resolve(Some(&text), None), Some(3));
        // 書き換えない返事
        assert_eq!(anchor.resolve(None, None), Some(3));
        // 選び直して文字が変わった(「採る」)．エンジンが新しい字を添える
        let other = utf16("写真を採る");
        assert_eq!(anchor.resolve(Some(&other), Some(3)), Some(3));
    }

    #[test]
    fn 組み立て中の文字が変わり_そろえる字も無ければ全体にそろえる() {
        let mut anchor = PanelAnchor::default();
        assert_eq!(anchor.resolve(Some(&utf16("とる")), Some(0)), Some(0));
        // 打ち進めて文字が変わった(候補の一覧を閉じた)
        assert_eq!(anchor.resolve(Some(&utf16("とるな")), None), None);
        assert_eq!(anchor.resolve(None, None), None);
        // 組み立てを終えたら持ち越さない
        assert_eq!(anchor.resolve(Some(&utf16("とる")), Some(0)), Some(0));
        anchor.reset();
        assert_eq!(anchor.resolve(Some(&utf16("とる")), None), None);
    }

    fn segment(text: &str, style: TextStyle) -> TextSegment {
        TextSegment {
            text: text.into(),
            style,
        }
    }

    #[test]
    fn 区間を_utf16_で数える() {
        let plan = CompositionPlan::new(&[
            segment("𠮷野", TextStyle::Focused),
            segment("家", TextStyle::Converted),
        ]);
        assert_eq!(plan.text.len(), 4);
        assert_eq!(
            plan.ranges,
            vec![
                StyledRange {
                    start: 0,
                    length: 3,
                    style: TextStyle::Focused
                },
                StyledRange {
                    start: 3,
                    length: 1,
                    style: TextStyle::Converted
                },
            ]
        );
    }

    #[test]
    fn 空の区間は下線を付けない() {
        let plan = CompositionPlan::new(&[segment("", TextStyle::Reading)]);
        assert!(plan.is_empty());
        assert!(plan.ranges.is_empty());
    }

    #[test]
    fn 入力位置は文字の中だけに置き_外なら末尾にする() {
        let segments = [
            segment("今日は", TextStyle::Converted),
            segment("かな", TextStyle::Reading),
        ];
        assert_eq!(
            CompositionPlan::new(&segments).with_caret(Some(3)).caret,
            Some(3)
        );
        assert_eq!(
            CompositionPlan::new(&segments).with_caret(Some(5)).caret,
            None
        );
        assert_eq!(CompositionPlan::new(&segments).with_caret(None).caret, None);
    }
}
