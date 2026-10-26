#![forbid(unsafe_code)]

//! 連想の一覧(R-18)の見出しの行(macOS の AssociationHeadingDrawing)．一覧と分岐図で同じ形にする．
//! 左に「連想」と元の語と今の意味の説明，右に意味のまとまりの位置(「1 / 3」)を置く

use super::paint::Painter;
use super::Frame;
use crate::strings;
use crate::theme::Font;
use ipc::AssociationHeading;
use tokens::size::candidate;

fn prefix() -> String {
    format!("{}\u{3000}", strings::ASSOCIATION_PREFIX)
}

fn label(heading: &AssociationHeading) -> String {
    if heading.label.is_empty() {
        String::new()
    } else {
        format!("\u{3000}{}", heading.label)
    }
}

fn position(heading: &AssociationHeading) -> String {
    if heading.group_count > 1 {
        strings::association_position(heading.group, heading.group_count)
    } else {
        String::new()
    }
}

/// 行に要る幅(左右の余白を除く)
pub fn width(painter: &Painter, heading: &AssociationHeading) -> f32 {
    painter.width(&prefix(), Font::Label)
        + painter.width(&heading.headword, Font::Label)
        + painter.width(&label(heading), Font::Label)
        + painter.width(&position(heading), Font::Label)
        + candidate::PADDING_X * 3.0
}

pub fn draw(painter: &mut Painter, heading: &AssociationHeading, row: Frame) {
    let theme = painter.theme;
    let mut x = row.x + candidate::PADDING_X;
    let prefix = prefix();
    painter.text(&prefix, Font::Label, theme.text_muted, x, row);
    x += painter.width(&prefix, Font::Label);
    painter.text(&heading.headword, Font::Label, theme.text, x, row);
    x += painter.width(&heading.headword, Font::Label);
    let right = row.max_x() - candidate::PADDING_X;
    let position = position(heading);
    painter.text_right(&position, Font::Label, theme.text_muted, right, row);
    let label = label(heading);
    if !label.is_empty() {
        // 意味の説明は位置の手前までに収める
        let available = right - painter.width(&position, Font::Label) - candidate::PADDING_X - x;
        let shown = painter.truncated(&label, Font::Label, available);
        painter.text(&shown, Font::Label, theme.text_muted, x, row);
    }
}
