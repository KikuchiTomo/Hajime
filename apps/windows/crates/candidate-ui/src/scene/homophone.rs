#![forbid(unsafe_code)]

//! 語の意味と同音異義語の使い分けの欄(R-08，macOS の HomophoneDrawing)．一覧と分岐図で同じ形にする．
//! 意味ごとに 1 行を使い，最初の行の頭に語(強く)を置いて，意味と使い方の例(控えめ)を語の後ろにそろえて並べる．
//! 意味が 2 つ以上なら番号を付ける．同じ読みのほかの語があれば，最後の行に「ほかに」とその札を並べる．
//! 欄の幅は USAGE_MAX_WIDTH までにし，入らない分は例，意味の順に省く(意味が長くても窓を広げすぎない)

use super::paint::{Painter, TagStyle};
use super::Frame;
use crate::strings;
use crate::theme::Font;
use ipc::HomophoneNote;
use tokens::size::glass;

/// 意味の行と，ほかの語があればその行の数
fn row_count(note: &HomophoneNote) -> usize {
    note.senses.len() + usize::from(!note.others.is_empty())
}

/// 欄の高さ(上下の余白を含む)
pub fn height(note: &HomophoneNote) -> f32 {
    glass::USAGE_ROW_HEIGHT * row_count(note) as f32 + glass::USAGE_PADDING_Y * 2.0
}

fn example(text: &str) -> String {
    format!("「{text}」")
}

/// 意味の番号と後ろの間の幅．意味が 1 つなら番号を付けない
fn number_width(painter: &Painter, note: &HomophoneNote, index: usize) -> f32 {
    if note.senses.len() > 1 {
        painter.width(&strings::sense_number(index + 1), Font::Label) + glass::NOTE_GAP
    } else {
        0.0
    }
}

/// 欄に要る幅(左右の余白を除く)．USAGE_MAX_WIDTH を超えない
pub fn width(painter: &Painter, note: &HomophoneNote) -> f32 {
    let lead = painter.width(&note.word, Font::Emphasis) + glass::NOTE_GAP;
    let senses = note
        .senses
        .iter()
        .enumerate()
        .map(|(index, sense)| {
            lead + number_width(painter, note, index)
                + painter.width(&sense.meaning, Font::Label)
                + sense.example.as_deref().map_or(0.0, |text| {
                    glass::NOTE_GAP + painter.width(&example(text), Font::Label)
                })
        })
        .fold(0.0, f32::max);
    let others = if note.others.is_empty() {
        0.0
    } else {
        painter.width(strings::HOMOPHONE_OTHERS, Font::Label)
            + note
                .others
                .iter()
                .map(|word| glass::USAGE_TAG_GAP + painter.tag_width(word))
                .sum::<f32>()
    };
    senses.max(others).min(glass::USAGE_MAX_WIDTH).ceil()
}

pub fn draw(painter: &mut Painter, note: &HomophoneNote, area: Frame) {
    let theme = painter.theme;
    let row = |index: usize| {
        Frame::new(
            area.x,
            area.y + glass::USAGE_PADDING_Y + glass::USAGE_ROW_HEIGHT * index as f32,
            area.width,
            glass::USAGE_ROW_HEIGHT,
        )
    };

    // 意味の行: 語の後ろに番号・意味・例．入らなければ例を省き，それでも入らなければ意味を「…」で切る
    painter.text(&note.word, Font::Emphasis, theme.text, area.x, row(0));
    let lead = area.x + painter.width(&note.word, Font::Emphasis) + glass::NOTE_GAP;
    for (index, sense) in note.senses.iter().enumerate() {
        let line = row(index);
        let mut x = lead;
        if note.senses.len() > 1 {
            let number = strings::sense_number(index + 1);
            painter.text(&number, Font::Label, theme.text_muted, x, line);
            x += painter.width(&number, Font::Label) + glass::NOTE_GAP;
        }
        let available = line.max_x() - x;
        let meaning_width = painter.width(&sense.meaning, Font::Label);
        let example = sense.example.as_deref().map(example);
        let example_fits = example.as_ref().is_some_and(|text| {
            meaning_width + glass::NOTE_GAP + painter.width(text, Font::Label) <= available
        });
        let meaning = painter.truncated(&sense.meaning, Font::Label, available);
        painter.text(&meaning, Font::Label, theme.text, x, line);
        x += painter.width(&meaning, Font::Label);
        if let Some(example) = example.filter(|_| example_fits) {
            painter.text(
                &example,
                Font::Label,
                theme.text_muted,
                x + glass::NOTE_GAP,
                line,
            );
        }
    }

    // ほかの語の行: ほかに＋札．入らない札は「+n」にまとめる
    if note.others.is_empty() {
        return;
    }
    let bottom = row(note.senses.len());
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
