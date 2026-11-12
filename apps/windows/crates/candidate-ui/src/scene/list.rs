#![forbid(unsafe_code)]

//! 候補の一覧(macOS の CandidateView)．上から，文字種の行・候補・足元の 3 つの区画．
//! 語の意味のカードは，候補の右(候補の列と同じ高さ)か，候補と足元のあいだに出す

use super::meaning;
use super::paint::{Painter, TagStyle};
use super::{Frame, Look, Measure, Point, Scene};
use crate::strings;
use crate::theme::Font;
use ipc::{CandidateFocus, CandidateList, KeyHint, MeaningPlacement};
use tokens::opacity;
use tokens::size::{branch, candidate, glass};

struct Metrics {
    row_height: f32,
    section_height: f32,
    /// 外枠と立体の縁の太さ．角丸のテーマは余白
    inset: f32,
    /// 番号の幅
    lead: f32,
    shadow: f32,
}

impl Metrics {
    fn new(look: &Look, measure: &dyn Measure) -> Self {
        let rounded = look.theme.is_rounded();
        let base_row = if rounded {
            glass::ROW_HEIGHT
        } else {
            candidate::ROW_HEIGHT
        };
        Self {
            row_height: (base_row * look.font_size / candidate::FONT_SIZE).round(),
            section_height: if rounded {
                glass::FOOTER_HEIGHT
            } else {
                measure.height(Font::Label).ceil().max(glass::KEYCAP_HEIGHT)
                    + candidate::SECTION_PADDING_Y * 2.0
            },
            inset: if rounded {
                glass::PADDING / 2.0
            } else {
                candidate::FRAME_WIDTH + candidate::BEVEL_WIDTH
            },
            lead: if rounded {
                glass::BADGE_SIZE + candidate::PADDING_X
            } else {
                candidate::INDEX_WIDTH
            },
            shadow: if look.theme.has_drop_shadow() {
                candidate::SHADOW_OFFSET
            } else {
                0.0
            },
        }
    }
}

struct Footer {
    hints: Vec<KeyHint>,
    note: Option<ipc::Note>,
    position: String,
    /// 選んでいる候補に連想があることの知らせ(R-18)のうち，キーの割り当てが無いときの語．
    /// キーがあればキーキャップの札として hints に入れる(キーを文字で書かない)
    association_hint: Option<String>,
}

fn footer(list: &CandidateList) -> Footer {
    if list.focus == CandidateFocus::Variants {
        let index = list.selected_variant.map_or(1, |index| index + 1);
        return Footer {
            hints: list.hints.clone().unwrap_or_default(),
            note: list.note.clone(),
            position: strings::variants_position(index, list.variants.len() as u32),
            association_hint: None,
        };
    }
    // キーの案内はエンジンが，キー設定の表と「キーの案内を表示」の設定に従って作る(FooterHints)
    let mut hints = list.hints.clone().unwrap_or_default();
    let mut association_hint = None;
    if let Some(label) = &list.association_hint {
        match &list.association_key {
            Some(key) => hints.push(KeyHint {
                keys: key.clone(),
                label: label.clone(),
            }),
            None => association_hint = Some(label.clone()),
        }
    }
    Footer {
        hints,
        note: list.note.clone(),
        // まだ選んでいない(入力中の候補の窓で選び始める前の)ときは，何番目かを出さない
        position: if list.position == 0 {
            String::new()
        } else {
            strings::position(list.position, list.position, list.total)
        },
        association_hint,
    }
}

/// 候補を表に広げたとき(キー設定の表の「候補を表に広げる」)の 1 列の候補の数．広げていなければ None
fn column_length(list: &CandidateList) -> Option<usize> {
    list.column_length
        .map(|length| length as usize)
        .filter(|&length| length > 0)
}

/// 列の数．広げていなければ 1
fn column_count(list: &CandidateList) -> usize {
    column_length(list).map_or(1, |length| list.entries.len().div_ceil(length).max(1))
}

/// index 番目の候補に振る番号(1 から)．表では選んでいる候補の列(字種の行にいるときは先頭の列)にだけ振る．
/// 番号を振らない窓(選び始める前の入力中の候補の窓)なら None．core の CandidatePanel.number(ofEntry:) と同じ決まり
fn entry_number(list: &CandidateList, index: usize) -> Option<usize> {
    if !list.shows_numbers.unwrap_or(true) {
        return None;
    }
    let Some(length) = column_length(list) else {
        return Some(index + 1);
    };
    let numbered = match (list.focus, list.selected_entry) {
        (CandidateFocus::Candidate, Some(selected)) => selected as usize / length,
        _ => 0,
    };
    (index / length == numbered).then_some(index % length + 1)
}

pub fn candidate_list(list: &CandidateList, look: &Look, measure: &dyn Measure) -> Scene {
    let metrics = Metrics::new(look, measure);
    let mut painter = Painter::new(look, measure);
    let theme = look.theme;
    let padding = candidate::PADDING_X;
    let footer = footer(list);

    // 候補の右に出す語の意味のカード．幅は決まっているので，候補の列より先に決める
    let card_margin = card_margin(look);
    let side = (meaning::placement(list.meaning_placement) == MeaningPlacement::Side)
        .then(|| {
            let card = list
                .homophone
                .as_ref()
                .map(|note| meaning::list_card(&painter, note));
            meaning::side_slot(card, glass::MEANING_CARD_WIDTH, look.reserved_card)
        })
        .flatten()
        .map(|slot| meaning::Slot {
            width: slot.width + card_margin,
            height: slot.height + card_margin * 2.0,
            ..slot
        });
    let side_extent = side
        .as_ref()
        .map_or(0.0, |slot| glass::MEANING_GAP + slot.width);

    // 表に広げたときは列の幅をそろえ，窓が表の幅の上限に収まるよう列を狭める(収まらない候補は末尾を省く)
    let grid = column_length(list);
    let columns = column_count(list) as f32;
    let cell_limit = grid.map(|_| {
        ((candidate::GRID_MAX_WIDTH
            - metrics.inset * 2.0
            - metrics.shadow
            - candidate::FRAME_WIDTH * (columns - 1.0))
            / columns)
            .floor()
    });
    // 長い文の候補は，窓の幅の上限に収まるよう省く．ほかの候補と違うところの少し手前から見せる
    // (頭が同じ文が並ぶので，末尾を省くと見分けられない．macOS の CandidateView と同じ)
    let text_limit = cell_limit
        .unwrap_or(candidate::MAX_WIDTH - metrics.inset * 2.0 - metrics.shadow - side_extent)
        - metrics.lead
        - padding * 2.0;
    let shown: Vec<String> = list
        .entries
        .iter()
        .map(|entry| {
            let annotation = entry
                .annotation
                .as_deref()
                .map_or(0.0, |note| painter.tag_width(note) + padding)
                + entry.command.map_or(0.0, |_| Painter::command_width())
                + painter.detail_width(entry.detail.as_deref());
            let available = (text_limit - annotation).max(0.0);
            let measure = |text: &str| painter.width(text, Font::Candidate);
            if measure(&entry.text) <= available {
                return entry.text.clone();
            }
            let shared = super::fitting::shared_prefix_length(
                &entry.text,
                list.entries.iter().map(|other| other.text.as_str()),
            )
            .saturating_sub(candidate::TRUNCATION_CONTEXT as usize);
            super::fitting::truncated_keeping(&entry.text, available, shared, &measure)
        })
        .collect();

    // 大きさ
    let entry_width = list
        .entries
        .iter()
        .zip(&shown)
        .map(|(entry, text)| {
            entry.command.map_or(0.0, |_| Painter::command_width())
                + painter.width(text, Font::Candidate)
                + painter.detail_width(entry.detail.as_deref())
                + entry
                    .annotation
                    .as_deref()
                    .map_or(0.0, |note| painter.tag_width(note) + padding)
        })
        .fold(0.0, f32::max);
    let variants_width: f32 = list
        .variants
        .iter()
        .map(|variant| {
            painter.width(&variant.label, Font::Label) + candidate::VARIANT_PADDING_X * 2.0
        })
        .sum();
    let hints_width = match &footer.note {
        Some(note) => painter.note_width(note),
        None => painter.hints_width(&footer.hints),
    };
    let association_hint = footer
        .association_hint
        .as_deref()
        .map_or(0.0, |hint| painter.width(hint, Font::Label) + padding);
    let footer_width = hints_width
        + association_hint
        + painter.width(&footer.position, Font::Label)
        + padding * 3.0;
    let heading_width = list
        .association
        .as_ref()
        .map_or(0.0, |heading| super::association::width(&painter, heading));
    // 候補 1 つの枠の幅．表では文字が収まる幅を切り上げ，上限から割った幅を超えない(列の位置を整数にそろえる)
    let natural_cell = metrics.lead + entry_width + padding * 2.0;
    let cell_width = cell_limit.map_or(natural_cell, |limit| natural_cell.ceil().min(limit));
    // 候補の列(文字種の行・候補)の幅と高さ．足元とカードを除く．表なら，すべての列と列のあいだの線を合わせた幅
    let list_width = candidate::MIN_WIDTH
        .max(cell_width * columns + candidate::FRAME_WIDTH * (columns - 1.0))
        .max(variants_width + padding * 2.0)
        .max(heading_width);
    // 候補を縦に並べる行の数．表なら 1 列の候補の数(最後のページで候補が少なければその数)
    let rows = grid.map_or(list.entries.len(), |length| list.entries.len().min(length));
    // 連想の一覧では，文字種の行の代わりに見出しの行を出す
    let list_height = rows as f32 * metrics.row_height
        + if !list.variants.is_empty() || list.association.is_some() {
            metrics.section_height + candidate::FRAME_WIDTH
        } else {
            0.0
        };
    let footer_height = metrics.section_height + candidate::FRAME_WIDTH;
    let (content_width, content_height, slot) = match side {
        Some(slot) => (
            (list_width + side_extent).max(footer_width),
            list_height.max(slot.height) + footer_height,
            Some(slot),
        ),
        None => {
            // 候補の下のカードは窓の幅いっぱいにし，その幅で折り返す
            let below = (list.meaning_placement == Some(MeaningPlacement::Below))
                .then_some(list.homophone.as_ref())
                .flatten();
            let content_width = list_width.max(footer_width).max(below.map_or(0.0, |_| {
                glass::MEANING_CARD_WIDTH + glass::MEANING_PADDING * 2.0 + padding
            }));
            let slot = below.map(|note| {
                let width = content_width - padding - glass::MEANING_PADDING * 2.0;
                meaning::below_slot(meaning::Card::new(
                    &painter,
                    note,
                    note.others.clone(),
                    width,
                ))
            });
            let below_height = slot
                .as_ref()
                .map_or(0.0, |slot| slot.height + below_margin() * 2.0);
            (
                content_width,
                list_height + below_height + footer_height,
                slot,
            )
        }
    };
    let width = (content_width + metrics.inset * 2.0 + metrics.shadow).ceil();
    let height = (content_height + metrics.inset * 2.0 + metrics.shadow).ceil();
    let (width, height) = look.sized(width, height);

    // 描く
    let body = Frame::new(0.0, 0.0, width - metrics.shadow, height - metrics.shadow);
    painter.panel(body);
    let content = body.inset(metrics.inset, metrics.inset);
    // 候補の右にカードを出すときは，候補の列をカードの分だけ狭める
    let list_width = match &slot {
        Some(slot) if slot.placement == MeaningPlacement::Side => {
            (content.width - glass::MEANING_GAP - slot.width).max(0.0)
        }
        _ => content.width,
    };
    let list_max_x = content.x + list_width;
    let mut y = content.y;
    if let Some(heading) = &list.association {
        super::association::draw(
            &mut painter,
            heading,
            Frame::new(content.x, y, list_width, metrics.section_height),
        );
        y += metrics.section_height;
        separator(&mut painter, y, content.x, list_max_x);
        y += candidate::FRAME_WIDTH;
    } else if !list.variants.is_empty() {
        variants(
            &mut painter,
            list,
            Frame::new(content.x, y, list_width, metrics.section_height),
        );
        y += metrics.section_height;
        separator(&mut painter, y, content.x, list_max_x);
        y += candidate::FRAME_WIDTH;
    }
    let mut selected_mid_y = None;
    let entries_top = y;
    if let Some(length) = grid {
        // 表の列のあいだの縦の線．glass は上下を少し空けた細い線，platinum と desk は候補の行の高さいっぱいの線
        let margin = if theme.is_rounded() {
            glass::PADDING / 2.0
        } else {
            0.0
        };
        let height = list.entries.len().min(length) as f32 * metrics.row_height;
        for column in 1..column_count(list) {
            let x = (content.x + column as f32 * (cell_width + candidate::FRAME_WIDTH)
                - candidate::FRAME_WIDTH)
                .round();
            painter.rect(
                Frame::new(
                    x,
                    entries_top + margin,
                    candidate::FRAME_WIDTH,
                    height - margin * 2.0,
                ),
                theme.line,
            );
        }
    }
    for (index, entry) in list.entries.iter().enumerate() {
        // 表では上から下へ詰め，列を左から右へ並べる
        let row = match grid {
            Some(length) => Frame::new(
                content.x + (index / length) as f32 * (cell_width + candidate::FRAME_WIDTH),
                entries_top + (index % length) as f32 * metrics.row_height,
                cell_width,
                metrics.row_height,
            ),
            None => Frame::new(
                content.x,
                entries_top + index as f32 * metrics.row_height,
                list_width,
                metrics.row_height,
            ),
        };
        // コメントの札は行の中にあるので，行より先に足す(押した位置は先に足した範囲から引く)．
        // 札を押すと候補の代わりにコメントを入れる
        if let Some(comment) = super::entry_comment(entry) {
            let frame = painter.tag_hit_frame(comment, tag_max_x(row), row);
            painter.hit(
                frame,
                ipc::PointerTarget::Comment {
                    index: index as u32,
                },
            );
        }
        painter.hit(
            row,
            ipc::PointerTarget::Entry {
                index: index as u32,
            },
        );
        let selected =
            list.focus == CandidateFocus::Candidate && list.selected_entry == Some(index as u32);
        if selected {
            selected_mid_y = Some(row.mid_y());
            if theme.is_rounded() {
                painter.capsule(row.inset(0.0, glass::SELECTION_INSET_Y), theme.selection);
            } else {
                painter.rect(row, theme.selection);
            }
        }
        // 出した直後は，第 1 候補と選んでいる候補だけを濃く出す
        let opacity = if selected || index == 0 {
            1.0
        } else {
            look.rest_opacity
        };
        let text_color = if selected {
            theme.selection_text
        } else {
            theme.text
        }
        .faded(opacity);
        let muted_color = if selected {
            theme.selection_text
        } else {
            theme.text_muted
        }
        .faded(opacity);
        // 表では選んでいる列にだけ番号を振る(番号キーはその列の中で選ぶ)．ほかの列は番号の場所を空けたままにし，列を移っても文字を動かさない
        let number = entry_number(list, index).map(|number| number.to_string());
        let mut text_x = if theme.is_rounded() {
            row.x + padding / 2.0 + metrics.lead
        } else {
            row.x + padding + metrics.lead
        };
        if let Some(kind) = entry.command {
            // コマンドの候補は，文字の前に種類のアイコンを置く
            painter.command(kind, text_x, row.mid_y(), selected, opacity);
            text_x += Painter::command_width();
        }
        // 番号キーで選べない窓(選び始める前の入力中の候補など)では番号を振らない．
        // 文字の位置は変えない(選び始めて番号が出たときに候補が横に動かないように)
        if theme.is_rounded() {
            if let Some(number) = &number {
                let center =
                    Point::new(row.x + padding / 2.0 + glass::BADGE_SIZE / 2.0, row.mid_y());
                painter.badge(
                    number,
                    center,
                    selected,
                    opacity,
                    glass::BADGE_SIZE,
                    Font::Key,
                );
            }
            painter.text(&shown[index], Font::Candidate, text_color, text_x, row);
        } else {
            if let Some(number) = &number {
                painter.text(number, Font::Label, muted_color, row.x + padding, row);
            }
            painter.text(&shown[index], Font::Candidate, text_color, text_x, row);
        }
        // 絵文字の名前は候補の文字のすぐあとに薄く小さく添える(番号と同じ色)
        if let Some(detail) = entry.detail.as_deref() {
            painter.detail(
                &shown[index],
                Font::Candidate,
                detail,
                muted_color,
                text_x,
                row,
            );
        }
        // 省いたときは補正の下線を引かない(位置が合わない)
        let whole = shown[index] == entry.text;
        if let (true, Some(start), Some(length)) =
            (whole, entry.corrected_start, entry.corrected_length)
        {
            // 打ち間違いを直した語句に，入力中の文字と同じ補正の点線を引く．位置は char の数で届く
            let before: String = entry.text.chars().take(start as usize).collect();
            let corrected: String = entry
                .text
                .chars()
                .skip(start as usize)
                .take(length as usize)
                .collect();
            let from = (text_x + painter.width(&before, Font::Candidate)).round();
            let to = (from + painter.width(&corrected, Font::Candidate)).round();
            let offset = if theme.is_rounded() {
                glass::UNDERLINE_OFFSET
            } else {
                branch::UNDERLINE_OFFSET
            };
            let color = if selected {
                theme.selection_text
            } else {
                theme.correction
            }
            .faded(opacity);
            painter.underline(from, to, row.max_y() - offset, color, true);
        }
        if let Some(annotation) = entry.annotation.as_deref() {
            painter.tag(
                annotation,
                tag_max_x(row),
                row.mid_y(),
                selected,
                TagStyle::of(annotation, entry.command.is_some()),
            );
        }
    }
    y = entries_top + rows as f32 * metrics.row_height;
    if let Some(slot) = &slot {
        match slot.placement {
            MeaningPlacement::Side => {
                // 候補の右: 候補の列と同じ高さのカードにし，選んでいる候補を左の辺の三角で指す．
                // platinum と desk はカードの枠を窓の縁から離し，二重の線に見せない
                y = content.y + list_height.max(slot.height);
                let card = Frame::new(
                    list_max_x + glass::MEANING_GAP,
                    content.y + card_margin,
                    slot.width - card_margin,
                    y - content.y - card_margin * 2.0,
                );
                meaning::draw(&mut painter, slot.card.as_ref(), card, selected_mid_y);
            }
            MeaningPlacement::Below => {
                // 候補の下: 候補と足元のあいだに，窓の幅いっぱいのカードを出す．足元のキーの案内は消さない
                y += below_margin();
                let card = Frame::new(
                    content.x + padding / 2.0,
                    y,
                    content.width - padding,
                    slot.height,
                );
                meaning::draw(&mut painter, slot.card.as_ref(), card, None);
                y += slot.height + below_margin();
            }
        }
    }
    separator(&mut painter, y, content.x, content.max_x());
    y += candidate::FRAME_WIDTH;
    footer_section(
        &mut painter,
        &footer,
        Frame::new(content.x, y, content.width, metrics.section_height),
    );
    painter.finish(width, height)
}

/// 候補の行の札の右端
fn tag_max_x(row: Frame) -> f32 {
    row.max_x() - candidate::PADDING_X / 2.0
}

/// platinum と desk は窓の縁に余白が無いので，候補の右のカードを縁から離す空き(上・下・右)．角丸のテーマは 0
fn card_margin(look: &Look) -> f32 {
    if look.theme.is_rounded() {
        0.0
    } else {
        candidate::PADDING_X / 2.0
    }
}

/// 候補の下に出すカードの上下の空き
fn below_margin() -> f32 {
    candidate::PADDING_X / 2.0
}

fn separator(painter: &mut Painter, y: f32, from: f32, to: f32) {
    if painter.theme.is_rounded() {
        let half = candidate::PADDING_X / 2.0;
        painter.separator(y, from + half, to - half);
    } else {
        painter.separator(y, from, to);
    }
}

/// 文字種の行．ふだんは弱い文字で見せ，上キーで移ったときだけ強調する(R-03)
fn variants(painter: &mut Painter, list: &CandidateList, section: Frame) {
    let theme = painter.theme;
    let inset_y = if theme.is_rounded() {
        glass::VARIANT_INSET_Y
    } else {
        candidate::VARIANT_INSET_Y
    };
    let mut x = section.x + candidate::PADDING_X / 2.0;
    for (index, variant) in list.variants.iter().enumerate() {
        let selected =
            list.focus == CandidateFocus::Variants && list.selected_variant == Some(index as u32);
        let color = match (selected, variant.is_available) {
            (true, _) => theme.selection_text,
            (false, true) => theme.text_muted,
            (false, false) => theme.text_muted.faded(opacity::variant::UNAVAILABLE),
        };
        let width = painter.width(&variant.label, Font::Label) + candidate::VARIANT_PADDING_X * 2.0;
        let cell = Frame::new(
            x,
            section.y + inset_y,
            width,
            section.height - inset_y * 2.0,
        );
        if variant.is_available {
            painter.hit(
                cell,
                ipc::PointerTarget::ListVariant {
                    index: index as u32,
                },
            );
        }
        if selected {
            if theme.is_rounded() {
                painter.capsule(cell, theme.selection);
            } else {
                painter.rect(cell, theme.selection);
            }
        }
        painter.text(
            &variant.label,
            Font::Label,
            color,
            cell.x + candidate::VARIANT_PADDING_X,
            cell,
        );
        x += width;
    }
}

/// 角丸のテーマは案内を左，位置を右．platinum と desk は位置を左，案内を右(漢字Talk 7 の候補ウィンドウにならう)
fn footer_section(painter: &mut Painter, footer: &Footer, section: Frame) {
    let theme = painter.theme;
    let left = section.x + candidate::PADDING_X;
    let right = section.max_x() - candidate::PADDING_X;
    if theme.is_rounded() {
        match &footer.note {
            Some(note) => painter.note(note, left, section.mid_y()),
            None => {
                painter.hints(&footer.hints, left, section.mid_y());
                if let Some(hint) = &footer.association_hint {
                    // 選んでいる候補に連想があることを，キーの案内のあとに小さく出す(R-18)
                    let x = left + painter.hints_width(&footer.hints) + candidate::PADDING_X;
                    painter.text(hint, Font::Label, theme.text_muted, x, section);
                }
            }
        }
        painter.text_right(
            &footer.position,
            Font::Label,
            theme.text_muted,
            right,
            section,
        );
        return;
    }
    painter.text(
        &footer.position,
        Font::Label,
        theme.text_muted,
        left,
        section,
    );
    match &footer.note {
        Some(note) => {
            let width = painter.note_width(note);
            painter.note(note, right - width, section.mid_y());
        }
        None => {
            let width = painter.hints_width(&footer.hints);
            painter.hints(&footer.hints, right - width, section.mid_y());
            if let Some(hint) = &footer.association_hint {
                let end = right - width - candidate::PADDING_X;
                painter.text_right(hint, Font::Label, theme.text_muted, end, section);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use super::super::Draw;
    use super::*;
    use ipc::{CandidateEntry, CandidateVariant};

    #[test]
    fn 窓の大きさを外から決めると_その大きさで描く() {
        let theme = theme("washi");
        let look = Look::new(&theme, 15.0);
        let natural = candidate_list(&list(Some(0)), &look, &Fixed);
        let narrower = (natural.width - 10.0, natural.height - 10.0);
        let sized = candidate_list(
            &list(Some(0)),
            &Look {
                size: Some(narrower),
                ..look
            },
            &Fixed,
        );
        assert_eq!((sized.width, sized.height), narrower);
        assert_eq!(texts(&sized), texts(&natural));
    }

    fn list(selected: Option<u32>) -> CandidateList {
        CandidateList {
            association: None,
            association_hint: None,
            association_key: None,
            homophone: None,
            shows_numbers: None,
            variants: vec![CandidateVariant {
                label: "カタカナ".into(),
                is_available: true,
            }],
            selected_variant: None,
            entries: vec![
                CandidateEntry {
                    text: "変換".into(),
                    annotation: None,
                    corrected_start: None,
                    corrected_length: None,
                    command: None,
                    has_comment: None,
                    detail: None,
                },
                CandidateEntry {
                    text: "へんかん".into(),
                    annotation: Some("入力のまま".into()),
                    corrected_start: None,
                    corrected_length: None,
                    command: None,
                    has_comment: None,
                    detail: None,
                },
            ],
            selected_entry: selected,
            focus: CandidateFocus::Candidate,
            position: 2,
            total: 30,
            note: None,
            meaning_placement: None,
            column_length: None,
            hints: Some(vec![hint("↑", "文字種")]),
        }
    }

    /// 「缶1」〜「缶20」を 1 列 9 個の表に広げ，2 列目の 2 番目(缶11)を選んだ一覧
    fn grid() -> CandidateList {
        let mut list = list(Some(10));
        list.entries = (1..=20)
            .map(|number| CandidateEntry {
                text: format!("缶{number}"),
                annotation: None,
                corrected_start: None,
                corrected_length: None,
                command: None,
                has_comment: None,
                detail: None,
            })
            .collect();
        list.column_length = Some(9);
        list.position = 11;
        list.total = 20;
        list.hints = Some(vec![hint("←→", "列"), hint("Alt+↓", "戻す")]);
        list
    }

    #[test]
    fn 表に広げた一覧は上から下へ詰めて列を左から右へ並べ_押した位置の候補を選ぶ() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let scene = candidate_list(&grid(), &Look::new(&theme, 15.0), &Fixed);
            let frame = |text: &str| text_frame(&scene, text).expect("描いた文字がある");
            // 同じ行の列は同じ高さ，同じ列の候補は同じ x
            assert_eq!(frame("缶1").y, frame("缶10").y);
            assert_eq!(frame("缶10").y, frame("缶19").y);
            assert!(frame("缶1").x < frame("缶10").x && frame("缶10").x < frame("缶19").x);
            assert_eq!(frame("缶10").x, frame("缶18").x);
            assert!(frame("缶9").y > frame("缶1").y);
            let at = |text: &str| {
                let found = frame(text);
                scene.target_at(found.x + 1.0, found.mid_y())
            };
            assert_eq!(at("缶12"), Some(ipc::PointerTarget::Entry { index: 11 }));
            assert_eq!(at("缶20"), Some(ipc::PointerTarget::Entry { index: 19 }));
        }
    }

    #[test]
    fn 表では選んでいる列にだけ番号を振る() {
        let shown = grid();
        assert_eq!(entry_number(&shown, 9), Some(1));
        assert_eq!(entry_number(&shown, 17), Some(9));
        assert_eq!(entry_number(&shown, 0), None);
        assert_eq!(entry_number(&shown, 18), None);
        // 字種の行にいるときは先頭の列
        let mut variants = grid();
        variants.focus = CandidateFocus::Variants;
        variants.selected_entry = None;
        assert_eq!(entry_number(&variants, 0), Some(1));
        assert_eq!(entry_number(&variants, 9), None);
        // 広げていない一覧はすべてに振る
        assert_eq!(entry_number(&list(Some(0)), 1), Some(2));
        // platinum の番号の文字は 2 列目の 9 個だけ
        let scene = candidate_list(&grid(), &Look::new(&theme("platinum"), 15.0), &Fixed);
        let numbers: Vec<String> = texts(&scene)
            .into_iter()
            .map(|(text, _)| text)
            .filter(|text| text.parse::<u32>().is_ok())
            .collect();
        assert_eq!(numbers, (1..=9).map(|n| n.to_string()).collect::<Vec<_>>());
    }

    fn hint(keys: &str, label: &str) -> KeyHint {
        KeyHint {
            keys: keys.into(),
            label: label.into(),
        }
    }

    #[test]
    fn 押した位置から行と字種を引く_描いた文字の位置と合う() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let scene = candidate_list(&list(Some(0)), &Look::new(&theme, 15.0), &Fixed);
            let at = |text: &str| {
                let frame = text_frame(&scene, text).expect("描いた文字がある");
                scene.target_at(frame.x + 1.0, frame.mid_y())
            };
            assert_eq!(at("へんかん"), Some(ipc::PointerTarget::Entry { index: 1 }));
            assert_eq!(
                at("カタカナ"),
                Some(ipc::PointerTarget::ListVariant { index: 0 })
            );
            // 使えない字種は押せない
            let mut unavailable = list(Some(0));
            unavailable.variants[0].is_available = false;
            let scene = candidate_list(&unavailable, &Look::new(&theme, 15.0), &Fixed);
            let frame = text_frame(&scene, "カタカナ").expect("描いた文字がある");
            assert_eq!(scene.target_at(frame.x + 1.0, frame.mid_y()), None);
        }
    }

    #[test]
    fn コメントの札を押すとコメント_札の外の行と_コメントでない札は候補() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut commented = list(Some(0));
            commented.entries[0].annotation = Some("千代田区千代田1-1".into());
            commented.entries[0].has_comment = Some(true);
            let scene = candidate_list(&commented, &Look::new(&theme, 15.0), &Fixed);
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
            // 札の上下の空きも，行の高さいっぱいまで札として押せる
            let row = hit(ipc::PointerTarget::Entry { index: 0 }).expect("候補の行");
            let area = hit(comment.clone()).expect("札を押せる範囲");
            assert_eq!((area.y, area.height), (row.y, row.height), "{name}");
            assert_eq!(scene.target_at(tag.mid_x(), row.y + 1.0), Some(comment));
            // 札の左(候補の文字の側)は候補
            assert_eq!(
                scene.target_at(area.x - 1.0, row.mid_y()),
                Some(ipc::PointerTarget::Entry { index: 0 })
            );
            let text = text_frame(&scene, "変換").expect("描いた文字がある");
            assert_eq!(
                scene.target_at(text.x + 1.0, text.mid_y()),
                Some(ipc::PointerTarget::Entry { index: 0 })
            );
            // コメントでない札(入力のまま)は押しても候補
            let plain = text_frame(&scene, "入力のまま").expect("札を描く");
            assert_eq!(
                scene.target_at(plain.mid_x(), plain.mid_y()),
                Some(ipc::PointerTarget::Entry { index: 1 })
            );
        }
        // コメントの無い一覧には札の押せる範囲を足さない
        let theme = theme("automatic");
        let scene = candidate_list(&list(Some(0)), &Look::new(&theme, 15.0), &Fixed);
        assert!(!scene
            .hits
            .iter()
            .any(|hit| matches!(hit.target, ipc::PointerTarget::Comment { .. })));
    }

    #[test]
    fn 連想の一覧は文字種の行の代わりに見出しを出し_足元に連想の知らせを出す() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut associated = list(Some(0));
            associated.association = Some(ipc::AssociationHeading {
                headword: "速い".into(),
                label: "速度".into(),
                group: 1,
                group_count: 3,
            });
            let scene = candidate_list(&associated, &Look::new(&theme, 15.0), &Fixed);
            let texts: Vec<String> = texts(&scene).into_iter().map(|(text, _)| text).collect();
            assert!(texts.contains(&"速い".to_string()));
            assert!(texts.contains(&"1 / 3".to_string()));
            assert!(!texts.contains(&"カタカナ".to_string()));
            // 連想変換のキーは文字ではなくキーキャップで描き，語だけを文字にする
            let mut hinted = list(Some(0));
            hinted.association_hint = Some("連想".into());
            hinted.association_key = Some("Ctrl+Tab".into());
            let scene = candidate_list(&hinted, &Look::new(&theme, 15.0), &Fixed);
            let hinted_texts = texts_of(&scene);
            assert!(hinted_texts.contains(&"連想".to_string()));
            assert!(!hinted_texts.iter().any(|text| text.contains("Tab")));
            // キーが割り当てられていなければ語だけ
            hinted.association_key = None;
            let scene = candidate_list(&hinted, &Look::new(&theme, 15.0), &Fixed);
            assert!(texts_of(&scene).contains(&"連想".to_string()));
        }
    }

    fn homophone() -> ipc::HomophoneNote {
        ipc::HomophoneNote {
            word: "変換".into(),
            senses: vec![ipc::HomophoneSense {
                meaning: "別の形に変える".into(),
                example: Some("かなを漢字に変換する".into()),
            }],
            others: vec!["返還".into(), "偏官".into()],
            part_of_speech: Some(ipc::PartOfSpeech::Noun),
        }
    }

    fn with_meaning(placement: MeaningPlacement) -> CandidateList {
        CandidateList {
            homophone: Some(homophone()),
            meaning_placement: Some(placement),
            ..list(Some(0))
        }
    }

    /// 描いた多角形(一覧のカードが選んでいる候補を指す三角)
    fn polygons(scene: &Scene) -> Vec<Vec<Point>> {
        scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Polygon { points, .. } => Some(points.clone()),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn 語の意味は候補の右のカードにし_選んでいる候補を三角で指す() {
        for name in ["platinum", "automatic", "desk"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let scene = candidate_list(&with_meaning(MeaningPlacement::Side), &look, &Fixed);
            let texts = texts_of(&scene);
            for text in ["変換", "名詞", "別の形に変える", "同音語", "返還", "偏官"]
            {
                assert!(texts.contains(&text.to_string()), "{name}: {text}");
            }
            // 足元のキーの案内は消さない
            assert!(texts.contains(&"2 / 30".to_string()), "{name}");
            // カードは候補の列の右に置き，候補の行はカードにかからない
            let meaning = text_frame(&scene, "別の形に変える").expect("意味を描く");
            let candidate = text_frame(&scene, "へんかん").expect("候補を描く");
            assert!(meaning.x > candidate.max_x(), "{name}");
            let row = scene
                .hits
                .iter()
                .find(|hit| hit.target == ipc::PointerTarget::Entry { index: 0 })
                .map(|hit| hit.frame)
                .expect("候補の行");
            assert!(row.max_x() + glass::MEANING_GAP <= meaning.x, "{name}");
            // 三角は選んでいる候補の行の高さを指す(カードの角にかからない範囲で)
            let pointers = polygons(&scene);
            assert_eq!(pointers.len(), 1, "{name}");
            assert!(
                (pointers[0][1].y - row.mid_y()).abs()
                    <= glass::MEANING_RADIUS + glass::MEANING_NOTCH,
                "{name}"
            );
            assert!(pointers[0][1].x < meaning.x, "{name}");
            // 意味の無い一覧より広い
            let plain = candidate_list(&list(Some(0)), &look, &Fixed);
            assert!(
                scene.width >= plain.width + glass::MEANING_CARD_WIDTH,
                "{name}"
            );
        }
    }

    #[test]
    fn 文字種の行を選んでいるあいだは三角で指さない() {
        let theme = theme("automatic");
        let mut variants = with_meaning(MeaningPlacement::Side);
        variants.focus = CandidateFocus::Variants;
        variants.selected_variant = Some(0);
        let scene = candidate_list(&variants, &Look::new(&theme, 15.0), &Fixed);
        assert!(polygons(&scene).is_empty());
        assert!(texts_of(&scene).contains(&"別の形に変える".to_string()));
    }

    #[test]
    fn 長い意味はカードの幅で折り返し_候補を窓の幅の上限に収める() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let mut long = with_meaning(MeaningPlacement::Side);
            if let Some(note) = long.homophone.as_mut() {
                note.senses[0].meaning = "意".repeat(200);
                note.others = (0..30).map(|index| format!("語{index}")).collect();
            }
            long.entries[1].text = "長".repeat(80);
            let scene = candidate_list(&long, &look, &Fixed);
            let texts = texts_of(&scene);
            let lines = texts.iter().filter(|text| text.starts_with('意')).count();
            assert_eq!(lines, glass::MEANING_MEANING_LINES as usize, "{name}");
            assert!(texts
                .iter()
                .any(|text| text.starts_with('意') && text.ends_with('…')));
            assert!(texts.iter().any(|text| text.starts_with('+')));
            // 長い候補は省き，カードを含めて窓の幅の上限に収める
            assert!(texts
                .iter()
                .any(|text| text.starts_with('長') && text.ends_with('…')));
            assert!(
                scene.width <= candidate::MAX_WIDTH + 1.0,
                "{name}: {}",
                scene.width
            );
            for draw in &scene.draws {
                if let Draw::Text { frame, .. } = draw {
                    assert!(
                        frame.x >= 0.0 && frame.max_x() <= scene.body.max_x(),
                        "{name}: {draw:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn 候補の下に出す設定では候補と足元のあいだに窓の幅いっぱいのカードを出す() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let scene = candidate_list(&with_meaning(MeaningPlacement::Below), &look, &Fixed);
            let meaning = text_frame(&scene, "別の形に変える").expect("意味を描く");
            let last = text_frame(&scene, "へんかん").expect("候補を描く");
            let footer = text_frame(&scene, "2 / 30").expect("足元を描く");
            assert!(
                meaning.y > last.max_y() && meaning.max_y() < footer.y,
                "{name}"
            );
            // 三角で指さない
            assert!(polygons(&scene).is_empty(), "{name}");
            // 窓の幅はカードの幅に合わせて広げる
            assert!(scene.width >= glass::MEANING_CARD_WIDTH + glass::MEANING_PADDING * 2.0);
            let plain = candidate_list(&list(Some(0)), &look, &Fixed);
            assert!(scene.height > plain.height, "{name}");
        }
    }

    #[test]
    fn 意味の無い候補に移っても空けておいたカードで窓の大きさを変えない() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let mut reservation = crate::scene::CardReservation::default();
            let shown = with_meaning(MeaningPlacement::Side);
            let first = candidate_list(
                &shown,
                &Look {
                    reserved_card: reservation.list(&shown, &look, &Fixed),
                    ..look
                },
                &Fixed,
            );
            let moved = CandidateList {
                homophone: None,
                meaning_placement: None,
                selected_entry: Some(1),
                ..list(Some(1))
            };
            let reserved = reservation.list(&moved, &look, &Fixed);
            assert!(reserved.is_some(), "{name}");
            let empty = candidate_list(
                &moved,
                &Look {
                    reserved_card: reserved,
                    ..look
                },
                &Fixed,
            );
            assert_eq!(
                (empty.width, empty.height),
                (first.width, first.height),
                "{name}"
            );
            assert!(!texts_of(&empty).contains(&"別の形に変える".to_string()));
            assert!(empty.draws.iter().any(|draw| matches!(
                draw,
                Draw::Icon {
                    icon: crate::keys::Icon::Book,
                    ..
                }
            )));
            // 空けておかなければカードを出さない
            let bare = candidate_list(&moved, &look, &Fixed);
            assert!(bare.width < empty.width, "{name}");
        }
    }

    #[test]
    fn 意味が2つ以上なら角丸の四角に番号を入れる() {
        let theme = theme("automatic");
        let look = Look::new(&theme, 15.0);
        let mut two = with_meaning(MeaningPlacement::Side);
        if let Some(note) = two.homophone.as_mut() {
            note.senses.push(ipc::HomophoneSense {
                meaning: "向きを変える".into(),
                example: None,
            });
        }
        let single = candidate_list(&with_meaning(MeaningPlacement::Side), &look, &Fixed);
        let double = candidate_list(&two, &look, &Fixed);
        let texts = texts_of(&double);
        assert!(texts.contains(&"向きを変える".to_string()));
        let badges = double
            .draws
            .iter()
            .filter(|draw| matches!(draw, Draw::RoundRect { radius, .. } if *radius == glass::MEANING_BADGE_RADIUS))
            .count();
        assert_eq!(badges, 2);
        assert!(double.height >= single.height);
        // 意味が 1 つなら番号の四角を描かない
        assert!(!single.draws.iter().any(|draw| matches!(draw, Draw::RoundRect { radius, .. } if *radius == glass::MEANING_BADGE_RADIUS)));
    }

    fn texts_of(scene: &Scene) -> Vec<String> {
        texts(scene).into_iter().map(|(text, _)| text).collect()
    }

    #[test]
    fn 番号キーで選べない窓は番号を振らず_文字種の行が無ければ文字種の案内を出さない() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let numbered = texts_of(&candidate_list(&list(Some(0)), &look, &Fixed));
            assert!(numbered.contains(&"1".to_string()));
            assert!(numbered.contains(&"文字種".to_string()));
            let mut browsing = list(None);
            browsing.shows_numbers = Some(false);
            browsing.variants.clear();
            // 文字種の行が無い一覧には，エンジンが文字種の案内を送らない(FooterHints)
            browsing.hints = None;
            let scene = candidate_list(&browsing, &look, &Fixed);
            let texts = texts_of(&scene);
            assert!(texts.contains(&"変換".to_string()));
            assert!(!texts.contains(&"1".to_string()));
            assert!(!texts.contains(&"2".to_string()));
            assert!(!texts.contains(&"文字種".to_string()));
            // 番号を振らなくても，候補の文字の位置は変えない
            let natural = candidate_list(&list(None), &look, &Fixed);
            assert_eq!(
                text_frame(&scene, "変換").map(|frame| frame.x),
                text_frame(&natural, "変換").map(|frame| frame.x)
            );
        }
    }

    #[test]
    fn 選んだ行を選択の色にする() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let scene = candidate_list(&list(Some(1)), &Look::new(&theme, 15.0), &Fixed);
            let texts = texts(&scene);
            assert!(texts.contains(&("変換".into(), theme.text)));
            assert!(texts.contains(&("へんかん".into(), theme.selection_text)));
            assert!(texts.contains(&("入力のまま".into(), theme.selection_text)));
            assert!(texts.contains(&("2 / 30".into(), theme.text_muted)));
            assert!(scene.width >= candidate::MIN_WIDTH);
        }
    }

    #[test]
    fn 絵文字の名前は候補の文字のすぐあとに薄い色で添え_窓をその分広げる() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut emoji = list(Some(0));
            emoji.entries.push(CandidateEntry {
                text: "😄".into(),
                annotation: None,
                corrected_start: None,
                corrected_length: None,
                command: None,
                has_comment: None,
                detail: Some("笑顔".into()),
            });
            let plain = candidate_list(&list(Some(0)), &Look::new(&theme, 15.0), &Fixed);
            let scene = candidate_list(&emoji, &Look::new(&theme, 15.0), &Fixed);
            let text = text_frame(&scene, "😄").unwrap();
            let detail = text_frame(&scene, "笑顔").unwrap();
            assert_eq!(detail.x, (text.x + 10.0 + candidate::DETAIL_GAP).round());
            assert!(texts(&scene).contains(&("笑顔".into(), theme.text_muted)));
            assert!(scene.width >= plain.width);
        }
    }

    #[test]
    fn コマンドの候補は種類のアイコンを文字の前に置き_札をアクセントの色にする() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut commands = list(Some(0));
            commands.entries.push(CandidateEntry {
                text: "Claude を開く".into(),
                annotation: Some(strings::COMMAND.into()),
                corrected_start: None,
                corrected_length: None,
                command: Some(ipc::CommandKind::OpenApplication),
                has_comment: None,
                detail: None,
            });
            let plain = candidate_list(&list(Some(0)), &Look::new(&theme, 15.0), &Fixed);
            let scene = candidate_list(&commands, &Look::new(&theme, 15.0), &Fixed);
            let icon = scene.draws.iter().find_map(|draw| match draw {
                Draw::Icon {
                    icon, frame, color, ..
                } if *icon == crate::keys::Icon::Window => Some((*frame, *color)),
                _ => None,
            });
            let (icon, color) = icon.expect("種類のアイコンを描く");
            assert_eq!(color, theme.selection);
            // 文字はアイコンの右から書き，ほかの行の文字より右に寄る
            let title = text_frame(&scene, "Claude を開く").unwrap();
            assert!(title.x >= icon.max_x());
            assert!(title.x > text_frame(&scene, "変換").unwrap().x);
            assert!(texts(&scene).contains(&(strings::COMMAND.into(), theme.selection)));
            // アイコンの幅だけ窓を広げる
            assert!(scene.width > plain.width);
        }
    }

    #[test]
    fn 選んでいるコマンドの候補は_アイコンと札を選択の文字の色にする() {
        let theme = theme("automatic");
        let mut commands = list(Some(2));
        commands.entries.push(CandidateEntry {
            text: "サイト".into(),
            annotation: Some(strings::COMMAND.into()),
            corrected_start: None,
            corrected_length: None,
            command: Some(ipc::CommandKind::OpenURL),
            has_comment: None,
            detail: None,
        });
        let scene = candidate_list(&commands, &Look::new(&theme, 15.0), &Fixed);
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::Icon { icon: crate::keys::Icon::Globe, color, .. } if *color == theme.selection_text)));
        assert!(texts(&scene).contains(&(strings::COMMAND.into(), theme.selection_text)));
    }

    #[test]
    fn 候補の中の直した語句に補正の点線を引く() {
        let theme = theme("automatic");
        let mut corrected = list(None);
        corrected.entries[0] = CandidateEntry {
            text: "今日は良い".into(),
            annotation: None,
            corrected_start: Some(3),
            corrected_length: Some(2),
            command: None,
            has_comment: None,
            detail: None,
        };
        let scene = candidate_list(&corrected, &Look::new(&theme, 15.0), &Fixed);
        let lines: Vec<(f32, f32)> = scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Line {
                    from,
                    to,
                    color,
                    dot_pitch: Some(_),
                    ..
                } if *color == theme.correction => Some((from.x, to.x)),
                _ => None,
            })
            .collect();
        assert_eq!(lines.len(), 1);
        // 「良い」の 2 文字の幅(Fixed は 1 文字 10)
        assert_eq!(lines[0].1 - lines[0].0, 20.0);
        assert!(candidate_list(&list(None), &Look::new(&theme, 15.0), &Fixed)
            .draws
            .iter()
            .all(|draw| !matches!(draw, Draw::Line { color, dot_pitch: Some(_), .. } if *color == theme.correction)));
    }

    #[test]
    fn 高さは行の数で決まる() {
        let theme = theme("platinum");
        let look = Look::new(&theme, 15.0);
        let two = candidate_list(&list(None), &look, &Fixed);
        let mut longer = list(None);
        longer.entries.push(CandidateEntry {
            text: "返還".into(),
            annotation: None,
            corrected_start: None,
            corrected_length: None,
            command: None,
            has_comment: None,
            detail: None,
        });
        let three = candidate_list(&longer, &look, &Fixed);
        assert_eq!(three.height - two.height, (candidate::ROW_HEIGHT).round());
    }

    #[test]
    fn 角丸のテーマは番号を丸に入れ_選択を角丸にする() {
        let theme = theme("washi");
        let scene = candidate_list(&list(Some(0)), &Look::new(&theme, 15.0), &Fixed);
        assert_eq!(
            count(&scene, |draw| matches!(draw, Draw::Ellipse { .. })),
            2
        );
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::RoundRect { radius, fill: Some(color), .. } if *radius == glass::SELECTION_RADIUS && *color == theme.selection)));
        // 足元の案内はキーキャップ(↑ のアイコン)と説明
        assert!(scene.draws.iter().any(|draw| matches!(
            draw,
            Draw::Icon {
                icon: crate::keys::Icon::Up,
                ..
            }
        )));
        assert!(texts(&scene).iter().any(|(text, _)| text == "文字種"));
    }

    #[test]
    fn 出した直後は第_1_候補と選んだ候補のほかを薄くする() {
        let theme = theme("nordic");
        let mut look = Look::new(&theme, 15.0);
        look.rest_opacity = 0.0;
        let mut three = list(Some(2));
        three.entries.push(CandidateEntry {
            text: "返還".into(),
            annotation: None,
            corrected_start: None,
            corrected_length: None,
            command: None,
            has_comment: None,
            detail: None,
        });
        three.entries.push(CandidateEntry {
            text: "偏官".into(),
            annotation: None,
            corrected_start: None,
            corrected_length: None,
            command: None,
            has_comment: None,
            detail: None,
        });
        let texts = texts(&candidate_list(&three, &look, &Fixed));
        let alpha = |wanted: &str| {
            texts
                .iter()
                .find(|(text, _)| text == wanted)
                .map(|(_, color)| color.alpha)
        };
        assert_eq!(alpha("変換"), Some(1.0));
        assert_eq!(alpha("へんかん"), Some(0.0));
        assert_eq!(alpha("返還"), Some(1.0));
    }

    #[test]
    fn 文字種の行を選んでいるときは位置と案内を変える() {
        let theme = theme("automatic");
        let mut variants = list(None);
        variants.focus = CandidateFocus::Variants;
        variants.selected_variant = Some(0);
        variants.hints = Some(vec![hint("←→", "選択"), hint("Space", "候補")]);
        let scene = candidate_list(&variants, &Look::new(&theme, 15.0), &Fixed);
        let texts = texts(&scene);
        assert!(texts.contains(&("文字種 1 / 1".into(), theme.text_muted)));
        assert!(texts.contains(&("カタカナ".into(), theme.selection_text)));
        assert!(texts.iter().any(|(text, _)| text == "選択"));
    }

    #[test]
    fn 知らせがあれば案内の代わりに出す() {
        let theme = theme("platinum");
        let mut noted = list(Some(0));
        noted.note = Some(ipc::Note {
            tone: ipc::NoteTone::Correction,
            title: "修正".into(),
            subject: None,
            key: Some("Space".into()),
            key_action: Some("入力のままに戻す".into()),
            text: "修正　Space 入力のままに戻す".into(),
        });
        let scene = candidate_list(&noted, &Look::new(&theme, 15.0), &Fixed);
        // 主な語は補正の色，キーでできることはキーの案内と同じ控えめな色
        assert!(texts(&scene).contains(&("修正".into(), theme.correction)));
        assert!(texts(&scene).contains(&("入力のままに戻す".into(), theme.text_muted)));
        assert!(!texts(&scene).iter().any(|(text, _)| text == "文字種"));
    }

    #[test]
    fn desk_は右と下に影の分だけ大きくする() {
        let desk = theme("desk");
        let platinum = theme("platinum");
        let a = candidate_list(&list(None), &Look::new(&desk, 15.0), &Fixed);
        let b = candidate_list(&list(None), &Look::new(&platinum, 15.0), &Fixed);
        assert_eq!(a.width - b.width, candidate::SHADOW_OFFSET);
        assert!(
            matches!(a.draws[0], Draw::Rect { frame, .. } if frame.x == candidate::SHADOW_OFFSET)
        );
    }
}
