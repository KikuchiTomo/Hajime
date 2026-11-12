#![forbid(unsafe_code)]

//! 取り込んだ辞書・連想の辞書の一覧(macOS の ImportedDictionariesView・AssociationSection と DictionaryRowHeader)．
//! 辞書ごとに 1 行の見出し(開閉・オン・オフ・名前と要約・優先度を上げる・下げる)を置き，開いた 1 つの辞書だけ
//! 中身(名前・分野・使う場面・選んだアプリ・再読み込み・削除)を見出しの下に並べる．上ほど優先する．
//! 一覧の下に取り込むボタンと，取り込んでいるあいだの輪を置く

use super::{Element, Frame, PageView, Part, RowState};
use crate::app::paint::{self, Canvas, TextLayout, TextStyle};
use crate::app::theme::Color;
use crate::dictionaries::{self as model, Entry};
use crate::layout::Rect;
use crate::pages::{DictionaryList, DICTIONARY_CONDITIONS};
use crate::strings::{dictionaries, settings, windows as text};
use crate::ui::anim::{Easing, Tween};
use tokens::motion::settings_windows as motion;
use tokens::size::settings_windows as size;

/// 辞書の行の中の押せる部品
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum EntryPart {
    /// 中身を開く・閉じる(macOS の chevron.right)
    Expand,
    /// オン・オフ
    Toggle,
    /// 優先度を上げる・下げる(macOS の chevron.up・chevron.down)
    MoveUp,
    MoveDown,
    /// 名前・分野の打つ欄
    Name,
    Field,
    /// 使う場面を選ぶ欄
    Condition,
    /// 選んだアプリを外す(アプリの番号)
    RemoveApp(usize),
    AddApp,
    Reimport,
    Remove,
}

impl EntryPart {
    /// 読み上げの番号の中での位置(アプリを外すボタンは後ろに並べる)
    pub fn ordinal(self) -> usize {
        match self {
            EntryPart::Expand => 0,
            EntryPart::Toggle => 1,
            EntryPart::MoveUp => 2,
            EntryPart::MoveDown => 3,
            EntryPart::Name => 4,
            EntryPart::Field => 5,
            EntryPart::Condition => 6,
            EntryPart::AddApp => 7,
            EntryPart::Reimport => 8,
            EntryPart::Remove => 9,
            EntryPart::RemoveApp(index) => 10 + index,
        }
    }
}

/// 一覧に書く文字
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Label {
    /// 辞書の名前と要約(辞書の番号)
    Name(usize),
    Summary(usize),
    /// 中身の行の名前(名前・分野・使う場面)
    Caption(&'static str),
    /// 選んだアプリ(辞書の番号とアプリの番号)
    App(usize, usize),
    /// 辞書が無いときの文
    Empty,
}

/// 一覧の中の置き場所(ページの中の座標)
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Placement {
    /// 押せる部品(辞書の番号・部品・位置)．フォーカスの順
    pub parts: Vec<(usize, EntryPart, Rect)>,
    pub labels: Vec<(Rect, Label)>,
    /// 行のあいだの区切り線(左端・右端・上端)
    pub dividers: Vec<(f32, f32, f32)>,
    /// カードの中の高さ
    pub height: f32,
}

/// 見出しの高さ(名前の行と要約の行に，カードの上下の余白を足す．名前の下に注記を置く行と同じ)
fn header_height() -> f32 {
    size::BODY_LINE_HEIGHT + size::NOTE_LINE_HEIGHT + size::CARD_PADDING_Y * 2.0
}

/// 辞書の一覧を (x, y) から幅 width のカードに置く．expanded は開いている辞書の番号．
/// button はボタンの名前からボタンの幅を返す
pub fn place(
    list: DictionaryList,
    entries: &[Entry],
    expanded: Option<usize>,
    (x, y, width): (f32, f32, f32),
    button: &dyn Fn(&str) -> f32,
) -> Placement {
    let mut placement = Placement::default();
    let left = x + size::CARD_PADDING_X;
    let right = (x + width - size::CARD_PADDING_X).max(left);
    let mut top = y;
    if entries.is_empty() {
        placement.labels.push((
            Rect::new(left, top, right - left, size::ROW_HEIGHT),
            Label::Empty,
        ));
        placement.height = size::ROW_HEIGHT;
        return placement;
    }
    let icon = size::STEPPER_BUTTON_WIDTH;
    let control = size::CONTROL_HEIGHT;
    for (index, entry) in entries.iter().enumerate() {
        if index > 0 {
            placement.dividers.push((left, right, top));
        }
        let height = header_height();
        let button_top = top + (height - control) / 2.0;
        let expand = Rect::new(left, button_top, icon, control);
        let down = Rect::new(right - icon, button_top, icon, control);
        let up = Rect::new(down.x - icon, button_top, icon, control);
        let toggle_x = (up.x - size::CONTROL_GAP - size::TOGGLE_WIDTH).max(expand.max_x());
        let toggle = Rect::new(
            toggle_x,
            button_top,
            (up.x - size::CONTROL_GAP - toggle_x).max(0.0),
            control,
        );
        let text_left = expand.max_x() + size::CONTROL_GAP;
        let text_width = (toggle.x - size::CONTROL_GAP - text_left).max(0.0);
        let name = Rect::new(
            text_left,
            top + size::CARD_PADDING_Y,
            text_width,
            size::BODY_LINE_HEIGHT,
        );
        let summary = Rect::new(text_left, name.max_y(), text_width, size::NOTE_LINE_HEIGHT);
        placement.parts.extend([
            (index, EntryPart::Expand, expand),
            (index, EntryPart::Toggle, toggle),
            (index, EntryPart::MoveUp, up),
            (index, EntryPart::MoveDown, down),
        ]);
        placement
            .labels
            .extend([(name, Label::Name(index)), (summary, Label::Summary(index))]);
        top += height;
        if expanded == Some(index) {
            top = place_body(
                &mut placement,
                list,
                entry,
                index,
                (text_left, right, top),
                button,
            );
        }
    }
    placement.height = top - y;
    placement
}

/// 開いた辞書の中身を見出しの下に置く．左端は見出しの名前にそろえる．中身の下端を返す
fn place_body(
    placement: &mut Placement,
    list: DictionaryList,
    entry: &Entry,
    index: usize,
    (left, right, mut top): (f32, f32, f32),
    button: &dyn Fn(&str) -> f32,
) -> f32 {
    let row = size::ROW_HEIGHT;
    let control = size::CONTROL_HEIGHT;
    let inner = (row - control) / 2.0;
    let field_width = size::CONTROL_WIDTH.min(right - left);
    // 名前を左に，部品を右の端に置く行(macOS の Form の TextField・Picker)
    let labeled = |placement: &mut Placement, top: &mut f32, caption, part| {
        placement.dividers.push((left, right, *top));
        let field = Rect::new(right - field_width, *top + inner, field_width, control);
        let caption_width = (field.x - size::CONTROL_GAP - left).max(0.0);
        placement.labels.push((
            Rect::new(left, *top, caption_width, row),
            Label::Caption(caption),
        ));
        placement.parts.push((index, part, field));
        *top += row;
    };
    labeled(placement, &mut top, dictionaries::NAME, EntryPart::Name);
    if list == DictionaryList::Imported {
        labeled(placement, &mut top, dictionaries::FIELD, EntryPart::Field);
        labeled(
            placement,
            &mut top,
            dictionaries::CONDITION,
            EntryPart::Condition,
        );
        if entry.condition == model::APPS {
            let remove = button(settings::REMOVE).min(right - left);
            for app in 0..entry.apps.len() {
                placement.dividers.push((left, right, top));
                let button = Rect::new(right - remove, top + inner, remove, control);
                let label_width = (button.x - size::CONTROL_GAP - left).max(0.0);
                placement.labels.push((
                    Rect::new(left, top, label_width, row),
                    Label::App(index, app),
                ));
                placement
                    .parts
                    .push((index, EntryPart::RemoveApp(app), button));
                top += row;
            }
            placement.dividers.push((left, right, top));
            let add = button(dictionaries::ADD_APP).min(right - left);
            placement.parts.push((
                index,
                EntryPart::AddApp,
                Rect::new(left, top + inner, add, control),
            ));
            top += row;
        }
    }
    // 再読み込みは左，削除は右の端(macOS の HStack と Spacer)
    placement.dividers.push((left, right, top));
    let reimport = button(dictionaries::REIMPORT).min(right - left);
    let remove = button(settings::REMOVE).min(right - left);
    placement.parts.extend([
        (
            index,
            EntryPart::Reimport,
            Rect::new(left, top + inner, reimport, control),
        ),
        (
            index,
            EntryPart::Remove,
            Rect::new(right - remove, top + inner, remove, control),
        ),
    ]);
    top + row
}

/// 一覧の状態(辞書の行・開いている辞書・スイッチの動き・取り込んでいるか)
#[derive(Debug)]
pub struct Rows {
    pub list: DictionaryList,
    pub entries: Vec<Entry>,
    /// 開いている辞書の id(並べ替えても開いたままにする)
    pub expanded: Option<String>,
    /// 辞書ごとのスイッチのつまみの位置(entries と同じ並び)
    pub knobs: Vec<Tween>,
    /// 辞書を取り込んでいる(取り込むボタン・再読み込みを使えなくし，輪を回す)
    pub busy: bool,
    pub placement: Placement,
}

impl Rows {
    pub fn new(list: DictionaryList) -> Self {
        Self {
            list,
            entries: Vec::new(),
            expanded: None,
            knobs: Vec::new(),
            busy: false,
            placement: Placement::default(),
        }
    }

    /// 開いている辞書の番号
    pub fn expanded_index(&self) -> Option<usize> {
        let id = self.expanded.as_deref()?;
        self.entries.iter().position(|entry| entry.id == id)
    }

    /// 設定の値の辞書を映す．スイッチはオン・オフが変わった辞書だけ動かす．無くなった辞書は閉じる
    pub fn set_entries(&mut self, entries: Vec<Entry>, now: f64) {
        let knobs = entries
            .iter()
            .map(|entry| {
                let target = if entry.is_enabled { 1.0 } else { 0.0 };
                let previous = self
                    .entries
                    .iter()
                    .position(|old| old.id == entry.id)
                    .and_then(|position| self.knobs.get(position).copied());
                match previous {
                    Some(mut knob) => {
                        if knob.target() != target {
                            knob.retarget(target, now, f64::from(motion::TOGGLE), Easing::STANDARD);
                        }
                        knob
                    }
                    None => Tween::fixed(target),
                }
            })
            .collect();
        self.knobs = knobs;
        self.entries = entries;
        if self.expanded_index().is_none() {
            self.expanded = None;
        }
    }

    /// カードの中の高さ(幅に依らない)
    pub fn height(&self) -> f32 {
        place(
            self.list,
            &self.entries,
            self.expanded_index(),
            (0.0, 0.0, 0.0),
            &|_| 0.0,
        )
        .height
    }

    pub fn part_rect(&self, index: usize, part: EntryPart) -> Option<Rect> {
        self.placement
            .parts
            .iter()
            .find(|(entry, candidate, _)| *entry == index && *candidate == part)
            .map(|(_, _, rect)| *rect)
    }

    /// 部品を使えるか(端の辞書は動かせない．同梱の辞書は取り込み直せず消せない．取り込んでいるあいだは取り込めない)
    pub fn part_enabled(&self, index: usize, part: EntryPart) -> bool {
        let Some(entry) = self.entries.get(index) else {
            return false;
        };
        match part {
            EntryPart::MoveUp => index > 0,
            EntryPart::MoveDown => index + 1 < self.entries.len(),
            EntryPart::Reimport => !self.busy && !entry.is_bundled,
            EntryPart::Remove => !entry.is_bundled,
            _ => true,
        }
    }

    /// 使う場面の欄で選んでいる番号
    pub fn condition_index(&self, index: usize) -> Option<usize> {
        let entry = self.entries.get(index)?;
        DICTIONARY_CONDITIONS
            .iter()
            .position(|(value, _)| *value == entry.condition)
            .or(Some(0))
    }

    /// 部品の読み上げの名前
    pub fn name(&self, index: usize, part: EntryPart) -> String {
        let Some(entry) = self.entries.get(index) else {
            return String::new();
        };
        let with_name = |label: &str| format!("{} {label}", entry.name);
        match part {
            EntryPart::Expand => with_name(self.expand_label(index)),
            EntryPart::Toggle => entry.name.clone(),
            EntryPart::MoveUp => with_name(dictionaries::MOVE_UP),
            EntryPart::MoveDown => with_name(dictionaries::MOVE_DOWN),
            EntryPart::Name => dictionaries::NAME.to_string(),
            EntryPart::Field => dictionaries::FIELD.to_string(),
            EntryPart::Condition => dictionaries::CONDITION.to_string(),
            EntryPart::RemoveApp(app) => format!(
                "{} {}",
                entry.apps.get(app).map_or("", String::as_str),
                settings::REMOVE
            ),
            EntryPart::AddApp => dictionaries::ADD_APP.to_string(),
            EntryPart::Reimport => with_name(dictionaries::REIMPORT),
            EntryPart::Remove => with_name(settings::REMOVE),
        }
    }

    /// 開閉のボタンの説明(開いていれば隠す)
    pub fn expand_label(&self, index: usize) -> &'static str {
        if self.expanded_index() == Some(index) {
            dictionaries::HIDE_DETAILS
        } else {
            dictionaries::SHOW_DETAILS
        }
    }

    /// 絵だけのボタンの説明(macOS の .help)
    pub fn tooltip(&self, index: usize, part: EntryPart) -> Option<&'static str> {
        match part {
            EntryPart::Expand => Some(self.expand_label(index)),
            EntryPart::MoveUp => Some(dictionaries::MOVE_UP),
            EntryPart::MoveDown => Some(dictionaries::MOVE_DOWN),
            _ => None,
        }
    }

    /// 取り込んでいる輪を回し続けるか・スイッチが動いているか
    pub fn animating(&self, now: f64) -> bool {
        self.busy || self.knobs.iter().any(|knob| knob.running(now))
    }
}

impl PageView {
    /// 辞書の一覧を描く
    pub(super) fn paint_dictionaries(
        &self,
        canvas: &mut dyn Canvas,
        frame: &Frame,
        index: usize,
        row: &RowState,
    ) {
        let Some(rows) = &row.dictionaries else {
            return;
        };
        let theme = frame.theme;
        let palette = &theme.palette;
        let (text_color, secondary) = if row.enabled {
            (palette.text, palette.text_secondary)
        } else {
            (palette.text_disabled, palette.text_disabled)
        };
        for (left, right, top) in &rows.placement.dividers {
            canvas.fill_rect(
                Rect::new(*left, *top, right - left, 1.0),
                Color::from(palette.card_stroke),
            );
        }
        for (rect, label) in &rows.placement.labels {
            if !frame.shows(*rect) {
                continue;
            }
            let entry = |position: usize| rows.entries.get(position);
            let (shown, style, color) = match label {
                Label::Name(position) => (
                    entry(*position).map_or_else(String::new, |entry| entry.name.clone()),
                    TextStyle::Body,
                    text_color,
                ),
                Label::Summary(position) => (
                    entry(*position)
                        .map_or_else(String::new, |entry| model::summary(rows.list, entry)),
                    TextStyle::Caption,
                    secondary,
                ),
                Label::Caption(caption) => ((*caption).to_string(), TextStyle::Body, text_color),
                // アプリは等幅の文字で出す(macOS の monospaced)
                Label::App(position, app) => (
                    entry(*position)
                        .and_then(|entry| entry.apps.get(*app))
                        .cloned()
                        .unwrap_or_default(),
                    TextStyle::Code,
                    text_color,
                ),
                Label::Empty => (
                    rows.list.empty_text().to_string(),
                    TextStyle::Body,
                    secondary,
                ),
            };
            canvas.text(*rect, &shown, style, Color::from(color), TextLayout::LINE);
        }
        for (position, part, rect) in &rows.placement.parts {
            if !frame.shows(*rect) {
                continue;
            }
            let element_part = Part::Entry(*position, *part);
            let element = Element {
                row: index,
                part: element_part,
            };
            let state = self.state(frame, element, row.part_enabled(element_part));
            match part {
                EntryPart::Expand | EntryPart::MoveUp | EntryPart::MoveDown => {
                    let glyph = match part {
                        EntryPart::MoveUp => theme.glyphs.chevron_up,
                        EntryPart::MoveDown => theme.glyphs.chevron_down,
                        _ if rows.expanded_index() == Some(*position) => theme.glyphs.chevron_down,
                        _ => theme.glyphs.chevron_right,
                    };
                    paint::button(canvas, theme, *rect, glyph, paint::ButtonKind::Quiet, state);
                }
                EntryPart::Toggle => {
                    let on = rows
                        .entries
                        .get(*position)
                        .is_some_and(|entry| entry.is_enabled);
                    let knob = rows
                        .knobs
                        .get(*position)
                        .map_or(if on { 1.0 } else { 0.0 }, |knob| knob.value(frame.now));
                    paint::toggle(canvas, theme, *rect, on, knob, text::ON, text::OFF, state);
                }
                EntryPart::Name | EntryPart::Field => {
                    self.paint_field(canvas, frame, index, row, element_part);
                }
                EntryPart::Condition => {
                    let label = rows
                        .condition_index(*position)
                        .and_then(|choice| DICTIONARY_CONDITIONS.get(choice))
                        .map_or("", |(_, label)| label);
                    paint::dropdown(
                        canvas,
                        theme,
                        *rect,
                        label,
                        frame.open == Some(element),
                        state,
                    );
                }
                EntryPart::RemoveApp(_) | EntryPart::AddApp | EntryPart::Reimport => {
                    let label = match part {
                        EntryPart::AddApp => dictionaries::ADD_APP,
                        EntryPart::Reimport => dictionaries::REIMPORT,
                        _ => settings::REMOVE,
                    };
                    paint::button(
                        canvas,
                        theme,
                        *rect,
                        label,
                        paint::ButtonKind::Standard,
                        state,
                    );
                }
                // 消すボタンは危険の色(macOS の role: .destructive)
                EntryPart::Remove => paint::button(
                    canvas,
                    theme,
                    *rect,
                    settings::REMOVE,
                    paint::ButtonKind::Destructive,
                    state,
                ),
            }
        }
        // 一覧の下の取り込むボタンと，取り込んでいるあいだの輪(macOS の ProgressView)
        if let Some(rect) = row.part_rect(Part::Import) {
            let element = Element {
                row: index,
                part: Part::Import,
            };
            paint::button(
                canvas,
                theme,
                rect,
                rows.list.import_label(),
                paint::ButtonKind::Standard,
                self.state(frame, element, row.part_enabled(Part::Import)),
            );
            if rows.busy {
                let period = f64::from(motion::PROGRESS_RING);
                let phase = ((frame.now % period) / period) as f32;
                let ring = size::PROGRESS_RING_SIZE;
                paint::progress_ring(
                    canvas,
                    theme,
                    rect.max_x() + size::CONTROL_GAP + ring / 2.0,
                    rect.y + rect.height / 2.0,
                    phase,
                );
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str, condition: &str, apps: &[&str]) -> Entry {
        Entry {
            id: id.to_string(),
            name: id.to_string(),
            field: String::new(),
            is_enabled: true,
            condition: condition.to_string(),
            apps: apps.iter().map(|app| (*app).to_string()).collect(),
            count: 1,
            is_bundled: false,
        }
    }

    fn width(label: &str) -> f32 {
        label.chars().count() as f32 * size::BODY_FONT_SIZE + size::BUTTON_PADDING_X * 2.0
    }

    fn parts_of(placement: &Placement, index: usize) -> Vec<EntryPart> {
        placement
            .parts
            .iter()
            .filter(|(entry, _, _)| *entry == index)
            .map(|(_, part, _)| *part)
            .collect()
    }

    #[test]
    fn 閉じた辞書は見出しだけを並べる() {
        let entries = [
            entry("a", model::ALWAYS, &[]),
            entry("b", model::ALWAYS, &[]),
        ];
        let placement = place(
            DictionaryList::Imported,
            &entries,
            None,
            (0.0, 0.0, 800.0),
            &width,
        );
        assert_eq!(placement.height, header_height() * 2.0);
        assert_eq!(
            parts_of(&placement, 1),
            vec![
                EntryPart::Expand,
                EntryPart::Toggle,
                EntryPart::MoveUp,
                EntryPart::MoveDown
            ]
        );
        // 区切り線は辞書のあいだだけ
        assert_eq!(placement.dividers.len(), 1);
        let rect = |part| {
            placement
                .parts
                .iter()
                .find(|(entry, candidate, _)| *entry == 0 && *candidate == part)
                .map(|(_, _, rect)| *rect)
                .unwrap()
        };
        // 開閉は左の端，スイッチ・上げる・下げるは右の端に左から並べる
        assert_eq!(rect(EntryPart::Expand).x, size::CARD_PADDING_X);
        assert_eq!(
            rect(EntryPart::MoveDown).max_x(),
            800.0 - size::CARD_PADDING_X
        );
        assert_eq!(rect(EntryPart::MoveUp).max_x(), rect(EntryPart::MoveDown).x);
        assert!(rect(EntryPart::Toggle).max_x() < rect(EntryPart::MoveUp).x);
        // 名前は開閉のボタンの右から，スイッチの左まで
        let (name, _) = placement.labels[0];
        assert!(name.x > rect(EntryPart::Expand).max_x());
        assert!(name.max_x() < rect(EntryPart::Toggle).x);
    }

    #[test]
    fn 開いた辞書だけ中身を置き_選んだアプリの行を並べる() {
        let entries = [
            entry("a", model::ALWAYS, &[]),
            entry("b", model::APPS, &["code.exe", "notepad.exe"]),
        ];
        let closed = place(
            DictionaryList::Imported,
            &entries,
            None,
            (0.0, 0.0, 800.0),
            &width,
        );
        let open = place(
            DictionaryList::Imported,
            &entries,
            Some(1),
            (0.0, 0.0, 800.0),
            &width,
        );
        assert!(parts_of(&open, 0).len() == 4);
        assert_eq!(
            parts_of(&open, 1),
            vec![
                EntryPart::Expand,
                EntryPart::Toggle,
                EntryPart::MoveUp,
                EntryPart::MoveDown,
                EntryPart::Name,
                EntryPart::Field,
                EntryPart::Condition,
                EntryPart::RemoveApp(0),
                EntryPart::RemoveApp(1),
                EntryPart::AddApp,
                EntryPart::Reimport,
                EntryPart::Remove,
            ]
        );
        // 名前・分野・使う場面・アプリ 2 つ・アプリを追加・再読み込みと削除の 7 行
        assert_eq!(open.height, closed.height + size::ROW_HEIGHT * 7.0);
        assert!(open
            .labels
            .iter()
            .any(|(_, label)| *label == Label::App(1, 1)));
        // 部品はカードの中に収まる
        for (_, _, rect) in &open.parts {
            assert!(rect.x >= size::CARD_PADDING_X);
            assert!(rect.max_x() <= 800.0 - size::CARD_PADDING_X + 0.01);
            assert!(rect.max_y() <= open.height);
        }
        // 使う場面が選んだアプリでなければアプリの行を置かない
        let always = place(
            DictionaryList::Imported,
            &entries,
            Some(0),
            (0.0, 0.0, 800.0),
            &width,
        );
        assert!(!parts_of(&always, 0).contains(&EntryPart::AddApp));
    }

    #[test]
    fn 連想の辞書の中身は名前と再読み込みと削除() {
        let entries = [entry("w", model::ALWAYS, &[])];
        let placement = place(
            DictionaryList::Association,
            &entries,
            Some(0),
            (0.0, 0.0, 600.0),
            &width,
        );
        assert_eq!(
            parts_of(&placement, 0)[4..],
            [EntryPart::Name, EntryPart::Reimport, EntryPart::Remove]
        );
    }

    #[test]
    fn 辞書が無ければ文を一行だけ出す() {
        let placement = place(
            DictionaryList::Imported,
            &[],
            None,
            (0.0, 0.0, 600.0),
            &width,
        );
        assert_eq!(placement.labels.len(), 1);
        assert_eq!(placement.labels[0].1, Label::Empty);
        assert!(placement.parts.is_empty());
        assert_eq!(placement.height, size::ROW_HEIGHT);
    }

    #[test]
    fn 端の辞書は動かせず_同梱の辞書は消せない() {
        let mut rows = Rows::new(DictionaryList::Association);
        let mut bundled = entry("w", model::ALWAYS, &[]);
        bundled.is_bundled = true;
        rows.set_entries(vec![bundled, entry("x", model::ALWAYS, &[])], 0.0);
        assert!(!rows.part_enabled(0, EntryPart::MoveUp));
        assert!(rows.part_enabled(0, EntryPart::MoveDown));
        assert!(rows.part_enabled(1, EntryPart::MoveUp));
        assert!(!rows.part_enabled(1, EntryPart::MoveDown));
        assert!(!rows.part_enabled(0, EntryPart::Remove));
        assert!(!rows.part_enabled(0, EntryPart::Reimport));
        assert!(rows.part_enabled(1, EntryPart::Reimport));
        rows.busy = true;
        assert!(!rows.part_enabled(1, EntryPart::Reimport));
        assert!(rows.part_enabled(1, EntryPart::Remove));
    }

    #[test]
    fn 開いた辞書は並べ替えても開いたまま_消えたら閉じる() {
        let mut rows = Rows::new(DictionaryList::Imported);
        let a = entry("a", model::ALWAYS, &[]);
        let b = entry("b", model::ALWAYS, &[]);
        rows.set_entries(vec![a.clone(), b.clone()], 0.0);
        rows.expanded = Some("b".into());
        assert_eq!(rows.expanded_index(), Some(1));
        rows.set_entries(vec![b.clone(), a.clone()], 0.0);
        assert_eq!(rows.expanded_index(), Some(0));
        assert_eq!(rows.expand_label(0), dictionaries::HIDE_DETAILS);
        assert_eq!(rows.expand_label(1), dictionaries::SHOW_DETAILS);
        let closed = rows.height();
        rows.set_entries(vec![a], 0.0);
        assert_eq!(rows.expanded, None);
        assert!(rows.height() < closed);
    }

    #[test]
    fn オン_オフが変わった辞書だけスイッチを動かす() {
        let mut rows = Rows::new(DictionaryList::Imported);
        let a = entry("a", model::ALWAYS, &[]);
        let b = entry("b", model::ALWAYS, &[]);
        rows.set_entries(vec![a.clone(), b.clone()], 0.0);
        assert!(!rows.animating(0.0));
        let mut off = b.clone();
        off.is_enabled = false;
        rows.set_entries(vec![a, off], 1.0);
        assert!(!rows.knobs[0].running(1.0));
        assert!(rows.knobs[1].running(1.0));
        assert_eq!(rows.knobs[1].target(), 0.0);
    }
}
