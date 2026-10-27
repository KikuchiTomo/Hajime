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

fn clamp(value: usize) -> i32 {
    i32::try_from(value).unwrap_or(i32::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

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
