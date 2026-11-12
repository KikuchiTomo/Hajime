#![forbid(unsafe_code)]

//! パレットの窓の部品の位置(DIP)と，押した位置の対象(macOS の PaletteView と core の PaletteWindowLayout と同じ決め方)．
//! 描く側(palette::scene)と押した位置を調べる側が同じ計算を使う．
//! 顔文字は，マス目の幅を 1 行のマスの数(cells_per_row)で割った広いマスに並べる．
//!
//! 余白は間隔の段階(design/tokens の size.space)だけで決める．
//! - 窓の内側の余白は上下左右とも padding(窓の縁の内側から．角丸のテーマは縁の線，platinum と desk は立体の縁)
//! - 区画(探す欄 → タブ → マス目 → 区切り → 説明 → 区切り → 足元)のあいだは section-gap．区切りの線の上と下も同じ
//! - まとまりのあいだ(探す欄と種類の切り替え，タブとマスの見出し，マス目とスクロールの位置の線)は group-gap，
//!   まとまりの中(マスの見出しとマス目)は item-gap
//! - 中身の右の端は 1 か所(探す欄・種類の切り替え・区切りの線・スクロールの位置の線・肌の色のボタンの右の端)
//!
//! 窓の大きさは列数・行数・マスの大きさ・説明に出す項目の設定と種類で決め，選んでいる文字では変えない．
//! 説明の欄は種類ごとに出る行の分の高さにし，いちばん高い種類(絵文字)との差は，core がマス目の行に回す(visible_rows に足してある)．
//! 回しきれない端の高さは余白に回さず，窓をその分だけ低くする．区切りの線の上と下はどの種類でも同じ

use super::emoji::SKIN_TONES;
use super::preview;
use crate::geometry::Frame;
use crate::scene::Measure;
use crate::theme::{Font, ResolvedTheme, Role};
use ipc::{PaletteKind, PalettePanel, PaletteTarget};
use tokens::size::{candidate, glass, palette};

/// 外形に合わせて大きさを決める絵文字の書体の候補の数．目当ての一辺より 2 ポイント大きいものから 1 ポイントずつ小さくする
/// (書体によって外形が書体の大きさより小さいことも大きいこともある)
pub const EMOJI_FIT_STEPS: usize = 8;
/// 候補の大きさのうち，目当ての一辺より大きくする分
const EMOJI_FIT_ABOVE: f32 = 2.0;

/// 外形に合わせて大きさを決める絵文字の書体の候補(大きい順)．描くときに箱から余白を除いた一辺に外形が収まるものを選ぶ
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct EmojiSizes {
    pub fonts: [Font; EMOJI_FIT_STEPS],
}

impl EmojiSizes {
    /// 外形を一辺 target(箱の一辺から余白を除いたもの)に収める候補
    fn new(target: f32) -> Self {
        let largest = target.max(1.0) + EMOJI_FIT_ABOVE;
        Self {
            fonts: std::array::from_fn(|step| {
                Font::sized(Role::Emoji, (largest - step as f32).max(1.0))
            }),
        }
    }

    /// 外形を測れないときに使う書体(大きさが一辺 target にいちばん近いもの)
    pub fn nearest(&self, target: f32) -> Font {
        self.fonts
            .iter()
            .copied()
            .min_by_key(|font| match font {
                Font::Sized(_, size) => (f32::from(*size) - target).abs().round() as u32,
                _ => u32::MAX,
            })
            .unwrap_or(self.fonts[0])
    }
}

/// パレットで描く文字の書体と大きさ．マスの文字はマスの大きさで変わる
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Fonts {
    pub search: Font,
    pub search_icon: Font,
    pub mode: Font,
    pub tab_icon: Font,
    /// タブにアイコンを描けないときの代わりの文字
    pub tab_symbol: Font,
    pub heading: Font,
    /// マス目の絵文字．外形がマスの余白(cell-padding)の内側に収まる大きさを候補から選ぶ
    pub cell_emoji: EmojiSizes,
    pub cell_symbol: Font,
    /// 顔文字の広いマスの文字．収まらなければ kaomoji_small に縮める
    pub cell_kaomoji: Font,
    /// 顔文字とタブの短い顔を縮めるときの文字(下限の大きさ)．これでも収まらなければ末尾を省く
    pub kaomoji_small: Font,
    /// マス目の中の知らせと，説明の Unicode の名前と読み
    pub detail: Font,
    pub name: Font,
    /// 説明のショートコードとコードポイントのチップ(等幅)．行に入らないタグは code_small に縮める
    pub code: Font,
    pub code_small: Font,
    /// 説明の項目名と，見出しに添える名前の出どころ
    pub label: Font,
    /// 説明の見本の四角・足元の肌の色のボタン・肌の色の帯のマスの絵文字．外形が余白の内側に収まる大きさを候補から選ぶ
    pub preview_emoji: EmojiSizes,
    pub preview_symbol: Font,
    pub preview_kaomoji: Font,
    pub button_emoji: EmojiSizes,
    pub picker_emoji: EmojiSizes,
}

impl Fonts {
    pub fn new(cell_size: f32) -> Self {
        Self {
            search: Font::sized(Role::Candidate, palette::SEARCH_FONT_SIZE),
            search_icon: Font::sized(Role::Icon, palette::SEARCH_ICON_SIZE),
            mode: Font::sized(Role::Label, palette::MODE_FONT_SIZE),
            tab_icon: Font::sized(Role::Icon, palette::TAB_ICON_SIZE),
            tab_symbol: Font::sized(
                Role::Candidate,
                palette::TAB_ICON_SIZE + candidate::FRAME_WIDTH,
            ),
            heading: Font::sized(Role::Label, palette::HEADING_FONT_SIZE),
            cell_emoji: EmojiSizes::new(cell_size - palette::CELL_PADDING * 2.0),
            cell_symbol: Font::sized(Role::Candidate, cell_size * palette::SYMBOL_SCALE),
            cell_kaomoji: Font::sized(Role::Candidate, cell_size * palette::KAOMOJI_SCALE),
            kaomoji_small: Font::sized(Role::Candidate, palette::KAOMOJI_MIN_FONT_SIZE),
            detail: Font::sized(Role::Annotation, palette::DETAIL_FONT_SIZE),
            name: Font::sized(Role::Emphasis, palette::NAME_FONT_SIZE),
            code: Font::sized(Role::Code, palette::CODE_FONT_SIZE),
            code_small: Font::sized(Role::Code, palette::PREVIEW_CHIP_SMALL_FONT_SIZE),
            label: Font::sized(Role::Annotation, palette::PREVIEW_LABEL_FONT_SIZE),
            preview_emoji: EmojiSizes::new(palette::TILE_SIZE - palette::TILE_PADDING * 2.0),
            preview_symbol: Font::sized(
                Role::Candidate,
                palette::PREVIEW_GLYPH_SIZE * palette::SYMBOL_SCALE * palette::PREVIEW_SYMBOL_BOOST,
            ),
            preview_kaomoji: Font::sized(Role::Candidate, palette::PREVIEW_KAOMOJI_FONT_SIZE),
            // タグの縁(角丸のテーマと desk は線 1，platinum は外枠と立体の縁 2)の内側から余白を空ける．縁の細いほうで候補を作る
            button_emoji: EmojiSizes::new(
                glass::KEYCAP_HEIGHT
                    - candidate::FRAME_WIDTH * 2.0
                    - palette::SKIN_BUTTON_PADDING * 2.0,
            ),
            picker_emoji: EmojiSizes::new(palette::PICKER_CELL_SIZE - palette::CELL_PADDING * 2.0),
        }
    }

    /// 使う書体のすべて(重なりを除く)．描く側が前もって書式を作る
    pub fn all(&self) -> Vec<Font> {
        let mut unique = Vec::new();
        let fitted = [
            self.cell_emoji,
            self.preview_emoji,
            self.button_emoji,
            self.picker_emoji,
        ]
        .into_iter()
        .flat_map(|sizes| sizes.fonts);
        for font in [
            self.search,
            self.search_icon,
            self.mode,
            self.tab_icon,
            self.tab_symbol,
            self.heading,
            self.cell_symbol,
            self.cell_kaomoji,
            self.kaomoji_small,
            self.detail,
            self.name,
            self.code,
            self.code_small,
            self.label,
            self.preview_symbol,
            self.preview_kaomoji,
        ]
        .into_iter()
        .chain(fitted)
        {
            if !unique.contains(&font) {
                unique.push(font);
            }
        }
        unique
    }
}

/// マスの一辺．設定の値が使えない(0 以下や数でない)ときは 0 にし，マス目を描かない
pub fn cell_size(panel: &PalettePanel) -> f32 {
    let size = panel.cell_size as f32;
    if size.is_finite() && size > 0.0 {
        size
    } else {
        0.0
    }
}

/// 今の種類(選んでいる種類の切り替え．無ければ絵文字)
pub fn kind(panel: &PalettePanel) -> PaletteKind {
    panel
        .modes
        .iter()
        .find(|mode| mode.is_selected)
        .map_or(PaletteKind::Emoji, |mode| mode.kind)
}

/// 今の種類のマス目に回す行の数．説明の欄がいちばん高い種類(絵文字)より低い分を，マスの一辺で割って切り捨てる
/// (core の PaletteWindowLayout.extraRows．core が visible_rows に足して送る．見本を作るときに使う)
pub fn extra_rows(preview_height: f32, window_preview_height: f32, cell: f32) -> u32 {
    if cell <= 0.0 {
        return 0;
    }
    ((window_preview_height - preview_height) / cell)
        .floor()
        .max(0.0) as u32
}

/// パレットの窓の部品の位置．上から 探す欄と種類の切り替え・まとまりのタブ・見出し・マス目・説明・足元
#[derive(Debug, Clone, PartialEq)]
pub struct Layout {
    /// 窓の大きさ(desk の影を含む)
    pub width: f32,
    pub height: f32,
    /// 枠の中(desk の影を除く)
    pub body: Frame,
    /// 窓の内側の余白の内側
    pub content: Frame,
    pub search: Frame,
    pub modes: Vec<Frame>,
    pub tabs: Vec<Frame>,
    pub heading: Frame,
    pub grid: Frame,
    pub scrollbar: Frame,
    /// 区切りの線(上の端の y)．説明を出すときは 2 本，出さないときは 1 本
    pub separators: Vec<f32>,
    /// 説明の欄．出さない設定なら None
    pub preview: Option<Frame>,
    /// 足元の行(キーキャップの高さ)
    pub footer: Frame,
    /// 既定の肌の色のボタン．キーキャップと同じ高さの正方形で，中身の右の端に置く
    pub skin_tone_button: Frame,
    /// マスの高さ(四角いマスの一辺)
    pub cell: f32,
    /// マスの幅．四角いマスは cell と同じ．顔文字の広いマスはマス目の幅を 1 行のマスの数で割ったもの
    pub cell_width: f32,
    /// 今の種類のマスが顔文字の広いマスか．広いマスの文字は，絵文字を含んでいても候補の書体で描く
    pub wide: bool,
    pub kind: PaletteKind,
    pub fonts: Fonts,
    first_row: u32,
}

impl Layout {
    /// 窓の大きさは列数・行数・マスの大きさ・説明を出すかと説明に出す項目と種類で決まり，中身(探した結果の数や選んでいる文字)では変えない
    pub fn new(panel: &PalettePanel, theme: &ResolvedTheme, measure: &dyn Measure) -> Self {
        let cell = cell_size(panel);
        let fonts = Fonts::new(cell);
        let shadow = if theme.has_drop_shadow() {
            candidate::SHADOW_OFFSET
        } else {
            0.0
        };
        // 窓の縁の太さ(角丸のテーマは縁の線，platinum と desk は外枠と立体の縁)．内側の余白はこの内側から測る
        let border = if theme.is_rounded() {
            candidate::FRAME_WIDTH
        } else {
            candidate::FRAME_WIDTH + candidate::BEVEL_WIDTH
        };
        let inset = border + palette::PADDING;
        let line = candidate::FRAME_WIDTH;
        let control = palette::CONTROL_HEIGHT;
        let footer_height = glass::KEYCAP_HEIGHT;
        let kind = kind(panel);
        let visible_rows = panel.visible_rows;
        let fields = preview::fields(panel.preview_fields.as_ref());
        // 今の種類の説明の欄の高さ
        let preview_height = panel.shows_preview.then(|| preview::height(&fields, kind));
        let grid_width = panel.columns as f32 * cell;
        let content_width = grid_width + palette::GROUP_GAP + palette::SCROLLBAR_WIDTH;
        let mut body_height = inset * 2.0
            + control
            + palette::SECTION_GAP
            + control
            + palette::GROUP_GAP
            + palette::TEXT_ROW_HEIGHT
            + palette::ITEM_GAP
            + visible_rows as f32 * cell
            + palette::SECTION_GAP
            + line
            + palette::SECTION_GAP
            + footer_height;
        if let Some(height) = preview_height {
            body_height += height + palette::SECTION_GAP + line + palette::SECTION_GAP;
        }
        let body = Frame::new(0.0, 0.0, inset * 2.0 + content_width, body_height);
        let content = body.inset(inset, inset);
        let mut y = content.y;
        // 探す欄の右に種類の切り替えを置き，右の端を中身の右の端にそろえる
        let mode_widths: Vec<f32> = panel
            .modes
            .iter()
            .map(|mode| {
                (measure.width(&mode.title, fonts.mode) + palette::CONTROL_PADDING_X * 2.0).ceil()
            })
            .collect();
        let modes_width: f32 = mode_widths.iter().sum();
        let mut x = content.max_x() - modes_width;
        let modes = mode_widths
            .iter()
            .map(|width| {
                let frame = Frame::new(x, y, *width, control);
                x += width;
                frame
            })
            .collect();
        let search = Frame::new(
            content.x,
            y,
            content.width - modes_width - palette::GROUP_GAP,
            control,
        );
        y += control + palette::SECTION_GAP;
        let tab_width = if panel.tabs.is_empty() {
            0.0
        } else {
            // 探す欄と同じ高さの正方形にまとまりのあいだの間隔を足した幅で並べ，窓の幅に収まらなければ詰める
            (control + palette::GROUP_GAP)
                .min(content.width / panel.tabs.len() as f32)
                .floor()
        };
        let tabs = (0..panel.tabs.len())
            .map(|index| Frame::new(content.x + index as f32 * tab_width, y, tab_width, control))
            .collect();
        y += control + palette::GROUP_GAP;
        let heading = Frame::new(content.x, y, content.width, palette::TEXT_ROW_HEIGHT);
        y += palette::TEXT_ROW_HEIGHT + palette::ITEM_GAP;
        let grid = Frame::new(content.x, y, grid_width, visible_rows as f32 * cell);
        // 1 行のマスの数．送られてこなければ四角いマス(列の数と同じ)
        let cells_per_row = panel
            .cells_per_row
            .unwrap_or(panel.columns)
            .clamp(1, panel.columns.max(1));
        let cell_width = grid.width / cells_per_row as f32;
        let scrollbar = Frame::new(
            content.max_x() - palette::SCROLLBAR_WIDTH,
            grid.y,
            palette::SCROLLBAR_WIDTH,
            grid.height,
        );
        y = grid.max_y() + palette::SECTION_GAP;
        let mut separators = vec![y];
        y += line + palette::SECTION_GAP;
        let preview = preview_height.map(|height| {
            let frame = Frame::new(content.x, y, content.width, height);
            y += height + palette::SECTION_GAP;
            separators.push(y);
            y += line + palette::SECTION_GAP;
            frame
        });
        let footer = Frame::new(content.x, y, content.width, footer_height);
        let skin_tone_button = Frame::new(
            content.max_x() - footer_height,
            y,
            footer_height,
            footer_height,
        );
        Self {
            width: body.width + shadow,
            height: body.height + shadow,
            body,
            content,
            search,
            modes,
            tabs,
            heading,
            grid,
            scrollbar,
            separators,
            preview,
            footer,
            skin_tone_button,
            cell,
            cell_width,
            wide: kind == PaletteKind::Kaomoji,
            kind,
            fonts,
            first_row: panel.first_row,
        }
    }

    /// row 行(全体の中の位置)・column 列のマス
    pub fn cell_frame(&self, row: u32, column: u32) -> Frame {
        Frame::new(
            self.grid.x + column as f32 * self.cell_width,
            self.grid.y + row.saturating_sub(self.first_row) as f32 * self.cell,
            self.cell_width,
            self.cell,
        )
    }

    /// 肌の色の帯のマス．説明の欄(無ければマス目の下の端)の中央に重ねて出す
    pub fn picker_cells(&self, count: usize) -> Vec<Frame> {
        let size = palette::PICKER_CELL_SIZE;
        let width = size * count as f32;
        let area = self.preview.unwrap_or(Frame::new(
            self.grid.x,
            self.grid.max_y() - size,
            self.grid.width,
            size,
        ));
        let x = (area.mid_x() - width / 2.0).round();
        let y = (area.mid_y() - size / 2.0).round();
        (0..count)
            .map(|index| Frame::new(x + index as f32 * size, y, size, size))
            .collect()
    }

    /// 説明の欄のピン留めのボタン．欄の右の端で，見出しの行の縦の中心に置く(押せる範囲は探す欄と同じ高さの正方形)
    pub fn pin(&self, preview: Frame) -> Frame {
        let side = palette::CONTROL_HEIGHT;
        Frame::new(
            preview.max_x() - side,
            (preview::heading_mid_y(preview.y) - side / 2.0).round(),
            side,
            side,
        )
    }

    /// (x, y)(窓の本体の座標)を押したときの対象．hovering ならポインタを置いただけで，マスの上のときだけ返す
    pub fn target(
        &self,
        panel: &PalettePanel,
        x: f32,
        y: f32,
        hovering: bool,
    ) -> Option<PaletteTarget> {
        if let Some(picker) = &panel.skin_tone_picker {
            let cells = self.picker_cells(picker.options.len());
            if let Some(index) = cells.iter().position(|cell| contains(cell, x, y)) {
                if hovering {
                    return None;
                }
                return SKIN_TONES
                    .get(index)
                    .map(|tone| PaletteTarget::SkinTone { tone: *tone });
            }
        }
        if contains(&self.grid, x, y) {
            return self.cell_at(panel, x, y).map(|(row, column)| {
                if hovering {
                    PaletteTarget::Hover { row, column }
                } else {
                    PaletteTarget::Cell { row, column }
                }
            });
        }
        if hovering {
            return None;
        }
        if let Some(index) = self.tabs.iter().position(|tab| contains(tab, x, y)) {
            return panel.tabs.get(index).map(|tab| PaletteTarget::Tab {
                section: tab.section.clone(),
            });
        }
        if let Some(index) = self.modes.iter().position(|mode| contains(mode, x, y)) {
            return panel
                .modes
                .get(index)
                .map(|mode| PaletteTarget::Mode { kind: mode.kind });
        }
        if contains(&self.skin_tone_button, x, y) {
            return Some(PaletteTarget::SkinToneButton);
        }
        match self.preview {
            Some(preview) if panel.preview.is_some() && contains(&self.pin(preview), x, y) => {
                Some(PaletteTarget::Pin)
            }
            _ => None,
        }
    }

    /// マス目の中の点にある文字の行と列．文字の無いマスなら None
    fn cell_at(&self, panel: &PalettePanel, x: f32, y: f32) -> Option<(u32, u32)> {
        if self.cell <= 0.0 || self.cell_width <= 0.0 {
            return None;
        }
        let column = ((x - self.grid.x) / self.cell_width).floor() as u32;
        let row = panel
            .first_row
            .checked_add(((y - self.grid.y) / self.cell).floor() as u32)?;
        let cells = panel
            .rows
            .iter()
            .find(|shown| shown.index == row)?
            .cells
            .len();
        ((column as usize) < cells).then_some((row, column))
    }
}

fn contains(frame: &Frame, x: f32, y: f32) -> bool {
    x >= frame.x && x < frame.max_x() && y >= frame.y && y < frame.max_y()
}

/// ホイールの回した量をため，マス 1 つ分ごとに 1 行スクロールする(macOS の PaletteView.scrollWheel)．
/// ホイールの 1 目盛りをマス 1 つ分とする．細かく回せるホイールやタッチパッドの端数は次に回す
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct Wheel {
    remainder: f32,
}

impl Wheel {
    /// notches は回した目盛りの数(奥へ回すと正)．返すのはスクロールする行の数(下へが正)．0 なら何もしない
    pub fn turn(&mut self, notches: f32) -> i32 {
        if !notches.is_finite() {
            return 0;
        }
        self.remainder -= notches;
        let rows = self.remainder.trunc();
        self.remainder -= rows;
        rows as i32
    }

    pub fn reset(&mut self) {
        self.remainder = 0.0;
    }
}

#[cfg(test)]
mod tests {
    use super::super::sample;
    use super::*;
    use crate::scene::testing::{theme, Fixed};

    fn layout(panel: &PalettePanel, name: &str) -> Layout {
        Layout::new(panel, &theme(name), &Fixed)
    }

    #[test]
    fn 顔文字は窓の幅を変えずに広いマスに並べ押した位置を広いマスで数える() {
        let kaomoji = sample::kaomoji();
        let wide = layout(&kaomoji, "automatic");
        let square = layout(&sample::emoji(), "automatic");
        assert_eq!(wide.width, square.width);
        assert!(wide.wide);
        assert!(!square.wide);
        assert_eq!(wide.cell_width, wide.cell * 3.0);
        assert_eq!(square.cell_width, square.cell);
        let second = wide.cell_frame(1, 1);
        assert_eq!(second.x, wide.grid.x + wide.cell_width);
        assert_eq!(second.width, wide.cell_width);
        assert_eq!(
            wide.target(&kaomoji, second.mid_x(), second.mid_y(), false),
            Some(PaletteTarget::Cell { row: 1, column: 1 })
        );
        // 1 行のマスの数が列の数を超えていたら列の数にする
        let broken = PalettePanel {
            cells_per_row: Some(100),
            ..sample::kaomoji()
        };
        assert_eq!(layout(&broken, "automatic").cell_width, wide.cell);
    }

    #[test]
    fn 窓の大きさは列数と行数とマスの大きさで決まり中身では変えない() {
        let emoji = sample::emoji();
        let washi = layout(&emoji, "washi");
        let cell = cell_size(&emoji);
        assert_eq!(
            washi.width,
            (candidate::FRAME_WIDTH + palette::PADDING) * 2.0
                + 9.0 * cell
                + palette::GROUP_GAP
                + palette::SCROLLBAR_WIDTH
        );
        assert_eq!(washi.grid.width, 9.0 * cell);
        assert_eq!(washi.grid.height, 6.0 * cell);
        // 探した結果が 3 つでも，窓の大きさは同じ
        let search = layout(&sample::search(), "washi");
        assert_eq!((search.width, search.height), (washi.width, washi.height));
        // 説明を出さなければ，説明の欄と区切り 1 本と上下の間隔の分だけ低い
        let hidden = layout(
            &PalettePanel {
                shows_preview: false,
                ..emoji.clone()
            },
            "washi",
        );
        assert_eq!(hidden.preview, None);
        let fields = preview::fields(None);
        assert_eq!(
            washi.height - hidden.height,
            preview::height(&fields, PaletteKind::Emoji)
                + palette::SECTION_GAP * 2.0
                + candidate::FRAME_WIDTH
        );
        // 説明に出す項目を減らせば説明の欄は低くなる
        let fewer = layout(
            &PalettePanel {
                preview_fields: Some(ipc::PalettePreviewFields {
                    readings: false,
                    shortcodes: false,
                    code_points: false,
                    ..fields
                }),
                ..emoji.clone()
            },
            "washi",
        );
        assert!(fewer.height < washi.height);
        // desk は影の分だけ大きく，本体は影を除く
        let desk = layout(&emoji, "desk");
        assert_eq!(desk.body.width, desk.width - candidate::SHADOW_OFFSET);
        assert_eq!(desk.body.height, desk.height - candidate::SHADOW_OFFSET);
    }

    #[test]
    fn 説明の欄が低い種類は回せる分をマス目の行に回し_回しきれない端の分だけ窓を低くする() {
        for name in ["automatic", "platinum", "desk"] {
            let emoji = layout(&sample::emoji(), name);
            let symbol = layout(&sample::symbol(), name);
            let kaomoji = layout(&sample::kaomoji(), name);
            for other in [&symbol, &kaomoji] {
                assert_eq!(other.width, emoji.width, "{name}");
            }
            // 顔文字は説明の欄が 68 低い．1 行(36)をマス目に回し，残りの 32 だけ窓を低くする
            assert_eq!(kaomoji.grid.height, emoji.grid.height + 36.0, "{name}");
            assert_eq!(emoji.height - kaomoji.height, 32.0, "{name}");
            // 記号は 20 低いので行は回さず，20 だけ窓を低くする
            assert_eq!(symbol.grid.height, emoji.grid.height, "{name}");
            assert_eq!(emoji.height - symbol.height, 20.0, "{name}");
            let fields = preview::fields(None);
            assert_eq!(
                kaomoji.preview.map(|frame| frame.height),
                Some(preview::height(&fields, PaletteKind::Kaomoji))
            );
            assert_eq!(
                symbol.preview.map(|frame| frame.height),
                Some(preview::height(&fields, PaletteKind::Symbol))
            );
        }
    }

    #[test]
    fn 窓の内側の余白は上下左右とも同じで_中身の右の端は_1_か所にそろう() {
        for name in ["automatic", "platinum", "desk"] {
            for panel in [sample::emoji(), sample::symbol(), sample::kaomoji()] {
                let layout = layout(&panel, name);
                let top = layout.search.y - layout.body.y;
                let left = layout.content.x - layout.body.x;
                let right = layout.body.max_x() - layout.content.max_x();
                let bottom = layout.body.max_y() - layout.footer.max_y();
                assert_eq!([top, left, right], [bottom; 3], "{name}");
                let right_edges = [
                    layout.modes.last().unwrap().max_x(),
                    layout.scrollbar.max_x(),
                    layout.skin_tone_button.max_x(),
                    layout.preview.unwrap().max_x(),
                    layout.footer.max_x(),
                ];
                assert_eq!(right_edges, [layout.content.max_x(); 5], "{name}");
                // 区切りの線も中身の左の端から右の端まで(描く側が content を使う)
                assert_eq!(layout.grid.x, layout.content.x);
            }
        }
    }

    #[test]
    fn 区切りの線の上と下の間隔は同じ() {
        for name in ["automatic", "platinum", "desk"] {
            for panel in [sample::emoji(), sample::symbol(), sample::kaomoji()] {
                let layout = layout(&panel, name);
                let preview = layout.preview.unwrap();
                let line = candidate::FRAME_WIDTH;
                assert_eq!(layout.separators.len(), 2);
                // 区切りの線の上と下は，どの種類でも区画のあいだ(端数を余白に回さない)
                assert_eq!(
                    layout.separators[0] - layout.grid.max_y(),
                    palette::SECTION_GAP,
                    "{name}"
                );
                assert_eq!(
                    preview.y - (layout.separators[0] + line),
                    palette::SECTION_GAP,
                    "{name}"
                );
                assert_eq!(layout.separators[1] - preview.max_y(), palette::SECTION_GAP);
                assert_eq!(
                    layout.footer.y - (layout.separators[1] + line),
                    palette::SECTION_GAP
                );
            }
        }
        // 説明を出さなければ，マス目と足元のあいだの区切り 1 本だけ
        let hidden = layout(
            &PalettePanel {
                shows_preview: false,
                ..sample::emoji()
            },
            "automatic",
        );
        assert_eq!(hidden.separators.len(), 1);
        assert_eq!(
            hidden.separators[0] - hidden.grid.max_y(),
            palette::SECTION_GAP
        );
        assert_eq!(
            hidden.footer.y - (hidden.separators[0] + candidate::FRAME_WIDTH),
            palette::SECTION_GAP
        );
    }

    #[test]
    fn 足元のキーキャップと肌の色のボタンは同じ高さと縦の中心で_上下の余白が等しい() {
        for name in ["automatic", "platinum", "desk"] {
            let layout = layout(&sample::emoji(), name);
            let button = layout.skin_tone_button;
            assert_eq!(button.height, glass::KEYCAP_HEIGHT);
            assert_eq!(button.width, button.height);
            assert_eq!(button.mid_y(), layout.footer.mid_y());
            // 下の余白は窓の縁(platinum と desk は立体の縁の内側)から測る
            let border = layout.content.x - layout.body.x - palette::PADDING;
            let above = layout.footer.y - (layout.separators[1] + candidate::FRAME_WIDTH);
            let below = layout.body.max_y() - border - layout.footer.max_y();
            assert_eq!(above, below, "{name}");
        }
    }

    #[test]
    fn 部品は上から順に重ならずに並ぶ() {
        for name in ["automatic", "platinum", "desk"] {
            let layout = layout(&sample::emoji(), name);
            let preview = layout.preview.unwrap();
            assert_eq!(
                layout.search.max_y() + palette::SECTION_GAP,
                layout.tabs[0].y,
                "{name}"
            );
            assert_eq!(
                layout.search.max_x() + palette::GROUP_GAP,
                layout.modes[0].x,
                "{name}"
            );
            assert_eq!(
                layout.tabs[0].max_y() + palette::GROUP_GAP,
                layout.heading.y,
                "{name}"
            );
            assert_eq!(
                layout.heading.max_y() + palette::ITEM_GAP,
                layout.grid.y,
                "{name}"
            );
            assert!(layout.grid.max_y() < layout.separators[0], "{name}");
            assert!(layout.separators[0] < preview.y, "{name}");
            assert!(preview.max_y() < layout.footer.y, "{name}");
            assert_eq!(
                layout.grid.max_x() + palette::GROUP_GAP,
                layout.scrollbar.x,
                "{name}"
            );
        }
    }

    #[test]
    fn タブは窓の幅に収まるだけの幅で並べる() {
        let panel = sample::emoji();
        let layout = layout(&panel, "automatic");
        assert_eq!(layout.tabs.len(), panel.tabs.len());
        let last = layout.tabs.last().unwrap();
        assert!(last.max_x() <= layout.content.max_x());
        assert!(layout.tabs[0].width <= palette::CONTROL_HEIGHT + palette::GROUP_GAP);
    }

    #[test]
    fn 押したマスとポインタを置いたマスを見分ける() {
        let panel = sample::emoji();
        let layout = layout(&panel, "automatic");
        let cell = layout.cell_frame(1, 2);
        let (x, y) = (cell.mid_x(), cell.mid_y());
        assert_eq!(
            layout.target(&panel, x, y, false),
            Some(PaletteTarget::Cell { row: 1, column: 2 })
        );
        assert_eq!(
            layout.target(&panel, x, y, true),
            Some(PaletteTarget::Hover { row: 1, column: 2 })
        );
        // 文字の無いマス(よく使う文字の行の後ろは空いていない見本なので，探した結果で確かめる)
        let search = sample::search();
        let found = Layout::new(&search, &theme("automatic"), &Fixed);
        let empty = found.cell_frame(0, 5);
        assert_eq!(
            found.target(&search, empty.mid_x(), empty.mid_y(), false),
            None
        );
        let second = found.cell_frame(1, 0);
        assert_eq!(
            found.target(&search, second.mid_x(), second.mid_y(), false),
            None
        );
    }

    #[test]
    fn スクロールした位置のマスは全体の中の行で返す() {
        let mut panel = sample::emoji();
        panel.first_row = 10;
        for (offset, row) in panel.rows.iter_mut().enumerate() {
            row.index = 10 + offset as u32;
        }
        let layout = layout(&panel, "automatic");
        let cell = layout.cell_frame(12, 0);
        assert_eq!(cell.y, layout.grid.y + layout.cell * 2.0);
        assert_eq!(
            layout.target(&panel, cell.mid_x(), cell.mid_y(), false),
            Some(PaletteTarget::Cell { row: 12, column: 0 })
        );
    }

    #[test]
    fn タブと種類と肌の色のボタンとピン留めを押す() {
        let panel = sample::emoji();
        let layout = layout(&panel, "platinum");
        let tab = layout.tabs[2];
        assert_eq!(
            layout.target(&panel, tab.mid_x(), tab.mid_y(), false),
            Some(PaletteTarget::Tab {
                section: panel.tabs[2].section.clone()
            })
        );
        assert_eq!(layout.target(&panel, tab.mid_x(), tab.mid_y(), true), None);
        let symbol = layout.modes[1];
        assert_eq!(
            layout.target(&panel, symbol.mid_x(), symbol.mid_y(), false),
            Some(PaletteTarget::Mode {
                kind: ipc::PaletteKind::Symbol
            })
        );
        let button = layout.skin_tone_button;
        assert_eq!(
            layout.target(&panel, button.mid_x(), button.mid_y(), false),
            Some(PaletteTarget::SkinToneButton)
        );
        let pin = layout.pin(layout.preview.unwrap());
        assert_eq!(
            layout.target(&panel, pin.mid_x(), pin.mid_y(), false),
            Some(PaletteTarget::Pin)
        );
        // 説明が無ければピン留めのボタンも無い
        let without = PalettePanel {
            preview: None,
            ..panel.clone()
        };
        assert_eq!(
            layout.target(&without, pin.mid_x(), pin.mid_y(), false),
            None
        );
        // 探す欄と余白は何も起こさない
        let search = layout.search;
        assert_eq!(
            layout.target(&panel, search.mid_x(), search.mid_y(), false),
            None
        );
        assert_eq!(layout.target(&panel, 0.5, 0.5, false), None);
    }

    #[test]
    fn 肌の色の帯は説明の欄の中央に並べ押した順の肌の色を返す() {
        let panel = sample::search();
        let layout = layout(&panel, "automatic");
        let preview = layout.preview.unwrap();
        let cells = layout.picker_cells(6);
        let strip = cells[5].max_x() - cells[0].x;
        assert!((cells[0].x + strip / 2.0 - preview.mid_x()).abs() <= 0.5);
        for (index, cell) in cells.iter().enumerate() {
            assert!(cell.y >= preview.y && cell.max_y() <= preview.max_y());
            assert_eq!(
                layout.target(&panel, cell.mid_x(), cell.mid_y(), false),
                Some(PaletteTarget::SkinTone {
                    tone: SKIN_TONES[index]
                })
            );
            assert_eq!(
                layout.target(&panel, cell.mid_x(), cell.mid_y(), true),
                None
            );
        }
        // 説明の欄が無ければマス目の下の端に重ねる
        let hidden = Layout::new(
            &PalettePanel {
                shows_preview: false,
                ..panel.clone()
            },
            &theme("automatic"),
            &Fixed,
        );
        let cells = hidden.picker_cells(6);
        assert_eq!(cells[0].max_y(), hidden.grid.max_y());
    }

    #[test]
    fn マスの大きさが使えなければマス目を押せない() {
        let panel = PalettePanel {
            cell_size: f64::NAN,
            ..sample::emoji()
        };
        let layout = layout(&panel, "automatic");
        assert_eq!(layout.cell, 0.0);
        assert_eq!(layout.grid.width, 0.0);
        assert_eq!(
            layout.target(&panel, layout.grid.x, layout.grid.y, false),
            None
        );
    }

    #[test]
    fn ホイールは1目盛りで1行進め端数をためる() {
        let mut wheel = Wheel::default();
        // 手前へ回すと下へ
        assert_eq!(wheel.turn(-1.0), 1);
        assert_eq!(wheel.turn(2.0), -2);
        assert_eq!(wheel.turn(-0.5), 0);
        assert_eq!(wheel.turn(-0.5), 1);
        assert_eq!(wheel.turn(-0.25), 0);
        wheel.reset();
        assert_eq!(wheel.turn(-0.75), 0);
        assert_eq!(wheel.turn(f32::NAN), 0);
    }

    #[test]
    fn 使う書体は重ならずにすべて並べる() {
        let fonts = Fonts::new(36.0);
        let all = fonts.all();
        // 知らせと説明の読みは同じ書体
        assert!(all.contains(&fonts.detail));
        assert!(fonts.cell_emoji.fonts.iter().all(|font| all.contains(font)));
        // マスの絵文字の候補は，マスから余白を除いた一辺(28)より 2 大きいものから
        assert_eq!(fonts.cell_emoji.fonts[0], Font::Sized(Role::Emoji, 30));
        assert_eq!(fonts.cell_emoji.nearest(28.0), Font::Sized(Role::Emoji, 28));
        assert_eq!(fonts.cell_symbol, Font::Sized(Role::Candidate, 20));
        for (index, font) in all.iter().enumerate() {
            assert!(!all[index + 1..].contains(font), "{font:?}");
        }
    }
}
