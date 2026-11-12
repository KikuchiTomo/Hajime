//! scene の部品を Direct2D と DirectWrite で描く．配置と色は scene が決めるので，ここは部品をなぞるだけにする

use crate::fonts::{InstalledFace, Selection};
use crate::geometry::Frame;
use crate::icon;
use crate::scene::{Draw, Measure, Scene};
use crate::theme::{Color, Face, Font, FontSpec, ResolvedTheme, Weight};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::OnceLock;
use windows::Win32::Graphics::Direct2D::Common::{
    D2D1_BEZIER_SEGMENT, D2D1_COLOR_F, D2D1_FIGURE_BEGIN_FILLED, D2D1_FIGURE_BEGIN_HOLLOW,
    D2D1_FIGURE_END_CLOSED, D2D1_FIGURE_END_OPEN, D2D_RECT_F,
};
use windows::Win32::Graphics::Direct2D::{
    D2D1CreateFactory, ID2D1Factory, ID2D1Geometry, ID2D1RenderTarget, ID2D1SolidColorBrush,
    ID2D1StrokeStyle, D2D1_CAP_STYLE_ROUND, D2D1_DASH_STYLE_CUSTOM, D2D1_DASH_STYLE_SOLID,
    D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT, D2D1_ELLIPSE, D2D1_FACTORY_TYPE_SINGLE_THREADED,
    D2D1_LINE_JOIN_ROUND, D2D1_ROUNDED_RECT, D2D1_STROKE_STYLE_PROPERTIES,
};
use windows::Win32::Graphics::DirectWrite::{
    DWriteCreateFactory, IDWriteFactory, IDWriteFactory5, IDWriteFontCollection, IDWriteTextFormat,
    IDWriteTextLayout, DWRITE_FACTORY_TYPE_SHARED, DWRITE_FONT_STRETCH, DWRITE_FONT_STRETCH_NORMAL,
    DWRITE_FONT_STYLE_ITALIC, DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_WEIGHT,
    DWRITE_FONT_WEIGHT_MEDIUM, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_WEIGHT_SEMI_BOLD,
    DWRITE_LINE_METRICS, DWRITE_PARAGRAPH_ALIGNMENT_CENTER, DWRITE_TEXT_METRICS,
    DWRITE_WORD_WRAPPING_NO_WRAP,
};
use windows_core::{Interface, Result, BOOL, HSTRING};

const LOCALE: &str = "ja-JP";

/// 書式ごと・文字ごとの行の高さとベースライン
type LineCache = HashMap<Font, HashMap<String, (f32, f32)>>;
/// 書式ごと・文字ごとの字の外形(測れなければ None)
type InkCache = HashMap<Font, HashMap<String, Option<Frame>>>;
/// 角丸のテーマの影をぼかすときに重ねる層の数(1 ドットに 1 層)
const SHADOW_LAYERS_PER_DOT: f32 = 1.0;
/// 作った書体の組を覚えておく数．候補の窓・予測の窓・パレットなどが別の書体の組を使っても作り直さないように
const MEASURE_CACHE: usize = 4;
/// 書体の組ごとに覚えておく文字の幅の数．超えたら忘れて測り直す(打った文字が増え続けても覚える量を抑える)
const WIDTH_CACHE: usize = 4096;
/// 書体の組ごとに覚えておく，描くための文字の配置の数．超えたら忘れて作り直す
const LAYOUT_CACHE: usize = 512;

/// 配布物に入れた書体のディレクトリ(実行ファイルと同じディレクトリの中)とファイル．
/// Kiwi Maru(SIL OFL 1.1．LICENSES/OFL-1.1-KiwiMaru.txt)．data/fonts/ を tools/fonts/update.sh で取ってくる
const BUNDLED_FONT_DIRECTORY: &str = "fonts";
const BUNDLED_FONT_FILES: &[&str] = &["KiwiMaru-Regular.ttf", "KiwiMaru-Medium.ttf"];

/// 書体の系統ごとの Windows の書体(docs/dev/DESIGN-SYSTEM.md の「書体」)．前から順に，入っている最初のものを使う．
/// 日本語の UI の書体と丸みのある書体は，配布物に入れた Kiwi Maru を先に使う(入っていなければ Yu Gothic UI)
fn families(face: &Face) -> &'static [&'static str] {
    match face {
        Face::System | Face::Rounded => &["Kiwi Maru", "Yu Gothic UI"],
        Face::Named(_) => &["Yu Gothic UI"],
        Face::Ui => &["Segoe UI"],
        Face::Mincho => &["Yu Mincho"],
        Face::Monospaced => &["BIZ UDGothic", "MS Gothic"],
        Face::Emoji => &["Segoe UI Emoji"],
        // Windows 11 は Segoe Fluent Icons，Windows 10 は Segoe MDL2 Assets(同じ字の番号でアイコンを持つ)
        Face::Icon => &["Segoe Fluent Icons", "Segoe MDL2 Assets"],
        // 小さくても字の線が細くならない等幅の書体(Windows 11 は Cascadia Mono)
        Face::Code => &["Cascadia Mono", "Consolas"],
        // かなを詰めない書体(Yu Gothic UI はかなを詰めるので，カタカナが英字より小さく見える)
        Face::Readable => &["BIZ UDPGothic", "Yu Gothic", "Meiryo"],
        Face::SystemReadable => &["Kiwi Maru", "BIZ UDPGothic", "Yu Gothic"],
    }
}

fn weight(weight: Weight) -> DWRITE_FONT_WEIGHT {
    match weight {
        Weight::Regular => DWRITE_FONT_WEIGHT_NORMAL,
        Weight::Medium => DWRITE_FONT_WEIGHT_MEDIUM,
        Weight::Semibold => DWRITE_FONT_WEIGHT_SEMI_BOLD,
    }
}

/// Direct2D の点(windows_numerics::Vector2)を，その型の名前を出さずに作る(windows クレートが再公開しない型のために依存を増やさない)
macro_rules! vector {
    ($x:expr, $y:expr) => {{
        let mut point = D2D1_ELLIPSE::default().point;
        point.X = $x;
        point.Y = $y;
        point
    }};
}

pub struct Renderer {
    d2d: ID2D1Factory,
    dwrite: IDWriteFactory,
    fonts: Option<IDWriteFontCollection>,
    /// 配布物に入れた書体の集まり．読めなければ None(OS の書体だけで描く)
    bundled: Option<IDWriteFontCollection>,
    round: ID2D1StrokeStyle,
    /// OS に入っている書体の一覧．カスタムテーマの書体の PostScript 名を初めて引くときに読む
    faces: OnceLock<Vec<InstalledFace>>,
    /// 前に作った書体の組と，その元の書体の指定(新しいものが後ろ)．
    /// 打つたびやアニメーションのコマごとに同じ書体を作り直さないよう，指定が同じなら使い回す
    measures: RefCell<Vec<(Vec<FontSpec>, Rc<TextMeasure>)>>,
}

/// 描いた文字の配置を引く鍵(書体と，描く枠の幅と高さのビット)
type LayoutKey = (Font, u32, u32);

/// テーマと文字の大きさを決めた書体の組．文字の幅を測り，描くときにも使う
pub struct TextMeasure {
    dwrite: IDWriteFactory,
    formats: HashMap<Font, IDWriteTextFormat>,
    /// OS の書体の集まり．書式が書体の集まりを持たないときに字を探す
    system: Option<IDWriteFontCollection>,
    /// 測った幅と高さと字の有無．同じ書式で同じ文字を測れば DirectWrite は同じ値を返すので，覚えた値を返す
    widths: RefCell<HashMap<Font, HashMap<String, f32>>>,
    width_count: std::cell::Cell<usize>,
    heights: RefCell<HashMap<Font, f32>>,
    /// 文字ごとの行の高さとベースライン(書体の代わりの字で変わる)
    lines: RefCell<LineCache>,
    line_count: std::cell::Cell<usize>,
    /// 文字ごとの字の外形(絵文字を箱の真ん中に置く)
    inks: RefCell<InkCache>,
    ink_count: std::cell::Cell<usize>,
    glyphs: RefCell<HashMap<(Font, char), bool>>,
    /// 描いた文字の配置(書式・描く枠の幅と高さ・文字ごと)．アニメーションのコマごとや打つたびに同じ文字を並べ直さない
    layouts: RefCell<HashMap<LayoutKey, HashMap<String, IDWriteTextLayout>>>,
    layout_count: std::cell::Cell<usize>,
}

impl TextMeasure {
    fn new(
        dwrite: IDWriteFactory,
        formats: HashMap<Font, IDWriteTextFormat>,
        system: Option<IDWriteFontCollection>,
    ) -> Self {
        Self {
            dwrite,
            formats,
            system,
            widths: RefCell::default(),
            width_count: std::cell::Cell::new(0),
            heights: RefCell::default(),
            lines: RefCell::default(),
            line_count: std::cell::Cell::new(0),
            inks: RefCell::default(),
            ink_count: std::cell::Cell::new(0),
            glyphs: RefCell::default(),
            layouts: RefCell::default(),
            layout_count: std::cell::Cell::new(0),
        }
    }

    /// 文字を width × height の枠に並べた配置．ID2D1RenderTarget::DrawText が中で作るものと同じ引数で作り，覚えておく
    fn layout(&self, text: &str, font: Font, width: f32, height: f32) -> Option<IDWriteTextLayout> {
        let key = (font, width.to_bits(), height.to_bits());
        if let Some(layout) = self
            .layouts
            .borrow()
            .get(&key)
            .and_then(|layouts| layouts.get(text))
        {
            return Some(layout.clone());
        }
        let format = self.format(font)?;
        let wide: Vec<u16> = text.encode_utf16().collect();
        // SAFETY: format は生きている COM の参照で，wide は呼び出しのあいだ有効
        let layout = unsafe {
            self.dwrite
                .CreateTextLayout(&wide, format, width, height)
                .ok()?
        };
        let mut layouts = self.layouts.borrow_mut();
        if self.layout_count.get() >= LAYOUT_CACHE {
            layouts.clear();
            self.layout_count.set(0);
        }
        layouts
            .entry(key)
            .or_default()
            .insert(text.to_string(), layout.clone());
        self.layout_count.set(self.layout_count.get() + 1);
        Some(layout)
    }

    fn format(&self, font: Font) -> Option<&IDWriteTextFormat> {
        self.formats.get(&font)
    }

    /// 1 行目の行の高さとベースライン(GetLineMetrics)
    fn line_metrics(&self, text: &str, font: Font) -> Option<(f32, f32)> {
        let wide: Vec<u16> = text.encode_utf16().collect();
        let format = self.format(font)?;
        // SAFETY: format は生きている COM の参照で，wide は呼び出しのあいだ有効
        let layout = unsafe {
            self.dwrite
                .CreateTextLayout(&wide, format, f32::MAX, f32::MAX)
                .ok()?
        };
        let mut lines = [DWRITE_LINE_METRICS::default()];
        let mut count = 0u32;
        // SAFETY: lines と count は書き込める領域．折り返さない書式なので 1 行に収まる
        unsafe { layout.GetLineMetrics(Some(&mut lines), &mut count).ok()? };
        (count >= 1).then(|| (lines[0].height, lines[0].baseline))
    }

    /// 字の外形．幅 width・高さ height の枠に並べた配置がその枠からはみ出す量(GetOverhangMetrics．はみ出せば正)から求める．
    /// 書式は左寄せで縦は中央なので，枠の高さを行の高さにすると，枠の左上は Draw::Text の枠の左上と同じになる
    fn ink_metrics(&self, text: &str, font: Font) -> Option<Frame> {
        let (height, _) = self.line(text, font);
        let width = self.width(text, font).ceil();
        let layout = self.layout(text, font, width + height, height)?;
        // SAFETY: layout は生きている COM の参照
        let overhang = unsafe { layout.GetOverhangMetrics().ok()? };
        let ink = Frame::new(
            -overhang.left,
            -overhang.top,
            width + height + overhang.left + overhang.right,
            height + overhang.top + overhang.bottom,
        );
        (ink.width > 0.0 && ink.height > 0.0).then_some(ink)
    }

    fn metrics(&self, text: &str, font: Font) -> Option<DWRITE_TEXT_METRICS> {
        let wide: Vec<u16> = text.encode_utf16().collect();
        let format = self.format(font)?;
        // SAFETY: format は生きている COM の参照で，wide は呼び出しのあいだ有効
        let layout = unsafe {
            self.dwrite
                .CreateTextLayout(&wide, format, f32::MAX, f32::MAX)
                .ok()?
        };
        let mut metrics = DWRITE_TEXT_METRICS::default();
        // SAFETY: metrics は書き込める領域
        unsafe { layout.GetMetrics(&mut metrics).ok()? };
        Some(metrics)
    }
}

impl Measure for TextMeasure {
    fn width(&self, text: &str, font: Font) -> f32 {
        if let Some(width) = self
            .widths
            .borrow()
            .get(&font)
            .and_then(|widths| widths.get(text))
        {
            return *width;
        }
        let width = self
            .metrics(text, font)
            .map_or(0.0, |metrics| metrics.widthIncludingTrailingWhitespace);
        let mut widths = self.widths.borrow_mut();
        if self.width_count.get() >= WIDTH_CACHE {
            widths.clear();
            self.width_count.set(0);
        }
        widths
            .entry(font)
            .or_default()
            .insert(text.to_string(), width);
        self.width_count.set(self.width_count.get() + 1);
        width
    }

    fn height(&self, font: Font) -> f32 {
        if let Some(height) = self.heights.borrow().get(&font) {
            return *height;
        }
        let height = self
            .metrics("あ", font)
            .map_or(0.0, |metrics| metrics.height);
        self.heights.borrow_mut().insert(font, height);
        height
    }

    fn line(&self, text: &str, font: Font) -> (f32, f32) {
        if let Some(line) = self
            .lines
            .borrow()
            .get(&font)
            .and_then(|lines| lines.get(text))
        {
            return *line;
        }
        let height = self.height(font);
        let line = self
            .line_metrics(text, font)
            .unwrap_or((height, (height * 0.75).round()));
        let mut lines = self.lines.borrow_mut();
        if self.line_count.get() >= WIDTH_CACHE {
            lines.clear();
            self.line_count.set(0);
        }
        lines
            .entry(font)
            .or_default()
            .insert(text.to_string(), line);
        self.line_count.set(self.line_count.get() + 1);
        line
    }

    fn has_glyph(&self, font: Font, glyph: char) -> bool {
        if let Some(has) = self.glyphs.borrow().get(&(font, glyph)) {
            return *has;
        }
        let has = self.find_glyph(font, glyph);
        self.glyphs.borrow_mut().insert((font, glyph), has);
        has
    }

    fn ink(&self, text: &str, font: Font) -> Option<Frame> {
        if let Some(ink) = self
            .inks
            .borrow()
            .get(&font)
            .and_then(|inks| inks.get(text))
        {
            return *ink;
        }
        let ink = self.ink_metrics(text, font);
        let mut inks = self.inks.borrow_mut();
        if self.ink_count.get() >= WIDTH_CACHE {
            inks.clear();
            self.ink_count.set(0);
        }
        inks.entry(font).or_default().insert(text.to_string(), ink);
        self.ink_count.set(self.ink_count.get() + 1);
        ink
    }
}

impl TextMeasure {
    fn find_glyph(&self, font: Font, glyph: char) -> bool {
        let Some(format) = self.format(font) else {
            return false;
        };
        // SAFETY: format と書体の集まりは生きている COM の参照．name は長さを尋ねてから確保した領域
        unsafe {
            let length = format.GetFontFamilyNameLength() as usize;
            let mut name = vec![0u16; length + 1];
            if format.GetFontFamilyName(&mut name).is_err() {
                return false;
            }
            let Some(collection) = format.GetFontCollection().ok().or(self.system.clone()) else {
                return false;
            };
            let family = String::from_utf16_lossy(&name[..length]);
            let mut index = 0;
            let mut exists = BOOL(0);
            let found = collection.FindFamilyName(&HSTRING::from(family), &mut index, &mut exists);
            if found.is_err() || !exists.as_bool() {
                return false;
            }
            collection
                .GetFontFamily(index)
                .and_then(|family| {
                    family.GetFirstMatchingFont(
                        format.GetFontWeight(),
                        format.GetFontStretch(),
                        format.GetFontStyle(),
                    )
                })
                .and_then(|matched| matched.HasCharacter(u32::from(glyph)))
                .is_ok_and(|has| has.as_bool())
        }
    }
}

/// 書体の集まりに family があるか
fn contains(collection: Option<&IDWriteFontCollection>, family: &str) -> bool {
    let Some(collection) = collection else {
        return false;
    };
    let mut index = 0;
    let mut exists = BOOL(0);
    // SAFETY: index と exists は書き込める領域
    let found =
        unsafe { collection.FindFamilyName(&HSTRING::from(family), &mut index, &mut exists) };
    found.is_ok() && exists.as_bool()
}

/// 配布物に入れた書体を読み込んだ書体の集まり．OS に入れずにこのプロセスだけで使う(DirectWrite の書体の組．Windows 10 1703 から)．
/// 書体のファイルが無い・読めないときは None
fn bundled_fonts(dwrite: &IDWriteFactory) -> Option<IDWriteFontCollection> {
    let directory = std::env::current_exe()
        .ok()?
        .parent()?
        .join(BUNDLED_FONT_DIRECTORY);
    let factory: IDWriteFactory5 = dwrite.cast().ok()?;
    // SAFETY: 作ったばかりの COM の参照を使う．ファイルの場所の文字列は呼び出しのあいだ有効
    unsafe {
        let builder = factory.CreateFontSetBuilder().ok()?;
        let mut added = false;
        for name in BUNDLED_FONT_FILES {
            let path = directory.join(name);
            if !path.is_file() {
                continue;
            }
            let file = dwrite
                .CreateFontFileReference(&HSTRING::from(path.as_os_str()), None)
                .ok()?;
            added |= builder.AddFontFile(&file).is_ok();
        }
        if !added {
            return None;
        }
        let set = builder.CreateFontSet().ok()?;
        factory
            .CreateFontCollectionFromFontSet(&set)
            .ok()?
            .cast()
            .ok()
    }
}

impl Renderer {
    pub fn new() -> Result<Self> {
        // SAFETY: 引数は定数
        let d2d: ID2D1Factory =
            unsafe { D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, None)? };
        // SAFETY: 引数は定数
        let dwrite: IDWriteFactory = unsafe { DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED)? };
        let mut fonts = None;
        // SAFETY: fonts は書き込める領域
        let _ = unsafe { dwrite.GetSystemFontCollection(&mut fonts, false) };
        let properties = D2D1_STROKE_STYLE_PROPERTIES {
            startCap: D2D1_CAP_STYLE_ROUND,
            endCap: D2D1_CAP_STYLE_ROUND,
            dashCap: D2D1_CAP_STYLE_ROUND,
            lineJoin: D2D1_LINE_JOIN_ROUND,
            miterLimit: 1.0,
            dashStyle: D2D1_DASH_STYLE_SOLID,
            dashOffset: 0.0,
        };
        // SAFETY: properties は呼び出しのあいだ有効
        let round = unsafe { d2d.CreateStrokeStyle(&properties, None)? };
        let bundled = bundled_fonts(&dwrite);
        Ok(Self {
            d2d,
            dwrite,
            fonts,
            bundled,
            round,
            faces: OnceLock::new(),
            measures: RefCell::default(),
        })
    }

    pub fn factory(&self) -> &ID2D1Factory {
        &self.d2d
    }

    /// テーマの書体で，文字を測り描くための書体の組を作る
    pub fn measure(&self, theme: &ResolvedTheme, font_size: f32) -> Result<Rc<TextMeasure>> {
        self.measure_with(theme, font_size, &[])
    }

    /// measure に，大きさを決めて描く文字(パレット)の書体 sized を足す．
    /// 書体の指定がすべて前に作った組と同じなら，その組を返す(書式は指定と OS の書体の集まりだけで決まる)
    pub fn measure_with(
        &self,
        theme: &ResolvedTheme,
        font_size: f32,
        sized: &[Font],
    ) -> Result<Rc<TextMeasure>> {
        let fonts: Vec<Font> = Font::ALL.iter().chain(sized).copied().collect();
        let specs: Vec<FontSpec> = fonts
            .iter()
            .map(|font| theme.font(*font, font_size))
            .collect();
        let mut measures = self.measures.borrow_mut();
        if let Some(index) = measures.iter().position(|(known, measure)| {
            *known == specs
                && measure.formats.len() == fonts.len()
                && fonts.iter().all(|font| measure.formats.contains_key(font))
        }) {
            let entry = measures.remove(index);
            let measure = entry.1.clone();
            measures.push(entry);
            return Ok(measure);
        }
        let mut formats = HashMap::new();
        for (font, spec) in fonts.iter().zip(&specs) {
            formats.insert(*font, self.format(spec)?);
        }
        let measure = Rc::new(TextMeasure::new(
            self.dwrite.clone(),
            formats,
            self.fonts.clone(),
        ));
        if measures.len() >= MEASURE_CACHE {
            measures.remove(0);
        }
        measures.push((specs, measure.clone()));
        Ok(measure)
    }

    fn installed(&self, family: &str) -> bool {
        contains(self.fonts.as_ref(), family) || contains(self.bundled.as_ref(), family)
    }

    /// 書体の名前を決める．カスタムテーマの書体が入っていなければ，日本語の UI の書体にする
    fn family(&self, face: &Face) -> String {
        if let Face::Named(name) = face {
            if self.installed(name) {
                return name.clone();
            }
        }
        let candidates = families(face);
        candidates
            .iter()
            .find(|family| self.installed(family))
            .or(candidates.first())
            .map_or_else(String::new, |family| (*family).to_string())
    }

    /// カスタムテーマの書体が PostScript 名で入っている書体．ファミリーの名前(古い版で保存した値)や入っていない書体なら None
    fn named_face(&self, face: &Face) -> Option<&InstalledFace> {
        let Face::Named(name) = face else {
            return None;
        };
        if self.installed(name) {
            return None;
        }
        let faces = self.faces.get_or_init(|| {
            self.fonts
                .as_ref()
                .map_or_else(Vec::new, super::fonts::faces)
        });
        match crate::fonts::find(faces, name)? {
            Selection::Face(face) => Some(face),
            Selection::Family(_) => None,
        }
    }

    fn format(&self, spec: &FontSpec) -> Result<IDWriteTextFormat> {
        // カスタムテーマで PostScript 名の書体を選んでいれば，そのファミリーと太さ・斜体・幅で作る
        let (family, weight, style, stretch) = match self.named_face(&spec.face) {
            Some(face) => (
                face.family.clone(),
                DWRITE_FONT_WEIGHT(i32::try_from(face.weight).unwrap_or(400)),
                if face.italic {
                    DWRITE_FONT_STYLE_ITALIC
                } else {
                    DWRITE_FONT_STYLE_NORMAL
                },
                DWRITE_FONT_STRETCH(i32::try_from(face.stretch).unwrap_or(5)),
            ),
            None => (
                self.family(&spec.face),
                weight(spec.weight),
                DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_STRETCH_NORMAL,
            ),
        };
        // 配布物の書体は OS の書体の集まりに無いので，その集まりを渡す
        let collection = self.bundled.as_ref().filter(|bundled| {
            !contains(self.fonts.as_ref(), &family) && contains(Some(bundled), &family)
        });
        // SAFETY: 文字列は呼び出しのあいだ有効
        let format = unsafe {
            self.dwrite.CreateTextFormat(
                &HSTRING::from(family.as_str()),
                collection,
                weight,
                style,
                stretch,
                spec.size,
                &HSTRING::from(LOCALE),
            )?
        };
        // SAFETY: format は作ったばかりの COM の参照
        unsafe {
            format.SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER)?;
            format.SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP)?;
        }
        Ok(format)
    }

    /// target に scene を描く．BeginDraw と EndDraw は呼ぶ側が受け持つ．
    /// scale は 1 ドットのデバイスピクセル数，opacity は全体の濃さ(モードの札のフェード)
    pub fn paint(
        &self,
        target: &ID2D1RenderTarget,
        scene: &Scene,
        measure: &TextMeasure,
        scale: f32,
        opacity: f32,
    ) -> Result<()> {
        let clear = D2D1_COLOR_F::default();
        // SAFETY: target は描いている途中の COM の参照
        unsafe { target.Clear(Some(&clear)) };
        self.paint_over(target, scene, measure, scale, opacity)
    }

    /// 前に描いたものを消さずに，その上に scene を opacity の濃さで描く(重ね変わり)
    pub fn paint_over(
        &self,
        target: &ID2D1RenderTarget,
        scene: &Scene,
        measure: &TextMeasure,
        scale: f32,
        opacity: f32,
    ) -> Result<()> {
        let clear = D2D1_COLOR_F::default();
        // SAFETY: target は描いている途中の COM の参照
        let brush = unsafe { target.CreateSolidColorBrush(&clear, None)? };
        let painter = Painter {
            renderer: self,
            target,
            brush: &brush,
            measure,
            scale,
            opacity,
        };
        for draw in &scene.draws {
            painter.draw(draw)?;
        }
        Ok(())
    }
}

struct Painter<'a> {
    renderer: &'a Renderer,
    target: &'a ID2D1RenderTarget,
    brush: &'a ID2D1SolidColorBrush,
    measure: &'a TextMeasure,
    scale: f32,
    opacity: f32,
}

impl Painter<'_> {
    fn color(&self, color: Color) {
        let color = D2D1_COLOR_F {
            r: color.red,
            g: color.green,
            b: color.blue,
            a: color.alpha * self.opacity,
        };
        // SAFETY: brush は生きている COM の参照
        unsafe { self.brush.SetColor(&color) };
    }

    /// 1 ドットの線をぼかさないよう，長方形の辺をデバイスのピクセルにそろえる
    fn snapped(&self, frame: &Frame) -> D2D_RECT_F {
        let snap = |value: f32| (value * self.scale).round() / self.scale;
        D2D_RECT_F {
            left: snap(frame.x),
            top: snap(frame.y),
            right: snap(frame.max_x()),
            bottom: snap(frame.max_y()),
        }
    }

    fn stroke_style(&self, dot_pitch: Option<f32>, width: f32) -> Result<ID2D1StrokeStyle> {
        let Some(pitch) = dot_pitch else {
            return Ok(self.renderer.round.clone());
        };
        let properties = D2D1_STROKE_STYLE_PROPERTIES {
            startCap: D2D1_CAP_STYLE_ROUND,
            endCap: D2D1_CAP_STYLE_ROUND,
            dashCap: D2D1_CAP_STYLE_ROUND,
            lineJoin: D2D1_LINE_JOIN_ROUND,
            miterLimit: 1.0,
            dashStyle: D2D1_DASH_STYLE_CUSTOM,
            dashOffset: 0.0,
        };
        // 長さ 0 の線と丸い端で丸い点にする．間隔は線の太さを 1 とした長さで渡す
        let dashes = [0.0, pitch / width.max(f32::EPSILON)];
        // SAFETY: properties と dashes は呼び出しのあいだ有効
        unsafe {
            self.renderer
                .d2d
                .CreateStrokeStyle(&properties, Some(&dashes))
        }
    }

    fn draw(&self, draw: &Draw) -> Result<()> {
        match draw {
            Draw::Rect { frame, color } => {
                self.color(*color);
                // SAFETY: target・brush は生きている COM の参照
                unsafe { self.target.FillRectangle(&self.snapped(frame), self.brush) };
            }
            Draw::RoundRect {
                frame,
                radius,
                fill,
                stroke,
            } => {
                let shape = D2D1_ROUNDED_RECT {
                    rect: rect(frame),
                    radiusX: *radius,
                    radiusY: *radius,
                };
                if let Some(color) = fill {
                    self.color(*color);
                    // SAFETY: 同上
                    unsafe { self.target.FillRoundedRectangle(&shape, self.brush) };
                }
                if let Some((color, width)) = stroke {
                    self.color(*color);
                    // SAFETY: 同上
                    unsafe {
                        self.target
                            .DrawRoundedRectangle(&shape, self.brush, *width, None)
                    };
                }
            }
            Draw::Ellipse { frame, color } => {
                self.color(*color);
                let ellipse = D2D1_ELLIPSE {
                    point: vector!(frame.mid_x(), frame.mid_y()),
                    radiusX: frame.width / 2.0,
                    radiusY: frame.height / 2.0,
                };
                // SAFETY: 同上
                unsafe { self.target.FillEllipse(&ellipse, self.brush) };
            }
            Draw::Polygon { points, color } => {
                let Some((first, rest)) = points.split_first() else {
                    return Ok(());
                };
                // SAFETY: factory は生きている COM の参照．sink は閉じるまでこの関数の中だけで使う
                let geometry = unsafe {
                    let path = self.renderer.d2d.CreatePathGeometry()?;
                    let sink = path.Open()?;
                    sink.BeginFigure(vector!(first.x, first.y), D2D1_FIGURE_BEGIN_FILLED);
                    let rest: Vec<_> = rest.iter().map(|point| vector!(point.x, point.y)).collect();
                    sink.AddLines(&rest);
                    sink.EndFigure(D2D1_FIGURE_END_CLOSED);
                    sink.Close()?;
                    path
                };
                let geometry: ID2D1Geometry = geometry.into();
                self.color(*color);
                // SAFETY: target・brush・geometry は生きている COM の参照
                unsafe { self.target.FillGeometry(&geometry, self.brush, None) };
            }
            Draw::Curve {
                from,
                control1,
                control2,
                to,
                color,
                width,
            } => {
                // SAFETY: factory は生きている COM の参照．sink は閉じるまでこの関数の中だけで使う
                let geometry = unsafe {
                    let path = self.renderer.d2d.CreatePathGeometry()?;
                    let sink = path.Open()?;
                    sink.BeginFigure(vector!(from.x, from.y), D2D1_FIGURE_BEGIN_HOLLOW);
                    sink.AddBezier(&D2D1_BEZIER_SEGMENT {
                        point1: vector!(control1.x, control1.y),
                        point2: vector!(control2.x, control2.y),
                        point3: vector!(to.x, to.y),
                    });
                    sink.EndFigure(D2D1_FIGURE_END_OPEN);
                    sink.Close()?;
                    path
                };
                self.stroke(&geometry.into(), *color, *width, None)?;
            }
            Draw::Line {
                from,
                to,
                color,
                width,
                dot_pitch,
            } => {
                self.color(*color);
                let style = self.stroke_style(*dot_pitch, *width)?;
                // SAFETY: 同上
                unsafe {
                    self.target.DrawLine(
                        vector!(from.x, from.y),
                        vector!(to.x, to.y),
                        self.brush,
                        *width,
                        &style,
                    )
                };
            }
            Draw::Icon {
                icon,
                frame,
                color,
                width,
            } => {
                let figures = icon::figures(*icon, *frame);
                // SAFETY: 同上
                let geometry = unsafe {
                    let path = self.renderer.d2d.CreatePathGeometry()?;
                    let sink = path.Open()?;
                    for figure in &figures {
                        let Some((first, rest)) = figure.points.split_first() else {
                            continue;
                        };
                        sink.BeginFigure(vector!(first.x, first.y), D2D1_FIGURE_BEGIN_HOLLOW);
                        let rest: Vec<_> =
                            rest.iter().map(|point| vector!(point.x, point.y)).collect();
                        sink.AddLines(&rest);
                        sink.EndFigure(if figure.closed {
                            D2D1_FIGURE_END_CLOSED
                        } else {
                            D2D1_FIGURE_END_OPEN
                        });
                    }
                    sink.Close()?;
                    path
                };
                self.stroke(&geometry.into(), *color, *width, None)?;
            }
            Draw::Text {
                frame,
                text,
                font,
                color,
            } => {
                // 測った幅に少し余裕を持たせ，最後の字が折り返したり切れたりしないようにする
                let bounds = D2D_RECT_F {
                    left: frame.x,
                    top: frame.y,
                    right: frame.max_x() + frame.height,
                    bottom: frame.max_y(),
                };
                // DrawText と同じく，枠の幅と高さで並べた配置を枠の左上に描く(並べた配置は覚えておいて使い回す)
                let Some(layout) = self.measure.layout(
                    text,
                    *font,
                    bounds.right - bounds.left,
                    bounds.bottom - bounds.top,
                ) else {
                    return Ok(());
                };
                self.color(*color);
                // SAFETY: 同上．layout は生きている COM の参照
                unsafe {
                    self.target.DrawTextLayout(
                        vector!(bounds.left, bounds.top),
                        &layout,
                        self.brush,
                        D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT,
                    )
                };
            }
            Draw::Shadow {
                frame,
                radius,
                blur,
                color,
            } => {
                // 角丸の形を少しずつ広げて薄く重ね，ぼかした影に見せる
                let layers = (blur * SHADOW_LAYERS_PER_DOT).ceil().max(1.0);
                self.color(color.with_alpha(color.alpha / layers));
                let mut layer = 0.0;
                while layer < layers {
                    let spread = blur * (1.0 - layer / layers);
                    let shape = D2D1_ROUNDED_RECT {
                        rect: rect(&frame.inset(-spread, -spread)),
                        radiusX: radius + spread,
                        radiusY: radius + spread,
                    };
                    // SAFETY: 同上
                    unsafe { self.target.FillRoundedRectangle(&shape, self.brush) };
                    layer += 1.0;
                }
            }
        }
        Ok(())
    }

    fn stroke(
        &self,
        geometry: &ID2D1Geometry,
        color: Color,
        width: f32,
        dot_pitch: Option<f32>,
    ) -> Result<()> {
        self.color(color);
        let style = self.stroke_style(dot_pitch, width)?;
        // SAFETY: 同上
        unsafe {
            self.target
                .DrawGeometry(geometry, self.brush, width, &style)
        };
        Ok(())
    }
}

fn rect(frame: &Frame) -> D2D_RECT_F {
    D2D_RECT_F {
        left: frame.x,
        top: frame.y,
        right: frame.max_x(),
        bottom: frame.max_y(),
    }
}
