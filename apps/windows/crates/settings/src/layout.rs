#![forbid(unsafe_code)]

//! 項目の並び(pages::Section)を，ページの中の位置に置く．寸法は 96dpi の 1 ピクセルを 1 とし，app が DPI に合わせて拡大する．
//! Windows 11 の設定アプリと同じく，1 行ずつを角の丸い地(カード)に入れ，名前を左，部品を右に置く．
//! 注記は前の行のカードの中に，名前の下の説明として入れる

use crate::pages::{Control, ListButtons, Row, Section};
use tokens::size::settings_windows as size;

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

/// 1 行のカードと，その中の部品の位置
#[derive(Debug, Clone, PartialEq)]
pub struct CardLayout {
    /// section.rows の中の位置
    pub row: usize,
    pub card: Rect,
    pub label: Rect,
    /// 説明(後ろに続く注記の行)の位置と section.rows の中の位置
    pub descriptions: Vec<(usize, Rect)>,
    pub control: Rect,
    /// 既定に戻すボタン(部品の左)
    pub reset: Rect,
    /// 一覧の行の入力欄と追加・削除のボタン(左の欄・右の欄・追加・削除．右の欄の無い一覧は 3 つ)
    pub parts: Vec<Rect>,
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

/// 部品の幅
pub fn control_width(control: &Control) -> f32 {
    match control {
        Control::Toggle => size::TOGGLE_WIDTH,
        Control::Choice(_) => size::CONTROL_WIDTH,
        Control::Stepper(_) => size::STEPPER_WIDTH,
        Control::Seconds(_) => size::CONTROL_WIDTH,
        Control::Action(_) | Control::Stat(_) | Control::Info(_) => size::CONTROL_WIDTH,
        Control::List(..)
        | Control::Preview
        | Control::Dictionary(_)
        | Control::Symbols(..)
        | Control::SyncFields(_)
        | Control::Dictionaries(..)
        | Control::CustomThemes(_)
        | Control::ThemePreview
        | Control::Notices => 0.0,
        Control::Color => size::CONTROL_WIDTH,
        Control::Version => size::CONTROL_WIDTH,
        Control::Preset => size::CONTROL_WIDTH + size::CONTROL_GAP + size::BUTTON_WIDTH,
        Control::KeymapReport | Control::ThemeReport => 0.0,
        Control::Note => 0.0,
    }
}

/// 行の中身の左端と幅(窓を広げても行が伸びすぎないよう，幅に上限を設ける)
pub fn content_frame(page_width: f32) -> (f32, f32) {
    let width = (page_width - size::PAGE_PADDING_X * 2.0).clamp(0.0, size::CONTENT_MAX_WIDTH);
    (size::PAGE_PADDING_X, width)
}

/// ページの部品を置く．visible は行を出すか，lines は文を幅に収めたときの行の数
pub fn layout(
    sections: &[Section],
    page_width: f32,
    visible: impl Fn(&Row) -> bool,
    lines: impl Fn(&str, f32) -> usize,
) -> PageLayout {
    let (left, width) = content_frame(page_width);
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
        for (position, row) in section.rows.iter().enumerate() {
            if !visible(row) {
                continue;
            }
            if row.control == Control::Note {
                if let Some(card) = cards.last_mut() {
                    add_description(card, position, row.title, &lines);
                    y = card.card.max_y() + size::CARD_GAP;
                }
                continue;
            }
            let card = Rect::new(left, y, width, card_height(&row.control, width));
            cards.push(place(position, row, card));
            y = card.max_y() + size::CARD_GAP;
        }
        let footer = section.footer.map(|text| {
            let height = lines(text, width) as f32 * size::NOTE_LINE_HEIGHT;
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

/// カードの高さ．入力欄の並ぶカードは入力欄の行と下の表・結果・文の高さを足す．width はカードの幅(表の下のボタンを折り返すため)
fn card_height(control: &Control, width: f32) -> f32 {
    let inputs = size::CONTROL_HEIGHT + size::CONTROL_GAP;
    if let Some(buttons) = control.list_buttons() {
        let inner = (width - size::CARD_PADDING_X * 2.0).max(0.0);
        let below = button_lines(&bottom_widths(buttons), inner).len() as f32 * inputs;
        return size::CARD_PADDING_X * 2.0 + inputs + size::LIST_HEIGHT + below;
    }
    match control {
        Control::Preview => {
            size::CARD_PADDING_X * 2.0 + inputs + size::BODY_LINE_HEIGHT * PREVIEW_LINES
        }
        Control::Notices => size::CARD_PADDING_X * 2.0 + size::LIST_HEIGHT * NOTICES_LISTS,
        Control::KeymapReport | Control::ThemeReport => {
            size::CARD_PADDING_X * 2.0 + size::BODY_LINE_HEIGHT * REPORT_LINES
        }
        Control::ThemePreview => size::CARD_PADDING_X * 2.0 + size::PREVIEW_HEIGHT,
        _ => size::ROW_HEIGHT,
    }
}

fn place(position: usize, row: &Row, card: Rect) -> CardLayout {
    match &row.control {
        control if control.list_buttons().is_some() => {
            let fields = control.list_spec().map_or(0, |spec| spec.fields.len());
            let buttons = control.list_buttons().unwrap_or(NO_BUTTONS);
            return place_inputs(position, fields, buttons, card, size::LIST_HEIGHT);
        }
        Control::Preview => {
            return place_inputs(
                position,
                2,
                NO_BUTTONS,
                card,
                size::BODY_LINE_HEIGHT * PREVIEW_LINES,
            )
        }
        Control::Notices => {
            return place_inputs(
                position,
                0,
                NO_BUTTONS,
                card,
                size::LIST_HEIGHT * NOTICES_LISTS,
            )
        }
        Control::ThemePreview => {
            return place_inputs(position, 0, NO_BUTTONS, card, size::PREVIEW_HEIGHT);
        }
        Control::KeymapReport | Control::ThemeReport => {
            return place_inputs(
                position,
                0,
                NO_BUTTONS,
                card,
                size::BODY_LINE_HEIGHT * REPORT_LINES,
            )
        }
        _ => {}
    }
    let control_width = control_width(&row.control);
    if let Control::Action(_) = row.control {
        // 操作のボタンは名前を持たず，カードの左にボタンだけを置く
        let x = card.x + size::CARD_PADDING_X;
        return CardLayout {
            row: position,
            card,
            label: Rect::new(x, card.y, 0.0, 0.0),
            descriptions: Vec::new(),
            control: Rect::new(
                x,
                card.y + (card.height - size::CONTROL_HEIGHT) / 2.0,
                control_width
                    .min(card.width - size::CARD_PADDING_X * 2.0)
                    .max(0.0),
                size::CONTROL_HEIGHT,
            ),
            reset: Rect::new(x, card.y, 0.0, 0.0),
            parts: Vec::new(),
        };
    }
    let control_x = card.max_x() - size::CARD_PADDING_X - control_width;
    let reset_x = control_x - size::CONTROL_GAP - size::RESET_SIZE;
    let label_x = card.x + size::CARD_PADDING_X;
    let control_y = card.y + (card.height - size::CONTROL_HEIGHT) / 2.0;
    // ひな形は一覧と読み込むボタンを並べる
    let (control_width, parts) = match row.control {
        Control::Preset => (
            size::CONTROL_WIDTH,
            vec![Rect::new(
                control_x + size::CONTROL_WIDTH + size::CONTROL_GAP,
                control_y,
                size::BUTTON_WIDTH,
                size::CONTROL_HEIGHT,
            )],
        ),
        _ => (control_width, Vec::new()),
    };
    CardLayout {
        row: position,
        card,
        label: Rect::new(
            label_x,
            card.y + (card.height - size::BODY_LINE_HEIGHT) / 2.0,
            (reset_x - size::CONTROL_GAP - label_x).max(0.0),
            size::BODY_LINE_HEIGHT,
        ),
        descriptions: Vec::new(),
        control: Rect::new(control_x, control_y, control_width, size::CONTROL_HEIGHT),
        reset: Rect::new(
            reset_x,
            card.y + (card.height - size::RESET_SIZE) / 2.0,
            size::RESET_SIZE,
            size::RESET_SIZE,
        ),
        parts,
    }
}

const NO_BUTTONS: ListButtons = ListButtons {
    top: &[],
    bottom: &[],
    search: false,
};

/// 表の下に並べるものの幅(検索欄と，ボタン)
fn bottom_widths(buttons: ListButtons) -> Vec<f32> {
    buttons
        .search
        .then_some(size::CONTROL_WIDTH)
        .into_iter()
        .chain(buttons.bottom.iter().map(|label| button_width(label)))
        .collect()
}

/// 試す欄の結果の行の数
const PREVIEW_LINES: f32 = 2.0;
/// 謝辞の欄の高さ(一覧の表の何倍か)
const NOTICES_LISTS: f32 = 2.0;
/// キー設定の表の問題の欄の行の数(超えたら欄の中で送る)
const REPORT_LINES: f32 = 4.0;

/// ボタンの幅．名前の長さ(全角を 1，半角を 0.5 文字とみなす)に左右の余白を足し，下限より狭くしない
pub fn button_width(label: &str) -> f32 {
    let units: f32 = label
        .chars()
        .map(|character| if character.is_ascii() { 0.5 } else { 1.0 })
        .sum();
    (units * size::BODY_FONT_SIZE + size::BUTTON_PADDING_X * 2.0).max(size::BUTTON_WIDTH)
}

/// 表の下のボタンを幅 inner に収まるよう折り返した行(ボタンの幅の並び)
fn button_lines(widths: &[f32], inner: f32) -> Vec<Vec<f32>> {
    let mut lines: Vec<Vec<f32>> = Vec::new();
    let mut used = 0.0;
    for &width in widths {
        match lines.last_mut() {
            Some(line) if used + size::CONTROL_GAP + width <= inner => {
                used += size::CONTROL_GAP + width;
                line.push(width);
            }
            _ => {
                used = width;
                lines.push(vec![width]);
            }
        }
    }
    lines
}

/// 入力欄の並ぶカード(一覧・試す欄)．上に入力欄とボタン，下に表か結果を置き，表の下に検索欄とボタンを並べる．
/// parts は入力欄・上のボタン・検索欄・下のボタンの順
fn place_inputs(
    position: usize,
    fields: usize,
    buttons: ListButtons,
    card: Rect,
    below: f32,
) -> CardLayout {
    let x = card.x + size::CARD_PADDING_X;
    let top = card.y + size::CARD_PADDING_X;
    let inner = (card.width - size::CARD_PADDING_X * 2.0).max(0.0);
    let widths: Vec<f32> = buttons
        .top
        .iter()
        .map(|label| button_width(label))
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
    let mut line_top = list_top + below + size::CONTROL_GAP;
    for line in button_lines(&bottom_widths(buttons), inner) {
        let mut cursor = x;
        for width in line {
            parts.push(Rect::new(cursor, line_top, width, size::CONTROL_HEIGHT));
            cursor += width + size::CONTROL_GAP;
        }
        line_top += size::CONTROL_HEIGHT + size::CONTROL_GAP;
    }
    CardLayout {
        row: position,
        card,
        label: Rect::new(x, card.y, 0.0, 0.0),
        descriptions: Vec::new(),
        control: Rect::new(x, list_top, inner, below),
        reset: Rect::new(x, card.y, 0.0, 0.0),
        parts,
    }
}

/// 注記をカードの説明として足し，カードを高くする．名前と説明をひとまとまりにしてカードの中で上下の真ん中に置く
fn add_description(
    card: &mut CardLayout,
    position: usize,
    text: &str,
    lines: &impl Fn(&str, f32) -> usize,
) {
    let height = lines(text, card.label.width).max(1) as f32 * size::NOTE_LINE_HEIGHT;
    card.descriptions.push((
        position,
        Rect::new(card.label.x, 0.0, card.label.width, height),
    ));
    let text_height = size::BODY_LINE_HEIGHT
        + card
            .descriptions
            .iter()
            .map(|(_, rect)| rect.height)
            .sum::<f32>();
    let card_height =
        size::ROW_HEIGHT.max(text_height + (size::ROW_HEIGHT - size::BODY_LINE_HEIGHT));
    let delta = card_height - card.card.height;
    card.card.height = card_height;
    card.control.y += delta / 2.0;
    card.reset.y += delta / 2.0;
    let mut y = card.card.y + (card_height - text_height) / 2.0;
    card.label.y = y;
    y += size::BODY_LINE_HEIGHT;
    for (_, rect) in &mut card.descriptions {
        rect.y = y;
        y += rect.height;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pages::{sections, Page};

    fn one_line(_: &str, _: f32) -> usize {
        1
    }

    #[test]
    fn 行を上から順に重ならないよう置く() {
        let page = sections(Page::Input).unwrap();
        let layout = layout(&page, 800.0, |_| true, one_line);
        let mut last = layout.title.max_y();
        for section in &layout.sections {
            if let Some(title) = section.title {
                assert!(title.y >= last);
                last = title.max_y();
            }
            for card in &section.cards {
                assert!(card.card.y >= last);
                assert!(card.control.x > card.label.x);
                assert!(card.reset.max_x() <= card.control.x);
                last = card.card.max_y();
            }
        }
        assert!(layout.height > last);
    }

    #[test]
    fn 注記は前の行の説明にする() {
        let page = sections(Page::Input).unwrap();
        let layout = layout(&page, 800.0, |_| true, |_, _| 2);
        // キー配列の行(4 番目の行)に注記(5 番目)が付く
        let card = layout.sections[0]
            .cards
            .iter()
            .find(|card| card.row == 4)
            .unwrap();
        assert_eq!(card.descriptions.len(), 1);
        assert_eq!(card.descriptions[0].0, 5);
        assert!(card.card.height > size::ROW_HEIGHT);
        let (_, description) = card.descriptions[0];
        assert!(description.y >= card.label.max_y());
        assert!(description.max_y() <= card.card.max_y());
    }

    #[test]
    fn 出さない行は場所を取らない() {
        let page = sections(Page::Input).unwrap();
        let all = layout(&page, 800.0, |_| true, one_line);
        let some = layout(&page, 800.0, |row| row.control != Control::Toggle, one_line);
        assert!(some.height < all.height);
    }

    #[test]
    fn 操作のボタンはカードの左に置く() {
        let page = sections(Page::Backup).unwrap();
        let layout = layout(&page, 800.0, |_| true, one_line);
        let card = &layout.sections[0].cards[0];
        assert_eq!(card.control.x, card.card.x + size::CARD_PADDING_X);
        assert!(card.control.max_x() <= card.card.max_x());
    }

    #[test]
    fn 一覧は入力欄とボタンを表の上に並べ_検索欄を表の下に置く() {
        let page = sections(Page::Correction).unwrap();
        let layout = layout(&page, 800.0, |_| true, one_line);
        let card = &layout.sections[1].cards[0];
        // 入力欄 2 つ・追加・削除・検索欄
        assert_eq!(card.parts.len(), 5);
        for pair in card.parts[..4].windows(2) {
            assert!(pair[0].max_x() <= pair[1].x);
        }
        assert!(card.parts[3].max_x() <= card.card.max_x());
        assert!(card.control.y >= card.parts[0].max_y());
        let search = card.parts[4];
        assert!(search.y >= card.control.max_y());
        assert!(search.max_y() <= card.card.max_y());
        // 直さない語句は 1 列
        assert_eq!(layout.sections[2].cards[0].parts.len(), 4);
    }

    #[test]
    fn 記号の一覧は入力欄を2つとボタンを3つ並べ_表の下に検索欄を置く() {
        let page = sections(Page::Symbols).unwrap();
        let layout = layout(&page, 800.0, |_| true, one_line);
        for section in &layout.sections {
            let card = &section.cards[0];
            // 入力欄 2 つ・追加・削除・切り替え・検索欄
            assert_eq!(card.parts.len(), 6);
            assert!(card.parts[4].max_x() <= card.card.max_x());
            assert!(card.parts[5].y >= card.control.max_y());
        }
    }

    #[test]
    fn 辞書の一覧は表の下にボタンを折り返して並べ_名前の長いボタンは広げる() {
        let page = sections(Page::Dictionary).unwrap();
        for width in [800.0, 400.0] {
            let layout = layout(&page, width, |_| true, one_line);
            let card = &layout.sections[1].cards[0];
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
        assert!(button_width("有効・無効の切り替え") > size::BUTTON_WIDTH);
        assert_eq!(button_width("更新"), size::BUTTON_WIDTH);
    }

    #[test]
    fn 行がひとつも出ないまとまりは見出しも置かない() {
        let page = sections(Page::Appearance).unwrap();
        // カスタムテーマを選んでいない(色・形の行を出さない)
        let hidden = layout(&page, 800.0, |row| row.visible.is_none(), one_line);
        let shown = layout(&page, 800.0, |_| true, one_line);
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
        for page in [Page::Language, Page::Dictionary, Page::Symbols, Page::About] {
            let page = sections(page).unwrap();
            let layout = layout(&page, 800.0, |_| true, one_line);
            for card in layout.sections.iter().flat_map(|section| &section.cards) {
                assert!(card.control.max_y() <= card.card.max_y(), "{card:?}");
                assert!(card.control.y >= card.card.y);
            }
        }
    }

    #[test]
    fn 広い窓でも行の幅は上限まで() {
        let page = sections(Page::Input).unwrap();
        let layout = layout(&page, 3000.0, |_| true, one_line);
        assert_eq!(
            layout.sections[0].cards[0].card.width,
            size::CONTENT_MAX_WIDTH
        );
    }
}
