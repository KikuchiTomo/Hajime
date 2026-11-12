#![forbid(unsafe_code)]

//! 辞書のファイルを取り込む前に中身を見せるシート(macOS の ImportPreviewSheet)．WinUI の ContentDialog と同じく，
//! 窓の中身を暗くして真ん中に出す．上にファイル名と見分けた形のタグ，名詞にする行・読めない行があればその行だけを出す
//! 切り替え，列の見出しと行の表(表の中で送る)，下の帯にキャンセルと「〇語を取り込む」を置く．
//! 「取り込む」を押すまで何も登録しない．置き場所は窓の中の座標(タイトルバーの下の DIP)

use super::paint::{self, ButtonKind, Canvas, Measure, State, TextLayout, TextStyle};
use super::sheet::SheetFrame;
use super::theme::Color;
use crate::layout::Rect;
use crate::pages::DictionaryList;
use crate::strings::{import_preview as text, settings};
use crate::ui::scroll::Scroller;
use ipc::{ImportColumn, ImportKind, ImportPreview, ImportPreviewRow, ImportRowStatus};
use tokens::opacity::settings_windows as opacity;
use tokens::size::settings::{
    IMPORT_PREVIEW_KIND_COLUMN_WIDTH, IMPORT_PREVIEW_LINE_COLUMN_WIDTH,
    IMPORT_PREVIEW_TABLE_HEIGHT, IMPORT_PREVIEW_WIDTH,
};
use tokens::size::settings_windows as size;
use tokens::size::{part, space};

/// 「取り込む」を押したときにする取り込み
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ImportAction {
    /// 登録した単語に足す
    UserDictionary,
    /// 取り込んだ辞書・連想の辞書として足す(replacing は取り込み直す辞書)
    Dictionary {
        list: DictionaryList,
        replacing: Option<String>,
    },
}

impl ImportAction {
    pub fn kind(&self) -> ImportKind {
        match self {
            ImportAction::UserDictionary => ImportKind::UserDictionary,
            ImportAction::Dictionary {
                list: DictionaryList::Imported,
                ..
            } => ImportKind::Dictionary,
            ImportAction::Dictionary {
                list: DictionaryList::Association,
                ..
            } => ImportKind::Association,
        }
    }
}

/// 取り込む前に中身を見せているファイル
#[derive(Debug, Clone, PartialEq)]
pub struct PendingImport {
    pub path: String,
    pub preview: ImportPreview,
    pub action: ImportAction,
}

impl PendingImport {
    pub fn file_name(&self) -> String {
        std::path::Path::new(&self.path.replace('\\', "/"))
            .file_name()
            .map_or_else(
                || self.path.clone(),
                |name| name.to_string_lossy().into_owned(),
            )
    }
}

/// 見せる行
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Filter {
    All,
    Defaulted,
    Unreadable,
}

/// シートの中の押せる部品(フォーカスの順)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ImportPart {
    /// 見せる行の切り替え(filters の番号)
    Filter(usize),
    /// 行の表(矢印で送る)
    Table,
    Cancel,
    Import,
}

/// 出しているシート
pub struct ImportSheet {
    pub pending: PendingImport,
    pub filter: Filter,
    pub focus: ImportPart,
    /// キーボードで動かしたあと(フォーカスの印を出す)
    pub focus_visible: bool,
    pub hover: Option<ImportPart>,
    pub pressed: Option<ImportPart>,
    /// 表の送り
    pub scroll: Scroller,
}

impl ImportSheet {
    pub fn new(pending: PendingImport) -> Self {
        let focus = if pending.preview.importable > 0 {
            ImportPart::Import
        } else {
            ImportPart::Cancel
        };
        Self {
            pending,
            filter: Filter::All,
            focus,
            focus_visible: false,
            hover: None,
            pressed: None,
            scroll: Scroller::default(),
        }
    }

    /// 見せる行の切り替え．名詞にする行か読めない行があるときだけ出す
    pub fn filters(&self) -> Vec<(Filter, String)> {
        let preview = &self.pending.preview;
        if preview.defaulted == 0 && preview.unreadable == 0 {
            return Vec::new();
        }
        let mut filters = vec![(
            Filter::All,
            text::filter(text::ALL, preview.importable + preview.unreadable),
        )];
        if preview.defaulted > 0 {
            filters.push((
                Filter::Defaulted,
                text::filter(text::DEFAULTED, preview.defaulted),
            ));
        }
        if preview.unreadable > 0 {
            filters.push((
                Filter::Unreadable,
                text::filter(text::UNREADABLE, preview.unreadable),
            ));
        }
        filters
    }

    /// 切り替えで選んだ行
    pub fn rows(&self) -> Vec<&ImportPreviewRow> {
        self.pending
            .preview
            .rows
            .iter()
            .filter(|row| match self.filter {
                Filter::All => true,
                Filter::Defaulted => row.status == ImportRowStatus::DefaultedWordClass,
                Filter::Unreadable => row.status == ImportRowStatus::Unreadable,
            })
            .collect()
    }

    /// 切り替えの index 番目を選ぶ(表は先頭に戻す)
    pub fn set_filter(&mut self, index: usize) {
        if let Some((filter, _)) = self.filters().get(index) {
            self.filter = *filter;
            self.scroll.jump_to(0.0);
        }
    }

    /// 部品を使えるか(取り込めるものが無ければ取り込めない)
    pub fn enabled(&self, part: ImportPart) -> bool {
        part != ImportPart::Import || self.pending.preview.importable > 0
    }

    /// 部品の名前(読み上げとボタンの字)
    pub fn name(&self, part: ImportPart) -> String {
        match part {
            ImportPart::Filter(index) => self
                .filters()
                .get(index)
                .map(|(_, label)| label.clone())
                .unwrap_or_default(),
            ImportPart::Table => self.pending.file_name(),
            ImportPart::Cancel => settings::CANCEL.to_string(),
            ImportPart::Import => {
                text::import_button(self.pending.preview.importable, self.pending.action.kind())
            }
        }
    }
}

/// シートの置き場所(窓の中の座標)
#[derive(Debug, Clone, PartialEq)]
pub struct ImportLayout {
    pub dialog: Rect,
    pub footer: Rect,
    /// ファイル名と，見分けた形のタグ
    pub title: Rect,
    pub tag: Rect,
    /// 列の見出し(表の上の端)と，行を並べるところ
    pub header: Rect,
    pub body: Rect,
    /// 列(None は行の番号)の左端と幅
    pub columns: Vec<(Option<ImportColumn>, f32, f32)>,
    pub parts: Vec<(ImportPart, Rect)>,
}

fn button_width(label: &str, measure: &dyn Measure) -> f32 {
    (measure.width(label, TextStyle::Body) + size::BUTTON_PADDING_X * 2.0)
        .ceil()
        .max(size::BUTTON_WIDTH)
}

impl ImportLayout {
    /// 窓の大きさ(タイトルバーの下)に合わせて真ん中に置く
    pub fn new(window: (f32, f32), sheet: &ImportSheet, measure: &dyn Measure) -> Self {
        let (window_width, window_height) = window;
        let padding = space::PAGE;
        let width = IMPORT_PREVIEW_WIDTH.min((window_width - size::PAGE_PADDING_X * 2.0).max(0.0));
        let inner = (width - padding * 2.0).max(0.0);
        let filters = sheet.filters();
        let title_height = size::BODY_LINE_HEIGHT;
        let filter_height = if filters.is_empty() {
            0.0
        } else {
            part::FIELD_HEIGHT + space::SECTION
        };
        // 窓が低いときは表を縮める(本文と下の帯の上下の余白・ボタン・題・切り替えを除いた高さ)
        let around = padding * 2.0;
        let table_height = IMPORT_PREVIEW_TABLE_HEIGHT.min(
            (window_height - around - around - size::CONTROL_HEIGHT - title_height - filter_height)
                .max(size::TABLE_HEADER_HEIGHT * 2.0),
        );
        let body_height =
            padding * 2.0 + title_height + space::SECTION + filter_height + table_height;
        let footer_height = size::CONTROL_HEIGHT + padding * 2.0;
        let height = body_height + footer_height;
        let x = ((window_width - width) / 2.0).max(0.0).round();
        let y = ((window_height - height) / 2.0).max(0.0).round();
        let dialog = Rect::new(x, y, width, height);
        let left = x + padding;
        let mut top = y + padding;
        // ファイル名と形のタグ(ファイル名は残りの幅で切る)
        let format = text::format(sheet.pending.preview.format);
        let tag_width =
            (measure.width(format, TextStyle::Caption) + part::TAG_PADDING_X * 2.0).ceil();
        let name_width = measure
            .width(&sheet.pending.file_name(), TextStyle::Body)
            .ceil()
            .min((inner - tag_width - space::GROUP).max(0.0));
        let title = Rect::new(left, top, name_width, title_height);
        let tag = Rect::new(
            title.max_x() + space::GROUP,
            top + (title_height - part::TAG_HEIGHT) / 2.0,
            tag_width,
            part::TAG_HEIGHT,
        );
        top += title_height + space::SECTION;
        let mut parts = Vec::new();
        // 見せる行の切り替え(ページの上の切り替えと同じ形．左から隙間なく並べる)
        let mut filter_x = left;
        for (index, (_, label)) in filters.iter().enumerate() {
            let segment =
                (measure.width(label, TextStyle::Body) + part::FIELD_PADDING_X * 2.0).ceil();
            parts.push((
                ImportPart::Filter(index),
                Rect::new(filter_x, top, segment, part::FIELD_HEIGHT),
            ));
            filter_x += segment;
        }
        top += filter_height;
        let table = Rect::new(left, top, inner, table_height);
        parts.push((ImportPart::Table, table));
        let header = Rect::new(left, top, inner, size::TABLE_HEADER_HEIGHT);
        let body = Rect::new(
            left,
            header.max_y(),
            inner,
            (table_height - size::TABLE_HEADER_HEIGHT).max(0.0),
        );
        // 列: 行の番号と品詞は決まった幅，ほかは中身の長さで配る(空いている列は見出しの幅まで縮めて，長い列に回す)
        let columns_in = sheet.pending.preview.columns.clone();
        let content = inner - size::FIELD_PADDING_X * 2.0;
        let gaps = space::GROUP * columns_in.len() as f32;
        let fixed = if columns_in.contains(&ImportColumn::WordClass) {
            IMPORT_PREVIEW_KIND_COLUMN_WIDTH
        } else {
            0.0
        };
        let flexible: Vec<usize> = (0..columns_in.len())
            .filter(|index| columns_in[*index] != ImportColumn::WordClass)
            .collect();
        let natural: Vec<f32> = flexible
            .iter()
            .map(|index| {
                sheet
                    .pending
                    .preview
                    .rows
                    .iter()
                    .map(|row| {
                        row.cells
                            .get(*index)
                            .map_or(0.0, |cell| measure.width(cell, TextStyle::Body).ceil())
                    })
                    .fold(0.0, f32::max)
            })
            .collect();
        let minimum: Vec<f32> = flexible
            .iter()
            .map(|index| {
                measure
                    .width(column_title(Some(columns_in[*index])), TextStyle::Caption)
                    .ceil()
            })
            .collect();
        let available = content - IMPORT_PREVIEW_LINE_COLUMN_WIDTH - gaps - fixed;
        let mut shares = distribute(&natural, &minimum, available).into_iter();
        let mut column_x = left + size::FIELD_PADDING_X;
        let mut columns = vec![(None, column_x, IMPORT_PREVIEW_LINE_COLUMN_WIDTH)];
        column_x += IMPORT_PREVIEW_LINE_COLUMN_WIDTH + space::GROUP;
        for column in columns_in {
            let width = if column == ImportColumn::WordClass {
                IMPORT_PREVIEW_KIND_COLUMN_WIDTH
            } else {
                shares.next().unwrap_or(0.0)
            };
            columns.push((Some(column), column_x, width));
            column_x += width + space::GROUP;
        }
        // キャンセルと取り込むは下の帯を同じ幅で分ける(WinUI の ContentDialog)
        let footer = Rect::new(x, y + body_height, width, footer_height);
        let button = ((inner - size::CONTROL_GAP) / 2.0)
            .max(0.0)
            .max(button_width(&sheet.name(ImportPart::Import), measure).min(inner / 2.0));
        let button_y = footer.y + padding;
        parts.push((
            ImportPart::Cancel,
            Rect::new(left, button_y, button, size::CONTROL_HEIGHT),
        ));
        parts.push((
            ImportPart::Import,
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
            title,
            tag,
            header,
            body,
            columns,
            parts,
        }
    }

    pub fn rect(&self, part: ImportPart) -> Option<Rect> {
        self.parts
            .iter()
            .find(|(candidate, _)| *candidate == part)
            .map(|(_, rect)| *rect)
    }

    /// (x, y) にある部品
    pub fn hit(&self, x: f32, y: f32) -> Option<ImportPart> {
        self.parts
            .iter()
            .find(|(_, rect)| x >= rect.x && x < rect.max_x() && y >= rect.y && y < rect.max_y())
            .map(|(part, _)| *part)
    }

    /// フォーカスで巡る部品
    pub fn order(&self) -> Vec<ImportPart> {
        self.parts.iter().map(|(part, _)| *part).collect()
    }

    /// 表の中身の高さ(送りの幅)
    pub fn content_height(sheet: &ImportSheet) -> f32 {
        sheet.rows().len() as f32 * size::TABLE_ROW_HEIGHT
    }
}

/// 列の見出し(None は行の番号)
fn column_title(column: Option<ImportColumn>) -> &'static str {
    match column {
        None => text::LINE,
        Some(ImportColumn::Reading) => settings::READING,
        Some(ImportColumn::Word) => settings::WORD,
        Some(ImportColumn::WordClass) => settings::WORD_CLASS,
        Some(ImportColumn::Comment) => settings::COMMENT,
        Some(ImportColumn::Meaning) => text::MEANING,
        Some(ImportColumn::Words) => text::WORDS,
    }
}

/// 列の幅を中身の長さで配る(core の ColumnWidths.distribute と同じ)．natural は中身のいちばん長い幅，
/// minimum は縮めてもよい幅(見出しの幅)．収まるときは余りを中身の長さの割合で足し，収まらないときは
/// 最小を超える分を同じ割合で削る．最小の合計も収まらなければ最小を割合で縮める
pub fn distribute(natural: &[f32], minimum: &[f32], available: f32) -> Vec<f32> {
    if natural.is_empty() || natural.len() != minimum.len() {
        return Vec::new();
    }
    let wanted: Vec<f32> = natural
        .iter()
        .zip(minimum)
        .map(|(a, b)| a.max(*b))
        .collect();
    let total: f32 = wanted.iter().sum();
    if total <= available {
        let extra = available - total;
        return wanted
            .iter()
            .map(|width| {
                if total > 0.0 {
                    width + extra * width / total
                } else {
                    available / wanted.len() as f32
                }
            })
            .collect();
    }
    let floor: f32 = minimum.iter().sum();
    if floor >= available {
        return minimum
            .iter()
            .map(|least| {
                if floor > 0.0 {
                    available * least / floor
                } else {
                    0.0
                }
            })
            .collect();
    }
    let shrinkable = total - floor;
    let cut = total - available;
    wanted
        .iter()
        .zip(minimum)
        .map(|(width, least)| width - cut * (width - least) / shrinkable)
        .collect()
}

/// 窓の中身を暗くし，シートを描く
pub fn paint(
    canvas: &mut dyn Canvas,
    sheet: &ImportSheet,
    layout: &ImportLayout,
    frame: &SheetFrame,
    now: f64,
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
    // 下の帯は窓の背景の色(WinUI の ContentDialog の CommandSpace)
    canvas.push_clip(layout.footer);
    canvas.fill_round(dialog, radius, Color::from(palette.background));
    canvas.pop_clip();
    canvas.fill_rect(
        Rect::new(dialog.x, layout.footer.y, dialog.width, 1.0),
        Color::from(palette.card_stroke),
    );
    canvas.stroke_round(dialog, radius, 1.0, Color::from(palette.flyout_stroke));
    let text_color = Color::from(palette.text);
    let secondary = Color::from(palette.text_secondary);
    // ファイル名と形のタグ
    canvas.text(
        layout.title,
        &sheet.pending.file_name(),
        TextStyle::Body,
        text_color,
        TextLayout::LINE,
    );
    canvas.fill_round(
        layout.tag,
        part::TAG_RADIUS,
        text_color.with_alpha(tokens::opacity::settings::SUBTLE_SELECTED),
    );
    canvas.text(
        layout.tag,
        text::format(sheet.pending.preview.format),
        TextStyle::Caption,
        secondary,
        TextLayout::CENTER,
    );
    let state = |part: ImportPart| State {
        enabled: sheet.enabled(part),
        hover: if sheet.hover == Some(part) && sheet.enabled(part) {
            frame.hover
        } else {
            0.0
        },
        pressed: sheet.pressed == Some(part),
        focus_visible: sheet.focus_visible && sheet.focus == part,
    };
    let filters = sheet.filters();
    for (part, rect) in &layout.parts {
        match *part {
            ImportPart::Filter(index) => {
                let (filter, label) = &filters[index];
                paint::segment(
                    canvas,
                    theme,
                    *rect,
                    label,
                    *filter == sheet.filter,
                    state(*part),
                );
            }
            ImportPart::Table => paint_table(canvas, sheet, layout, frame, now, state(*part)),
            ImportPart::Cancel | ImportPart::Import => {
                let kind = if *part == ImportPart::Import {
                    ButtonKind::Accent
                } else {
                    ButtonKind::Standard
                };
                paint::button(canvas, theme, *rect, &sheet.name(*part), kind, state(*part));
            }
        }
    }
}

/// 列の見出しと行．品詞を名詞にする行は品詞を注意の色で，読めない行は行の番号に注意の印を付けて薄く出す
fn paint_table(
    canvas: &mut dyn Canvas,
    sheet: &ImportSheet,
    layout: &ImportLayout,
    frame: &SheetFrame,
    now: f64,
    state: State,
) {
    let theme = frame.theme;
    let palette = &theme.palette;
    let Some(table) = layout.rect(ImportPart::Table) else {
        return;
    };
    canvas.fill_round(table, size::CONTROL_RADIUS, Color::from(palette.control));
    let secondary = Color::from(palette.text_secondary);
    let caution = Color::from(palette.caution);
    for (column, x, width) in &layout.columns {
        let title = column_title(*column);
        let layout_kind = if column.is_none() {
            TextLayout::TRAILING
        } else {
            TextLayout::LINE
        };
        canvas.text(
            Rect::new(*x, layout.header.y, *width, layout.header.height),
            title,
            TextStyle::Caption,
            secondary,
            layout_kind,
        );
    }
    canvas.fill_rect(
        Rect::new(table.x, layout.header.max_y() - 1.0, table.width, 1.0),
        Color::from(palette.card_stroke),
    );
    let body = layout.body;
    let offset = sheet.scroll.offset(now);
    canvas.push_clip(body);
    for (index, row) in sheet.rows().iter().enumerate() {
        let top = body.y + index as f32 * size::TABLE_ROW_HEIGHT - offset;
        if top + size::TABLE_ROW_HEIGHT < body.y || top > body.max_y() {
            continue;
        }
        if index % 2 == 1 {
            canvas.fill_rect(
                Rect::new(
                    table.x + part::STROKE,
                    top,
                    table.width - part::STROKE * 2.0,
                    size::TABLE_ROW_HEIGHT,
                ),
                Color::from(palette.text).with_alpha(opacity::TABLE_STRIPE),
            );
        }
        let unreadable = row.status == ImportRowStatus::Unreadable;
        let color = if unreadable {
            secondary
        } else {
            Color::from(palette.text)
        };
        for (column_index, (column, x, width)) in layout.columns.iter().enumerate() {
            let cell = Rect::new(*x, top, *width, size::TABLE_ROW_HEIGHT);
            match column {
                None => {
                    canvas.text(
                        cell,
                        &row.line.to_string(),
                        TextStyle::Body,
                        secondary,
                        TextLayout::TRAILING,
                    );
                    if unreadable {
                        let digits = canvas.width(&row.line.to_string(), TextStyle::Body);
                        let glyph = size::CHEVRON_SIZE;
                        canvas.text(
                            Rect::new(
                                cell.max_x() - digits - space::INLINE - glyph,
                                top,
                                glyph,
                                size::TABLE_ROW_HEIGHT,
                            ),
                            theme.glyphs.warning,
                            TextStyle::IconSmall,
                            caution,
                            TextLayout::CENTER,
                        );
                    }
                }
                Some(column) => {
                    let value = row.cells.get(column_index - 1).map_or("", String::as_str);
                    let (shown, cell_color) = if *column == ImportColumn::WordClass && !unreadable {
                        let label = crate::options::label_of(crate::options::WORD_CLASSES, value);
                        let tone = if row.status == ImportRowStatus::DefaultedWordClass {
                            caution
                        } else {
                            color
                        };
                        (label, tone)
                    } else {
                        (value, color)
                    };
                    canvas.text(cell, shown, TextStyle::Body, cell_color, TextLayout::LINE);
                }
            }
        }
    }
    canvas.pop_clip();
    super::page::scrollbar(canvas, theme, body, &sheet.scroll, now);
    canvas.stroke_round(
        table,
        size::CONTROL_RADIUS,
        1.0,
        Color::from(palette.control_stroke),
    );
    if state.focus_visible {
        paint::focus_ring(canvas, theme, table, size::CONTROL_RADIUS);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ipc::ImportFormat;

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

    fn sheet(defaulted: u32, unreadable: u32, importable: u32) -> ImportSheet {
        let row = |line: u32, status: ImportRowStatus| ImportPreviewRow {
            line,
            cells: vec![
                "かいしゃ".into(),
                "会社".into(),
                "noun".into(),
                String::new(),
            ],
            status,
        };
        ImportSheet::new(PendingImport {
            path: "C:\\辞書\\ユーザー辞書.txt".into(),
            preview: ImportPreview {
                format: ImportFormat::TabSeparated,
                columns: vec![
                    ImportColumn::Reading,
                    ImportColumn::Word,
                    ImportColumn::WordClass,
                    ImportColumn::Comment,
                ],
                rows: vec![
                    row(1, ImportRowStatus::Ok),
                    row(2, ImportRowStatus::DefaultedWordClass),
                    row(3, ImportRowStatus::Unreadable),
                ],
                importable,
                defaulted,
                unreadable,
            },
            action: ImportAction::UserDictionary,
        })
    }

    #[test]
    fn シートは窓の真ん中に置き_部品と列はシートに収まる() {
        let sheet = sheet(1, 1, 2);
        let layout = ImportLayout::new((1000.0, 800.0), &sheet, &Fixed);
        let dialog = layout.dialog;
        assert_eq!(dialog.width, IMPORT_PREVIEW_WIDTH);
        assert!((dialog.x + dialog.width / 2.0 - 500.0).abs() <= 1.0);
        for (_, rect) in &layout.parts {
            assert!(rect.x >= dialog.x && rect.max_x() <= dialog.max_x() + 0.01);
            assert!(rect.y >= dialog.y && rect.max_y() <= dialog.max_y() + 0.01);
        }
        let table = layout.rect(ImportPart::Table).expect("表");
        let (_, last_x, last_width) = layout.columns.last().copied().expect("列");
        assert!(last_x + last_width <= table.max_x());
        // 行の番号・読み・単語・品詞・コメントの 5 列．品詞は決まった幅
        assert_eq!(layout.columns.len(), 5);
        assert_eq!(layout.columns[3].2, IMPORT_PREVIEW_KIND_COLUMN_WIDTH);
        // 取り込むは右下(キャンセルの右)
        let cancel = layout.rect(ImportPart::Cancel).expect("キャンセル");
        let import = layout.rect(ImportPart::Import).expect("取り込む");
        assert!(import.x > cancel.max_x());
        assert_eq!(import.max_x(), table.max_x());
    }

    #[test]
    fn 名詞にする行と読めない行があるときだけ切り替えを出し_選んだ行だけを並べる() {
        let mut problems = sheet(1, 1, 2);
        assert_eq!(problems.filters().len(), 3);
        problems.set_filter(2);
        assert_eq!(problems.filter, Filter::Unreadable);
        assert_eq!(problems.rows().len(), 1);
        let clean = sheet(0, 0, 3);
        assert!(clean.filters().is_empty());
        let layout = ImportLayout::new((1000.0, 800.0), &clean, &Fixed);
        assert!(!layout
            .order()
            .iter()
            .any(|part| matches!(part, ImportPart::Filter(_))));
    }

    #[test]
    fn 取り込める行が無ければ取り込めず_キャンセルにフォーカスを置く() {
        let empty = sheet(0, 3, 0);
        assert!(!empty.enabled(ImportPart::Import));
        assert_eq!(empty.focus, ImportPart::Cancel);
        assert_eq!(sheet(0, 0, 3).focus, ImportPart::Import);
    }

    #[test]
    fn 列の幅は中身の長さで配り_空いている列は見出しの幅にする() {
        let fits = distribute(&[100.0, 200.0, 0.0], &[40.0, 40.0, 60.0], 720.0);
        assert!((fits.iter().sum::<f32>() - 720.0).abs() < 0.01);
        assert!(fits[1] > fits[0] && fits[2] < fits[0]);
        let shrinks = distribute(&[300.0, 500.0, 60.0], &[40.0, 40.0, 60.0], 600.0);
        assert!((shrinks.iter().sum::<f32>() - 600.0).abs() < 0.01);
        assert_eq!(shrinks[2], 60.0);
        assert_eq!(
            distribute(&[300.0, 300.0], &[100.0, 300.0], 200.0),
            vec![50.0, 150.0]
        );
    }

    #[test]
    fn ファイル名は_windows_のパスの最後の部分() {
        assert_eq!(sheet(0, 0, 1).pending.file_name(), "ユーザー辞書.txt");
    }
}
