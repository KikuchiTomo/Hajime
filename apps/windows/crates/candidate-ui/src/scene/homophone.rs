#![forbid(unsafe_code)]

//! 同音異義語の使い分けの欄(R-08，macOS の HomophoneDrawing)．一覧と分岐図で同じ形にする．
//! 上の行に語(強く)と意味と使い方の例(控えめ)，下の行に「ほかに」と同じ読みのほかの語の札を並べる．
//! 欄の幅は USAGE_MAX_WIDTH までにし，入らない分は例，意味の順に省く(意味が長くても窓を広げすぎない)

use super::paint::{Painter, TagStyle};
use super::Frame;
use crate::strings;
use crate::theme::Font;
use ipc::HomophoneNote;
use tokens::size::glass;

/// 欄の高さ(上下の余白を含む)
pub fn height() -> f32 {
    glass::USAGE_ROW_HEIGHT * 2.0 + glass::USAGE_PADDING_Y * 2.0
}

fn example(text: &str) -> String {
    format!("「{text}」")
}

/// 欄に要る幅(左右の余白を除く)．USAGE_MAX_WIDTH を超えない
pub fn width(painter: &Painter, note: &HomophoneNote) -> f32 {
    let first = painter.width(&note.word, Font::Emphasis)
        + glass::NOTE_GAP
        + painter.width(&note.meaning, Font::Label)
        + note.example.as_deref().map_or(0.0, |text| {
            glass::NOTE_GAP + painter.width(&example(text), Font::Label)
        });
    let second = painter.width(strings::HOMOPHONE_OTHERS, Font::Label)
        + note
            .others
            .iter()
            .map(|word| glass::USAGE_TAG_GAP + painter.tag_width(word))
            .sum::<f32>();
    first.max(second).min(glass::USAGE_MAX_WIDTH).ceil()
}

pub fn draw(painter: &mut Painter, note: &HomophoneNote, area: Frame) {
    let theme = painter.theme;
    let top = Frame::new(
        area.x,
        area.y + glass::USAGE_PADDING_Y,
        area.width,
        glass::USAGE_ROW_HEIGHT,
    );
    let bottom = Frame::new(
        top.x,
        top.y + glass::USAGE_ROW_HEIGHT,
        top.width,
        top.height,
    );

    // 上の行: 語・意味・例．入らなければ例を省き，それでも入らなければ意味を「…」で切る
    painter.text(&note.word, Font::Emphasis, theme.text, top.x, top);
    let mut x = top.x + painter.width(&note.word, Font::Emphasis) + glass::NOTE_GAP;
    let available = top.max_x() - x;
    let meaning_width = painter.width(&note.meaning, Font::Label);
    let example = note.example.as_deref().map(example);
    let example_fits = example.as_ref().is_some_and(|text| {
        meaning_width + glass::NOTE_GAP + painter.width(text, Font::Label) <= available
    });
    let meaning = painter.truncated(&note.meaning, Font::Label, available);
    painter.text(&meaning, Font::Label, theme.text, x, top);
    x += painter.width(&meaning, Font::Label);
    if let Some(example) = example.filter(|_| example_fits) {
        painter.text(
            &example,
            Font::Label,
            theme.text_muted,
            x + glass::NOTE_GAP,
            top,
        );
    }

    // 下の行: ほかに＋札．入らない札は「+n」にまとめる
    painter.text(
        strings::HOMOPHONE_OTHERS,
        Font::Label,
        theme.text_muted,
        bottom.x,
        bottom,
    );
    let mut x = bottom.x + painter.width(strings::HOMOPHONE_OTHERS, Font::Label);
    for (index, word) in note.others.iter().enumerate() {
        let tag = painter.tag_width(word);
        let rest = note.others.len() - index - 1;
        let reserve = if rest > 0 {
            glass::USAGE_TAG_GAP + painter.width(&strings::more(rest), Font::Label)
        } else {
            0.0
        };
        if x + glass::USAGE_TAG_GAP + tag + reserve > bottom.max_x() {
            painter.text(
                &strings::more(note.others.len() - index),
                Font::Label,
                theme.text_muted,
                x + glass::USAGE_TAG_GAP,
                bottom,
            );
            break;
        }
        x += glass::USAGE_TAG_GAP + tag;
        painter.tag(word, x, bottom.mid_y(), false, TagStyle::Plain);
    }
}
