#![forbid(unsafe_code)]

//! パレットの中身を，描く順の部品(Draw)の並びにする(macOS の PaletteView.draw)．
//! 位置は layout と同じものを使い，押した位置を調べる側とずれないようにする

use super::emoji::{is_emoji, skin_tone_sample};
use super::layout::{skin_tone_button_inset, Layout};
use super::motion::{bounce, overshoot, Tween};
use super::preview::{self, Part};
use crate::geometry::Frame;
use crate::scene::paint::Painter;
use crate::scene::{Draw, Look, Measure, Scene};
use crate::theme::{Color, Font, ResolvedTheme};
use ipc::{PaletteContentMotion, PalettePanel, PalettePreview, PaletteSkinTonePicker};
use tokens::opacity;
use tokens::size::{candidate, glass, palette};

/// アイコンの書体(Segoe Fluent Icons と Segoe MDL2 Assets)の字．macOS の SF Symbols に当たる
mod glyph {
    pub const SEARCH: char = '\u{E721}';
    pub const PIN: char = '\u{E718}';
    pub const PIN_FILL: char = '\u{E841}';
    pub const RECENT: char = '\u{E823}';
    pub const EMOJI: char = '\u{E899}';
    pub const CONTACT: char = '\u{E77B}';
    pub const LEAF: char = '\u{E8BE}';
    pub const CAFE: char = '\u{EC32}';
    pub const CAR: char = '\u{E804}';
    pub const GAME: char = '\u{E7FC}';
    pub const LIGHTBULB: char = '\u{EA80}';
    pub const HEART: char = '\u{EB51}';
    pub const FLAG: char = '\u{E7C1}';
}

/// アイコンの書体が無いときに代わりに描く文字(core の PaletteStrings.resultsSymbol・pinnedSymbol)
const SEARCH_FALLBACK: &str = "🔍";
const PIN_FALLBACK: &str = "📌";

/// まとまりのタブのアイコン．絵文字のまとまりとピン留め・よく使う文字・探した結果はアイコンで描き，
/// 記号と顔文字のまとまりは代表の文字で描く(macOS の PaletteIcons.symbolName)．名前は core の PaletteSection.Kind.wireName
fn tab_glyph(section: &str) -> Option<char> {
    Some(match section {
        "pinned" => glyph::PIN,
        "frequent" => glyph::RECENT,
        "results" => glyph::SEARCH,
        "smileys" => glyph::EMOJI,
        "people" => glyph::CONTACT,
        "nature" => glyph::LEAF,
        "food" => glyph::CAFE,
        "travel" => glyph::CAR,
        "activities" => glyph::GAME,
        "objects" => glyph::LIGHTBULB,
        "symbols" => glyph::HEART,
        "flags" => glyph::FLAG,
        _ => return None,
    })
}

/// パレットの窓の中身．窓の大きさは layout と同じ．tween は動きの途中の形(止まっていれば Tween::default())
pub fn palette<'a>(
    panel: &'a PalettePanel,
    layout: &'a Layout,
    look: &'a Look,
    measure: &'a dyn Measure,
    tween: Tween<'a>,
) -> Scene {
    let mut drawing = Drawing {
        painter: Painter::new(look, measure),
        theme: look.theme,
        measure,
        layout,
        panel,
        tween,
    };
    drawing.paint();
    drawing.painter.finish(layout.width, layout.height)
}

struct Drawing<'a> {
    painter: Painter<'a>,
    theme: &'a ResolvedTheme,
    measure: &'a dyn Measure,
    layout: &'a Layout,
    panel: &'a PalettePanel,
    tween: Tween<'a>,
}

impl Drawing<'_> {
    fn paint(&mut self) {
        let layout = self.layout;
        self.painter.panel(layout.body);
        self.search();
        self.modes();
        self.tabs();
        self.heading();
        self.grid();
        if let Some(preview) = layout.preview {
            self.painter.separator(
                (preview.y - palette::GAP / 2.0).round(),
                layout.grid.x,
                layout.footer.max_x(),
            );
            if let Some(shown) = &self.panel.preview {
                self.preview(shown, preview);
            }
        }
        self.painter.separator(
            layout.footer.y.round(),
            layout.footer.x,
            layout.footer.max_x(),
        );
        self.footer();
        if let Some(picker) = &self.panel.skin_tone_picker {
            self.picker(picker);
        }
    }

    // MARK: - 形

    /// paint で描いた部品を，clip の中だけに opacity の濃さで描くまとまりにする．scale が 1 でなければ clip の真ん中を中心に大きさを変える
    fn grouped(&mut self, clip: Frame, opacity: f32, scale: f32, paint: impl FnOnce(&mut Self)) {
        let outer = std::mem::take(&mut self.painter.draws);
        paint(self);
        let draws = std::mem::replace(&mut self.painter.draws, outer);
        self.painter.draws.push(Draw::Group {
            clip,
            opacity,
            scale,
            draws,
        });
    }

    /// 角丸のテーマは角丸で，platinum と desk は角の立った形で塗る
    fn fill(&mut self, frame: Frame, color: Color, radius: f32) {
        if self.theme.is_rounded() {
            self.painter.draws.push(Draw::RoundRect {
                frame,
                radius,
                fill: Some(color),
                stroke: None,
            });
        } else {
            self.painter.rect(frame, color);
        }
    }

    /// frame の内側を width の線で縁取る．角の立った形は 4 本の長方形にし，デバイスのピクセルにそろえる
    fn outline(&mut self, frame: Frame, color: Color, radius: f32, width: f32) {
        if self.theme.is_rounded() {
            let half = width / 2.0;
            self.painter.draws.push(Draw::RoundRect {
                frame: frame.inset(half, half),
                radius,
                fill: None,
                stroke: Some((color, width)),
            });
            return;
        }
        let side = frame.height - width * 2.0;
        for edge in [
            Frame::new(frame.x, frame.y, frame.width, width),
            Frame::new(frame.x, frame.max_y() - width, frame.width, width),
            Frame::new(frame.x, frame.y + width, width, side),
            Frame::new(frame.max_x() - width, frame.y + width, width, side),
        ] {
            self.painter.rect(edge, color);
        }
    }

    /// 選んでいるマス．色だけに頼らないよう，地を塗ったうえで枠も描く
    fn selection(&mut self, frame: Frame) {
        let inner = frame.inset(candidate::FRAME_WIDTH, candidate::FRAME_WIDTH);
        self.fill(inner, self.theme.focus_tint, palette::CELL_RADIUS);
        self.outline(
            inner,
            self.theme.selection,
            palette::CELL_RADIUS,
            palette::SELECTION_STROKE,
        );
    }

    /// アイコンの字を frame の中央に描く．書体に字が無ければ fallback を代わりの書体で描く
    fn glyph(
        &mut self,
        glyph: char,
        font: Font,
        fallback: (&str, Font),
        color: Color,
        frame: Frame,
    ) {
        if self.measure.has_glyph(font, glyph) {
            self.painter
                .centered(&glyph.to_string(), font, color, frame);
        } else {
            self.painter.centered(fallback.0, fallback.1, color, frame);
        }
    }

    // MARK: - 部品

    /// 探す欄．虫めがね・探す語(空なら案内を薄く)・打った文字が入る位置の縦の線
    /// font で rect の幅に収まれば真ん中に描き，収まらなければ顔文字の下限の大きさ(kaomoji_small)に縮める．
    /// それでも収まらなければ末尾を省く(macOS の PaletteView.drawFitted．書体は前もって作るので 2 段で縮める)
    fn fitted(&mut self, text: &str, font: Font, color: Color, rect: Frame) {
        if self.painter.width(text, font) <= rect.width {
            self.painter.centered(text, font, color, rect);
            return;
        }
        let small = self.layout.fonts.kaomoji_small;
        let shown = self.painter.truncated(text, small, rect.width);
        self.painter.centered(&shown, small, color, rect);
    }

    fn search(&mut self) {
        let theme = self.theme;
        let fonts = self.layout.fonts;
        let rect = self.layout.search;
        self.fill(rect, theme.badge, palette::SEARCH_RADIUS);
        self.glyph(
            glyph::SEARCH,
            fonts.search_icon,
            (SEARCH_FALLBACK, fonts.tab_symbol),
            theme.text_muted,
            Frame::new(
                rect.x + palette::MODE_PADDING_X,
                rect.y,
                palette::SEARCH_ICON_SIZE,
                rect.height,
            ),
        );
        let caret_width = palette::SELECTION_STROKE;
        let text_x =
            rect.x + palette::MODE_PADDING_X * 2.0 + palette::SEARCH_ICON_SIZE + caret_width;
        let empty = self.panel.query.is_empty();
        let (text, color) = if empty {
            (&self.panel.placeholder, theme.text_muted)
        } else {
            (&self.panel.query, theme.text)
        };
        let available = rect.max_x() - text_x - palette::MODE_PADDING_X;
        let shown = self.painter.truncated(text, fonts.search, available);
        let width = self.painter.width(&shown, fonts.search);
        self.painter.text(&shown, fonts.search, color, text_x, rect);
        // 打った文字が探す欄に入ることを示す縦の線(入力位置)．空なら案内の文の前に置く
        let line = candidate::FRAME_WIDTH;
        let caret_x = if empty {
            text_x - caret_width * 2.0
        } else {
            (text_x + width + line).min(rect.max_x() - palette::MODE_PADDING_X)
        };
        self.painter.rect(
            Frame::new(
                caret_x.round(),
                (rect.mid_y() - palette::SEARCH_FONT_SIZE / 2.0 - line).round(),
                caret_width,
                palette::SEARCH_FONT_SIZE + line * 2.0,
            ),
            theme.selection,
        );
    }

    /// 絵文字と記号の切り替え．選んでいる方を選択の色で塗る
    fn modes(&mut self) {
        let theme = self.theme;
        let frames = &self.layout.modes;
        let (Some(first), Some(last)) = (frames.first(), frames.last()) else {
            return;
        };
        let whole = Frame::new(first.x, first.y, last.max_x() - first.x, first.height);
        self.fill(whole, theme.badge, palette::SEARCH_RADIUS);
        let font = self.layout.fonts.mode;
        for (mode, frame) in self.panel.modes.iter().zip(frames) {
            self.painter
                .centered(&mode.title, font, theme.text_muted, *frame);
        }
        let Some(selected) = self
            .panel
            .modes
            .iter()
            .position(|mode| mode.is_selected)
            .and_then(|index| frames.get(index))
        else {
            return;
        };
        // 選んでいる種類の印．切り替えたら前の種類から滑らせ，印に重なった文字だけを選択の文字の色で描き直す
        // (印が滑るあいだ，文字の色も印の端で切り替わる)
        let inner = palette::SELECTION_STROKE;
        let pill = self.tween.mode.unwrap_or(*selected).inset(inner, inner);
        self.fill(pill, theme.selection, palette::SEARCH_RADIUS - inner);
        let modes = &self.panel.modes;
        self.grouped(pill, 1.0, 1.0, |drawing| {
            for (mode, frame) in modes.iter().zip(frames) {
                if frame.x < pill.max_x() && pill.x < frame.max_x() {
                    drawing
                        .painter
                        .centered(&mode.title, font, theme.selection_text, *frame);
                }
            }
        });
    }

    /// まとまりのタブ．角丸のテーマは薄い地と下の線，platinum と desk は選択の色で塗って示す
    fn tabs(&mut self) {
        let theme = self.theme;
        let inner = palette::SELECTION_STROKE;
        let frames = &self.layout.tabs;
        let selected = self
            .panel
            .tabs
            .iter()
            .position(|tab| tab.is_selected)
            .and_then(|index| frames.get(index))
            .map(|frame| self.tween.tab.unwrap_or(*frame));
        // 選んでいるまとまりの印．まとまりが変わったら前のタブから滑らせる
        if let Some(frame) = selected {
            if theme.is_rounded() {
                self.fill(
                    frame.inset(inner, inner),
                    theme.focus_tint,
                    glass::SELECTION_RADIUS,
                );
                self.painter.rect(
                    Frame::new(
                        frame.x + inner * 2.0,
                        frame.max_y() - palette::SELECTION_STROKE,
                        frame.width - inner * 4.0,
                        palette::SELECTION_STROKE,
                    ),
                    theme.selection,
                );
            } else {
                self.painter
                    .rect(frame.inset(inner, inner), theme.selection);
            }
        }
        let tabs = &self.panel.tabs;
        for (tab, frame) in tabs.iter().zip(frames) {
            let color = if tab.is_selected && theme.is_rounded() {
                theme.text
            } else {
                theme.text_muted
            };
            self.tab_icon(tab, *frame, color);
        }
        // platinum と desk は印を選択の色で塗るので，印に重なったアイコンだけを選択の文字の色で描き直す
        if let (Some(frame), false) = (selected, theme.is_rounded()) {
            let clip = frame.inset(inner, inner);
            self.grouped(clip, 1.0, 1.0, |drawing| {
                for (tab, tab_frame) in tabs.iter().zip(frames) {
                    if tab_frame.x < clip.max_x() && clip.x < tab_frame.max_x() {
                        drawing.tab_icon(tab, *tab_frame, theme.selection_text);
                    }
                }
            });
        }
    }

    fn tab_icon(&mut self, tab: &ipc::PaletteTab, frame: Frame, color: Color) {
        let fonts = self.layout.fonts;
        match tab_glyph(&tab.section) {
            Some(glyph) => self.glyph(
                glyph,
                fonts.tab_icon,
                (&tab.symbol, fonts.tab_symbol),
                color,
                frame,
            ),
            // 顔文字のまとまりの短い顔はタブの幅に収まるよう縮める
            None => self.fitted(
                &tab.symbol,
                fonts.tab_symbol,
                color,
                frame.inset(palette::SELECTION_STROKE, 0.0),
            ),
        }
    }

    fn heading(&mut self) {
        let rect = self.layout.heading;
        let font = self.layout.fonts.heading;
        let x = rect.x + palette::CELL_RADIUS;
        let shown = self
            .painter
            .truncated(&self.panel.heading, font, rect.max_x() - x);
        self.painter
            .text(&shown, font, self.theme.text_muted, x, rect);
    }

    /// マス目．まとまりの境目の細い線・選んでいるマス・文字・知らせ・スクロールバー
    fn grid(&mut self) {
        let theme = self.theme;
        let layout = self.layout;
        let panel = self.panel;
        let fonts = layout.fonts;
        if let Some((previous, previous_layout, direction, t)) = self.tween.content {
            // 中身を送る．前の中身を送る向きへ出ていかせながら薄くし，今の中身を手前から入れながら濃くする
            let (dx, dy) = match direction {
                PaletteContentMotion::Next => (1.0, 0.0),
                PaletteContentMotion::Previous => (-1.0, 0.0),
                PaletteContentMotion::Down => (0.0, 1.0),
                PaletteContentMotion::Up => (0.0, -1.0),
            };
            let shift = palette::CONTENT_SHIFT;
            let stroke = palette::SELECTION_STROKE;
            let clip = layout.grid.inset(-stroke, -stroke);
            self.grouped(clip, 1.0 - t, 1.0, |drawing| {
                drawing.cells(previous, previous_layout, None);
                drawing.shift_all(-dx * shift * t, -dy * shift * t);
            });
            self.grouped(clip, t, 1.0, |drawing| {
                drawing.cells(panel, layout, None);
                drawing.shift_all(dx * shift * (1.0 - t), dy * shift * (1.0 - t));
            });
        } else {
            self.cells(panel, layout, self.tween.selection);
        }
        if let Some(message) = &panel.message {
            let shown = self
                .painter
                .truncated(message, fonts.detail, layout.footer.width);
            self.painter
                .centered(&shown, fonts.detail, theme.text_muted, layout.grid);
        }
        self.scrollbar();
    }

    /// 描いた部品をすべて dx, dy だけずらす(まとまりの中で使う)
    fn shift_all(&mut self, dx: f32, dy: f32) {
        let draws = std::mem::take(&mut self.painter.draws);
        self.painter.draws = draws.into_iter().map(|draw| draw.offset(dx, dy)).collect();
    }

    /// panel のマス目の線・選択の枠・文字．sliding は滑っている途中の選択の枠の位置
    fn cells(&mut self, panel: &PalettePanel, layout: &Layout, sliding: Option<Frame>) {
        let theme = self.theme;
        let last_row = panel.first_row.saturating_add(panel.visible_rows);
        let selected = panel.selection.as_ref().map(|position| {
            sliding.unwrap_or_else(|| layout.cell_frame(position.row, position.column))
        });
        if let Some(frame) = selected {
            self.selection(frame);
        }
        let mut cells = Vec::new();
        for row in &panel.rows {
            // 見えている行だけを描く(マス目の外にはみ出さない)
            if row.index < panel.first_row || row.index >= last_row {
                continue;
            }
            if row.starts_section && row.index != panel.first_row {
                let top = layout.cell_frame(row.index, 0).y.round();
                self.painter.rect(
                    Frame::new(
                        layout.grid.x + palette::CELL_RADIUS,
                        top,
                        layout.grid.width - palette::CELL_RADIUS * 2.0,
                        candidate::FRAME_WIDTH,
                    ),
                    theme.line,
                );
            }
            for (column, cell) in (0..panel.columns).zip(&row.cells) {
                let frame = layout.cell_frame(row.index, column);
                self.cell(&cell.text, frame, layout, theme.text);
                cells.push((cell.text.as_str(), frame));
            }
        }
        // platinum と desk の選んでいるマスは選択の色で塗るので，枠に重なった文字だけを選択の文字の色で描き直す
        // (枠が滑るあいだ，文字の色も枠の端で切り替わる)
        if let (Some(frame), false) = (selected, theme.is_rounded()) {
            let clip = frame.inset(candidate::FRAME_WIDTH, candidate::FRAME_WIDTH);
            self.grouped(clip, 1.0, 1.0, |drawing| {
                for (text, cell) in &cells {
                    let overlaps = cell.x < clip.max_x()
                        && clip.x < cell.max_x()
                        && cell.y < clip.max_y()
                        && clip.y < cell.max_y();
                    if overlaps {
                        drawing.cell(text, *cell, layout, theme.selection_text);
                    }
                }
            });
        }
    }

    /// 1 つのマスの文字
    fn cell(&mut self, text: &str, frame: Frame, layout: &Layout, color: Color) {
        let fonts = layout.fonts;
        if layout.wide {
            // 顔文字は絵文字を含んでいても候補の書体で描く(顔の形を崩さない)
            self.fitted(
                text,
                fonts.cell_kaomoji,
                color,
                frame.inset(palette::KAOMOJI_PADDING_X, 0.0),
            );
            return;
        }
        let font = if is_emoji(text) {
            fonts.cell_emoji
        } else {
            fonts.cell_symbol
        };
        self.painter.centered(text, font, color, frame);
    }

    /// 全体の行がマス目に収まらないときだけ，右に見えている位置を示すつまみを描く
    fn scrollbar(&mut self) {
        let panel = self.panel;
        if panel.row_count <= panel.visible_rows {
            return;
        }
        let rect = self.layout.scrollbar;
        let length = (rect.height * panel.visible_rows as f32 / panel.row_count as f32)
            .max(palette::SCROLLBAR_MIN_LENGTH)
            .min(rect.height);
        let travel = rect.height - length;
        let maximum_first = (panel.row_count - panel.visible_rows) as f32;
        let progress = (panel.first_row as f32 / maximum_first).min(1.0);
        self.fill(
            Frame::new(
                rect.x,
                (rect.y + travel * progress).round(),
                rect.width,
                length.round(),
            ),
            self.theme
                .text_muted
                .with_alpha(opacity::palette::SCROLLBAR),
            rect.width / 2.0,
        );
    }

    /// 選んでいる文字の説明．左上に大きな見本，右上にピン留めのボタン，見本の右と下に名前・読み・札(palette::preview)
    fn preview(&mut self, shown: &PalettePreview, rect: Frame) {
        let theme = self.theme;
        let fonts = self.layout.fonts;
        let content = preview::content_area(rect);
        let side = preview::tile_side();
        let mut tile = Frame::new(content.x, content.y, side, side);
        if self.layout.wide {
            // 顔文字は横に長いので，文字の幅に合わせて枠を広げる(説明の欄の幅の一定の割合まで)
            let width = self.painter.width(&shown.text, fonts.preview_kaomoji)
                + palette::KAOMOJI_PADDING_X * 4.0;
            tile.width = tile
                .width
                .max(width.ceil())
                .min((rect.width * palette::PREVIEW_KAOMOJI_WIDTH).round());
            self.fill(tile, theme.badge, palette::CELL_RADIUS);
            self.fitted(
                &shown.text,
                fonts.preview_kaomoji,
                theme.text,
                tile.inset(palette::KAOMOJI_PADDING_X, 0.0),
            );
        } else {
            self.fill(tile, theme.badge, palette::CELL_RADIUS);
            let font = if is_emoji(&shown.text) {
                fonts.preview_emoji
            } else {
                fonts.preview_symbol
            };
            self.painter.centered(&shown.text, font, theme.text, tile);
        }
        let pin = self.layout.pin(rect);
        let area = preview::Area { content, tile, pin };
        for part in preview::parts(shown, &area, &fonts, self.measure) {
            self.preview_part(part);
        }
        let (glyph, color) = if shown.is_pinned {
            (glyph::PIN_FILL, theme.selection)
        } else {
            (glyph::PIN, theme.text_muted)
        };
        // ピン留めを切り替えたら，ピンを一度大きくして弾ませる
        let scale = self
            .tween
            .pin
            .map_or(1.0, |t| 1.0 + (palette::PIN_BOUNCE - 1.0) * bounce(t));
        let room = pin.width * (palette::PIN_BOUNCE - 1.0);
        self.grouped(pin.inset(-room, -room), 1.0, scale, |drawing| {
            drawing.glyph(
                glyph,
                fonts.tab_icon,
                (PIN_FALLBACK, fonts.tab_symbol),
                color,
                pin,
            );
        });
    }

    /// 説明の名前・読み・札の 1 つ
    fn preview_part(&mut self, part: Part) {
        let theme = self.theme;
        let fonts = self.layout.fonts;
        match part {
            Part::Text { text, font, frame } => {
                self.painter.text(&text, font, theme.text, frame.x, frame);
            }
            Part::Tag { text, frame } => {
                // 名前を定めたところと「読み」は，値と見分けるよう枠だけの札にする
                self.outline(
                    frame,
                    theme.line,
                    palette::PREVIEW_TAG_RADIUS,
                    candidate::FRAME_WIDTH,
                );
                self.painter
                    .centered(&text, fonts.tag, theme.text_muted, frame);
            }
            Part::Chip {
                lines,
                small,
                frame,
            } => {
                // 角丸のテーマは控えめな地．platinum と desk は光の縁の色の地に 1 ドットの枠(入力欄の形)
                if self.theme.is_rounded() {
                    self.fill(frame, theme.badge, palette::PREVIEW_CHIP_RADIUS);
                } else {
                    self.painter.rect(frame, theme.line);
                    self.painter.rect(
                        frame.inset(candidate::FRAME_WIDTH, candidate::FRAME_WIDTH),
                        theme.bevel_light,
                    );
                }
                let font = if small { fonts.code_small } else { fonts.code };
                let line = self.measure.height(font).ceil();
                for (index, text) in lines.iter().enumerate() {
                    let row = Frame::new(
                        frame.x,
                        frame.y + palette::PREVIEW_CHIP_PADDING_Y + line * index as f32,
                        frame.width,
                        line,
                    );
                    self.painter.text(
                        text,
                        font,
                        theme.text,
                        frame.x + palette::PREVIEW_CHIP_PADDING_X,
                        row,
                    );
                }
            }
            Part::More { count, frame } => {
                self.painter.text(
                    &crate::strings::more(count),
                    fonts.detail,
                    theme.text_muted,
                    frame.x,
                    frame,
                );
            }
        }
    }

    /// 足元．キーの案内(収まらないものは後ろから出さない)と，右に既定の肌の色のボタン
    fn footer(&mut self) {
        let theme = self.theme;
        let footer = self.layout.footer;
        let hints = self.painter.hints_fitting(
            &self.panel.hints,
            footer.width - palette::FOOTER_HEIGHT - palette::GAP,
        );
        self.painter.hints(&hints, footer.x, footer.mid_y());
        let inset = skin_tone_button_inset();
        let button = self.layout.skin_tone_button.inset(inset, inset);
        self.fill(button, theme.badge, palette::CELL_RADIUS);
        self.painter.centered(
            &skin_tone_sample(self.panel.skin_tone),
            self.layout.fonts.button_emoji,
            theme.text,
            button,
        );
    }

    /// 肌の色の帯．下の説明の文字が帯のまわりに見えないよう，説明の欄ごと面の色で覆ってから重ねる
    fn picker(&mut self, picker: &PaletteSkinTonePicker) {
        let theme = self.theme;
        let cells = self.layout.picker_cells(picker.options.len());
        let (Some(first), Some(last)) = (cells.first(), cells.last()) else {
            return;
        };
        let margin = palette::SELECTION_STROKE * 2.0;
        let strip = Frame::new(first.x, first.y, last.max_x() - first.x, first.height)
            .inset(-margin, -margin);
        let surface = theme.surface.with_alpha(1.0);
        // 開いたら，覆いと帯を薄い形から濃くし，帯は少し小さい形から少し行き過ぎて元の大きさへ浮かび上がらせる
        let (opacity, scale) = self.tween.picker.map_or((1.0, 1.0), |t| {
            (
                (t * 2.0).min(1.0).powf(0.5),
                palette::POP_SCALE + (1.0 - palette::POP_SCALE) * overshoot(t),
            )
        });
        let body = self.layout.body;
        self.grouped(body, opacity, 1.0, |drawing| {
            if let Some(preview) = drawing.layout.preview {
                drawing.painter.rect(cover(preview), surface);
            }
            let room = strip.height;
            drawing.grouped(strip.inset(-room, -room), 1.0, scale, |drawing| {
                drawing.fill(strip, surface, palette::SEARCH_RADIUS);
                drawing.outline(
                    strip,
                    theme.frame,
                    palette::SEARCH_RADIUS,
                    candidate::FRAME_WIDTH,
                );
                for (index, (option, frame)) in picker.options.iter().zip(&cells).enumerate() {
                    if index == picker.selected as usize {
                        drawing.selection(*frame);
                    }
                    drawing.painter.centered(
                        option,
                        drawing.layout.fonts.picker_emoji,
                        theme.text,
                        *frame,
                    );
                }
            });
        });
    }
}

/// 肌の色の帯の下に敷く面．説明の欄を，上の区切りの線の下から覆う(見出しの名前の字の上の端も隠す)
fn cover(preview: Frame) -> Frame {
    let top = (preview.y - palette::GAP / 2.0).round() + candidate::FRAME_WIDTH;
    Frame::new(preview.x, top, preview.width, preview.max_y() - top)
}

#[cfg(test)]
mod tests {
    use super::super::sample;
    use super::*;
    use crate::scene::testing::{count, flattened, text_frame, texts, theme, Fixed};
    use crate::theme::Role;

    /// アイコンの書体が入っているとして測る
    struct WithIcons;

    impl Measure for WithIcons {
        fn width(&self, text: &str, font: Font) -> f32 {
            Fixed.width(text, font)
        }

        fn height(&self, font: Font) -> f32 {
            Fixed.height(font)
        }

        fn has_glyph(&self, font: Font, _glyph: char) -> bool {
            matches!(font, Font::Sized(Role::Icon, _))
        }
    }

    fn draw(panel: &PalettePanel, name: &str, measure: &dyn Measure) -> (Layout, Scene) {
        let theme = theme(name);
        let layout = Layout::new(panel, &theme, measure);
        let scene = palette(
            panel,
            &layout,
            &Look::new(&theme, 15.0),
            measure,
            Tween::default(),
        );
        (layout, scene)
    }

    fn fonts_of(scene: &Scene) -> Vec<(String, Font)> {
        flattened(&scene.draws)
            .into_iter()
            .filter_map(|draw| match draw {
                Draw::Text { text, font, .. } => Some((text.clone(), *font)),
                _ => None,
            })
            .collect()
    }

    #[test]
    fn 窓の大きさは配置と同じ() {
        for name in ["automatic", "platinum", "desk", "washi"] {
            let (layout, scene) = draw(&sample::emoji(), name, &Fixed);
            assert_eq!((scene.width, scene.height), (layout.width, layout.height));
        }
    }

    #[test]
    fn 使う書体はすべて前もって作る書体の中にある() {
        for panel in [
            sample::emoji(),
            sample::search(),
            sample::symbol(),
            sample::kaomoji(),
        ] {
            for measure in [&Fixed as &dyn Measure, &WithIcons] {
                let (layout, scene) = draw(&panel, "automatic", measure);
                let prepared = layout.fonts.all();
                for (text, font) in fonts_of(&scene) {
                    assert!(
                        prepared.contains(&font) || matches!(font, Font::Label | Font::Key),
                        "{text} {font:?}"
                    );
                }
            }
        }
    }

    #[test]
    fn 顔文字は広いマスに候補の書体で描き収まらなければ縮めて省く() {
        let (layout, scene) = draw(&sample::kaomoji(), "automatic", &Fixed);
        let fonts = fonts_of(&scene);
        assert!(layout.wide);
        assert!(fonts.contains(&("(^o^)".into(), layout.fonts.cell_kaomoji)));
        // 絵文字の字(✧)を含む顔文字も絵文字の書体にしない
        assert!(!fonts
            .iter()
            .any(|(text, font)| text.contains('✧') && *font == layout.fonts.cell_emoji));
        // 広いマス(幅 108 から余白を除いた 100)に収まらない 23 文字の顔文字は，下限の大きさにして末尾を省く
        let long = fonts
            .iter()
            .find(|(text, _)| text.starts_with("((((((((("))
            .expect("長い顔文字");
        assert_eq!(long.1, layout.fonts.kaomoji_small);
        assert!(long.0.ends_with('…'));
        // 説明の大きな顔文字と，タブの短い顔
        assert!(fonts.contains(&("(´・ω・｀)".into(), layout.fonts.preview_kaomoji)));
        assert!(fonts.contains(&("T_T".into(), layout.fonts.tab_symbol)));
    }

    /// from から to へ動き始めて milliseconds たったところ
    fn draw_moving(
        from: &PalettePanel,
        to: &PalettePanel,
        milliseconds: f32,
        name: &str,
    ) -> (Layout, Scene) {
        let theme = theme(name);
        let from_layout = Layout::new(from, &theme, &Fixed);
        let layout = Layout::new(to, &theme, &Fixed);
        let start = std::time::Instant::now();
        let mut motion = super::super::motion::Motion::default();
        motion.start(from, &from_layout, to, &layout, start);
        let at = start + std::time::Duration::from_secs_f32(milliseconds / 1000.0);
        let tween = motion.tween(to, &layout, at);
        let scene = palette(to, &layout, &Look::new(&theme, 15.0), &Fixed, tween);
        (layout, scene)
    }

    #[test]
    fn 動きの途中は印と枠を滑らせ_中身を送るときは前と今の中身を薄くして重ねる() {
        let steps = sample::motion_steps();
        // 選択の枠とタブの印が滑っている途中
        let (from, to, milliseconds) = &steps[0];
        let (layout, scene) = draw_moving(from, to, *milliseconds, "automatic");
        let target = layout
            .cell_frame(3, 6)
            .inset(candidate::FRAME_WIDTH, candidate::FRAME_WIDTH);
        let focus = theme("automatic").focus_tint;
        let tints: Vec<Frame> = flattened(&scene.draws)
            .into_iter()
            .filter_map(|draw| match draw {
                Draw::RoundRect {
                    frame,
                    fill: Some(color),
                    ..
                } if *color == focus && frame.width == target.width => Some(*frame),
                _ => None,
            })
            .collect();
        assert!(!tints.contains(&target), "滑り終えていない");
        // 種類を切り替えて中身を送っている途中．前と今の中身を，濃さの和が 1 のまとまりで重ねる
        let (from, to, milliseconds) = &steps[1];
        let (layout, scene) = draw_moving(from, to, *milliseconds, "platinum");
        let groups: Vec<f32> = scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Group {
                    clip,
                    opacity,
                    draws,
                    ..
                } if clip.width > layout.grid.width && !draws.is_empty() => Some(*opacity),
                _ => None,
            })
            .collect();
        assert_eq!(groups.len(), 2);
        assert!((groups[0] + groups[1] - 1.0).abs() < 1e-4);
        assert!(groups
            .iter()
            .all(|opacity| *opacity > 0.0 && *opacity < 1.0));
        // 止まっていればまとまりで重ねない
        let (_, still) = draw(to, "platinum", &Fixed);
        assert!(!still.draws.iter().any(
            |draw| matches!(draw, Draw::Group { clip, .. } if clip.width > layout.grid.width)
        ));
    }

    #[test]
    fn 肌の色の帯は浮かび上がる途中は薄く小さい() {
        let steps = sample::motion_steps();
        let (from, to, milliseconds) = &steps[2];
        let (_, scene) = draw_moving(from, to, *milliseconds, "automatic");
        let popping = scene.draws.iter().find_map(|draw| match draw {
            Draw::Group { opacity, draws, .. } if *opacity < 1.0 => {
                draws.iter().find_map(|inner| match inner {
                    Draw::Group { scale, .. } => Some((*opacity, *scale)),
                    _ => None,
                })
            }
            _ => None,
        });
        let (opacity, scale) = popping.expect("帯が浮かび上がっている");
        assert!(opacity > 0.0 && opacity < 1.0);
        assert!(scale > palette::POP_SCALE && scale < 1.1);
    }

    #[test]
    fn 絵文字は絵文字の書体で記号は候補の書体で描く() {
        let (layout, emoji) = draw(&sample::emoji(), "automatic", &Fixed);
        let fonts = fonts_of(&emoji);
        assert!(fonts.contains(&("😀".into(), layout.fonts.cell_emoji)));
        assert!(fonts.contains(&("☺\u{FE0F}".into(), layout.fonts.cell_emoji)));
        let (layout, symbol) = draw(&sample::symbol(), "automatic", &Fixed);
        let fonts = fonts_of(&symbol);
        assert!(fonts.contains(&("⇐".into(), layout.fonts.cell_symbol)));
        assert!(fonts.contains(&("⇒".into(), layout.fonts.preview_symbol)));
        // 肌の色のボタンは絵文字の書体
        assert!(fonts.contains(&("👋".into(), layout.fonts.button_emoji)));
    }

    #[test]
    fn 選んでいるマスは地と枠で示す() {
        let panel = sample::emoji();
        let (layout, scene) = draw(&panel, "automatic", &Fixed);
        let rounded = theme("automatic");
        let selected = layout.cell_frame(1, 2);
        let inner = selected.inset(candidate::FRAME_WIDTH, candidate::FRAME_WIDTH);
        assert!(scene.draws.contains(&Draw::RoundRect {
            frame: inner,
            radius: palette::CELL_RADIUS,
            fill: Some(rounded.focus_tint),
            stroke: None,
        }));
        let half = palette::SELECTION_STROKE / 2.0;
        assert!(scene.draws.contains(&Draw::RoundRect {
            frame: inner.inset(half, half),
            radius: palette::CELL_RADIUS,
            fill: None,
            stroke: Some((rounded.selection, palette::SELECTION_STROKE)),
        }));
        // platinum は角の立った枠を 4 本の長方形で描く
        let (layout, scene) = draw(&panel, "platinum", &Fixed);
        let platinum = theme("platinum");
        let inner = layout
            .cell_frame(1, 2)
            .inset(candidate::FRAME_WIDTH, candidate::FRAME_WIDTH);
        assert!(scene.draws.contains(&Draw::Rect {
            frame: Frame::new(inner.x, inner.y, inner.width, palette::SELECTION_STROKE),
            color: platinum.selection,
        }));
        assert_eq!(
            count(&scene, |draw| matches!(draw, Draw::RoundRect { .. })),
            0
        );
    }

    #[test]
    fn まとまりの境目に線を引き見えている先頭の行には引かない() {
        let panel = sample::emoji();
        let (layout, scene) = draw(&panel, "automatic", &Fixed);
        let theme = theme("automatic");
        let lines: Vec<Frame> = scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Rect { frame, color }
                    if *color == theme.line && frame.x == layout.grid.x + palette::CELL_RADIUS =>
                {
                    Some(*frame)
                }
                _ => None,
            })
            .collect();
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].y, layout.cell_frame(1, 0).y);
        assert_eq!(lines[0].height, candidate::FRAME_WIDTH);
        assert_eq!(lines[0].y, lines[0].y.round());
    }

    #[test]
    fn スクロールバーは行が収まらないときだけ描く() {
        let scrollbar = |scene: &Scene, layout: &Layout| {
            count(
                scene,
                |draw| matches!(draw, Draw::RoundRect { frame, .. } if frame.x == layout.scrollbar.x),
            )
        };
        let (layout, scene) = draw(&sample::emoji(), "automatic", &Fixed);
        assert_eq!(scrollbar(&scene, &layout), 1);
        let (layout, scene) = draw(&sample::search(), "automatic", &Fixed);
        assert_eq!(scrollbar(&scene, &layout), 0);
        // 最後までスクロールしたら，つまみの下の端はマス目の下の端
        let mut panel = sample::emoji();
        panel.first_row = panel.row_count - panel.visible_rows;
        for (offset, row) in panel.rows.iter_mut().enumerate() {
            row.index = panel.first_row + offset as u32;
        }
        let (layout, scene) = draw(&panel, "automatic", &Fixed);
        let thumb = scene.draws.iter().find_map(|draw| match draw {
            Draw::RoundRect { frame, .. } if frame.x == layout.scrollbar.x => Some(*frame),
            _ => None,
        });
        let thumb = thumb.unwrap();
        assert!((thumb.max_y() - layout.scrollbar.max_y()).abs() <= 1.0);
    }

    #[test]
    fn 探す語が無ければ案内を薄く出し入力位置の線を描く() {
        let theme = theme("automatic");
        let (_, scene) = draw(&sample::emoji(), "automatic", &Fixed);
        assert!(texts(&scene).contains(&("絵文字を検索".into(), theme.text_muted)));
        let (layout, scene) = draw(&sample::search(), "automatic", &Fixed);
        assert!(texts(&scene).contains(&("おじぎ".into(), theme.text)));
        let query = text_frame(&scene, "おじぎ").unwrap();
        let caret = scene.draws.iter().find_map(|draw| match draw {
            Draw::Rect { frame, color }
                if *color == theme.selection && frame.width == palette::SELECTION_STROKE =>
            {
                Some(*frame)
            }
            _ => None,
        });
        let caret = caret.unwrap();
        assert!(caret.x >= query.max_x());
        assert!(caret.max_x() <= layout.search.max_x());
    }

    #[test]
    fn タブはアイコンの書体があればアイコンで描き無ければ代表の文字で描く() {
        let panel = sample::symbol();
        let (layout, scene) = draw(&panel, "automatic", &WithIcons);
        let fonts = fonts_of(&scene);
        // ピン留めはアイコン，記号のまとまりは代表の文字
        assert!(fonts.contains(&(glyph::PIN.to_string(), layout.fonts.tab_icon)));
        assert!(fonts.contains(&("±".into(), layout.fonts.tab_symbol)));
        let (layout, scene) = draw(&panel, "automatic", &Fixed);
        let fonts = fonts_of(&scene);
        assert!(fonts.contains(&("📌".into(), layout.fonts.tab_symbol)));
        assert!(!fonts.iter().any(|(_, font)| *font == layout.fonts.tab_icon));
        let (layout, scene) = draw(&sample::emoji(), "automatic", &WithIcons);
        assert!(fonts_of(&scene).contains(&(glyph::EMOJI.to_string(), layout.fonts.tab_icon)));
    }

    #[test]
    fn 説明は名前と名前を定めたところと読みと札を並べピン留めを示す() {
        let theme = theme("automatic");
        let (layout, scene) = draw(&sample::emoji(), "automatic", &WithIcons);
        let shown = texts(&scene);
        assert!(shown.contains(&("笑顔".into(), theme.text)));
        for tag in ["CLDR", "Unicode", "読み"] {
            assert!(shown.contains(&(tag.into(), theme.text_muted)), "{tag}");
        }
        // Unicode の名前は折り返し(ピン留めのボタンの高さまではボタンの手前で止める)，読みは「、」でつなぐ
        for line in ["SMILING FACE", "WITH OPEN MOUTH AND", "SMILING EYES"] {
            assert!(shown.contains(&(line.into(), theme.text)), "{line}");
        }
        let first = text_frame(&scene, "SMILING FACE").unwrap();
        let second = text_frame(&scene, "WITH OPEN MOUTH AND").unwrap();
        assert_eq!(first.x, second.x);
        let readings = "えがお、すまいる、はっぴー、わーい";
        assert!(shown.contains(&(readings.into(), theme.text)));
        // ショートコードとコードポイントは等幅の札にし，途中で切らない
        let fonts = fonts_of(&scene);
        assert!(fonts.contains(&(":smile:".into(), layout.fonts.code)));
        assert!(fonts.contains(&("U+1F604".into(), layout.fonts.code)));
        assert!(!shown.iter().any(|(text, _)| text.contains('…')));
        assert!(scene.draws.iter().any(|draw| matches!(
            draw,
            Draw::RoundRect { fill: Some(color), radius, .. }
                if *color == theme.badge && *radius == palette::PREVIEW_CHIP_RADIUS
        )));
        // 見出しの名前・読み・札は上から順に重ならず，説明の欄に収まる
        let name = text_frame(&scene, "笑顔").unwrap();
        let reading = text_frame(&scene, readings).unwrap();
        let chip = text_frame(&scene, ":smile:").unwrap();
        assert!(reading.y >= name.max_y());
        assert!(chip.y >= reading.max_y());
        assert!(chip.max_y() <= layout.preview.unwrap().max_y());
        assert!(shown.contains(&(glyph::PIN.to_string(), theme.text_muted)));
        // ピン留めしてある文字は塗ったピンを選択の色で
        let (_, pinned) = draw(&sample::search(), "automatic", &WithIcons);
        assert!(texts(&pinned).contains(&(glyph::PIN_FILL.to_string(), theme.selection)));
    }

    #[test]
    fn 国旗の並びには_cldr_の英語の名前を出し_platinum_の札は入力欄の形にする() {
        let theme = theme("platinum");
        let (_, scene) = draw(&sample::flag(), "platinum", &Fixed);
        let shown = texts(&scene);
        assert!(shown.contains(&("旗: 日本".into(), theme.text)));
        assert!(shown.contains(&("flag: Japan".into(), theme.text)));
        assert_eq!(shown.iter().filter(|(text, _)| text == "CLDR").count(), 2);
        for chip in [":jp:", ":flag-jp:", "U+1F1EF", "U+1F1F5"] {
            let text = text_frame(&scene, chip).unwrap();
            assert!(
                scene.draws.iter().any(|draw| matches!(
                    draw,
                    Draw::Rect { frame, color }
                        if *color == theme.bevel_light && frame.x <= text.x && frame.max_x() >= text.max_x()
                )),
                "{chip}"
            );
        }
        assert_eq!(
            count(&scene, |draw| matches!(draw, Draw::RoundRect { .. })),
            0
        );
    }

    #[test]
    fn 顔文字の説明には名前と読みだけを出す() {
        let theme = theme("automatic");
        let (layout, scene) = draw(&sample::kaomoji(), "automatic", &Fixed);
        let shown = texts(&scene);
        assert!(shown.contains(&("しょぼーん".into(), theme.text)));
        assert!(shown.contains(&("しょんぼり、がっかり".into(), theme.text)));
        assert!(!shown
            .iter()
            .any(|(text, _)| text == "CLDR" || text == "Unicode"));
        assert!(!fonts_of(&scene)
            .iter()
            .any(|(_, font)| *font == layout.fonts.code));
    }

    #[test]
    fn 肌の色の帯は説明の欄を覆い選んでいる肌の色を示す() {
        let panel = sample::search();
        let (layout, scene) = draw(&panel, "automatic", &Fixed);
        let theme = theme("automatic");
        let preview = layout.preview.unwrap();
        // 帯は開く動きのためにまとまり(Draw::Group)に入れるので，まとまりの中も含めた描く順で比べる
        let draws = flattened(&scene.draws);
        let cover = draws.iter().position(|draw| {
            **draw
                == Draw::Rect {
                    frame: super::cover(preview),
                    color: theme.surface.with_alpha(1.0),
                }
        });
        let cover = cover.unwrap();
        // 説明の文字は覆う前に描く
        let name = draws
            .iter()
            .position(|draw| matches!(draw, Draw::Text { text, .. } if text == "おじぎする人"));
        assert!(name.unwrap() < cover);
        let cells = layout.picker_cells(6);
        for option in &panel.skin_tone_picker.as_ref().unwrap().options {
            assert!(text_frame(&scene, option).is_some(), "{option}");
        }
        let inner = cells[2].inset(candidate::FRAME_WIDTH, candidate::FRAME_WIDTH);
        assert!(draws.contains(&&Draw::RoundRect {
            frame: inner,
            radius: palette::CELL_RADIUS,
            fill: Some(theme.focus_tint),
            stroke: None,
        }));
    }

    #[test]
    fn キーの案内は収まらないものを後ろから出さない() {
        let panel = sample::emoji();
        let (layout, scene) = draw(&panel, "automatic", &Fixed);
        let shown = texts(&scene);
        assert!(shown.iter().any(|(text, _)| text == "入力"));
        assert!(!shown.iter().any(|(text, _)| text == "閉じる"));
        // 出した案内は肌の色のボタンにかからない
        let right = scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Text {
                    frame,
                    font: Font::Label,
                    ..
                } if frame.y >= layout.footer.y => Some(frame.max_x()),
                _ => None,
            })
            .fold(0.0, f32::max);
        assert!(right <= layout.skin_tone_button.x);
    }

    #[test]
    fn 知らせはマス目の中央に出す() {
        let panel = PalettePanel {
            rows: vec![],
            row_count: 0,
            selection: None,
            preview: None,
            message: Some("見つかりません".into()),
            ..sample::search()
        };
        let (layout, scene) = draw(&panel, "automatic", &Fixed);
        let frame = text_frame(&scene, "見つかりません").unwrap();
        assert!((frame.mid_x() - layout.grid.mid_x()).abs() <= 1.0);
        assert_eq!(frame.y, layout.grid.y);
        assert_eq!(frame.height, layout.grid.height);
    }

    #[test]
    fn desk_は影を付け_platinum_は付けない() {
        let (layout, desk) = draw(&sample::emoji(), "desk", &Fixed);
        let shadow = theme("desk").frame;
        assert!(desk.draws.contains(&Draw::Rect {
            frame: layout
                .body
                .offset(candidate::SHADOW_OFFSET, candidate::SHADOW_OFFSET),
            color: shadow,
        }));
        let (layout, platinum) = draw(&sample::emoji(), "platinum", &Fixed);
        assert_eq!(layout.body.width, layout.width);
        assert!(!platinum.draws.iter().any(|draw| matches!(draw, Draw::Rect { frame, .. } if frame.x == candidate::SHADOW_OFFSET && frame.y == candidate::SHADOW_OFFSET)));
    }
}
