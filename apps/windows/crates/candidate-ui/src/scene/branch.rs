#![forbid(unsafe_code)]

//! 分岐図(ADR 0007．macOS の BranchView)．文を 1 本の幹として文節を横に並べ，注目している文節から枝を伸ばす．
//!
//! - 下の枝: 変換の候補．上の枝: 文字種
//! - 確信の低い文節は幹の文字に点線を引き，注目していなければ次の候補を 1 つだけ薄く添える
//! - 選び直した文節は実線を引く
//! - 文節を区切っているときは，注目している文節の幹を切れ目で分け，切れ目に小さな番号の丸を挟む．枝は出さない
//!
//! 角丸のテーマは曲線の枝と角丸の選択，platinum と desk は 1 ドットの直線の枝で描く

use super::paint::Painter;
use super::{Draw, Frame, Look, Measure, Point, Scene};
use crate::strings;
use crate::theme::Font;
use ipc::{BranchColumn, BranchMap, BranchSplit};
use tokens::size::{branch, candidate, glass};

/// テーマごとの寸法．角丸のテーマは余白と行を広く取る
struct Metrics {
    inset: f32,
    row_height: f32,
    trunk_gap: f32,
    branch_indent: f32,
    stem_x: f32,
    /// 候補の文字の前に置く番号の幅
    lead: f32,
    footer_height: f32,
    shadow: f32,
}

impl Metrics {
    fn new(look: &Look, measure: &dyn Measure) -> Self {
        let scale = look.font_size / candidate::FONT_SIZE;
        let shadow = if look.theme.has_drop_shadow() {
            candidate::SHADOW_OFFSET
        } else {
            0.0
        };
        if look.theme.is_rounded() {
            return Self {
                inset: glass::PADDING,
                row_height: (glass::ROW_HEIGHT * scale).round(),
                trunk_gap: glass::TRUNK_GAP,
                branch_indent: glass::BRANCH_INDENT,
                stem_x: glass::BRANCH_STEM_X,
                lead: glass::BADGE_SIZE + candidate::PADDING_X,
                footer_height: glass::FOOTER_HEIGHT,
                shadow,
            };
        }
        let label = measure.height(Font::Label).ceil() + candidate::SECTION_PADDING_Y * 2.0;
        Self {
            inset: candidate::FRAME_WIDTH + candidate::BEVEL_WIDTH + candidate::PADDING_X,
            row_height: (candidate::ROW_HEIGHT * scale).round(),
            trunk_gap: branch::TRUNK_GAP,
            branch_indent: branch::BRANCH_INDENT,
            stem_x: branch::BRANCH_STEM_X,
            lead: candidate::INDEX_WIDTH,
            footer_height: label.max(glass::KEYCAP_HEIGHT + candidate::SECTION_PADDING_Y * 2.0),
            shadow,
        }
    }
}

/// 幹・枝・足元の位置．描くときと大きさを求めるときで同じものを使う
struct Layout {
    trunk_x: Vec<f32>,
    trunk_width: Vec<f32>,
    lower_rows: usize,
    trunk_y: f32,
    branch_width: f32,
    width: f32,
    height: f32,
}

/// 区切る位置の番号を挟んだ文節の並び．runs は番号のあいだの字と左端，badges は番号と丸の中心(幹の文字の左端から)
struct SplitPieces {
    runs: Vec<(String, f32)>,
    badges: Vec<(String, f32)>,
    width: f32,
}

fn split_pieces(split: &BranchSplit, painter: &Painter) -> SplitPieces {
    let slot = branch::SPLIT_BADGE_SIZE + branch::SPLIT_BADGE_GAP * 2.0;
    let mut pieces = SplitPieces {
        runs: Vec::new(),
        badges: Vec::new(),
        width: 0.0,
    };
    let mut x = 0.0;
    for (index, text) in split.pieces.iter().enumerate() {
        if index > 0 {
            pieces.badges.push((index.to_string(), x + slot / 2.0));
            x += slot;
        }
        pieces.runs.push((text.clone(), x));
        x += painter.width(text, Font::Trunk);
    }
    pieces.width = x;
    pieces
}

fn focused(map: &BranchMap) -> Option<(usize, &BranchColumn)> {
    map.columns
        .iter()
        .enumerate()
        .find(|(_, column)| column.is_focused)
}

/// 足元の右に何番目の候補かを出すか．区切っているときは候補を出さないので出さない
fn position(map: &BranchMap) -> String {
    match focused(map) {
        Some((_, column)) if column.split.is_some() => String::new(),
        focused => {
            let count = focused.map_or(0, |(_, column)| column.alternatives.len() as u32);
            strings::position(map.position, map.position + count.max(1) - 1, map.total)
        }
    }
}

fn layout(map: &BranchMap, metrics: &Metrics, painter: &Painter) -> Layout {
    let padding = candidate::PADDING_X;
    let mut x = metrics.inset;
    let mut trunk_x = Vec::new();
    let mut trunk_width = Vec::new();
    for column in &map.columns {
        let text = column.split.as_ref().map_or_else(
            || painter.width(&column.text, Font::Trunk),
            |split| split_pieces(split, painter).width,
        );
        let width = text + padding * 2.0;
        trunk_x.push(x);
        trunk_width.push(width);
        x += width + metrics.trunk_gap;
    }
    let trunk_right = x - metrics.trunk_gap;
    let focused = focused(map);
    let column = focused.map(|(_, column)| column);
    let label_width = column
        .map(|column| column.alternatives.iter().chain(column.variants.iter()))
        .into_iter()
        .flatten()
        .map(|label| painter.width(label, Font::Candidate))
        .fold(0.0, f32::max);
    // 打ったまま・修正の添え書きの幅も足す
    let note_width = column
        .and_then(|column| {
            column
                .alternative_notes
                .iter()
                .flatten()
                .map(|note| painter.width(note, Font::Label))
                .reduce(f32::max)
        })
        .map_or(0.0, |width| width + padding * 2.0);
    let branch_width = metrics.stem_x
        + metrics.branch_indent
        + metrics.lead
        + label_width
        + note_width
        + padding * 2.0;
    let branch_right = focused.map_or(metrics.inset, |(index, _)| trunk_x[index]) + branch_width;
    let preview_rows = usize::from(map.columns.iter().any(|column| column.preview.is_some()));
    let upper_rows = column.map_or(0, |column| column.variants.len());
    let lower_rows = column
        .map_or(0, |column| column.alternatives.len())
        .max(preview_rows);
    let footer =
        footer_width(map, painter) + painter.width(&position(map), Font::Label) + padding * 3.0;
    // 使い分けや誤用の注釈と，IME からの知らせは，枝と足元のあいだに 1 行ずつ出す
    let note = [
        column.and_then(|column| column.usage_note.as_deref()),
        map.note.as_deref(),
    ]
    .into_iter()
    .flatten()
    .map(|text| painter.width(text, Font::Label) + padding * 2.0)
    .fold(0.0, f32::max);
    let width = candidate::MIN_WIDTH
        .max(trunk_right + metrics.inset)
        .max(branch_right + metrics.inset)
        .max(footer + metrics.inset * 2.0)
        .max(note + metrics.inset * 2.0);
    let trunk_y = metrics.inset + upper_rows as f32 * metrics.row_height;
    let extra_rows = usize::from(column.is_some_and(|column| column.usage_note.is_some()))
        + usize::from(map.note.is_some());
    let height = trunk_y
        + metrics.row_height * (1 + lower_rows) as f32
        + candidate::FRAME_WIDTH
        + metrics.footer_height * (1 + extra_rows) as f32
        + if painter.theme.is_rounded() {
            0.0
        } else {
            metrics.inset
        };
    Layout {
        trunk_x,
        trunk_width,
        lower_rows,
        trunk_y,
        branch_width,
        width: width.ceil(),
        height: height.ceil(),
    }
}

fn footer_width(map: &BranchMap, painter: &Painter) -> f32 {
    let source = focused(map)
        .and_then(|(_, column)| column.source_name.as_deref())
        .map_or(0.0, |name| {
            painter.width(&strings::dictionary_source(name), Font::Label) + candidate::PADDING_X
        });
    painter.hints_width(&map.hints) + source
}

pub fn branch_map(map: &BranchMap, look: &Look, measure: &dyn Measure) -> Scene {
    let metrics = Metrics::new(look, measure);
    let mut painter = Painter::new(look, measure);
    let theme = look.theme;
    let layout = layout(map, &metrics, &painter);
    let body = Frame::new(0.0, 0.0, layout.width, layout.height);
    painter.panel(body);
    let focused_index = focused(map).map(|(index, _)| index);
    // 注目している文節の枝が重なる範囲には，ほかの文節の添え書きを描かない
    let branch_range = focused_index.map(|index| {
        (
            layout.trunk_x[index],
            layout.trunk_x[index] + layout.branch_width,
        )
    });
    for (index, column) in map.columns.iter().enumerate() {
        let node = Frame::new(
            layout.trunk_x[index],
            layout.trunk_y,
            layout.trunk_width[index],
            metrics.row_height,
        );
        trunk_node(&mut painter, column, node);
        if !theme.is_rounded() {
            if let Some(next) = layout.trunk_x.get(index + 1) {
                // 角丸のテーマは文節の間を空けるだけにし，文として読めるようにする
                painter.rect(
                    Frame::new(
                        node.max_x(),
                        node.mid_y().round(),
                        next - node.max_x(),
                        branch::LINE_WIDTH,
                    ),
                    theme.line,
                );
            }
        }
        if column.is_focused {
            branches(
                &mut painter,
                &lower_rows(column, look.rest_opacity),
                node,
                layout.branch_width,
                true,
                &metrics,
            );
            branches(
                &mut painter,
                &upper_rows(column, look.rest_opacity),
                node,
                layout.branch_width,
                false,
                &metrics,
            );
        } else if let Some(preview) = column.preview.as_deref() {
            let overlaps =
                branch_range.is_some_and(|(from, to)| node.x <= to && node.max_x() >= from);
            if !overlaps {
                // 添える候補は次の文節の手前までに収め，はみ出す分は省く
                let limit = layout
                    .trunk_x
                    .get(index + 1)
                    .copied()
                    .unwrap_or(body.max_x() - metrics.inset);
                draw_preview(
                    &mut painter,
                    preview,
                    node,
                    limit,
                    look.rest_opacity,
                    &metrics,
                );
            }
        }
    }
    let mut footer_y = layout.trunk_y + metrics.row_height * (1 + layout.lower_rows) as f32;
    let content_width = body.width - metrics.inset * 2.0;
    if let Some(note) = focused(map).and_then(|(_, column)| column.usage_note.as_deref()) {
        let row = Frame::new(
            metrics.inset,
            footer_y,
            content_width,
            metrics.footer_height,
        );
        painter.text(note, Font::Label, theme.text_muted, row.x, row);
        footer_y += metrics.footer_height;
    }
    if let Some(note) = map.note.as_deref() {
        // 打ち間違いを直したことなど，IME が変えたことを知らせる
        let row = Frame::new(
            metrics.inset,
            footer_y,
            content_width,
            metrics.footer_height,
        );
        painter.text(note, Font::Label, theme.correction, row.x, row);
        footer_y += metrics.footer_height;
    }
    footer(&mut painter, map, footer_y, body.width, &metrics);
    painter.finish(
        layout.width + metrics.shadow,
        layout.height + metrics.shadow,
    )
}

fn trunk_node(painter: &mut Painter, column: &BranchColumn, node: Frame) {
    let theme = painter.theme;
    let rounded = theme.is_rounded();
    if column.is_focused {
        if rounded {
            painter.capsule(node.inset(0.0, glass::SELECTION_INSET_Y), theme.focus_tint);
        } else {
            painter.rect(node, theme.selection);
        }
    }
    let color = if !rounded && column.is_focused {
        theme.selection_text
    } else {
        theme.text
    };
    match &column.split {
        Some(split) => draw_split(painter, split, node, color),
        None => painter.text(
            &column.text,
            Font::Trunk,
            color,
            node.x + candidate::PADDING_X,
            node,
        ),
    }
    // 下線: 選び直した文節は実線，確信の低い文節は点線．線の種類でも区別し，色だけに頼らない
    let offset = if rounded {
        glass::UNDERLINE_OFFSET
    } else {
        branch::UNDERLINE_OFFSET
    };
    let y = node.max_y() - offset;
    let from = node.x + candidate::PADDING_X;
    let to = node.max_x() - candidate::PADDING_X;
    if column.is_decided {
        painter.underline(
            from,
            to,
            y,
            if rounded { theme.text_muted } else { color },
            false,
        );
    } else if column.is_uncertain {
        let dots = if !rounded && column.is_focused {
            theme.selection_text
        } else {
            theme.correction
        };
        painter.underline(from, to, y, dots, true);
    }
}

/// 区切っている文節の幹．切れ目(「問題｜が｜ある」)に，候補の番号と同じ形の小さな丸で番号を描く
fn draw_split(painter: &mut Painter, split: &BranchSplit, node: Frame, color: crate::theme::Color) {
    let pieces = split_pieces(split, painter);
    let left = node.x + candidate::PADDING_X;
    for (text, x) in &pieces.runs {
        painter.text(text, Font::Trunk, color, left + x, node);
    }
    // platinum と desk は注目している文節を選択の色で塗るので，丸も選んでいる行の上の描き方にする
    let selected = !painter.theme.is_rounded();
    for (label, center_x) in &pieces.badges {
        painter.badge(
            label,
            Point::new((left + center_x).round(), node.mid_y().round()),
            selected,
            1.0,
            branch::SPLIT_BADGE_SIZE,
            Font::SplitKey,
        );
    }
}

struct Row {
    text: String,
    badge: String,
    selected: bool,
    opacity: f32,
    /// 打ったまま・修正の添え書き
    note: Option<String>,
}

/// 下の枝(変換の候補)．第 1 候補はすぐに濃く出す
fn lower_rows(column: &BranchColumn, rest: f32) -> Vec<Row> {
    column
        .alternatives
        .iter()
        .enumerate()
        .map(|(index, text)| Row {
            text: text.clone(),
            badge: (index + 1).to_string(),
            selected: column.selected_alternative == Some(index as u32),
            opacity: if index == 0 { 1.0 } else { rest },
            note: column.alternative_notes.get(index).cloned().flatten(),
        })
        .collect()
}

/// 上の枝(文字種)．幹に近いものから上へ積む
fn upper_rows(column: &BranchColumn, rest: f32) -> Vec<Row> {
    column
        .variants
        .iter()
        .enumerate()
        .map(|(index, text)| Row {
            text: text.clone(),
            badge: strings::VARIANT_BADGE.to_string(),
            selected: column.selected_variant == Some(index as u32),
            opacity: rest,
            note: None,
        })
        .collect()
}

fn branches(
    painter: &mut Painter,
    rows: &[Row],
    node: Frame,
    width: f32,
    downward: bool,
    metrics: &Metrics,
) {
    if rows.is_empty() {
        return;
    }
    let stem_x = (node.x + metrics.stem_x).round();
    let row_frame = |index: usize| {
        let y = if downward {
            node.max_y() + index as f32 * metrics.row_height
        } else {
            node.y - (index + 1) as f32 * metrics.row_height
        };
        Frame::new(
            stem_x + metrics.branch_indent,
            y,
            width - metrics.stem_x - metrics.branch_indent,
            metrics.row_height,
        )
    };
    if painter.theme.curved_branches() {
        let stem_y = if downward {
            node.max_y() - glass::CURVE_START_OVERLAP
        } else {
            node.y + glass::CURVE_START_OVERLAP
        };
        curves(painter, rows, Point::new(stem_x, stem_y), &row_frame);
    } else {
        straight_lines(painter, rows, stem_x, node, downward, &row_frame);
    }
    for (index, row) in rows.iter().enumerate() {
        draw_row(painter, row, row_frame(index), metrics);
    }
}

/// 枝の曲線．幹の下(上)の start から，候補の行の左の end へ，角を丸めて曲がる
fn curve(start: Point, end: Point, color: crate::theme::Color, width: f32) -> Draw {
    Draw::Curve {
        from: start,
        control1: Point::new(start.x, end.y),
        control2: Point::new(start.x + (end.x - start.x) * glass::CURVE_BEND, end.y),
        to: end,
        color,
        width,
    }
}

/// 幹の下(上)の 1 点から，候補ごとに曲線を出す．選んでいる枝は最後に選択の色で重ねる
fn curves(painter: &mut Painter, rows: &[Row], start: Point, row_frame: &dyn Fn(usize) -> Frame) {
    let end = |index: usize| {
        let frame = row_frame(index);
        Point::new(frame.x - glass::CURVE_END_GAP, frame.mid_y())
    };
    let line = painter.theme.line;
    let selection = painter.theme.selection;
    for (index, row) in rows.iter().enumerate().filter(|(_, row)| !row.selected) {
        painter.draws.push(curve(
            start,
            end(index),
            line.faded(row.opacity),
            glass::LINE_WIDTH,
        ));
    }
    for (index, _) in rows.iter().enumerate().filter(|(_, row)| row.selected) {
        painter.draws.push(curve(
            start,
            end(index),
            selection,
            glass::LINE_WIDTH_SELECTED,
        ));
    }
}

/// platinum と desk: 縦の線を下ろし，候補ごとに横の線を出す
fn straight_lines(
    painter: &mut Painter,
    rows: &[Row],
    stem_x: f32,
    node: Frame,
    downward: bool,
    row_frame: &dyn Fn(usize) -> Frame,
) {
    let last = row_frame(rows.len() - 1);
    let (top, bottom) = if downward {
        (node.max_y(), last.mid_y())
    } else {
        (last.mid_y(), node.y)
    };
    let theme = painter.theme;
    painter.rect(
        Frame::new(stem_x, top, branch::LINE_WIDTH, bottom - top),
        theme.line,
    );
    for (index, row) in rows.iter().enumerate() {
        let frame = row_frame(index);
        let tick = if row.selected {
            branch::LINE_WIDTH_SELECTED
        } else {
            branch::LINE_WIDTH
        };
        painter.rect(
            Frame::new(
                stem_x,
                (frame.mid_y() - tick / 2.0).round(),
                frame.x - stem_x - candidate::FRAME_WIDTH,
                tick,
            ),
            if row.selected {
                theme.selection
            } else {
                theme.line
            },
        );
    }
}

fn draw_row(painter: &mut Painter, row: &Row, frame: Frame, metrics: &Metrics) {
    let theme = painter.theme;
    let padding = candidate::PADDING_X;
    let opacity = if row.selected { 1.0 } else { row.opacity };
    let text_color = if row.selected {
        theme.selection_text
    } else {
        theme.text
    }
    .faded(opacity);
    let muted_color = if row.selected {
        theme.selection_text
    } else {
        theme.text_muted
    }
    .faded(opacity);
    if theme.is_rounded() {
        if row.selected {
            painter.capsule(frame.inset(0.0, glass::SELECTION_INSET_Y), theme.selection);
        }
        let center = Point::new(
            frame.x + padding / 2.0 + glass::BADGE_SIZE / 2.0,
            frame.mid_y(),
        );
        painter.badge(
            &row.badge,
            center,
            row.selected,
            row.opacity,
            glass::BADGE_SIZE,
            Font::Key,
        );
    } else {
        if row.selected {
            painter.rect(frame, theme.selection);
        }
        painter.label(
            &row.badge,
            muted_color,
            Frame::new(
                frame.x + padding / 2.0,
                frame.y,
                metrics.lead - padding / 2.0,
                frame.height,
            ),
            Font::Key,
        );
    }
    painter.text(
        &row.text,
        Font::Candidate,
        text_color,
        frame.x + padding / 2.0 + metrics.lead,
        frame,
    );
    if let Some(note) = row.note.as_deref() {
        painter.text_right(
            note,
            Font::Label,
            muted_color,
            frame.max_x() - padding,
            frame,
        );
    }
}

/// 注目していない確信の低い文節の下に，次の候補を 1 つだけ薄く添える
fn draw_preview(
    painter: &mut Painter,
    text: &str,
    node: Frame,
    max_x: f32,
    rest: f32,
    metrics: &Metrics,
) {
    let theme = painter.theme;
    let stem_x = (node.x + metrics.stem_x).round();
    let row = Frame::new(stem_x, node.max_y(), node.width, metrics.row_height);
    let color = theme.text_muted.faded(rest);
    let text_x = if theme.is_rounded() {
        let end = Point::new(stem_x + metrics.branch_indent / 2.0, row.mid_y());
        let start = Point::new(stem_x, node.max_y() - glass::CURVE_START_OVERLAP);
        painter
            .draws
            .push(curve(start, end, theme.line.faded(rest), glass::LINE_WIDTH));
        end.x + candidate::PADDING_X / 2.0
    } else {
        painter.rect(
            Frame::new(stem_x, node.max_y(), branch::LINE_WIDTH, row.height / 2.0),
            color,
        );
        painter.rect(
            Frame::new(
                stem_x,
                row.mid_y().round(),
                metrics.branch_indent / 2.0,
                branch::LINE_WIDTH,
            ),
            color,
        );
        stem_x + metrics.branch_indent / 2.0 + candidate::PADDING_X / 2.0
    };
    let shown = painter.truncated(text, Font::Candidate, max_x - text_x);
    painter.text(&shown, Font::Candidate, color, text_x, row);
}

fn footer(painter: &mut Painter, map: &BranchMap, y: f32, width: f32, metrics: &Metrics) {
    let theme = painter.theme;
    let line_inset = if theme.is_rounded() {
        metrics.inset
    } else {
        metrics.inset - candidate::PADDING_X
    };
    painter.separator(y, line_inset, width - line_inset);
    let footer = Frame::new(
        metrics.inset,
        y + candidate::FRAME_WIDTH,
        width - metrics.inset * 2.0,
        metrics.footer_height,
    );
    painter.hints(&map.hints, footer.x, footer.mid_y());
    let position = position(map);
    let position_width = painter.width(&position, Font::Label);
    painter.text_right(
        &position,
        Font::Label,
        theme.text_muted,
        footer.max_x(),
        footer,
    );
    if let Some(source) = focused(map).and_then(|(_, column)| column.source_name.as_deref()) {
        // 選んでいる候補が取り込んだ辞書の語なら，その辞書の名前を位置の左に小さく出す(R-16)
        let label = strings::dictionary_source(source);
        let right = footer.max_x() - position_width - candidate::PADDING_X;
        painter.text_right(&label, Font::Label, theme.correction, right, footer);
    }
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use super::*;
    use crate::theme::{ResolvedTheme, SystemLook};
    use ipc::KeyHint;

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

    fn map() -> BranchMap {
        BranchMap {
            columns: vec![column("今日は", true), column("晴れ", false)],
            position: 1,
            total: 2,
            note: Some("直しました".into()),
            hints: vec![KeyHint {
                keys: "Space".into(),
                label: "候補".into(),
            }],
        }
    }

    #[test]
    fn 注目している文節から枝を出す() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let scene = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
            let texts = texts(&scene);
            assert!(texts.contains(&("京は".into(), theme.selection_text)));
            assert!(texts.contains(&("修正".into(), theme.selection_text)));
            assert!(texts.contains(&("きょうは".into(), theme.text)));
            assert!(texts.contains(&("直しました".into(), theme.correction)));
            assert!(texts.contains(&("1–2 / 2".into(), theme.text_muted)));
            // 注目している文節の枝と重なる文節には，次の候補を添えない
            assert!(!texts.iter().any(|(text, _)| text == "腫れ"));
        }
    }

    #[test]
    fn 角丸のテーマは曲線の枝で_選んだ枝を最後に選択の色で描く() {
        let theme = theme("automatic");
        let scene = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
        let curves: Vec<_> = scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Curve {
                    from,
                    to,
                    color,
                    width,
                    ..
                } => Some((*from, *to, *color, *width)),
                _ => None,
            })
            .collect();
        // 下の枝 2 本・上の枝 1 本
        assert_eq!(curves.len(), 3);
        let selected: Vec<_> = curves
            .iter()
            .filter(|curve| curve.2 == theme.selection)
            .collect();
        assert_eq!(selected.len(), 1);
        assert_eq!(selected[0].3, glass::LINE_WIDTH_SELECTED);
        // 枝は幹の下の 1 点から出て，行の左の手前で終わる
        let node_bottom = glass::PADDING + glass::ROW_HEIGHT * 2.0;
        assert_eq!(selected[0].0.y, node_bottom - glass::CURVE_START_OVERLAP);
        assert_eq!(
            selected[0].1.x,
            (glass::PADDING + glass::BRANCH_STEM_X).round() + glass::BRANCH_INDENT
                - glass::CURVE_END_GAP
        );
        // 確信の低い文節の点線は丸い点
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::Line { dot_pitch: Some(pitch), color, .. } if *pitch == glass::DOT_PITCH && *color == theme.correction)));
    }

    #[test]
    fn platinum_は直線の枝と文節をつなぐ線() {
        let theme = theme("platinum");
        let scene = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
        assert_eq!(count(&scene, |draw| matches!(draw, Draw::Curve { .. })), 0);
        // 選んだ枝の横の線は 2 ドットで選択の色
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::Rect { frame, color } if frame.height == branch::LINE_WIDTH_SELECTED && *color == theme.selection)));
    }

    #[test]
    fn カスタムテーマの直線の枝() {
        let mut theme = theme("nordic");
        theme.straight_branches = true;
        let scene = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
        assert_eq!(count(&scene, |draw| matches!(draw, Draw::Curve { .. })), 0);
    }

    #[test]
    fn 区切っているときは切れ目に番号の丸を挟み_位置を出さない() {
        for name in ["washi", "platinum"] {
            let theme = theme(name);
            let mut focused = column("問題がある", true);
            focused.alternatives.clear();
            focused.variants.clear();
            focused.selected_alternative = None;
            focused.split = Some(BranchSplit {
                pieces: vec!["問題".into(), "が".into(), "ある".into()],
            });
            let split = BranchMap {
                columns: vec![focused],
                position: 1,
                total: 4,
                note: None,
                hints: vec![],
            };
            let scene = branch_map(&split, &Look::new(&theme, 15.0), &Fixed);
            let texts = texts(&scene);
            for piece in ["問題", "が", "ある", "1", "2"] {
                assert!(
                    texts.iter().any(|(text, _)| text == piece),
                    "{name}: {piece}"
                );
            }
            assert!(!texts.iter().any(|(text, _)| text.contains('/')));
            let badges: Vec<_> = scene
                .draws
                .iter()
                .filter_map(|draw| match draw {
                    Draw::Ellipse { frame, .. } => Some(*frame),
                    _ => None,
                })
                .collect();
            assert_eq!(badges.len(), 2);
            assert_eq!(badges[0].width, branch::SPLIT_BADGE_SIZE);
            // 「問題」(2 文字)の後ろに丸の枠の分を空けて「が」を置く
            let ga = text_frame(&scene, "が").map(|frame| frame.x);
            let mondai = text_frame(&scene, "問題").map(|frame| frame.x);
            assert_eq!(
                ga.zip(mondai).map(|(ga, mondai)| ga - mondai),
                Some(20.0 + branch::SPLIT_BADGE_SIZE + branch::SPLIT_BADGE_GAP * 2.0)
            );
        }
    }

    #[test]
    fn 足元の案内はキーキャップに入れる() {
        let theme = ResolvedTheme::resolve("automatic", None, &SystemLook::default());
        let mut hinted = map();
        hinted.hints = vec![KeyHint {
            keys: "Shift+←".into(),
            label: "今日".into(),
        }];
        let scene = branch_map(&hinted, &Look::new(&theme, 15.0), &Fixed);
        let icons = count(&scene, |draw| matches!(draw, Draw::Icon { .. }));
        // Shift と ← のアイコン，上の枝の ↑
        assert_eq!(icons, 3);
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::RoundRect { radius, .. } if *radius == glass::KEYCAP_RADIUS)));
    }

    #[test]
    fn 添える候補は次の文節の手前で省く() {
        let theme = theme("automatic");
        let mut long = map();
        long.columns = vec![
            column("今日は", false),
            BranchColumn {
                preview: None,
                ..column("いい天気", false)
            },
        ];
        long.columns[0].preview = Some("とてもとても長い候補".into());
        let scene = branch_map(&long, &Look::new(&theme, 15.0), &Fixed);
        let shown = texts(&scene)
            .into_iter()
            .find(|(text, _)| text.ends_with('…'));
        assert_eq!(shown.map(|(_, color)| color), Some(theme.text_muted));
        // 添える候補の枝は曲線(注目している文節が無いので，この 1 本だけ)
        assert_eq!(count(&scene, |draw| matches!(draw, Draw::Curve { .. })), 1);
    }
}
