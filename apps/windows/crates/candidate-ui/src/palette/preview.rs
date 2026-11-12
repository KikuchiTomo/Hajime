#![forbid(unsafe_code)]

//! パレットの説明の欄のうち，大きな見本の右と下に並べる名前・読み・札の配置(macOS の PalettePreviewDrawing)．
//!
//! 上から順に次を並べる．
//! - 見出しの名前．どこで定めた名前か(CLDR)を枠の札で後ろに添える．入らなければ折り返し，札は最後の行の後ろに置く
//! - Unicode の名前．どこで定めた名前か(Unicode・CLDR)の札を前に置き，入らなければ折り返す(続く行は札の後ろにそろえる)
//! - 読み．「読み」の札のあとに「、」で並べ，入らない読みは「+n」にまとめる
//! - ショートコードとコードポイント．等幅の字の札にし，札の途中では切らずに次の行へ送る．行より広い札は字を縮め，それでも入らなければ札の中で折り返す
//!
//! 項目は，見本の高さまでに始まるものは見本の右に，その下で始まるものは欄の幅いっぱいに置く(折り返した行は項目の 1 行目にそろえる)．
//! ピン留めのボタンの高さまでの行はボタンの手前で止める．
//! 欄の高さは出す項目の設定だけで決める(`height`)．選んでいる文字の中身が入りきらなければ，
//! Unicode の名前の行を減らし，見出しの名前を 1 行にし，読みを省き，Unicode の名前を省く順に詰める．それでも入らない札は「+n」にまとめる

use super::layout::Fonts;
use crate::geometry::Frame;
use crate::scene::fitting;
use crate::scene::Measure;
use crate::strings;
use crate::theme::Font;
use ipc::{PalettePreview, PalettePreviewFields};
use tokens::size::palette;

/// 描く部品．文字の枠の高さは行の高さで，描く側が縦に中央にそろえる
#[derive(Debug, Clone, PartialEq)]
pub enum Part {
    Text {
        text: String,
        font: Font,
        frame: Frame,
    },
    /// 名前を定めたところと「読み」の枠の札
    Tag { text: String, frame: Frame },
    /// ショートコードとコードポイントの札．行より広ければ字を縮め(small)，それでも入らなければ札の中で折り返す
    Chip {
        lines: Vec<String>,
        small: bool,
        frame: Frame,
    },
    /// 入らなかった読みや札の数(「+n」)
    More { count: usize, frame: Frame },
}

impl Part {
    pub fn frame(&self) -> Frame {
        match self {
            Self::Text { frame, .. }
            | Self::Tag { frame, .. }
            | Self::Chip { frame, .. }
            | Self::More { frame, .. } => *frame,
        }
    }

    fn is_chip(&self) -> bool {
        matches!(self, Self::Chip { .. })
    }
}

/// 欄の中で，名前・読み・札を置く場所(上下の余白を除いた欄)と，見本とピン留めのボタンが占める場所
#[derive(Debug, Clone, Copy)]
pub struct Area {
    pub content: Frame,
    pub tile: Frame,
    pub pin: Frame,
}

/// 説明の欄に出す項目．送られてこなければ(項目を選べないエンジン)すべて出す
pub fn fields(sent: Option<&PalettePreviewFields>) -> PalettePreviewFields {
    sent.cloned().unwrap_or(PalettePreviewFields {
        unicode_name: true,
        readings: true,
        shortcodes: true,
        code_points: true,
    })
}

/// 見本の枠の一辺(顔文字は横に広げる)
pub fn tile_side() -> f32 {
    palette::PREVIEW_GLYPH_SIZE + palette::PREVIEW_TILE_PADDING * 2.0
}

/// 欄(rect)から上下の余白を除いた，見本と名前を置く場所
pub fn content_area(rect: Frame) -> Frame {
    rect.inset(0.0, palette::PREVIEW_PADDING_Y)
}

/// 欄の高さ．見本の高さと，見込んだ行(見出し・Unicode の名前・読み・札)を積んだ高さの大きいほうに，上下の余白を足したもの
pub fn height(fields: &PalettePreviewFields, fonts: &Fonts, measure: &dyn Measure) -> f32 {
    let metrics = Metrics { fonts, measure };
    let mut height = metrics.name_row();
    if fields.unicode_name {
        height += palette::PREVIEW_LINE_GAP
            + metrics.detail_row()
            + metrics.line(fonts.detail) * (palette::PREVIEW_NAME_LINES - 1.0);
    }
    if fields.readings {
        height += palette::PREVIEW_LINE_GAP + metrics.detail_row();
    }
    if fields.shortcodes || fields.code_points {
        let lines = palette::PREVIEW_CHIP_LINES;
        height += palette::PREVIEW_LINE_GAP
            + metrics.chip_height(1, false) * lines
            + palette::PREVIEW_CHIP_GAP * (lines - 1.0);
    }
    (height.max(tile_side()) + palette::PREVIEW_PADDING_Y * 2.0).ceil()
}

/// 名前・読み・札の部品．入りきらなければ詰める
pub fn parts(
    shown: &PalettePreview,
    area: &Area,
    fonts: &Fonts,
    measure: &dyn Measure,
) -> Vec<Part> {
    let metrics = Metrics { fonts, measure };
    let mut options = Options::default();
    let mut parts = plan(shown, &options, area, &metrics);
    // 入りきらなければ，Unicode の名前の行を見込んだ数まで減らし，見出しの名前を 1 行にし，読みを省き，Unicode の名前を 1 行にし，省く
    let steps: [fn(&mut Options); 5] = [
        |options| {
            options.unicode_lines = options
                .unicode_lines
                .min(palette::PREVIEW_NAME_LINES as usize)
        },
        |options| options.heading_lines = 1,
        |options| options.readings = false,
        |options| options.unicode_lines = 1,
        |options| options.unicode_name = false,
    ];
    for step in steps {
        if bottom(&parts) <= area.content.max_y() {
            break;
        }
        step(&mut options);
        parts = plan(shown, &options, area, &metrics);
    }
    limiting_chips(parts, area, &metrics)
}

/// 詰めるときに変えるもの
struct Options {
    heading_lines: usize,
    unicode_lines: usize,
    readings: bool,
    unicode_name: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            heading_lines: palette::PREVIEW_HEADING_MAX_LINES as usize,
            unicode_lines: palette::PREVIEW_NAME_MAX_LINES as usize,
            readings: true,
            unicode_name: true,
        }
    }
}

/// 書体ごとの行の高さと文字の幅
struct Metrics<'a> {
    fonts: &'a Fonts,
    measure: &'a dyn Measure,
}

impl Metrics<'_> {
    fn line(&self, font: Font) -> f32 {
        self.measure.height(font).ceil()
    }

    fn width(&self, text: &str, font: Font) -> f32 {
        if text.is_empty() {
            0.0
        } else {
            self.measure.width(text, font).ceil()
        }
    }

    fn tag_height(&self) -> f32 {
        self.line(self.fonts.tag) + palette::PREVIEW_CHIP_PADDING_Y
    }

    /// 札を添える行の高さ
    fn name_row(&self) -> f32 {
        self.line(self.fonts.name).max(self.tag_height())
    }

    fn detail_row(&self) -> f32 {
        self.line(self.fonts.detail).max(self.tag_height())
    }

    fn chip_height(&self, lines: usize, small: bool) -> f32 {
        let font = if small {
            self.fonts.code_small
        } else {
            self.fonts.code
        };
        self.line(font) * lines as f32 + palette::PREVIEW_CHIP_PADDING_Y * 2.0
    }

    fn tag_width(&self, text: &str) -> f32 {
        self.width(text, self.fonts.tag) + palette::PREVIEW_TAG_PADDING_X * 2.0
    }

    fn more_width(&self, count: usize) -> f32 {
        self.width(&strings::more(count), self.fonts.detail)
    }

    fn measure_with(&self, font: Font) -> impl Fn(&str) -> f32 + '_ {
        move |text: &str| self.width(text, font)
    }
}

/// y から始まる行の左右の端．見本の高さまでは見本の右，ピン留めのボタンの高さまではボタンの手前まで
fn span(y: f32, area: &Area) -> (f32, f32) {
    let min_x = if y < area.tile.max_y() {
        area.tile.max_x() + palette::PREVIEW_GAP
    } else {
        area.content.x
    };
    let max_x = if y < area.pin.max_y() {
        area.pin.x
    } else {
        area.content.max_x()
    };
    (min_x, max_x)
}

/// 折り返して置く文字の書式．indent は行の左の端からずらす幅(札の後ろにそろえる)，reserve は行の右に空けておく幅(後ろに置く札の分)．
/// rows は 1 行目(札を置く行)と続く行の高さ
struct Block {
    font: Font,
    max_lines: usize,
    indent: f32,
    reserve: f32,
    rows: (f32, f32),
}

/// 折り返した 1 行．frame の高さは行の高さ
struct Line {
    text: String,
    frame: Frame,
}

/// top から text を折り返して置いた行．左の端は 1 行目の位置(span)にそろえ，右の端は行ごとに決める．
/// max_lines を超える分は最後の行の末尾を「…」で省く
fn flow(text: &str, block: &Block, top: f32, area: &Area, metrics: &Metrics) -> Vec<Line> {
    let measure = metrics.measure_with(block.font);
    let mut lines: Vec<Line> = Vec::new();
    let mut rest: Vec<char> = text.chars().collect();
    let mut y = top;
    // 続く行も 1 行目と同じ左の端から書く(見本の下に回り込ませると，札の後ろにそろわない)
    let x = span(top, area).0 + block.indent;
    while !rest.is_empty() && lines.len() < block.max_lines {
        let width = span(y, area).1 - x - block.reserve;
        let count = fitting::line_break(&rest, width, &measure);
        let last = lines.len() + 1 == block.max_lines && count < rest.len();
        let shown = if last {
            fitting::truncated(&rest.iter().collect::<String>(), width, &measure)
        } else {
            rest[..count].iter().collect::<String>().trim().to_string()
        };
        let row = if lines.is_empty() {
            block.rows.0
        } else {
            block.rows.1
        };
        lines.push(Line {
            frame: Frame::new(x.round(), y.round(), metrics.width(&shown, block.font), row),
            text: shown,
        });
        y += row;
        rest = if last {
            Vec::new()
        } else {
            rest[count..]
                .iter()
                .skip_while(|character| **character == ' ')
                .copied()
                .collect()
        };
    }
    lines
}

/// 行(高さ row)の中で縦に中央にそろえた枠
fn centered(x: f32, y: f32, width: f32, height: f32, row: f32) -> Frame {
    Frame::new(x.round(), (y + (row - height) / 2.0).round(), width, height)
}

fn plan(shown: &PalettePreview, options: &Options, area: &Area, metrics: &Metrics) -> Vec<Part> {
    let fonts = metrics.fonts;
    let mut parts = Vec::new();
    let mut y = area.content.y;
    // 見出しの名前と，どこで定めた名前かの札．札は最後の行の後ろに置く
    let tag_space = shown.name_source.as_deref().map_or(0.0, |source| {
        metrics.tag_width(source) + palette::PREVIEW_TAG_GAP
    });
    let heading = flow(
        &shown.japanese_name,
        &Block {
            font: fonts.name,
            max_lines: options.heading_lines,
            indent: 0.0,
            reserve: tag_space,
            rows: (metrics.name_row(), metrics.line(fonts.name)),
        },
        y,
        area,
        metrics,
    );
    if let (Some(source), Some(last)) = (shown.name_source.as_deref(), heading.last()) {
        parts.push(Part::Tag {
            text: source.to_string(),
            frame: centered(
                last.frame.max_x() + palette::PREVIEW_TAG_GAP,
                last.frame.y,
                metrics.tag_width(source),
                metrics.tag_height(),
                last.frame.height,
            ),
        });
    }
    y = heading
        .last()
        .map_or(y + metrics.name_row(), |line| line.frame.max_y());
    parts.extend(heading.into_iter().map(|line| Part::Text {
        text: line.text,
        font: fonts.name,
        frame: line.frame,
    }));
    // Unicode の名前．札の後ろから書き，折り返した行も札の後ろにそろえる
    if options.unicode_name && !shown.english_name.is_empty() {
        y += palette::PREVIEW_LINE_GAP;
        let detail_row = metrics.detail_row();
        let mut indent = 0.0;
        if let Some(source) = shown.english_name_source.as_deref() {
            let width = metrics.tag_width(source);
            parts.push(Part::Tag {
                text: source.to_string(),
                frame: centered(span(y, area).0, y, width, metrics.tag_height(), detail_row),
            });
            indent = width + palette::PREVIEW_TAG_GAP;
        }
        let lines = flow(
            &shown.english_name,
            &Block {
                font: fonts.detail,
                max_lines: options.unicode_lines,
                indent,
                reserve: 0.0,
                rows: (detail_row, metrics.line(fonts.detail)),
            },
            y,
            area,
            metrics,
        );
        y = lines.last().map_or(y, |line| line.frame.max_y());
        parts.extend(lines.into_iter().map(|line| Part::Text {
            text: line.text,
            font: fonts.detail,
            frame: line.frame,
        }));
    }
    // 読み．入る数だけ並べ，残りの数を添える
    if options.readings && !shown.readings.is_empty() {
        y += palette::PREVIEW_LINE_GAP;
        let (min_x, max_x) = span(y, area);
        let detail_row = metrics.detail_row();
        let label_width = metrics.tag_width(strings::PALETTE_READINGS);
        parts.push(Part::Tag {
            text: strings::PALETTE_READINGS.to_string(),
            frame: centered(min_x, y, label_width, metrics.tag_height(), detail_row),
        });
        let x = min_x + label_width + palette::PREVIEW_TAG_GAP;
        let (text, rest) = fitting_readings(&shown.readings, max_x - x, metrics);
        let width = metrics.width(&text, fonts.detail);
        parts.push(Part::Text {
            text,
            font: fonts.detail,
            frame: Frame::new(x.round(), y.round(), width, detail_row),
        });
        if rest > 0 {
            parts.push(Part::More {
                count: rest,
                frame: Frame::new(
                    (x + width + palette::PREVIEW_TAG_GAP).round(),
                    y.round(),
                    metrics.more_width(rest),
                    detail_row,
                ),
            });
        }
        y += detail_row;
    }
    // ショートコードとコードポイントの札．入らない札は次の行へ送り，行より広い札は字を縮め，それでも入らなければ札の中で折り返す
    let chips: Vec<&str> = shown
        .shortcodes
        .iter()
        .map(String::as_str)
        .chain(shown.code_points.split_whitespace())
        .collect();
    if chips.is_empty() {
        return parts;
    }
    y += palette::PREVIEW_LINE_GAP;
    let (mut min_x, mut max_x) = span(y, area);
    let mut x = min_x;
    let mut row = 0.0_f32;
    let measure = metrics.measure_with(fonts.code_small);
    for chip in chips {
        let mut lines = vec![chip.to_string()];
        let mut width = metrics.width(chip, fonts.code) + palette::PREVIEW_CHIP_PADDING_X * 2.0;
        if x > min_x && x + width > max_x {
            y += row + palette::PREVIEW_CHIP_GAP;
            (min_x, max_x) = span(y, area);
            x = min_x;
            row = 0.0;
        }
        let row_width = max_x - min_x;
        let small = width > row_width;
        if small {
            width = metrics.width(chip, fonts.code_small) + palette::PREVIEW_CHIP_PADDING_X * 2.0;
            if width > row_width {
                width = row_width;
                lines = fitting::wrapped(
                    chip,
                    width - palette::PREVIEW_CHIP_PADDING_X * 2.0,
                    usize::MAX,
                    &measure,
                );
            }
        }
        let height = metrics.chip_height(lines.len(), small);
        parts.push(Part::Chip {
            lines,
            small,
            frame: Frame::new(x.round(), y.round(), width, height),
        });
        x += width + palette::PREVIEW_CHIP_GAP;
        row = row.max(height);
    }
    parts
}

fn bottom(parts: &[Part]) -> f32 {
    parts
        .iter()
        .map(|part| part.frame().max_y())
        .fold(0.0, f32::max)
}

/// 欄の下の端を越える札を除き，除いた数を最後に残した札の後ろに「+n」で示す．「+n」が入らなければその札も除く
fn limiting_chips(parts: Vec<Part>, area: &Area, metrics: &Metrics) -> Vec<Part> {
    let limit = area.content.max_y();
    if bottom(&parts) <= limit {
        return parts;
    }
    let total = parts.iter().filter(|part| part.is_chip()).count();
    let mut kept: Vec<Part> = parts
        .into_iter()
        .filter(|part| !part.is_chip() || part.frame().max_y() <= limit)
        .collect();
    while let Some(index) = kept.iter().rposition(Part::is_chip) {
        let last = kept[index].frame();
        let dropped = total - kept.iter().filter(|part| part.is_chip()).count();
        let more = Frame::new(
            last.max_x() + palette::PREVIEW_CHIP_GAP,
            last.y,
            metrics.more_width(dropped),
            last.height,
        );
        if more.max_x() <= span(last.y, area).1 {
            kept.push(Part::More {
                count: dropped,
                frame: more,
            });
            return kept;
        }
        kept.remove(index);
    }
    kept
}

/// 幅に入る数の読み(「、」でつなぐ)と，入らなかった読みの数．1 つ目も入らなければ末尾を省く
fn fitting_readings(readings: &[String], width: f32, metrics: &Metrics) -> (String, usize) {
    let fonts = metrics.fonts;
    let more = |rest: usize| {
        if rest > 0 {
            palette::PREVIEW_TAG_GAP + metrics.more_width(rest)
        } else {
            0.0
        }
    };
    for count in (1..=readings.len()).rev() {
        let text = readings[..count].join(strings::PALETTE_READING_SEPARATOR);
        let rest = readings.len() - count;
        if metrics.width(&text, fonts.detail) + more(rest) <= width {
            return (text, rest);
        }
    }
    let rest = readings.len().saturating_sub(1);
    let first = readings.first().map(String::as_str).unwrap_or_default();
    (
        fitting::truncated(
            first,
            width - more(rest),
            &metrics.measure_with(fonts.detail),
        ),
        rest,
    )
}

#[cfg(test)]
mod tests {
    use super::super::sample;
    use super::*;
    use crate::scene::testing::Fixed;

    fn fonts() -> Fonts {
        Fonts::new(36.0)
    }

    /// 幅 width の欄(上の余白を除いた高さは fields で決まる)．見本は左上，ピン留めのボタンは右上
    fn area(width: f32, fields: &PalettePreviewFields) -> Area {
        let rect = Frame::new(0.0, 0.0, width, height(fields, &fonts(), &Fixed));
        let content = content_area(rect);
        Area {
            content,
            tile: Frame::new(content.x, content.y, tile_side(), tile_side()),
            pin: Frame::new(
                rect.max_x() - palette::FOOTER_HEIGHT,
                rect.y,
                palette::FOOTER_HEIGHT,
                palette::FOOTER_HEIGHT,
            ),
        }
    }

    fn texts(parts: &[Part]) -> Vec<String> {
        parts
            .iter()
            .map(|part| match part {
                Part::Text { text, .. } | Part::Tag { text, .. } => text.clone(),
                Part::Chip { lines, .. } => lines.join(""),
                Part::More { count, .. } => strings::more(*count),
            })
            .collect()
    }

    fn all() -> PalettePreviewFields {
        fields(None)
    }

    #[test]
    fn 欄の高さは出す項目の設定だけで決まる() {
        let all = all();
        let none = PalettePreviewFields {
            unicode_name: false,
            readings: false,
            shortcodes: false,
            code_points: false,
        };
        let full = height(&all, &fonts(), &Fixed);
        let bare = height(&none, &fonts(), &Fixed);
        assert!(full > bare);
        // 何も出さなくても見本の高さは空ける
        assert_eq!(
            bare,
            (tile_side() + palette::PREVIEW_PADDING_Y * 2.0).ceil()
        );
        // 札の片方だけでも札の行を空ける
        let chips = PalettePreviewFields {
            shortcodes: false,
            ..all.clone()
        };
        assert_eq!(height(&chips, &fonts(), &Fixed), full);
    }

    #[test]
    fn 名前に名前を定めたところを添え_読みと札を並べる() {
        let panel = sample::emoji();
        let shown = panel.preview.as_ref().unwrap();
        let area = area(340.0, &all());
        let parts = parts(shown, &area, &fonts(), &Fixed);
        let shown_texts = texts(&parts);
        for text in ["笑顔", "CLDR", "Unicode", "読み", ":smile:", "U+1F604"] {
            assert!(shown_texts.iter().any(|shown| shown == text), "{text}");
        }
        // 札は途中で切らない
        assert!(!shown_texts.iter().any(|text| text.contains('…')));
        // 見出しの名前・Unicode の名前・読み・札は上から順に重ならない
        let top = |wanted: &str| {
            parts
                .iter()
                .find(|part| texts(std::slice::from_ref(part))[0] == wanted)
                .map(|part| part.frame())
                .unwrap()
        };
        assert!(top("Unicode").y >= top("笑顔").max_y());
        assert!(top("読み").y > top("Unicode").max_y());
        assert!(top(":smile:").y > top("読み").max_y());
        // 見本の高さまでは見本の右に，その下は欄の左から置く
        assert!(top("笑顔").x >= area.tile.max_x());
        assert_eq!(top(":smile:").x, area.content.x);
        // どの部品も欄に収まり，ピン留めのボタンに重ならない
        for part in &parts {
            let frame = part.frame();
            assert!(frame.max_y() <= area.content.max_y(), "{part:?}");
            assert!(frame.max_x() <= area.content.max_x(), "{part:?}");
            assert!(
                frame.y >= area.pin.max_y() || frame.max_x() <= area.pin.x,
                "{part:?}"
            );
        }
    }

    #[test]
    fn 長い_unicode_の名前は札の後ろにそろえて折り返す() {
        let shown = PalettePreview {
            english_name: "CLOCKWISE RIGHTWARDS AND LEFTWARDS OPEN CIRCLE ARROWS".into(),
            ..sample::emoji().preview.unwrap()
        };
        let area = area(340.0, &all());
        let parts = parts(&shown, &area, &fonts(), &Fixed);
        let tag = parts
            .iter()
            .find(|part| matches!(part, Part::Tag { text, .. } if text == "Unicode"))
            .unwrap()
            .frame();
        // Unicode の名前の行(英大文字と空白だけの行)
        let lines: Vec<Frame> = parts
            .iter()
            .filter_map(|part| match part {
                Part::Text { text, frame, .. }
                    if text
                        .chars()
                        .all(|c| c.is_ascii_uppercase() || c == ' ' || c == '…') =>
                {
                    Some(*frame)
                }
                _ => None,
            })
            .collect();
        assert!(lines.len() >= 2);
        // 続く行も札の後ろから書く
        assert_eq!(lines[0].x, tag.max_x() + palette::PREVIEW_TAG_GAP);
        assert_eq!(lines[1].x, lines[0].x);
        assert!(texts(&parts).iter().any(|text| text == "CLOCKWISE"));
    }

    #[test]
    fn 長い見出しの名前は折り返し_札を最後の行の後ろに置く() {
        let shown = PalettePreview {
            japanese_name: "旗: サウスジョージア・サウスサンドウィッチ諸島".into(),
            english_name: "flag: South Georgia & South Sandwich Islands".into(),
            ..sample::flag().preview.unwrap()
        };
        let area = area(340.0, &all());
        let parts = parts(&shown, &area, &fonts(), &Fixed);
        let heading: Vec<(String, Frame)> = parts
            .iter()
            .filter_map(|part| match part {
                Part::Text { text, font, frame } if *font == fonts().name => {
                    Some((text.clone(), *frame))
                }
                _ => None,
            })
            .collect();
        assert_eq!(heading.len(), 2);
        assert_eq!(
            heading
                .iter()
                .map(|(text, _)| text.as_str())
                .collect::<String>(),
            "旗: サウスジョージア・サウスサンドウィッチ諸島"
        );
        let tag = parts
            .iter()
            .find(|part| matches!(part, Part::Tag { text, .. } if text == "CLDR"))
            .unwrap()
            .frame();
        assert!(tag.x > heading[1].1.max_x());
        assert!((tag.mid_y() - heading[1].1.mid_y()).abs() <= 1.0);
        // 欄に入るよう，Unicode の名前の行を減らして読みを残す
        assert!(texts(&parts).iter().any(|text| text == "読み"));
        for part in &parts {
            assert!(part.frame().max_y() <= area.content.max_y(), "{part:?}");
        }
    }

    #[test]
    fn 札が入りきらなければ読みを先に省き_札は途中で切らない() {
        // 国旗と人を ZWJ でつないだ長い並びと，長いショートコード
        let shown = PalettePreview {
            shortcodes: vec![":smiling_face_with_smiling_eyes_and_hand_covering_mouth:".into()],
            code_points:
                "U+1F469 U+1F3FD U+200D U+2764 U+FE0F U+200D U+1F48B U+200D U+1F468 U+1F3FF".into(),
            ..sample::emoji().preview.unwrap()
        };
        let area = area(340.0, &all());
        let parts = parts(&shown, &area, &fonts(), &Fixed);
        let shown_texts = texts(&parts);
        assert!(!shown_texts.iter().any(|text| text == "読み"));
        // 欄より広い札は字を縮め，それでも入らなければ札の中で折り返し，字は省かない
        let long = parts
            .iter()
            .find_map(|part| match part {
                Part::Chip {
                    lines, small: true, ..
                } if lines.len() > 1 => Some(lines.join("")),
                _ => None,
            })
            .unwrap();
        assert_eq!(
            long,
            ":smiling_face_with_smiling_eyes_and_hand_covering_mouth:"
        );
        for part in &parts {
            assert!(part.frame().max_y() <= area.content.max_y(), "{part:?}");
        }
        // 入りきらない札は「+n」にまとめる
        let chips = parts.iter().filter(|part| part.is_chip()).count();
        let more = parts.iter().find_map(|part| match part {
            Part::More { count, .. } => Some(*count),
            _ => None,
        });
        assert_eq!(chips + more.unwrap_or(0), 11);
    }
}
