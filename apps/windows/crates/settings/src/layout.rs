#![forbid(unsafe_code)]

//! 項目の並び(pages::Section)を，ページの中の位置に置く．寸法は 96dpi の 1 ピクセルを 1 とし，app が DPI に合わせて拡大する．
//! Windows 11 の設定アプリと同じく，1 行ずつを角の丸い背景(カード)に入れ，名前を左，部品を右に置く．
//! 部品は右の端にそろえ，既定に戻すボタンは部品の右の決まった場所に置く(macOS の ResettableRow と同じ並び)．
//! 注記は前の行のカードの中に，名前の下の説明として入れる．窓が狭く名前の欄が足りないときは，部品を名前の下に置く

use crate::pages::{Control, ListButtons, Row, Section, TryKind};
use crate::strings::more;
use tokens::size::settings as size_settings;
use tokens::size::settings_windows as size;
use tokens::size::space;

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
    /// 中身で高さの変わるカード(謝辞)の高さ．width はカードの幅．None なら決まった高さ．
    /// 見本の行(ThemePreview など)は見本を描く高さで，width は見本を置ける幅(余白を除く)
    fn height(&self, _row: &Row, _width: f32) -> Option<f32> {
        None
    }
    /// 一覧のカードの中で，そのときの状態で変わるもの(書き方のボタン・結果の行・書き方のチップの欄)．width はカードの幅
    fn list_state(&self, _row: &Row, _width: f32) -> ListState {
        ListState::default()
    }
}

/// 一覧のカードの中で，画面の状態で出し入れするもの(macOS の RuleListEditor の TemplateAssist と showingResult)
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct ListState {
    /// 書き方を入れる欄のすぐ右に「{ }」のボタンを置く(書き方を値にしない設定では置かない)
    pub template_button: bool,
    /// 入れたときの結果の行を置く(結果のあるときだけ)
    pub result: bool,
    /// 書き方のチップの欄の高さ．閉じていれば None
    pub panel: Option<f32>,
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
    /// 絵(情報のページのアイコン・テーマの見本・名前の横の候補の見本)．無ければ幅 0
    pub icon: Rect,
    /// 一覧の入れたときの結果の行(押せない．ListState::result)
    pub result: Option<Rect>,
    /// 一覧の書き方のボタン(ListState::template_button)
    pub template_button: Option<Rect>,
    /// 一覧の書き方のチップの欄(ListState::panel)
    pub template_panel: Option<Rect>,
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

/// 選択肢のいちばん長い名前が収まるドロップダウンの幅(名前・山形の印と，その左右の余白．paint::dropdown と同じ並び)
fn dropdown_width(choices: &[crate::options::Choice], metrics: &dyn Metrics) -> f32 {
    let widest = choices
        .iter()
        .map(|(_, label)| metrics.width(label, TextKind::Body))
        .fold(0.0, f32::max);
    (widest + size::FIELD_PADDING_X * 2.0 + size::FIELD_PADDING_X + size::CHEVRON_SIZE).ceil()
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
        Control::Preset => size::CONTROL_WIDTH,
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
    shows_example: impl Fn(&Row) -> bool,
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
    // 候補の見本は，続けて見える範囲(見出しのあるまとまりと，そのすぐ下に続く見出しの無いまとまり)の中で
    // いちばん長い見本付きの名前のあとから書き出し，左の端をそろえる．見出しで区切った別のまとまりとはそろえない
    let mut example_titles = vec![0.0f32; sections.len()];
    let mut start = 0;
    for end in 1..=sections.len() {
        if end < sections.len() && sections[end].title.is_none() {
            continue;
        }
        let widest = sections[start..end]
            .iter()
            .flat_map(|section| &section.rows)
            .filter(|row| row.example.is_some() && shows_example(row))
            .map(|row| metrics.width(row.title, TextKind::Body))
            .fold(0.0, f32::max);
        example_titles[start..end].fill(widest);
        start = end;
    }
    for (section, example_title) in sections.iter().zip(example_titles) {
        // 行がひとつも出ないまとまりは，見出しも間も置かない(カスタムテーマを選んでいないときの色・形など)
        if !section.rows.iter().any(&visible) {
            result.push(SectionLayout {
                title: None,
                cards: Vec::new(),
                footer: None,
            });
            continue;
        }
        // まとまりの行は 1 枚のカードに区切り線で並べる(macOS の Form の grouped)．行と行のあいだは空けない
        if shown > 0 {
            y += size::SECTION_GAP;
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
                    example_title,
                    shows_example: shows_example(row),
                };
                let card = place(index, row, &notes, frame, metrics);
                y = card.card.max_y();
                // 辞書の一覧は取り込むボタンをカードの下に置く(macOS の Section の footer)
                if let Control::Dictionaries(_) = row.control {
                    y = card.parts.iter().map(Rect::max_y).fold(y, f32::max);
                }
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
            y += size::FOOTER_GAP;
            let height = longest as f32 * size::NOTE_LINE_HEIGHT;
            let rect = Rect::new(left, y, width, height);
            y += height;
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
    /// ページの中で候補の見本を添える行の，いちばん長い名前の幅(タグの左の端をそろえる)
    example_title: f32,
    /// この行の見本を出すか(条件付きの見本は条件を満たすときだけ)
    shows_example: bool,
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
        result: None,
        template_button: None,
        template_panel: None,
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
        let spec_fields = control.list_spec().map_or(&[][..], |spec| spec.fields);
        let fields = buttons.top_fields(spec_fields.len());
        // 表の下の帯に置く欄(選ぶ欄)は，いちばん長い選択肢が収まる幅にする
        let bottom_fields: Vec<f32> = spec_fields[fields..buttons.input_fields(spec_fields.len())]
            .iter()
            .map(|field| dropdown_width(field.choices.unwrap_or(&[]), metrics))
            .collect();
        // キー設定は行が多いので表を高くする
        let height = match control {
            Control::List(spec, _) if spec.path == "keymap" => size::KEYMAP_LIST_HEIGHT,
            _ => size::LIST_HEIGHT,
        };
        let state = metrics.list_state(row, frame.width);
        return place_list(
            position,
            (fields, &bottom_fields),
            buttons,
            state,
            frame,
            height,
            metrics,
        );
    }
    match control {
        // 英語と日本語の試す欄は下に単語へ足すボタンを置く．変換マクロの結果は並べると長くなるので行を多く取る
        // 英語と日本語の試す欄は，macOS と同じく打つ欄を縦に 2 つ並べ，下に結果のタグ(2 行のタグ)を置く
        Control::Preview(TryKind::Language) => {
            let chip = size::BODY_LINE_HEIGHT
                + size::NOTE_LINE_HEIGHT
                + tokens::size::settings::PREVIEW_CHIP_PADDING_Y * 2.0;
            // 結果のタグを押して一覧に足す(macOS の WordLanguagePage)ので，下にボタンは置かない
            place_stacked_inputs(
                position,
                2,
                NO_BUTTONS,
                frame,
                chip * size::PREVIEW_LINES + tokens::size::settings::PREVIEW_BUTTON_GAP,
                metrics,
            )
        }
        // 変換マクロの試す語と読みは欄だけ．結果は下の節の PreviewChips に並べる
        Control::Preview(TryKind::Macros) => place_inputs(
            position,
            2,
            NO_BUTTONS,
            ListState::default(),
            frame,
            0.0,
            metrics,
        ),
        // 結果のタグの行の数に合わせた高さ(画面の側で測る．測れなければ決まった行数)
        Control::PreviewChips(_) => place_inputs(
            position,
            0,
            NO_BUTTONS,
            ListState::default(),
            frame,
            metrics
                .height(row, frame.width)
                .unwrap_or(size::BODY_LINE_HEIGHT * size::MACRO_PREVIEW_LINES),
            metrics,
        ),
        Control::KeymapReport => place_inputs(
            position,
            0,
            NO_BUTTONS,
            ListState::default(),
            frame,
            size::BODY_LINE_HEIGHT * size::REPORT_LINES,
            metrics,
        ),
        Control::ThemePreview | Control::PalettePreview | Control::EmojiPreview => {
            place_preview(position, row, frame, metrics)
        }
        // 謝辞・読みにくい組み合わせの知らせは中身を画面の側で測って置く．部品の欄はカードの中の全体
        Control::Acknowledgement(_) | Control::ThemeIssue(_) => {
            let height = metrics.height(row, frame.width).unwrap_or(size::ROW_HEIGHT);
            let mut card = empty(frame.card(height), position);
            card.control = Rect::new(frame.inner_left(), frame.y, frame.inner_width(), height);
            card
        }
        Control::Dictionaries(list) => {
            place_dictionaries(position, row, *list, notes, frame, metrics)
        }
        Control::Segmented(choices) => place_segments(position, choices, frame, metrics),
        Control::Action(_) => place_action(position, row.title, notes, frame, metrics),
        Control::Buttons(buttons) => {
            let labels: Vec<&str> = buttons.iter().map(|(label, _)| *label).collect();
            place_buttons(position, &labels, frame, metrics)
        }
        Control::Version => place_about(position, row.title, frame, metrics),
        Control::ThemeOption(_) => place_option(position, frame),
        Control::CustomTheme(_) => place_custom_theme(position, frame),
        // 打つ欄は部品の欄に置く(一覧の入力欄と同じく parts の先頭)
        Control::TextField => {
            let mut card = place_labeled(position, row, notes, frame, metrics);
            card.parts.push(card.control);
            card
        }
        _ => place_labeled(position, row, notes, frame, metrics),
    }
}

/// 辞書の一覧(macOS の ImportedDictionariesView・AssociationSection)．カードは辞書の行の高さ(画面の側で測る)にし，
/// 取り込むボタンをカードの下に注記と同じ間を空けて置く(parts の 0 番目)．部品の欄はカードの中の全体．
/// 続く注記(一覧についての 1 行．「上の辞書ほど優先」)は，一覧のすぐ下，取り込むボタンの上に置く
fn place_dictionaries(
    position: usize,
    row: &Row,
    list: crate::pages::DictionaryList,
    notes: &[(usize, &str)],
    frame: Frame,
    metrics: &dyn Metrics,
) -> CardLayout {
    let height = metrics.height(row, frame.width).unwrap_or(size::ROW_HEIGHT);
    let mut card = empty(frame.card(height), position);
    card.control = Rect::new(frame.inner_left(), frame.y, frame.inner_width(), height);
    let mut y = frame.y + height;
    card.descriptions = notes
        .iter()
        .map(|(index, text)| {
            let lines = metrics.lines(text, TextKind::Caption, frame.width);
            let rect = Rect::new(
                frame.x,
                y + size::FOOTER_GAP,
                frame.width,
                lines as f32 * size::NOTE_LINE_HEIGHT,
            );
            y = rect.max_y();
            (*index, rect)
        })
        .collect();
    let button = button_width(list.import_label(), metrics).min(frame.width);
    card.parts = vec![Rect::new(
        frame.x,
        y + size::FOOTER_GAP,
        button,
        size::CONTROL_HEIGHT,
    )];
    card
}

/// 見本の行(macOS の AppearancePage の ThemePreview)．見本は描いた大きさのまま置き，まわりに見本の余白をとる．
/// 欄の幅が描いた幅より狭ければ見本ごと同じ比で縮める(高さも縮む)．描いた高さは画面の側で測る(Metrics::height)
fn place_preview(position: usize, row: &Row, frame: Frame, metrics: &dyn Metrics) -> CardLayout {
    // 絵文字の見本は設定の項目の名前と同じ左の端から，ほかの行と同じカードの余白で置く(macOS の EmojiSection)．
    // 外観とパレットの見本は欄の真ん中に，まわりに見本の余白をとって置く
    let (x, width, padding_y) = if row.control == Control::EmojiPreview {
        (
            frame.inner_left(),
            frame.inner_width(),
            size::CARD_PADDING_Y,
        )
    } else {
        let padding = size_settings::PREVIEW_PADDING;
        (
            frame.x + padding,
            (frame.width - padding * 2.0).max(0.0),
            padding,
        )
    };
    let height = metrics
        .height(row, width)
        .unwrap_or(size::ROW_HEIGHT - padding_y * 2.0)
        .max(0.0);
    let mut card = empty(frame.card(height + padding_y * 2.0), position);
    card.control = Rect::new(x, frame.y + padding_y, width, height);
    card
}

/// 見本を幅 width に収めたときの高さ．natural は描いた大きさ(幅・高さ)．広ければ描いた高さのまま，
/// 狭ければ幅に合わせて同じ比で縮める(macOS の ScaledPreview.size)
pub fn preview_height(natural: (f32, f32), width: f32) -> f32 {
    let (natural_width, natural_height) = natural;
    if natural_width <= 0.0 {
        return natural_height.max(0.0);
    }
    let shown = natural_width.min(width.max(0.0));
    (natural_height * shown / natural_width).ceil()
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
    // 名前の横の候補の見本．まとまりの中でいちばん長い名前のあとにそろえて置き，
    // 名前の 1 行目の横に収まらなければ，名前の下の行に置く
    let example = row
        .example
        .filter(|_| frame.shows_example)
        .map(|example| (example_width(example, metrics).min(label_width), example));
    let example_x = left + frame.example_title + space::GROUP;
    let example_beside = example
        .is_some_and(|(width, _)| label_lines == 1 && example_x + width <= left + label_width);
    let example_below = match example {
        Some(_) if !example_beside => space::STACK + example_height(),
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
        // 部品はカードの右の端にそろえる．既定に戻すボタンは部品の左に置く(macOS の SettingsRows は
        // 変えた行だけ部品の左にボタンを出す．空けておく場所は名前の欄から取る)
        (
            height,
            frame.y + (height - text_height) / 2.0,
            control_top,
            right - trailing,
        )
    };
    // 狭い窓で部品の幅が足りなければ縮める
    let trailing = trailing.min((frame.inner_width() - reset_space).max(0.0));
    let label = Rect::new(left, text_top, label_width.max(0.0), label_height);
    // タグは名前の 1 行目と同じ大きさの文字を，行の真ん中にそろえて書く(ベースラインがそろう)
    let icon = match example {
        Some((width, _)) if example_beside => Rect::new(
            example_x,
            label.y + (size::BODY_LINE_HEIGHT - example_height()) / 2.0,
            width,
            example_height(),
        ),
        Some((width, _)) => Rect::new(left, label.max_y() + space::STACK, width, example_height()),
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
    let reset_x = if stacked {
        // 名前の下に部品を置く狭い窓では，部品の右に置く
        trailing_x + trailing + size::CONTROL_GAP
    } else {
        trailing_x - size::CONTROL_GAP - size::RESET_SIZE
    };
    let reset = Rect::new(
        reset_x,
        control_top + (size::CONTROL_HEIGHT - size::RESET_SIZE) / 2.0,
        size::RESET_SIZE,
        size::RESET_SIZE,
    );
    // ボタンを右に添える部品は，ボタンを右の端に置き，残りを部品の欄にする
    let button = match &row.control {
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
        result: None,
        template_button: None,
        template_panel: None,
    }
}

/// 候補の見本の高さ(名前と同じ大きさの文字の 1 行と上下の余白)
pub fn example_height() -> f32 {
    size::BODY_LINE_HEIGHT + size_settings::PREVIEW_CHIP_PADDING_Y * 2.0
}

/// 候補の見本の中身(読み・矢印・候補)の並び．タグの左の端からの位置と幅を返す(描く側と同じ並べ方)
pub fn example_parts(example: (&str, &str), width: impl Fn(&str) -> f32) -> [(f32, f32); 3] {
    let (reading, candidate) = example;
    let mut x = size_settings::PREVIEW_CHIP_PADDING_X;
    let mut parts = [(0.0, 0.0); 3];
    for (index, text) in [reading, EXAMPLE_ARROW, candidate].into_iter().enumerate() {
        let part = width(text);
        parts[index] = (x, part);
        x += part + space::INLINE;
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

/// 既成のテーマの 1 つ．選ぶ印・見本・名前を左から並べ，カードのどこを押しても選ぶ
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

/// カスタムテーマの行の右の絵のボタンの数(編集・複製・削除．app::page の ThemeAction::ROW と同じ並び)
const CUSTOM_THEME_BUTTONS: usize = 3;

/// カスタムテーマの行(macOS の CustomThemeRow)．既成のテーマの行と同じく選ぶ印・見本の色・名前を並べ，
/// 右の端に編集・複製・削除の絵のボタンを置き，名前とボタンのあいだに読みにくい印の場所をとる．
/// control は選ぶ印，parts はボタン(左から)と印の場所
fn place_custom_theme(position: usize, frame: Frame) -> CardLayout {
    let mut card = place_option(position, frame);
    let center = frame.y + size::ROW_HEIGHT / 2.0;
    let button = size::RESET_SIZE;
    let mut right = frame.inner_right();
    let mut buttons = Vec::new();
    for _ in 0..CUSTOM_THEME_BUTTONS {
        right -= button;
        buttons.push(Rect::new(right, center - button / 2.0, button, button));
        right -= space::INLINE;
    }
    buttons.reverse();
    let icon = size::ICON_FONT_SIZE;
    let mark = Rect::new(right - icon, center - icon / 2.0, icon, icon);
    card.control = card.parts.first().copied().unwrap_or(card.control);
    card.label.width = (mark.x - size::CONTROL_GAP - card.label.x).max(0.0);
    card.parts = buttons;
    card.parts.push(mark);
    card
}

const NO_BUTTONS: ListButtons = ListButtons {
    top: &[],
    bottom: &[],
    search: false,
    filter: false,
    files: None,
    arrow: None,
    field_widths: &[],
    toolbar: false,
    trailing_bottom: 0,
    note_line: false,
    bottom_fields: 0,
    sheet: false,
    move_icons: false,
    message_line: false,
    result: false,
    template_field: None,
    caption: None,
};

/// 入力欄の並ぶカード(一覧・試す欄)．macOS の RuleListEditor と同じく，上に入力欄とボタン(追加・キャンセル)，
/// 下に表か結果を置き，表の下の帯は左にボタン(削除など)，右に絞り込み・検索欄・ファイルを読み込む・書き出すボタンを並べる．
/// 帯が 1 行に収まらなければ，右の組だけを次の行に右寄せで置く．
/// parts は入力欄・上のボタン・検索欄・絞り込み・下のボタン・ファイルのボタンの順
fn place_inputs(
    position: usize,
    fields: usize,
    buttons: ListButtons,
    state: ListState,
    frame: Frame,
    below: f32,
    metrics: &dyn Metrics,
) -> CardLayout {
    place_list(
        position,
        (fields, &[]),
        buttons,
        state,
        frame,
        below,
        metrics,
    )
}

/// place_inputs と同じ．fields の 2 つ目は表の下の帯の左に置く欄の幅(下のボタンの前に並べる．
/// parts では下のボタンの前に入る)
fn place_list(
    position: usize,
    (fields, bottom_fields): (usize, &[f32]),
    buttons: ListButtons,
    state: ListState,
    frame: Frame,
    below: f32,
    metrics: &dyn Metrics,
) -> CardLayout {
    // 山形の絵のボタン(優先度を上げる・下げる)は決まった幅にする
    let button = |label: &str| {
        if buttons.is_icon(label) {
            size::ICON_BUTTON_WIDTH
        } else {
            button_width(label, metrics)
        }
    };
    let x = frame.inner_left();
    let card_top = frame.y + size::CARD_PADDING_Y;
    let inner = frame.inner_width();
    // 上の帯(キー設定): 検索欄が残りの幅に広がり，右に「キーで検索」のボタンと絞り込みを置く(macOS の KeymapPage)
    let mut key_search = None;
    let (toolbar_search, toolbar_filter, top) = if buttons.toolbar {
        let filter = buttons.filter.then(|| {
            Rect::new(
                x + inner - size::STEPPER_WIDTH,
                card_top,
                size::STEPPER_WIDTH,
                size::CONTROL_HEIGHT,
            )
        });
        let filter_left = filter.map_or(x + inner, |rect| rect.x - size::CONTROL_GAP);
        let key_width = button_width(crate::strings::keys::SEARCH_BY_KEY, metrics);
        let key = Rect::new(
            filter_left - key_width,
            card_top,
            key_width,
            size::CONTROL_HEIGHT,
        );
        key_search = Some(key);
        let search_right = key.x - size::CONTROL_GAP;
        let search = buttons.search.then(|| {
            Rect::new(
                x,
                card_top,
                (search_right - x).max(0.0),
                size::CONTROL_HEIGHT,
            )
        });
        (
            search,
            filter,
            card_top + size::CONTROL_HEIGHT + size::CONTROL_GAP,
        )
    } else {
        (None, None, card_top)
    };
    let widths: Vec<f32> = buttons
        .top
        .iter()
        .map(|label| button_width(label, metrics))
        .collect();
    let buttons_width: f32 = widths.iter().map(|width| width + size::CONTROL_GAP).sum();
    // 添え書きの欄(最後の欄)を次の行に置くときは，1 行目に並べる欄から外す
    let note_line = buttons.note_line && fields >= 2;
    let all_fields = fields;
    let fields = if note_line { fields - 1 } else { fields };
    // 決まった幅の欄(キー設定の状態とキー)を除いた欄で残りを分ける
    let fixed: Vec<f32> = buttons.field_widths.iter().copied().take(fields).collect();
    let fixed_total: f32 = fixed.iter().sum();
    let count = (fields - fixed.len()).max(1) as f32;
    // 矢印を置くときは先頭の 2 つの欄のあいだを広げる
    let arrow = buttons.arrow.filter(|index| index + 1 < fields);
    let arrow_extra = if arrow.is_some() {
        size::LIST_ARROW_WIDTH
    } else {
        0.0
    };
    let gaps = size::CONTROL_GAP * (fields.max(1) - 1) as f32;
    // 書き方のボタンは書き方を入れる欄のすぐ右に，欄と同じ高さの正方形で置く(macOS の RuleListEditor の templateButton)
    let template_after = buttons
        .template_field
        .filter(|index| state.template_button && *index < fields);
    let template_extra = if template_after.is_some() {
        size::CONTROL_HEIGHT + size::CONTROL_GAP
    } else {
        0.0
    };
    // 欄の前に置く名前(判別ルールの「直前」)は，名前の幅と欄までの間を空ける
    let caption = buttons
        .caption
        .filter(|(index, _)| *index < fields)
        .map(|(index, text)| (index, metrics.width(text, TextKind::Body).ceil()));
    let caption_extra = caption.map_or(0.0, |(_, width)| width + size::CONTROL_GAP);
    let field_width = ((inner
        - buttons_width
        - gaps
        - arrow_extra
        - template_extra
        - caption_extra
        - fixed_total)
        / count)
        .max(0.0);
    let mut parts = Vec::new();
    let mut template_button = None;
    let mut cursor = x;
    for index in 0..fields {
        if caption.is_some_and(|(at, _)| at == index) {
            cursor += caption_extra;
        }
        let width = fixed.get(index).copied().unwrap_or(field_width);
        parts.push(Rect::new(cursor, top, width, size::CONTROL_HEIGHT));
        cursor += width + size::CONTROL_GAP;
        if template_after == Some(index) {
            template_button = Some(Rect::new(
                cursor,
                top,
                size::CONTROL_HEIGHT,
                size::CONTROL_HEIGHT,
            ));
            cursor += template_extra;
        }
        if arrow == Some(index) {
            cursor += arrow_extra;
        }
    }
    for width in widths {
        parts.push(Rect::new(cursor, top, width, size::CONTROL_HEIGHT));
        cursor += width + size::CONTROL_GAP;
    }
    // 入力欄の並びの上の帯は 1 行目の欄・ボタンのあとに置く(parts の順: 入力欄・上のボタン)．
    // 添え書きの欄は 2 行目に幅いっぱいで置き，1 行目の欄のすぐあとの parts に入れる(入力欄の番号の順)
    let mut list_top = if all_fields + buttons.top.len() == 0 {
        top
    } else {
        top + size::CONTROL_HEIGHT + size::CONTROL_GAP
    };
    // 入れたときの結果の行は，結果を求める欄(単語・形)の左端から，入力欄のすぐ下に置く(結果のあるときだけ)
    let result = (buttons.result && state.result).then(|| {
        let field = parts
            .get(1)
            .filter(|_| fields >= 2)
            .or(parts.first())
            .copied();
        let left = field.map_or(x, |field| field.x);
        let rect = Rect::new(
            left,
            list_top,
            (x + inner - left).max(0.0),
            size::BODY_LINE_HEIGHT,
        );
        list_top += size::BODY_LINE_HEIGHT + size::CONTROL_GAP;
        rect
    });
    // 書き方のチップの欄は欄(と結果)のすぐ下に幅いっぱいで置き，上下を section 空けて入力の行とは別のまとまりに見せる
    let template_panel = state.panel.map(|height| {
        let panel_top = list_top - size::CONTROL_GAP + tokens::size::space::SECTION;
        list_top = panel_top + height + tokens::size::space::SECTION;
        Rect::new(x, panel_top, inner, height)
    });
    if note_line {
        let note = Rect::new(x, list_top, inner, size::CONTROL_HEIGHT);
        parts.insert(fields, note);
        list_top += size::CONTROL_HEIGHT + size::CONTROL_GAP;
    }
    // 打った行の確かめの文の行(空のときも場所を取り，文が出ても表が動かないようにする)
    if buttons.message_line {
        list_top += size::NOTE_LINE_HEIGHT;
    }
    // 表の下の帯: 左の組(下のボタン)と右の組(右に寄せる下のボタン・絞り込み・検索欄・ファイルのボタン)
    let split = buttons.bottom.len().saturating_sub(buttons.trailing_bottom);
    let leading: Vec<f32> = bottom_fields
        .iter()
        .copied()
        .chain(buttons.bottom[..split].iter().map(|label| button(label)))
        .collect();
    let trailing_buttons: Vec<f32> = buttons.bottom[split..]
        .iter()
        .map(|label| button(label))
        .collect();
    let bar_search = buttons.search && !buttons.toolbar;
    let bar_filter = buttons.filter && !buttons.toolbar;
    let search_width = tokens::size::settings::RULE_SEARCH_WIDTH;
    let file_widths: Vec<f32> = buttons
        .files
        .map(|files| {
            files
                .labels()
                .iter()
                .map(|label| button_width(label, metrics))
                .collect()
        })
        .unwrap_or_default();
    let trailing: Vec<f32> = trailing_buttons
        .iter()
        .copied()
        .chain(bar_filter.then_some(size::STEPPER_WIDTH))
        .chain(bar_search.then_some(search_width))
        .chain(file_widths.iter().copied())
        .collect();
    let total = |widths: &[f32]| -> f32 {
        widths.iter().sum::<f32>() + size::CONTROL_GAP * widths.len().saturating_sub(1) as f32
    };
    let leading_lines = flow(&leading, inner);
    let trailing_total = total(&trailing);
    let leading_end = leading_lines
        .last()
        .and_then(|line| line.last())
        .map_or(0.0, |(offset, width)| offset + width);
    let line_top = list_top + below + size::CONTROL_GAP;
    let line_height = size::CONTROL_HEIGHT + size::CONTROL_GAP;
    // 右の組を置く行(左の組の最後の行に収まればその行，収まらなければ次の行)
    let trailing_line = if trailing.is_empty() {
        None
    } else if leading_lines.is_empty() || leading_end + size::CONTROL_GAP + trailing_total <= inner
    {
        Some(leading_lines.len().saturating_sub(1))
    } else {
        Some(leading_lines.len())
    };
    let mut trailing_rects = Vec::new();
    if let Some(line) = trailing_line {
        let mut offset = (inner - trailing_total).max(0.0);
        for width in &trailing {
            trailing_rects.push(Rect::new(
                x + offset,
                line_top + line as f32 * line_height,
                *width,
                size::CONTROL_HEIGHT,
            ));
            offset += width + size::CONTROL_GAP;
        }
    }
    let leading_rects: Vec<Rect> = leading_lines
        .iter()
        .enumerate()
        .flat_map(|(index, line)| {
            line.iter().map(move |(offset, width)| {
                Rect::new(
                    x + offset,
                    line_top + index as f32 * line_height,
                    *width,
                    size::CONTROL_HEIGHT,
                )
            })
        })
        .collect();
    // parts の順に入れる: 検索欄・絞り込み・下の帯の欄・下のボタン(左の組・右の組)・ファイルのボタン
    let mut trailing_iter = trailing_rects.into_iter();
    let right_buttons: Vec<Rect> = trailing_iter
        .by_ref()
        .take(trailing_buttons.len())
        .collect();
    let filter_rect = if buttons.toolbar {
        toolbar_filter
    } else {
        bar_filter.then(|| trailing_iter.next()).flatten()
    };
    let search_rect = if buttons.toolbar {
        toolbar_search
    } else {
        bar_search.then(|| trailing_iter.next()).flatten()
    };
    parts.extend(search_rect);
    parts.extend(filter_rect);
    parts.extend(leading_rects);
    parts.extend(right_buttons);
    parts.extend(trailing_iter);
    // 「キーで検索」のボタンは最後に入れる(part_rect は最後の部品を引く)
    parts.extend(key_search);
    let lines = leading_lines
        .len()
        .max(trailing_line.map_or(0, |line| line + 1));
    // 下に何も置かない(欄だけの)カードは，最後の欄のすぐ下で終える
    let bottom = if lines == 0 && below <= 0.0 {
        list_top - size::CONTROL_GAP
    } else if lines == 0 {
        list_top + below
    } else {
        line_top + lines as f32 * line_height - size::CONTROL_GAP
    };
    let height = bottom + size::CARD_PADDING_Y - frame.y;
    let mut card = empty(frame.card(height), position);
    card.control = Rect::new(x, list_top, inner, below);
    card.parts = parts;
    card.result = result;
    card.template_button = template_button;
    card.template_panel = template_panel;
    card
}

/// 打つ欄を縦に並べる入力欄のカード(英語と日本語の試す欄)．入力欄は 1 つずつ幅いっぱいの行に置き，
/// その下に結果と下のボタンを place_inputs と同じに置く
fn place_stacked_inputs(
    position: usize,
    fields: usize,
    buttons: ListButtons,
    frame: Frame,
    below: f32,
    metrics: &dyn Metrics,
) -> CardLayout {
    let extra = (size::CONTROL_HEIGHT + size::CONTROL_GAP) * fields as f32;
    // 欄を置かずに place_inputs で下のボタンを置き(欄の分を結果の上に足しておく)，あとで欄を縦に置く
    let mut card = place_inputs(
        position,
        0,
        buttons,
        ListState::default(),
        frame,
        below + extra,
        metrics,
    );
    let x = frame.inner_left();
    let top = frame.y + size::CARD_PADDING_Y;
    let fields_rects: Vec<Rect> = (0..fields)
        .map(|index| {
            Rect::new(
                x,
                top + index as f32 * (size::CONTROL_HEIGHT + size::CONTROL_GAP),
                frame.inner_width(),
                size::CONTROL_HEIGHT,
            )
        })
        .collect();
    let list_top = top + fields as f32 * (size::CONTROL_HEIGHT + size::CONTROL_GAP);
    card.control = Rect::new(x, list_top, frame.inner_width(), below);
    let mut parts = fields_rects;
    parts.extend(card.parts);
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
    use crate::pages::{sections, Page, Section};
    use crate::strings::extras;
    use crate::strings::settings as settings_strings;

    fn all(page: Page, width: f32) -> PageLayout {
        layout(
            &sections(page).unwrap(),
            width,
            |_| true,
            |_| true,
            &Estimate,
        )
    }

    #[test]
    fn 判別ルールの足す行は直前の欄の前に名前を置く間を空ける() {
        let page = sections(Page::Language).unwrap();
        let layout = layout(&page, 900.0, |_| true, |_| true, &Estimate);
        let card = page
            .iter()
            .zip(&layout.sections)
            .flat_map(|(section, placed)| {
                placed
                    .cards
                    .iter()
                    .filter(|card| {
                        matches!(&section.rows[card.row].control,
                            crate::pages::Control::List(spec, _) if spec.path == "wordLanguage.rules")
                    })
                    .cloned()
                    .collect::<Vec<_>>()
            })
            .next()
            .unwrap();
        let caption = Estimate
            .width(
                crate::strings::features::LANGUAGE_RULE_CONTEXT,
                TextKind::Body,
            )
            .ceil();
        // 単語の欄・(間)・「直前」・(間)・直前の欄(macOS の WordLanguagePage の HStack と同じ並び)
        let between = card.parts[1].x - card.parts[0].max_x();
        assert!((between - (size::CONTROL_GAP + caption + size::CONTROL_GAP)).abs() < 0.01);
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
                // 既定に戻すボタンは部品の左で，名前に重ならない
                assert!(card.reset.max_x() <= card.control.x);
                assert!(card.label.max_x() <= card.reset.x);
                last = card.card.max_y();
            }
        }
        assert!(layout.height > last);
    }

    #[test]
    fn 部品は右の端にそろえ_既定に戻すボタンは部品の左に置く() {
        for page in [Page::Input, Page::Conversion, Page::Palette] {
            let layout = all(page, 900.0);
            let cards: Vec<&CardLayout> = layout
                .sections
                .iter()
                .flat_map(|section| &section.cards)
                .filter(|card| card.reset.width > 0.0 && card.label.width > 0.0)
                .collect();
            for card in &cards {
                // 部品はカードの右の余白の内側にそろえる(macOS と同じく右の端を空けない)
                assert!(
                    (card.control.max_x() - (card.card.max_x() - size::CARD_PADDING_X)).abs()
                        < 0.01,
                    "{page:?} {card:?}"
                );
                assert!((card.reset.max_x() + size::CONTROL_GAP - card.control.x).abs() < 0.01);
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

    /// 変換のページの「絵文字」の 2 つの切り替え(名前の横に候補の見本を添える行)
    fn example_cards(width: f32) -> Vec<CardLayout> {
        let page = sections(Page::Conversion).unwrap();
        let layout = layout(&page, width, |_| true, |_| true, &Estimate);
        page.iter()
            .zip(&layout.sections)
            .flat_map(|(section, placed)| {
                placed
                    .cards
                    .iter()
                    .filter(|card| {
                        let row = &section.rows[card.row];
                        row.example.is_some() && row.path.starts_with("emoji")
                    })
                    .cloned()
                    .collect::<Vec<_>>()
            })
            .collect()
    }

    #[test]
    fn 候補の見本は名前の横に置き_名前と同じ行の真ん中にそろえる() {
        let cards = example_cards(900.0);
        assert_eq!(cards.len(), 2);
        // 2 つのタグの左の端は，同じまとまりの中でいちばん長い見本付きの名前のあとにそろえる(見出しで区切った「候補」の見本とはそろえない)
        assert_eq!(cards[0].icon.x, cards[1].icon.x);
        let longest = [
            settings_strings::EMOJI_CONVERSION,
            settings_strings::EMOJI_WORD_CONVERSION,
        ]
        .iter()
        .map(|title| Estimate.width(title, TextKind::Body))
        .fold(0.0, f32::max);
        assert_eq!(cards[0].icon.x, cards[0].label.x + longest + space::GROUP);
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
    fn 絵文字の見本は項目の名前と同じ左の端から置く() {
        let page = sections(Page::Conversion).unwrap();
        let layout = layout(&page, 900.0, |_| true, |_| true, &Estimate);
        let cards: Vec<(&Row, &CardLayout)> = page
            .iter()
            .zip(&layout.sections)
            .flat_map(|(section, placed)| {
                placed
                    .cards
                    .iter()
                    .map(move |card| (&section.rows[card.row], card))
            })
            .collect();
        let (_, preview) = cards
            .iter()
            .find(|(row, _)| row.control == Control::EmojiPreview)
            .unwrap();
        let (_, names) = cards
            .iter()
            .find(|(row, _)| row.path == "showsEmojiNames")
            .unwrap();
        assert_eq!(preview.control.x, names.label.x);
        assert_eq!(preview.control.y - preview.card.y, size::CARD_PADDING_Y);
    }

    #[test]
    fn 補正のページの見本のタグはまとまりをまたいで左の端をそろえる() {
        let page = sections(Page::Correction).unwrap();
        let layout = layout(&page, 900.0, |_| true, |_| true, &Estimate);
        let xs: Vec<f32> = page
            .iter()
            .zip(&layout.sections)
            .flat_map(|(section, placed)| {
                placed
                    .cards
                    .iter()
                    .filter(|card| section.rows[card.row].example.is_some())
                    .map(|card| card.icon.x)
                    .collect::<Vec<_>>()
            })
            .collect();
        assert_eq!(xs.len(), 3);
        assert!(xs.iter().all(|x| *x == xs[0]));
    }

    #[test]
    fn 見出しで区切ったまとまりの見本とは左の端をそろえない() {
        let page = sections(Page::Conversion).unwrap();
        let layout = layout(&page, 900.0, |_| true, |_| true, &Estimate);
        let cards: Vec<(&str, CardLayout)> = page
            .iter()
            .zip(&layout.sections)
            .flat_map(|(section, placed)| {
                placed
                    .cards
                    .iter()
                    .filter(|card| {
                        matches!(
                            section.rows[card.row].path,
                            "listSegmentAlternatives" | "emojiConversion"
                        )
                    })
                    .map(|card| (section.rows[card.row].path, card.clone()))
                    .collect::<Vec<_>>()
            })
            .collect();
        assert_eq!(cards.len(), 2);
        // 「候補」のまとまりの見本は 1 つだけなので，名前のすぐ後ろに置く(「絵文字」の見本の列にはそろえない)
        let (_, segment) = cards
            .iter()
            .find(|(path, _)| *path == "listSegmentAlternatives")
            .unwrap();
        let title = Estimate.width(
            crate::strings::more::LIST_SEGMENT_ALTERNATIVES,
            TextKind::Body,
        );
        assert_eq!(segment.icon.x, segment.label.x + title + space::GROUP);
    }

    #[test]
    fn 入力方式の見本は英字入力自動のときだけ名前のすぐ後ろに置く() {
        let page = sections(Page::Input).unwrap();
        let card = |shows: bool| {
            let layout = layout(&page, 900.0, |_| true, |_| shows, &Estimate);
            layout.sections[0]
                .cards
                .iter()
                .find(|card| page[0].rows[card.row].path == "inputStyle")
                .cloned()
                .unwrap()
        };
        let shown = card(true);
        assert!(shown.icon.width > 0.0);
        assert!(shown.icon.x > shown.label.x);
        assert_eq!(
            shown.icon.y + shown.icon.height / 2.0,
            shown.label.y + size::BODY_LINE_HEIGHT / 2.0
        );
        assert_eq!(card(false).icon.width, 0.0);
    }

    #[test]
    fn 連想の辞書は一覧_上の辞書ほど優先_取り込むボタン_見本の順に置く() {
        let page = sections(Page::Conversion).unwrap();
        let layout = layout(&page, 800.0, |_| true, |_| true, &Estimate);
        let (section, placed) = page
            .iter()
            .zip(&layout.sections)
            .find(|(section, _)| {
                section.rows.iter().any(|row| {
                    row.control == Control::Dictionaries(crate::pages::DictionaryList::Association)
                })
            })
            .unwrap();
        let card = &placed.cards[0];
        assert_eq!(card.descriptions.len(), 1);
        let (note, rect) = card.descriptions[0];
        assert_eq!(section.rows[note].title, crate::strings::association::NOTE);
        assert!(rect.y >= card.card.max_y());
        let button = card.parts[0];
        assert!(button.y >= rect.max_y());
        assert!(placed.footer.unwrap().y >= button.max_y());
    }

    #[test]
    fn 名前の横に収まらない窓では候補の見本を名前の下に置く() {
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
        // 説明(注記)が何行も続くトグルの行
        let section = Section {
            title: None,
            rows: std::iter::once(Row::toggle(extras::DYNAMIC_DICTIONARY, "dynamicDictionary"))
                .chain((0..6).map(|_| Row::note(extras::HAND_SHIFT_NOTE)))
                .collect(),
            footer: None,
            footer_variants: &[],
        };
        let layout = layout(&[section], 800.0, |_| true, |_| true, &Estimate);
        let card = &layout.sections[0].cards[0];
        assert!(card.descriptions.len() > 5);
        assert!(card.card.height > size::ROW_HEIGHT * 2.0);
        assert!(card.control.max_y() <= card.card.y + size::ROW_HEIGHT);
    }

    /// 一覧の行に，書き方のボタン・結果の行・チップの欄を出す状態を返す(画面の側の RowState の代わり)
    struct WithList(ListState);

    impl Metrics for WithList {
        fn lines(&self, text: &str, kind: TextKind, width: f32) -> usize {
            Estimate.lines(text, kind, width)
        }

        fn width(&self, text: &str, kind: TextKind) -> f32 {
            Estimate.width(text, kind)
        }

        fn list_state(&self, row: &Row, _width: f32) -> ListState {
            if row.control.template_target().is_some() {
                self.0
            } else {
                ListState::default()
            }
        }
    }

    /// 登録した単語の一覧のカード
    fn word_card(state: ListState) -> CardLayout {
        let page = sections(Page::Dictionary).unwrap();
        let layout = layout(&page, 800.0, |_| true, |_| true, &WithList(state));
        layout
            .sections
            .iter()
            .zip(&page)
            .flat_map(|(placed, section)| placed.cards.iter().map(move |card| (card, section)))
            .find(|(card, section)| {
                matches!(section.rows[card.row].control, Control::Dictionary(_))
            })
            .map(|(card, _)| card.clone())
            .expect("登録した単語の行")
    }

    #[test]
    fn 単語の一覧は結果のあるときだけ_単語の欄の左端から結果の行を置く() {
        let card = word_card(ListState {
            result: true,
            ..ListState::default()
        });
        let (word, result) = (card.parts[1], card.result.expect("結果の行"));
        assert_eq!(result.x, word.x);
        assert_eq!(result.y, word.max_y() + size::CONTROL_GAP);
        assert_eq!(result.height, size::BODY_LINE_HEIGHT);
        // 表は結果の行の下から
        assert!(card.control.y >= result.max_y() + size::CONTROL_GAP);
        // 結果が無ければ行を取らない(入力欄と次の部品のあいだを広げない)
        let plain = word_card(ListState::default());
        assert_eq!(plain.result, None);
        assert_eq!(plain.parts[1].max_y() + size::CONTROL_GAP, plain.parts[3].y);
    }

    #[test]
    fn 書き方のボタンは単語の欄のすぐ右に_欄と同じ高さで置く() {
        let card = word_card(ListState {
            template_button: true,
            ..ListState::default()
        });
        let (word, button) = (card.parts[1], card.template_button.expect("ボタン"));
        assert_eq!(button.x, word.max_x() + size::CONTROL_GAP);
        assert_eq!((button.y, button.height), (word.y, word.height));
        assert_eq!(button.width, button.height);
        // 次の部品(品詞)はボタンのすぐ右から
        assert_eq!(card.parts[2].x, button.max_x() + size::CONTROL_GAP);
        // スイッチがオフなら置かず，欄が広がる
        let plain = word_card(ListState::default());
        assert_eq!(plain.template_button, None);
        assert!(plain.parts[1].width > word.width);
    }

    #[test]
    fn 書き方のチップの欄は結果の下に幅いっぱいで_上下を_section_空けて置く() {
        let card = word_card(ListState {
            template_button: true,
            result: true,
            panel: Some(100.0),
        });
        let result = card.result.expect("結果の行");
        let panel = card.template_panel.expect("チップの欄");
        assert_eq!(panel.y, result.max_y() + tokens::size::space::SECTION);
        assert_eq!(panel.height, 100.0);
        assert_eq!(panel.x, card.parts[0].x);
        // コメントの欄はチップの欄の下から
        assert_eq!(
            card.parts[3].y,
            panel.max_y() + tokens::size::space::SECTION
        );
    }

    #[test]
    fn 注記は前の行の説明にする() {
        let page = sections(Page::Conversion).unwrap();
        let layout = layout(&page, 800.0, |_| true, |_| true, &Estimate);
        // Zenzai モデルの行に，併用のときの注記(次の行)が付く
        let (section, placed) = page
            .iter()
            .zip(&layout.sections)
            .find(|(section, _)| section.rows.iter().any(|row| row.path == "zenzaiModel"))
            .unwrap();
        let card = placed
            .cards
            .iter()
            .find(|card| section.rows[card.row].path == "zenzaiModel")
            .unwrap();
        assert_eq!(card.descriptions.len(), 1);
        assert_eq!(card.descriptions[0].0, card.row + 1);
        let (_, description) = card.descriptions[0];
        assert!(description.y >= card.label.max_y());
        assert!(description.max_y() <= card.card.max_y());
        assert!(description.width > 0.0);
    }

    #[test]
    fn 出さない行は場所を取らない() {
        let page = sections(Page::Input).unwrap();
        let all = layout(&page, 800.0, |_| true, |_| true, &Estimate);
        let some = layout(
            &page,
            800.0,
            |row| row.control != Control::Toggle,
            |_| true,
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
        // 入力欄 2 つ・追加・キャンセル・検索欄・削除・インポート・エクスポート
        assert_eq!(card.parts.len(), 8);
        for pair in card.parts[..4].windows(2) {
            assert!(pair[0].max_x() <= pair[1].x);
        }
        // 打つもの → 置き換えるものの欄のあいだは矢印の分だけ広い
        assert!(card.parts[1].x - card.parts[0].max_x() >= size::LIST_ARROW_WIDTH);
        assert!(card.parts[3].max_x() <= card.card.max_x());
        assert!(card.control.y >= card.parts[0].max_y());
        // 表の下の帯は 1 行で，削除は左の端，検索欄とファイルのボタンは右に寄せる(macOS の RuleListEditor)
        let search = card.parts[4];
        let remove = card.parts[5];
        let export = card.parts[7];
        assert!(search.y >= card.control.max_y());
        assert_eq!(remove.y, search.y);
        assert_eq!(export.y, search.y);
        assert!((remove.x - (card.card.x + size::CARD_PADDING_X)).abs() < 0.01);
        assert!(remove.max_x() < search.x);
        assert!((export.max_x() - (card.card.max_x() - size::CARD_PADDING_X)).abs() < 0.01);
        assert!(export.max_y() <= card.card.max_y());
    }

    #[test]
    fn 除外設定は表の下の左に動作とアプリの追加_右に並べ替えと削除を置く() {
        let layout = all(Page::Apps, 800.0);
        let card = &layout.sections[0].cards[0];
        // 名前の欄・追加・動作・アプリを追加…・∧・∨・削除
        assert_eq!(card.parts.len(), 7);
        let (name, add) = (card.parts[0], card.parts[1]);
        assert_eq!(name.y, add.y);
        assert!(name.max_y() <= card.control.y);
        let bottom = &card.parts[2..];
        let left = card.card.x + size::CARD_PADDING_X;
        let right = card.card.max_x() - size::CARD_PADDING_X;
        assert!((bottom[0].x - left).abs() < 0.01);
        assert!(bottom[0].max_x() < bottom[1].x);
        for rect in bottom {
            assert_eq!(rect.y, bottom[0].y);
            assert!(rect.y >= card.control.max_y());
        }
        // 絵のボタンは決まった幅で，削除は右の端
        assert_eq!(bottom[2].width, size::ICON_BUTTON_WIDTH);
        assert_eq!(bottom[3].width, size::ICON_BUTTON_WIDTH);
        assert!((bottom[4].max_x() - right).abs() < 0.01);
        assert!(bottom[1].max_x() < bottom[2].x);
    }

    #[test]
    fn コマンドの一覧は入力欄を置かず_表の下にボタンを並べる() {
        let layout = all(Page::Commands, 800.0);
        let card = &layout.sections[0].cards[1];
        // コマンドを追加…・編集…・削除
        assert_eq!(card.parts.len(), 3);
        assert!((card.control.y - (card.card.y + size::CARD_PADDING_Y)).abs() < 0.01);
        for pair in card.parts.windows(2) {
            assert!(pair[0].max_x() < pair[1].x);
            assert_eq!(pair[0].y, pair[1].y);
        }
        assert!(card.parts[0].y >= card.control.max_y());
    }

    #[test]
    fn 辞書の一覧は取り込むボタンをカードの下に置き_注記はその下() {
        for (page, index) in [(Page::Dictionary, 3), (Page::Conversion, 0)] {
            let sections = sections(page).unwrap();
            let index = sections
                .iter()
                .position(|section| {
                    section
                        .rows
                        .iter()
                        .any(|row| matches!(row.control, Control::Dictionaries(_)))
                })
                .unwrap_or(index);
            for width in [800.0, 400.0] {
                let layout = layout(&sections, width, |_| true, |_| true, &Estimate);
                let section = &layout.sections[index];
                let card = &section.cards[0];
                // 取り込むボタンだけ．カードの左の端にそろえ，カード(一覧についての注記があればその下)に間を空けて置く
                assert_eq!(card.parts.len(), 1);
                let button = card.parts[0];
                assert_eq!(button.x, card.card.x);
                let above = card
                    .descriptions
                    .last()
                    .map_or(card.card.max_y(), |(_, rect)| rect.max_y());
                assert_eq!(button.y, above + size::FOOTER_GAP);
                assert!(button.width >= size::BUTTON_WIDTH);
                let footer = section.footer.unwrap();
                assert!(footer.y >= button.max_y());
            }
        }
        assert_eq!(button_width("更新", &Estimate), size::BUTTON_WIDTH);
    }

    #[test]
    fn 行がひとつも出ないまとまりは見出しも置かない() {
        let page = crate::pages::theme_editor();
        // 読みにくい組み合わせが無い(読みやすさの知らせを出さない)
        let hidden = layout(
            &page,
            800.0,
            |row| !matches!(row.control, Control::ThemeIssue(_)),
            |_| true,
            &Estimate,
        );
        let shown = layout(&page, 800.0, |_| true, |_| true, &Estimate);
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
    }

    /// 見本の高さを決める(謝辞と同じく画面の側で測る)
    struct Previewed(f32, f32);

    impl Metrics for Previewed {
        fn lines(&self, text: &str, kind: TextKind, width: f32) -> usize {
            Estimate.lines(text, kind, width)
        }

        fn width(&self, text: &str, kind: TextKind) -> f32 {
            Estimate.width(text, kind)
        }

        fn height(&self, row: &Row, width: f32) -> Option<f32> {
            (row.control == Control::ThemePreview).then(|| preview_height((self.0, self.1), width))
        }
    }

    #[test]
    fn 見本は描いた大きさで置き_狭ければ縮める() {
        assert_eq!(preview_height((400.0, 200.0), 600.0), 200.0);
        assert_eq!(preview_height((400.0, 200.0), 200.0), 100.0);
        let page = sections(Page::Appearance).unwrap();
        let padding = size_settings::PREVIEW_PADDING;
        // 広い窓: 見本は描いた高さのまま，まわりに見本の余白をとる
        let wide = layout(&page, 1000.0, |_| true, |_| true, &Previewed(400.0, 200.0));
        let card = &wide.sections[0].cards[0];
        assert_eq!(card.control.height, 200.0);
        assert_eq!(card.card.height, 200.0 + padding * 2.0);
        assert_eq!(card.control.x - card.card.x, padding);
        // 狭い窓: 幅に合わせて同じ比で縮める
        let narrow = layout(&page, 300.0, |_| true, |_| true, &Previewed(400.0, 200.0));
        let card = &narrow.sections[0].cards[0];
        assert!(card.control.height < 200.0);
        assert_eq!(
            card.control.height,
            preview_height((400.0, 200.0), card.control.width)
        );
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
            let rows = sections(page).unwrap();
            for (section, rows) in layout.sections.iter().zip(&rows) {
                for card in &section.cards {
                    assert!(card.control.max_y() <= card.card.max_y(), "{card:?}");
                    assert!(card.control.y >= card.card.y);
                    // 辞書の一覧の取り込むボタンはカードの下に置く
                    if matches!(rows.rows[card.row].control, Control::Dictionaries(_)) {
                        continue;
                    }
                    for part in &card.parts {
                        assert!(part.max_y() <= card.card.max_y(), "{card:?}");
                    }
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
