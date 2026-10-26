#![forbid(unsafe_code)]

//! 候補ウィンドウと分岐図に共通の部品(macOS の GlassDrawing と BevelDrawing に当たる)

use super::{Draw, Frame, Look, Measure, Point, Scene};
use crate::keys::{self, Icon, Part};
use crate::theme::{Color, Font, Kind, ResolvedTheme};
use ipc::KeyHint;
use tokens::opacity;
use tokens::size::{branch, candidate, glass};

pub(super) struct Painter<'a> {
    pub theme: &'a ResolvedTheme,
    pub measure: &'a dyn Measure,
    pub draws: Vec<Draw>,
}

impl<'a> Painter<'a> {
    pub fn new(look: &Look<'a>, measure: &'a dyn Measure) -> Self {
        Self {
            theme: look.theme,
            measure,
            draws: Vec::new(),
        }
    }

    pub fn finish(self, width: f32, height: f32) -> Scene {
        Scene {
            width,
            height,
            body: Frame::new(0.0, 0.0, width, height),
            draws: self.draws,
        }
    }

    /// 文字の幅(切り上げ)
    pub fn width(&self, text: &str, font: Font) -> f32 {
        if text.is_empty() {
            0.0
        } else {
            self.measure.width(text, font).ceil()
        }
    }

    pub fn rect(&mut self, frame: Frame, color: Color) {
        self.draws.push(Draw::Rect { frame, color });
    }

    /// 行の高さの中で縦に中央にそろえて描く．左端は整数に丸め，文字の輪郭をぼかさない
    pub fn text(&mut self, text: &str, font: Font, color: Color, x: f32, row: Frame) {
        if text.is_empty() {
            return;
        }
        let width = self.width(text, font);
        self.draws.push(Draw::Text {
            frame: Frame::new(x.round(), row.y, width, row.height),
            text: text.to_string(),
            font,
            color,
        });
    }

    /// 右端を right にそろえて描く
    pub fn text_right(&mut self, text: &str, font: Font, color: Color, right: f32, row: Frame) {
        let width = self.width(text, font);
        self.text(text, font, color, right - width, row);
    }

    /// frame の中央に描く
    pub fn centered(&mut self, text: &str, font: Font, color: Color, frame: Frame) {
        let width = self.measure.width(text, font);
        self.text(text, font, color, frame.mid_x() - width / 2.0, frame);
    }

    // MARK: - 枠

    /// 窓の枠．角丸のテーマは角丸の縁と面(すりガラスの地なら面を塗らない)，platinum と desk は立体の縁
    pub fn panel(&mut self, body: Frame) {
        if self.theme.is_rounded() {
            if self.theme.backdrop {
                // 地と縁と角の丸みは OS(DWM)が描く
                return;
            }
            self.draws.push(Draw::RoundRect {
                frame: body.inset(0.5, 0.5),
                radius: self.theme.corner_radius,
                fill: Some(self.theme.surface),
                stroke: Some((self.theme.frame, candidate::FRAME_WIDTH)),
            });
            return;
        }
        if self.theme.has_drop_shadow() {
            // ぼかしの無い影(desk だけ)．右と下に出す
            self.rect(
                body.offset(candidate::SHADOW_OFFSET, candidate::SHADOW_OFFSET),
                self.theme.frame,
            );
        }
        self.bevel(body, self.theme.surface);
    }

    /// 外枠 1 ドット，その内側に光の縁(左と上)と影の縁(右と下)を描き，面を塗る
    fn bevel(&mut self, frame: Frame, surface: Color) {
        let line = candidate::FRAME_WIDTH;
        let bevel = candidate::BEVEL_WIDTH;
        self.rect(frame, self.theme.frame);
        let inner = frame.inset(line, line);
        self.rect(inner, surface);
        self.rect(
            Frame::new(inner.x, inner.y, inner.width, bevel),
            self.theme.bevel_light,
        );
        self.rect(
            Frame::new(inner.x, inner.y, bevel, inner.height),
            self.theme.bevel_light,
        );
        self.rect(
            Frame::new(inner.x, inner.max_y() - bevel, inner.width, bevel),
            self.theme.bevel_shadow,
        );
        self.rect(
            Frame::new(inner.max_x() - bevel, inner.y, bevel, inner.height),
            self.theme.bevel_shadow,
        );
    }

    /// 区画を分ける 1 ドットの線
    pub fn separator(&mut self, y: f32, from: f32, to: f32) {
        self.rect(
            Frame::new(from, y, to - from, candidate::FRAME_WIDTH),
            self.theme.line,
        );
    }

    /// 選んでいるものの角丸の地
    pub fn capsule(&mut self, frame: Frame, color: Color) {
        self.draws.push(Draw::RoundRect {
            frame,
            radius: glass::SELECTION_RADIUS,
            fill: Some(color),
            stroke: None,
        });
    }

    // MARK: - 番号の丸

    /// 番号などを入れる小さな丸．selected は選んでいる行の上(選択の地)に描くとき
    pub fn badge(
        &mut self,
        label: &str,
        center: Point,
        selected: bool,
        opacity: f32,
        side: f32,
        font: Font,
    ) {
        let frame = Frame::square(center, side);
        let fill = if selected {
            self.theme
                .selection_text
                .with_alpha(opacity::badge::SELECTED)
        } else {
            self.theme.badge.faded(opacity)
        };
        self.draws.push(Draw::Ellipse { frame, color: fill });
        let color = if selected {
            self.theme.selection_text
        } else {
            self.theme.text_muted.faded(opacity)
        };
        self.label(label, color, frame, font);
    }

    /// 番号は文字で，矢印などの記号はアイコンで，frame の中央に描く
    pub fn label(&mut self, label: &str, color: Color, frame: Frame, font: Font) {
        if let Some(icon) = keys::icon(label) {
            let side = self.icon_size(font) - 1.0;
            self.icon(
                icon,
                Frame::square(Point::new(frame.mid_x(), frame.mid_y()), side),
                color,
            );
            return;
        }
        self.centered(label, font, color, frame);
    }

    fn icon(&mut self, icon: Icon, frame: Frame, color: Color) {
        self.draws.push(Draw::Icon {
            icon,
            frame,
            color,
            width: glass::LINE_WIDTH,
        });
    }

    /// アイコンの大きさ．文字の大きさと同じ正方形
    fn icon_size(&self, font: Font) -> f32 {
        self.theme.font(font, candidate::FONT_SIZE).size
    }

    // MARK: - 下線

    /// 文節の下線．実線か点線．角丸のテーマは丸い点と丸い端の線
    pub fn underline(&mut self, from: f32, to: f32, y: f32, color: Color, dotted: bool) {
        if self.theme.is_rounded() {
            self.draws.push(Draw::Line {
                from: Point::new(from, y),
                to: Point::new(to, y),
                color,
                width: glass::LINE_WIDTH_SELECTED,
                dot_pitch: dotted.then_some(glass::DOT_PITCH),
            });
            return;
        }
        let line = Frame::new(from, y, to - from, branch::LINE_WIDTH);
        if !dotted {
            self.rect(line, color);
            return;
        }
        let step = branch::LINE_WIDTH_SELECTED * 2.0;
        let mut x = line.x;
        while x < line.max_x() {
            self.rect(
                Frame::new(
                    x,
                    line.y,
                    branch::LINE_WIDTH_SELECTED.min(line.max_x() - x),
                    line.height,
                ),
                color,
            );
            x += step;
        }
    }

    // MARK: - 足元の案内

    /// 案内の幅．描くときと大きさを求めるときで同じものを使う
    pub fn hints_width(&self, hints: &[KeyHint]) -> f32 {
        if hints.is_empty() {
            return 0.0;
        }
        hints.iter().map(|hint| self.hint_width(hint)).sum::<f32>()
            + glass::HINT_GAP * (hints.len() - 1) as f32
    }

    /// キーキャップの札とその説明を左から並べる．札の形はテーマに合わせる:
    /// 角丸のテーマは角丸，platinum は立体の縁，desk は文字の色の縁取り
    pub fn hints(&mut self, hints: &[KeyHint], x: f32, mid_y: f32) {
        let mut x = x;
        for hint in hints {
            let parts = keys::parts(&hint.keys);
            let cap = Frame::new(
                x,
                (mid_y - glass::KEYCAP_HEIGHT / 2.0).round(),
                self.keycap_width(&parts),
                glass::KEYCAP_HEIGHT,
            );
            self.keycap(cap);
            let mut part_x = cap.x + glass::KEYCAP_PADDING_X;
            for part in &parts {
                let width = self.part_width(part);
                let frame = Frame::new(part_x, cap.y, width, cap.height);
                match part {
                    Part::Icon(icon) => {
                        let side = glass::KEY_FONT_SIZE;
                        self.icon(
                            *icon,
                            Frame::square(Point::new(frame.mid_x(), frame.mid_y()), side),
                            self.theme.text,
                        );
                    }
                    Part::Text(text) => self.centered(text, Font::Key, self.theme.text, frame),
                }
                part_x += width + glass::KEYCAP_PART_GAP;
            }
            self.text(
                &hint.label,
                Font::Label,
                self.theme.text_muted,
                cap.max_x() + glass::KEYCAP_PADDING_X,
                Frame::new(
                    cap.x,
                    (mid_y - glass::FOOTER_HEIGHT / 2.0).round(),
                    0.0,
                    glass::FOOTER_HEIGHT,
                ),
            );
            x += self.hint_width(hint) + glass::HINT_GAP;
        }
    }

    fn keycap(&mut self, cap: Frame) {
        match self.theme.kind {
            Kind::Platinum => self.bevel(cap, self.theme.surface),
            Kind::Desk => {
                // 蛍光表示管の琥珀色で縁取った札
                self.rect(cap, self.theme.text.with_alpha(opacity::keycap::DESK_FILL));
                self.draws.push(Draw::RoundRect {
                    frame: cap.inset(0.5, 0.5),
                    radius: 0.0,
                    fill: None,
                    stroke: Some((
                        self.theme.text.with_alpha(opacity::keycap::DESK_STROKE),
                        candidate::FRAME_WIDTH,
                    )),
                });
            }
            _ => self.draws.push(Draw::RoundRect {
                frame: cap.inset(0.5, 0.5),
                radius: glass::KEYCAP_RADIUS,
                fill: Some(self.theme.badge),
                stroke: Some((self.theme.line, candidate::FRAME_WIDTH)),
            }),
        }
    }

    fn part_width(&self, part: &Part) -> f32 {
        match part {
            Part::Icon(_) => glass::KEY_FONT_SIZE.ceil(),
            Part::Text(text) => self.width(text, Font::Key),
        }
    }

    fn keycap_width(&self, parts: &[Part]) -> f32 {
        let content = parts.iter().map(|part| self.part_width(part)).sum::<f32>()
            + glass::KEYCAP_PART_GAP * parts.len().saturating_sub(1) as f32;
        glass::KEYCAP_HEIGHT.max((content + glass::KEYCAP_PADDING_X * 2.0).ceil())
    }

    fn hint_width(&self, hint: &KeyHint) -> f32 {
        self.keycap_width(&keys::parts(&hint.keys))
            + glass::KEYCAP_PADDING_X
            + self.width(&hint.label, Font::Label)
    }

    /// 幅に収まるよう末尾を「…」で省く
    pub fn truncated(&self, text: &str, font: Font, width: f32) -> String {
        if self.measure.width(text, font) <= width {
            return text.to_string();
        }
        let mut characters: Vec<char> = text.chars().collect();
        while !characters.is_empty() {
            let candidate: String = characters.iter().chain(std::iter::once(&'…')).collect();
            if self.measure.width(&candidate, font) <= width {
                return candidate;
            }
            characters.pop();
        }
        String::new()
    }
}
