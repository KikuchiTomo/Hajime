#![forbid(unsafe_code)]

//! 候補ウィンドウと分岐図に共通の部品(macOS の GlassDrawing と BevelDrawing に当たる)

use super::{Draw, Frame, Look, Measure, Point, Scene};
use crate::keys::{self, Icon, Part};
use crate::theme::{Color, Font, Kind, ResolvedTheme};
use ipc::{CommandKind, KeyHint};
use tokens::opacity;
use tokens::size::{branch, candidate, glass};

/// 候補の横の札の色分け
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum TagStyle {
    /// 控えめな地(「入力のまま」，取り込んだ辞書の名前)
    Plain,
    /// 補正の色の地(「修正」)
    Corrected,
    /// アクセントの色の地(「コマンド」)
    Command,
}

impl TagStyle {
    /// 添え書きの文字から決める(コマンドかどうかは候補の種類で決める)
    pub fn of(text: &str, command: bool) -> Self {
        if command {
            Self::Command
        } else if text == crate::strings::CORRECTED {
            Self::Corrected
        } else {
            Self::Plain
        }
    }
}

pub(super) struct Painter<'a> {
    pub theme: &'a ResolvedTheme,
    pub measure: &'a dyn Measure,
    pub draws: Vec<Draw>,
    pub hits: Vec<super::Hit>,
}

impl<'a> Painter<'a> {
    pub fn new(look: &Look<'a>, measure: &'a dyn Measure) -> Self {
        Self {
            theme: look.theme,
            measure,
            draws: Vec::new(),
            hits: Vec::new(),
        }
    }

    pub fn finish(self, width: f32, height: f32) -> Scene {
        Scene {
            width,
            height,
            body: Frame::new(0.0, 0.0, width, height),
            draws: self.draws,
            hits: self.hits,
        }
    }

    /// マウスで押せる範囲を足す
    pub fn hit(&mut self, frame: Frame, target: ipc::PointerTarget) {
        self.hits.push(super::Hit { frame, target });
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

    // MARK: - 案内と札(macOS の NoteDrawing と同じ形)

    /// 案内の頭のアイコン．ほかの知らせにはアイコンを付けない
    fn note_icon(tone: ipc::NoteTone) -> Option<Icon> {
        match tone {
            ipc::NoteTone::Correction => Some(Icon::Sparkle),
            ipc::NoteTone::Suggestion => Some(Icon::Lightbulb),
            ipc::NoteTone::Info => None,
        }
    }

    fn note_hints(note: &ipc::Note) -> Vec<KeyHint> {
        match (&note.key, &note.key_action) {
            (Some(key), Some(action)) => vec![KeyHint {
                keys: key.clone(),
                label: action.clone(),
            }],
            _ => Vec::new(),
        }
    }

    /// 案内の幅．描くときと大きさを求めるときで同じものを使う
    pub fn note_width(&self, note: &ipc::Note) -> f32 {
        let mut parts = Vec::new();
        if Self::note_icon(note.tone).is_some() {
            parts.push(glass::NOTE_ICON_SIZE);
        }
        if !note.title.is_empty() {
            parts.push(self.width(&note.title, Font::Label));
        }
        if let Some(subject) = &note.subject {
            parts.push(self.width(subject, Font::Label));
        }
        let hints = Self::note_hints(note);
        if !hints.is_empty() {
            parts.push(self.hints_width(&hints));
        }
        parts.iter().sum::<f32>() + glass::NOTE_GAP * parts.len().saturating_sub(1) as f32
    }

    /// 案内を x から左寄せで描く: 頭のアイコン(補正の色の地の丸)，主な語(補正の色)，
    /// 対象の字(直す前の字は薄く取り消し線，直した字は文字の色)，キーキャップの札とそのキーでできること
    pub fn note(&mut self, note: &ipc::Note, x: f32, mid_y: f32) {
        let theme = self.theme;
        let mut x = x;
        if let Some(icon) = Self::note_icon(note.tone) {
            let frame = Frame::square(
                Point::new(x + glass::NOTE_ICON_SIZE / 2.0, mid_y),
                glass::NOTE_ICON_SIZE,
            );
            if theme.is_rounded() {
                self.draws.push(Draw::Ellipse {
                    frame,
                    color: theme.correction_tint(),
                });
            } else {
                self.rect(frame, theme.correction_tint());
            }
            self.icon(
                icon,
                Frame::square(
                    Point::new(frame.mid_x(), frame.mid_y()),
                    glass::KEY_FONT_SIZE,
                ),
                theme.correction,
            );
            x = frame.max_x() + glass::NOTE_GAP;
        }
        let row = Frame::new(
            x,
            (mid_y - glass::FOOTER_HEIGHT / 2.0).round(),
            0.0,
            glass::FOOTER_HEIGHT,
        );
        if !note.title.is_empty() {
            let color = if note.tone == ipc::NoteTone::Info {
                theme.text_muted
            } else {
                theme.correction
            };
            self.text(&note.title, Font::Label, color, x, row);
            x += self.width(&note.title, Font::Label) + glass::NOTE_GAP;
        }
        if let Some(subject) = &note.subject {
            let width = self.width(subject, Font::Label);
            if note.tone == ipc::NoteTone::Correction {
                // 直す前の字は，消したことが分かるよう取り消し線で薄く
                self.text(subject, Font::Label, theme.text_muted, x, row);
                self.rect(
                    Frame::new(x, mid_y.round(), width, branch::LINE_WIDTH),
                    theme.text_muted,
                );
            } else {
                self.text(subject, Font::Label, theme.text, x, row);
            }
            x += width + glass::NOTE_GAP;
        }
        let hints = Self::note_hints(note);
        if !hints.is_empty() {
            self.hints(&hints, x, mid_y);
        }
    }

    /// 候補の横の札の幅
    pub fn tag_width(&self, text: &str) -> f32 {
        (self.width(text, Font::Label) + glass::TAG_PADDING_X * 2.0).ceil()
    }

    /// 候補の横の札(「修正」「入力のまま」「コマンド」，取り込んだ辞書の名前)．「修正」は補正の色の地，
    /// コマンドはアクセントの色の地，ほかは控えめな地．selected は選んでいる行の上(選択の地)に描くとき
    pub fn tag(&mut self, text: &str, max_x: f32, mid_y: f32, selected: bool, style: TagStyle) {
        let theme = self.theme;
        let width = self.tag_width(text);
        let frame = Frame::new(
            (max_x - width).round(),
            (mid_y - glass::TAG_HEIGHT / 2.0).round(),
            width,
            glass::TAG_HEIGHT,
        );
        let (fill, color) = if selected {
            (
                theme.selection_text.with_alpha(opacity::badge::SELECTED),
                theme.selection_text,
            )
        } else {
            match style {
                TagStyle::Corrected => (theme.correction_tint(), theme.correction),
                TagStyle::Command => (theme.command_tint(), theme.selection),
                TagStyle::Plain => (theme.badge, theme.text_muted),
            }
        };
        let radius = if theme.is_rounded() {
            glass::TAG_RADIUS
        } else {
            0.0
        };
        self.draws.push(Draw::RoundRect {
            frame,
            radius,
            fill: Some(fill),
            stroke: None,
        });
        self.centered(text, Font::Label, color, frame);
    }

    // MARK: - コマンドの候補(macOS の CommandDrawing と同じ形)

    /// 種類ごとのアイコン
    fn command_icon(kind: CommandKind) -> Icon {
        match kind {
            CommandKind::OpenApplication => Icon::Window,
            CommandKind::OpenURL => Icon::Globe,
            CommandKind::OpenFile => Icon::Document,
            CommandKind::RunShortcut => Icon::Layers,
        }
    }

    /// 種類のアイコンと，そのあとの文字までの空きを合わせた幅
    pub fn command_width() -> f32 {
        glass::COMMAND_ICON_SIZE + glass::NOTE_GAP
    }

    /// x を左端に種類のアイコンを描く．アクセントの色を薄く敷いた四角(角丸のテーマは角を丸める)にアクセントの色の線画．
    /// selected は選んでいる行の上(選択の地)に描くとき．opacity は出し始めの薄さ
    pub fn command(&mut self, kind: CommandKind, x: f32, mid_y: f32, selected: bool, opacity: f32) {
        let theme = self.theme;
        let size = glass::COMMAND_ICON_SIZE;
        let frame = Frame::new(x.round(), (mid_y - size / 2.0).round(), size, size);
        let (fill, color) = if selected {
            (
                theme.selection_text.with_alpha(opacity::badge::SELECTED),
                theme.selection_text,
            )
        } else {
            (theme.command_tint(), theme.selection)
        };
        let radius = if theme.is_rounded() {
            glass::COMMAND_ICON_RADIUS
        } else {
            0.0
        };
        self.draws.push(Draw::RoundRect {
            frame,
            radius,
            fill: Some(fill.faded(opacity)),
            stroke: None,
        });
        self.icon(
            Self::command_icon(kind),
            Frame::square(
                Point::new(frame.mid_x(), frame.mid_y()),
                glass::KEY_FONT_SIZE,
            ),
            color.faded(opacity),
        );
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
