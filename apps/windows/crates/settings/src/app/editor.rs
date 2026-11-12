#![forbid(unsafe_code)]

//! カスタムテーマを編集する画面(macOS の CustomThemeEditor のシート)．設定の窓のページの場所に重ねて開く．
//! 分岐図の見本を上に留め，名前・読みやすさ・色・形をその下で送り(pages::theme_editor の行をページと同じ部品で描く)，
//! 複製・キャンセル・保存のボタンを下に留める．開いているあいだは左の一覧と検索を使えなくする(ほかのページに移らない)．
//! 値はテーマの下書きに書き，「保存」を押したときだけ設定のファイルに書く(キャンセルすれば元のまま)

use super::actions::After;
use super::ffi;
use super::page::{EditorAction, PageView};
use super::paint::{self, Canvas, Measure, State, TextStyle};
use super::theme::{Color, Theme};
use super::window::App;
use crate::layout::{self, Metrics, Rect, TextKind};
use crate::pages::{self, Page};
use crate::strings::{more, settings};
use crate::themes;
use serde_json::Value;
use tokens::size::settings as size_settings;
use tokens::size::settings_windows as size;

/// 開いている編集の画面
pub struct ThemeEditor {
    /// 編集しているテーマ(設定のファイルの customThemes の 1 つと同じ形)
    pub draft: Value,
    /// まだ保存していない新しいテーマか(複製のボタンを出さない)
    pub is_new: bool,
    /// 開く前の外観のページの送りの位置(閉じたら戻す)
    pub return_scroll: f32,
}

/// 編集の画面の置き場所(窓の中のタイトルバーの下の座標，DIP)
#[derive(Debug, Clone, PartialEq)]
pub struct SheetLayout {
    /// 上に留める見本の帯
    pub band: Rect,
    /// 見本を描く場所(帯の中．まわりに見本の余白をとる)
    pub preview: Rect,
    /// 下に留めるボタンの帯
    pub footer: Rect,
    /// ボタン(フォーカスの順)
    pub buttons: Vec<(EditorAction, Rect)>,
}

/// ボタンの名前(macOS の CustomThemeEditor と同じ)
pub fn label(action: EditorAction) -> &'static str {
    match action {
        EditorAction::Duplicate => more::DUPLICATE_THEME,
        EditorAction::Cancel => settings::CANCEL,
        EditorAction::Save => settings::SAVE,
    }
}

/// ボタンの幅を測る(layout::button_width は Metrics で測る)
struct Widths<'a>(&'a dyn Measure);

impl Metrics for Widths<'_> {
    fn lines(&self, _: &str, _: TextKind, _: f32) -> usize {
        1
    }

    fn width(&self, text: &str, _: TextKind) -> f32 {
        self.0.width(text, TextStyle::Body)
    }
}

impl SheetLayout {
    /// left・width はページの場所，height は窓の高さ(タイトルバーの下)．natural は見本を描いた大きさ
    pub fn new(
        (left, width, height): (f32, f32, f32),
        natural: Option<(f32, f32)>,
        is_new: bool,
        measure: &dyn Measure,
    ) -> Self {
        let padding = size_settings::PREVIEW_PADDING;
        let inner = (width - padding * 2.0).max(0.0);
        // 見本は描いた大きさで置き，幅が足りなければ縮める(外観のページの見本と同じ)．
        // 窓が低くて見本が窓の半分より高くなるときは，見本ごと縮めて下の欄を残す
        let shown = natural.map_or(0.0, |natural| layout::preview_height(natural, inner));
        let limit = (height / 2.0 - padding * 2.0).max(0.0);
        let preview_height = shown.min(limit);
        let band = Rect::new(left, 0.0, width, preview_height + padding * 2.0);
        let preview = Rect::new(left + padding, padding, inner, preview_height);
        let footer_height = size::CONTROL_HEIGHT + size::CARD_PADDING_Y * 2.0;
        let footer = Rect::new(
            left,
            (height - footer_height).max(band.max_y()),
            width,
            footer_height,
        );
        // ボタンは行のカードと同じ左右の端にそろえ，複製を左，キャンセルと保存を右に置く(macOS の HStack と Spacer)
        let (content_left, content_width) = layout::content_frame(width);
        let top = footer.y + size::CARD_PADDING_Y;
        let widths = Widths(measure);
        let button = |action: EditorAction, x: f32| {
            let width = layout::button_width(label(action), &widths);
            (action, Rect::new(x, top, width, size::CONTROL_HEIGHT))
        };
        let mut buttons = Vec::new();
        if !is_new {
            buttons.push(button(EditorAction::Duplicate, left + content_left));
        }
        let mut right = left + content_left + content_width;
        let mut trailing = Vec::new();
        for action in [EditorAction::Save, EditorAction::Cancel] {
            let (action, rect) = button(action, 0.0);
            right -= rect.width;
            trailing.push((action, Rect { x: right, ..rect }));
            right -= size::CONTROL_GAP;
        }
        buttons.extend(trailing.into_iter().rev());
        Self {
            band,
            preview,
            footer,
            buttons,
        }
    }

    /// 点(x, y)にあるボタン
    pub fn hit(&self, x: f32, y: f32) -> Option<EditorAction> {
        self.buttons
            .iter()
            .find(|(_, rect)| x >= rect.x && x < rect.max_x() && y >= rect.y && y < rect.max_y())
            .map(|(action, _)| *action)
    }
}

/// ボタンを描くときの状態
pub struct SheetState {
    pub enabled: [bool; 3],
    pub hover: Option<EditorAction>,
    pub pressed: Option<EditorAction>,
    pub focus: Option<EditorAction>,
    pub focus_visible: bool,
}

fn index(action: EditorAction) -> usize {
    match action {
        EditorAction::Duplicate => 0,
        EditorAction::Cancel => 1,
        EditorAction::Save => 2,
    }
}

/// 上に留めた見本の帯と，下に留めたボタンの帯を描く(ページを描いたあと)
pub fn paint_sheet(
    canvas: &mut dyn Canvas,
    theme: &Theme,
    layout: &SheetLayout,
    state: &SheetState,
) {
    let palette = &theme.palette;
    // 見本の帯はカードの地にし(macOS の background.secondary)，下に区切り線を引く
    canvas.fill_rect(layout.band, Color::from(palette.card));
    canvas.preview(layout.preview);
    let line = |y: f32| Rect::new(layout.band.x, y, layout.band.width, 1.0);
    canvas.fill_rect(
        line(layout.band.max_y() - 1.0),
        Color::from(palette.card_stroke),
    );
    canvas.fill_rect(line(layout.footer.y), Color::from(palette.card_stroke));
    for (action, rect) in &layout.buttons {
        let enabled = state.enabled[index(*action)];
        let kind = if *action == EditorAction::Save {
            paint::ButtonKind::Accent
        } else {
            paint::ButtonKind::Standard
        };
        let button_state = State {
            enabled,
            hover: if enabled && state.hover == Some(*action) {
                1.0
            } else {
                0.0
            },
            pressed: enabled && state.pressed == Some(*action),
            focus_visible: state.focus_visible && state.focus == Some(*action),
        };
        paint::button(canvas, theme, *rect, label(*action), kind, button_state);
    }
}

impl App {
    /// 編集の画面の置き場所(開いていなければ None)
    pub(super) fn sheet(&self) -> Option<SheetLayout> {
        let editor = self.editor.as_ref()?;
        let (width, height) = self.size();
        let left = super::window::nav_width(width);
        Some(SheetLayout::new(
            (left, width - left, height),
            self.preview_natural_size(),
            editor.is_new,
            &self.graphics,
        ))
    }

    /// 下のボタンを使えるか(保存は名前があるとき，複製は上限まで作っていないとき)
    pub(super) fn sheet_enabled(&self, action: EditorAction) -> bool {
        let Some(editor) = &self.editor else {
            return false;
        };
        match action {
            EditorAction::Cancel => true,
            EditorAction::Save => {
                !themes::trimmed_name(&editor.draft, self.catalog.limits.theme_name_length)
                    .is_empty()
            }
            EditorAction::Duplicate => self.model.as_ref().is_some_and(|model| {
                themes::entries(model.value(themes::THEMES)).len()
                    < self.catalog.limits.custom_themes
            }),
        }
    }

    pub(super) fn sheet_state(&self) -> SheetState {
        let enabled = [
            EditorAction::Duplicate,
            EditorAction::Cancel,
            EditorAction::Save,
        ]
        .map(|action| self.sheet_enabled(action));
        SheetState {
            enabled,
            hover: self.sheet_hover(),
            pressed: self.sheet_pressed(),
            focus: self.sheet_focus(),
            focus_visible: self.focus_visible(),
        }
    }

    /// 編集の画面を開く(下書き draft．is_new はまだ保存していないテーマ)
    pub(super) fn open_theme_editor(&mut self, draft: Value, is_new: bool) {
        let now = self.now();
        let return_scroll = self.scroll_offset(now);
        let availability = self.availability();
        let Some(font) = &self.field_font else { return };
        let mut pool = std::mem::take(&mut self.pool);
        let view = PageView::with_sections(
            self.window,
            font,
            &mut pool,
            Page::Appearance,
            pages::theme_editor(),
            &self.catalog,
            availability,
        )
        .untitled();
        std::mem::replace(&mut self.view, view).release(&mut pool);
        self.pool = pool;
        self.editor = Some(ThemeEditor {
            draft,
            is_new,
            return_scroll,
        });
        // 開いているあいだは検索を使えなくする(ほかのページに移らない)
        ffi::enable(self.search_window(), false);
        self.reset_page_state(now);
        self.check_draft();
        self.refresh();
        // 名前の欄から打てるようにする(macOS のシートも最初の欄にフォーカスを置く)
        if let Some(first) = self.view.focusable().first().copied() {
            self.focus_page(first);
        }
    }

    /// 編集の画面を閉じて外観のページに戻る(送りの位置も戻す)
    pub(super) fn close_theme_editor(&mut self) {
        let Some(editor) = self.editor.take() else {
            return;
        };
        ffi::enable(self.search_window(), true);
        self.open_page(Page::Appearance);
        self.restore_scroll(editor.return_scroll);
    }

    /// 下書きの値を変える(名前・色・形・書体)．書き換えられない値なら何もしない
    pub(super) fn edit_draft(&mut self, path: &str, value: &Value) -> Option<After> {
        let editor = self.editor.as_mut()?;
        themes::edit(&mut editor.draft, path, value)?;
        self.check_draft();
        self.refresh();
        None
    }

    /// 下書きの読みやすさをエンジンに確かめてもらう(macOS の CustomThemeEditor の lowContrastPairs)
    pub(super) fn check_draft(&mut self) {
        self.extras.theme_issues.clear();
        self.extras.theme_pairs.clear();
        let (Some(model), Some(editor)) = (&self.model, &self.editor) else {
            return;
        };
        let Ok(issues) = model.store().check_custom_theme(&editor.draft) else {
            return;
        };
        self.extras.theme_issues = issues.iter().map(themes::issue_text).collect();
        self.extras.theme_pairs = issues.iter().map(|issue| issue.pair).collect();
    }

    /// 下のボタン(と名前の欄の Enter)
    pub(super) fn editor_action(&mut self, action: EditorAction) -> Option<After> {
        if !self.sheet_enabled(action) {
            return None;
        }
        let limit = self.catalog.limits.custom_themes;
        let name_limit = self.catalog.limits.theme_name_length;
        let editor = self.editor.as_ref()?;
        let theme = match action {
            EditorAction::Cancel => {
                self.close_theme_editor();
                return None;
            }
            EditorAction::Save => editor.draft.clone(),
            // 今の下書きを別の新しいテーマとして保存する(元のテーマは変えない)
            EditorAction::Duplicate => {
                let name: String =
                    more::copy_name(&themes::trimmed_name(&editor.draft, name_limit))
                        .chars()
                        .take(name_limit)
                        .collect();
                let mut copy = editor.draft.clone();
                themes::edit(&mut copy, themes::NAME, &Value::String(name))?;
                if let Some(element) = copy.as_object_mut() {
                    element.insert(
                        "id".into(),
                        Value::String(themes::new_id(super::actions::seed())),
                    );
                }
                copy
            }
        };
        let model = self.model.as_mut()?;
        let changed = match themes::saved(model.value(themes::THEMES), &theme, limit, name_limit) {
            Ok(changed) => changed,
            Err(themes::SaveError::Name) => {
                return Some(After::Message {
                    text: more::INVALID_THEME.into(),
                    warning: true,
                })
            }
            Err(themes::SaveError::Full) => return Some(After::Notice(more::themes_full(limit))),
        };
        let id = theme.get("id").cloned().unwrap_or(Value::Null);
        // 保存したテーマを使う(macOS の saveCustomTheme)
        if let Err(error) = model.set_all(&[(themes::THEMES, changed), (themes::ACTIVE, id)]) {
            return self.failure(error);
        }
        self.close_theme_editor();
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 全角を 1 文字ぶん，本文の大きさで測る(テスト)
    struct Fixed;

    impl Measure for Fixed {
        fn width(&self, text: &str, _: TextStyle) -> f32 {
            text.chars().count() as f32 * size::BODY_FONT_SIZE
        }

        fn wrapped_height(&self, _: &str, _: TextStyle, _: f32) -> f32 {
            size::BODY_LINE_HEIGHT
        }
    }

    #[test]
    fn 見本を上に_ボタンを下に置く() {
        let layout = SheetLayout::new((280.0, 720.0, 668.0), Some((400.0, 200.0)), false, &Fixed);
        let padding = size_settings::PREVIEW_PADDING;
        assert_eq!(layout.preview.height, 200.0);
        assert_eq!(layout.band.height, 200.0 + padding * 2.0);
        assert_eq!(layout.footer.max_y(), 668.0);
        let actions: Vec<EditorAction> = layout.buttons.iter().map(|(action, _)| *action).collect();
        assert_eq!(
            actions,
            vec![
                EditorAction::Duplicate,
                EditorAction::Cancel,
                EditorAction::Save
            ]
        );
        // 保存は右の端，キャンセルはその左
        let (left, width) = layout::content_frame(720.0);
        let save = layout.buttons[2].1;
        let cancel = layout.buttons[1].1;
        assert_eq!(save.max_x(), 280.0 + left + width);
        assert!(cancel.max_x() < save.x);
        assert_eq!(
            layout.hit(save.x + 1.0, save.y + 1.0),
            Some(EditorAction::Save)
        );
        assert_eq!(layout.hit(save.x + 1.0, layout.band.y), None);
        // 新しいテーマは複製を出さない
        let new = SheetLayout::new((280.0, 720.0, 668.0), Some((400.0, 200.0)), true, &Fixed);
        assert_eq!(new.buttons.len(), 2);
    }

    #[test]
    fn 低い窓では見本を縮めて下の欄を残す() {
        let layout = SheetLayout::new((0.0, 720.0, 400.0), Some((400.0, 300.0)), true, &Fixed);
        assert!(layout.band.max_y() <= 200.0);
        assert!(layout.footer.y > layout.band.max_y());
    }
}
