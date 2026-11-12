#![forbid(unsafe_code)]

//! 見本のパレット(macOS の SamplePalettes と同じ中身)．見た目を見比べる PNG の書き出し(デバッグビルド)と試験で使う．
//! キーの名前は Windows の書き方にする

use super::emoji::{with_skin_tone, SKIN_TONES};
use ipc::{
    KeyHint, PaletteCell, PaletteKind, PaletteMode, PalettePanel, PalettePosition, PalettePreview,
    PaletteRow, PaletteSkinTonePicker, PaletteTab, SkinTone,
};

/// 設定のマスの大きさの既定(core の DefaultSettings.paletteCellSize)
const CELL_SIZE: f64 = 36.0;
const COLUMNS: u32 = 9;
const VISIBLE_ROWS: u32 = 6;

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

fn strings(texts: &[&str]) -> Vec<String> {
    texts.iter().map(|text| (*text).to_string()).collect()
}

fn hints() -> Vec<KeyHint> {
    [
        ("Enter", "入力"),
        ("Tab", "分類"),
        ("Ctrl+Tab", "絵文字と記号"),
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

#[allow(clippy::too_many_arguments)]
fn preview(
    text: &str,
    japanese_name: &str,
    english_name: &str,
    shortcodes: &[&str],
    readings: &[&str],
    code_points: &str,
    is_pinned: bool,
) -> PalettePreview {
    PalettePreview {
        text: text.into(),
        japanese_name: japanese_name.into(),
        english_name: english_name.into(),
        shortcodes: strings(shortcodes),
        readings: strings(readings),
        code_points: code_points.into(),
        is_pinned,
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
            "目も笑っている笑顔",
            "grinning face with smiling eyes",
            &[":smile:"],
            &["めもわらっているえがお", "えがお", "すまいる"],
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
    }
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
            "おじぎする人",
            "person bowing",
            &[":bow:"],
            &["おじぎするひと", "おじぎ", "ごめんなさい", "どげざ"],
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
    }
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
            "右向き二重矢印",
            "rightwards double arrow",
            &[],
            &["みぎむきにじゅうやじるし", "ならば", "やじるし"],
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
    }
}
