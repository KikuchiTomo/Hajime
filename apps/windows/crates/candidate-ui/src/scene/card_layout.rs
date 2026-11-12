#![forbid(unsafe_code)]

//! 語の意味のカード(R-08)の配置．core の MeaningCardLayout(macOS)と同じ決め方．
//!
//! カードの中は「目印の列」と「文の列」の 2 列にする．
//! - 目印の列は幅が決まっていて，見出しの辞書のアイコン・意味の番号の札・同音語の耳のアイコンを，列の中で横の真ん中に置く
//! - 文の列は，見出しの語・意味・使い方の例の縦の線・「同音語」を，どれも同じ x(text_x)から書き出す．
//!   使い方の例の文は，そこから EXAMPLE_INDENT だけ下げる．折り返した行も，それぞれの書き出しの x にそろえる
//!
//! 縦は，文字の行の箱(書体の行の高さ．DirectWrite は文字をこの箱の縦の真ん中に描く)で積む．
//! - 目印と札は，その行の 1 行目の行の箱の縦の真ん中に置く(枠の真ん中ではなく文字に合わせる)
//! - 行の箱と行の箱のあいだ・カードの縁と行の箱のあいだを，トークンの間隔にする．内側の余白は上下左右とも PADDING
//! - 折り返した行は MEANING_PITCH(例は EXAMPLE_PITCH)ずつ下げる
//! - 例の縦の線は，例の 1 行目の行の箱の上の端から，最後の行の行の箱の下の端まで
//!
//! 座標はカードの左上が原点で，下が y の正

use super::{Frame, Measure};
use crate::theme::Font;
use tokens::size::{candidate, glass, meaning};

/// 横の列．x はカードの左の端から
#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) struct Columns {
    pub marker_x: f32,
    pub marker_width: f32,
    /// 文の列(見出しの語・意味・例の縦の線・「同音語」の書き出し)
    pub text_x: f32,
    pub text_width: f32,
    /// 例の文の書き出しと幅
    pub example_x: f32,
    pub example_width: f32,
}

impl Columns {
    pub fn new(width: f32) -> Self {
        let marker_x = meaning::PADDING;
        let text_x = marker_x + meaning::MARKER_WIDTH + meaning::MARKER_GAP;
        let text_width = (width - meaning::PADDING - text_x).max(0.0);
        Self {
            marker_x,
            marker_width: meaning::MARKER_WIDTH,
            text_x,
            text_width,
            example_x: text_x + meaning::EXAMPLE_INDENT,
            example_width: (text_width - meaning::EXAMPLE_INDENT).max(0.0),
        }
    }
}

/// 1 行の文字(中身を配置が持つもの)．frame は文字の行の箱
#[derive(Debug, Clone, PartialEq)]
pub(super) struct Text {
    pub text: String,
    pub font: Font,
    pub frame: Frame,
}

/// 札．frame の中に，文字(text)を行の箱 text_frame に書く
#[derive(Debug, Clone, PartialEq)]
pub(super) struct Chip {
    pub text: String,
    pub frame: Frame,
    pub text_frame: Frame,
}

/// 1 つの意味．meaning と example は折り返した行の行の箱
#[derive(Debug, Clone, PartialEq)]
pub(super) struct Sense {
    pub badge: Option<Frame>,
    pub number: Option<Text>,
    pub meaning: Vec<Frame>,
    /// 使い方の例の左の縦の線．例が無ければ None
    pub example_bar: Option<Frame>,
    pub example: Vec<Frame>,
}

/// 配置に渡す 1 つの意味．number は番号の札の文字(意味が 1 つなら None)，行の数は描く側が columns の幅で折り返したもの
pub(super) struct SenseLines {
    pub number: Option<String>,
    pub meaning_lines: usize,
    pub example_lines: usize,
}

pub(super) struct Content<'a> {
    pub word: &'a str,
    pub part_of_speech: Option<&'a str>,
    pub senses: Vec<SenseLines>,
    pub others: &'a [String],
    pub others_label: &'a str,
    pub more: &'a dyn Fn(usize) -> String,
}

/// 置いたカード
#[derive(Debug, Clone, PartialEq)]
pub(super) struct CardLayout {
    pub width: f32,
    pub height: f32,
    pub columns: Columns,
    /// 見出しの辞書のアイコンの枠(目印の列の一辺の正方形)
    pub book_icon: Frame,
    /// 見出しの語(入らなければ末尾を「…」で省いたもの)
    pub headword: Text,
    pub part_of_speech: Option<Chip>,
    pub senses: Vec<Sense>,
    /// 同音語の行の上の区切りの線．同音語が無ければ None
    pub separator: Option<Frame>,
    pub ear_icon: Option<Frame>,
    pub others_label: Option<Text>,
    pub tags: Vec<Chip>,
    /// 入らなかった札の数(「+n」)
    pub more: Option<Text>,
}

impl CardLayout {
    /// 見出しの行の縦の真ん中(カードの上の端から)．分岐図で候補からつなぐ線はここへ引く
    pub fn header_mid_y(&self) -> f32 {
        self.book_icon.mid_y()
    }

    /// 置いた部品の枠(重なりを確かめるのに使う)
    #[cfg(test)]
    pub fn parts(&self) -> Vec<Frame> {
        let mut parts = vec![self.book_icon, self.headword.frame];
        parts.extend(self.part_of_speech.as_ref().map(|chip| chip.frame));
        for sense in &self.senses {
            parts.extend(sense.badge);
            parts.extend(sense.meaning.iter().copied());
            parts.extend(sense.example.iter().copied());
            parts.extend(sense.example_bar);
        }
        parts.extend(self.separator);
        parts.extend(self.ear_icon);
        parts.extend(self.others_label.as_ref().map(|text| text.frame));
        parts.extend(self.more.as_ref().map(|text| text.frame));
        parts.extend(self.tags.iter().map(|chip| chip.frame));
        parts
    }
}

/// 文字の行の箱の高さ(整数に切り上げる)
fn line_height(measure: &dyn Measure, font: Font) -> f32 {
    measure.height(font).ceil()
}

/// 行の箱の縦の真ん中が mid_y の 1 行．上の端は整数の位置にする(字をぼかさない)
fn centered(measure: &dyn Measure, font: Font, x: f32, width: f32, mid_y: f32) -> Frame {
    let height = line_height(measure, font);
    Frame::new(x, (mid_y - height / 2.0).round(), width, height)
}

/// 1 行目の行の箱の上の端が top の段落．続く行は pitch ずつ下げる(行の箱より狭ければ行の箱の高さ)
fn paragraph(
    measure: &dyn Measure,
    font: Font,
    lines: usize,
    x: f32,
    width: f32,
    top: f32,
    pitch: f32,
) -> Vec<Frame> {
    let height = line_height(measure, font);
    let step = pitch.max(height);
    (0..lines)
        .map(|index| Frame::new(x, top.round() + step * index as f32, width, height))
        .collect()
}

/// 目印の枠: 目印の列の中で，mid_y を縦の真ん中にした正方形
fn marker(x: f32, mid_y: f32) -> Frame {
    let size = meaning::MARKER_WIDTH;
    Frame::new(x, (mid_y - size / 2.0).round(), size, size)
}

/// frame の中の札の文字．文字の行の箱を札の縦の真ん中に置く
fn chip(measure: &dyn Measure, text: &str, font: Font, frame: Frame, padding_x: f32) -> Chip {
    Chip {
        text: text.to_string(),
        text_frame: centered(
            measure,
            font,
            frame.x + padding_x,
            measure.width(text, font),
            frame.mid_y(),
        ),
        frame,
    }
}

/// 末尾を「…」にして width に収めたもの
fn truncated(measure: &dyn Measure, text: &str, font: Font, width: f32) -> String {
    if measure.width(text, font) <= width {
        return text.to_string();
    }
    let mut characters: Vec<char> = text.chars().collect();
    while !characters.is_empty() {
        characters.pop();
        let candidate: String = characters.iter().chain(std::iter::once(&'…')).collect();
        if measure.width(&candidate, font) <= width {
            return candidate;
        }
    }
    "…".to_string()
}

/// 幅 width(内側の余白を含む)のカードの配置
pub(super) fn place(content: &Content, width: f32, measure: &dyn Measure) -> CardLayout {
    let columns = Columns::new(width);
    let right = width - meaning::PADDING;

    // 見出し: 辞書のアイコン・語・品詞の札を，語の行の箱の縦の真ん中にそろえる
    let mut y = meaning::PADDING;
    let header_height = line_height(measure, Font::MeaningHeadword)
        .max(meaning::PART_OF_SPEECH_HEIGHT)
        .max(meaning::MARKER_WIDTH);
    let pos_width = content.part_of_speech.map(|name| {
        (measure.width(name, Font::MeaningTag) + meaning::PART_OF_SPEECH_PADDING_X * 2.0).ceil()
    });
    let word_width =
        (right - columns.text_x - pos_width.map_or(0.0, |pos| pos + meaning::PART_OF_SPEECH_GAP))
            .max(0.0);
    let word = truncated(measure, content.word, Font::MeaningHeadword, word_width);
    let word_frame = centered(
        measure,
        Font::MeaningHeadword,
        columns.text_x,
        measure.width(&word, Font::MeaningHeadword),
        y + header_height / 2.0,
    );
    let book_icon = marker(columns.marker_x, word_frame.mid_y());
    let part_of_speech = content.part_of_speech.zip(pos_width).map(|(name, pos)| {
        let frame = Frame::new(
            (word_frame.max_x() + meaning::PART_OF_SPEECH_GAP).round(),
            (word_frame.mid_y() - meaning::PART_OF_SPEECH_HEIGHT / 2.0).round(),
            pos,
            meaning::PART_OF_SPEECH_HEIGHT,
        );
        chip(
            measure,
            name,
            Font::MeaningTag,
            frame,
            meaning::PART_OF_SPEECH_PADDING_X,
        )
    });
    y += header_height + meaning::HEADER_GAP;

    // 意味: 番号の札は 1 行目の行の箱の縦の真ん中．例は縦の線を文の列の x に引き，文を下げる
    let mut senses = Vec::new();
    for (index, sense) in content.senses.iter().enumerate() {
        if index > 0 {
            y += meaning::SENSE_GAP;
        }
        let lines = paragraph(
            measure,
            Font::MeaningBody,
            sense.meaning_lines,
            columns.text_x,
            columns.text_width,
            y,
            meaning::MEANING_PITCH,
        );
        let (badge, number) = match (&sense.number, lines.first()) {
            (Some(label), Some(first)) => {
                let badge = marker(columns.marker_x, first.mid_y());
                let label_width = measure.width(label, Font::MeaningNumber);
                let number = Text {
                    text: label.clone(),
                    font: Font::MeaningNumber,
                    frame: centered(
                        measure,
                        Font::MeaningNumber,
                        badge.mid_x() - label_width / 2.0,
                        label_width,
                        badge.mid_y(),
                    ),
                };
                (Some(badge), Some(number))
            }
            _ => (None, None),
        };
        if let Some(last) = lines.last() {
            y = last.max_y();
        }
        let mut example = Vec::new();
        let mut example_bar = None;
        if sense.example_lines > 0 {
            y += meaning::EXAMPLE_GAP;
            example = paragraph(
                measure,
                Font::MeaningExample,
                sense.example_lines,
                columns.example_x,
                columns.example_width,
                y,
                meaning::EXAMPLE_PITCH,
            );
            if let (Some(first), Some(last)) = (example.first(), example.last()) {
                example_bar = Some(Frame::new(
                    columns.text_x,
                    first.y,
                    meaning::EXAMPLE_BAR_WIDTH,
                    last.max_y() - first.y,
                ));
                y = last.max_y();
            }
        }
        senses.push(Sense {
            badge,
            number,
            meaning: lines,
            example_bar,
            example,
        });
    }

    // 同音語: 区切りの線の下に，耳のアイコン・「同音語」・札．入らない札は「+n」にまとめる
    let mut layout = CardLayout {
        width,
        height: 0.0,
        columns,
        book_icon,
        headword: Text {
            text: word,
            font: Font::MeaningHeadword,
            frame: word_frame,
        },
        part_of_speech,
        senses,
        separator: None,
        ear_icon: None,
        others_label: None,
        tags: Vec::new(),
        more: None,
    };
    if !content.others.is_empty() {
        y += meaning::OTHERS_GAP;
        let separator = Frame::new(
            meaning::PADDING,
            y.round(),
            width - meaning::PADDING * 2.0,
            candidate::FRAME_WIDTH,
        );
        y = separator.max_y() + meaning::OTHERS_GAP;
        let row_height = line_height(measure, Font::Label)
            .max(glass::TAG_HEIGHT)
            .max(meaning::MARKER_WIDTH);
        let label = centered(
            measure,
            Font::Label,
            columns.text_x,
            measure.width(content.others_label, Font::Label),
            y + row_height / 2.0,
        );
        layout.separator = Some(separator);
        layout.ear_icon = Some(marker(columns.marker_x, label.mid_y()));
        layout.others_label = Some(Text {
            text: content.others_label.to_string(),
            font: Font::Label,
            frame: label,
        });
        let mut x = label.max_x() + meaning::TAG_GAP;
        for (index, word) in content.others.iter().enumerate() {
            let tag_width = (measure.width(word, Font::Label) + glass::TAG_PADDING_X * 2.0).ceil();
            let rest = content.others.len() - index - 1;
            let reserve = if rest > 0 {
                meaning::TAG_GAP + measure.width(&(content.more)(rest), Font::Label)
            } else {
                0.0
            };
            if x + tag_width + reserve > right {
                let text = (content.more)(content.others.len() - index);
                let frame = centered(
                    measure,
                    Font::Label,
                    x,
                    measure.width(&text, Font::Label),
                    label.mid_y(),
                );
                layout.more = Some(Text {
                    text,
                    font: Font::Label,
                    frame,
                });
                break;
            }
            let frame = Frame::new(
                x.round(),
                (label.mid_y() - glass::TAG_HEIGHT / 2.0).round(),
                tag_width,
                glass::TAG_HEIGHT,
            );
            layout.tags.push(chip(
                measure,
                word,
                Font::Label,
                frame,
                glass::TAG_PADDING_X,
            ));
            x = frame.max_x() + meaning::TAG_GAP;
        }
        y += row_height;
    }
    layout.height = (y + meaning::PADDING).ceil();
    layout
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 書体ごとに行の高さを変える(行の箱で揃えないと揃わない)．幅は字 1 つを書体の大きさとして測る
    struct Varied;

    impl Varied {
        fn size(font: Font) -> f32 {
            match font {
                Font::MeaningHeadword => 15.0,
                Font::MeaningBody => 13.0,
                Font::MeaningExample | Font::MeaningExampleStrong => 12.0,
                Font::MeaningTag | Font::MeaningNumber => 10.5,
                _ => 11.5,
            }
        }
    }

    impl Measure for Varied {
        fn width(&self, text: &str, font: Font) -> f32 {
            text.chars()
                .map(|c| if c.is_ascii() { 0.6 } else { 1.0 } * Self::size(font))
                .sum()
        }

        fn height(&self, font: Font) -> f32 {
            Self::size(font) * 1.33
        }
    }

    fn more(count: usize) -> String {
        format!("+{count}")
    }

    fn sense(number: Option<&str>, meaning_lines: usize, example_lines: usize) -> SenseLines {
        SenseLines {
            number: number.map(str::to_string),
            meaning_lines,
            example_lines,
        }
    }

    /// 見本: 名前・意味ごとの行の数・同音語・品詞
    type Sample = (
        &'static str,
        Vec<SenseLines>,
        Vec<String>,
        Option<&'static str>,
    );

    fn samples() -> Vec<Sample> {
        let others: Vec<String> = ["取る", "採る", "執る", "捕る"]
            .iter()
            .map(|word| word.to_string())
            .collect();
        vec![
            (
                "意味が 2 つで同音語あり",
                vec![sense(Some("1"), 1, 1), sense(Some("2"), 2, 1)],
                others.clone(),
                Some("動詞"),
            ),
            (
                "意味が 1 つで例なし",
                vec![sense(None, 1, 0)],
                Vec::new(),
                Some("動詞"),
            ),
            (
                "意味が 3 つで折り返しあり",
                vec![
                    sense(Some("1"), 3, 2),
                    sense(Some("2"), 1, 0),
                    sense(Some("3"), 2, 1),
                ],
                others.clone(),
                Some("名詞"),
            ),
            (
                "品詞なし",
                vec![sense(Some("1"), 1, 1), sense(Some("2"), 1, 1)],
                others,
                None,
            ),
            (
                "同音語が入りきらない",
                vec![sense(None, 2, 1)],
                (1..=12).map(|index| format!("語{index}")).collect(),
                Some("動詞"),
            ),
        ]
    }

    fn layouts() -> Vec<(&'static str, CardLayout)> {
        samples()
            .into_iter()
            .map(|(name, senses, others, pos)| {
                let content = Content {
                    word: "撮る",
                    part_of_speech: pos,
                    senses,
                    others: &others,
                    others_label: "同音語",
                    more: &more,
                };
                (name, place(&content, meaning::LIST_WIDTH, &Varied))
            })
            .collect()
    }

    fn intersects(a: &Frame, b: &Frame) -> bool {
        a.x < b.max_x() && b.x < a.max_x() && a.y < b.max_y() && b.y < a.max_y()
    }

    #[test]
    fn 文の列のxは1か所() {
        for (name, layout) in layouts() {
            let x = layout.columns.text_x;
            assert_eq!(layout.headword.frame.x, x, "{name}");
            for sense in &layout.senses {
                assert!(sense.meaning.iter().all(|line| line.x == x), "{name}");
                if let Some(bar) = sense.example_bar {
                    assert_eq!(bar.x, x, "{name}");
                }
                assert!(
                    sense
                        .example
                        .iter()
                        .all(|line| line.x == x + meaning::EXAMPLE_INDENT),
                    "{name}"
                );
            }
            if let Some(label) = &layout.others_label {
                assert_eq!(label.frame.x, x, "{name}");
            }
            assert_eq!(
                x,
                meaning::PADDING + meaning::MARKER_WIDTH + meaning::MARKER_GAP
            );
        }
    }

    #[test]
    fn 目印は同じ列で_1行目の行の箱の縦の真ん中() {
        for (name, layout) in layouts() {
            let mut markers = vec![layout.book_icon];
            markers.extend(layout.senses.iter().filter_map(|sense| sense.badge));
            markers.extend(layout.ear_icon);
            assert!(
                markers
                    .iter()
                    .all(|marker| marker.x == meaning::PADDING
                        && marker.width == meaning::MARKER_WIDTH),
                "{name}"
            );
            assert!(
                (layout.book_icon.mid_y() - layout.headword.frame.mid_y()).abs() <= 0.5,
                "{name}"
            );
            for sense in &layout.senses {
                if let (Some(badge), Some(first), Some(number)) =
                    (sense.badge, sense.meaning.first(), &sense.number)
                {
                    assert!((badge.mid_y() - first.mid_y()).abs() <= 0.5, "{name}");
                    assert!(
                        (number.frame.mid_y() - badge.mid_y()).abs() <= 0.5,
                        "{name}"
                    );
                    assert!(
                        (number.frame.mid_x() - badge.mid_x()).abs() <= 0.5,
                        "{name}"
                    );
                }
            }
            if let (Some(ear), Some(label)) = (layout.ear_icon, &layout.others_label) {
                assert!((ear.mid_y() - label.frame.mid_y()).abs() <= 0.5, "{name}");
            }
        }
    }

    #[test]
    fn 札は行の箱の縦の真ん中() {
        for (name, layout) in layouts() {
            if let Some(chip) = &layout.part_of_speech {
                assert!(
                    (chip.frame.mid_y() - layout.headword.frame.mid_y()).abs() <= 0.5,
                    "{name}"
                );
                assert!((chip.text_frame.mid_y() - chip.frame.mid_y()).abs() <= 0.5);
            }
            if let Some(label) = &layout.others_label {
                for tag in &layout.tags {
                    assert!(
                        (tag.frame.mid_y() - label.frame.mid_y()).abs() <= 0.5,
                        "{name}"
                    );
                }
            }
        }
    }

    #[test]
    fn 例の縦の線は例の行の箱の上から下まで() {
        for (name, layout) in layouts() {
            for sense in layout
                .senses
                .iter()
                .filter(|sense| !sense.example.is_empty())
            {
                let bar = sense.example_bar.expect("縦の線");
                let first = sense.example[0];
                let last = sense.example[sense.example.len() - 1];
                assert_eq!(bar.y, first.y, "{name}");
                assert_eq!(bar.max_y(), last.max_y(), "{name}");
                assert!(bar.max_x() < first.x, "{name}");
            }
        }
    }

    #[test]
    fn 内側の余白は上下左右で同じ() {
        for (name, layout) in layouts() {
            let parts = layout.parts();
            let top = parts.iter().map(|part| part.y).fold(f32::MAX, f32::min);
            let left = parts.iter().map(|part| part.x).fold(f32::MAX, f32::min);
            let bottom = layout.height - parts.iter().map(|part| part.max_y()).fold(0.0, f32::max);
            assert!((top - meaning::PADDING).abs() <= 0.5, "{name}: {top}");
            assert_eq!(left, meaning::PADDING, "{name}");
            assert!(
                (meaning::PADDING - 0.5..meaning::PADDING + 1.0).contains(&bottom),
                "{name}: {bottom}"
            );
            if let Some(separator) = layout.separator {
                assert_eq!(separator.max_x(), layout.width - meaning::PADDING, "{name}");
            }
            for tag in &layout.tags {
                assert!(
                    tag.frame.max_x() <= layout.width - meaning::PADDING,
                    "{name}"
                );
            }
        }
    }

    #[test]
    fn 区切りの線の上と下は同じ間隔() {
        for (name, layout) in layouts() {
            let Some(separator) = layout.separator else {
                continue;
            };
            let last = layout.senses.last().expect("意味");
            let above = separator.y
                - last
                    .example
                    .last()
                    .or(last.meaning.last())
                    .expect("行")
                    .max_y();
            let row_top = layout
                .tags
                .iter()
                .map(|tag| tag.frame.y)
                .chain(layout.ear_icon.map(|ear| ear.y))
                .chain(layout.others_label.as_ref().map(|label| label.frame.y))
                .fold(f32::MAX, f32::min);
            let below = row_top - separator.max_y();
            assert!(
                (above - meaning::OTHERS_GAP).abs() <= 0.5,
                "{name}: {above}"
            );
            assert!(
                (below - meaning::OTHERS_GAP).abs() <= 1.0,
                "{name}: {below}"
            );
        }
    }

    #[test]
    fn 部品が重ならない() {
        for (name, layout) in layouts() {
            let parts = layout.parts();
            for (index, part) in parts.iter().enumerate() {
                for other in &parts[index + 1..] {
                    assert!(!intersects(part, other), "{name}: {part:?} と {other:?}");
                }
            }
        }
    }

    #[test]
    fn 入らない同音語の札は数にまとめて余白の内側に収める() {
        let (_, layout) = layouts()
            .into_iter()
            .find(|(name, _)| *name == "同音語が入りきらない")
            .expect("見本");
        let more = layout.more.expect("+n");
        assert_eq!(more.text, format!("+{}", 12 - layout.tags.len()));
        assert!(more.frame.max_x() <= layout.width - meaning::PADDING);
    }

    #[test]
    fn 長い見出しの語は品詞の札の手前で省く() {
        let long = "長".repeat(40);
        let senses = vec![sense(None, 1, 0)];
        let content = Content {
            word: &long,
            part_of_speech: Some("動詞"),
            senses,
            others: &[],
            others_label: "同音語",
            more: &more,
        };
        let layout = place(&content, meaning::LIST_WIDTH, &Varied);
        assert!(layout.headword.text.ends_with('…'));
        let chip = layout.part_of_speech.expect("品詞");
        assert!(chip.frame.max_x() <= layout.width - meaning::PADDING);
    }
}
