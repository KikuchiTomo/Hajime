#![forbid(unsafe_code)]

//! 項目の並び(pages::Section)を，ページの中の位置に置く．寸法は 96dpi の 1 ピクセルを 1 とし，app が DPI に合わせて拡大する．
//! Windows 11 の設定アプリと同じく，1 行ずつを角の丸い地(カード)に入れ，名前を左，部品を右に置く．
//! 部品は右の端にそろえ，既定に戻すボタンは部品の右の決まった場所に置く(macOS の ResettableRow と同じ並び)．
//! 注記は前の行のカードの中に，名前の下の説明として入れる．窓が狭く名前の欄が足りないときは，部品を名前の下に置く

use crate::pages::{Control, ListButtons, Row, Section, TryKind};
use crate::strings::{keys, more};
use tokens::size::settings as size_settings;
use tokens::size::settings_windows as size;
use tokens::size::space as size_space;

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct Rect {
    pub x: f32,
    pub y: f32,
    pub width: f32,
    pub height: f32,
}

impl Rect {
    pub fn new(x: f32, y: f32, width: f32, height: f32) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    pub fn max_x(&self) -> f32 {
        self.x + self.width
    }

    pub fn max_y(&self) -> f32 {
        self.y + self.height
    }
}

/// 測る文字の種類(本文と注記)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TextKind {
    Body,
    Caption,
}

/// 文字を測る口(app は DirectWrite で測る)
pub trait Metrics {
    /// text を width で折り返したときの行の数(1 以上)
    fn lines(&self, text: &str, kind: TextKind, width: f32) -> usize;
    /// 1 行にしたときの幅
    fn width(&self, text: &str, kind: TextKind) -> f32;
    /// 中身で高さの変わるカード(謝辞)の高さ．width はカードの幅．None なら決まった高さ
    fn height(&self, _row: &Row, _width: f32) -> Option<f32> {
        None
    }
}

/// 1 行のカードと，その中の部品の位置
#[derive(Debug, Clone, PartialEq)]
pub struct CardLayout {
    /// section.rows の中の位置
    pub row: usize,
    pub card: Rect,
    /// 名前(折り返すときは複数行の高さ)
    pub label: Rect,
    /// 説明(後ろに続く注記の行)の位置と section.rows の中の位置
    pub descriptions: Vec<(usize, Rect)>,
    pub control: Rect,
    /// 既定に戻すボタン(部品の右)
    pub reset: Rect,
    /// 部品の中のボタン・入力欄(一覧は 左の欄・右の欄・上のボタン・検索欄・絞り込み・下のボタンの順)
    pub parts: Vec<Rect>,
    /// 絵(情報のページのアイコン・テーマの見本の札・名前の横の候補の見本の札)．無ければ幅 0
    pub icon: Rect,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SectionLayout {
    pub title: Option<Rect>,
    pub cards: Vec<CardLayout>,
    pub footer: Option<Rect>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PageLayout {
    pub title: Rect,
    pub sections: Vec<SectionLayout>,
    /// ページの中身の高さ(これより窓が低ければスクロールする)
    pub height: f32,
}

/// ボタンの幅．名前を測った幅に左右の余白を足し，下限より狭くしない
pub fn button_width(label: &str, metrics: &dyn Metrics) -> f32 {
    (metrics.width(label, TextKind::Body) + size::BUTTON_PADDING_X * 2.0)
        .ceil()
        .max(size::BUTTON_WIDTH)
}

/// 名前の右に置く部品の幅(ボタンを含む)
fn trailing_width(control: &Control, metrics: &dyn Metrics) -> f32 {
    match control {
        Control::Toggle => size::TOGGLE_WIDTH,
        Control::Stepper(_) => size::STEPPER_WIDTH,
        Control::Preset => {
            size::CONTROL_WIDTH + size::CONTROL_GAP + button_width(keys::LOAD, metrics)
        }
        Control::LabeledAction(_, label) => button_width(label, metrics),
        Control::InfoAction(_, _, label) => {
            size::CONTROL_WIDTH + size::CONTROL_GAP + button_width(label, metrics)
        }
        _ => size::CONTROL_WIDTH,
    }
}

/// 行の中身の左端と幅(窓を広げても行が伸びすぎないよう，幅に上限を設ける)
pub fn content_frame(page_width: f32) -> (f32, f32) {
    let width = (page_width - size::PAGE_PADDING_X * 2.0).clamp(0.0, size::CONTENT_MAX_WIDTH);
    (size::PAGE_PADDING_X, width)
}

/// ページの部品を置く．visible は行を出すか
pub fn layout(
    sections: &[Section],
    page_width: f32,
    visible: impl Fn(&Row) -> bool,
    metrics: &dyn Metrics,
) -> PageLayout {
    let (left, width) = content_frame(page_width);
    // 既定に戻せる行があるページは，どの行も既定に戻すボタンの場所を空け，部品の右の端をそろえる
    let reserve = sections
        .iter()
        .flat_map(|section| &section.rows)
        .any(Row::has_value);
    let mut y = size::PAGE_PADDING_TOP;
    let title = Rect::new(left, y, width, size::TITLE_HEIGHT);
    y += size::TITLE_HEIGHT;
    let mut result = Vec::new();
    let mut shown = 0;
    for section in sections {
        // 行がひとつも出ないまとまりは，見出しも間も置かない(カスタムテーマを選んでいないときの色・形など)
        if !section.rows.iter().any(&visible) {
            result.push(SectionLayout {
                title: None,
                cards: Vec::new(),
                footer: None,
            });
            continue;
        }
        if shown > 0 {
            y += size::SECTION_GAP - size::CARD_GAP;
        }
        shown += 1;
        let title = section.title.map(|_| {
            let rect = Rect::new(left, y, width, size::SECTION_TITLE_HEIGHT);
            y += size::SECTION_TITLE_HEIGHT;
            rect
        });
        let mut cards: Vec<CardLayout> = Vec::new();
        let rows = &section.rows;
        let mut index = 0;
        while index < rows.len() {
            let row = &rows[index];
            // 後ろに続く注記はこの行の説明にする
            let mut next = index + 1;
            let mut notes = Vec::new();
            while next < rows.len() && rows[next].control == Control::Note {
                if visible(&rows[next]) {
                    notes.push((next, rows[next].title));
                }
                next += 1;
            }
            if visible(row) && row.control != Control::Note {
                let frame = Frame {
                    x: left,
                    y,
                    width,
                    reserve,
                };
                let card = place(index, row, &notes, frame, metrics);
                y = card.card.max_y() + size::CARD_GAP;
                cards.push(card);
            }
            index = next;
        }
        let footer = section.footer.map(|text| {
            let longest = std::iter::once(text)
                .chain(section.footer_variants.iter().map(|(_, text)| *text))
                .map(|text| metrics.lines(text, TextKind::Caption, width))
                .max()
                .unwrap_or(1);
            y += size::FOOTER_GAP - size::CARD_GAP;
            let height = longest as f32 * size::NOTE_LINE_HEIGHT;
            let rect = Rect::new(left, y, width, height);
            y += height + size::CARD_GAP;
            rect
        });
        result.push(SectionLayout {
            title,
            cards,
            footer,
        });
    }
    PageLayout {
        title,
        sections: result,
        height: y + size::SECTION_GAP,
    }
}

/// カードを置く場所(上端と，左端と幅)と，既定に戻すボタンの場所を空けるか
#[derive(Debug, Clone, Copy)]
struct Frame {
    x: f32,
    y: f32,
    width: f32,
    reserve: bool,
}

impl Frame {
    fn inner_left(&self) -> f32 {
        self.x + size::CARD_PADDING_X
    }

    fn inner_width(&self) -> f32 {
        (self.width - size::CARD_PADDING_X * 2.0).max(0.0)
    }

    fn inner_right(&self) -> f32 {
        self.inner_left() + self.inner_width()
    }

    fn card(&self, height: f32) -> Rect {
        Rect::new(self.x, self.y, self.width, height)
    }
}

fn empty(card: Rect, row: usize) -> CardLayout {
    CardLayout {
        row,
        card,
        label: Rect::new(card.x, card.y, 0.0, 0.0),
        descriptions: Vec::new(),
        control: Rect::new(card.x, card.y, 0.0, 0.0),
        reset: Rect::new(card.x, card.y, 0.0, 0.0),
        parts: Vec::new(),
        icon: Rect::new(card.x, card.y, 0.0, 0.0),
    }
}

fn place(
    position: usize,
    row: &Row,
    notes: &[(usize, &str)],
    frame: Frame,
    metrics: &dyn Metrics,
) -> CardLayout {
    let control = &row.control;
    if let Some(buttons) = control.list_buttons() {
        let fields = control.list_spec().map_or(0, |spec| spec.fields.len());
        return place_inputs(position, fields, buttons, frame, size::LIST_HEIGHT, metrics);
    }
    match control {
        // 英語と日本語の試す欄は下に単語へ足すボタンを置く．変換マクロの結果は並べると長くなるので行を多く取る
        Control::Preview(TryKind::Language) => place_inputs(
            position,
            2,
            PREVIEW_BUTTONS,
            frame,
            size::BODY_LINE_HEIGHT * size::PREVIEW_LINES,
            metrics,
        ),
        Control::Preview(TryKind::Macros) => place_inputs(
            position,
            2,
            NO_BUTTONS,
            frame,
            size::BODY_LINE_HEIGHT * size::MACRO_PREVIEW_LINES,
            metrics,
        ),
        Control::KeymapReport | Control::ThemeReport => place_inputs(
            position,
            0,
            NO_BUTTONS,
            frame,
            size::BODY_LINE_HEIGHT * size::REPORT_LINES,
            metrics,
        ),
        Control::ThemePreview => place_inputs(
            position,
            0,
            NO_BUTTONS,
            frame,
            size::PREVIEW_HEIGHT,
            metrics,
        ),
        Control::PalettePreview => place_inputs(
            position,
            0,
            NO_BUTTONS,
            frame,
            size::PALETTE_PREVIEW_HEIGHT,
            metrics,
        ),
        Control::EmojiPreview => place_inputs(
            position,
            0,
            NO_BUTTONS,
            frame,
            size::EMOJI_PREVIEW_HEIGHT,
            metrics,
        ),
        // 謝辞は中身(名前・出どころ・ライセンスの全文)を画面の側で測って置く．部品の欄はカードの中の全体
        Control::Acknowledgement(_) => {
            let height = metrics.height(row, frame.width).unwrap_or(size::ROW_HEIGHT);
            let mut card = empty(frame.card(height), position);
            card.control = Rect::new(frame.inner_left(), frame.y, frame.inner_width(), height);
            card
        }
        Control::Segmented(choices) => place_segments(position, choices, frame, metrics),
        Control::Action(_) => place_action(position, row.title, notes, frame, metrics),
        Control::Buttons(buttons) => {
            let labels: Vec<&str> = buttons.iter().map(|(label, _)| *label).collect();
            place_buttons(position, &labels, frame, metrics)
        }
        Control::Version => place_about(position, row.title, frame, metrics),
        Control::ThemeOption(_) => place_option(position, frame),
        _ => place_labeled(position, row, notes, frame, metrics),
    }
}

/// 名前(と説明)を左，部品を右に置く行
fn place_labeled(
    position: usize,
    row: &Row,
    notes: &[(usize, &str)],
    frame: Frame,
    metrics: &dyn Metrics,
) -> CardLayout {
    let left = frame.inner_left();
    let right = frame.inner_right();
    let reset_space = if frame.reserve {
        size::RESET_SIZE + size::CONTROL_GAP
    } else {
        0.0
    };
    let trailing = trailing_width(&row.control, metrics);
    let beside = right - reset_space - trailing - size::CONTROL_GAP - left;
    // 名前の欄が狭すぎるときは，部品を名前の下に置く(Windows 11 の設定アプリの狭い窓と同じ)
    let stacked = beside < size::LABEL_MIN_WIDTH;
    let label_width = if stacked { frame.inner_width() } else { beside };
    let label_lines = if row.title.is_empty() {
        0
    } else {
        metrics.lines(row.title, TextKind::Body, label_width)
    };
    // 名前の横の候補の見本の札．名前の 1 行目の横に収まらなければ，名前の下の行に置く
    let example = row
        .example
        .map(|example| (example_width(example, metrics).min(label_width), example));
    let example_beside = example.is_some_and(|(width, _)| {
        label_lines == 1
            && metrics.width(row.title, TextKind::Body) + size_space::SM + width <= label_width
    });
    let example_below = match example {
        Some(_) if !example_beside => size_space::XS + example_height(),
        _ => 0.0,
    };
    let label_height = label_lines as f32 * size::BODY_LINE_HEIGHT;
    let note_heights: Vec<f32> = notes
        .iter()
        .map(|(_, text)| {
            metrics.lines(text, TextKind::Caption, label_width) as f32 * size::NOTE_LINE_HEIGHT
        })
        .collect();
    let text_height = label_height + example_below + note_heights.iter().sum::<f32>();
    let (height, text_top, control_top, trailing_x) = if stacked {
        let height =
            size::CARD_PADDING_Y * 2.0 + text_height + size::CONTROL_GAP + size::CONTROL_HEIGHT;
        let control_top = frame.y + size::CARD_PADDING_Y + text_height + size::CONTROL_GAP;
        (height, frame.y + size::CARD_PADDING_Y, control_top, left)
    } else {
        let height = size::ROW_HEIGHT
            .max(text_height + size::CARD_PADDING_Y * 2.0)
            .max(size::CONTROL_HEIGHT + size::CARD_PADDING_Y * 2.0);
        // 説明が長くてカードが 2 行分より高いときは，部品をカードの真ん中でなく名前の行の高さに置く
        // (ユーザー辞書の書き方の表のように説明が長いと，真ん中の部品がどの行のものか分からない)
        let control_top = if height > size::ROW_HEIGHT * 2.0 {
            frame.y + (size::ROW_HEIGHT - size::CONTROL_HEIGHT) / 2.0
        } else {
            frame.y + (height - size::CONTROL_HEIGHT) / 2.0
        };
        (
            height,
            frame.y + (height - text_height) / 2.0,
            control_top,
            right - reset_space - trailing,
        )
    };
    // 狭い窓で部品の幅が足りなければ縮める
    let trailing = trailing.min((frame.inner_width() - reset_space).max(0.0));
    let label = Rect::new(left, text_top, label_width.max(0.0), label_height);
    // 札は名前の 1 行目と同じ大きさの文字を，行の真ん中にそろえて書く(ベースラインがそろう)
    let icon = match example {
        Some((width, _)) if example_beside => Rect::new(
            left + metrics.width(row.title, TextKind::Body) + size_space::SM,
            label.y + (size::BODY_LINE_HEIGHT - example_height()) / 2.0,
            width,
            example_height(),
        ),
        Some((width, _)) => Rect::new(
            left,
            label.max_y() + size_space::XS,
            width,
            example_height(),
        ),
        None => Rect::new(left, frame.y, 0.0, 0.0),
    };
    let mut y = label.max_y() + example_below;
    let descriptions = notes
        .iter()
        .zip(&note_heights)
        .map(|((index, _), height)| {
            let rect = Rect::new(left, y, label_width.max(0.0), *height);
            y += height;
            (*index, rect)
        })
        .collect();
    let reset = Rect::new(
        trailing_x + trailing + size::CONTROL_GAP,
        control_top + (size::CONTROL_HEIGHT - size::RESET_SIZE) / 2.0,
        size::RESET_SIZE,
        size::RESET_SIZE,
    );
    // ボタンを右に添える部品は，ボタンを右の端に置き，残りを部品の欄にする
    let button = match &row.control {
        Control::Preset => Some(button_width(keys::LOAD, metrics)),
        Control::InfoAction(_, _, label) => Some(button_width(label, metrics)),
        _ => None,
    };
    let (control, parts) = match button {
        Some(button) => {
            let button = button.min(trailing);
            let control_width = (trailing - button - size::CONTROL_GAP).max(0.0);
            (
                Rect::new(trailing_x, control_top, control_width, size::CONTROL_HEIGHT),
                vec![Rect::new(
                    trailing_x + trailing - button,
                    control_top,
                    button,
                    size::CONTROL_HEIGHT,
                )],
            )
        }
        None => (
            Rect::new(trailing_x, control_top, trailing, size::CONTROL_HEIGHT),
            Vec::new(),
        ),
    };
    CardLayout {
        row: position,
        card: frame.card(height),
        label,
        descriptions,
        control,
        reset,
        parts,
        icon,
    }
}

/// 候補の見本の札の高さ(名前と同じ大きさの文字の 1 行と上下の余白)
pub fn example_height() -> f32 {
    size::BODY_LINE_HEIGHT + size_settings::PREVIEW_CHIP_PADDING_Y * 2.0
}

/// 候補の見本の札の中身(読み・矢印・候補)の並び．札の左の端からの位置と幅を返す(描く側と同じ並べ方)
pub fn example_parts(example: (&str, &str), width: impl Fn(&str) -> f32) -> [(f32, f32); 3] {
    let (reading, candidate) = example;
    let mut x = size_settings::PREVIEW_CHIP_PADDING_X;
    let mut parts = [(0.0, 0.0); 3];
    for (index, text) in [reading, EXAMPLE_ARROW, candidate].into_iter().enumerate() {
        let part = width(text);
        parts[index] = (x, part);
        x += part + size_space::XS;
    }
    parts
}

/// 読みと候補のあいだの矢印
pub const EXAMPLE_ARROW: &str = "→";

fn example_width(example: (&str, &str), metrics: &dyn Metrics) -> f32 {
    let [.., (x, width)] = example_parts(example, |text| metrics.width(text, TextKind::Body));
    (x + width + size_settings::PREVIEW_CHIP_PADDING_X).ceil()
}

/// 操作のボタンの行．名前を持たず，カードの左にボタンを置く．説明はボタンの下に置く
fn place_action(
    position: usize,
    title: &str,
    notes: &[(usize, &str)],
    frame: Frame,
    metrics: &dyn Metrics,
) -> CardLayout {
    let left = frame.inner_left();
    let inner = frame.inner_width();
    let button = button_width(title, metrics).min(inner);
    let mut card = empty(frame.card(size::ROW_HEIGHT), position);
    if notes.is_empty() {
        card.control = Rect::new(
            left,
            frame.y + (size::ROW_HEIGHT - size::CONTROL_HEIGHT) / 2.0,
            button,
            size::CONTROL_HEIGHT,
        );
        return card;
    }
    card.control = Rect::new(
        left,
        frame.y + size::CARD_PADDING_Y,
        button,
        size::CONTROL_HEIGHT,
    );
    let mut y = card.control.max_y() + size::CONTROL_GAP;
    for (index, text) in notes {
        let height = metrics.lines(text, TextKind::Caption, inner) as f32 * size::NOTE_LINE_HEIGHT;
        card.descriptions
            .push((*index, Rect::new(left, y, inner, height)));
        y += height;
    }
    card.card.height = y + size::CARD_PADDING_Y - frame.y;
    card
}

/// 幅 widths のものを inner の幅に左から並べ，収まらなければ折り返す．行ごとの (左端からの位置, 幅) を返す
fn flow(widths: &[f32], inner: f32) -> Vec<Vec<(f32, f32)>> {
    let mut lines: Vec<Vec<(f32, f32)>> = Vec::new();
    let mut used = 0.0;
    for &width in widths {
        match lines.last_mut() {
            Some(line) if used + size::CONTROL_GAP + width <= inner => {
                line.push((used + size::CONTROL_GAP, width));
                used += size::CONTROL_GAP + width;
            }
            _ => {
                let width = width.min(inner);
                lines.push(vec![(0.0, width)]);
                used = width;
            }
        }
    }
    lines
}

/// 1 つのカードに並べる操作のボタン
fn place_buttons(
    position: usize,
    labels: &[&str],
    frame: Frame,
    metrics: &dyn Metrics,
) -> CardLayout {
    let left = frame.inner_left();
    let widths: Vec<f32> = labels
        .iter()
        .map(|label| button_width(label, metrics))
        .collect();
    let lines = flow(&widths, frame.inner_width());
    let count = lines.len().max(1) as f32;
    let block = count * size::CONTROL_HEIGHT + (count - 1.0) * size::CONTROL_GAP;
    let height = size::ROW_HEIGHT.max(block + size::CARD_PADDING_Y * 2.0);
    let mut card = empty(frame.card(height), position);
    let mut top = frame.y + (height - block) / 2.0;
    for line in lines {
        for (offset, width) in line {
            card.parts
                .push(Rect::new(left + offset, top, width, size::CONTROL_HEIGHT));
        }
        top += size::CONTROL_HEIGHT + size::CONTROL_GAP;
    }
    card.control = Rect::new(left, frame.y, frame.inner_width(), height);
    card
}

/// 一覧を切り替える部品．カードに入れず，真ん中に置く
fn place_segments(
    position: usize,
    choices: &[crate::options::Choice],
    frame: Frame,
    metrics: &dyn Metrics,
) -> CardLayout {
    let widths: Vec<f32> = choices
        .iter()
        .map(|(_, label)| {
            (metrics.width(label, TextKind::Body) + size::BUTTON_PADDING_X * 2.0)
                .ceil()
                .max(size::SEGMENT_MIN_WIDTH)
        })
        .collect();
    let total: f32 = widths.iter().sum();
    let mut card = empty(frame.card(size::CONTROL_HEIGHT), position);
    let mut x = frame.x + ((frame.width - total) / 2.0).max(0.0);
    card.control = Rect::new(x, frame.y, total.min(frame.width), size::CONTROL_HEIGHT);
    for width in widths {
        card.parts
            .push(Rect::new(x, frame.y, width, size::CONTROL_HEIGHT));
        x += width;
    }
    card
}

/// 情報のページの見出し(アイコン・製品名・バージョン・更新を確かめるボタン．macOS の AboutPage)
fn place_about(position: usize, title: &str, frame: Frame, metrics: &dyn Metrics) -> CardLayout {
    let left = frame.inner_left();
    let right = frame.inner_right();
    let button = button_width(more::CHECK_FOR_UPDATES, metrics).min(frame.inner_width());
    let icon_size = size::ABOUT_ICON;
    let text_left = left + icon_size + size::CARD_PADDING_X;
    let title_height = size::TITLE_HEIGHT - size::BODY_LINE_HEIGHT;
    let text_height = title_height + size::BODY_LINE_HEIGHT;
    let beside = right - button - size::CONTROL_GAP - text_left;
    // 狭い窓では，ボタンを名前の下に置く
    let stacked = beside < size::LABEL_MIN_WIDTH
        || metrics.width(title, TextKind::Body) > beside.max(0.0) * 2.0;
    let header = icon_size + size::CARD_PADDING_Y * 2.0;
    let height = if stacked {
        header + size::CONTROL_HEIGHT + size::CARD_PADDING_Y
    } else {
        header
    };
    let mut card = empty(frame.card(height), position);
    let center = frame.y + header / 2.0;
    card.icon = Rect::new(left, center - icon_size / 2.0, icon_size, icon_size);
    let text_width = if stacked { right - text_left } else { beside };
    card.label = Rect::new(
        text_left,
        center - text_height / 2.0,
        text_width.max(0.0),
        title_height,
    );
    card.control = Rect::new(
        text_left,
        card.label.max_y(),
        text_width.max(0.0),
        size::BODY_LINE_HEIGHT,
    );
    let button_rect = if stacked {
        Rect::new(left, frame.y + header, button, size::CONTROL_HEIGHT)
    } else {
        Rect::new(
            right - button,
            center - size::CONTROL_HEIGHT / 2.0,
            button,
            size::CONTROL_HEIGHT,
        )
    };
    card.parts.push(button_rect);
    card
}

/// 既成のテーマの 1 つ．選ぶ印・見本の札・名前を左から並べ，カードのどこを押しても選ぶ
fn place_option(position: usize, frame: Frame) -> CardLayout {
    let left = frame.inner_left();
    let height = size::ROW_HEIGHT;
    let mut card = empty(frame.card(height), position);
    let center = frame.y + height / 2.0;
    let radio = Rect::new(
        left,
        center - size::RADIO_SIZE / 2.0,
        size::RADIO_SIZE,
        size::RADIO_SIZE,
    );
    card.icon = Rect::new(
        radio.max_x() + size::NAV_ICON_GAP,
        center - size::THEME_SWATCH_HEIGHT / 2.0,
        size::THEME_SWATCH_WIDTH,
        size::THEME_SWATCH_HEIGHT,
    );
    let label_left = card.icon.max_x() + size::NAV_ICON_GAP;
    card.label = Rect::new(
        label_left,
        center - size::BODY_LINE_HEIGHT / 2.0,
        (frame.inner_right() - label_left).max(0.0),
        size::BODY_LINE_HEIGHT,
    );
    card.parts.push(radio);
    card.control = card.card;
    card
}

/// 試す欄の下のボタン(試した語をいつも英語・いつも日本語にする単語に足す．macOS は結果の語のメニュー)
pub const PREVIEW_BUTTONS: ListButtons = ListButtons {
    top: &[],
    bottom: &[
        crate::strings::windows::ADD_TO_ENGLISH,
        crate::strings::windows::ADD_TO_JAPANESE,
    ],
    search: false,
    filter: false,
    files: None,
};

const NO_BUTTONS: ListButtons = ListButtons {
    top: &[],
    bottom: &[],
    search: false,
    filter: false,
    files: None,
};

/// 入力欄の並ぶカード(一覧・試す欄)．上に入力欄とボタン，下に表か結果を置き，表の下の帯に検索欄・絞り込み・ボタンを左から，
/// ファイルを読み込む・書き出すボタンを右に寄せて並べる．parts は入力欄・上のボタン・検索欄・絞り込み・下のボタン・ファイルのボタンの順
fn place_inputs(
    position: usize,
    fields: usize,
    buttons: ListButtons,
    frame: Frame,
    below: f32,
    metrics: &dyn Metrics,
) -> CardLayout {
    let x = frame.inner_left();
    let top = frame.y + size::CARD_PADDING_Y;
    let inner = frame.inner_width();
    let widths: Vec<f32> = buttons
        .top
        .iter()
        .map(|label| button_width(label, metrics))
        .collect();
    let buttons_width: f32 = widths.iter().map(|width| width + size::CONTROL_GAP).sum();
    let count = fields.max(1) as f32;
    let field_width =
        ((inner - buttons_width - size::CONTROL_GAP * (count - 1.0)) / count).max(0.0);
    let mut parts = Vec::new();
    let mut cursor = x;
    for _ in 0..fields {
        parts.push(Rect::new(cursor, top, field_width, size::CONTROL_HEIGHT));
        cursor += field_width + size::CONTROL_GAP;
    }
    for width in widths {
        parts.push(Rect::new(cursor, top, width, size::CONTROL_HEIGHT));
        cursor += width + size::CONTROL_GAP;
    }
    let list_top = if fields + buttons.top.len() == 0 {
        top
    } else {
        top + size::CONTROL_HEIGHT + size::CONTROL_GAP
    };
    // 表の下の帯
    let leading: Vec<f32> = buttons
        .search
        .then_some(size::CONTROL_WIDTH)
        .into_iter()
        .chain(buttons.filter.then_some(size::STEPPER_WIDTH))
        .chain(
            buttons
                .bottom
                .iter()
                .map(|label| button_width(label, metrics)),
        )
        .collect();
    let trailing: Vec<f32> = buttons
        .files
        .map(|files| {
            files
                .labels()
                .iter()
                .map(|label| button_width(label, metrics))
                .collect()
        })
        .unwrap_or_default();
    let trailing_total: f32 = trailing.iter().sum::<f32>()
        + size::CONTROL_GAP * (trailing.len().saturating_sub(1)) as f32;
    let mut lines = flow(&leading, inner);
    let line_top = list_top + below + size::CONTROL_GAP;
    let mut placed_trailing = Vec::new();
    if !trailing.is_empty() {
        // ファイルのボタンは右に寄せる．最後の行に収まらなければ次の行に置く
        let used = lines
            .last()
            .and_then(|line| line.last())
            .map_or(0.0, |(offset, width)| offset + width);
        let fits = lines.is_empty() || used + size::CONTROL_GAP + trailing_total <= inner;
        let line = if fits && !lines.is_empty() {
            lines.len() - 1
        } else {
            lines.push(Vec::new());
            lines.len() - 1
        };
        let mut offset = (inner - trailing_total).max(0.0);
        for width in &trailing {
            placed_trailing.push((line, offset, *width));
            offset += width + size::CONTROL_GAP;
        }
    }
    let line_height = size::CONTROL_HEIGHT + size::CONTROL_GAP;
    for (index, line) in lines.iter().enumerate() {
        for (offset, width) in line {
            parts.push(Rect::new(
                x + offset,
                line_top + index as f32 * line_height,
                *width,
                size::CONTROL_HEIGHT,
            ));
        }
    }
    for (line, offset, width) in placed_trailing {
        parts.push(Rect::new(
            x + offset,
            line_top + line as f32 * line_height,
            width,
            size::CONTROL_HEIGHT,
        ));
    }
    let bottom = if lines.is_empty() {
        list_top + below
    } else {
        line_top + lines.len() as f32 * line_height - size::CONTROL_GAP
    };
    let height = bottom + size::CARD_PADDING_Y - frame.y;
    let mut card = empty(frame.card(height), position);
    card.control = Rect::new(x, list_top, inner, below);
    card.parts = parts;
    card
}

/// 試しに測る(テスト)．全角を 1，半角を 0.5 文字とみなし，本文の大きさを掛ける
#[cfg(test)]
pub struct Estimate;

#[cfg(test)]
impl Metrics for Estimate {
    fn lines(&self, text: &str, kind: TextKind, width: f32) -> usize {
        if width <= 0.0 {
            return 1;
        }
        ((self.width(text, kind) / width).ceil() as usize).max(1)
    }

    fn width(&self, text: &str, kind: TextKind) -> f32 {
        let font = match kind {
            TextKind::Body => size::BODY_FONT_SIZE,
            TextKind::Caption => size::CAPTION_FONT_SIZE,
        };
        text.chars()
            .map(|character| if character.is_ascii() { 0.5 } else { 1.0 })
            .sum::<f32>()
            * font
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pages::{sections, Page};

    fn all(page: Page, width: f32) -> PageLayout {
        layout(&sections(page).unwrap(), width, |_| true, &Estimate)
    }

    #[test]
    fn 行を上から順に重ならないよう置く() {
        let layout = all(Page::Input, 800.0);
        let mut last = layout.title.max_y();
        for section in &layout.sections {
            if let Some(title) = section.title {
                assert!(title.y >= last);
                last = title.max_y();
            }
            for card in &section.cards {
                assert!(card.card.y >= last);
                assert!(card.control.x > card.label.x);
                assert!(card.label.max_x() <= card.control.x);
                assert!(card.reset.x >= card.control.max_x());
                last = card.card.max_y();
            }
        }
        assert!(layout.height > last);
    }

    #[test]
    fn 部品と既定に戻すボタンは右の端にそろえる() {
        for page in [Page::Input, Page::Conversion, Page::Palette] {
            let layout = all(page, 900.0);
            let cards: Vec<&CardLayout> = layout
                .sections
                .iter()
                .flat_map(|section| &section.cards)
                .filter(|card| card.reset.width > 0.0 && card.label.width > 0.0)
                .collect();
            let right = cards[0].reset.max_x();
            for card in &cards {
                assert!(
                    (card.reset.max_x() - right).abs() < 0.01,
                    "{page:?} {card:?}"
                );
                assert!((card.control.max_x() + size::CONTROL_GAP - card.reset.x).abs() < 0.01);
            }
        }
    }

    #[test]
    fn 狭い窓では部品を名前の下に置き名前を消さない() {
        let layout = all(Page::Input, 360.0);
        for card in layout.sections.iter().flat_map(|section| &section.cards) {
            assert!(card.label.width > 0.0, "{card:?}");
            assert!(card.control.y >= card.label.max_y());
            assert!(card.control.max_y() <= card.card.max_y());
            assert!(card.control.max_x() <= card.card.max_x());
        }
    }

    /// 変換のページの「絵文字」の 2 つの切り替え(名前の横に候補の見本の札を添える行)
    fn example_cards(width: f32) -> Vec<CardLayout> {
        let page = sections(Page::Conversion).unwrap();
        let layout = layout(&page, width, |_| true, &Estimate);
        page.iter()
            .zip(&layout.sections)
            .flat_map(|(section, placed)| {
                placed
                    .cards
                    .iter()
                    .filter(|card| section.rows[card.row].example.is_some())
                    .cloned()
                    .collect::<Vec<_>>()
            })
            .collect()
    }

    #[test]
    fn 候補の見本の札は名前の横に置き_名前と同じ行の真ん中にそろえる() {
        let cards = example_cards(900.0);
        assert_eq!(cards.len(), 2);
        for card in &cards {
            assert!(card.icon.width > 0.0);
            assert!(card.icon.x > card.label.x);
            assert!(card.icon.max_x() <= card.label.max_x());
            let center = card.label.y + size::BODY_LINE_HEIGHT / 2.0;
            assert!((card.icon.y + card.icon.height / 2.0 - center).abs() < 0.01);
            assert!(card.icon.max_y() <= card.card.max_y());
        }
    }

    #[test]
    fn 名前の横に収まらない窓では候補の見本の札を名前の下に置く() {
        let cards = example_cards(260.0);
        assert_eq!(cards.len(), 2);
        for card in cards {
            assert!(card.icon.width > 0.0);
            assert_eq!(card.icon.x, card.label.x);
            assert!(card.icon.y >= card.label.max_y());
            assert!(card.icon.max_y() <= card.card.max_y() - size::CARD_PADDING_Y + 0.01);
            assert!(card.control.y >= card.icon.max_y() || card.control.x > card.icon.max_x());
        }
    }

    #[test]
    fn 説明の長い行は部品を名前の高さに置く() {
        let page = sections(Page::Dictionary).unwrap();
        let layout = layout(&page, 800.0, |_| true, &Estimate);
        // 単語に書ける書き方の表を説明に持つ行(ユーザー辞書の 2 つ目の区切り)
        let card = &layout.sections[1].cards[0];
        assert!(card.descriptions.len() > 5);
        assert!(card.card.height > size::ROW_HEIGHT * 2.0);
        assert!(card.control.max_y() <= card.card.y + size::ROW_HEIGHT);
    }

    #[test]
    fn 注記は前の行の説明にする() {
        let page = sections(Page::Input).unwrap();
        let layout = layout(&page, 800.0, |_| true, &Estimate);
        // キー配列の行(4 番目の行)に注記(5 番目)が付く
        let card = layout.sections[0]
            .cards
            .iter()
            .find(|card| card.row == 4)
            .unwrap();
        assert_eq!(card.descriptions.len(), 1);
        assert_eq!(card.descriptions[0].0, 5);
        let (_, description) = card.descriptions[0];
        assert!(description.y >= card.label.max_y());
        assert!(description.max_y() <= card.card.max_y());
        assert!(description.width > 0.0);
    }

    #[test]
    fn 出さない行は場所を取らない() {
        let page = sections(Page::Input).unwrap();
        let all = layout(&page, 800.0, |_| true, &Estimate);
        let some = layout(
            &page,
            800.0,
            |row| row.control != Control::Toggle,
            &Estimate,
        );
        assert!(some.height < all.height);
    }

    #[test]
    fn 操作のボタンはカードの左に置き名前の幅に合わせる() {
        let layout = all(Page::Conversion, 800.0);
        let card = layout.sections.last().unwrap().cards.last().unwrap();
        assert_eq!(card.control.x, card.card.x + size::CARD_PADDING_X);
        assert!(card.control.width >= Estimate.width("学習結果を消去", TextKind::Body));
    }

    #[test]
    fn 一覧は入力欄とボタンを表の上に並べ_検索欄とファイルのボタンを表の下に置く() {
        let layout = all(Page::Correction, 800.0);
        // 0 は修正の対象，1 は手のずれ
        let card = &layout.sections[2].cards[0];
        // 入力欄 2 つ・追加・削除・検索欄・インポート・エクスポート
        assert_eq!(card.parts.len(), 7);
        for pair in card.parts[..4].windows(2) {
            assert!(pair[0].max_x() <= pair[1].x);
        }
        assert!(card.parts[3].max_x() <= card.card.max_x());
        assert!(card.control.y >= card.parts[0].max_y());
        let search = card.parts[4];
        assert!(search.y >= card.control.max_y());
        // ファイルのボタンは右の端
        let export = card.parts[6];
        assert!((export.max_x() - (card.card.max_x() - size::CARD_PADDING_X)).abs() < 0.01);
        assert!(export.max_y() <= card.card.max_y());
    }

    #[test]
    fn 辞書の一覧は表の下にボタンを折り返して並べる() {
        let page = sections(Page::Dictionary).unwrap();
        for width in [800.0, 400.0] {
            let layout = layout(&page, width, |_| true, &Estimate);
            let card = &layout.sections[3].cards[0];
            // 入力欄 4 つ・更新・表の下の 6 つ
            assert_eq!(card.parts.len(), 11);
            for part in &card.parts {
                assert!(part.max_x() <= card.card.max_x() - size::CARD_PADDING_X + 0.01);
                assert!(part.max_y() <= card.card.max_y());
            }
            for part in &card.parts[5..] {
                assert!(part.y >= card.control.max_y());
            }
        }
        assert!(button_width("有効・無効の切り替え", &Estimate) > size::BUTTON_WIDTH);
        assert_eq!(button_width("更新", &Estimate), size::BUTTON_WIDTH);
    }

    #[test]
    fn 行がひとつも出ないまとまりは見出しも置かない() {
        let page = sections(Page::Appearance).unwrap();
        // カスタムテーマを選んでいない(色・形の行を出さない)
        let hidden = layout(&page, 800.0, |row| row.visible.is_none(), &Estimate);
        let shown = layout(&page, 800.0, |_| true, &Estimate);
        let titles = |layout: &PageLayout| {
            layout
                .sections
                .iter()
                .filter(|section| section.title.is_some())
                .count()
        };
        assert!(titles(&hidden) < titles(&shown));
        assert_eq!(hidden.sections.len(), page.len());
        assert!(hidden.height < shown.height);
        // 見本の欄は見本の高さを取る
        assert!(shown.sections[0].cards[0].control.height >= size::PREVIEW_HEIGHT);
    }

    #[test]
    fn 入力欄の並ぶカードは中身がカードに収まる() {
        for page in [
            Page::Language,
            Page::Dictionary,
            Page::Symbols,
            Page::About,
            Page::Palette,
        ] {
            let layout = all(page, 800.0);
            for card in layout.sections.iter().flat_map(|section| &section.cards) {
                assert!(card.control.max_y() <= card.card.max_y(), "{card:?}");
                assert!(card.control.y >= card.card.y);
                for part in &card.parts {
                    assert!(part.max_y() <= card.card.max_y(), "{card:?}");
                }
            }
        }
    }

    #[test]
    fn 注記はカードから離して置く() {
        let layout = all(Page::Conversion, 800.0);
        for section in &layout.sections {
            if let (Some(footer), Some(card)) = (section.footer, section.cards.last()) {
                assert!(footer.y - card.card.max_y() >= size::FOOTER_GAP - 0.01);
            }
        }
    }

    #[test]
    fn 広い窓でも行の幅は上限まで() {
        let layout = all(Page::Input, 3000.0);
        assert_eq!(
            layout.sections[0].cards[0].card.width,
            size::CONTENT_MAX_WIDTH
        );
    }
}
