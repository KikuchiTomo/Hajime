#![forbid(unsafe_code)]

//! 分岐図(ADR 0007．macOS の BranchView)．文を 1 本の幹として文節を横に並べ，注目している文節から枝を伸ばす．
//!
//! - 下の枝: 変換の候補．上の枝: 文字種
//! - 確信の低い文節は幹の文字に点線を引き，注目していなければ次の候補を 1 つだけ薄く添える
//! - 選び直した文節は実線を引く
//! - 文節を区切っているときは，注目している文節の幹を切れ目で分け，切れ目に小さな番号の丸を挟む．枝は出さない
//! - 語の意味のカードは，候補の枝の先に置いて選んでいる候補から線でつなぐか，枝と足元のあいだに窓の幅いっぱいに出す
//!
//! 枝は幹の文節から 1 本の幹を伸ばし，候補ごとに同じ形の曲がり角と水平の線を出す(branch_lines)．
//! 曲線の枝のテーマは 4 分の 1 の円で，直線の枝のテーマは直角に曲がる．platinum と desk は 1 ドットの線で描く

use super::branch_lines::{BranchLines, Turn};
use super::meaning::{self, Slot};
use super::paint::{Painter, TagStyle};
use super::{Color, Draw, Figure, Frame, Look, Measure, Point, Scene, Segment};
use crate::strings;
use crate::theme::Font;
use ipc::{BranchColumn, BranchMap, BranchSplit, CommandKind, KeyHint, MeaningPlacement};
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
    line_width: f32,
    line_width_selected: f32,
    /// 幹の根元を文節の枠の端からずらす量(角丸のテーマは文節の地が上下に細いので，その端から伸ばす)
    root_inset: f32,
    /// 枝の水平の線の終わりから候補の行までの空き
    tip_gap: f32,
    /// 枝の曲がり角の半径．直線の枝は 0(直角)
    turn_radius: f32,
    /// 1 ドットあたりのデバイスのピクセル数
    pixel_scale: f32,
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
                line_width: glass::LINE_WIDTH,
                line_width_selected: glass::LINE_WIDTH_SELECTED,
                root_inset: glass::SELECTION_INSET_Y,
                tip_gap: glass::BRANCH_TIP_GAP,
                turn_radius: if look.theme.curved_branches() {
                    glass::BRANCH_TURN_RADIUS
                } else {
                    0.0
                },
                pixel_scale: look.pixel_scale,
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
            line_width: branch::LINE_WIDTH,
            line_width_selected: branch::LINE_WIDTH_SELECTED,
            root_inset: 0.0,
            tip_gap: candidate::FRAME_WIDTH,
            turn_radius: 0.0,
            pixel_scale: look.pixel_scale,
        }
    }
}

/// 幹・枝・足元の位置．描くときと大きさを求めるときで同じものを使う
struct Layout {
    trunk_x: Vec<f32>,
    trunk_width: Vec<f32>,
    trunk_y: f32,
    branch_width: f32,
    /// 下の枝の高さ(候補の枝と，候補の右に出すカードの高い方)
    lower_height: f32,
    /// 語の意味のカードと，その枠．カードを出さなければ None
    slot: Option<Slot>,
    card: Option<Frame>,
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

/// 注目している文節の位置と文節
pub(super) fn focused(map: &BranchMap) -> Option<(usize, &BranchColumn)> {
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

/// 候補の下に出すカードの上下の空き
fn below_margin() -> f32 {
    candidate::PADDING_X / 2.0
}

/// 注目している文節で出す語の意味のカード．区切っているあいだは出さない．
/// 候補の右は幅が決まっているので content_width を使わず，候補の下は content_width(窓の中身の幅)で折り返す
fn meaning_slot(
    map: &BranchMap,
    painter: &Painter,
    reserved: Option<f32>,
    content_width: Option<f32>,
) -> Option<Slot> {
    let (_, column) = focused(map)?;
    if column.split.is_some() {
        return None;
    }
    match meaning::placement(map.meaning_placement) {
        MeaningPlacement::Side => {
            let card = column.homophone.as_ref().map(|note| {
                meaning::branch_card(painter, note, column, glass::MEANING_BRANCH_WIDTH)
            });
            meaning::side_slot(card, glass::MEANING_BRANCH_WIDTH, reserved)
        }
        MeaningPlacement::Below => {
            let note = column.homophone.as_ref()?;
            let width =
                (content_width? - glass::MEANING_PADDING * 2.0).max(glass::MEANING_CARD_WIDTH);
            Some(meaning::below_slot(meaning::branch_card(
                painter, note, column, width,
            )))
        }
    }
}

fn layout(map: &BranchMap, metrics: &Metrics, painter: &Painter, reserved: Option<f32>) -> Layout {
    let padding = candidate::PADDING_X;
    let mut x = metrics.inset;
    let mut trunk_x = Vec::new();
    let mut trunk_width = Vec::new();
    for column in &map.columns {
        let text = column.split.as_ref().map_or_else(
            || match trunk_command(column) {
                Some((_, title)) => Painter::command_width() + painter.width(title, Font::Trunk),
                None => painter.width(&column.text, Font::Trunk),
            },
            |split| split_pieces(split, painter).width,
        );
        let width = text + padding * 2.0 + corrected_label_width(column, painter);
        trunk_x.push(x);
        trunk_width.push(width);
        x += width + metrics.trunk_gap;
    }
    let trunk_right = x - metrics.trunk_gap;
    let focused = focused(map);
    let column = focused.map(|(_, column)| column);
    // コマンドの候補は文字の前に種類のアイコンを置くので，その幅も足す
    let label_width = column
        .map(|column| {
            lower_rows(column, 1.0)
                .into_iter()
                .map(|row| {
                    painter.width(&row.text, Font::Candidate)
                        + row.command.map_or(0.0, |_| Painter::command_width())
                        + painter.detail_width(row.detail.as_deref())
                })
                .chain(
                    column
                        .variants
                        .iter()
                        .map(|label| painter.width(label, Font::Candidate)),
                )
                .collect::<Vec<_>>()
        })
        .into_iter()
        .flatten()
        .fold(0.0, f32::max);
    // 打ったまま・修正・コマンドの添え書きの幅も足す
    let note_width = column
        .and_then(|column| {
            column
                .alternative_notes
                .iter()
                .flatten()
                .map(|note| painter.tag_width(note))
                .reduce(f32::max)
        })
        .map_or(0.0, |width| width + padding * 2.0);
    let branch_width = metrics.stem_x
        + metrics.branch_indent
        + metrics.lead
        + label_width
        + note_width
        + padding * 2.0;
    // 候補の右に出すカードは，候補の枝の先に続けて置く(枝の一部として幅に数える)
    let side = meaning_slot(map, painter, reserved, None)
        .filter(|slot| slot.placement == MeaningPlacement::Side);
    let card_extent = side
        .as_ref()
        .map_or(0.0, |slot| glass::MEANING_GAP + slot.width);
    let branch_right =
        focused.map_or(metrics.inset, |(index, _)| trunk_x[index]) + branch_width + card_extent;
    let preview_rows = usize::from(map.columns.iter().any(|column| column.preview.is_some()));
    let upper_rows = column.map_or(0, |column| column.variants.len());
    let lower_rows = column
        .map_or(0, |column| column.alternatives.len())
        .max(preview_rows);
    let lower_height = (metrics.row_height * lower_rows as f32).max(
        side.as_ref()
            .map_or(0.0, |slot| slot.height + padding / 2.0),
    );
    let footer =
        footer_width(map, painter) + painter.width(&position(map), Font::Label) + padding * 3.0;
    // 使い分けや誤用の注釈と，IME からの知らせは，枝と足元のあいだに 1 行ずつ出す．候補の下のカードは窓の幅をカードの幅まで広げる
    let below = map.meaning_placement == Some(MeaningPlacement::Below)
        && column.is_some_and(|column| column.homophone.is_some() && column.split.is_none());
    let note = [
        column
            .and_then(|column| column.usage_note.as_deref())
            .map(|text| painter.width(text, Font::Label)),
        map.note.as_ref().map(|note| painter.note_width(note)),
        below.then_some(glass::MEANING_CARD_WIDTH + glass::MEANING_PADDING * 2.0),
    ]
    .into_iter()
    .flatten()
    .map(|width| width + padding * 2.0)
    .fold(0.0, f32::max);
    let heading = map
        .association
        .as_ref()
        .map_or(0.0, |heading| super::association::width(painter, heading));
    let width = candidate::MIN_WIDTH
        .max(trunk_right + metrics.inset)
        .max(branch_right + metrics.inset)
        .max(footer + metrics.inset * 2.0)
        .max(note + metrics.inset * 2.0)
        .max(heading + metrics.inset * 2.0);
    let trunk_y =
        metrics.inset + heading_height(map, metrics) + upper_rows as f32 * metrics.row_height;
    let width = width.ceil();
    let extra_rows = usize::from(column.is_some_and(|column| column.usage_note.is_some()))
        + usize::from(map.note.is_some());
    // 候補の下のカードは，窓の中身の幅で折り返す
    let slot =
        side.or_else(|| meaning_slot(map, painter, reserved, Some(width - metrics.inset * 2.0)));
    let below_height = slot
        .as_ref()
        .filter(|slot| slot.placement == MeaningPlacement::Below)
        .map_or(0.0, |slot| slot.height + below_margin() * 2.0);
    let height = trunk_y
        + metrics.row_height
        + lower_height
        + candidate::FRAME_WIDTH
        + below_height
        + metrics.footer_height * (1 + extra_rows) as f32
        + if painter.theme.is_rounded() {
            0.0
        } else {
            metrics.inset
        };
    let card = slot
        .as_ref()
        .zip(focused)
        .map(|(slot, (index, _))| match slot.placement {
            MeaningPlacement::Side => Frame::new(
                trunk_x[index] + branch_width + glass::MEANING_GAP,
                trunk_y + metrics.row_height + padding / 4.0,
                slot.width,
                slot.height,
            ),
            MeaningPlacement::Below => Frame::new(
                metrics.inset,
                trunk_y + metrics.row_height + lower_height + below_margin(),
                width - metrics.inset * 2.0,
                slot.height,
            ),
        });
    Layout {
        trunk_x,
        trunk_width,
        trunk_y,
        branch_width,
        lower_height,
        slot,
        card,
        width,
        height: height.ceil(),
    }
}

fn footer_width(map: &BranchMap, painter: &Painter) -> f32 {
    let source = focused(map)
        .and_then(|(_, column)| column.source_name.as_deref())
        .map_or(0.0, |name| {
            painter.width(&strings::dictionary_source(name), Font::Label) + candidate::PADDING_X
        });
    let association = map.association_hint.as_deref().map_or(0.0, |hint| {
        let width = association_key_hint(map).map_or_else(
            || painter.width(hint, Font::Label),
            |key_hint| painter.hints_width(&[key_hint]),
        );
        width + candidate::PADDING_X
    });
    painter.hints_width(&map.hints) + source + association
}

/// 連想の知らせ(R-18)のキーキャップの札．キーが割り当てられていなければ None(語だけを文字で出す)
fn association_key_hint(map: &BranchMap) -> Option<KeyHint> {
    let label = map.association_hint.as_ref()?;
    map.association_key.as_ref().map(|key| KeyHint {
        keys: key.clone(),
        label: label.clone(),
    })
}

/// 連想の一覧の見出しの行の高さ(区切りの線を含む)．連想でなければ 0
fn heading_height(map: &BranchMap, metrics: &Metrics) -> f32 {
    if map.association.is_some() {
        metrics.footer_height + candidate::FRAME_WIDTH
    } else {
        0.0
    }
}

pub fn branch_map(map: &BranchMap, look: &Look, measure: &dyn Measure) -> Scene {
    let metrics = Metrics::new(look, measure);
    let mut painter = Painter::new(look, measure);
    let theme = look.theme;
    let layout = layout(map, &metrics, &painter, look.reserved_card);
    let (width, height) = look.sized(
        layout.width + metrics.shadow,
        layout.height + metrics.shadow,
    );
    let body = Frame::new(0.0, 0.0, width - metrics.shadow, height - metrics.shadow);
    painter.panel(body);
    if let Some(heading) = &map.association {
        let row = Frame::new(
            metrics.inset,
            metrics.inset,
            body.width - metrics.inset * 2.0,
            metrics.footer_height,
        );
        super::association::draw(&mut painter, heading, row);
        let line_inset = if theme.is_rounded() {
            metrics.inset
        } else {
            metrics.inset - candidate::PADDING_X
        };
        painter.separator(row.max_y(), line_inset, body.width - line_inset);
    }
    let focused_index = focused(map).map(|(index, _)| index);
    // 注目している文節の枝(候補の右のカードを含む)が重なる範囲には，ほかの文節の添え書きを描かない
    let side_card = layout
        .slot
        .as_ref()
        .zip(layout.card)
        .filter(|(slot, _)| slot.placement == MeaningPlacement::Side);
    let branch_range = focused_index.map(|index| {
        (
            layout.trunk_x[index],
            side_card.map_or(layout.trunk_x[index] + layout.branch_width, |(_, card)| {
                card.max_x()
            }),
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
        painter.hit(
            node,
            ipc::PointerTarget::Segment {
                index: index as u32,
            },
        );
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
            // 区切っているあいだ(⇧↓)は番号キーで区切る位置を選ぶので，枝は押せない
            let pressable = column.split.is_none();
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
            if pressable {
                for index in 0..column.alternatives.len() {
                    // コメントの札は枝の行の中にあるので，行より先に足す(押した位置は先に足した範囲から引く)．
                    // 札を押すと候補の代わりにコメントを入れる
                    if let Some(comment) = super::alternative_comment(column, index) {
                        let row = branch_row(node, layout.branch_width, index, true, &metrics);
                        let frame = painter.tag_hit_frame(comment, tag_max_x(row), row);
                        painter.hit(
                            frame,
                            ipc::PointerTarget::Comment {
                                index: index as u32,
                            },
                        );
                    }
                    let y = node.max_y() + index as f32 * metrics.row_height;
                    painter.hit(
                        Frame::new(node.x, y, layout.branch_width, metrics.row_height),
                        ipc::PointerTarget::Alternative {
                            index: index as u32,
                        },
                    );
                }
                for index in 0..column.variants.len() {
                    let y = node.y - (index + 1) as f32 * metrics.row_height;
                    painter.hit(
                        Frame::new(node.x, y, layout.branch_width, metrics.row_height),
                        ipc::PointerTarget::Variant {
                            index: index as u32,
                        },
                    );
                }
            }
            if let Some((slot, card)) = side_card {
                // 選んでいる候補の枝の先から，カードの見出しへ線でつなぐ
                let selected = column
                    .selected_alternative
                    .filter(|index| (*index as usize) < column.alternatives.len());
                if let (Some(selected), Some(content)) = (selected, &slot.card) {
                    let row_y = node.max_y() + selected as f32 * metrics.row_height;
                    let start = Point::new(
                        (node.x + layout.branch_width).round(),
                        (row_y + metrics.row_height / 2.0).round(),
                    );
                    let end = Point::new(card.x, content.header_mid_y(card));
                    meaning::connector(&mut painter, start, end);
                }
                meaning::draw(&mut painter, slot.card.as_ref(), card, None);
            }
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
    let mut footer_y = layout.trunk_y + metrics.row_height + layout.lower_height;
    let content_width = body.width - metrics.inset * 2.0;
    if let (Some(slot), Some(card)) = (&layout.slot, layout.card) {
        if slot.placement == MeaningPlacement::Below {
            // 候補の下: 枝と足元のあいだに，窓の幅いっぱいのカードを出す
            meaning::draw(&mut painter, slot.card.as_ref(), card, None);
            footer_y = card.max_y() + below_margin();
        }
    }
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
    if let Some(note) = map.note.as_ref() {
        // 打ち間違いを直したことなど，IME が変えたことを知らせる
        let row = Frame::new(
            metrics.inset,
            footer_y,
            content_width,
            metrics.footer_height,
        );
        painter.note(note, row.x, row.mid_y());
        footer_y += metrics.footer_height;
    }
    footer(&mut painter, map, footer_y, body.width, &metrics);
    painter.finish(width, height)
}

/// 打ち間違いを直した文節の幹で，文字のあとに添える「修正」の札の幅(前の空きを含む)．直していなければ 0
fn corrected_label_width(column: &BranchColumn, painter: &Painter) -> f32 {
    if column.is_corrected == Some(true) {
        painter.tag_width(strings::CORRECTED) + candidate::PADDING_X / 2.0
    } else {
        0.0
    }
}

/// 幹の文節で選んでいるコマンドの種類と名前．コマンドを選んでいなければ None
fn trunk_command(column: &BranchColumn) -> Option<(CommandKind, &str)> {
    let index = column.selected_alternative? as usize;
    let kind = (*column.alternative_commands.as_ref()?.get(index)?)?;
    Some((kind, column.alternatives.get(index)?))
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
    match (&column.split, trunk_command(column)) {
        (Some(split), _) => draw_split(painter, split, node, color),
        (None, Some((kind, title))) => {
            // コマンドを選んでいれば，幹も枝と同じく種類のアイコンと名前で見せる(入力中の文字には印を付けた名前が出る)
            let x = node.x + candidate::PADDING_X;
            painter.command(kind, x, node.mid_y(), !rounded && column.is_focused, 1.0);
            painter.text(
                title,
                Font::Trunk,
                color,
                x + Painter::command_width(),
                node,
            );
        }
        (None, None) => painter.text(
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
    let to = node.max_x() - candidate::PADDING_X - corrected_label_width(column, painter);
    if column.is_corrected == Some(true) {
        // 打ち間違いを直した文節には，文字のあとに補正の色で「修正」と添える．確信の低い文節の点線と見分けるため
        painter.tag(
            strings::CORRECTED,
            node.max_x() - candidate::PADDING_X / 2.0,
            node.mid_y(),
            !rounded && column.is_focused,
            TagStyle::Corrected,
        );
    }
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
    /// 打ったまま・修正・コマンドの添え書きか，ユーザー辞書の語のコメント
    note: Option<String>,
    /// コマンドの候補なら，その種類(文字の前にアイコンを置き，添え書きをアクセントの色の札にする)
    command: Option<CommandKind>,
    /// 文字のすぐあとに控えめに添える説明(絵文字の名前)
    detail: Option<String>,
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
            command: column
                .alternative_commands
                .as_ref()
                .and_then(|kinds| kinds.get(index).copied().flatten()),
            detail: column
                .alternative_details
                .as_ref()
                .and_then(|details| details.get(index).cloned().flatten()),
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
            command: None,
            detail: None,
        })
        .collect()
}

/// 枝の index 番目の行(番号・文字・札を描く枠)．描くときと押した位置を調べるときで同じものを使う
fn branch_row(node: Frame, width: f32, index: usize, downward: bool, metrics: &Metrics) -> Frame {
    let stem_x = (node.x + metrics.stem_x).round();
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
}

/// 枝の行の札の右端
fn tag_max_x(row: Frame) -> f32 {
    row.max_x() - candidate::PADDING_X / 2.0
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
    let row_frame = |index: usize| branch_row(node, width, index, downward, metrics);
    let mids: Vec<f32> = (0..rows.len())
        .map(|index| row_frame(index).mid_y())
        .collect();
    let color = painter.theme.line;
    lines(
        painter,
        Point::new(node.x + metrics.stem_x, root_y(node, downward, metrics)),
        &mids,
        row_frame(0).x - metrics.tip_gap,
        rows.iter().position(|row| row.selected),
        color,
        metrics,
    );
    for (index, row) in rows.iter().enumerate() {
        draw_row(painter, row, row_frame(index), metrics);
    }
}

/// 幹の根元: 下の枝は文節の札の下の端，上の枝は上の端
fn root_y(node: Frame, downward: bool, metrics: &Metrics) -> f32 {
    if downward {
        node.max_y() - metrics.root_inset
    } else {
        node.y + metrics.root_inset
    }
}

/// 幹と枝の線(macOS の BranchLineDrawing)．root は幹の x と根元の y，mids は候補の行の縦の中心(幹に近い順)．
/// 選んでいない線(幹と，候補ごとの曲がり角と水平の線)は 1 つの部品にまとめて 1 回でなぞり，重なったところを濃くしない．
/// 選んでいる候補への道(幹の根元からその候補の曲がり角まで，曲がり角，水平の線)は，最後に選択の色と太さで上に重ねる
fn lines(
    painter: &mut Painter,
    root: Point,
    mids: &[f32],
    tip_x: f32,
    selected: Option<usize>,
    color: Color,
    metrics: &Metrics,
) {
    let layout = |width: f32| {
        BranchLines::new(
            root.x,
            root.y,
            mids,
            tip_x,
            metrics.turn_radius,
            width,
            metrics.pixel_scale,
        )
    };
    let base = layout(metrics.line_width);
    let last = base.turns.len().saturating_sub(1);
    let mut figures = Vec::new();
    for (index, turn) in base.turns.iter().enumerate() {
        if Some(index) == selected {
            continue;
        }
        // 幹はいちばん遠い候補の曲がり角とひと続きにし，角に切れ目を作らない(選んでいる候補より先の部分だけを描く)
        let mut figure = match base.stem_after(selected).filter(|_| index == last) {
            Some((from, to)) => Figure {
                start: from,
                segments: vec![Segment::Line(to)],
            },
            None => Figure {
                start: turn.start,
                segments: Vec::new(),
            },
        };
        figure.segments.extend(turn_segments(turn));
        figures.push(figure);
    }
    if !figures.is_empty() {
        painter.draws.push(Draw::Path {
            figures,
            color,
            width: metrics.line_width,
        });
    }
    let Some(selected) = selected.filter(|&index| index < base.turns.len()) else {
        return;
    };
    let route = layout(metrics.line_width_selected);
    let turn = &route.turns[selected];
    let mut segments = vec![Segment::Line(turn.start)];
    segments.extend(turn_segments(turn));
    painter.draws.push(Draw::Path {
        figures: vec![Figure {
            start: route.root,
            segments,
        }],
        color: painter.theme.selection,
        width: metrics.line_width_selected,
    });
}

/// 曲がり角(半径が 0 なら直角)と水平の線．曲がり角の始まりから描き始めること．
/// 下へ進んで右へ曲がる角は，y が下へ増える画面では反時計回り，上へ進んで右へ曲がる角は時計回り
fn turn_segments(turn: &Turn) -> Vec<Segment> {
    let radius = turn.end.x - turn.start.x;
    let corner = if radius > 0.0 {
        Segment::Arc {
            to: turn.end,
            radius,
            clockwise: turn.end.y < turn.start.y,
        }
    } else {
        Segment::Line(turn.end)
    };
    vec![corner, Segment::Line(turn.tip)]
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
    let mut text_x = frame.x + padding / 2.0 + metrics.lead;
    if let Some(kind) = row.command {
        // コマンドの候補は，文字の前に種類のアイコンを置く
        painter.command(kind, text_x, frame.mid_y(), row.selected, opacity);
        text_x += Painter::command_width();
    }
    painter.text(&row.text, Font::Candidate, text_color, text_x, frame);
    // 絵文字の名前は候補の文字のすぐあとに薄く小さく添える(番号と同じ色)
    if let Some(detail) = row.detail.as_deref() {
        painter.detail(
            &row.text,
            Font::Candidate,
            detail,
            muted_color,
            text_x,
            frame,
        );
    }
    if let Some(note) = row.note.as_deref() {
        painter.tag(
            note,
            tag_max_x(frame),
            frame.mid_y(),
            row.selected,
            TagStyle::of(note, row.command.is_some()),
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
    let stem_x = node.x + metrics.stem_x;
    let row = Frame::new(stem_x, node.max_y(), node.width, metrics.row_height);
    let color = theme.text_muted.faded(rest);
    // 枝と同じ形で，幹から短く曲がる
    let tip_x = (stem_x + metrics.branch_indent / 2.0).round();
    lines(
        painter,
        Point::new(stem_x, root_y(node, true, metrics)),
        &[row.mid_y()],
        tip_x,
        None,
        theme.line.faded(rest),
        metrics,
    );
    let text_x = tip_x + candidate::PADDING_X / 2.0;
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
    if let Some(hint) = map.association_hint.as_deref() {
        // 選んでいる候補に連想があることを，キーの案内のあとに小さく出す(R-18)．キーは文字ではなくキーキャップで描く
        let x = footer.x + painter.hints_width(&map.hints) + candidate::PADDING_X;
        match association_key_hint(map) {
            Some(key_hint) => painter.hints(&[key_hint], x, footer.mid_y()),
            None => painter.text(hint, Font::Label, theme.text_muted, x, footer),
        }
    }
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
            is_corrected: None,
            preview: (!focused).then(|| "腫れ".to_string()),
            shorter: None,
            longer: None,
            usage_note: None,
            homophone: None,
            alternative_notes: vec![None, Some("修正".into())],
            alternative_commands: None,
            alternative_comments: None,
            alternative_details: None,
            source_name: None,
            split: None,
        }
    }

    fn map() -> BranchMap {
        BranchMap {
            association: None,
            association_hint: None,
            association_key: None,
            columns: vec![column("今日は", true), column("晴れ", false)],
            position: 1,
            total: 2,
            note: Some(ipc::Note {
                tone: ipc::NoteTone::Info,
                title: "学習から削除しました".into(),
                subject: None,
                key: None,
                key_action: None,
                text: "学習から削除しました".into(),
            }),
            hints: vec![KeyHint {
                keys: "Space".into(),
                label: "候補".into(),
            }],
            meaning_placement: None,
        }
    }

    /// 読み全体の 1 つの文節で，下の枝の 2 番目に Web のページを開くコマンドがある分岐図．selected は選んでいる枝
    fn command_map(selected: u32) -> BranchMap {
        let mut focused = column("▶ サイト", true);
        focused.alternatives = vec!["クロード".into(), "サイト".into()];
        focused.selected_alternative = Some(selected);
        focused.alternative_notes = vec![None, Some(strings::COMMAND.into())];
        focused.alternative_commands = Some(vec![None, Some(CommandKind::OpenURL)]);
        if selected == 0 {
            focused.text = "クロード".into();
        }
        BranchMap {
            columns: vec![focused],
            ..map()
        }
    }

    #[test]
    fn コマンドの枝は種類のアイコンと札を付け_選ぶと幹も印の代わりにアイコンで見せる() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let globes = |scene: &Scene| {
                scene
                    .draws
                    .iter()
                    .filter(|draw| {
                        matches!(
                            draw,
                            Draw::Icon {
                                icon: crate::keys::Icon::Globe,
                                ..
                            }
                        )
                    })
                    .count()
            };
            let unselected = branch_map(&command_map(0), &look, &Fixed);
            assert_eq!(globes(&unselected), 1);
            assert!(texts(&unselected).contains(&(strings::COMMAND.into(), theme.selection)));
            let chosen = branch_map(&command_map(1), &look, &Fixed);
            // 枝と幹の 2 か所．幹の文字は印を除いた名前
            assert_eq!(globes(&chosen), 2);
            assert!(text_frame(&chosen, "▶ サイト").is_none());
            let trunk = chosen
                .draws
                .iter()
                .filter_map(|draw| match draw {
                    Draw::Text { text, frame, .. } if text == "サイト" => Some(frame.y),
                    _ => None,
                })
                .fold(f32::MAX, f32::min);
            assert!(trunk < text_frame(&chosen, "クロード").unwrap().y);
        }
    }

    #[test]
    fn 直した文節に修正と添える() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut corrected = column("良いですね", false);
            corrected.is_corrected = Some(true);
            let marked = BranchMap {
                columns: vec![column("今日は", true), corrected],
                ..map()
            };
            let scene = branch_map(&marked, &Look::new(&theme, 15.0), &Fixed);
            assert!(texts(&scene).contains(&(strings::CORRECTED.into(), theme.correction)));
            let plain = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
            assert!(!texts(&plain).contains(&(strings::CORRECTED.into(), theme.correction)));
        }
    }

    #[test]
    fn 押した位置から幹と枝を引く_描いた文字の位置と合う() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let scene = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
            let at = |text: &str| {
                let frame = text_frame(&scene, text).expect("描いた文字がある");
                scene.target_at(frame.x + 1.0, frame.mid_y())
            };
            assert_eq!(
                at("京は"),
                Some(ipc::PointerTarget::Alternative { index: 1 })
            );
            assert_eq!(
                at("きょうは"),
                Some(ipc::PointerTarget::Variant { index: 0 })
            );
            assert_eq!(at("晴れ"), Some(ipc::PointerTarget::Segment { index: 1 }));
            // 足元の案内は押せない
            let hint = text_frame(&scene, "候補").expect("案内がある");
            assert_eq!(scene.target_at(hint.x + 1.0, hint.mid_y()), None);
        }
    }

    #[test]
    fn コメントの札を押すとコメント_札の外の枝と_コメントでない札は候補() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut commented = map();
            commented.columns[0].alternative_notes =
                vec![Some("千代田区千代田1-1".into()), Some("修正".into())];
            commented.columns[0].alternative_comments = Some(vec![true, false]);
            let scene = branch_map(&commented, &Look::new(&theme, 15.0), &Fixed);
            let hit = |target: ipc::PointerTarget| {
                scene
                    .hits
                    .iter()
                    .find(|hit| hit.target == target)
                    .map(|hit| hit.frame)
            };
            let comment = ipc::PointerTarget::Comment { index: 0 };
            let tag = text_frame(&scene, "千代田区千代田1-1").expect("札を描く");
            assert_eq!(
                scene.target_at(tag.mid_x(), tag.mid_y()),
                Some(comment.clone())
            );
            // 札の上下の空きも，枝の行の高さいっぱいまで札として押せる
            let row = hit(ipc::PointerTarget::Alternative { index: 0 }).expect("枝の行");
            let area = hit(comment.clone()).expect("札を押せる範囲");
            assert_eq!((area.y, area.height), (row.y, row.height), "{name}");
            assert!(area.max_x() <= row.max_x(), "{name}");
            assert_eq!(scene.target_at(tag.mid_x(), row.y + 1.0), Some(comment));
            // 札の左(候補の文字の側)は候補
            assert_eq!(
                scene.target_at(area.x - 1.0, row.mid_y()),
                Some(ipc::PointerTarget::Alternative { index: 0 })
            );
            // コメントでない札(修正)は押しても候補
            let corrected = scene
                .draws
                .iter()
                .filter_map(|draw| match draw {
                    Draw::Text { text, frame, .. } if text == "修正" => Some(*frame),
                    _ => None,
                })
                .find(|frame| frame.y > row.y)
                .expect("枝の札を描く");
            assert_eq!(
                scene.target_at(corrected.mid_x(), corrected.mid_y()),
                Some(ipc::PointerTarget::Alternative { index: 1 })
            );
        }
        // コメントの無い分岐図には札の押せる範囲を足さない
        let theme = theme("automatic");
        let scene = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
        assert!(!scene
            .hits
            .iter()
            .any(|hit| matches!(hit.target, ipc::PointerTarget::Comment { .. })));
    }

    #[test]
    fn 区切っているあいだは枝を押せない() {
        let theme = theme("automatic");
        let mut splitting = map();
        splitting.columns[0].split = Some(BranchSplit {
            pieces: vec!["今日".into(), "は".into()],
        });
        let scene = branch_map(&splitting, &Look::new(&theme, 15.0), &Fixed);
        assert!(!scene.hits.iter().any(|hit| matches!(
            hit.target,
            ipc::PointerTarget::Alternative { .. }
                | ipc::PointerTarget::Variant { .. }
                | ipc::PointerTarget::Comment { .. }
        )));
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
            // ほかの知らせは控えめな色で出す
            assert!(texts.contains(&("学習から削除しました".into(), theme.text_muted)));
            assert!(texts.contains(&("1–2 / 2".into(), theme.text_muted)));
            // 注目している文節の枝と重なる文節には，次の候補を添えない
            assert!(!texts.iter().any(|(text, _)| text == "腫れ"));
        }
    }

    /// 枝の線の部品(図形・色・太さ)を描く順に
    fn paths(scene: &Scene) -> Vec<(Vec<Figure>, Color, f32)> {
        scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Path {
                    figures,
                    color,
                    width,
                } => Some((figures.clone(), *color, *width)),
                _ => None,
            })
            .collect()
    }

    fn arcs(figures: &[Figure]) -> Vec<(f32, bool)> {
        figures
            .iter()
            .flat_map(|figure| figure.segments.iter())
            .filter_map(|segment| match segment {
                Segment::Arc {
                    radius, clockwise, ..
                } => Some((*radius, *clockwise)),
                Segment::Line(_) => None,
            })
            .collect()
    }

    /// 図形の終わり(水平の線の終わり)
    fn tip(figure: &Figure) -> Point {
        match figure.segments.last() {
            Some(Segment::Line(to)) | Some(Segment::Arc { to, .. }) => *to,
            None => figure.start,
        }
    }

    #[test]
    fn 曲線の枝は1本の幹と同じ半径の曲がり角で描き_選んだ道を最後に選択の色で重ねる() {
        let theme = theme("nordic");
        let scene = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
        let paths = paths(&scene);
        // 下の枝の選んでいない線・下の枝の選んだ道・上の枝の選んでいない線．線は向きごとに 1 つの部品にまとめる
        assert_eq!(paths.len(), 3);
        assert_eq!(
            paths.iter().map(|path| path.1).collect::<Vec<_>>(),
            vec![theme.line, theme.selection, theme.line]
        );
        assert_eq!(paths[0].2, glass::LINE_WIDTH);
        assert_eq!(paths[1].2, glass::LINE_WIDTH_SELECTED);
        // 曲がり角はどれも同じ半径．下へ曲がる角は反時計回り，上へ曲がる角は時計回り
        assert_eq!(arcs(&paths[0].0), vec![(glass::BRANCH_TURN_RADIUS, false)]);
        assert_eq!(arcs(&paths[1].0), vec![(glass::BRANCH_TURN_RADIUS, false)]);
        assert_eq!(arcs(&paths[2].0), vec![(glass::BRANCH_TURN_RADIUS, true)]);
        // 選んだ道は文節の地の下の端から始まり，どの枝も行の左の手前の同じ x で終わる
        let node_bottom = glass::PADDING + glass::ROW_HEIGHT * 2.0;
        assert_eq!(
            paths[1].0[0].start.y,
            node_bottom - glass::SELECTION_INSET_Y
        );
        let tip_x = (glass::PADDING + glass::BRANCH_STEM_X).round() + glass::BRANCH_INDENT
            - glass::BRANCH_TIP_GAP;
        for (figures, _, _) in &paths {
            assert!(figures.iter().all(|figure| tip(figure).x == tip_x));
        }
        // 選んだのは下の枝のいちばん遠い候補なので，選んでいない線に幹は無く，手前の候補の曲がり角だけ
        assert_eq!(paths[0].0.len(), 1);
        assert_eq!(paths[0].0[0].segments.len(), 2);
        // 上の枝は幹といちばん遠い候補の曲がり角をひと続きに描く
        assert_eq!(paths[2].0.len(), 1);
        assert_eq!(paths[2].0[0].segments.len(), 3);
        assert_eq!(
            paths[2].0[0].start.y,
            glass::PADDING + glass::ROW_HEIGHT + glass::SELECTION_INSET_Y
        );
        assert_eq!(count(&scene, |draw| matches!(draw, Draw::Curve { .. })), 0);
        // 確信の低い文節の点線は丸い点
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::Line { dot_pitch: Some(pitch), color, .. } if *pitch == glass::DOT_PITCH && *color == theme.correction)));
    }

    #[test]
    fn 線はデバイスのピクセルにそろえる() {
        let theme = theme("washi");
        let look = Look {
            pixel_scale: 2.0,
            ..Look::new(&theme, 15.0)
        };
        let scene = branch_map(&map(), &look, &Fixed);
        for (figures, _, width) in paths(&scene) {
            for figure in &figures {
                // 幹の線の縁と水平の線の縁が，デバイスのピクセルの境に来る
                let edge = figure.start.x * 2.0 - width;
                let end = tip(figure);
                assert_eq!(end.x * 2.0, (end.x * 2.0).round());
                assert_eq!((end.y * 2.0 - width), (end.y * 2.0 - width).round());
                if figure.segments.len() == 3 {
                    assert_eq!(edge, edge.round());
                }
            }
        }
    }

    #[test]
    fn platinum_は直線の枝と文節をつなぐ線() {
        let theme = theme("platinum");
        let scene = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
        assert_eq!(count(&scene, |draw| matches!(draw, Draw::Curve { .. })), 0);
        let paths = paths(&scene);
        // 直角に曲がる．選んだ道は 2 ドットで選択の色
        assert!(paths.iter().all(|path| arcs(&path.0).is_empty()));
        assert!(paths
            .iter()
            .any(|path| path.1 == theme.selection && path.2 == branch::LINE_WIDTH_SELECTED));
        assert!(paths
            .iter()
            .any(|path| path.1 == theme.line && path.2 == branch::LINE_WIDTH));
    }

    #[test]
    fn カスタムテーマの直線の枝() {
        let mut theme = theme("nordic");
        theme.straight_branches = true;
        let scene = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
        assert_eq!(count(&scene, |draw| matches!(draw, Draw::Curve { .. })), 0);
        let paths = paths(&scene);
        assert_eq!(paths.len(), 3);
        assert!(paths.iter().all(|path| arcs(&path.0).is_empty()));
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
                association: None,
                association_hint: None,
                association_key: None,
                columns: vec![focused],
                position: 1,
                total: 4,
                note: None,
                hints: vec![],
                meaning_placement: None,
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

    /// 「撮る」の文節で候補の枝を開き，2 番目の「撮る」を選んだ分岐図(意味のカードを出す)
    fn meaning_map(placement: ipc::MeaningPlacement) -> BranchMap {
        let mut focused = column("撮る", true);
        focused.alternatives = vec!["取る".into(), "撮る".into(), "とる".into()];
        focused.alternative_notes = vec![None, None, None];
        focused.selected_alternative = Some(1);
        focused.homophone = Some(ipc::HomophoneNote {
            word: "撮る".into(),
            part_of_speech: Some(ipc::PartOfSpeech::Verb),
            senses: vec![ipc::HomophoneSense {
                meaning: "写真や動画を写す".into(),
                example: Some("記念写真を撮った".into()),
            }],
            others: vec!["取る".into(), "採る".into()],
        });
        BranchMap {
            columns: vec![column("写真を", false), focused],
            note: None,
            meaning_placement: Some(placement),
            ..map()
        }
    }

    #[test]
    fn 語の意味は選んでいる候補の枝の先にカードを置き_線でつなぐ() {
        for name in ["washi", "platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let scene = branch_map(&meaning_map(ipc::MeaningPlacement::Side), &look, &Fixed);
            let texts = texts(&scene);
            for text in ["写真や動画を写す", "動詞", "同音語", "採る"] {
                assert!(
                    texts.iter().any(|(shown, _)| shown == text),
                    "{name}: {text}"
                );
            }
            // 同音語の札には，枝に出ている語(取る)を出さない
            let tags = texts.iter().filter(|(shown, _)| shown == "取る").count();
            assert_eq!(tags, 1, "{name}");
            // カードは候補の枝の右に置く
            let meaning = text_frame(&scene, "写真や動画を写す").expect("意味を描く");
            let branch = scene
                .hits
                .iter()
                .find(|hit| hit.target == ipc::PointerTarget::Alternative { index: 1 })
                .map(|hit| hit.frame)
                .expect("選んでいる枝");
            assert!(meaning.x >= branch.max_x() + glass::MEANING_GAP, "{name}");
            // 端の丸は選んでいる枝の高さより下(カードの見出し)にあり，カードの左の辺に付く
            let dot = scene
                .draws
                .iter()
                .find_map(|draw| match draw {
                    Draw::Ellipse { frame, color }
                        if frame.width == glass::MEANING_DOT_SIZE && *color == theme.selection =>
                    {
                        Some(*frame)
                    }
                    _ => None,
                })
                .expect("端の丸");
            assert_eq!(dot.mid_x(), branch.max_x() + glass::MEANING_GAP, "{name}");
            if theme.curved_branches() {
                assert!(scene.draws.iter().any(|draw| matches!(draw,
                    Draw::Curve { from, to, .. } if from.x == branch.max_x().round() && to.x == dot.mid_x())), "{name}");
            }
            // 一覧と違って三角で指さない
            assert!(
                !scene
                    .draws
                    .iter()
                    .any(|draw| matches!(draw, Draw::Polygon { .. })),
                "{name}"
            );
            let plain = branch_map(
                &BranchMap {
                    meaning_placement: None,
                    columns: meaning_map(ipc::MeaningPlacement::Side)
                        .columns
                        .into_iter()
                        .map(|column| BranchColumn {
                            homophone: None,
                            ..column
                        })
                        .collect(),
                    ..meaning_map(ipc::MeaningPlacement::Side)
                },
                &look,
                &Fixed,
            );
            assert!(
                scene.width >= plain.width + glass::MEANING_BRANCH_WIDTH,
                "{name}"
            );
        }
    }

    #[test]
    fn 分岐図で候補の下に出す設定では枝と足元のあいだに窓の幅いっぱいのカードを出す() {
        for name in ["washi", "platinum"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let scene = branch_map(&meaning_map(ipc::MeaningPlacement::Below), &look, &Fixed);
            let meaning = text_frame(&scene, "写真や動画を写す").expect("意味を描く");
            let last = text_frame(&scene, "とる").expect("最後の枝");
            let footer = text_frame(&scene, "候補").expect("足元の案内");
            assert!(
                meaning.y > last.max_y() && meaning.max_y() < footer.y,
                "{name}"
            );
            // 線でつながない
            assert!(
                !scene.draws.iter().any(|draw| matches!(draw,
                Draw::Ellipse { frame, .. } if frame.width == glass::MEANING_DOT_SIZE)),
                "{name}"
            );
        }
    }

    #[test]
    fn 分岐図で意味の無い候補に移っても空けておいたカードで窓の大きさを変えない() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let mut reservation = crate::scene::CardReservation::default();
        let shown = meaning_map(ipc::MeaningPlacement::Side);
        let first = branch_map(
            &shown,
            &Look {
                reserved_card: reservation.branch(&shown, &look, &Fixed),
                ..look
            },
            &Fixed,
        );
        let mut moved = shown.clone();
        moved.columns[1].selected_alternative = Some(2);
        moved.columns[1].text = "とる".into();
        moved.columns[1].homophone = None;
        moved.meaning_placement = None;
        let empty = branch_map(
            &moved,
            &Look {
                reserved_card: reservation.branch(&moved, &look, &Fixed),
                ..look
            },
            &Fixed,
        );
        assert_eq!((empty.width, empty.height), (first.width, first.height));
        assert!(text_frame(&empty, "写真や動画を写す").is_none());
        assert!(empty.draws.iter().any(|draw| matches!(
            draw,
            Draw::Icon {
                icon: crate::keys::Icon::Book,
                ..
            }
        )));
        // 空いたカードへは線を引かない
        assert!(!empty.draws.iter().any(|draw| matches!(draw,
            Draw::Ellipse { frame, .. } if frame.width == glass::MEANING_DOT_SIZE)));
    }

    #[test]
    fn 区切っているあいだは語の意味のカードを出さない() {
        let theme = theme("washi");
        let mut splitting = meaning_map(ipc::MeaningPlacement::Side);
        splitting.columns[1].split = Some(BranchSplit {
            pieces: vec!["撮".into(), "る".into()],
        });
        let scene = branch_map(&splitting, &Look::new(&theme, 15.0), &Fixed);
        assert!(text_frame(&scene, "写真や動画を写す").is_none());
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
        // 添える候補の枝は 1 本だけ(注目している文節が無いので)
        assert_eq!(count(&scene, |draw| matches!(draw, Draw::Path { .. })), 1);
        assert_eq!(count(&scene, |draw| matches!(draw, Draw::Curve { .. })), 0);
    }
}
