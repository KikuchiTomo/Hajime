#![forbid(unsafe_code)]

//! パレットの説明の欄の配置(core の PalettePreviewLayout と同じ決め方)．左に見本の四角，右に情報の列を置く 2 段の配置にし，
//! 情報は見本の下へ回り込ませない．
//!
//! 情報の列は，上に見出しの行，その下に「項目名 → 値」の表を置く．
//! - 見出しの行: 名前を大きく出し，名前を定めたところ(CLDR)を同じベースラインに小さく添える．ピン留めのボタンは見出しの行の縦の中心に置く
//! - 表: 項目名はいちばん長い項目名の幅の列に置き，値はどの行も同じ x から書き出す．折り返した値の 2 行目以降も値の x にそろえる
//! - 項目名と値は文字のベースラインで合わせる．ショートコードとコードポイントの札も，中の文字のベースラインを項目名に合わせる
//! - 行の高さはトークンで決める(見出しの行は preview-heading-height，表の行は text-row-height)．文字は行の縦の真ん中に置く．
//!   行の間は間隔の段階の item-gap 1 つ，見本と情報の列・項目名と値・名前と出どころのあいだは group-gap
//!
//! 欄の高さ(`height`)は，その種類で設定により出る行がすべて出たときの高さ(Unicode の名前は preview-name-lines 行)にし，
//! 選んでいる文字では変えない．行の高さはトークンなので書体を測らずに求まり，core の PaletteSession と同じ値になる．
//! Unicode の名前がその行数に入らなければ末尾を「…」で省く(読み上げでは全体を伝える)．中身が欄に入りきらなければ
//! (長いショートコードや多くのコードポイントの札が何行にもなるとき)，読みを省き，Unicode の名前を 1 行にし，Unicode の名前を省く順に詰め，
//! それでも入らない札は「+n」にまとめる

use super::layout::Fonts;
use crate::geometry::Frame;
use crate::scene::fitting;
use crate::scene::Measure;
use crate::strings;
use crate::theme::Font;
use ipc::{PaletteKind, PalettePreview, PalettePreviewFields};
use tokens::size::palette;

/// 文字の役割．描く側が役割ごとに書体と色を決める
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    /// 見出しの名前
    Heading,
    /// 見出しに添える，名前を定めたところ
    Source,
    /// 表の項目名
    Label,
    /// 表の値(Unicode の名前と読み)
    Value,
    /// 入らなかった読みや札の数(「+n」)
    More,
    /// ショートコードとコードポイントの札の文字
    Code,
    /// 行に入らない札を縮めた文字
    SmallCode,
}

impl Role {
    pub fn font(self, fonts: &Fonts) -> Font {
        match self {
            Self::Heading => fonts.name,
            Self::Source | Self::Label => fonts.label,
            Self::Value | Self::More => fonts.detail,
            Self::Code => fonts.code,
            Self::SmallCode => fonts.code_small,
        }
    }
}

/// 描く部品
#[derive(Debug, Clone, PartialEq)]
pub enum Part {
    /// 1 行の文字．x から書き，baseline に文字のベースラインを置く
    Text {
        text: String,
        role: Role,
        x: f32,
        baseline: f32,
        width: f32,
    },
    /// 等幅の文字の札．lines は札の中の行(行より広い札だけ 2 行以上)で，baselines はその行のベースライン
    Chip {
        lines: Vec<String>,
        role: Role,
        frame: Frame,
        text_x: f32,
        baselines: Vec<f32>,
    },
}

/// 置いた部品
#[derive(Debug, Clone, PartialEq)]
pub struct Placed {
    pub parts: Vec<Part>,
    /// 見出しの行の縦の中心
    pub heading_mid_y: f32,
    /// 値を書き出す x
    pub value_x: f32,
    /// 最後の行の下の端．入りきるかは行の高さで決める(字の下の高さは書体の行送りの余りを含むことがあるので使わない)
    pub rows_bottom: f32,
}

/// 説明の欄(content)と見本の四角と，見出しの行の右に空けておくピン留めのボタンの幅
#[derive(Debug, Clone, Copy)]
pub struct Area {
    pub content: Frame,
    pub tile: Frame,
    pub pin_width: f32,
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

/// その種類で出しうる項目．顔文字は読みだけ，記号にはショートコードが無い(core の PalettePreviewLayout.shownFields)
pub fn shown_fields(fields: &PalettePreviewFields, kind: PaletteKind) -> PalettePreviewFields {
    match kind {
        PaletteKind::Emoji => fields.clone(),
        PaletteKind::Symbol => PalettePreviewFields {
            shortcodes: false,
            ..fields.clone()
        },
        PaletteKind::Kaomoji => PalettePreviewFields {
            unicode_name: false,
            readings: fields.readings,
            shortcodes: false,
            code_points: false,
        },
    }
}

/// 欄の高さ．見本の高さと，その種類で設定により出る行がすべて出たときの高さの大きいほう．
/// 行の高さはトークンで決まるので書体を測らずに求まる(core の PalettePreviewLayout.height と同じ値)
pub fn height(fields: &PalettePreviewFields, kind: PaletteKind) -> f32 {
    let fields = shown_fields(fields, kind);
    let row = palette::ITEM_GAP + palette::TEXT_ROW_HEIGHT;
    let mut height = palette::PREVIEW_HEADING_HEIGHT;
    if fields.unicode_name {
        height += palette::ITEM_GAP + palette::TEXT_ROW_HEIGHT * palette::PREVIEW_NAME_LINES;
    }
    for shown in [fields.readings, fields.shortcodes, fields.code_points] {
        if shown {
            height += row;
        }
    }
    height.max(palette::TILE_SIZE)
}

/// 欄の上の端(top)から見たときの，見出しの行の縦の中心
pub fn heading_mid_y(top: f32) -> f32 {
    top + palette::PREVIEW_HEADING_HEIGHT / 2.0
}

/// 部品の枠(文字は書体の上と下の高さの枠)．重なりと欄からのはみ出しを確かめるのに使う
pub fn frame_of(part: &Part, fonts: &Fonts, measure: &dyn Measure) -> Frame {
    match part {
        Part::Text {
            role,
            x,
            baseline,
            width,
            ..
        } => {
            let metrics = Metrics { fonts, measure };
            let (ascent, descent) = metrics.font_extent(*role);
            Frame::new(*x, baseline - ascent, *width, ascent + descent)
        }
        Part::Chip { frame, .. } => *frame,
    }
}

/// 名前・項目名・値・札を置く．kind は今の種類(項目名の列の幅は，その種類で出しうる項目名で決める)
pub fn place(
    shown: &PalettePreview,
    fields: &PalettePreviewFields,
    kind: PaletteKind,
    area: &Area,
    fonts: &Fonts,
    measure: &dyn Measure,
) -> Placed {
    let fields = shown_fields(fields, kind);
    let metrics = Metrics { fonts, measure };
    let planner = Planner {
        shown,
        fields: &fields,
        area,
        rows: Rows::new(&metrics),
        metrics,
    };
    let mut options = Options::default();
    let mut placed = planner.plan(&options);
    // 入りきらなければ，読みを省き，Unicode の名前を 1 行にし，Unicode の名前を省く(求められた Unicode の名前をなるべく残す)
    let steps: [fn(&mut Options); 3] = [
        |options| options.readings = false,
        |options| options.unicode_lines = 1,
        |options| options.unicode_name = false,
    ];
    for step in steps {
        if placed.rows_bottom <= area.content.max_y() {
            break;
        }
        step(&mut options);
        placed = planner.plan(&options);
    }
    planner.limiting_chips(placed)
}

/// 詰め方．入りきらないときに変える
struct Options {
    unicode_lines: usize,
    readings: bool,
    unicode_name: bool,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            unicode_lines: palette::PREVIEW_NAME_LINES as usize,
            readings: true,
            unicode_name: true,
        }
    }
}

/// 書体ごとの幅と高さ
struct Metrics<'a> {
    fonts: &'a Fonts,
    measure: &'a dyn Measure,
}

/// 書体の高さを測る字(英字と，書体の代わりに使う日本語の字の両方)
const LINE_SAMPLE: &str = "Aあ";
/// 札の書体の高さを測る字(札には英数字だけを書く)
const CODE_SAMPLE: &str = "U+1F";

impl Metrics<'_> {
    fn width(&self, text: &str, role: Role) -> f32 {
        if text.is_empty() {
            0.0
        } else {
            self.measure.width(text, role.font(self.fonts)).ceil()
        }
    }

    /// 書体のベースラインから上と下の高さ(DirectWrite の行の高さとベースライン)
    fn font_extent(&self, role: Role) -> (f32, f32) {
        let sample = match role {
            Role::Code | Role::SmallCode => CODE_SAMPLE,
            _ => LINE_SAMPLE,
        };
        let (height, baseline) = self.measure.line(sample, role.font(self.fonts));
        (baseline, (height - baseline).max(0.0))
    }

    fn measuring(&self, role: Role) -> impl Fn(&str) -> f32 + '_ {
        move |text: &str| self.width(text, role)
    }
}

/// 行の高さ(pitch)と，行の上の端から 1 行目のベースラインまで(ascent)．文字は行の縦の真ん中に置き，ベースラインは整数の位置にする
#[derive(Debug, Clone, Copy)]
struct RowMetrics {
    ascent: f32,
    pitch: f32,
}

impl RowMetrics {
    /// 字が行より高ければ，下の端を行に収める(はみ出す分は上の行の間に出す)
    fn new(pitch: f32, ascent: f32, descent: f32) -> Self {
        Self {
            ascent: ((pitch - ascent - descent) / 2.0 + ascent)
                .round()
                .min((pitch - descent).floor()),
            pitch,
        }
    }

    fn height(&self, lines: usize) -> f32 {
        self.pitch * lines.max(1) as f32
    }
}

/// 見出しの行と表の行．表の行は，文字の値の行も札の行も同じ高さにし，縦の間隔をそろえる
struct Rows {
    heading: RowMetrics,
    table: RowMetrics,
}

impl Rows {
    fn new(metrics: &Metrics) -> Self {
        let max = |roles: &[Role], padding: f32| {
            roles
                .iter()
                .fold((0.0f32, 0.0f32), |(ascent, descent), role| {
                    let (a, d) = metrics.font_extent(*role);
                    let extra = if matches!(role, Role::Code) {
                        padding
                    } else {
                        0.0
                    };
                    (ascent.max(a + extra), descent.max(d + extra))
                })
        };
        let (heading_ascent, heading_descent) = max(&[Role::Heading, Role::Source], 0.0);
        // 札は中の文字の上下に余白を足しても，行の高さに収める
        let (table_ascent, table_descent) = max(
            &[Role::Label, Role::Value, Role::More, Role::Code],
            palette::CHIP_PADDING_Y,
        );
        Self {
            heading: RowMetrics::new(
                palette::PREVIEW_HEADING_HEIGHT,
                heading_ascent,
                heading_descent,
            ),
            table: RowMetrics::new(palette::TEXT_ROW_HEIGHT, table_ascent, table_descent),
        }
    }
}

/// 1 つの文字の配置を，詰め方ごとに作る
struct Planner<'a> {
    shown: &'a PalettePreview,
    fields: &'a PalettePreviewFields,
    area: &'a Area,
    rows: Rows,
    metrics: Metrics<'a>,
}

impl Planner<'_> {
    /// 情報の列の左の端
    fn left(&self) -> f32 {
        self.area.tile.max_x() + palette::GROUP_GAP
    }

    /// 項目名の列の幅．その種類で出しうる項目名のうちいちばん長いもの(選んでいる文字によらず値の x を変えない)
    fn label_width(&self) -> f32 {
        let mut labels = Vec::new();
        if self.fields.unicode_name {
            labels.extend([strings::PALETTE_UNICODE_NAME, strings::PALETTE_ENGLISH_NAME]);
        }
        if self.fields.readings {
            labels.push(strings::PALETTE_READINGS);
        }
        if self.fields.shortcodes {
            labels.push(strings::PALETTE_SHORTCODES);
        }
        if self.fields.code_points {
            labels.push(strings::PALETTE_CODE_POINTS);
        }
        labels
            .into_iter()
            .map(|label| self.metrics.width(label, Role::Label))
            .fold(0.0, f32::max)
    }

    fn value_x(&self) -> f32 {
        let width = self.label_width();
        if width > 0.0 {
            self.left() + width + palette::GROUP_GAP
        } else {
            self.left()
        }
    }

    fn text(&self, text: String, role: Role, x: f32, baseline: f32) -> Part {
        let width = self.metrics.width(&text, role);
        Part::Text {
            text,
            role,
            x,
            baseline,
            width,
        }
    }

    fn plan(&self, options: &Options) -> Placed {
        let rows = &self.rows;
        let content = self.area.content;
        let gap = palette::ITEM_GAP;
        let left = self.left();
        let mut parts = Vec::new();
        // 見出しの行．名前と名前を定めたところを同じベースラインに置く
        let heading_baseline = content.y + rows.heading.ascent;
        let source = self
            .shown
            .name_source
            .as_deref()
            .map(|source| (source, self.metrics.width(source, Role::Source)));
        let space = content.max_x()
            - self.area.pin_width
            - left
            - source.map_or(0.0, |(_, width)| palette::GROUP_GAP + width);
        let name = fitting::truncated(
            &self.shown.japanese_name,
            space,
            &self.metrics.measuring(Role::Heading),
        );
        let name_width = self.metrics.width(&name, Role::Heading);
        parts.push(self.text(name, Role::Heading, left, heading_baseline));
        if let Some((text, _)) = source {
            parts.push(self.text(
                text.to_string(),
                Role::Source,
                left + name_width + palette::GROUP_GAP,
                heading_baseline,
            ));
        }
        let mut y = content.y + rows.heading.height(1);
        let value_x = self.value_x();
        let value_width = content.max_x() - value_x;
        let pitch = rows.table.pitch;
        // Unicode の名前(並びは英語の名前)．値の x にそろえて折り返す
        if options.unicode_name && self.fields.unicode_name && !self.shown.english_name.is_empty() {
            y += gap;
            let label = if self.shown.english_name_source.as_deref()
                == Some(strings::PALETTE_UNICODE_SOURCE)
            {
                strings::PALETTE_UNICODE_NAME
            } else {
                strings::PALETTE_ENGLISH_NAME
            };
            let lines = fitting::wrapped(
                &self.shown.english_name,
                value_width,
                options.unicode_lines,
                &self.metrics.measuring(Role::Value),
            );
            for (index, line) in lines.iter().enumerate() {
                let baseline = y + rows.table.ascent + pitch * index as f32;
                if index == 0 {
                    parts.push(self.text(label.to_string(), Role::Label, left, baseline));
                }
                parts.push(self.text(line.clone(), Role::Value, value_x, baseline));
            }
            y += rows.table.height(lines.len());
        }
        // 読み．入る数だけ「、」でつなぎ，残りの数を添える
        if options.readings && self.fields.readings && !self.shown.readings.is_empty() {
            y += gap;
            let baseline = y + rows.table.ascent;
            parts.push(self.text(
                strings::PALETTE_READINGS.to_string(),
                Role::Label,
                left,
                baseline,
            ));
            let (text, rest) = self.fitting_readings(value_width);
            let width = self.metrics.width(&text, Role::Value);
            parts.push(self.text(text, Role::Value, value_x, baseline));
            if rest > 0 {
                parts.push(self.text(
                    strings::more(rest),
                    Role::More,
                    value_x + width + palette::ITEM_GAP,
                    baseline,
                ));
            }
            y += rows.table.height(1);
        }
        // ショートコードとコードポイントの札
        let code_points: Vec<String> = self
            .shown
            .code_points
            .split_whitespace()
            .map(String::from)
            .collect();
        for (label, values, shown) in [
            (
                strings::PALETTE_SHORTCODES,
                &self.shown.shortcodes,
                self.fields.shortcodes,
            ),
            (
                strings::PALETTE_CODE_POINTS,
                &code_points,
                self.fields.code_points,
            ),
        ] {
            if !shown || values.is_empty() {
                continue;
            }
            y += gap;
            parts.push(self.text(label.to_string(), Role::Label, left, y + rows.table.ascent));
            let (chips, lines) = self.flow_chips(values, y, value_x, value_width);
            parts.extend(chips);
            y += rows.table.height(lines);
        }
        Placed {
            parts,
            heading_mid_y: heading_mid_y(content.y),
            value_x,
            rows_bottom: y,
        }
    }

    /// 札を値の幅で流し込む．入らない札は次の行へ送り，値の幅より広い札は字を縮め，それでも入らなければ札の中で折り返す(札の高さは行の数だけ)
    fn flow_chips(&self, values: &[String], top: f32, left: f32, width: f32) -> (Vec<Part>, usize) {
        let padding_x = palette::CHIP_PADDING_X;
        let pitch = self.rows.table.pitch;
        let mut chips = Vec::new();
        let mut line = 0;
        let mut x = left;
        for value in values {
            let mut role = Role::Code;
            let mut chip_width = self.metrics.width(value, Role::Code) + padding_x * 2.0;
            let mut lines = vec![value.clone()];
            if chip_width > width {
                role = Role::SmallCode;
                chip_width = self.metrics.width(value, Role::SmallCode) + padding_x * 2.0;
                if chip_width > width {
                    lines = fitting::wrapped(
                        value,
                        width - padding_x * 2.0,
                        usize::MAX,
                        &self.metrics.measuring(Role::SmallCode),
                    );
                    chip_width = lines
                        .iter()
                        .map(|line| self.metrics.width(line, Role::SmallCode))
                        .fold(0.0, f32::max)
                        + padding_x * 2.0;
                }
            }
            // 行の途中で入らない札と，2 行以上の札は，次の行の頭から置く
            if x > left && (x + chip_width > left + width || lines.len() > 1) {
                line += 1;
                x = left;
            }
            let baselines: Vec<f32> = (0..lines.len())
                .map(|index| top + self.rows.table.ascent + pitch * (line + index) as f32)
                .collect();
            // 札は文字の上下に chip-padding-y を足した高さで，行の中の縦の真ん中に置く(行の高さに収め，縁はドットにそろえる)
            let (ascent, descent) = self.metrics.font_extent(role);
            let height = (ascent + descent + palette::CHIP_PADDING_Y * 2.0)
                .round()
                .min(pitch);
            let row_top = top + pitch * line as f32;
            let frame = Frame::new(
                x,
                row_top + ((pitch - height) / 2.0).floor(),
                chip_width.ceil(),
                height + pitch * (lines.len() - 1) as f32,
            );
            let count = lines.len();
            chips.push(Part::Chip {
                lines,
                role,
                frame,
                text_x: x + padding_x,
                baselines,
            });
            if count > 1 {
                line += count;
                x = left;
            } else {
                x += chip_width + palette::ITEM_GAP;
            }
        }
        let lines = if x > left { line + 1 } else { line };
        (chips, lines)
    }

    /// 欄の下の端を越える札を除き，除いた数を最後に残した札の後ろに「+n」で示す．「+n」が入らなければその札も除く
    fn limiting_chips(&self, mut placed: Placed) -> Placed {
        let limit = self.area.content.max_y();
        if placed.rows_bottom <= limit {
            return placed;
        }
        let is_chip = |part: &Part| matches!(part, Part::Chip { .. });
        let total = placed.parts.iter().filter(|part| is_chip(part)).count();
        placed
            .parts
            .retain(|part| !matches!(part, Part::Chip { frame, .. } if frame.max_y() > limit));
        while let Some(index) = placed.parts.iter().rposition(is_chip) {
            let kept = placed.parts.iter().filter(|part| is_chip(part)).count();
            let Part::Chip {
                frame, baselines, ..
            } = &placed.parts[index]
            else {
                break;
            };
            let more = strings::more(total - kept);
            let x = frame.max_x() + palette::ITEM_GAP;
            let baseline = baselines[0];
            if x + self.metrics.width(&more, Role::More) <= self.area.content.max_x() {
                placed.parts.push(self.text(more, Role::More, x, baseline));
                return placed;
            }
            placed.parts.remove(index);
        }
        placed
    }

    /// 幅に入る数の読み(「、」でつなぐ)と，入らなかった読みの数．1 つ目も入らなければ末尾を省く
    fn fitting_readings(&self, width: f32) -> (String, usize) {
        let readings = &self.shown.readings;
        let more = |rest: usize| {
            if rest > 0 {
                palette::ITEM_GAP + self.metrics.width(&strings::more(rest), Role::More)
            } else {
                0.0
            }
        };
        for count in (1..=readings.len()).rev() {
            let text = readings[..count].join(strings::PALETTE_READING_SEPARATOR);
            let rest = readings.len() - count;
            if self.metrics.width(&text, Role::Value) + more(rest) <= width {
                return (text, rest);
            }
        }
        let rest = readings.len().saturating_sub(1);
        let first = readings.first().map(String::as_str).unwrap_or_default();
        (
            fitting::truncated(
                first,
                width - more(rest),
                &self.metrics.measuring(Role::Value),
            ),
            rest,
        )
    }
}

#[cfg(test)]
mod tests {
    use super::super::sample;
    use super::*;
    use crate::scene::testing::Uneven;
    use ipc::PaletteKind;

    fn fonts() -> Fonts {
        Fonts::new(36.0)
    }

    struct Setup {
        placed: Placed,
        area: Area,
        height: f32,
    }

    fn setup(
        shown: &PalettePreview,
        fields: &PalettePreviewFields,
        kind: PaletteKind,
        tile_width: f32,
    ) -> Setup {
        let measure = Uneven;
        let height = height(fields, kind);
        let content = Frame::new(8.0, 4.0, 333.0, height);
        let area = Area {
            content,
            tile: Frame::new(content.x, content.y, tile_width, palette::TILE_SIZE),
            pin_width: palette::CONTROL_HEIGHT,
        };
        Setup {
            placed: place(shown, fields, kind, &area, &fonts(), &measure),
            area,
            height,
        }
    }

    fn texts(placed: &Placed, role: Role) -> Vec<(String, f32, f32)> {
        placed
            .parts
            .iter()
            .filter_map(|part| match part {
                Part::Text {
                    text,
                    role: found,
                    x,
                    baseline,
                    ..
                } if *found == role => Some((text.clone(), *x, *baseline)),
                _ => None,
            })
            .collect()
    }

    fn chips(placed: &Placed) -> Vec<(Vec<String>, Frame, Vec<f32>)> {
        placed
            .parts
            .iter()
            .filter_map(|part| match part {
                Part::Chip {
                    lines,
                    frame,
                    baselines,
                    ..
                } => Some((lines.clone(), *frame, baselines.clone())),
                _ => None,
            })
            .collect()
    }

    /// 値の x・項目名と値のベースライン・見出しのベースライン・重なり・欄からのはみ出しを確かめる
    fn assert_aligned(setup: &Setup) {
        let placed = &setup.placed;
        let left = setup.area.tile.max_x() + palette::GROUP_GAP;
        // 値は，どの行も同じ x から書き出す(行の頭の札も)
        for (text, x, _) in texts(placed, Role::Value) {
            assert_eq!(x, placed.value_x, "{text}");
        }
        let chips = chips(placed);
        for (lines, frame, baselines) in &chips {
            let starts_line = !chips
                .iter()
                .any(|(_, other, others)| other.max_x() <= frame.x && others[0] == baselines[0]);
            if starts_line {
                assert_eq!(frame.x, placed.value_x, "{lines:?}");
            }
        }
        // 項目名は情報の列の左の端にそろい，ベースラインが値の 1 行目と同じ
        let values: Vec<f32> = texts(placed, Role::Value)
            .into_iter()
            .map(|(_, _, baseline)| baseline)
            .chain(chips.iter().map(|(_, _, baselines)| baselines[0]))
            .collect();
        for (label, x, baseline) in texts(placed, Role::Label) {
            assert_eq!(x, left, "{label}");
            let value = values
                .iter()
                .copied()
                .filter(|value| *value >= baseline - 0.5)
                .fold(f32::MAX, f32::min);
            assert!((value - baseline).abs() <= 0.5, "{label}");
        }
        // 見出しと添える文字のベースラインが同じ
        let heading: Vec<f32> = texts(placed, Role::Heading)
            .into_iter()
            .chain(texts(placed, Role::Source))
            .map(|(_, _, baseline)| baseline)
            .collect();
        assert!(heading.windows(2).all(|pair| pair[0] == pair[1]));
        // ピン留めのボタンを合わせる見出しの行の中心は，欄の上の端から見出しの行の高さの半分
        assert_eq!(
            placed.heading_mid_y,
            setup.area.content.y + palette::PREVIEW_HEADING_HEIGHT / 2.0
        );
        // 部品どうし(見本を含む)が重ならず，欄の中に収まる
        let frames: Vec<Frame> = placed
            .parts
            .iter()
            .map(|part| frame_of(part, &fonts(), &Uneven))
            .chain([setup.area.tile])
            .collect();
        for (index, frame) in frames.iter().enumerate() {
            for other in &frames[index + 1..] {
                let overlaps = frame.x < other.max_x()
                    && other.x < frame.max_x()
                    && frame.y < other.max_y()
                    && other.y < frame.max_y();
                assert!(!overlaps, "{frame:?} {other:?}");
            }
        }
        let content = setup.area.content;
        for frame in &frames[..frames.len() - 1] {
            assert!(frame.x >= content.x && frame.max_x() <= content.max_x() + 0.01);
            assert!(frame.y >= content.y - 0.01 && frame.max_y() <= content.max_y() + 0.01);
        }
    }

    #[test]
    fn 情報は見本の右の列に置き_値の_x_と項目名と値のベースラインをそろえる() {
        let panel = sample::emoji();
        let setup = setup(
            panel.preview.as_ref().unwrap(),
            &fields(None),
            PaletteKind::Emoji,
            palette::TILE_SIZE,
        );
        assert_aligned(&setup);
        let labels: Vec<String> = texts(&setup.placed, Role::Label)
            .into_iter()
            .map(|(text, _, _)| text)
            .collect();
        assert_eq!(
            labels,
            ["Unicode", "読み", "ショートコード", "コードポイント"]
        );
        let chips: Vec<Vec<String>> = chips(&setup.placed)
            .into_iter()
            .map(|(lines, _, _)| lines)
            .collect();
        assert_eq!(chips, [vec![":smile:"], vec!["U+1F604"]]);
        assert_eq!(texts(&setup.placed, Role::Source)[0].0, "CLDR");
    }

    #[test]
    fn 欄の高さは設定で出る行の分だけで_典型の絵文字では最後の行の下に行の間より大きな空きを残さない(
    ) {
        let panel = sample::emoji();
        let shown = panel.preview.as_ref().unwrap();
        let setup = setup(shown, &fields(None), PaletteKind::Emoji, palette::TILE_SIZE);
        let bottom = setup
            .placed
            .parts
            .iter()
            .map(|part| frame_of(part, &fonts(), &Uneven).max_y())
            .fold(0.0, f32::max);
        let space = setup.area.content.max_y() - bottom;
        assert!((0.0..=palette::ITEM_GAP).contains(&space), "{space}");
        // 項目を減らせば欄は低くなり，値の x は出す項目名だけで決める
        let fewer = PalettePreviewFields {
            unicode_name: true,
            readings: false,
            shortcodes: false,
            code_points: false,
        };
        let reduced = self::setup(shown, &fewer, PaletteKind::Emoji, palette::TILE_SIZE);
        assert!(reduced.height < setup.height);
        assert!(reduced.placed.value_x < setup.placed.value_x);
        assert_aligned(&reduced);
    }

    #[test]
    fn 並びの英語の名前は英語の行に出し_cldr_は見出しの_1_か所だけ() {
        let panel = sample::flag();
        let setup = setup(
            panel.preview.as_ref().unwrap(),
            &fields(None),
            PaletteKind::Emoji,
            palette::TILE_SIZE,
        );
        assert_aligned(&setup);
        let all: Vec<String> = setup
            .placed
            .parts
            .iter()
            .filter_map(|part| match part {
                Part::Text { text, .. } => Some(text.clone()),
                _ => None,
            })
            .collect();
        assert_eq!(all.iter().filter(|text| *text == "CLDR").count(), 1);
        assert_eq!(texts(&setup.placed, Role::Label)[0].0, "英語");
    }

    #[test]
    fn 長い_unicode_の名前は_2_行目の末尾を省き_長いショートコードは縮めて札の中で折り返す() {
        let panel = sample::long_name();
        let setup = setup(
            panel.preview.as_ref().unwrap(),
            &fields(None),
            PaletteKind::Emoji,
            palette::TILE_SIZE,
        );
        assert_aligned(&setup);
        let chips = chips(&setup.placed);
        let long = chips.iter().find(|(lines, _, _)| lines.len() > 1).unwrap();
        assert_eq!(
            long.0.concat(),
            ":black_right_pointing_double_triangle_with_vertical_bar:"
        );
        // 札の中の行も表の行と同じ間隔
        let pitches: Vec<f32> = long.2.windows(2).map(|pair| pair[1] - pair[0]).collect();
        assert!(pitches.windows(2).all(|pair| pair[0] == pair[1]));
        // 欄が足りないので，Unicode の名前(2 行)より先に読みを省く
        let labels: Vec<String> = texts(&setup.placed, Role::Label)
            .into_iter()
            .map(|(text, _, _)| text)
            .collect();
        assert_eq!(labels, ["Unicode", "ショートコード", "コードポイント"]);
        assert_eq!(texts(&setup.placed, Role::Value).len(), 2);
    }

    #[test]
    fn 顔文字は広い見本の右に名前と読みだけを出す() {
        let panel = sample::kaomoji();
        let setup = setup(
            panel.preview.as_ref().unwrap(),
            &fields(None),
            PaletteKind::Kaomoji,
            140.0,
        );
        assert_aligned(&setup);
        let labels: Vec<String> = texts(&setup.placed, Role::Label)
            .into_iter()
            .map(|(text, _, _)| text)
            .collect();
        assert_eq!(labels, ["読み"]);
        assert!(chips(&setup.placed).is_empty());
    }

    #[test]
    fn 札が入りきらなければ詰め_入らない札は数にまとめる() {
        let shown = PalettePreview {
            code_points:
                "U+1F469 U+1F3FD U+200D U+2764 U+FE0F U+200D U+1F48B U+200D U+1F468 U+1F3FF".into(),
            ..sample::emoji().preview.unwrap()
        };
        let setup = setup(
            &shown,
            &fields(None),
            PaletteKind::Emoji,
            palette::TILE_SIZE,
        );
        assert_aligned(&setup);
        let shown_points = chips(&setup.placed)
            .iter()
            .filter(|(lines, _, _)| lines[0].starts_with("U+"))
            .count();
        let more = texts(&setup.placed, Role::More)
            .first()
            .and_then(|(text, _, _)| text.trim_start_matches('+').parse::<usize>().ok())
            .unwrap_or(0);
        assert_eq!(shown_points + more, 10);
    }

    #[test]
    fn 欄の高さは種類ごとに出る行の分だけで_core_と同じ() {
        let all = fields(None);
        let emoji = height(&all, PaletteKind::Emoji);
        let symbol = height(&all, PaletteKind::Symbol);
        let kaomoji = height(&all, PaletteKind::Kaomoji);
        // 見出し 20，Unicode の名前 2 行，読み・ショートコード・コードポイント(行の間 4，行 16)
        assert_eq!(emoji, 20.0 + 4.0 + 32.0 + 20.0 * 3.0);
        assert_eq!(symbol, emoji - 20.0);
        // 顔文字は見出しと読みだけなので，見本の高さ
        assert_eq!(kaomoji, palette::TILE_SIZE);
    }

    #[test]
    fn 文字は行の縦の真ん中に置く() {
        let panel = sample::emoji();
        let setup = setup(
            panel.preview.as_ref().unwrap(),
            &fields(None),
            PaletteKind::Emoji,
            palette::TILE_SIZE,
        );
        let top = setup.area.content.y;
        let heading = texts(&setup.placed, Role::Heading)[0].2;
        let metrics = Metrics {
            fonts: &fonts(),
            measure: &Uneven,
        };
        let (ascent, descent) = metrics.font_extent(Role::Heading);
        let above = heading - ascent - top;
        let below = top + palette::PREVIEW_HEADING_HEIGHT - (heading + descent);
        assert!((above - below).abs() <= 1.0, "{above} {below}");
        // 札は行の高さに収まる
        for (lines, frame, _) in chips(&setup.placed) {
            assert!(frame.height <= palette::TEXT_ROW_HEIGHT, "{lines:?}");
        }
    }
}
