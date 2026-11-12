#![forbid(unsafe_code)]

//! パレットの中身を，描く順の部品(Draw)の並びにする(macOS の PaletteView.draw)．
//! 位置は layout と同じものを使い，押した位置を調べる側とずれないようにする

use super::emoji::{is_emoji, skin_tone_sample};
use super::layout::{skin_tone_button_inset, Layout};
use super::preview::{self, Part, Role};
use crate::geometry::Frame;
use crate::scene::paint::Painter;
use crate::scene::{Draw, Look, Measure, Scene};
use crate::theme::{Color, Font, ResolvedTheme};
use ipc::{PalettePanel, PalettePosition, PalettePreview, PaletteSkinTonePicker};
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

/// パレットの窓の中身．窓の大きさは layout と同じ
pub fn palette(panel: &PalettePanel, layout: &Layout, look: &Look, measure: &dyn Measure) -> Scene {
    let mut drawing = Drawing {
        painter: Painter::new(look, measure),
        theme: look.theme,
        measure,
        layout,
        panel,
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
        let inner = palette::SELECTION_STROKE;
        for (mode, frame) in self.panel.modes.iter().zip(frames) {
            let color = if mode.is_selected {
                self.fill(
                    frame.inset(inner, inner),
                    theme.selection,
                    palette::SEARCH_RADIUS - inner,
                );
                theme.selection_text
            } else {
                theme.text_muted
            };
            self.painter
                .centered(&mode.title, self.layout.fonts.mode, color, *frame);
        }
    }

    /// まとまりのタブ．角丸のテーマは薄い地と下の線，platinum と desk は選択の色で塗って示す
    fn tabs(&mut self) {
        let theme = self.theme;
        let fonts = self.layout.fonts;
        let inner = palette::SELECTION_STROKE;
        for (tab, frame) in self.panel.tabs.iter().zip(&self.layout.tabs) {
            let mut color = if tab.is_selected {
                theme.text
            } else {
                theme.text_muted
            };
            if tab.is_selected && theme.is_rounded() {
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
            } else if tab.is_selected {
                self.painter
                    .rect(frame.inset(inner, inner), theme.selection);
                color = theme.selection_text;
            }
            match tab_glyph(&tab.section) {
                Some(glyph) => self.glyph(
                    glyph,
                    fonts.tab_icon,
                    (&tab.symbol, fonts.tab_symbol),
                    color,
                    *frame,
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
        let last_row = panel.first_row.saturating_add(panel.visible_rows);
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
                let selected = panel.selection
                    == Some(PalettePosition {
                        row: row.index,
                        column,
                    });
                if selected {
                    self.selection(frame);
                }
                // platinum と desk の選んでいるマスは選択の色で塗るので，記号は選択の文字の色にする
                let color = if selected && !theme.is_rounded() {
                    theme.selection_text
                } else {
                    theme.text
                };
                if layout.wide {
                    // 顔文字は絵文字を含んでいても候補の書体で描く(顔の形を崩さない)
                    self.fitted(
                        &cell.text,
                        fonts.cell_kaomoji,
                        color,
                        frame.inset(palette::KAOMOJI_PADDING_X, 0.0),
                    );
                    continue;
                }
                let font = if is_emoji(&cell.text) {
                    fonts.cell_emoji
                } else {
                    fonts.cell_symbol
                };
                self.painter.centered(&cell.text, font, color, frame);
            }
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

    /// 選んでいる文字の説明．左に大きな見本，右に名前と「項目名 → 値」の表(palette::preview)．
    /// ピン留めのボタンは見出しの行の縦の中心に置く
    fn preview(&mut self, shown: &PalettePreview, rect: Frame) {
        let theme = self.theme;
        let fonts = self.layout.fonts;
        let content = preview::content_area(rect);
        let side = preview::tile_side();
        let mut tile = Frame::new(content.x, content.y, side, side);
        if self.layout.wide {
            // 顔文字は横に長いので，文字の幅に合わせて四角を広げる(説明の欄の幅の一定の割合まで)
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
        let area = preview::Area {
            content,
            tile,
            pin_width: palette::FOOTER_HEIGHT,
        };
        let fields = preview::fields(self.panel.preview_fields.as_ref());
        let placed = preview::place(
            shown,
            &fields,
            self.layout.wide,
            &area,
            &fonts,
            self.measure,
        );
        for part in placed.parts {
            self.preview_part(part);
        }
        let (glyph, color) = if shown.is_pinned {
            (glyph::PIN_FILL, theme.selection)
        } else {
            (glyph::PIN, theme.text_muted)
        };
        let pin = self.layout.pin(rect);
        self.glyph(
            glyph,
            fonts.tab_icon,
            (PIN_FALLBACK, fonts.tab_symbol),
            color,
            pin,
        );
    }

    /// 文字をベースラインの位置に描く．枠の高さを文字の行の高さにすると，枠の上の端から測ったベースラインの位置に描かれる
    fn text_at_baseline(&mut self, text: &str, font: Font, color: Color, x: f32, baseline: f32) {
        let (height, offset) = self.measure.line(text, font);
        let row = Frame::new(x, baseline - offset, 0.0, height);
        self.painter.text(text, font, color, x, row);
    }

    /// 説明の名前・項目名・値・札の 1 つ
    fn preview_part(&mut self, part: Part) {
        let theme = self.theme;
        let fonts = self.layout.fonts;
        match part {
            Part::Text {
                text,
                role,
                x,
                baseline,
                ..
            } => {
                // 名前と値は文字の色，名前の出どころと項目名と「+n」は控えめな色
                let color = match role {
                    Role::Heading | Role::Value | Role::Code | Role::SmallCode => theme.text,
                    Role::Source | Role::Label | Role::More => theme.text_muted,
                };
                self.text_at_baseline(&text, role.font(&fonts), color, x, baseline);
            }
            Part::Chip {
                lines,
                role,
                frame,
                text_x,
                baselines,
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
                for (line, baseline) in lines.iter().zip(baselines) {
                    self.text_at_baseline(line, role.font(&fonts), theme.text, text_x, baseline);
                }
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
        if let Some(preview) = self.layout.preview {
            self.painter.rect(cover(preview), surface);
        }
        self.fill(strip, surface, palette::SEARCH_RADIUS);
        self.outline(
            strip,
            theme.frame,
            palette::SEARCH_RADIUS,
            candidate::FRAME_WIDTH,
        );
        for (index, (option, frame)) in picker.options.iter().zip(&cells).enumerate() {
            if index == picker.selected as usize {
                self.selection(*frame);
            }
            self.painter
                .centered(option, self.layout.fonts.picker_emoji, theme.text, *frame);
        }
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
    use crate::scene::testing::{count, text_frame, texts, theme, Fixed, Uneven};
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
        let scene = palette(panel, &layout, &Look::new(&theme, 15.0), measure);
        (layout, scene)
    }

    fn fonts_of(scene: &Scene) -> Vec<(String, Font)> {
        scene
            .draws
            .iter()
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

    /// 説明の欄の中の文字(枠・文字・書体・色)と，そのベースライン(枠の上の端から測った位置)
    fn preview_texts(
        scene: &Scene,
        layout: &Layout,
        measure: &dyn Measure,
    ) -> Vec<(String, Frame, Font, Color, f32)> {
        let preview = layout.preview.unwrap();
        scene
            .draws
            .iter()
            .filter_map(|draw| match draw {
                Draw::Text {
                    text,
                    frame,
                    font,
                    color,
                } if frame.y >= preview.y - 1.0 && frame.max_y() <= preview.max_y() + 1.0 => {
                    Some((
                        text.clone(),
                        *frame,
                        *font,
                        *color,
                        frame.y + measure.line(text, *font).1,
                    ))
                }
                _ => None,
            })
            .collect()
    }

    #[test]
    fn 説明は項目名と値をベースラインでそろえ_値は同じ_x_から書き出す() {
        let theme = theme("automatic");
        let measure = Uneven;
        let (layout, scene) = draw(&sample::emoji(), "automatic", &measure);
        let fonts = layout.fonts;
        let texts = preview_texts(&scene, &layout, &measure);
        let find = |wanted: &str| {
            texts
                .iter()
                .find(|(text, ..)| text == wanted)
                .unwrap_or_else(|| panic!("{wanted}"))
        };
        // Unicode の名前は値の幅で折り返す(1 行目と 2 行目)
        let first_line = texts
            .iter()
            .find(|(text, ..)| text.starts_with("SMILING FACE"))
            .unwrap();
        let second_line = texts
            .iter()
            .find(|(text, ..)| text.ends_with("SMILING EYES") && !text.starts_with("SMILING FACE"))
            .unwrap();
        // 見出しの名前と名前の出どころは同じベースライン．出どころと項目名は控えめな色
        let name = find("笑顔");
        let source = find("CLDR");
        assert_eq!(name.4, source.4);
        assert_eq!(source.3, theme.text_muted);
        // 項目名は同じ x の列に置き，値の 1 行目と同じベースライン．値はどの行も同じ x から書き出す
        let pairs = [
            ("Unicode", first_line.0.as_str()),
            ("読み", "えがお、すまいる、はっぴー、わーい"),
            ("ショートコード", ":smile:"),
            ("コードポイント", "U+1F604"),
        ];
        let label_x = find("Unicode").1.x;
        for (label, value) in pairs {
            let label = find(label);
            let value = find(value);
            assert_eq!(label.1.x, label_x, "{}", label.0);
            assert_eq!(label.3, theme.text_muted, "{}", label.0);
            assert!((label.4 - value.4).abs() <= 0.5, "{} {}", label.0, value.0);
        }
        let value_x = first_line.1.x;
        assert_eq!(second_line.1.x, value_x);
        assert_eq!(find("えがお、すまいる、はっぴー、わーい").1.x, value_x);
        // 札の文字は札の余白の分だけ内側から書く
        for chip in [":smile:", "U+1F604"] {
            assert_eq!(find(chip).1.x, value_x + palette::PREVIEW_CHIP_PADDING_X);
            assert_eq!(find(chip).2, fonts.code);
        }
        // ピン留めのアイコンの中心は見出しの行の中心
        let pin = layout.pin(layout.preview.unwrap());
        let heading_mid = layout.preview.unwrap().y
            + preview::heading_mid_y(palette::PREVIEW_PADDING_Y, &fonts, &measure);
        assert_eq!(pin.mid_y(), heading_mid.round());
        // 文字どうしが重ならず，説明の欄に収まる(ピン留めのアイコンの字は除く)
        let boxes: Vec<Frame> = texts
            .iter()
            .filter(|(text, ..)| text != "📌")
            .map(|(text, frame, font, _, baseline)| {
                let (height, offset) = measure.line(text, *font);
                Frame::new(frame.x, baseline - offset, frame.width, height)
            })
            .collect();
        for (index, frame) in boxes.iter().enumerate() {
            for other in &boxes[index + 1..] {
                let overlaps = frame.x < other.max_x()
                    && other.x < frame.max_x()
                    && frame.y < other.max_y()
                    && other.y < frame.max_y();
                assert!(!overlaps, "{frame:?} {other:?}");
            }
            assert!(frame.max_y() <= layout.preview.unwrap().max_y());
        }
    }

    #[test]
    fn 国旗の英語の名前は英語の行に出し_platinum_の札は入力欄の形にする() {
        let theme = theme("platinum");
        let measure = Uneven;
        let (layout, scene) = draw(&sample::flag(), "platinum", &measure);
        let texts = preview_texts(&scene, &layout, &measure);
        let shown: Vec<&str> = texts.iter().map(|(text, ..)| text.as_str()).collect();
        assert_eq!(shown.iter().filter(|text| **text == "CLDR").count(), 1);
        let english = texts.iter().find(|(text, ..)| text == "英語").unwrap();
        let value = texts
            .iter()
            .find(|(text, ..)| text == "flag: Japan")
            .unwrap();
        assert!((english.4 - value.4).abs() <= 0.5);
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
        let measure = Uneven;
        let (layout, scene) = draw(&sample::kaomoji(), "automatic", &measure);
        let placed = preview_texts(&scene, &layout, &measure);
        let shown: Vec<&str> = placed
            .iter()
            .map(|(text, ..)| text.as_str())
            .filter(|text| *text != "📌")
            .collect();
        assert_eq!(
            shown,
            ["(´・ω・｀)", "しょぼーん", "読み", "しょんぼり、がっかり"]
        );
        let ojigi = sample::search();
        let (_, pinned) = draw(&ojigi, "automatic", &WithIcons);
        assert!(
            texts(&pinned).contains(&(glyph::PIN_FILL.to_string(), theme("automatic").selection))
        );
    }

    #[test]
    fn 肌の色の帯は説明の欄を覆い選んでいる肌の色を示す() {
        let panel = sample::search();
        let (layout, scene) = draw(&panel, "automatic", &Fixed);
        let theme = theme("automatic");
        let preview = layout.preview.unwrap();
        let cover = scene.draws.iter().position(|draw| {
            *draw
                == Draw::Rect {
                    frame: super::cover(preview),
                    color: theme.surface.with_alpha(1.0),
                }
        });
        let cover = cover.unwrap();
        // 説明の文字は覆う前に描く
        let name = scene
            .draws
            .iter()
            .position(|draw| matches!(draw, Draw::Text { text, .. } if text == "おじぎする人"));
        assert!(name.unwrap() < cover);
        let cells = layout.picker_cells(6);
        for option in &panel.skin_tone_picker.as_ref().unwrap().options {
            assert!(text_frame(&scene, option).is_some(), "{option}");
        }
        let inner = cells[2].inset(candidate::FRAME_WIDTH, candidate::FRAME_WIDTH);
        assert!(scene.draws.contains(&Draw::RoundRect {
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
