#![forbid(unsafe_code)]

//! 候補の一覧(macOS の CandidateView)．上から，文字種の行・候補・足元の 3 つの区画．
//! 語の意味のカードは，候補の右(候補の列と同じ高さ)か，候補と足元のあいだに出す

use super::card_layout::{self, Placement};
use super::list_layout::{self, ListLayout, Style};
use super::meaning;
use super::paint::{Painter, TagStyle};
use super::{Frame, Look, Measure, Point, Scene};
use crate::strings;
use crate::theme::Font;
use ipc::{CandidateFocus, CandidateList, KeyHint, MeaningPlacement};
use tokens::opacity;
use tokens::size::meaning as card_size;
use tokens::size::{branch, candidate, glass, part};

/// 区画の寸法(list_layout)と，行の中の寸法
struct Metrics {
    layout: list_layout::Metrics,
    style: Style,
    /// 行の背景の内側の左右の余白．番号の丸(番号)の左と注釈のタグの右，足元の案内と位置の左右の端をここにそろえる
    row_padding_x: f32,
    /// 番号の幅(番号から候補の文字まで)
    lead: f32,
}

impl Metrics {
    fn new(look: &Look, measure: &dyn Measure) -> Self {
        let rounded = look.theme.is_rounded();
        let scale = look.font_size / candidate::FONT_SIZE;
        let label = measure.height(Font::Label).ceil();
        if rounded {
            // 足元の行は，キーキャップ・案内のアイコン・文字の行の箱のいちばん高いもの
            let footer = glass::KEYCAP_HEIGHT.max(glass::NOTE_ICON_SIZE).max(label);
            Self {
                layout: list_layout::Metrics::rounded(
                    (glass::ROW_HEIGHT * scale).round(),
                    glass::HEADER_HEIGHT,
                    footer,
                ),
                style: Style::Rounded,
                row_padding_x: glass::ROW_PADDING_X,
                lead: glass::BADGE_SIZE + glass::BADGE_GAP,
            }
        } else {
            // 文字種の行と足元の行は，角丸のテーマと同じく文字・キー・案内のアイコンのいちばん高いもの
            let section = label.max(glass::KEYCAP_HEIGHT).max(glass::NOTE_ICON_SIZE);
            Self {
                layout: list_layout::Metrics::bevel(
                    (candidate::ROW_HEIGHT * scale).round(),
                    section.max(glass::HEADER_HEIGHT),
                    section,
                    look.theme.has_drop_shadow(),
                ),
                style: Style::Bevel,
                row_padding_x: part::ROW_PADDING_X,
                lead: candidate::INDEX_WIDTH,
            }
        }
    }
}

struct Footer {
    hints: Vec<KeyHint>,
    note: Option<ipc::Note>,
    position: String,
    /// 選んでいる候補に連想があることの知らせ(R-18)のうち，キーの割り当てが無いときの語．
    /// キーがあればキーキャップとして hints に入れる(キーを文字で書かない)
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

/// 語の意味の上と下に足す余白．区切りの線の上下の空き(separator_gap)で取るので足さない
fn section_padding(_metrics: &Metrics) -> f32 {
    0.0
}

/// 候補の下の語の意味の置き方．目印の列を候補の番号に，文の列を候補の文字にそろえる
fn below_position(metrics: &Metrics, theme: &crate::theme::ResolvedTheme) -> Placement {
    Placement {
        left: metrics.row_padding_x + metrics.lead
            - card_size::MARKER_WIDTH
            - card_size::MARKER_GAP,
        header_mid_y: section_padding(metrics) + card_layout::header_height(theme) / 2.0,
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

/// index 番目の候補の番号の列に出す番号と，番号キーで選べるか．
/// 番号の列を取る窓では，選べない番号(表のほかの列，選び始める前の入力中の候補の窓)も薄く出し，列を空に見せない
fn shown_number(list: &CandidateList, index: usize) -> (usize, bool) {
    match entry_number(list, index) {
        Some(number) => (number, true),
        None => (
            column_length(list).map_or(index + 1, |length| index % length + 1),
            false,
        ),
    }
}

/// 表の列と列のあいだ(区切りの縦の線と，その左と右の空き)
fn column_gutter() -> f32 {
    candidate::COLUMN_GAP * 2.0 + candidate::FRAME_WIDTH
}

pub fn candidate_list(list: &CandidateList, look: &Look, measure: &dyn Measure) -> Scene {
    let metrics = Metrics::new(look, measure);
    let mut painter = Painter::new(look, measure);
    let padding = candidate::PADDING_X;
    let footer = footer(list);

    // 候補の右に出す設定の語の意味は，窓の外の吹き出し(bubble)に出す．窓の中に出すのは候補の下に出す設定だけ
    let outer = (metrics.layout.edge + metrics.layout.padding) * 2.0 + metrics.layout.shadow;

    // 表に広げたときは列の幅をそろえ，窓が表の幅の上限に収まるよう列を狭める(収まらない候補は末尾を省く)
    let grid = column_length(list);
    let columns = column_count(list) as f32;
    let cell_limit = grid.map(|_| {
        ((candidate::GRID_MAX_WIDTH - outer - column_gutter() * (columns - 1.0)) / columns).floor()
    });
    // 長い文の候補は，窓の幅の上限に収まるよう省く．ほかの候補と違うところの少し手前から見せる
    // (頭が同じ文が並ぶので，末尾を省くと見分けられない．macOS の CandidateView と同じ)
    let text_limit = cell_limit.unwrap_or(candidate::MAX_WIDTH - outer)
        - metrics.lead
        - metrics.row_padding_x
        - candidate::PADDING_X;
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
    let association_hint = footer.association_hint.as_deref().map_or(0.0, |hint| {
        painter.width(hint, Font::Label) + glass::HINT_GAP
    });
    let footer_width = if look.shows_footer {
        (hints_width
            + association_hint
            + painter.width(&footer.position, Font::Label)
            + metrics.row_padding_x * 2.0
            + glass::HINT_GAP)
            .ceil()
    } else {
        0.0
    };
    let heading_width = list.association.as_ref().map_or(0.0, |heading| {
        super::association::width(&painter, heading) + metrics.row_padding_x * 2.0
    });
    // 候補 1 つの行の背景の幅: 左の余白・番号・文字・右の余白(文字の右は番号の左より広く空ける)．
    // 表では文字が収まる幅を切り上げ，上限から割った幅を超えない(列の位置を整数にそろえる)
    let natural_cell = (metrics.row_padding_x + metrics.lead + entry_width + padding).ceil();
    let cell_width = cell_limit.map_or(natural_cell, |limit| natural_cell.min(limit));
    // 候補の列(行の背景)の幅．表なら，すべての列と列のあいだの線を合わせた幅
    let list_width = candidate::MIN_WIDTH
        .max(cell_width * columns + column_gutter() * (columns - 1.0))
        .max(variants_width + (metrics.row_padding_x - candidate::VARIANT_PADDING_X) * 2.0)
        .max(heading_width)
        .ceil();
    // 候補を縦に並べる行の数．表なら 1 列の候補の数(最後のページで候補が少なければその数)
    let rows = grid.map_or(list.entries.len(), |length| list.entries.len().min(length));
    let limit = candidate::MAX_WIDTH.max(candidate::MIN_WIDTH);
    // 候補の下の語の意味は窓の中身の幅いっぱいにし，その幅で折り返す
    let below = (list.meaning_placement == Some(MeaningPlacement::Below))
        .then_some(list.homophone.as_ref())
        .flatten();
    let slot = below.map(|note| {
        let width = list_layout::below_card_width(list_width, footer_width, card_size::LIST_WIDTH)
            .min(limit - outer)
            .floor();
        let position = below_position(&metrics, look.theme);
        meaning::below_slot(
            meaning::Card::new(&painter, note, note.others.clone(), width, position),
            section_padding(&metrics),
        )
    });
    let card = slot.as_ref().map(|slot| list_layout::Card::Below {
        width: slot.width,
        height: slot.height,
    });
    let has_header = !list.variants.is_empty() || list.association.is_some();
    let layout = list_layout::place(
        metrics.style,
        list_width,
        footer_width,
        has_header,
        rows,
        card,
        limit,
        &metrics.layout,
        look.size,
        look.shows_footer,
    );
    let cells = cells(list, &layout, cell_width);
    draw_list(
        &mut painter,
        list,
        &footer,
        &shown,
        &metrics,
        &layout,
        &cells,
        slot.as_ref(),
        look.rest_opacity,
    );
    painter.finish(layout.width, layout.height)
}

/// 候補ごとの行の背景と押せる範囲，表の列のあいだの縦の線
struct Cells {
    rows: Vec<Frame>,
    hit_rows: Vec<Frame>,
    separators: Vec<Frame>,
}

/// 候補ごとの枠．表では上から下へ詰め，列を左から右へ並べる．列のあいだは 1 ドットの縦の線で区切る．
/// 表でなければ，配置の候補の行をそのまま使う(macOS の CandidateView.cells と同じ)
fn cells(list: &CandidateList, layout: &ListLayout, cell_width: f32) -> Cells {
    let (Some(length), Some(first), Some(last)) =
        (column_length(list), layout.rows.first(), layout.rows.last())
    else {
        return Cells {
            rows: layout.rows.clone(),
            hit_rows: layout.hit_rows.clone(),
            separators: Vec::new(),
        };
    };
    let columns = column_count(list);
    let gutter = column_gutter();
    let cell =
        cell_width.min(((first.width - gutter * (columns - 1) as f32) / columns as f32).floor());
    let x = |column: usize| first.x + column as f32 * (cell + gutter);
    let place = |row: Frame, index: usize| Frame::new(x(index / length), row.y, cell, row.height);
    Cells {
        rows: (0..list.entries.len())
            .map(|index| place(layout.rows[index % length], index))
            .collect(),
        hit_rows: (0..list.entries.len())
            .map(|index| place(layout.hit_rows[index % length], index))
            .collect(),
        // 縦の線は列と列のあいだの真ん中．左と右の空きは同じ(COLUMN_GAP)で，選んでいる行の背景は線に触れない．
        // 縦は行の背景の上の端から下の端まで(角丸のテーマは行と行のあいだの空きの分だけ短くなる)
        separators: (1..columns)
            .map(|column| {
                Frame::new(
                    x(column) - candidate::COLUMN_GAP - candidate::FRAME_WIDTH,
                    first.y,
                    candidate::FRAME_WIDTH,
                    last.max_y() - first.y,
                )
            })
            .collect(),
    }
}

/// 区画の配置のとおりに描く．rest_opacity は第 1 候補と選んでいる候補以外の濃さ
#[allow(clippy::too_many_arguments)]
fn draw_list(
    painter: &mut Painter,
    list: &CandidateList,
    footer: &Footer,
    shown: &[String],
    metrics: &Metrics,
    layout: &ListLayout,
    cells: &Cells,
    slot: Option<&meaning::Slot>,
    rest_opacity: f32,
) {
    let theme = painter.theme;
    painter.panel(layout.body);
    if let Some(header) = layout.header {
        match &list.association {
            Some(heading) => {
                super::association::draw(painter, heading, header.inset(metrics.row_padding_x, 0.0))
            }
            None => variants(painter, list, header, metrics.row_padding_x),
        }
    }
    if let Some(line) = layout.header_separator {
        painter.rect(line, theme.line);
    }
    for separator in &cells.separators {
        painter.rect(*separator, theme.line);
    }
    // 行ごとの文字の範囲(番号から文字の終わりまで)と右に寄せたタグの範囲．吹き出しを窓の中に置くときに使う
    let mut contents: Vec<(Frame, Option<Frame>)> = Vec::with_capacity(list.entries.len());
    for (index, entry) in list.entries.iter().enumerate() {
        let row = cells.rows[index];
        // コメントのタグは行の中にあるので，行より先に足す(押した位置は先に足した範囲から引く)．
        // タグを押すと候補の代わりにコメントを入れる
        if let Some(comment) = super::entry_comment(entry) {
            // 押せる範囲は，候補の行と同じく行と行のあいだまで
            let frame =
                painter.tag_hit_frame(comment, tag_max_x(row, metrics), cells.hit_rows[index]);
            painter.hit(
                frame,
                ipc::PointerTarget::Comment {
                    index: index as u32,
                },
            );
        }
        painter.hit(
            cells.hit_rows[index],
            ipc::PointerTarget::Entry {
                index: index as u32,
            },
        );
        let selected =
            list.focus == CandidateFocus::Candidate && list.selected_entry == Some(index as u32);
        if selected {
            if theme.is_rounded() {
                painter.capsule(row, theme.selection);
            } else {
                painter.rect(row, theme.selection);
            }
        }
        // 出した直後は，第 1 候補と選んでいる候補だけを濃く出す
        // 文節を打ち直しているあいだ(⇧⌫)の候補は打ち直す前のものなので薄く出す(候補は変換したときに出し直す)
        let opacity = if list.is_editing == Some(true) {
            tokens::opacity::candidate::EDITING_STALE
        } else if selected || index == 0 {
            1.0
        } else {
            rest_opacity
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
        // 表では選んでいる列の番号だけを番号キーで選べる．ほかの列と，選び始める前の入力中の候補の窓の番号は薄く出し，
        // どの列も番号の列から始まるように見せる(列を移っても，選び始めても文字は動かない)
        let (number, selectable) = shown_number(list, index);
        let number = number.to_string();
        let number_opacity = if selectable {
            opacity
        } else {
            opacity * tokens::opacity::candidate::UNSELECTABLE_NUMBER
        };
        let number_x = row.x + metrics.row_padding_x;
        let mut text_x = number_x + metrics.lead;
        if let Some(kind) = entry.command {
            // コマンドの候補は，文字の前に種類のアイコンを置く
            painter.command(kind, text_x, row.mid_y(), selected, opacity);
            text_x += Painter::command_width();
        }
        if theme.is_rounded() {
            let center = Point::new(number_x + glass::BADGE_SIZE / 2.0, row.mid_y());
            painter.badge(
                &number,
                center,
                selected,
                number_opacity,
                glass::BADGE_SIZE,
                Font::Key,
            );
        } else {
            let color = if selectable {
                muted_color
            } else {
                theme.text_muted.faded(number_opacity)
            };
            painter.text(&number, Font::Label, color, number_x, row);
        }
        painter.text(&shown[index], Font::Candidate, text_color, text_x, row);
        let text_end = text_x
            + painter.width(&shown[index], Font::Candidate)
            + painter.detail_width(entry.detail.as_deref());
        let tag = entry.annotation.as_deref().map(|annotation| {
            let width = painter.tag_width(annotation);
            Frame::new(tag_max_x(row, metrics) - width, row.y, width, row.height)
        });
        contents.push((Frame::new(row.x, row.y, text_end - row.x, row.height), tag));
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
            // 角丸のテーマの行の背景は行の間隔より上下に縮めてあるので，その分を引く
            let offset = if theme.is_rounded() {
                glass::UNDERLINE_OFFSET - glass::SELECTION_INSET_Y
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
                tag_max_x(row, metrics),
                row.mid_y(),
                selected,
                TagStyle::of(annotation, entry.command.is_some()),
            );
        }
    }
    if let (Some(slot), Some(card)) = (slot, layout.card) {
        if let Some(line) = layout.card_separator {
            painter.rect(line, theme.line);
        }
        meaning::draw(painter, &slot.card, card);
    }
    // 語の意味の吹き出しは，選んでいない候補・文字種の行・候補の下の語の意味・足元の区切りの線から下を覆わない
    let selected = (list.focus == CandidateFocus::Candidate)
        .then_some(list.selected_entry)
        .flatten();
    for (index, row) in cells.rows.iter().enumerate() {
        if selected != Some(index as u32) {
            painter.keep_clear.push(*row);
        }
    }
    painter.keep_clear.extend(layout.header);
    painter.keep_clear.extend(layout.card);
    // 窓の中に置くときは，行の背景ではなく文字とタグの範囲を避ける
    let mut inside = selected
        .and_then(|index| contents.get(index as usize))
        .map(|(content, _)| super::bubble::Inside {
            content: *content,
            obstacles: contents
                .iter()
                .enumerate()
                .filter(|(index, _)| selected != Some(*index as u32))
                .flat_map(|(_, (text, tag))| std::iter::once(*text).chain(*tag))
                .chain(layout.header)
                .chain(layout.card)
                .collect(),
        });
    if layout.footer.height > 0.0 {
        let footer_top = layout.footer_separator.y;
        let footer_region = Frame::new(
            layout.body.x,
            footer_top,
            layout.body.width,
            layout.body.max_y() - footer_top,
        );
        painter.keep_clear.push(footer_region);
        if let Some(inside) = &mut inside {
            inside.obstacles.push(footer_region);
        }
        painter.rect(layout.footer_separator, theme.line);
        footer_section(painter, footer, layout.footer, metrics.row_padding_x);
    }
    painter.inside = inside;
}

/// 候補の行のタグの右端(行の背景の内側の余白の内側．足元の位置の右の端と同じ x)
fn tag_max_x(row: Frame, metrics: &Metrics) -> f32 {
    row.max_x() - metrics.row_padding_x
}

/// 文字種の行．ふだんは弱い文字で見せ，上キーで移ったときだけ強調する(R-03)．
/// 最初の文字種の文字を候補の番号の左(行の背景の内側の余白 inset)にそろえる
fn variants(painter: &mut Painter, list: &CandidateList, section: Frame, inset: f32) {
    let theme = painter.theme;
    let mut x = section.x + inset - candidate::VARIANT_PADDING_X;
    for (index, variant) in list.variants.iter().enumerate() {
        let selected =
            list.focus == CandidateFocus::Variants && list.selected_variant == Some(index as u32);
        let color = match (selected, variant.is_available) {
            // 文節を打ち直しているあいだ(⇧⌫)の文字種は打ち直す前の語のものなので，候補と同じ濃さに薄くする
            _ if list.is_editing == Some(true) => {
                theme.text.faded(tokens::opacity::candidate::EDITING_STALE)
            }
            (true, _) => theme.selection_text,
            (false, true) => theme.text_muted,
            (false, false) => theme.text_muted.faded(opacity::variant::UNAVAILABLE),
        };
        let width = painter.width(&variant.label, Font::Label) + candidate::VARIANT_PADDING_X * 2.0;
        let cell = Frame::new(x, section.y, width, section.height);
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

/// 案内を左，位置を右．どのテーマも同じ並び(テーマで変えるのは形と色だけ)．
/// 左右の端は候補の行の番号の左と注釈のタグの右(行の背景の内側の余白 inset)にそろえる
fn footer_section(painter: &mut Painter, footer: &Footer, section: Frame, inset: f32) {
    let theme = painter.theme;
    let left = section.x + inset;
    let right = section.max_x() - inset;
    match &footer.note {
        Some(note) => painter.note(note, left, section.mid_y()),
        None => {
            painter.hints(&footer.hints, left, section.mid_y());
            if let Some(hint) = &footer.association_hint {
                // 選んでいる候補に連想があることを，キーの案内のあとに小さく出す(R-18)
                let x = left + painter.hints_width(&footer.hints) + glass::HINT_GAP;
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
            is_editing: None,
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
        list.hints = Some(vec![hint("←→", "列"), hint("Alt+↓", "戻る")]);
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
        // platinum の番号の文字は，2 列目の 9 個がふつうの濃さで，ほかの列は薄い(どの列も番号の列から始まる)
        let theme = theme("platinum");
        let scene = candidate_list(&grid(), &Look::new(&theme, 15.0), &Fixed);
        let numbers: Vec<(String, crate::theme::Color)> = texts(&scene)
            .into_iter()
            .filter(|(text, _)| text.parse::<u32>().is_ok())
            .collect();
        let faint = theme
            .text_muted
            .faded(tokens::opacity::candidate::UNSELECTABLE_NUMBER);
        let selectable: Vec<String> = numbers
            .iter()
            .filter(|(_, color)| *color != faint)
            .map(|(text, _)| text.clone())
            .collect();
        assert_eq!(
            selectable,
            (1..=9).map(|n| n.to_string()).collect::<Vec<_>>()
        );
        assert_eq!(
            numbers.iter().filter(|(_, color)| *color == faint).count(),
            20 - 9
        );
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
    fn コメントのタグを押すとコメント_タグの外の行と_コメントでないタグは候補() {
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
            let tag = text_frame(&scene, "千代田区千代田1-1").expect("タグを描く");
            assert_eq!(
                scene.target_at(tag.mid_x(), tag.mid_y()),
                Some(comment.clone())
            );
            // タグの上下の空きも，行の高さいっぱいまでタグとして押せる
            let row = hit(ipc::PointerTarget::Entry { index: 0 }).expect("候補の行");
            let area = hit(comment.clone()).expect("タグを押せる範囲");
            assert_eq!((area.y, area.height), (row.y, row.height), "{name}");
            assert_eq!(scene.target_at(tag.mid_x(), row.y + 1.0), Some(comment));
            // タグの左(候補の文字の側)は候補
            assert_eq!(
                scene.target_at(area.x - 1.0, row.mid_y()),
                Some(ipc::PointerTarget::Entry { index: 0 })
            );
            let text = text_frame(&scene, "変換").expect("描いた文字がある");
            assert_eq!(
                scene.target_at(text.x + 1.0, text.mid_y()),
                Some(ipc::PointerTarget::Entry { index: 0 })
            );
            // コメントでないタグ(入力のまま)は押しても候補
            let plain = text_frame(&scene, "入力のまま").expect("タグを描く");
            assert_eq!(
                scene.target_at(plain.mid_x(), plain.mid_y()),
                Some(ipc::PointerTarget::Entry { index: 1 })
            );
        }
        // コメントの無い一覧にはタグの押せる範囲を足さない
        let theme = theme("automatic");
        let scene = candidate_list(&list(Some(0)), &Look::new(&theme, 15.0), &Fixed);
        assert!(!scene
            .hits
            .iter()
            .any(|hit| matches!(hit.target, ipc::PointerTarget::Comment { .. })));
    }

    #[test]
    fn 連想の見出しが窓の幅を決めるときは説明と位置のあいだを_group_だけ空ける() {
        use super::super::association::testing::{gap, long};
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut associated = list(Some(0));
            associated.association = Some(long());
            let scene = candidate_list(&associated, &Look::new(&theme, 15.0), &Fixed);
            assert_eq!(gap(&scene), tokens::size::space::GROUP, "{name}");
        }
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

    #[test]
    fn 吹き出しに出す設定では候補の窓に語の意味を入れず_窓の大きさを変えない() {
        for name in ["platinum", "automatic", "desk"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let shown = with_meaning(MeaningPlacement::Side);
            let scene = candidate_list(&shown, &look, &Fixed);
            let texts = texts_of(&scene);
            assert!(!texts.contains(&"別の形に変える".to_string()), "{name}");
            // 足元のキーの案内は消さない
            assert!(texts.contains(&"2 / 30".to_string()), "{name}");
            // 意味の無い一覧と同じ大きさ
            let plain = candidate_list(
                &CandidateList {
                    homophone: None,
                    ..shown.clone()
                },
                &look,
                &Fixed,
            );
            assert_eq!(
                (scene.width, scene.height),
                (plain.width, plain.height),
                "{name}"
            );
            // 吹き出しは選んでいる候補の行を指す
            let (note, others, row) =
                super::super::bubble::for_list(&shown, &scene).expect("吹き出し");
            assert_eq!(note.word, "変換");
            assert_eq!(others, note.others);
            let selected = scene
                .hits
                .iter()
                .find(|hit| hit.target == ipc::PointerTarget::Entry { index: 0 })
                .map(|hit| hit.frame)
                .expect("選んでいる行");
            assert_eq!(row, selected, "{name}");
        }
    }

    #[test]
    fn 文字種の行を選んでいるあいだは吹き出しを出さない() {
        let theme = theme("automatic");
        let mut variants = with_meaning(MeaningPlacement::Side);
        variants.focus = CandidateFocus::Variants;
        variants.selected_variant = Some(0);
        let scene = candidate_list(&variants, &Look::new(&theme, 15.0), &Fixed);
        assert!(super::super::bubble::for_list(&variants, &scene).is_none());
        // 候補の下に出す設定では吹き出しを出さない
        let below = with_meaning(MeaningPlacement::Below);
        let scene = candidate_list(&below, &Look::new(&theme, 15.0), &Fixed);
        assert!(super::super::bubble::for_list(&below, &scene).is_none());
    }

    #[test]
    fn 長い意味は窓の幅で折り返し_候補を窓の幅の上限に収める() {
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let mut long = with_meaning(MeaningPlacement::Below);
            if let Some(note) = long.homophone.as_mut() {
                note.senses[0].meaning = "意".repeat(600);
                note.others = (0..30).map(|index| format!("語{index}")).collect();
            }
            long.entries[1].text = "長".repeat(80);
            let scene = candidate_list(&long, &look, &Fixed);
            let texts = texts_of(&scene);
            let lines = texts.iter().filter(|text| text.starts_with('意')).count();
            assert_eq!(lines, card_size::MEANING_LINES as usize, "{name}");
            // 入らない分は省く(3 行に入る字だけを出す)
            let shown: usize = texts
                .iter()
                .filter(|text| text.starts_with('意'))
                .map(|text| text.chars().filter(|c| *c == '意').count())
                .sum();
            assert!(shown < 600, "{name}: {shown}");
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
            // 窓の幅はカードの幅に合わせて広げる
            assert!(scene.width >= card_size::LIST_WIDTH);
            let plain = candidate_list(&list(Some(0)), &look, &Fixed);
            assert!(scene.height > plain.height, "{name}");
        }
    }

    /// 枠線だけの丸(語の意味の番号)の数
    fn number_circles(scene: &Scene) -> usize {
        let size = card_size::MARKER_WIDTH - 1.0;
        scene
            .draws
            .iter()
            .filter(|draw| {
                matches!(draw, Draw::RoundRect { radius, frame, fill: None, stroke: Some(_) }
                if frame.width == size && frame.height == size && *radius == size / 2.0)
            })
            .count()
    }

    #[test]
    fn 意味が2つ以上なら枠線だけの丸に番号を入れる() {
        let theme = theme("automatic");
        let look = Look::new(&theme, 15.0);
        let mut two = with_meaning(MeaningPlacement::Below);
        if let Some(note) = two.homophone.as_mut() {
            note.senses.push(ipc::HomophoneSense {
                meaning: "向きを変える".into(),
                example: None,
            });
        }
        let single = candidate_list(&with_meaning(MeaningPlacement::Below), &look, &Fixed);
        let double = candidate_list(&two, &look, &Fixed);
        let texts = texts_of(&double);
        assert!(texts.contains(&"向きを変える".to_string()));
        assert_eq!(number_circles(&double), 2);
        assert!(double.height >= single.height);
        // 意味が 1 つなら番号の丸を描かない
        assert_eq!(number_circles(&single), 0);
    }

    fn texts_of(scene: &Scene) -> Vec<String> {
        texts(scene).into_iter().map(|(text, _)| text).collect()
    }

    #[test]
    fn 番号キーで選べない窓は番号を薄く出し_文字種の行が無ければ文字種の案内を出さない() {
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
            assert!(!texts.contains(&"文字種".to_string()));
            // 番号は選べる窓より薄く出す(番号の列を空に見せない)
            let numbered_scene = candidate_list(&list(Some(0)), &look, &Fixed);
            let number_color = |scene: &Scene| {
                scene.draws.iter().find_map(|draw| match draw {
                    Draw::Text { text, color, .. } if text == "2" => Some(color.alpha),
                    Draw::Group { draws, .. } => draws.iter().find_map(|draw| match draw {
                        Draw::Text { text, color, .. } if text == "2" => Some(color.alpha),
                        _ => None,
                    }),
                    _ => None,
                })
            };
            let faint = number_color(&scene).expect("薄い番号");
            let shown = number_color(&numbered_scene).expect("番号");
            assert!(faint < shown, "{name}: {faint} {shown}");
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
    fn コマンドの候補は種類のアイコンを文字の前に置き_タグをアクセントの色にする() {
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
    fn 選んでいるコマンドの候補は_アイコンとタグを選択の文字の色にする() {
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
            key_action: Some("元に戻す".into()),
            text: "修正　Space 元に戻す".into(),
        });
        let scene = candidate_list(&noted, &Look::new(&theme, 15.0), &Fixed);
        // 主な語は補正の色，キーでできることはキーの案内と同じ控えめな色
        assert!(texts(&scene).contains(&("修正".into(), theme.correction)));
        assert!(texts(&scene).contains(&("元に戻す".into(), theme.text_muted)));
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
