#![forbid(unsafe_code)]

//! コマンドを足す・書き換えるシート(macOS の CommandsPage の CommandEditor)．Windows 11 の設定アプリの
//! ContentDialog と同じく，窓の中身を暗くして真ん中に出す．読み・名前・動作・行き先と，種類ごとの選ぶボタン，
//! 形が誤っているときの文，キャンセル・保存を置く．打つ欄は標準の EDIT(設定の窓の子)で，枠と残りは Direct2D で描く．
//! 置き場所は窓の中の座標(タイトルバーの下の DIP)

use super::ffi::Window;
use super::paint::{self, ButtonKind, Canvas, Measure, State, TextLayout, TextStyle};
use super::theme::{Color, Theme};
use crate::commands::CommandDraft;
use crate::layout::Rect;
use crate::options::COMMAND_KINDS;
use crate::strings::extras;
use tokens::opacity::settings_windows as opacity;
use tokens::size::settings::COMMAND_EDITOR_WIDTH;
use tokens::size::settings_windows as size;
use tokens::size::space;

/// シートの中の押せる部品(フォーカスの順)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SheetPart {
    Reading,
    Title,
    Kind,
    Target,
    /// 行き先のアプリかファイルを選ぶボタン(URL では出さない)
    Choose,
    Cancel,
    Save,
}

impl SheetPart {
    /// 打つ欄の番号(読み・名前・行き先)
    pub fn field(self) -> Option<usize> {
        match self {
            SheetPart::Reading => Some(0),
            SheetPart::Title => Some(1),
            SheetPart::Target => Some(2),
            _ => None,
        }
    }

    const FIELDS: [SheetPart; 3] = [SheetPart::Reading, SheetPart::Title, SheetPart::Target];
}

/// 出しているシート
pub struct CommandSheet {
    pub draft: CommandDraft,
    /// 書き換えるコマンドの表の行の番号(id が無いときに使う)
    pub index: Option<usize>,
    /// 打つ欄(読み・名前・行き先)
    pub fields: [Window; 3],
    pub focus: SheetPart,
    /// キーボードで動かしたあと(フォーカスの印を出す)
    pub focus_visible: bool,
    pub hover: Option<SheetPart>,
    pub pressed: Option<SheetPart>,
    /// 動作の一覧を開いている
    pub open: bool,
    /// 保存したがエンジンが受け付けなかった(長すぎるなど)．書き直すまで確かめる文を出す
    pub rejected: bool,
}

/// シートの置き場所(窓の中の座標)
#[derive(Debug, Clone, PartialEq)]
pub struct SheetLayout {
    pub dialog: Rect,
    pub footer: Rect,
    /// 名前(読み・名前・動作・行き先)
    pub labels: [Rect; 4],
    pub parts: Vec<(SheetPart, Rect)>,
    /// 確かめる文の行
    pub problem: Rect,
}

const LABELS: [&str; 4] = [
    extras::COMMAND_READING,
    extras::COMMAND_TITLE,
    extras::COMMAND_KIND,
    extras::COMMAND_TARGET,
];

fn button_width(label: &str, measure: &dyn Measure) -> f32 {
    (measure.width(label, TextStyle::Body) + size::BUTTON_PADDING_X * 2.0)
        .ceil()
        .max(size::BUTTON_WIDTH)
}

impl SheetLayout {
    /// 窓の大きさ(タイトルバーの下)に合わせて真ん中に置く
    pub fn new(window: (f32, f32), draft: &CommandDraft, measure: &dyn Measure) -> Self {
        let (window_width, window_height) = window;
        let padding = space::PAGE;
        let width = COMMAND_EDITOR_WIDTH.min((window_width - size::PAGE_PADDING_X * 2.0).max(0.0));
        let inner = (width - padding * 2.0).max(0.0);
        let label_width = LABELS
            .iter()
            .map(|label| measure.width(label, TextStyle::Body))
            .fold(0.0, f32::max)
            .ceil();
        let line = size::CONTROL_HEIGHT + size::CONTROL_GAP;
        let body_height = padding * 2.0 + line * 4.0 + size::NOTE_LINE_HEIGHT;
        let footer_height = size::CONTROL_HEIGHT + padding * 2.0;
        let height = body_height + footer_height;
        let x = ((window_width - width) / 2.0).max(0.0).round();
        let y = ((window_height - height) / 2.0).max(0.0).round();
        let dialog = Rect::new(x, y, width, height);
        let left = x + padding;
        let field_x = left + label_width + space::GROUP;
        let field_width = (left + inner - field_x).max(0.0);
        let row = |index: usize| y + padding + line * index as f32;
        let labels = std::array::from_fn(|index| {
            Rect::new(left, row(index), label_width, size::CONTROL_HEIGHT)
        });
        let mut parts = vec![
            (
                SheetPart::Reading,
                Rect::new(field_x, row(0), field_width, size::CONTROL_HEIGHT),
            ),
            (
                SheetPart::Title,
                Rect::new(field_x, row(1), field_width, size::CONTROL_HEIGHT),
            ),
            (
                SheetPart::Kind,
                Rect::new(field_x, row(2), field_width, size::CONTROL_HEIGHT),
            ),
        ];
        // 行き先の欄の右に，種類ごとの選ぶボタンを置く
        let choose = draft
            .choose_label()
            .map(|label| button_width(label, measure));
        let target_width = choose.map_or(field_width, |button| {
            (field_width - button - size::CONTROL_GAP).max(0.0)
        });
        parts.push((
            SheetPart::Target,
            Rect::new(field_x, row(3), target_width, size::CONTROL_HEIGHT),
        ));
        if let Some(button) = choose {
            parts.push((
                SheetPart::Choose,
                Rect::new(left + inner - button, row(3), button, size::CONTROL_HEIGHT),
            ));
        }
        let problem = Rect::new(field_x, row(4), field_width, size::NOTE_LINE_HEIGHT);
        let footer = Rect::new(x, y + body_height, width, footer_height);
        // キャンセルと保存は下の帯を同じ幅で分ける(WinUI の ContentDialog)
        let button = ((inner - size::CONTROL_GAP) / 2.0).max(0.0);
        let button_y = footer.y + padding;
        parts.push((
            SheetPart::Cancel,
            Rect::new(left, button_y, button, size::CONTROL_HEIGHT),
        ));
        parts.push((
            SheetPart::Save,
            Rect::new(
                left + inner - button,
                button_y,
                button,
                size::CONTROL_HEIGHT,
            ),
        ));
        Self {
            dialog,
            footer,
            labels,
            parts,
            problem,
        }
    }

    pub fn rect(&self, part: SheetPart) -> Option<Rect> {
        self.parts
            .iter()
            .find(|(candidate, _)| *candidate == part)
            .map(|(_, rect)| *rect)
    }

    /// (x, y) にある部品
    pub fn hit(&self, x: f32, y: f32) -> Option<SheetPart> {
        self.parts
            .iter()
            .find(|(_, rect)| x >= rect.x && x < rect.max_x() && y >= rect.y && y < rect.max_y())
            .map(|(part, _)| *part)
    }

    /// フォーカスで巡る部品
    pub fn order(&self) -> Vec<SheetPart> {
        self.parts.iter().map(|(part, _)| *part).collect()
    }
}

impl CommandSheet {
    pub fn new(draft: CommandDraft, index: Option<usize>, fields: [Window; 3]) -> Self {
        Self {
            draft,
            index,
            fields,
            focus: SheetPart::Reading,
            focus_visible: false,
            hover: None,
            pressed: None,
            open: false,
            rejected: false,
        }
    }

    /// 打つ欄の窓の部品
    pub fn part_of(&self, window: Window) -> Option<SheetPart> {
        self.fields
            .iter()
            .position(|field| *field == window)
            .map(|index| SheetPart::FIELDS[index])
    }

    /// 部品の打つ欄の窓
    pub fn window(&self, part: SheetPart) -> Option<Window> {
        part.field()
            .and_then(|index| self.fields.get(index).copied())
    }

    /// 打つ欄の文字を書きかけのコマンドに写す
    pub fn set_text(&mut self, part: SheetPart, text: String) {
        match part {
            SheetPart::Reading => self.draft.reading = text,
            SheetPart::Title => self.draft.title = text,
            SheetPart::Target => self.draft.target = text,
            _ => return,
        }
        self.rejected = false;
    }

    /// 部品を使えるか(保存は形が正しいときだけ)
    pub fn enabled(&self, part: SheetPart) -> bool {
        part != SheetPart::Save || self.draft.is_valid()
    }

    /// 部品の名前(読み上げ)
    pub fn name(&self, part: SheetPart) -> &'static str {
        match part {
            SheetPart::Reading => extras::COMMAND_READING,
            SheetPart::Title => extras::COMMAND_TITLE,
            SheetPart::Kind => extras::COMMAND_KIND,
            SheetPart::Target => extras::COMMAND_TARGET,
            SheetPart::Choose => self.draft.choose_label().unwrap_or(""),
            SheetPart::Cancel => extras::CANCEL,
            SheetPart::Save => extras::SAVE,
        }
    }

    /// 動作の選択肢の名前と選んでいる番号
    pub fn kinds(&self) -> (Vec<String>, usize) {
        (
            COMMAND_KINDS
                .iter()
                .map(|(_, label)| (*label).to_string())
                .collect(),
            self.draft.kind,
        )
    }

    /// 確かめる文を出すか
    pub fn shows_problem(&self) -> bool {
        self.rejected || self.draft.shows_problem()
    }
}

/// 描くときに窓から渡すもの
pub struct SheetFrame<'a> {
    pub theme: &'a Theme,
    /// 窓の中身の大きさ(タイトルバーの下)
    pub size: (f32, f32),
    pub focused_edit: Option<Window>,
    /// ポインターを載せている部品の動き(0〜1)
    pub hover: f32,
}

/// 窓の中身を暗くし，シートを描く
pub fn paint(
    canvas: &mut dyn Canvas,
    sheet: &CommandSheet,
    layout: &SheetLayout,
    frame: &SheetFrame,
) {
    let theme = frame.theme;
    let palette = &theme.palette;
    let (width, height) = frame.size;
    canvas.fill_rect(
        Rect::new(0.0, 0.0, width, height),
        Color::from(palette.smoke).with_alpha(opacity::SMOKE),
    );
    let radius = size::DIALOG_RADIUS;
    let dialog = layout.dialog;
    canvas.fill_round(dialog, radius, Color::from(palette.card));
    // 下の帯は窓の背景の色(WinUI の ContentDialog の CommandSpace)．角の丸みは帯の外を切って残す
    canvas.push_clip(layout.footer);
    canvas.fill_round(dialog, radius, Color::from(palette.background));
    canvas.pop_clip();
    canvas.fill_rect(
        Rect::new(dialog.x, layout.footer.y, dialog.width, 1.0),
        Color::from(palette.card_stroke),
    );
    canvas.stroke_round(dialog, radius, 1.0, Color::from(palette.flyout_stroke));
    for (label, rect) in LABELS.iter().zip(&layout.labels) {
        canvas.text(
            *rect,
            label,
            TextStyle::Body,
            Color::from(palette.text),
            TextLayout::LINE,
        );
    }
    let state = |part: SheetPart| State {
        enabled: sheet.enabled(part),
        hover: if sheet.hover == Some(part) && sheet.enabled(part) {
            frame.hover
        } else {
            0.0
        },
        pressed: sheet.pressed == Some(part),
        focus_visible: sheet.focus_visible && sheet.focus == part && part.field().is_none(),
    };
    for (part, rect) in &layout.parts {
        let part = *part;
        match part {
            SheetPart::Reading | SheetPart::Title | SheetPart::Target => {
                let focused =
                    sheet.window(part).is_some() && frame.focused_edit == sheet.window(part);
                paint::field_frame(canvas, theme, *rect, focused, state(part));
            }
            SheetPart::Kind => {
                let (items, selected) = sheet.kinds();
                let label = items.get(selected).cloned().unwrap_or_default();
                paint::dropdown(canvas, theme, *rect, &label, sheet.open, state(part));
            }
            SheetPart::Choose | SheetPart::Cancel | SheetPart::Save => {
                let kind = if part == SheetPart::Save {
                    ButtonKind::Accent
                } else {
                    ButtonKind::Standard
                };
                paint::button(canvas, theme, *rect, sheet.name(part), kind, state(part));
            }
        }
    }
    if sheet.shows_problem() {
        // 形が誤っているときの文(macOS の exclamationmark.triangle.fill と橙の文字)
        let problem = layout.problem;
        let glyph = size::CHEVRON_SIZE;
        let color = Color::from(palette.caution);
        canvas.text(
            Rect::new(problem.x, problem.y, glyph, problem.height),
            theme.glyphs.warning,
            TextStyle::IconSmall,
            color,
            TextLayout::CENTER,
        );
        let left = problem.x + glyph + space::INLINE;
        canvas.text(
            Rect::new(
                left,
                problem.y,
                (problem.max_x() - left).max(0.0),
                problem.height,
            ),
            extras::INVALID_COMMAND,
            TextStyle::Caption,
            color,
            TextLayout::LINE,
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    struct Fixed;

    impl Measure for Fixed {
        fn width(&self, text: &str, _: TextStyle) -> f32 {
            text.chars().count() as f32 * 10.0
        }
        fn wrapped_height(&self, _: &str, _: TextStyle, _: f32) -> f32 {
            20.0
        }
        fn baseline(&self, _: &str, _: TextStyle) -> f32 {
            16.0
        }
    }

    #[test]
    fn シートは窓の真ん中に置き_部品はシートに収まる() {
        let draft = CommandDraft::default();
        let layout = SheetLayout::new((900.0, 640.0), &draft, &Fixed);
        let dialog = layout.dialog;
        assert_eq!(dialog.width, COMMAND_EDITOR_WIDTH);
        assert!((dialog.x + dialog.width / 2.0 - 450.0).abs() <= 1.0);
        for (_, rect) in &layout.parts {
            assert!(rect.x >= dialog.x && rect.max_x() <= dialog.max_x());
            assert!(rect.y >= dialog.y && rect.max_y() <= dialog.max_y());
        }
        // 読み・名前・動作は同じ左端と幅
        let reading = layout.rect(SheetPart::Reading).expect("読み");
        let kind = layout.rect(SheetPart::Kind).expect("動作");
        assert_eq!((reading.x, reading.width), (kind.x, kind.width));
        // アプリを開くときは行き先の右に選ぶボタンを置く
        let target = layout.rect(SheetPart::Target).expect("行き先");
        let choose = layout.rect(SheetPart::Choose).expect("選ぶボタン");
        assert!(target.max_x() < choose.x);
        assert_eq!(choose.max_x(), reading.max_x());
        // 保存は右下
        let save = layout.rect(SheetPart::Save).expect("保存");
        assert!(save.y >= layout.footer.y);
        assert_eq!(save.max_x(), reading.max_x());
    }

    #[test]
    fn url_のコマンドには選ぶボタンを置かない() {
        let draft = CommandDraft {
            kind: 1,
            ..CommandDraft::default()
        };
        assert_eq!(draft.kind_value(), "openURL");
        let layout = SheetLayout::new((900.0, 640.0), &draft, &Fixed);
        assert_eq!(layout.rect(SheetPart::Choose), None);
        let target = layout.rect(SheetPart::Target).expect("行き先");
        let reading = layout.rect(SheetPart::Reading).expect("読み");
        assert_eq!(target.width, reading.width);
        assert!(!layout.order().contains(&SheetPart::Choose));
    }
}
