#![forbid(unsafe_code)]

use crate::strings;
use ipc::{BranchColumn, BranchMap, CandidateFocus, CandidateList, InputMode};
use tokens::size::{branch, candidate, mode_indicator};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    Surface,
    BevelLight,
    BevelShadow,
    Frame,
    Text,
    TextMuted,
    Selection,
    SelectionText,
    Correction,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Font {
    Candidate,
    Label,
    Mode,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Frame {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl Frame {
    pub fn new(x: f32, y: f32, width: f32, height: f32) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    pub fn max_x(&self) -> f32 {
        self.x + self.width
    }

    pub fn max_y(&self) -> f32 {
        self.y + self.height
    }

    pub fn mid_y(&self) -> f32 {
        self.y + self.height / 2.0
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Draw {
    Fill {
        frame: Frame,
        role: Role,
    },
    Text {
        frame: Frame,
        text: String,
        font: Font,
        role: Role,
        opacity: f32,
    },
    Dots {
        frame: Frame,
        role: Role,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Scene {
    pub width: f32,
    pub height: f32,
    pub draws: Vec<Draw>,
}

pub trait Measure {
    fn width(&self, text: &str, font: Font) -> f32;
    fn height(&self, font: Font) -> f32;
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Metrics {
    pub font_size: f32,
    pub row_height: f32,
    pub section_height: f32,
    pub inset: f32,
}

impl Metrics {
    pub fn new(font_size: f32, measure: &dyn Measure) -> Self {
        let font_size = font_size.clamp(candidate::FONT_SIZE_MIN, candidate::FONT_SIZE_MAX);
        Self {
            font_size,
            row_height: (candidate::ROW_HEIGHT * font_size / candidate::FONT_SIZE).round(),
            section_height: measure.height(Font::Label).ceil() + candidate::SECTION_PADDING_Y * 2.0,
            inset: candidate::FRAME_WIDTH + candidate::BEVEL_WIDTH,
        }
    }
}

struct Builder {
    draws: Vec<Draw>,
}

impl Builder {
    fn new() -> Self {
        Self { draws: Vec::new() }
    }

    fn fill(&mut self, frame: Frame, role: Role) {
        self.draws.push(Draw::Fill { frame, role });
    }

    fn text(&mut self, frame: Frame, text: &str, font: Font, role: Role, opacity: f32) {
        if text.is_empty() {
            return;
        }
        self.draws.push(Draw::Text {
            frame,
            text: text.to_string(),
            font,
            role,
            opacity,
        });
    }

    fn panel(&mut self, width: f32, height: f32) {
        let line = candidate::FRAME_WIDTH;
        let bevel = candidate::BEVEL_WIDTH;
        self.fill(Frame::new(0.0, 0.0, width, height), Role::Frame);
        let inner = Frame::new(line, line, width - line * 2.0, height - line * 2.0);
        self.fill(inner, Role::Surface);
        self.fill(
            Frame::new(inner.x, inner.y, inner.width, bevel),
            Role::BevelLight,
        );
        self.fill(
            Frame::new(inner.x, inner.y, bevel, inner.height),
            Role::BevelLight,
        );
        self.fill(
            Frame::new(inner.x, inner.max_y() - bevel, inner.width, bevel),
            Role::BevelShadow,
        );
        self.fill(
            Frame::new(inner.max_x() - bevel, inner.y, bevel, inner.height),
            Role::BevelShadow,
        );
    }

    fn separator(&mut self, y: f32, from: f32, to: f32) {
        self.fill(
            Frame::new(from, y, to - from, candidate::FRAME_WIDTH),
            Role::Frame,
        );
    }

    fn finish(self, width: f32, height: f32) -> Scene {
        Scene {
            width,
            height,
            draws: self.draws,
        }
    }
}

pub fn candidate_list(list: &CandidateList, metrics: &Metrics, measure: &dyn Measure) -> Scene {
    let padding = candidate::PADDING_X;
    let lead = candidate::INDEX_WIDTH;
    let entry_width = list
        .entries
        .iter()
        .map(|entry| {
            measure.width(&entry.text, Font::Candidate)
                + entry
                    .annotation
                    .as_deref()
                    .map_or(0.0, |note| measure.width(note, Font::Label) + padding)
        })
        .fold(0.0, f32::max);
    let variants_width: f32 = list
        .variants
        .iter()
        .map(|variant| {
            measure.width(&variant.label, Font::Label) + candidate::VARIANT_PADDING_X * 2.0
        })
        .sum();
    let position = footer_position(list);
    let footer_width = list
        .note
        .as_deref()
        .map_or(0.0, |note| measure.width(note, Font::Label))
        + measure.width(&position, Font::Label)
        + padding * 3.0;
    let content_width = candidate::MIN_WIDTH
        .max(lead + entry_width + padding * 2.0)
        .max(variants_width + padding * 2.0)
        .max(footer_width);
    let mut content_height = list.entries.len() as f32 * metrics.row_height
        + metrics.section_height
        + candidate::FRAME_WIDTH;
    if !list.variants.is_empty() {
        content_height += metrics.section_height + candidate::FRAME_WIDTH;
    }
    let width = (content_width + metrics.inset * 2.0).ceil();
    let height = (content_height + metrics.inset * 2.0).ceil();

    let mut builder = Builder::new();
    builder.panel(width, height);
    let left = metrics.inset;
    let right = width - metrics.inset;
    let mut y = metrics.inset;
    if !list.variants.is_empty() {
        let mut x = left + padding / 2.0;
        for (index, variant) in list.variants.iter().enumerate() {
            let selected = list.focus == CandidateFocus::Variants
                && list.selected_variant == Some(index as u32);
            let cell_width =
                measure.width(&variant.label, Font::Label) + candidate::VARIANT_PADDING_X * 2.0;
            let cell = Frame::new(x, y + 1.0, cell_width, metrics.section_height - 2.0);
            if selected {
                builder.fill(cell, Role::Selection);
            }
            let (role, opacity) = match (selected, variant.is_available) {
                (true, _) => (Role::SelectionText, 1.0),
                (false, true) => (Role::TextMuted, 1.0),
                (false, false) => (Role::TextMuted, 0.4),
            };
            builder.text(
                Frame::new(
                    cell.x + candidate::VARIANT_PADDING_X,
                    cell.y,
                    cell_width,
                    cell.height,
                ),
                &variant.label,
                Font::Label,
                role,
                opacity,
            );
            x += cell_width;
        }
        y += metrics.section_height;
        builder.separator(y, left, right);
        y += candidate::FRAME_WIDTH;
    }
    for (index, entry) in list.entries.iter().enumerate() {
        let row = Frame::new(left, y, right - left, metrics.row_height);
        let selected =
            list.focus == CandidateFocus::Candidate && list.selected_entry == Some(index as u32);
        if selected {
            builder.fill(row, Role::Selection);
        }
        let (text_role, muted_role) = if selected {
            (Role::SelectionText, Role::SelectionText)
        } else {
            (Role::Text, Role::TextMuted)
        };
        builder.text(
            Frame::new(row.x + padding, row.y, lead, row.height),
            &(index + 1).to_string(),
            Font::Label,
            muted_role,
            1.0,
        );
        builder.text(
            Frame::new(
                row.x + padding + lead,
                row.y,
                row.width - padding - lead,
                row.height,
            ),
            &entry.text,
            Font::Candidate,
            text_role,
            1.0,
        );
        if let Some(annotation) = entry.annotation.as_deref() {
            let annotation_width = measure.width(annotation, Font::Label);
            builder.text(
                Frame::new(
                    row.max_x() - padding - annotation_width,
                    row.y,
                    annotation_width,
                    row.height,
                ),
                annotation,
                Font::Label,
                muted_role,
                1.0,
            );
        }
        y += metrics.row_height;
    }
    builder.separator(y, left, right);
    y += candidate::FRAME_WIDTH;
    let footer = Frame::new(
        left + padding,
        y,
        right - left - padding * 2.0,
        metrics.section_height,
    );
    builder.text(footer, &position, Font::Label, Role::TextMuted, 1.0);
    if let Some(note) = list.note.as_deref() {
        let note_width = measure.width(note, Font::Label);
        builder.text(
            Frame::new(
                footer.max_x() - note_width,
                footer.y,
                note_width,
                footer.height,
            ),
            note,
            Font::Label,
            Role::Correction,
            1.0,
        );
    }
    builder.finish(width, height)
}

fn footer_position(list: &CandidateList) -> String {
    match list.focus {
        CandidateFocus::Variants => strings::position(
            list.selected_variant.map_or(1, |index| index + 1),
            list.selected_variant.map_or(1, |index| index + 1),
            list.variants.len() as u32,
        ),
        CandidateFocus::Candidate => strings::position(list.position, list.position, list.total),
    }
}

struct BranchLayout {
    trunk_x: Vec<f32>,
    trunk_width: Vec<f32>,
    trunk_y: f32,
    lower_rows: usize,
    branch_width: f32,
    width: f32,
    height: f32,
}

fn branch_layout(map: &BranchMap, metrics: &Metrics, measure: &dyn Measure) -> BranchLayout {
    let padding = candidate::PADDING_X;
    let inset = metrics.inset + padding;
    let mut x = inset;
    let mut trunk_x = Vec::new();
    let mut trunk_width = Vec::new();
    for column in &map.columns {
        let width = measure.width(&column.text, Font::Candidate) + padding * 2.0;
        trunk_x.push(x);
        trunk_width.push(width);
        x += width + branch::TRUNK_GAP;
    }
    let trunk_right = x - branch::TRUNK_GAP;
    let focused = map.columns.iter().position(|column| column.is_focused);
    let column = focused.and_then(|index| map.columns.get(index));
    let labels = column
        .map(|column| column.alternatives.iter().chain(column.variants.iter()))
        .into_iter()
        .flatten();
    let label_width = labels
        .map(|label| measure.width(label, Font::Candidate))
        .fold(0.0, f32::max);
    let note_width = column
        .map(|column| {
            column
                .alternative_notes
                .iter()
                .flatten()
                .map(|note| measure.width(note, Font::Label) + padding * 2.0)
                .fold(0.0, f32::max)
        })
        .unwrap_or(0.0);
    let branch_width = branch::BRANCH_STEM_X
        + branch::BRANCH_INDENT
        + candidate::INDEX_WIDTH
        + label_width
        + note_width
        + padding * 2.0;
    let branch_right = focused
        .and_then(|index| trunk_x.get(index).copied())
        .unwrap_or(inset)
        + branch_width;
    let preview_rows = usize::from(map.columns.iter().any(|column| column.preview.is_some()));
    let upper_rows = column.map_or(0, |column| column.variants.len());
    let lower_rows = column
        .map_or(0, |column| column.alternatives.len())
        .max(preview_rows);
    let footer = hints_width(map, measure)
        + measure.width(&branch_position(map), Font::Label)
        + padding * 3.0;
    let note = [
        column.and_then(|column| column.usage_note.as_deref()),
        map.note.as_deref(),
    ]
    .into_iter()
    .flatten()
    .map(|text| measure.width(text, Font::Label) + padding * 2.0)
    .fold(0.0, f32::max);
    let width = candidate::MIN_WIDTH
        .max(trunk_right + inset)
        .max(branch_right + inset)
        .max(footer + inset * 2.0)
        .max(note + inset * 2.0);
    let trunk_y = inset + upper_rows as f32 * metrics.row_height;
    let extra_rows = usize::from(column.is_some_and(|column| column.usage_note.is_some()))
        + usize::from(map.note.is_some());
    let height = trunk_y
        + metrics.row_height * (1 + lower_rows) as f32
        + candidate::FRAME_WIDTH
        + metrics.section_height * (1 + extra_rows) as f32
        + inset;
    BranchLayout {
        trunk_x,
        trunk_width,
        trunk_y,
        lower_rows,
        branch_width,
        width: width.ceil(),
        height: height.ceil(),
    }
}

fn hints_width(map: &BranchMap, measure: &dyn Measure) -> f32 {
    map.hints
        .iter()
        .map(|hint| {
            measure.width(&hint.keys, Font::Label)
                + measure.width(&hint.label, Font::Label)
                + candidate::PADDING_X * 1.5
        })
        .sum()
}

fn branch_position(map: &BranchMap) -> String {
    let count = map
        .columns
        .iter()
        .find(|column| column.is_focused)
        .map_or(0, |column| column.alternatives.len() as u32);
    strings::position(map.position, map.position + count.max(1) - 1, map.total)
}

pub fn branch_map(map: &BranchMap, metrics: &Metrics, measure: &dyn Measure) -> Scene {
    let layout = branch_layout(map, metrics, measure);
    let mut builder = Builder::new();
    builder.panel(layout.width, layout.height);
    let padding = candidate::PADDING_X;
    let inset = metrics.inset + padding;
    let focused = map.columns.iter().position(|column| column.is_focused);
    let branch_range = focused
        .and_then(|index| layout.trunk_x.get(index))
        .map(|x| (*x, *x + layout.branch_width));
    for (index, column) in map.columns.iter().enumerate() {
        let node = Frame::new(
            layout.trunk_x[index],
            layout.trunk_y,
            layout.trunk_width[index],
            metrics.row_height,
        );
        trunk_node(&mut builder, column, node, padding);
        if let Some(next) = layout.trunk_x.get(index + 1) {
            builder.fill(
                Frame::new(
                    node.max_x(),
                    node.mid_y().round(),
                    next - node.max_x(),
                    branch::LINE_WIDTH,
                ),
                Role::Frame,
            );
        }
        if column.is_focused {
            branches(
                &mut builder,
                &lower_rows(column),
                node,
                layout.branch_width,
                true,
                metrics,
                measure,
            );
            branches(
                &mut builder,
                &upper_rows(column),
                node,
                layout.branch_width,
                false,
                metrics,
                measure,
            );
        } else if let Some(preview) = column.preview.as_deref() {
            let overlaps =
                branch_range.is_some_and(|(from, to)| node.x < to && node.max_x() > from);
            if !overlaps {
                let stem = (node.x + branch::BRANCH_STEM_X).round();
                builder.fill(
                    Frame::new(
                        stem,
                        node.max_y(),
                        branch::LINE_WIDTH,
                        metrics.row_height / 2.0,
                    ),
                    Role::TextMuted,
                );
                let row = Frame::new(stem, node.max_y(), node.width, metrics.row_height);
                builder.fill(
                    Frame::new(
                        stem,
                        row.mid_y().round(),
                        branch::BRANCH_INDENT / 2.0,
                        branch::LINE_WIDTH,
                    ),
                    Role::TextMuted,
                );
                let text_x = stem + branch::BRANCH_INDENT / 2.0 + padding / 2.0;
                let limit = layout
                    .trunk_x
                    .get(index + 1)
                    .copied()
                    .unwrap_or(layout.width - inset);
                builder.text(
                    Frame::new(text_x, row.y, (limit - text_x).max(0.0), row.height),
                    preview,
                    Font::Candidate,
                    Role::TextMuted,
                    1.0,
                );
            }
        }
    }
    let mut footer_y = layout.trunk_y + metrics.row_height * (1 + layout.lower_rows) as f32;
    let content_width = layout.width - inset * 2.0;
    if let Some(note) = focused.and_then(|index| map.columns[index].usage_note.as_deref()) {
        builder.text(
            Frame::new(inset, footer_y, content_width, metrics.section_height),
            note,
            Font::Label,
            Role::TextMuted,
            1.0,
        );
        footer_y += metrics.section_height;
    }
    if let Some(note) = map.note.as_deref() {
        builder.text(
            Frame::new(inset, footer_y, content_width, metrics.section_height),
            note,
            Font::Label,
            Role::Correction,
            1.0,
        );
        footer_y += metrics.section_height;
    }
    builder.separator(footer_y, metrics.inset, layout.width - metrics.inset);
    let footer = Frame::new(
        inset,
        footer_y + candidate::FRAME_WIDTH,
        content_width,
        metrics.section_height,
    );
    let mut x = footer.x;
    for hint in &map.hints {
        let keys_width = measure.width(&hint.keys, Font::Label);
        builder.text(
            Frame::new(x, footer.y, keys_width, footer.height),
            &hint.keys,
            Font::Label,
            Role::Text,
            1.0,
        );
        x += keys_width + padding / 2.0;
        let label_width = measure.width(&hint.label, Font::Label);
        builder.text(
            Frame::new(x, footer.y, label_width, footer.height),
            &hint.label,
            Font::Label,
            Role::TextMuted,
            1.0,
        );
        x += label_width + padding;
    }
    let position = branch_position(map);
    let position_width = measure.width(&position, Font::Label);
    builder.text(
        Frame::new(
            footer.max_x() - position_width,
            footer.y,
            position_width,
            footer.height,
        ),
        &position,
        Font::Label,
        Role::TextMuted,
        1.0,
    );
    if let Some(source) = focused.and_then(|index| map.columns[index].source_name.as_deref()) {
        let label = strings::dictionary_source(source);
        let label_width = measure.width(&label, Font::Label);
        builder.text(
            Frame::new(
                footer.max_x() - position_width - padding - label_width,
                footer.y,
                label_width,
                footer.height,
            ),
            &label,
            Font::Label,
            Role::Correction,
            1.0,
        );
    }
    builder.finish(layout.width, layout.height)
}

fn trunk_node(builder: &mut Builder, column: &BranchColumn, node: Frame, padding: f32) {
    if column.is_focused {
        builder.fill(node, Role::Selection);
    }
    let role = if column.is_focused {
        Role::SelectionText
    } else {
        Role::Text
    };
    builder.text(
        Frame::new(
            node.x + padding,
            node.y,
            node.width - padding * 2.0,
            node.height,
        ),
        &column.text,
        Font::Candidate,
        role,
        1.0,
    );
    let underline = Frame::new(
        node.x + padding,
        node.max_y() - branch::UNDERLINE_OFFSET,
        node.width - padding * 2.0,
        branch::LINE_WIDTH,
    );
    if column.is_decided {
        builder.fill(underline, role);
    } else if column.is_uncertain {
        let dots = if column.is_focused {
            Role::SelectionText
        } else {
            Role::Correction
        };
        builder.draws.push(Draw::Dots {
            frame: underline,
            role: dots,
        });
    }
}

struct Row {
    text: String,
    badge: String,
    selected: bool,
    note: Option<String>,
}

fn lower_rows(column: &BranchColumn) -> Vec<Row> {
    column
        .alternatives
        .iter()
        .enumerate()
        .map(|(index, text)| Row {
            text: text.clone(),
            badge: (index + 1).to_string(),
            selected: column.selected_alternative == Some(index as u32),
            note: column.alternative_notes.get(index).cloned().flatten(),
        })
        .collect()
}

fn upper_rows(column: &BranchColumn) -> Vec<Row> {
    column
        .variants
        .iter()
        .enumerate()
        .map(|(index, text)| Row {
            text: text.clone(),
            badge: strings::VARIANT_BADGE.to_string(),
            selected: column.selected_variant == Some(index as u32),
            note: None,
        })
        .collect()
}

fn branches(
    builder: &mut Builder,
    rows: &[Row],
    node: Frame,
    width: f32,
    downward: bool,
    metrics: &Metrics,
    measure: &dyn Measure,
) {
    if rows.is_empty() {
        return;
    }
    let padding = candidate::PADDING_X;
    let stem = (node.x + branch::BRANCH_STEM_X).round();
    let row_frame = |index: usize| {
        let y = if downward {
            node.max_y() + index as f32 * metrics.row_height
        } else {
            node.y - (index + 1) as f32 * metrics.row_height
        };
        Frame::new(
            stem + branch::BRANCH_INDENT,
            y,
            width - branch::BRANCH_STEM_X - branch::BRANCH_INDENT,
            metrics.row_height,
        )
    };
    let last = row_frame(rows.len() - 1);
    let (top, bottom) = if downward {
        (node.max_y(), last.mid_y())
    } else {
        (last.mid_y(), node.y)
    };
    builder.fill(
        Frame::new(stem, top, branch::LINE_WIDTH, bottom - top),
        Role::Frame,
    );
    for (index, row) in rows.iter().enumerate() {
        let frame = row_frame(index);
        let tick = if row.selected {
            branch::LINE_WIDTH_SELECTED
        } else {
            branch::LINE_WIDTH
        };
        builder.fill(
            Frame::new(
                stem,
                (frame.mid_y() - tick / 2.0).round(),
                frame.x - stem - candidate::FRAME_WIDTH,
                tick,
            ),
            if row.selected {
                Role::Selection
            } else {
                Role::Frame
            },
        );
        if row.selected {
            builder.fill(frame, Role::Selection);
        }
        let (text_role, muted_role) = if row.selected {
            (Role::SelectionText, Role::SelectionText)
        } else {
            (Role::Text, Role::TextMuted)
        };
        builder.text(
            Frame::new(
                frame.x + padding / 2.0,
                frame.y,
                candidate::INDEX_WIDTH - padding / 2.0,
                frame.height,
            ),
            &row.badge,
            Font::Label,
            muted_role,
            1.0,
        );
        builder.text(
            Frame::new(
                frame.x + padding / 2.0 + candidate::INDEX_WIDTH,
                frame.y,
                frame.width,
                frame.height,
            ),
            &row.text,
            Font::Candidate,
            text_role,
            1.0,
        );
        if let Some(note) = row.note.as_deref() {
            let note_width = measure.width(note, Font::Label);
            builder.text(
                Frame::new(
                    frame.max_x() - padding - note_width,
                    frame.y,
                    note_width,
                    frame.height,
                ),
                note,
                Font::Label,
                muted_role,
                1.0,
            );
        }
    }
}

pub fn note(text: &str, metrics: &Metrics, measure: &dyn Measure) -> Scene {
    let padding = candidate::PADDING_X;
    let width = (measure.width(text, Font::Label) + padding * 2.0 + metrics.inset * 2.0).ceil();
    let height = (metrics.section_height + metrics.inset * 2.0).ceil();
    let mut builder = Builder::new();
    builder.panel(width, height);
    builder.text(
        Frame::new(
            metrics.inset + padding,
            metrics.inset,
            width - padding * 2.0,
            metrics.section_height,
        ),
        text,
        Font::Label,
        Role::Text,
        1.0,
    );
    builder.finish(width, height)
}

pub fn mode(mode: InputMode, metrics: &Metrics, measure: &dyn Measure) -> Scene {
    let label = strings::mode(mode);
    let width =
        (measure.width(label, Font::Mode) + mode_indicator::PADDING_X * 2.0 + metrics.inset * 2.0)
            .ceil();
    let height =
        (measure.height(Font::Mode) + mode_indicator::PADDING_Y * 2.0 + metrics.inset * 2.0).ceil();
    let mut builder = Builder::new();
    builder.panel(width, height);
    builder.text(
        Frame::new(
            metrics.inset + mode_indicator::PADDING_X,
            metrics.inset,
            width - mode_indicator::PADDING_X * 2.0,
            height - metrics.inset * 2.0,
        ),
        label,
        Font::Mode,
        Role::Text,
        1.0,
    );
    builder.finish(width, height)
}

#[cfg(test)]
mod tests {
    use super::*;
    use ipc::{CandidateEntry, CandidateVariant, KeyHint};

    struct Fixed;

    impl Measure for Fixed {
        fn width(&self, text: &str, _font: Font) -> f32 {
            text.chars().count() as f32 * 10.0
        }

        fn height(&self, _font: Font) -> f32 {
            12.0
        }
    }

    fn list(selected: Option<u32>) -> CandidateList {
        CandidateList {
            variants: vec![CandidateVariant {
                label: "カタカナ".into(),
                is_available: true,
            }],
            selected_variant: None,
            entries: vec![
                CandidateEntry {
                    text: "変換".into(),
                    annotation: None,
                },
                CandidateEntry {
                    text: "へんかん".into(),
                    annotation: Some("入力のまま".into()),
                },
            ],
            selected_entry: selected,
            focus: CandidateFocus::Candidate,
            position: 2,
            total: 30,
            note: None,
        }
    }

    fn texts(scene: &Scene) -> Vec<(String, Role)> {
        scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Text { text, role, .. } => Some((text.clone(), *role)),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn 候補の一覧は選んだ行を選択の色にする() {
        let metrics = Metrics::new(15.0, &Fixed);
        let scene = candidate_list(&list(Some(1)), &metrics, &Fixed);
        let texts = texts(&scene);
        assert!(texts.contains(&("変換".into(), Role::Text)));
        assert!(texts.contains(&("へんかん".into(), Role::SelectionText)));
        assert!(texts.contains(&("入力のまま".into(), Role::SelectionText)));
        assert!(texts.contains(&("2 / 30".into(), Role::TextMuted)));
        assert!(scene.width >= candidate::MIN_WIDTH);
    }

    #[test]
    fn 候補の一覧の高さは行の数で決まる() {
        let metrics = Metrics::new(15.0, &Fixed);
        let two = candidate_list(&list(None), &metrics, &Fixed);
        let mut longer = list(None);
        longer.entries.push(CandidateEntry {
            text: "返還".into(),
            annotation: None,
        });
        let three = candidate_list(&longer, &metrics, &Fixed);
        assert_eq!(three.height - two.height, metrics.row_height);
    }

    fn column(text: &str, focused: bool) -> BranchColumn {
        BranchColumn {
            text: text.into(),
            alternatives: if focused {
                vec!["今日は".into(), "京は".into()]
            } else {
                vec![]
            },
            selected_alternative: focused.then_some(1),
            variants: if focused {
                vec!["きょうは".into()]
            } else {
                vec![]
            },
            selected_variant: None,
            is_focused: focused,
            is_uncertain: !focused,
            is_decided: false,
            preview: (!focused).then(|| "腫れ".to_string()),
            shorter: None,
            longer: None,
            usage_note: None,
            alternative_notes: vec![None, Some("修正".into())],
            source_name: None,
            split: None,
        }
    }

    #[test]
    fn 分岐図は注目している文節から枝を出す() {
        let map = BranchMap {
            columns: vec![column("今日は", true), column("晴れ", false)],
            position: 1,
            total: 2,
            note: Some("直しました".into()),
            hints: vec![KeyHint {
                keys: "Space".into(),
                label: "候補".into(),
            }],
        };
        let metrics = Metrics::new(15.0, &Fixed);
        let scene = branch_map(&map, &metrics, &Fixed);
        let texts = texts(&scene);
        assert!(texts.contains(&("京は".into(), Role::SelectionText)));
        assert!(texts.contains(&("修正".into(), Role::SelectionText)));
        assert!(texts.contains(&("きょうは".into(), Role::Text)));
        assert!(texts.contains(&("直しました".into(), Role::Correction)));
        assert!(texts.contains(&("1–2 / 2".into(), Role::TextMuted)));
        assert!(scene
            .draws
            .iter()
            .any(|draw| matches!(draw, Draw::Dots { .. })));
    }

    #[test]
    fn モードの札() {
        let metrics = Metrics::new(15.0, &Fixed);
        let scene = mode(InputMode::Japanese, &metrics, &Fixed);
        assert!(texts(&scene).contains(&("あ".into(), Role::Text)));
    }
}
