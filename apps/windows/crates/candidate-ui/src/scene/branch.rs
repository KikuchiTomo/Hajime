#![forbid(unsafe_code)]

//! 分岐図(ADR 0007．macOS の BranchView)．文を 1 本の線(幹)に並べ，選んでいる文節から枝を出す．できることは，すべて線でつながった枝として見せる．
//!
//! - 幹: 文節を横に並べ，その下の線に文節ごとの丸を置く．選んでいる文節の丸は選択の色で塗る．確信の低い文節は，下の線を点線にする．
//!   丸は，短い文節は真ん中，長い文節は左から決まった距離(1 字と余白)に置く(候補を移って字の数が変わっても枝が動かない)
//! - 下の枝: 変換の候補．選んでいる文節の丸から縦の線を下ろし，候補ごとに丸・番号(キーキャップの形)・文字を並べる．選んだ候補までの線は選択の色で太く描く
//! - 上の枝: 文字種(ひらがな・カタカナ・半角カタカナ)．文節の上から横へ伸ばす
//! - 先の枝: 選んでいる候補の行の先に小さな幹を伸ばし，連想(R-18)の丸を並べる．語の意味は今までどおり吹き出しか候補の下のカードに出す
//! - キーの案内: 足元には並べず，操作する場所に置く(区切り・分割は文節の境目の上，文字種は上の枝の先，再入力・表形式は候補の下，展開は先の枝の先)．
//!   候補の中身と見分けられるよう，背景と反転した色の面で囲む．文節の丸の上には，その文節へ移るキーを重ねる
//! - 表示項目を減らす設定では，畳んだ枝に端へ向けて透かした短い線を出す
//! - 文節を区切っているとき(⇧↓)は，幹を意味のある切れ目(「問題｜が｜ある」)で分け，切れ目に番号を挟む．枝は出さない
//!
//! 窓の幅に上限があるので，枝が右に入らないときは枝を左右に反転して左へ出す．どちらにも入らないときは，入る位置まで寄せて，角を曲げた線で文節とつなぐ．
//! 幹が窓より長いときは，選んでいる文節が見える位置まで幹を送り，はみ出した側を端へ向けて透かす．
//! 角丸のテーマは丸と丸い角の線，platinum と desk は四角と 1 ドットの線で描く(route)

use super::card_layout::{self, Placement};
use super::meaning::{self, Slot};
use super::paint::{Painter, TagStyle};
use super::route::{self, Line, State, Stop};
use super::{Draw, Frame, Look, Measure, Point, Scene};
use crate::strings;
use crate::theme::Font;
use ipc::{
    BranchColumn, BranchHints, BranchMap, BranchSplit, CommandKind, KeyHint, MeaningPlacement,
};
use tokens::opacity::candidate as stale_opacity;
use tokens::size::meaning as card_size;
use tokens::size::{branch, branch_map as map, candidate, glass, part, space};

/// テーマごとの寸法
struct Metrics {
    /// 窓の端から中身まで
    inset: f32,
    row_height: f32,
    /// 候補の行の背景の上下を縮める量(角丸のテーマ)
    row_inset: f32,
    /// 注釈・知らせ・見出しの行の高さ
    note_height: f32,
    line_width: f32,
    line_width_selected: f32,
    /// 線の曲がり角の半径．直線の枝のテーマと platinum・desk は 0
    turn_radius: f32,
    shadow: f32,
    /// 候補の文字の大きさ(文節の丸の位置を決める)
    font_size: f32,
    /// 1 ドットあたりのデバイスのピクセル数
    pixel_scale: f32,
}

/// 区切りの線の上と下，カードと枝のあいだの空き
const GAP: f32 = glass::SEPARATOR_GAP;
/// 縦の線から番号までの距離
const BADGE_OFFSET: f32 = map::STOP_SIZE_SELECTED / 2.0 + map::STEM_GAP;
/// 候補の番号と，そのあとの空き
const LEAD: f32 = glass::BADGE_SIZE + glass::BADGE_GAP;

impl Metrics {
    fn new(look: &Look, measure: &dyn Measure) -> Self {
        let scale = look.font_size / candidate::FONT_SIZE;
        let shadow = if look.theme.has_drop_shadow() {
            candidate::SHADOW_OFFSET
        } else {
            0.0
        };
        let note_height = glass::KEYCAP_HEIGHT
            .max(glass::NOTE_ICON_SIZE)
            .max(measure.height(Font::Label).ceil());
        if look.theme.is_rounded() {
            return Self {
                inset: candidate::FRAME_WIDTH + glass::WINDOW_PADDING,
                row_height: (glass::ROW_HEIGHT * scale).round(),
                row_inset: glass::SELECTION_INSET_Y,
                note_height,
                line_width: glass::LINE_WIDTH,
                line_width_selected: glass::LINE_WIDTH_SELECTED,
                turn_radius: if look.theme.curved_branches() {
                    glass::BRANCH_TURN_RADIUS
                } else {
                    0.0
                },
                shadow,
                font_size: look.font_size,
                pixel_scale: look.pixel_scale,
            };
        }
        Self {
            inset: candidate::FRAME_WIDTH + candidate::BEVEL_WIDTH + glass::WINDOW_PADDING,
            row_height: (candidate::ROW_HEIGHT * scale).round(),
            row_inset: 0.0,
            note_height,
            line_width: branch::LINE_WIDTH,
            line_width_selected: branch::LINE_WIDTH_SELECTED,
            turn_radius: 0.0,
            shadow,
            font_size: look.font_size,
            pixel_scale: look.pixel_scale,
        }
    }

    /// 見出し・注釈・知らせの文字の左右の端
    fn text_inset(&self) -> f32 {
        self.inset + part::ROW_PADDING_X
    }

    /// 文節の左の端から，その文節の丸(と，そこから出る枝)までの距離．短い文節は真ん中，長い文節は左から決まった距離(1 字と余白)
    fn stop_offset(&self, width: f32) -> f32 {
        (width / 2.0)
            .min(self.font_size + part::ROW_PADDING_X)
            .round()
    }
}

/// 操作する場所ごとの案内(エンジンが置き場所ごとに送る．BranchHints)．案内を出さない設定では空
fn hints(map: &BranchMap) -> BranchHints {
    map.placed_hints.clone().unwrap_or(BranchHints {
        boundary: Vec::new(),
        variant: None,
        candidates: Vec::new(),
        expand: None,
    })
}

/// キーの案内を出すか(案内を出さない設定では，エンジンが置き場所ごとの案内を送らない)
fn shows_hints(map: &BranchMap) -> bool {
    map.placed_hints.is_some()
}

/// 注目している文節の位置と文節
pub(super) fn focused(map: &BranchMap) -> Option<(usize, &BranchColumn)> {
    map.columns
        .iter()
        .enumerate()
        .find(|(_, column)| column.is_focused)
}

/// ページの数と今のページ(0 から)．1 ページか，1 ページの数が分からなければ None
fn pages(map: &BranchMap) -> Option<(u32, u32)> {
    let size = map.page_size.filter(|size| *size > 0)?;
    (map.total > size).then(|| {
        (
            map.total.div_ceil(size),
            map.position.saturating_sub(1) / size,
        )
    })
}

/// 候補の下の行に出す位置の文字．ページの位置は縦の線の下の点で示すので，点で示せないほどページが多いときだけ「3 / 12」と出す．
/// 1 ページの数を知らせない前の版のエンジンでは，今までどおり「1–4 / 8」と出す
fn position_text(map: &BranchMap) -> String {
    if map.page_size.is_none() {
        return position(map);
    }
    match pages(map) {
        Some((count, current)) if count as f32 > map::PAGE_DOT_LIMIT => {
            strings::group_position(current + 1, count)
        }
        _ => String::new(),
    }
}

/// ページの位置を示す点の並び．縦の線の下に，ページの数だけ縦に並べる
#[derive(Debug, Clone, Copy, PartialEq)]
struct PageDots {
    x: f32,
    top: f32,
    count: u32,
    current: u32,
}

/// 何番目の候補か．区切っているときは候補を出さないので出さない
fn position(map: &BranchMap) -> String {
    match focused(map) {
        Some((_, column)) if column.split.is_some() => String::new(),
        focused => {
            let count = focused.map_or(0, |(_, column)| column.alternatives.len() as u32);
            strings::position(map.position, map.position + count.max(1) - 1, map.total)
        }
    }
}

/// 候補の下の語の意味の置き方
fn below_position(painter: &Painter) -> Placement {
    Placement {
        left: part::ROW_PADDING_X,
        header_mid_y: card_layout::header_height(painter.theme) / 2.0,
    }
}

/// 注目している文節で，候補の下に出す幅 width(窓の中身の幅)の語の意味．区切っているあいだと，吹き出しに出す設定では None
fn meaning_slot(map: &BranchMap, painter: &Painter, width: f32) -> Option<Slot> {
    let (_, column) = focused(map)?;
    if column.split.is_some() || map.meaning_placement != Some(MeaningPlacement::Below) {
        return None;
    }
    let note = column.homophone.as_ref()?;
    Some(meaning::below_slot(
        meaning::Card::new(
            painter,
            note,
            meaning::branch_others(note, column),
            width,
            below_position(painter),
        ),
        0.0,
    ))
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

/// 打ち間違いを直した文節の幹で，文字のあとに添える「修正」のタグの幅(前の空きを含む)．直していなければ 0
fn corrected_label_width(column: &BranchColumn, painter: &Painter) -> f32 {
    if column.is_corrected == Some(true) {
        painter.tag_width(strings::CORRECTED) + space::INLINE
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

/// その場で打ち直している文節(⇧⌫)か(core の LatticePanel.Column.isEditing)
fn editing(column: &BranchColumn) -> bool {
    column.is_editing == Some(true)
}

/// 幹の文節の幅(文字と左右の余白)
fn trunk_width(column: &BranchColumn, painter: &Painter) -> f32 {
    let mut text = column.split.as_ref().map_or_else(
        || match trunk_command(column) {
            Some((_, title)) => Painter::command_width() + painter.width(title, Font::Trunk),
            None => painter.width(&column.text, Font::Trunk),
        },
        |split| split_pieces(split, painter).width,
    );
    // 打ち直している文節は，読みのあとの入力位置の線の分を足し，読みが空でも場所が分かる幅を残す
    if editing(column) && column.split.is_none() {
        text = (text + glass::EDITING_CARET_WIDTH).max(glass::EDITING_MIN_WIDTH);
    }
    text + part::ROW_PADDING_X * 2.0 + corrected_label_width(column, painter)
}

/// 候補の行
struct Row {
    text: String,
    badge: String,
    selected: bool,
    opacity: f32,
    /// 打ったまま・修正・コマンドの添え書きか，ユーザー辞書の語のコメント
    note: Option<String>,
    /// コマンドの候補なら，その種類(文字の前にアイコンを置き，添え書きをアクセントの色のタグにする)
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
            opacity: if editing(column) {
                stale_opacity::EDITING_STALE
            } else if index == 0 {
                1.0
            } else {
                rest
            },
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

/// 候補の行の文字の幅(コマンドのアイコンと，文字のあとに添える説明を含む)
fn lower_row_width(row: &Row, painter: &Painter) -> f32 {
    painter.width(&row.text, Font::Candidate)
        + row.command.map_or(0.0, |_| Painter::command_width())
        + painter.detail_width(row.detail.as_deref())
}

/// 上の枝の文字種ごとの，その文字種にするキー(variants と同じ数)．案内を出さない設定と，キーの無い文字種は None
fn variant_keys(map: &BranchMap, column: Option<&BranchColumn>) -> Vec<Option<String>> {
    let Some(column) = column else {
        return Vec::new();
    };
    let keys = column.variant_keys.as_deref().unwrap_or_default();
    (0..column.variants.len())
        .map(|index| {
            if shows_hints(map) {
                keys.get(index).cloned().flatten()
            } else {
                None
            }
        })
        .collect()
}

/// 文字種の 1 つ．線の上の丸と，文字の枠
struct Kind {
    stop: Point,
    label: Frame,
}

/// 先の枝の丸と見出し
struct Station {
    title: String,
    stop: Point,
    title_x: f32,
    title_mid_y: f32,
}

/// 幹・枝・案内の位置．描くとき・大きさを求めるとき・押した位置を調べるときで同じものを使う
#[derive(Default)]
struct Layout {
    width: f32,
    height: f32,
    /// 幹の文節の枠(送ったあとの位置)
    nodes: Vec<Frame>,
    /// 幹の線の y と，左右の端
    rail_y: f32,
    rail_start: f32,
    rail_end: f32,
    /// 幹が窓からはみ出している側
    fades_left: bool,
    fades_right: bool,
    focus: Option<usize>,
    /// 選んでいる文節の丸の x と，候補の枝の縦の線の x(枝を寄せていなければ同じ)
    focus_x: f32,
    stem_x: f32,
    /// 枝の向き．1 は右，-1 は左(左右に反転)
    direction: f32,
    /// 候補の行(選択の背景の枠)
    rows: Vec<Frame>,
    kinds: Vec<Kind>,
    twig_direction: f32,
    twig_y: f32,
    /// 文字種の線の，文節から遠い側の端
    twig_end_x: f32,
    variant_hint_x: Option<f32>,
    /// 文節の境目の上の案内の行
    boundary_mid_y: Option<f32>,
    boundary_x: f32,
    stations: Vec<Station>,
    expand_x: Option<f32>,
    expand_mid_y: f32,
    /// 畳んでいる枝の，続きがある印の線(表示項目を減らす設定)．文字種は文節の上へ，先の枝は選んでいる候補の行の先へ
    variant_stub: Option<(Point, Point)>,
    detail_stub: Option<(Point, Point)>,
    /// 候補の下の行(案内・位置・辞書の名前)
    bottom_mid_y: Option<f32>,
    bottom_hints_x: f32,
    position_x: f32,
    source_x: f32,
    /// ページの位置を示す点
    page_dots: Option<PageDots>,
    /// 候補の下に出す語の意味のカード
    slot: Option<Slot>,
    card: Option<Frame>,
    /// 注釈・知らせの行を置き始める y
    notes_top: f32,
    heading: Option<Frame>,
}

// 配置を 1 か所で決める(macOS の BranchView.makeLayout)．幹・枝の向き・縦の並びの順に決めるので長い
#[allow(clippy::too_many_lines)]
fn layout(map: &BranchMap, metrics: &Metrics, painter: &Painter, rest: f32) -> Layout {
    let hints = hints(map);
    let mut result = Layout::default();
    let tag = glass::TAG_HEIGHT;

    // 幹(送る前)．文節のあいだには，境目のつまみの両側の空きを取る
    let node_gap = map::SEGMENT_GAP * 2.0;
    let mut x = metrics.inset;
    let mut node_x = Vec::new();
    let mut node_widths = Vec::new();
    for column in &map.columns {
        let width = trunk_width(column, painter);
        node_x.push(x);
        node_widths.push(width);
        x += width + node_gap;
    }
    let trunk_right = if map.columns.is_empty() {
        metrics.inset
    } else {
        x - node_gap
    };
    let focus = focused(map).map(|(index, _)| index);
    let column = focus.map(|index| &map.columns[index]);
    let lower = column.map_or_else(Vec::new, |column| lower_rows(column, rest));
    let selected_row = lower.iter().position(|row| row.selected);

    // 候補の枝．縦の線から外へ向かう距離で決める(枝を左右に反転しても同じ距離を使う)
    let text_offset = BADGE_OFFSET + LEAD;
    let note_width = lower
        .iter()
        .filter_map(|row| row.note.as_deref().map(|note| painter.tag_width(note)))
        .fold(0.0, f32::max);
    let row_start = BADGE_OFFSET - part::ROW_PADDING_X;
    // 候補の下の行(案内・辞書の名前・位置)．候補の行の幅に収め，先の枝と重ねない
    let shows_pages = !lower.is_empty() && column.is_some_and(|column| column.split.is_none());
    let position_text = if shows_pages {
        position_text(map)
    } else {
        String::new()
    };
    let position_width = if position_text.is_empty() {
        0.0
    } else {
        painter.width(&position_text, Font::Label)
    };
    let source_width = column
        .and_then(|column| column.source_name.as_deref())
        .map_or(0.0, |name| {
            painter.width(&strings::dictionary_source(name), Font::Label) + candidate::PADDING_X
        });
    let far_width = position_width + source_width;
    let bottom_hints_width = if lower.is_empty() {
        0.0
    } else {
        painter.placed_hints_width(&hints.candidates)
    };
    let has_bottom = bottom_hints_width > 0.0 || far_width > 0.0;
    let bottom_end = BADGE_OFFSET
        + bottom_hints_width
        + if bottom_hints_width > 0.0 && far_width > 0.0 {
            space::GROUP
        } else {
            0.0
        }
        + far_width;
    let widest = lower
        .iter()
        .map(|row| lower_row_width(row, painter))
        .fold(0.0, f32::max);
    let row_end = (text_offset
        + widest
        + if note_width > 0.0 {
            space::GROUP + note_width
        } else {
            0.0
        }
        + part::ROW_PADDING_X * 2.0)
        .max(if has_bottom { bottom_end } else { 0.0 });
    let far_start = row_end - far_width;
    let mut reach = if lower.is_empty() { 0.0 } else { row_end };

    // 先の枝(連想)．候補を選んでいるときだけ出す
    let mut titles: Vec<String> = Vec::new();
    if column.is_some_and(|column| !editing(column))
        && selected_row.is_some()
        && map.association.is_none()
    {
        if let Some(label) = map.association_hint.clone() {
            titles.push(label);
        }
    }
    let mut station_offsets = Vec::new();
    let mut cursor = row_end + map::STATION_GAP;
    for title in &titles {
        let width = painter.width(title, Font::Label);
        station_offsets.push(cursor + width / 2.0);
        cursor += width + map::STATION_GAP;
    }
    let mut expand_offset = None;
    if !titles.is_empty() {
        reach = cursor - map::STATION_GAP;
        if let Some(expand) = hints.expand.as_ref() {
            expand_offset = Some(reach + space::GROUP);
            reach += space::GROUP + painter.placed_hint_width(expand);
        }
    }
    // 先の枝を畳んでいるとき: 候補の行の先に，続きがある印の線と開くキーの案内
    let shows_detail_stub = map.collapses_detail == Some(true)
        && selected_row.is_some()
        && column.is_some_and(|column| !editing(column));
    if shows_detail_stub {
        reach = row_end + map::STUB_LENGTH;
        if let Some(expand) = hints.expand.as_ref() {
            expand_offset = Some(reach + space::INSET);
            reach += space::INSET + painter.placed_hint_width(expand);
        }
    }

    // 文字種の枝．文節の上から横へ伸ばす．並びは反転しない．文字の前に，その文字種にするキーを置く
    let kind_keys = variant_keys(map, column);
    let kind_widths: Vec<f32> = column
        .map(|column| column.variants.as_slice())
        .unwrap_or_default()
        .iter()
        .enumerate()
        .map(|(index, text)| {
            painter.width(text, Font::Label)
                + part::ROW_PADDING_X * 2.0
                + kind_keys
                    .get(index)
                    .cloned()
                    .flatten()
                    .map_or(0.0, |key| painter.key_mark_width(&key) + space::INLINE)
        })
        .collect();
    // 文字種の文字・境目の案内・候補の番号・候補の下の案内の左の端を，縦の線から同じ距離にそろえる
    let kind_start = BADGE_OFFSET - part::ROW_PADDING_X;
    let variant_hint_width = if kind_widths.is_empty() {
        0.0
    } else {
        hints
            .variant
            .as_ref()
            .map_or(0.0, |hint| painter.placed_hint_width(hint))
    };
    let kinds_reach = if kind_widths.is_empty() {
        0.0
    } else {
        kind_start
            + kind_widths.iter().sum::<f32>()
            + map::STATION_GAP * (kind_widths.len() - 1) as f32
            + if variant_hint_width > 0.0 {
                space::GROUP + variant_hint_width
            } else {
                0.0
            }
    };

    // 窓の幅．上限を超える文は，幹を送る
    let focus_center = focus.map_or(metrics.inset, |index| {
        node_x[index] + metrics.stop_offset(node_widths[index])
    });
    let boundary_width = painter.placed_hints_width(&hints.boundary);
    let below = map.meaning_placement == Some(MeaningPlacement::Below)
        && column.is_some_and(|column| column.homophone.is_some() && column.split.is_none());
    let notes_width = [
        column
            .and_then(|column| column.usage_note.as_deref())
            .map(|text| painter.width(text, Font::Label)),
        map.note.as_ref().map(|note| painter.note_width(note)),
        below.then_some(card_size::LIST_WIDTH),
    ]
    .into_iter()
    .flatten()
    .map(|width| width + part::ROW_PADDING_X * 2.0)
    .fold(0.0, f32::max);
    let heading_width = map.association.as_ref().map_or(0.0, |heading| {
        super::association::width(painter, heading) + metrics.text_inset() * 2.0
    });
    // 境目の案内は，文節から上へ伸びる線の右に置く
    let boundary_start = BADGE_OFFSET;
    let mut width = candidate::MIN_WIDTH
        .max(trunk_right + metrics.inset)
        .max(focus_center + reach.max(kinds_reach) + metrics.inset)
        .max(focus_center + boundary_start + boundary_width + metrics.inset)
        .max(notes_width + metrics.inset * 2.0)
        .max(heading_width);
    let limit = candidate::MAX_WIDTH.max(candidate::MIN_WIDTH);
    let mut shift = 0.0;
    let mut overflows = false;
    if width > limit {
        width = limit;
        overflows = true;
        // 選んでいる文節(とその右の境目のつまみ)が窓の内側に入るだけ送る
        if let Some(index) = focus {
            let (low, high) = (node_x[index], node_x[index] + node_widths[index] + node_gap);
            let visible = limit - metrics.inset * 2.0;
            let mut offset: f32 = 0.0;
            if high - offset > metrics.inset + visible {
                offset = high - metrics.inset - visible;
            }
            if low - offset < metrics.inset {
                offset = low - metrics.inset;
            }
            shift = offset.clamp(
                0.0,
                (trunk_right + node_gap + metrics.inset - limit).max(0.0),
            );
        }
    }
    let width = width.ceil();
    let left = metrics.inset;
    let right = width - metrics.inset;
    let focus_x = (focus_center - shift).round();

    // 枝の向き．右に入れば右，入らなければ左右に反転して左．どちらにも入らなければ，広い側へ出して入る位置まで寄せる
    let mut direction: f32 = 1.0;
    if focus_x + reach > right && (focus_x - reach >= left || focus_x > width / 2.0) {
        direction = -1.0;
    }
    let edge = map::STOP_SIZE_SELECTED / 2.0;
    let stem_x = if direction > 0.0 {
        focus_x.min(right - reach).max(left + edge)
    } else {
        focus_x.max(left + reach).min(right - edge)
    }
    .round();
    let twig_direction = if focus_x + kinds_reach <= right || focus_x - kinds_reach < left {
        1.0
    } else {
        -1.0
    };
    // 縦の線から外へ start の距離に置く，幅 width の物の左の端
    let min_x = |start: f32, width: f32| {
        if direction > 0.0 {
            stem_x + start
        } else {
            stem_x - start - width
        }
    };

    // 縦の並び．上から，見出し(連想)・文字種・境目の案内・幹の文節・幹の線・候補・候補の下の行
    let mut y = metrics.inset;
    if map.association.is_some() {
        result.heading = Some(Frame::new(
            metrics.text_inset(),
            y,
            width - metrics.text_inset() * 2.0,
            metrics.note_height,
        ));
        y += metrics.note_height + GAP * 2.0 + candidate::FRAME_WIDTH;
    }
    if !kind_widths.is_empty() {
        let label_y = y;
        y += tag + space::INSET;
        result.twig_y = (y + map::STOP_SIZE / 2.0).round();
        y += map::STOP_SIZE + space::INSET;
        let mut kind_x = if twig_direction > 0.0 {
            focus_x + kind_start
        } else {
            focus_x - kinds_reach
                + if variant_hint_width > 0.0 {
                    variant_hint_width + space::GROUP
                } else {
                    0.0
                }
        };
        for kind_width in &kind_widths {
            let label = Frame::new(kind_x.round(), label_y, *kind_width, tag);
            result.kinds.push(Kind {
                stop: Point::new(
                    label.x + part::ROW_PADDING_X + map::STOP_SIZE / 2.0,
                    result.twig_y,
                ),
                label,
            });
            kind_x += kind_width + map::STATION_GAP;
        }
        let labels_end = kind_x - map::STATION_GAP;
        result.twig_end_x = if twig_direction > 0.0 {
            labels_end
        } else {
            result.kinds.first().map_or(focus_x, |kind| kind.label.x)
        };
        if variant_hint_width > 0.0 {
            result.variant_hint_x = Some(if twig_direction > 0.0 {
                labels_end + space::GROUP
            } else {
                focus_x - kinds_reach
            });
        }
    }
    if focus.is_some() && map.association.is_none() {
        result.boundary_mid_y = Some(y + tag / 2.0);
        y += tag + space::INSET;
    }
    let node_top = y;
    y += metrics.row_height;
    result.rail_y = (y + map::RAIL_HEIGHT / 2.0).round();
    y += map::RAIL_HEIGHT;
    if !lower.is_empty() {
        y += map::ROW_GAP;
        for index in 0..lower.len() {
            result.rows.push(Frame::new(
                min_x(row_start, row_end - row_start),
                y + index as f32 * metrics.row_height,
                row_end - row_start,
                metrics.row_height,
            ));
        }
        y += lower.len() as f32 * metrics.row_height;
    }
    let mut bottom = y;
    if let Some((count, current)) = pages(map).filter(|_| shows_pages) {
        if count as f32 <= map::PAGE_DOT_LIMIT {
            let dots = PageDots {
                x: stem_x,
                top: y + space::INSET,
                count,
                current,
            };
            bottom = bottom.max(dots.top + count as f32 * map::PAGE_DOT_PITCH);
            result.page_dots = Some(dots);
        }
    }
    if has_bottom {
        result.bottom_mid_y = Some(y + space::INSET + tag / 2.0);
        result.bottom_hints_x = min_x(BADGE_OFFSET, bottom_hints_width);
        let far_x = min_x(far_start, far_width);
        // 位置は枝の外の端に，辞書の名前はその内側に置く
        result.position_x = if direction > 0.0 {
            far_x + source_width
        } else {
            far_x
        };
        result.source_x = if direction > 0.0 {
            far_x
        } else {
            far_x + position_width + candidate::PADDING_X
        };
        bottom = bottom.max(y + space::INSET + tag);
    }
    if let Some(row) = selected_row.and_then(|index| result.rows.get(index)) {
        let mid_y = row.mid_y().round();
        for (title, offset) in titles.iter().zip(&station_offsets) {
            let title_width = painter.width(title, Font::Label);
            let stop_x = if direction > 0.0 {
                stem_x + offset
            } else {
                stem_x - offset
            }
            .round();
            result.stations.push(Station {
                title: title.clone(),
                stop: Point::new(stop_x, mid_y),
                title_x: stop_x - title_width / 2.0,
                title_mid_y: mid_y - map::STOP_SIZE / 2.0 - space::INSET - tag / 2.0,
            });
        }
        if let (Some(offset), Some(expand)) = (expand_offset, hints.expand.as_ref()) {
            result.expand_x = Some(min_x(offset, painter.placed_hint_width(expand)));
            result.expand_mid_y = mid_y;
        }
        if shows_detail_stub {
            let from = if direction > 0.0 {
                stem_x + row_end
            } else {
                stem_x - row_end
            };
            result.detail_stub = Some((
                Point::new(from, mid_y),
                Point::new(from + direction * map::STUB_LENGTH, mid_y),
            ));
        }
    }
    // 候補の下の語の意味: 窓の中身の幅いっぱい
    if focus.is_some() {
        if let Some(slot) = meaning_slot(map, painter, right - left) {
            let frame = Frame::new(left, bottom + GAP, slot.width, slot.height);
            bottom = frame.max_y();
            result.slot = Some(slot);
            result.card = Some(frame);
        }
    }
    result.notes_top = bottom;
    let notes = usize::from(column.is_some_and(|column| column.usage_note.is_some()))
        + usize::from(map.note.is_some());
    let height = bottom + (GAP + metrics.note_height) * notes as f32 + metrics.inset;

    result.nodes = (0..map.columns.len())
        .map(|index| {
            Frame::new(
                (node_x[index] - shift).round(),
                node_top,
                node_widths[index],
                metrics.row_height,
            )
        })
        .collect();
    result.fades_left = overflows && shift > 0.0;
    result.fades_right = overflows && trunk_right - shift > right;
    let stop_x = |node: &Frame| node.x + metrics.stop_offset(node.width);
    result.rail_start = if result.fades_left {
        0.0
    } else {
        result.nodes.first().map_or(left, stop_x)
    };
    result.rail_end = if result.fades_right {
        width
    } else {
        result.nodes.last().map_or(left, stop_x)
    };
    result.focus = focus;
    result.focus_x = focus_x;
    result.stem_x = stem_x;
    result.direction = direction;
    result.twig_direction = twig_direction;
    result.boundary_x = (focus_x + boundary_start)
        .min(right - boundary_width)
        .max(left);
    // 文字種の枝を畳んでいるとき: 文節の上へ，続きがある印の線を境目の案内の行の高さだけ伸ばす
    if map.collapses_variants == Some(true) && column.is_some_and(|column| column.split.is_none()) {
        if let Some(mid_y) = result.boundary_mid_y {
            result.variant_stub = Some((
                Point::new(focus_x, node_top + metrics.row_inset),
                Point::new(focus_x, mid_y - tag / 2.0),
            ));
        }
    }
    result.width = width;
    result.height = height.ceil();
    result
}

/// 選んでいる文節の丸から，候補の縦の線を y まで下ろす道すじ．枝を寄せているときは，幹の線と最初の候補のあいだで横へ曲げる
fn stem_points(y: f32, layout: &Layout, first_row: Frame) -> Vec<Point> {
    let start = Point::new(layout.focus_x, layout.rail_y);
    if layout.stem_x == layout.focus_x {
        return vec![start, Point::new(layout.stem_x, y)];
    }
    let bend_y = ((layout.rail_y + map::RAIL_HEIGHT / 2.0 + first_row.y) / 2.0).round();
    vec![
        start,
        Point::new(layout.focus_x, bend_y),
        Point::new(layout.stem_x, bend_y),
        Point::new(layout.stem_x, y),
    ]
}

/// 寄せた枝の曲がり角の半径．横と縦の線の長さに収まるようにする
fn bend_radius(layout: &Layout, first_row: Frame, metrics: &Metrics) -> f32 {
    let vertical = (first_row.y - layout.rail_y - map::RAIL_HEIGHT / 2.0) / 2.0;
    metrics
        .turn_radius
        .min((layout.stem_x - layout.focus_x).abs() / 2.0)
        .min(vertical)
        .max(0.0)
}

/// 候補の行の押せる範囲．縦の線の上の丸から行の端まで
fn row_area(row: Frame, layout: &Layout) -> Frame {
    let edge = map::STOP_SIZE_SELECTED / 2.0;
    let min_x = row.x.min(layout.stem_x - edge);
    Frame::new(
        min_x,
        row.y,
        row.max_x().max(layout.stem_x + edge) - min_x,
        row.height,
    )
}

/// 文字種の押せる範囲．文字と，その下の線の上の丸
fn kind_area(kind: &Kind) -> Frame {
    Frame::new(
        kind.label.x,
        kind.label.y,
        kind.label.width,
        kind.stop.y + map::STOP_SIZE / 2.0 - kind.label.y,
    )
}

/// 候補の行の添え書きのタグの右端．タグは，縦の線から遠い側の端に置く
fn tag_max_x(painter: &Painter, note: &str, row: Frame, direction: f32) -> f32 {
    if direction > 0.0 {
        row.max_x() - part::ROW_PADDING_X
    } else {
        row.x + part::ROW_PADDING_X + painter.tag_width(note)
    }
}

// 線・丸・文字・案内の順に重ねる．1 か所で順を決めるので長い
#[allow(clippy::too_many_lines)]
pub fn branch_map(map: &BranchMap, look: &Look, measure: &dyn Measure) -> Scene {
    let metrics = Metrics::new(look, measure);
    let mut painter = Painter::new(look, measure);
    let theme = look.theme;
    let hints = hints(map);
    let layout = layout(map, &metrics, &painter, look.rest_opacity);
    let (width, height) = look.sized(
        layout.width + metrics.shadow,
        layout.height + metrics.shadow,
    );
    let body = Frame::new(0.0, 0.0, width - metrics.shadow, height - metrics.shadow);
    painter.panel(body);
    if let (Some(heading), Some(row)) = (&map.association, layout.heading) {
        super::association::draw(&mut painter, heading, row);
        painter.separator(row.max_y() + GAP, metrics.inset, body.width - metrics.inset);
    }
    let column = layout.focus.map(|index| &map.columns[index]);
    let on_trunk = map.trunk_focused == Some(true);
    let rows = column.map_or_else(Vec::new, |column| lower_rows(column, look.rest_opacity));
    let selected_row = rows.iter().position(|row| row.selected);
    let stale = if column.is_some_and(editing) {
        stale_opacity::EDITING_STALE
    } else {
        1.0
    };
    let splitting = map.columns.iter().any(|column| column.split.is_some());

    // 丸．線は丸の内側を通さない
    let trunk_stops: Vec<Stop> = layout
        .nodes
        .iter()
        .enumerate()
        .map(|(index, node)| {
            Stop::new(
                Point::new(node.x + metrics.stop_offset(node.width), layout.rail_y),
                if Some(index) == layout.focus {
                    State::Selected
                } else {
                    State::Plain
                },
            )
        })
        .collect();
    let mut branch_stops: Vec<Stop> = Vec::new();
    for (index, row) in layout.rows.iter().enumerate().take(rows.len()) {
        let state = if Some(index) == selected_row {
            State::Selected
        } else if selected_row.is_some_and(|selected| index < selected) {
            State::Passed
        } else {
            State::Plain
        };
        branch_stops.push(Stop {
            center: Point::new(layout.stem_x, row.mid_y().round()),
            state,
            opacity: rows[index].opacity,
        });
    }
    let selected_variant = column
        .and_then(|column| column.selected_variant)
        .map(|index| index as usize);
    for (index, kind) in layout.kinds.iter().enumerate() {
        // 文節に近い側の丸ほど，選んだ道すじの途中になる
        let passed = selected_variant.is_some_and(|selected| {
            if layout.twig_direction > 0.0 {
                index < selected
            } else {
                index > selected
            }
        });
        let state = if Some(index) == selected_variant {
            State::Selected
        } else if passed {
            State::Passed
        } else {
            State::Plain
        };
        branch_stops.push(Stop {
            center: kind.stop,
            state,
            opacity: stale,
        });
    }
    branch_stops.extend(
        layout
            .stations
            .iter()
            .map(|station| Stop::new(station.stop, State::Plain)),
    );
    let mut avoided = branch_stops.clone();
    if let Some(index) = layout.focus {
        avoided.push(trunk_stops[index]);
    }

    // 幹．窓からはみ出す側は，端へ向けて透かす
    let start = painter.draws.len();
    {
        let mut solid = Vec::new();
        let mut dotted = Vec::new();
        let mut cursor = layout.rail_start;
        for (index, node) in layout.nodes.iter().enumerate() {
            if !map.columns[index].is_uncertain {
                continue;
            }
            // 確信の低い文節の下は点線．幹の線は最初と最後の丸で止めるので，点線もその内側に収める
            let from = (node.x + part::ROW_PADDING_X).max(layout.rail_start);
            let to = (node.max_x() - part::ROW_PADDING_X).min(layout.rail_end);
            if to <= from {
                continue;
            }
            if from > cursor {
                solid.push(Line::new(vec![
                    Point::new(cursor, layout.rail_y),
                    Point::new(from, layout.rail_y),
                ]));
            }
            dotted.push(Line {
                dotted: true,
                ..Line::new(vec![
                    Point::new(from, layout.rail_y),
                    Point::new(to, layout.rail_y),
                ])
            });
            cursor = to;
        }
        if layout.rail_end > cursor {
            solid.push(Line::new(vec![
                Point::new(cursor, layout.rail_y),
                Point::new(layout.rail_end, layout.rail_y),
            ]));
        }
        route::stroke(
            &mut painter,
            &solid,
            theme.line,
            metrics.line_width,
            &trunk_stops,
            metrics.pixel_scale,
        );
        route::stroke(
            &mut painter,
            &dotted,
            theme.text_muted,
            metrics.line_width_selected,
            &trunk_stops,
            metrics.pixel_scale,
        );
        route::draw_stops(&mut painter, &trunk_stops, metrics.line_width);
        for (index, column) in map.columns.iter().enumerate() {
            let node = layout.nodes[index];
            if node.max_x() >= 0.0 && node.x <= body.max_x() {
                trunk_node(&mut painter, column, node, on_trunk);
            }
        }
        // 文節へ移るキーを，文節の丸の上に重ねる(区切っているあいだは，番号キーが別の意味になるので出さない)
        if shows_hints(map) && !splitting {
            for (index, column) in map.columns.iter().enumerate() {
                let Some(key) = column.jump_key.as_deref() else {
                    continue;
                };
                let hint = KeyHint {
                    keys: key.to_string(),
                    label: String::new(),
                };
                let stop = trunk_stops[index];
                painter.placed_hint(
                    &hint,
                    stop.center.x - painter.placed_hint_width(&hint) / 2.0,
                    stop.center.y,
                    Some(index) == layout.focus,
                );
            }
        }
    }
    let trunk = painter.draws.split_off(start);
    painter.draws.extend(route::fading(
        trunk,
        layout.fades_left,
        layout.fades_right,
        body,
    ));

    // 枝の線．選んでいない線をまとめて描き，選んだ道すじを選択の色と太さで上に重ねる
    let mut lines = Vec::new();
    let mut path = Vec::new();
    if let Some(focus) = layout.focus {
        let node = layout.nodes[focus];
        if let (Some(first), Some(last)) = (layout.rows.first(), layout.rows.last()) {
            let radius = bend_radius(&layout, *first, &metrics);
            lines.push(Line::rounded(
                stem_points(last.mid_y().round(), &layout, *first),
                radius,
            ));
            if let Some(row) = selected_row.and_then(|index| layout.rows.get(index)) {
                path.push(Line::rounded(
                    stem_points(row.mid_y().round(), &layout, *first),
                    radius,
                ));
            }
        }
        if !layout.kinds.is_empty() {
            let top = Point::new(layout.focus_x, node.y + metrics.row_inset);
            let corner = Point::new(layout.focus_x, layout.twig_y);
            lines.push(Line::rounded(
                vec![top, corner, Point::new(layout.twig_end_x, layout.twig_y)],
                metrics.turn_radius,
            ));
            if let Some(kind) = selected_variant.and_then(|index| layout.kinds.get(index)) {
                path.push(Line::rounded(
                    vec![top, corner, Point::new(kind.stop.x, layout.twig_y)],
                    metrics.turn_radius,
                ));
            }
        }
    }
    if let (Some(row), Some(last)) = (
        selected_row.and_then(|index| layout.rows.get(index)),
        layout.stations.last(),
    ) {
        let edge = if layout.direction > 0.0 {
            row.max_x()
        } else {
            row.x
        };
        lines.push(Line::new(vec![Point::new(edge, last.stop.y), last.stop]));
    }
    route::stroke(
        &mut painter,
        &lines,
        theme.line.faded(stale),
        metrics.line_width,
        &avoided,
        metrics.pixel_scale,
    );
    route::stroke(
        &mut painter,
        &path,
        theme.selection,
        metrics.line_width_selected,
        &avoided,
        metrics.pixel_scale,
    );
    route::draw_stops(&mut painter, &branch_stops, metrics.line_width);
    if let Some(dots) = layout.page_dots {
        route::page_dots(&mut painter, dots.x, dots.top, dots.count, dots.current);
    }
    // 畳んでいる枝の，続きがある印．線の色のままだと透かした先が見えないので，控えめな文字の色から透かす
    for (from, to) in [layout.variant_stub, layout.detail_stub]
        .into_iter()
        .flatten()
    {
        route::fading_line(
            &mut painter,
            from,
            to,
            theme.text_muted.faded(stale),
            metrics.line_width,
        );
    }

    // 候補・文字種・先の枝の見出し
    for (index, row) in layout.rows.iter().enumerate().take(rows.len()) {
        draw_row(&mut painter, &rows[index], *row, layout.direction, on_trunk);
    }
    if let Some(column) = column {
        let keys = variant_keys(map, Some(column));
        for (index, kind) in layout.kinds.iter().enumerate() {
            let Some(text) = column.variants.get(index) else {
                continue;
            };
            draw_kind(
                &mut painter,
                text,
                keys.get(index).cloned().flatten().as_deref(),
                kind.label,
                Some(index) == selected_variant,
                stale,
            );
        }
    }
    for station in &layout.stations {
        let row = Frame::new(
            station.title_x,
            station.title_mid_y - glass::TAG_HEIGHT / 2.0,
            0.0,
            glass::TAG_HEIGHT,
        );
        painter.text(
            &station.title,
            Font::Label,
            theme.text_muted,
            station.title_x,
            row,
        );
    }

    // キーの案内と，文節の境目のつまみ
    if let Some(mid_y) = layout.boundary_mid_y.filter(|_| !hints.boundary.is_empty()) {
        painter.placed_hints(&hints.boundary, layout.boundary_x, mid_y);
        if let (Some(focus), Some(column)) = (layout.focus, column) {
            if column.split.is_none() && !editing(column) {
                let node = layout.nodes[focus];
                let height = painter.measure.height(Font::Trunk).round();
                route::grip(
                    &mut painter,
                    node.max_x() + map::SEGMENT_GAP,
                    node.mid_y(),
                    height,
                );
            }
        }
    }
    if let (Some(x), Some(hint), Some(kind)) = (
        layout.variant_hint_x,
        hints.variant.as_ref(),
        layout.kinds.first(),
    ) {
        painter.placed_hint(hint, x, kind.label.mid_y(), false);
    }
    if let (Some(x), Some(hint)) = (layout.expand_x, hints.expand.as_ref()) {
        painter.placed_hint(hint, x, layout.expand_mid_y, false);
    }
    if let Some(mid_y) = layout.bottom_mid_y {
        painter.placed_hints(&hints.candidates, layout.bottom_hints_x, mid_y);
        let row = Frame::new(0.0, mid_y - glass::TAG_HEIGHT / 2.0, 0.0, glass::TAG_HEIGHT);
        if !rows.is_empty() {
            painter.text(
                &position_text(map),
                Font::Label,
                theme.text_muted,
                layout.position_x,
                row,
            );
        }
        if let Some(source) = column.and_then(|column| column.source_name.as_deref()) {
            // 選んでいる候補が取り込んだ辞書の語なら，その辞書の名前を小さく出す(R-16)
            painter.text(
                &strings::dictionary_source(source),
                Font::Label,
                theme.correction,
                layout.source_x,
                row,
            );
        }
    }

    // 候補の下の語の意味，注釈，知らせ
    if let (Some(slot), Some(card)) = (&layout.slot, layout.card) {
        meaning::draw(&mut painter, &slot.card, card);
    }
    let mut note_y = layout.notes_top;
    let content_width = body.width - metrics.text_inset() * 2.0;
    if let Some(note) = column.and_then(|column| column.usage_note.as_deref()) {
        let row = Frame::new(
            metrics.text_inset(),
            note_y + GAP,
            content_width,
            metrics.note_height,
        );
        painter.text(note, Font::Label, theme.text_muted, row.x, row);
        note_y = row.max_y();
    }
    if let Some(note) = map.note.as_ref() {
        // 打ち間違いを直したことなど，IME が変えたことを知らせる
        let row = Frame::new(
            metrics.text_inset(),
            note_y + GAP,
            content_width,
            metrics.note_height,
        );
        painter.note(note, row.x, row.mid_y());
    }

    // 押せる範囲と，語の意味の吹き出しに覆わせない範囲
    for (index, node) in layout.nodes.iter().enumerate() {
        // 文節は，文字と，その下の線の上の丸を押せる
        painter.hit(
            Frame::new(node.x, node.y, node.width, node.height + map::RAIL_HEIGHT),
            ipc::PointerTarget::Segment {
                index: index as u32,
            },
        );
        painter.keep_clear.push(*node);
    }
    // 区切っているあいだ(⇧↓)は番号キーで区切る位置を選ぶので，枝は押せない
    if let Some(column) = column.filter(|column| column.split.is_none()) {
        for (index, row) in layout.rows.iter().enumerate().take(rows.len()) {
            // コメントのタグは行の中にあるので，行より先に足す(押した位置は先に足した範囲から引く)．
            // タグを押すと候補の代わりにコメントを入れる
            if let Some(comment) = super::alternative_comment(column, index) {
                let frame = painter.tag_hit_frame(
                    comment,
                    tag_max_x(&painter, comment, *row, layout.direction),
                    *row,
                );
                painter.hit(
                    frame,
                    ipc::PointerTarget::Comment {
                        index: index as u32,
                    },
                );
            }
            painter.hit(
                row_area(*row, &layout),
                ipc::PointerTarget::Alternative {
                    index: index as u32,
                },
            );
            // 吹き出しは選んでいない候補の行を覆わない
            if Some(index) != selected_row {
                painter.keep_clear.push(*row);
            }
        }
        for (index, kind) in layout.kinds.iter().enumerate() {
            painter.hit(
                kind_area(kind),
                ipc::PointerTarget::Variant {
                    index: index as u32,
                },
            );
            painter.keep_clear.push(kind.label);
        }
    }
    if let Some(mid_y) = layout.boundary_mid_y {
        painter.keep_clear.push(Frame::new(
            body.x,
            mid_y - glass::TAG_HEIGHT / 2.0,
            body.width,
            glass::TAG_HEIGHT,
        ));
    }
    // 候補の下の行・候補の下の語の意味・注釈・知らせ
    let rows_bottom = layout
        .rows
        .last()
        .map_or(layout.rail_y + map::RAIL_HEIGHT / 2.0, |row| row.max_y());
    painter.keep_clear.push(Frame::new(
        body.x,
        rows_bottom,
        body.width,
        (body.max_y() - rows_bottom).max(0.0),
    ));
    painter.finish(width, height)
}

/// その場で打ち直している文節(⇧⌫)の幹．塗らずに選択の色の枠線で囲み，打っている読みのあとに入力位置の線を置く．
/// 読みが空のあいだも枠を残し，どこを打ち直しているかを見せる
fn editing_node(painter: &mut Painter, column: &BranchColumn, node: Frame) {
    let theme = painter.theme;
    let stroke = part::STROKE;
    let (frame, radius) = if theme.is_rounded() {
        (
            node.inset(stroke / 2.0, glass::SELECTION_INSET_Y + stroke / 2.0),
            glass::SELECTION_RADIUS,
        )
    } else {
        (node.inset(stroke / 2.0, stroke / 2.0), 0.0)
    };
    painter.draws.push(Draw::RoundRect {
        frame,
        radius,
        fill: None,
        stroke: Some((theme.selection, stroke)),
    });
    let x = node.x + part::ROW_PADDING_X;
    painter.text(&column.text, Font::Trunk, theme.text, x, node);
    let height = painter.measure.height(Font::Trunk).round();
    let caret_x = (x + painter.width(&column.text, Font::Trunk)).round();
    painter.rect(
        Frame::new(
            caret_x,
            (node.mid_y() - height / 2.0).round(),
            glass::EDITING_CARET_WIDTH,
            height,
        ),
        theme.selection,
    );
}

/// on_trunk は，矢印で木をたどっていて幹の上(文節)にいるか．そのときは文節を候補と同じ強い選択で見せる(今いる場所)
fn trunk_node(painter: &mut Painter, column: &BranchColumn, node: Frame, on_trunk: bool) {
    if editing(column) && column.split.is_none() {
        editing_node(painter, column, node);
        return;
    }
    let theme = painter.theme;
    let rounded = theme.is_rounded();
    let strong = column.is_focused && (on_trunk || !rounded);
    if column.is_focused {
        if rounded {
            let fill = if on_trunk {
                theme.selection
            } else {
                theme.focus_tint
            };
            painter.capsule(node.inset(0.0, glass::SELECTION_INSET_Y), fill);
        } else {
            painter.rect(node, theme.selection);
        }
    }
    let color = if strong {
        theme.selection_text
    } else {
        theme.text
    };
    match (&column.split, trunk_command(column)) {
        (Some(split), _) => draw_split(painter, split, node, color),
        (None, Some((kind, title))) => {
            // コマンドを選んでいれば，幹も枝と同じく種類のアイコンと名前で見せる(入力中の文字には印を付けた名前が出る)
            let x = node.x + part::ROW_PADDING_X;
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
            node.x + part::ROW_PADDING_X,
            node,
        ),
    }
    if column.is_corrected == Some(true) {
        // 打ち間違いを直した文節には，文字のあとに補正の色で「修正」と添える．確信の低い文節の点線と見分けるため
        painter.tag(
            strings::CORRECTED,
            node.max_x() - part::ROW_PADDING_X,
            node.mid_y(),
            !rounded && column.is_focused,
            TagStyle::Corrected,
        );
    }
}

/// 区切っている文節の幹．切れ目(「問題｜が｜ある」)に，小さな丸で番号を描く
fn draw_split(painter: &mut Painter, split: &BranchSplit, node: Frame, color: crate::theme::Color) {
    let pieces = split_pieces(split, painter);
    let left = node.x + part::ROW_PADDING_X;
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

/// 候補の行．縦の線に近い側から，番号・文字・添え書きの順に並べる(枝を左右に反転したときは右から)．
/// soft なら(幹の上にいる)，選んでいる候補を文節と同じ薄い背景にして，文字はふつうの色のままにする
fn draw_row(painter: &mut Painter, row: &Row, frame: Frame, direction: f32, soft: bool) {
    let theme = painter.theme;
    let rounded = theme.is_rounded();
    let solid = row.selected && !soft;
    let opacity = if row.selected { 1.0 } else { row.opacity };
    let text_color = if solid {
        theme.selection_text
    } else {
        theme.text
    }
    .faded(opacity);
    let muted_color = if solid {
        theme.selection_text
    } else {
        theme.text_muted
    }
    .faded(opacity);
    if row.selected {
        let fill = if solid {
            theme.selection
        } else {
            theme.focus_tint
        };
        if rounded {
            painter.capsule(frame.inset(0.0, glass::SELECTION_INSET_Y), fill);
        } else {
            painter.rect(frame, fill);
        }
    }
    // 番号は番号キーで選べるので，キーキャップの形にする
    let badge_x = if direction > 0.0 {
        frame.x + part::ROW_PADDING_X
    } else {
        frame.max_x() - part::ROW_PADDING_X - glass::BADGE_SIZE
    };
    let badge = Frame::new(
        badge_x.round(),
        (frame.mid_y() - glass::BADGE_SIZE / 2.0).round(),
        glass::BADGE_SIZE,
        glass::BADGE_SIZE,
    );
    if rounded {
        painter.badge_box(badge, solid);
    }
    painter.label(&row.badge, muted_color, badge, Font::Key);
    let content_width = row.command.map_or(0.0, |_| Painter::command_width())
        + painter.width(&row.text, Font::Candidate)
        + painter.detail_width(row.detail.as_deref());
    let mut text_x = if direction > 0.0 {
        badge.max_x() + glass::BADGE_GAP
    } else {
        badge.x - glass::BADGE_GAP - content_width
    };
    if let Some(kind) = row.command {
        // コマンドの候補は，文字の前に種類のアイコンを置く
        painter.command(kind, text_x, frame.mid_y(), solid, opacity);
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
            tag_max_x(painter, note, frame, direction),
            frame.mid_y(),
            solid,
            TagStyle::of(note, row.command.is_some()),
        );
    }
}

/// 文字種．選んでいるものは選択の背景で囲む．key があれば，文字の前にその文字種にするキーを置く
fn draw_kind(
    painter: &mut Painter,
    text: &str,
    key: Option<&str>,
    label: Frame,
    selected: bool,
    opacity: f32,
) {
    let theme = painter.theme;
    if selected {
        if theme.is_rounded() {
            painter.capsule(label, theme.selection);
        } else {
            painter.rect(label, theme.selection);
        }
    }
    let color = if selected {
        theme.selection_text
    } else {
        theme.text.faded(opacity)
    };
    let mut text_x = label.x + part::ROW_PADDING_X;
    if let Some(key) = key {
        painter.key_mark(key, text_x, label.mid_y(), selected);
        text_x += painter.key_mark_width(key) + space::INLINE;
    }
    painter.text(text, Font::Label, color, text_x, label);
}

#[cfg(test)]
mod tests {
    use super::super::testing::*;
    use super::*;
    use crate::theme::ResolvedTheme;

    fn column(text: &str, focused: bool) -> BranchColumn {
        BranchColumn {
            is_editing: None,
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
            jump_key: None,
            variant_keys: None,
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
            collapses_variants: None,
            collapses_detail: None,
            placed_hints: None,
            trunk_focused: None,
            page_size: None,
            hints_on_hold: None,
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
    fn 打ち直している文節は塗らずに枠線で囲み_読みと入力位置の線を出し_枝を薄くする() {
        for name in ["automatic", "platinum"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let mut editing = map();
            editing.columns[0].text = "かな".into();
            editing.columns[0].is_editing = Some(true);
            editing.columns[0].selected_alternative = None;
            let scene = branch_map(&editing, &look, &Fixed);
            // 幹のその文節は打っている読み．塗らない枠線
            assert!(
                texts(&scene)
                    .iter()
                    .any(|(text, color)| text == "かな" && *color == theme.text),
                "{name}"
            );
            assert!(scene.draws.iter().any(|draw| matches!(draw,
                Draw::RoundRect { fill: None, stroke: Some((color, _)), .. } if *color == theme.selection)), "{name}");
            // 入力位置の線
            assert!(scene.draws.iter().any(|draw| matches!(draw,
                Draw::Rect { frame, color } if frame.width == glass::EDITING_CARET_WIDTH && *color == theme.selection)), "{name}");
            // 枝(打ち直す前の候補)は薄い
            let stale = theme.text.faded(tokens::opacity::candidate::EDITING_STALE);
            assert!(
                texts(&scene)
                    .iter()
                    .any(|(text, color)| text == "今日は" && *color == stale),
                "{name}"
            );
            // 読みが空でも枠の幅を残す
            editing.columns[0].text = String::new();
            let empty = branch_map(&editing, &look, &Fixed);
            let frame = empty
                .draws
                .iter()
                .find_map(|draw| match draw {
                    // 線の上の丸の輪より大きい枠
                    Draw::RoundRect {
                        frame,
                        fill: None,
                        stroke: Some(_),
                        ..
                    } if frame.height > map::STOP_SIZE_SELECTED => Some(*frame),
                    _ => None,
                })
                .expect("枠線");
            assert!(frame.width >= glass::EDITING_MIN_WIDTH, "{name}");
        }
    }

    #[test]
    fn 連想の見出しが窓の幅を決めるときは説明と位置のあいだを_group_だけ空ける() {
        use super::super::association::testing::{gap, long};
        for name in ["platinum", "automatic"] {
            let theme = theme(name);
            let mut associated = map();
            associated.association = Some(long());
            let scene = branch_map(&associated, &Look::new(&theme, 15.0), &Fixed);
            assert_eq!(gap(&scene), space::GROUP, "{name}");
        }
    }

    #[test]
    fn コマンドの枝は種類のアイコンとタグを付け_選ぶと幹も印の代わりにアイコンで見せる() {
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
            // 案内は押せない
            let keyed = branch_map(&keyed(map()), &Look::new(&theme, 15.0), &Fixed);
            let hint = text_frame(&keyed, "再入力").expect("案内がある");
            assert_eq!(keyed.target_at(hint.x + 1.0, hint.mid_y()), None);
        }
    }

    #[test]
    fn コメントのタグを押すとコメント_タグの外の枝と_コメントでないタグは候補() {
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
            let tag = text_frame(&scene, "千代田区千代田1-1").expect("タグを描く");
            assert_eq!(
                scene.target_at(tag.mid_x(), tag.mid_y()),
                Some(comment.clone())
            );
            // タグの上下の空きも，枝の行の高さいっぱいまでタグとして押せる
            let row = hit(ipc::PointerTarget::Alternative { index: 0 }).expect("枝の行");
            let area = hit(comment.clone()).expect("タグを押せる範囲");
            assert_eq!((area.y, area.height), (row.y, row.height), "{name}");
            assert!(area.max_x() <= row.max_x(), "{name}");
            assert_eq!(scene.target_at(tag.mid_x(), row.y + 1.0), Some(comment));
            // タグの左(候補の文字の側)は候補
            assert_eq!(
                scene.target_at(area.x - 1.0, row.mid_y()),
                Some(ipc::PointerTarget::Alternative { index: 0 })
            );
            // コメントでないタグ(修正)は押しても候補
            let corrected = scene
                .draws
                .iter()
                .filter_map(|draw| match draw {
                    Draw::Text { text, frame, .. } if text == "修正" => Some(*frame),
                    _ => None,
                })
                .find(|frame| frame.y > row.y)
                .expect("枝のタグを描く");
            assert_eq!(
                scene.target_at(corrected.mid_x(), corrected.mid_y()),
                Some(ipc::PointerTarget::Alternative { index: 1 })
            );
        }
        // コメントの無い分岐図にはタグの押せる範囲を足さない
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
            // 注目していない文節には，次の候補を添えない(線で選べる候補だけを出す)
            assert!(!texts.iter().any(|(text, _)| text == "腫れ"));
        }
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
                collapses_variants: None,
                collapses_detail: None,
                placed_hints: None,
                trunk_focused: None,
                page_size: None,
                hints_on_hold: None,
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
                    Draw::Ellipse { frame, .. } if frame.width == branch::SPLIT_BADGE_SIZE => {
                        Some(*frame)
                    }
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
    fn 吹き出しに出す設定では枝の窓に語の意味を入れず_選んでいる枝の行を指す() {
        for name in ["washi", "platinum", "automatic"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let shown = meaning_map(ipc::MeaningPlacement::Side);
            let scene = branch_map(&shown, &look, &Fixed);
            assert!(text_frame(&scene, "写真や動画を写す").is_none(), "{name}");
            // 意味の無い枝の窓と同じ大きさ
            let mut plain = shown.clone();
            plain.columns[1].homophone = None;
            let bare = branch_map(&plain, &look, &Fixed);
            assert_eq!(
                (scene.width, scene.height),
                (bare.width, bare.height),
                "{name}"
            );
            // 吹き出しは選んでいる枝の行を指し，同音語のタグには枝に出ていない語だけを出す
            let (note, others, row) =
                super::super::bubble::for_branch(&shown, &scene).expect("吹き出し");
            assert_eq!(note.word, "撮る");
            assert_eq!(others, vec!["採る".to_string()]);
            let selected = scene
                .hits
                .iter()
                .find(|hit| hit.target == ipc::PointerTarget::Alternative { index: 1 })
                .map(|hit| hit.frame)
                .expect("選んでいる枝");
            assert_eq!(row, selected, "{name}");
            // 意味の無い枝を選んだら出さない
            assert!(super::super::bubble::for_branch(&plain, &bare).is_none());
        }
    }

    #[test]
    fn 分岐図で候補の下に出す設定では候補の下に窓の幅いっぱいのカードを出す() {
        for name in ["washi", "platinum"] {
            let theme = theme(name);
            let look = Look::new(&theme, 15.0);
            let scene = branch_map(&meaning_map(ipc::MeaningPlacement::Below), &look, &Fixed);
            let meaning = text_frame(&scene, "写真や動画を写す").expect("意味を描く");
            let last = text_frame(&scene, "とる").expect("最後の枝");
            assert!(meaning.y > last.max_y(), "{name}");
            assert!(meaning.x < last.x, "{name}");
            // 吹き出しには出さない
            let map = meaning_map(ipc::MeaningPlacement::Below);
            assert!(
                super::super::bubble::for_branch(&map, &scene).is_none(),
                "{name}"
            );
        }
    }

    #[test]
    fn 区切っているあいだは語の意味を出さない() {
        let theme = theme("washi");
        let mut splitting = meaning_map(ipc::MeaningPlacement::Side);
        splitting.columns[1].split = Some(BranchSplit {
            pieces: vec!["撮".into(), "る".into()],
        });
        let scene = branch_map(&splitting, &Look::new(&theme, 15.0), &Fixed);
        assert!(text_frame(&scene, "写真や動画を写す").is_none());
        assert!(super::super::bubble::for_branch(&splitting, &scene).is_none());
    }

    /// 標準のキー設定の表のキーと置き場所ごとの案内を入れた分岐図
    fn keyed(map: BranchMap) -> BranchMap {
        super::super::sample::with_keys(map)
    }

    fn metrics_and_layout(map: &BranchMap, theme: &ResolvedTheme) -> Layout {
        let look = Look::new(theme, 15.0);
        let metrics = Metrics::new(&look, &Fixed);
        let painter = Painter::new(&look, &Fixed);
        layout(map, &metrics, &painter, 1.0)
    }

    #[test]
    fn 幹の文節の下の線に丸を置き_選んでいる文節の丸を選択の色で塗る() {
        for name in ["automatic", "platinum"] {
            let theme = theme(name);
            let scene = branch_map(&map(), &Look::new(&theme, 15.0), &Fixed);
            // 角丸のテーマは丸，platinum は四角
            let filled = scene.draws.iter().any(|draw| match draw {
                Draw::Ellipse { frame, color } | Draw::Rect { frame, color } => {
                    *color == theme.selection && frame.width == map::STOP_SIZE_SELECTED
                }
                _ => false,
            });
            assert!(filled, "{name}");
            // 選んでいない丸は輪
            assert!(
                scene.draws.iter().any(|draw| matches!(draw,
                Draw::RoundRect { fill: None, stroke: Some((color, _)), frame, .. }
                    if *color == theme.line && frame.width < map::STOP_SIZE)),
                "{name}"
            );
        }
    }

    #[test]
    fn 長い文節の丸は左から決まった距離_短い文節は真ん中() {
        let theme = theme("automatic");
        let look = Look::new(&theme, 15.0);
        let metrics = Metrics::new(&look, &Fixed);
        // 短い文節は真ん中
        assert_eq!(metrics.stop_offset(20.0), 10.0);
        // 長い文節は 1 字と余白
        assert_eq!(metrics.stop_offset(200.0), 15.0 + part::ROW_PADDING_X);
        // 選んでいる文節から下ろす縦の線も同じ位置
        let mut long = map();
        long.columns[0].text = "とてもとても長い文節".into();
        let layout = metrics_and_layout(&long, &theme);
        assert_eq!(
            layout.focus_x,
            layout.nodes[0].x + 15.0 + part::ROW_PADDING_X
        );
    }

    #[test]
    fn 文節へ移るキーを丸に重ね_選んでいる文節のキーは選択の色の面にする() {
        let theme = theme("automatic");
        let look = Look::new(&theme, 15.0);
        let scene = branch_map(&keyed(map()), &look, &Fixed);
        let faces = |scene: &Scene, color| {
            scene
                .draws
                .iter()
                .filter(|draw| {
                    matches!(draw, Draw::RoundRect { fill: Some(fill), radius, .. }
                    if *fill == color && *radius == map::BADGE_RADIUS)
                })
                .count()
        };
        assert_eq!(faces(&scene, theme.selection), 1);
        assert!(faces(&scene, theme.hint_fill()) >= 2);
        // 案内を出さない設定(置き場所ごとの案内を送らない)では出さない
        let mut silent = keyed(map());
        silent.placed_hints = None;
        let quiet = branch_map(&silent, &look, &Fixed);
        assert_eq!(faces(&quiet, theme.selection), 0);
        assert!(text_frame(&quiet, "再入力").is_none());
        // 区切っているあいだは，番号キーが別の意味になるので出さない
        let mut splitting = keyed(map());
        splitting.columns[0].split = Some(BranchSplit {
            pieces: vec!["今日".into(), "は".into()],
        });
        let split = branch_map(&splitting, &look, &Fixed);
        assert_eq!(faces(&split, theme.selection), 0);
    }

    #[test]
    fn キーの案内は操作する場所に置く() {
        let theme = theme("automatic");
        let scene = branch_map(&keyed(map()), &Look::new(&theme, 15.0), &Fixed);
        let frame = |text: &str| text_frame(&scene, text).expect(text);
        let node = frame("今日は");
        // 区切り・分割は文節の上
        assert!(frame("区切り").max_y() <= node.y);
        assert!(frame("分割").max_y() <= node.y);
        // 文字種は上の枝の先(文字種の文字の右)
        assert!(frame("文字種").x > frame("きょうは").max_x());
        // 再入力・表形式は候補の下
        let last = frame("京は");
        assert!(frame("再入力").y >= last.max_y());
        assert!(frame("表形式").y >= last.max_y());
        // 文字種にするキー(F6)を文字種の前に置く
        assert!(frame("F6").max_x() <= frame("きょうは").x);
    }

    #[test]
    fn 枝が右に入らなければ左右に反転して左へ出す() {
        let theme = theme("automatic");
        let last = super::super::sample::long_branch(13);
        let layout = metrics_and_layout(&last, &theme);
        assert_eq!(layout.direction, -1.0);
        assert!(layout.rows.iter().all(|row| row.max_x() <= layout.stem_x));
        let first = super::super::sample::long_branch(0);
        assert_eq!(metrics_and_layout(&first, &theme).direction, 1.0);
    }

    #[test]
    fn 長い文は選んでいる文節が見えるまで幹を送り_はみ出した側を透かす() {
        let theme = theme("automatic");
        let look = Look::new(&theme, 15.0);
        let last = super::super::sample::long_branch(13);
        let layout = metrics_and_layout(&last, &theme);
        assert!(layout.width <= candidate::MAX_WIDTH);
        assert!(layout.fades_left && !layout.fades_right);
        assert!(layout.nodes[13].max_x() <= layout.width);
        let first = metrics_and_layout(&super::super::sample::long_branch(0), &theme);
        assert!(!first.fades_left && first.fades_right);
        // 透かす側は濃さを変えた帯で描く
        let scene = branch_map(&last, &look, &Fixed);
        assert!(
            count(
                &scene,
                |draw| matches!(draw, Draw::Group { opacity, .. } if *opacity < 1.0)
            ) > 0
        );
        // 収まる文は透かさない
        let short = branch_map(&map(), &look, &Fixed);
        assert_eq!(count(&short, |draw| matches!(draw, Draw::Group { .. })), 0);
    }

    #[test]
    fn 表示項目を減らす設定では畳んだ枝に続きがある印を出し_開くキーを案内する() {
        let theme = theme("automatic");
        let fewer = super::super::sample::fewer_branch();
        let layout = metrics_and_layout(&fewer, &theme);
        let (from, to) = layout.variant_stub.expect("文字種の印");
        assert!(to.y < from.y && from.x == to.x);
        let (from, to) = layout.detail_stub.expect("先の枝の印");
        assert_eq!(from.y, to.y);
        assert!(layout.expand_x.is_some());
        let scene = branch_map(&fewer, &Look::new(&theme, 15.0), &Fixed);
        assert!(text_frame(&scene, "展開").is_some());
        // 畳まない設定では出さない
        let plain = metrics_and_layout(&keyed(map()), &theme);
        assert!(plain.variant_stub.is_none() && plain.detail_stub.is_none());
    }

    #[test]
    fn 曲線の枝のテーマは角を丸め_platinum_とカスタムテーマの直線の枝は直角() {
        let arcs = |scene: &Scene| {
            scene
                .draws
                .iter()
                .filter_map(|draw| match draw {
                    Draw::Path { figures, .. } => Some(figures.clone()),
                    _ => None,
                })
                .flatten()
                .flat_map(|figure| figure.segments)
                .filter(|segment| matches!(segment, super::super::Segment::Arc { .. }))
                .count()
        };
        let nordic = theme("nordic");
        assert!(arcs(&branch_map(&map(), &Look::new(&nordic, 15.0), &Fixed)) > 0);
        let platinum = theme("platinum");
        assert_eq!(
            arcs(&branch_map(&map(), &Look::new(&platinum, 15.0), &Fixed)),
            0
        );
        let mut straight = theme("nordic");
        straight.straight_branches = true;
        assert_eq!(
            arcs(&branch_map(&map(), &Look::new(&straight, 15.0), &Fixed)),
            0
        );
        // 選んだ道すじは選択の色の太い線
        let scene = branch_map(&map(), &Look::new(&nordic, 15.0), &Fixed);
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::Path { color, width, .. } if *color == nordic.selection && *width == glass::LINE_WIDTH_SELECTED)));
        // 確信の低い文節の下の幹は点線
        assert!(scene.draws.iter().any(|draw| matches!(draw,
            Draw::Line { dot_pitch: Some(pitch), .. } if *pitch == glass::DOT_PITCH)));
    }

    #[test]
    fn ページの位置は縦の線の下の点で示し_多すぎれば数字_1_ページなら出さない() {
        let theme = theme("automatic");
        let look = Look::new(&theme, 15.0);
        let mut paged = keyed(map());
        paged.page_size = Some(2);
        paged.total = 6;
        paged.position = 3;
        let layout = metrics_and_layout(&paged, &theme);
        let dots = layout.page_dots.expect("ページの点");
        assert_eq!((dots.count, dots.current), (3, 1));
        assert_eq!(dots.x, layout.stem_x);
        let scene = branch_map(&paged, &look, &Fixed);
        assert!(!texts(&scene).iter().any(|(text, _)| text.contains('/')));
        // 点で示せないほど多いときは数字
        paged.total = 20;
        let many = branch_map(&paged, &look, &Fixed);
        assert!(texts(&many).iter().any(|(text, _)| text == "2 / 10"));
        assert!(metrics_and_layout(&paged, &theme).page_dots.is_none());
        // 1 ページなら出さない
        paged.total = 2;
        paged.position = 1;
        assert!(metrics_and_layout(&paged, &theme).page_dots.is_none());
        let single = branch_map(&paged, &look, &Fixed);
        assert!(!texts(&single).iter().any(|(text, _)| text.contains('/')));
    }

    #[test]
    fn 幹の上にいるときは文節を強い選択にし_選んでいる候補を薄い背景にする() {
        let theme = theme("automatic");
        let look = Look::new(&theme, 15.0);
        let mut trunk = keyed(map());
        trunk.trunk_focused = Some(true);
        let scene = branch_map(&trunk, &look, &Fixed);
        let texts = texts(&scene);
        assert!(texts.contains(&("今日は".into(), theme.selection_text)));
        assert!(texts.contains(&("京は".into(), theme.text)));
        // ふだんは候補が強い選択
        let plain = branch_map(&keyed(map()), &look, &Fixed);
        assert!(
            super::super::testing::texts(&plain).contains(&("京は".into(), theme.selection_text))
        );
    }
}
