#![forbid(unsafe_code)]

//! 候補の一覧の窓の区画の配置(core の CandidateListLayout と同じ決め方)．
//! 上から，文字種の行(連想の一覧では見出しの行)・候補・語の意味のカード・足元．
//!
//! 角丸のテーマ(Rounded)
//! - 縁の線の内側に，上下左右とも PADDING の余白を空ける．候補の行の地・区切りの線・カードの左右の端は余白の内側の端にそろう
//! - 区切りの線の上と下は SEPARATOR_GAP．候補の右のカードと一覧のあいだ，候補の下のカードと候補のあいだも同じ
//! - 候補の右のカードは，上の端を候補の 1 行目の地の上の端に，右の端を足元の区切りの線の右の端にそろえる
//!
//! platinum と desk(Bevel)
//! - 候補の行は立体の縁の内側いっぱいに置く(余白を空けない)．区画と区画は 1 ドットの線で区切る
//! - カードは枠を描かない区画にし，一覧とのあいだに線を引く(候補の右は縦の線，候補の下は横の線)．中の余白はカードの側が持つ
//!
//! 座標は窓の左上が原点で，下が y の正

use super::Frame;
use tokens::size::{candidate, glass};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Style {
    /// 角丸のテーマ
    Rounded,
    /// platinum と desk
    Bevel,
}

/// 候補の下に出す語の意味(候補の右に出す設定では窓の外の吹き出しに出すので，窓の区画には入らない)
#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) enum Card {
    /// 幅は窓の中身の幅の下限(below_card_width)で，語の意味は窓の中身の幅いっぱいに置く
    Below { width: f32, height: f32 },
}

/// 寸法．テーマの種類ごとの値は rounded・bevel
#[derive(Debug, Clone, Copy, PartialEq)]
pub(super) struct Metrics {
    /// 縁の線(角丸)，外枠と立体の縁(platinum と desk)の太さ
    pub edge: f32,
    /// 縁の内側の余白
    pub padding: f32,
    /// 区切りの線の上と下の空き
    pub separator_gap: f32,
    pub separator_width: f32,
    /// 候補の行の間隔(行の地の高さと，行と行のあいだの和)
    pub row_pitch: f32,
    /// 候補の行の地の上下を縮める量．行と行のあいだはこの 2 倍
    pub row_inset: f32,
    /// 文字種の行・連想の見出しの行の高さ
    pub header_height: f32,
    /// 足元の行の高さ
    pub footer_height: f32,
    /// desk の影の幅(右と下)
    pub shadow: f32,
}

impl Metrics {
    /// 角丸のテーマ．行の間隔と行の高さは文字の大きさで変わるので描く側が渡す
    pub fn rounded(row_pitch: f32, header_height: f32, footer_height: f32) -> Self {
        Self {
            edge: candidate::FRAME_WIDTH,
            padding: glass::WINDOW_PADDING,
            separator_gap: glass::SEPARATOR_GAP,
            separator_width: candidate::FRAME_WIDTH,
            row_pitch,
            row_inset: glass::SELECTION_INSET_Y,
            header_height,
            footer_height,
            shadow: 0.0,
        }
    }

    /// platinum と desk．文字種の行と足元の行は同じ高さ(section_height)
    pub fn bevel(row_pitch: f32, header_height: f32, footer_height: f32, has_shadow: bool) -> Self {
        Self {
            edge: candidate::FRAME_WIDTH + candidate::BEVEL_WIDTH,
            padding: glass::WINDOW_PADDING,
            separator_gap: glass::SEPARATOR_GAP,
            separator_width: candidate::FRAME_WIDTH,
            row_pitch,
            row_inset: 0.0,
            header_height,
            footer_height,
            shadow: if has_shadow {
                candidate::SHADOW_OFFSET
            } else {
                0.0
            },
        }
    }
}

/// 置いた区画
#[derive(Debug, Clone, PartialEq)]
pub(super) struct ListLayout {
    /// 窓の大きさ(desk の影を含む)
    pub width: f32,
    pub height: f32,
    /// 窓の枠(影を除く)
    pub body: Frame,
    /// 縁と余白の内側
    pub content: Frame,
    /// 文字種の行(連想の一覧では見出しの行)と，その下の区切りの線
    pub header: Option<Frame>,
    pub header_separator: Option<Frame>,
    /// 候補の行の地(角丸のテーマは選んだ行の地そのもの)
    pub rows: Vec<Frame>,
    /// 候補の行を押せる範囲(行と行のあいだを含む)
    pub hit_rows: Vec<Frame>,
    /// 語の意味の場所．箱は描かない．platinum と desk の候補の下は，card_separator で一覧と区切る
    pub card: Option<Frame>,
    pub card_separator: Option<Frame>,
    pub footer_separator: Frame,
    pub footer: Frame,
}

/// 候補の下のカードの幅(窓の中身の幅)．list_width は候補の列，footer_width は足元の中身，minimum はカードの幅の下限
pub(super) fn below_card_width(list_width: f32, footer_width: f32, minimum: f32) -> f32 {
    list_width.max(footer_width).max(minimum)
}

/// list_width は候補の列(行の地)の幅，footer_width は足元の中身の幅．
/// maximum_width は窓の幅の上限で，超えるときは候補の列を狭める(長い候補は描く側が末尾を省く)．
/// size は窓の大きさ(影を含む)を外から決めるとき(Look::size)．幅は候補の列で吸収し，区画は上から積む．
/// has_footer が偽なら足元の行と区切りの線を置かない(設定の画面の見本．区画は候補の列の下の端の高さ 0)
#[allow(clippy::too_many_arguments)]
pub(super) fn place(
    style: Style,
    list_width: f32,
    footer_width: f32,
    has_header: bool,
    row_count: usize,
    card: Option<Card>,
    maximum_width: f32,
    metrics: &Metrics,
    size: Option<(f32, f32)>,
    has_footer: bool,
) -> ListLayout {
    let outer = metrics.edge + metrics.padding;
    let gap = metrics.separator_gap;
    let line = metrics.separator_width;
    let content_width = match card {
        Some(Card::Below { width, .. }) => list_width.max(footer_width).max(width),
        None => list_width.max(footer_width),
    };
    let body_width = size.map_or_else(
        || {
            (content_width + outer * 2.0)
                .min((maximum_width - metrics.shadow).max(0.0))
                .ceil()
        },
        |(width, _)| width - metrics.shadow,
    );
    let content_width = body_width - outer * 2.0;

    let mut y = outer;
    let mut header = None;
    let mut header_separator = None;
    if has_header {
        header = Some(Frame::new(outer, y, 0.0, metrics.header_height));
        y += metrics.header_height + gap;
        header_separator = Some(Frame::new(outer, y, 0.0, line));
        y += line + gap;
    }
    let rows_top = y;
    let row_height = metrics.row_pitch - metrics.row_inset * 2.0;
    let rows_height = if row_count > 0 {
        metrics.row_pitch * row_count as f32 - metrics.row_inset * 2.0
    } else {
        0.0
    };
    let mut list_bottom = rows_top + rows_height;
    let list_column = content_width;
    let mut card_frame = None;
    let mut card_separator = None;
    match card {
        Some(Card::Below { height, .. }) => {
            // platinum と desk は，一覧とのあいだに区切りの線を引く(線の上と下は同じ空き)
            let mut top = list_bottom + gap;
            if style == Style::Bevel {
                card_separator = Some(Frame::new(outer, top, content_width, line));
                top += line + gap;
            }
            card_frame = Some(Frame::new(outer, top, content_width, height));
            list_bottom = top + height;
        }
        None => {}
    }
    let rows: Vec<Frame> = (0..row_count)
        .map(|index| {
            Frame::new(
                outer,
                rows_top + metrics.row_pitch * index as f32,
                list_column,
                row_height,
            )
        })
        .collect();
    let hit_rows = rows
        .iter()
        .map(|row| {
            Frame::new(
                row.x,
                row.y - metrics.row_inset,
                row.width,
                metrics.row_pitch,
            )
        })
        .collect();
    // 文字種の行と，その下の区切りの線は候補の列の幅
    let header = header.map(|frame: Frame| Frame::new(frame.x, frame.y, list_column, frame.height));
    let header_separator = header_separator
        .map(|frame: Frame| Frame::new(frame.x, frame.y, list_column, frame.height));
    let (footer_separator, footer) = if has_footer {
        y = list_bottom + gap;
        let separator = Frame::new(outer, y, content_width, line);
        y += line + gap;
        (
            separator,
            Frame::new(outer, y, content_width, metrics.footer_height),
        )
    } else {
        (
            Frame::new(outer, list_bottom, content_width, 0.0),
            Frame::new(outer, list_bottom, content_width, 0.0),
        )
    };
    let body_height = size.map_or_else(
        || (footer.max_y() + outer).ceil(),
        |(_, height)| height - metrics.shadow,
    );
    let body = Frame::new(0.0, 0.0, body_width, body_height);
    ListLayout {
        width: body.width + metrics.shadow,
        height: body.height + metrics.shadow,
        content: Frame::new(outer, outer, content_width, body.height - outer * 2.0),
        body,
        header,
        header_separator,
        rows,
        hit_rows,
        card: card_frame,
        card_separator,
        footer_separator,
        footer,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metrics(style: Style) -> Metrics {
        match style {
            Style::Rounded => Metrics::rounded(glass::ROW_HEIGHT, 20.0, 18.0),
            Style::Bevel => Metrics::bevel(candidate::ROW_HEIGHT, 20.0, 18.0, true),
        }
    }

    fn samples() -> Vec<(String, Style, bool, Option<Card>)> {
        [Style::Rounded, Style::Bevel]
            .into_iter()
            .flat_map(|style| {
                vec![
                    (format!("{style:?} カードなし"), style, false, None),
                    (
                        format!("{style:?} 下のカード"),
                        style,
                        false,
                        Some(Card::Below {
                            width: 312.0,
                            height: 120.0,
                        }),
                    ),
                    (
                        format!("{style:?} 文字種の行と下のカード"),
                        style,
                        true,
                        Some(Card::Below {
                            width: 312.0,
                            height: 120.0,
                        }),
                    ),
                ]
            })
            .collect()
    }

    fn placed() -> Vec<(String, Style, Option<Card>, ListLayout)> {
        samples()
            .into_iter()
            .map(|(name, style, header, card)| {
                let layout = place(
                    style,
                    180.0,
                    160.0,
                    header,
                    4,
                    card,
                    720.0,
                    &metrics(style),
                    None,
                    true,
                );
                (name, style, card, layout)
            })
            .collect()
    }

    fn parts(layout: &ListLayout) -> Vec<Frame> {
        let mut parts: Vec<Frame> = [
            layout.header,
            layout.header_separator,
            layout.card,
            layout.card_separator,
            Some(layout.footer_separator),
            Some(layout.footer),
        ]
        .into_iter()
        .flatten()
        .collect();
        parts.extend(layout.rows.iter().copied());
        parts
    }

    fn intersects(a: &Frame, b: &Frame) -> bool {
        a.x < b.max_x() && b.x < a.max_x() && a.y < b.max_y() && b.y < a.max_y()
    }

    #[test]
    fn 縁の内側の余白は上下左右で同じ() {
        for (name, style, _, layout) in placed() {
            let metrics = metrics(style);
            let outer = metrics.edge + metrics.padding;
            let parts = parts(&layout);
            let min_x = parts.iter().map(|part| part.x).fold(f32::MAX, f32::min);
            let min_y = parts.iter().map(|part| part.y).fold(f32::MAX, f32::min);
            let max_x = parts.iter().map(|part| part.max_x()).fold(0.0, f32::max);
            let max_y = parts.iter().map(|part| part.max_y()).fold(0.0, f32::max);
            assert_eq!(min_x, outer, "{name}");
            assert_eq!(min_y, outer, "{name}");
            assert!((layout.body.max_x() - max_x - outer).abs() <= 0.5, "{name}");
            assert!((layout.body.max_y() - max_y - outer).abs() <= 0.5, "{name}");
            assert_eq!(layout.width, layout.body.width + metrics.shadow, "{name}");
        }
    }

    #[test]
    fn 区切りの線の上と下は同じ間隔() {
        for (name, style, card, layout) in placed() {
            let metrics = metrics(style);
            let last = layout.rows.last().expect("候補");
            let bottom = last
                .max_y()
                .max(layout.card.map_or(0.0, |card| card.max_y()));
            assert_eq!(
                layout.footer_separator.y - bottom,
                metrics.separator_gap,
                "{name}"
            );
            assert_eq!(
                layout.footer.y - layout.footer_separator.max_y(),
                metrics.separator_gap,
                "{name}"
            );
            if let (Some(header), Some(line)) = (layout.header, layout.header_separator) {
                assert_eq!(line.y - header.max_y(), metrics.separator_gap, "{name}");
                assert_eq!(
                    layout.rows[0].y - line.max_y(),
                    metrics.separator_gap,
                    "{name}"
                );
            }
            if let (Some(Card::Below { .. }), Some(card)) = (card, layout.card) {
                // platinum と desk は一覧とのあいだに区切りの線を引き，線の上と下を同じ空きにする
                match (style, layout.card_separator) {
                    (Style::Bevel, Some(line)) => {
                        assert_eq!(line.y - last.max_y(), metrics.separator_gap, "{name}");
                        assert_eq!(card.y - line.max_y(), metrics.separator_gap, "{name}");
                    }
                    _ => assert_eq!(card.y - last.max_y(), metrics.separator_gap, "{name}"),
                }
            }
        }
    }

    #[test]
    fn 候補の下のカードの左右の端は区切りの線の端() {
        for (name, _, card, layout) in placed() {
            let Some(Card::Below { .. }) = card else {
                continue;
            };
            let card = layout.card.expect("カード");
            assert_eq!(card.x, layout.footer_separator.x, "{name}");
            assert_eq!(card.max_x(), layout.footer_separator.max_x(), "{name}");
        }
    }

    #[test]
    fn 候補の行の地は同じxと幅で押せる範囲は隙間なく並ぶ() {
        for (name, style, _, layout) in placed() {
            let metrics = metrics(style);
            assert!(layout
                .rows
                .iter()
                .all(|row| row.x == layout.rows[0].x && row.width == layout.rows[0].width));
            for pair in layout.rows.windows(2) {
                assert_eq!(
                    pair[1].y - pair[0].max_y(),
                    metrics.row_inset * 2.0,
                    "{name}"
                );
            }
            for pair in layout.hit_rows.windows(2) {
                assert_eq!(pair[1].y, pair[0].max_y(), "{name}");
            }
        }
    }

    #[test]
    fn 区画が重ならない() {
        for (name, _, _, layout) in placed() {
            let parts = parts(&layout);
            for (index, part) in parts.iter().enumerate() {
                for other in &parts[index + 1..] {
                    assert!(!intersects(part, other), "{name}: {part:?} と {other:?}");
                }
            }
        }
    }

    #[test]
    fn 足元を出さない窓は最後の候補の行の下に縁の内側の余白だけを置く() {
        for style in [Style::Rounded, Style::Bevel] {
            let metrics = metrics(style);
            let with = place(
                style, 180.0, 0.0, false, 6, None, 720.0, &metrics, None, true,
            );
            let without = place(
                style, 180.0, 0.0, false, 6, None, 720.0, &metrics, None, false,
            );
            let last = without.rows.last().copied().unwrap();
            let outer = metrics.edge + metrics.padding;
            assert_eq!(without.footer.height, 0.0);
            assert!((without.body.max_y() - last.max_y() - outer).abs() <= 0.5);
            assert!(without.height < with.height);
        }
    }

    #[test]
    fn 窓の幅の上限を超えるときは候補の列を狭める() {
        let metrics = metrics(Style::Rounded);
        let layout = place(
            Style::Rounded,
            800.0,
            160.0,
            false,
            3,
            None,
            720.0,
            &metrics,
            None,
            true,
        );
        assert!(layout.width <= 720.0);
        // 候補の行の右の端と足元の区切りの線の右の端はそろったまま
        assert_eq!(layout.rows[0].max_x(), layout.footer_separator.max_x());
    }
}
