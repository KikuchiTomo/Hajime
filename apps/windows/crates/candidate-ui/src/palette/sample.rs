#![forbid(unsafe_code)]

//! 見本のパレット(macOS の SamplePalettes と同じ中身)．見た目を見比べる PNG の書き出し(デバッグビルド)と試験で使う．
//! キーの名前は Windows の書き方にする

use super::emoji::{with_skin_tone, SKIN_TONES};
use ipc::{
    KeyHint, PaletteCell, PaletteContentMotion, PaletteKind, PaletteMode, PaletteMotion,
    PalettePanel, PalettePosition, PalettePreview, PalettePreviewFields, PaletteRow,
    PaletteSkinTonePicker, PaletteTab, SkinTone,
};

/// 設定のマスの大きさの既定(core の DefaultSettings.paletteCellSize)
const CELL_SIZE: f64 = 36.0;
const COLUMNS: u32 = 9;
const VISIBLE_ROWS: u32 = 6;
/// 顔文字の 1 行の広いマスの数(列の数を core の DefaultSettings.paletteWideCellSpan で割ったもの)
const KAOMOJI_CELLS_PER_ROW: u32 = 3;

const EMOJI_ROWS: [&[&str]; 6] = [
    &["👍", "🙇", "😂", "🎉", "🙏", "✨", "👀", "🔥", "💯"],
    &["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂"],
    &["🙃", "🫠", "😉", "😊", "😇", "🥰", "😍", "🤩", "😘"],
    &["😗", "☺\u{FE0F}", "😚", "😙", "🥲", "😋", "😛", "😜", "🤪"],
    &["😝", "🤑", "🤗", "🤭", "🫢", "🫣", "🤫", "🤔", "🫡"],
    &["🤐", "🤨", "😐", "😑", "😶", "🫥", "😏", "😒", "🙄"],
];

const SYMBOL_ROWS: [&[&str]; 6] = [
    &["※", "→", "★", "〒", "①", "℃"],
    &["→", "←", "↑", "↓", "↔", "↕", "↗", "↘", "↙"],
    &["↖", "⇒", "⇐", "⇑", "⇓", "⇔", "⇕", "⟶", "⟵"],
    &["⟷", "⟹", "⟸", "⟺", "↦", "↤", "↩", "↪", "↺"],
    &["↻", "⤴", "⤵", "↰", "↱", "↲", "↳", "↴", "↵"],
    &["⇄", "⇅", "⇆", "⇇", "⇈", "⇉", "⇊", "⇋", "⇌"],
];

const KAOMOJI_ROWS: [&[&str]; 8] = [
    &["(^o^)", "m(_ _)m", "(´・ω・｀)"],
    &["＼(^o^)／", "(^o^)", "(^^)"],
    &["(*^^*)", "^_^", ":D"],
    &["・ω・", "(*´ω｀*)", "(^O^)"],
    &["(^_^)", "(・∀・)", "(*^_^*)"],
    &["ヾ(｡>﹏<｡)ﾉﾞ✧*。", "(((((((((((っ･ω･)っ ﾌﾞｰﾝ", "(*´∀｀*)"],
    &["(*´ω`*)", "(o^―^o)", "ヽ(*´∀｀)ノ"],
    &["(・ω・)", "(｀・ω・´)", "(*ﾟ▽ﾟ*)"],
];

/// 絵文字のまとまり: 送るときの名前・見出し・アイコンを描けないときの文字
const EMOJI_SECTIONS: [(&str, &str, &str); 9] = [
    ("smileys", "顔と感情", "😀"),
    ("people", "人と体", "👋"),
    ("nature", "動物と自然", "🐻"),
    ("food", "食べ物と飲み物", "🍔"),
    ("travel", "旅行と場所", "🚗"),
    ("activities", "活動", "⚽"),
    ("objects", "物", "💡"),
    ("symbols", "記号と標識", "🔣"),
    ("flags", "旗", "🏁"),
];

const SYMBOL_SECTIONS: [(&str, &str, &str); 10] = [
    ("punctuation", "句読点と約物", "、"),
    ("brackets", "括弧", "「"),
    ("arrows", "矢印", "→"),
    ("math", "数学", "±"),
    ("letters", "ギリシャ文字とキリル文字", "α"),
    ("units", "単位と通貨", "℃"),
    ("enclosed", "囲み文字", "①"),
    ("shapes", "図形", "★"),
    ("lines", "罫線", "┼"),
    ("misc", "その他の記号", "♪"),
];

const KAOMOJI_SECTIONS: [(&str, &str, &str); 8] = [
    ("joy", "笑顔", "^^"),
    ("sorrow", "悲しみ", "T_T"),
    ("sweat", "焦り", "^^;"),
    ("anger", "怒り", "`д´"),
    ("surprise", "驚き", "ﾟдﾟ"),
    ("greeting", "挨拶と動作", "ﾉｼ"),
    ("animals", "動物", "ΦωΦ"),
    ("otherFaces", "その他の顔文字", "☆彡"),
];

fn strings(texts: &[&str]) -> Vec<String> {
    texts.iter().map(|text| (*text).to_string()).collect()
}

fn hints() -> Vec<KeyHint> {
    [
        ("Enter", "入力"),
        ("Tab", "分類"),
        ("Ctrl+Tab", "種類"),
        ("Shift+Enter", "続けて入力"),
        ("Alt+Enter", "肌の色"),
        ("Ctrl+D", "ピン留め"),
        ("Esc", "閉じる"),
    ]
    .into_iter()
    .map(|(keys, label)| KeyHint {
        keys: keys.into(),
        label: label.into(),
    })
    .collect()
}

fn modes(kind: PaletteKind) -> Vec<PaletteMode> {
    [
        (PaletteKind::Emoji, "絵文字"),
        (PaletteKind::Symbol, "記号"),
        (PaletteKind::Kaomoji, "顔文字"),
    ]
    .into_iter()
    .map(|(mode, title)| PaletteMode {
        kind: mode,
        title: title.into(),
        is_selected: mode == kind,
    })
    .collect()
}

fn tab(section: &str, title: &str, symbol: &str, selected: bool) -> PaletteTab {
    PaletteTab {
        section: section.into(),
        title: title.into(),
        symbol: symbol.into(),
        is_selected: selected,
    }
}

fn tabs(first: PaletteTab, sections: &[(&str, &str, &str)], selected: &str) -> Vec<PaletteTab> {
    std::iter::once(first)
        .chain(
            sections
                .iter()
                .map(|(section, title, symbol)| tab(section, title, symbol, *section == selected)),
        )
        .collect()
}

/// 行．starts の行はまとまりの最初の行
fn rows(texts: &[&[&str]], titles: &[&str], starts: &[u32]) -> Vec<PaletteRow> {
    texts
        .iter()
        .zip(titles)
        .enumerate()
        .map(|(index, (row, title))| PaletteRow {
            index: index as u32,
            cells: row
                .iter()
                .map(|text| PaletteCell {
                    text: (*text).into(),
                    name: (*text).into(),
                    is_pinned: false,
                })
                .collect(),
            starts_section: starts.contains(&(index as u32)),
            section_title: (*title).into(),
        })
        .collect()
}

/// 説明．名前を定めたところは core の PaletteStrings.cldrSource・unicodeSource
const CLDR: Option<&str> = Some("CLDR");
const UNICODE: Option<&str> = Some("Unicode");

/// 説明の見本．値は同梱の表(data/palette/palette.tsv)の行から core(PalettePanel.Preview)が作るものと同じ
fn preview(
    text: &str,
    (name, name_source): (&str, Option<&str>),
    (unicode_name, unicode_name_source): (&str, Option<&str>),
    shortcodes: &[&str],
    readings: &[&str],
    code_points: &str,
    is_pinned: bool,
) -> PalettePreview {
    PalettePreview {
        text: text.into(),
        japanese_name: name.into(),
        english_name: unicode_name.into(),
        shortcodes: strings(shortcodes),
        readings: strings(readings),
        code_points: code_points.into(),
        is_pinned,
        name_source: name_source.map(Into::into),
        english_name_source: unicode_name_source.map(Into::into),
    }
}

/// 絵文字のパレットを開いたところ．よく使う文字の行の下に表のまとまりが続く
pub fn emoji() -> PalettePanel {
    let titles = [
        "よく使う",
        "顔と感情",
        "顔と感情",
        "顔と感情",
        "顔と感情",
        "顔と感情",
    ];
    PalettePanel {
        modes: modes(PaletteKind::Emoji),
        query: String::new(),
        placeholder: "絵文字を検索".into(),
        tabs: tabs(
            tab("frequent", "よく使う", "🕘", false),
            &EMOJI_SECTIONS,
            "smileys",
        ),
        heading: "よく使う".into(),
        rows: rows(&EMOJI_ROWS, &titles, &[0, 1]),
        row_count: 210,
        first_row: 0,
        columns: COLUMNS,
        visible_rows: VISIBLE_ROWS,
        selection: Some(PalettePosition { row: 1, column: 2 }),
        preview: Some(preview(
            "😄",
            ("笑顔", CLDR),
            ("SMILING FACE WITH OPEN MOUTH AND SMILING EYES", UNICODE),
            &[":smile:"],
            &["えがお", "すまいる", "はっぴー", "わーい"],
            "U+1F604",
            false,
        )),
        shows_preview: true,
        skin_tone: SkinTone::None,
        skin_tone_picker: None,
        message: None,
        hints: hints(),
        cell_size: CELL_SIZE,
        cells_per_row: None,
        motion: None,
        preview_fields: None,
    }
}

/// 設定の画面の見本(macOS の SamplePalettes.preview)．列数・行数・よく使う文字の行数・説明の有無と説明に出す項目・
/// マスの大きさは設定のとおりにし，絵文字は見本の並びを繰り返して埋める
pub fn settings(
    columns: u32,
    rows: u32,
    frequent_rows: u32,
    shows_preview: bool,
    fields: PalettePreviewFields,
    cell_size: f64,
) -> PalettePanel {
    let columns = columns.max(1);
    let rows = rows.max(1);
    let frequent_rows = frequent_rows.min(rows);
    let frequent: Vec<&str> = EMOJI_ROWS[0].to_vec();
    let smileys: Vec<&str> = EMOJI_ROWS[1..]
        .iter()
        .flat_map(|row| row.iter().copied())
        .collect();
    let cell = |text: &str| PaletteCell {
        text: text.into(),
        name: text.into(),
        is_pinned: false,
    };
    let mut panel_rows = Vec::new();
    for index in 0..rows {
        let (source, offset, title) = if index < frequent_rows {
            (&frequent, index * columns, "よく使う")
        } else {
            (&smileys, (index - frequent_rows) * columns, "顔と感情")
        };
        panel_rows.push(PaletteRow {
            index,
            cells: (0..columns)
                .map(|column| cell(source[((offset + column) as usize) % source.len()]))
                .collect(),
            starts_section: index == 0 || index == frequent_rows,
            section_title: title.into(),
        });
    }
    let mut panel = emoji();
    let first = if frequent_rows > 0 {
        tab("frequent", "よく使う", "🕘", false)
    } else {
        tab("smileys", "顔と感情", "😀", true)
    };
    let sections: &[(&str, &str, &str)] = if frequent_rows > 0 {
        &EMOJI_SECTIONS
    } else {
        &EMOJI_SECTIONS[1..]
    };
    panel.tabs = tabs(first, sections, "smileys");
    panel.heading = if frequent_rows > 0 {
        "よく使う"
    } else {
        "顔と感情"
    }
    .into();
    panel.rows = panel_rows;
    panel.columns = columns;
    panel.visible_rows = rows;
    panel.selection = Some(PalettePosition {
        row: 1.min(rows - 1),
        column: 2.min(columns - 1),
    });
    panel.shows_preview = shows_preview;
    // 出さない設定の項目は空にする(core の PalettePanel.Preview と同じ)
    panel.preview = panel
        .preview
        .filter(|_| shows_preview)
        .map(|preview| PalettePreview {
            english_name: if fields.unicode_name {
                preview.english_name
            } else {
                String::new()
            },
            english_name_source: preview.english_name_source.filter(|_| fields.unicode_name),
            readings: if fields.readings {
                preview.readings
            } else {
                Vec::new()
            },
            shortcodes: if fields.shortcodes {
                preview.shortcodes
            } else {
                Vec::new()
            },
            code_points: if fields.code_points {
                preview.code_points
            } else {
                String::new()
            },
            ..preview
        });
    panel.preview_fields = Some(fields);
    panel.cell_size = cell_size;
    panel
}

/// 「ojigi」と打って探したところ．肌の色の帯を開いている
pub fn search() -> PalettePanel {
    let options = SKIN_TONES
        .iter()
        .map(|tone| with_skin_tone('\u{1F647}', *tone))
        .collect();
    PalettePanel {
        modes: modes(PaletteKind::Emoji),
        query: "おじぎ".into(),
        placeholder: "絵文字を検索".into(),
        tabs: vec![],
        heading: "検索結果　3 件".into(),
        rows: rows(
            &[&["🙇", "🙇\u{200D}♂\u{FE0F}", "🙇\u{200D}♀\u{FE0F}"]],
            &["検索結果"],
            &[0],
        ),
        row_count: 1,
        first_row: 0,
        columns: COLUMNS,
        visible_rows: VISIBLE_ROWS,
        selection: Some(PalettePosition { row: 0, column: 0 }),
        preview: Some(preview(
            "🙇",
            ("おじぎする人", CLDR),
            ("PERSON BOWING DEEPLY", UNICODE),
            &[":bow:"],
            &["おじぎするひと", "おじぎ", "ごめんなさい", "じぇすちゃー"],
            "U+1F647",
            true,
        )),
        shows_preview: true,
        skin_tone: SkinTone::None,
        skin_tone_picker: Some(PaletteSkinTonePicker {
            options,
            selected: 2,
        }),
        message: None,
        hints: hints(),
        cell_size: CELL_SIZE,
        cells_per_row: None,
        motion: None,
        preview_fields: None,
    }
}

/// 「nihon」と打って探し，国旗を選んだところ．並び(国旗)には UCD の名前が無いので，CLDR の英語の名前を出す
pub fn flag() -> PalettePanel {
    PalettePanel {
        modes: modes(PaletteKind::Emoji),
        query: "にほん".into(),
        placeholder: "絵文字を検索".into(),
        tabs: vec![],
        heading: "検索結果　4 件".into(),
        rows: rows(&[&["🗾", "🏯", "🎌", "🇯🇵"]], &["検索結果"], &[0]),
        row_count: 1,
        first_row: 0,
        columns: COLUMNS,
        visible_rows: VISIBLE_ROWS,
        selection: Some(PalettePosition { row: 0, column: 3 }),
        preview: Some(preview(
            "🇯🇵",
            ("旗: 日本", CLDR),
            ("flag: Japan", CLDR),
            &[":jp:", ":flag-jp:"],
            &["にっぽん", "こっき", "しゅくじつ", "にほん"],
            "U+1F1EF U+1F1F5",
            false,
        )),
        shows_preview: true,
        skin_tone: SkinTone::None,
        skin_tone_picker: None,
        message: None,
        hints: hints(),
        cell_size: CELL_SIZE,
        cells_per_row: None,
        motion: None,
        preview_fields: None,
    }
}

/// 「tsugi」と打って探し，Unicode の名前とショートコードの長い ⏭️ を選んだところ(macOS の SamplePalettes.longName)．
/// 名前は 2 行で「…」にし，長い札は字を縮めて折り返す
pub fn long_name() -> PalettePanel {
    PalettePanel {
        query: "つぎ".into(),
        heading: "検索結果　3 件".into(),
        rows: rows(&[&["⏭\u{FE0F}", "⏩", "▶\u{FE0F}"]], &["検索結果"], &[0]),
        selection: Some(PalettePosition { row: 0, column: 0 }),
        preview: Some(preview(
            "⏭\u{FE0F}",
            ("次の曲ボタン", CLDR),
            (
                "BLACK RIGHT-POINTING DOUBLE TRIANGLE WITH VERTICAL BAR",
                UNICODE,
            ),
            &[":black_right_pointing_double_triangle_with_vertical_bar:"],
            &[
                "つぎのきょくぼたん",
                "ぼたん",
                "つぎのしーん",
                "つぎのとらっく",
            ],
            "U+23ED U+FE0F",
            false,
        )),
        ..flag()
    }
}

/// 説明に出す項目を設定で減らしたところ(Unicode の名前とショートコードだけ．macOS の SamplePalettes.reduced)
pub fn reduced() -> PalettePanel {
    let fields = PalettePreviewFields {
        unicode_name: true,
        readings: false,
        shortcodes: true,
        code_points: false,
    };
    let mut panel = emoji();
    panel.preview = panel.preview.map(|preview| PalettePreview {
        readings: Vec::new(),
        code_points: String::new(),
        ..preview
    });
    panel.preview_fields = Some(fields);
    panel
}

/// 記号のパレット．ピン留めの行の下に矢印のまとまり
pub fn symbol() -> PalettePanel {
    let titles = ["ピン留め", "矢印", "矢印", "矢印", "矢印", "矢印"];
    PalettePanel {
        modes: modes(PaletteKind::Symbol),
        query: String::new(),
        placeholder: "記号を検索".into(),
        tabs: tabs(
            tab("pinned", "ピン留め", "📌", false),
            &SYMBOL_SECTIONS,
            "arrows",
        ),
        heading: "矢印".into(),
        rows: rows(&SYMBOL_ROWS, &titles, &[0, 1]),
        row_count: 160,
        first_row: 0,
        columns: COLUMNS,
        visible_rows: VISIBLE_ROWS,
        selection: Some(PalettePosition { row: 2, column: 1 }),
        preview: Some(preview(
            "⇒",
            ("右向き二重矢印", CLDR),
            ("RIGHTWARDS DOUBLE ARROW", UNICODE),
            &[],
            &["みぎむきにじゅうやじるし", "やじるし"],
            "U+21D2",
            false,
        )),
        shows_preview: true,
        skin_tone: SkinTone::None,
        skin_tone_picker: None,
        message: None,
        hints: hints(),
        cell_size: CELL_SIZE,
        cells_per_row: None,
        motion: None,
        preview_fields: None,
    }
}

/// 顔文字のパレット．よく使う行の下に笑顔のまとまりが広いマスで続く
pub fn kaomoji() -> PalettePanel {
    let titles = [
        "よく使う",
        "笑顔",
        "笑顔",
        "笑顔",
        "笑顔",
        "笑顔",
        "笑顔",
        "笑顔",
    ];
    // 説明の欄が低い分(見出しと読みだけ)をマス目の行に回す(core の PaletteSession と同じ決め方)
    let fields = super::preview::fields(None);
    let extra = super::layout::extra_rows(
        super::preview::height(&fields, PaletteKind::Kaomoji),
        super::preview::height(&fields, PaletteKind::Emoji),
        CELL_SIZE as f32,
    );
    let visible_rows = VISIBLE_ROWS + extra;
    PalettePanel {
        modes: modes(PaletteKind::Kaomoji),
        query: String::new(),
        placeholder: "顔文字を検索".into(),
        tabs: tabs(
            tab("frequent", "よく使う", "🕘", false),
            &KAOMOJI_SECTIONS,
            "joy",
        ),
        heading: "よく使う".into(),
        rows: rows(&KAOMOJI_ROWS[..visible_rows as usize], &titles, &[0, 1]),
        row_count: 48,
        first_row: 0,
        columns: COLUMNS,
        visible_rows,
        selection: Some(PalettePosition { row: 0, column: 2 }),
        preview: Some(preview(
            "(´・ω・｀)",
            ("しょぼーん", None),
            ("", None),
            &[],
            &["しょんぼり", "がっかり"],
            "",
            false,
        )),
        shows_preview: true,
        skin_tone: SkinTone::None,
        skin_tone_picker: None,
        message: None,
        hints: hints(),
        cell_size: CELL_SIZE,
        cells_per_row: Some(KAOMOJI_CELLS_PER_ROW),
        motion: None,
        preview_fields: None,
    }
}

/// 動きの途中のコマの見本(macOS の SamplePalettes.motionSteps)．前の内容・動きを添えた次の内容・描く時刻(ミリ秒)
pub fn motion_steps() -> Vec<(PalettePanel, PalettePanel, f32)> {
    use tokens::motion::palette as duration;
    let still = PaletteMotion {
        selection_from: None,
        mode_from: None,
        tab_from: None,
        content: None,
        opens_picker: false,
        toggles_pin: false,
    };
    // 選択の枠が右下へ滑り，タブの印も次のまとまりへ滑る
    let mut moved = emoji();
    moved.selection = Some(PalettePosition { row: 3, column: 6 });
    for (index, tab) in moved.tabs.iter_mut().enumerate() {
        tab.is_selected = index == 2;
    }
    moved.motion = Some(PaletteMotion {
        selection_from: emoji().selection,
        tab_from: Some("smileys".into()),
        ..still.clone()
    });
    // 絵文字から記号へ切り替えて，種類の印を滑らせ，中身を左へ送る
    let switched = PalettePanel {
        motion: Some(PaletteMotion {
            mode_from: Some(PaletteKind::Emoji),
            content: Some(PaletteContentMotion::Next),
            ..still.clone()
        }),
        ..symbol()
    };
    // 肌の色の帯が浮かび上がる
    let before = PalettePanel {
        skin_tone_picker: None,
        ..search()
    };
    let picking = PalettePanel {
        motion: Some(PaletteMotion {
            opens_picker: true,
            ..still
        }),
        ..search()
    };
    vec![
        (emoji(), moved, duration::INDICATOR / 2.0),
        (emoji(), switched, duration::CONTENT / 2.0),
        (before, picking, duration::POP / 3.0),
    ]
}
