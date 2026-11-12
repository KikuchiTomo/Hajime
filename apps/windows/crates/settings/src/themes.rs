#![forbid(unsafe_code)]

//! カスタムテーマ(macOS の AppearancePage・CustomThemeEditor)．設定のファイルの customThemes と customThemeID をそのまま読み書きする．
//! 選んだテーマの色・形・書体は「customTheme.」で始まる道筋の値にし，ほかのページと同じ部品で出して書き換える

use crate::model::SettingsModel;
use crate::store::{Fields, SettingsStore, StoreError};
use crate::strings::{more, windows};
use serde_json::{json, Map, Value};

pub const THEMES: &str = "customThemes";
pub const ACTIVE: &str = "customThemeID";
/// 既成のテーマを選ぶ設定(カスタムテーマを使っているときは，その名前を選んだ状態で見せる)
pub const BASE_THEME: &str = "theme";

/// 編集しているテーマの id(選んでいなければ空)
pub const ID: &str = "customTheme.id";
/// 読みにくい組み合わせの知らせ(無ければ空)
pub const READABILITY: &str = "customTheme.readability";
const PREFIX: &str = "customTheme.";

/// 編集できる値(道筋の後ろと設定のファイルの名前が同じ)
pub const COLORS: &[(&str, &str)] = &[
    ("customTheme.surface", more::SURFACE),
    ("customTheme.text", more::TEXT),
    ("customTheme.textMuted", more::TEXT_MUTED),
    ("customTheme.selection", more::SELECTION),
    ("customTheme.selectionText", more::SELECTION_TEXT),
    ("customTheme.correction", more::CORRECTION),
    ("customTheme.line", more::LINE),
];
pub const CORNER_RADIUS: &str = "customTheme.cornerRadius";
pub const BRANCH_STYLE: &str = "customTheme.branchStyle";
pub const FONT_NAME: &str = "customTheme.fontName";

pub fn is_theme_path(path: &str) -> bool {
    path.starts_with(PREFIX)
}

/// 一覧の 1 行
#[derive(Debug, Clone, PartialEq)]
pub struct Entry {
    pub id: String,
    pub name: String,
    pub value: Value,
}

pub fn entries(themes: Option<&Value>) -> Vec<Entry> {
    let Some(Value::Array(elements)) = themes else {
        return Vec::new();
    };
    elements
        .iter()
        .filter_map(|element| {
            Some(Entry {
                id: element.get("id")?.as_str()?.to_string(),
                name: element.get("name")?.as_str()?.to_string(),
                value: element.clone(),
            })
        })
        .collect()
}

/// 使っているカスタムテーマの名前．使っていなければ None
pub fn active_name(themes: Option<&Value>, active: &str) -> Option<String> {
    if active.is_empty() {
        return None;
    }
    entries(themes)
        .into_iter()
        .find(|entry| entry.id == active)
        .map(|entry| entry.name)
}

/// ほかのテーマと重ならない名前(「新しいテーマ」「新しいテーマ 2」…)
pub fn unique_name(base: &str, entries: &[Entry]) -> String {
    let taken = |name: &str| entries.iter().any(|entry| entry.name == name);
    if !taken(base) {
        return base.to_string();
    }
    (2..)
        .map(|number| format!("{base} {number}"))
        .find(|name| !taken(name))
        .unwrap_or_else(|| base.to_string())
}

/// 表の行(名前・状態)
pub fn table(entries: &[Entry], active: Option<&str>) -> Vec<Vec<String>> {
    entries
        .iter()
        .map(|entry| {
            let state = if active == Some(entry.id.as_str()) {
                windows::IN_USE
            } else {
                ""
            };
            vec![entry.name.clone(), state.to_string()]
        })
        .collect()
}

/// 編集しているテーマの値(「customTheme.」の道筋)．テーマを選んでいなければ id だけを空にする
pub fn values(entry: Option<&Entry>, readability: &str) -> Fields {
    let mut values = Fields::new();
    values.insert(
        ID.into(),
        Value::String(entry.map_or_else(String::new, |entry| entry.id.clone())),
    );
    values.insert(READABILITY.into(), Value::String(readability.to_string()));
    let Some(entry) = entry else {
        return values;
    };
    for name in COLORS
        .iter()
        .map(|(path, _)| *path)
        .chain([CORNER_RADIUS, BRANCH_STYLE])
    {
        if let Some(value) = entry.value.get(field(name)) {
            values.insert(name.into(), value.clone());
        }
    }
    let font = entry
        .value
        .get("fontName")
        .and_then(Value::as_str)
        .unwrap_or("");
    values.insert(FONT_NAME.into(), Value::String(font.to_string()));
    values
}

fn field(path: &str) -> &str {
    path.strip_prefix(PREFIX).unwrap_or(path)
}

/// 「#RRGGBB」か
pub fn is_hex_color(text: &str) -> bool {
    text.len() == 7
        && text.starts_with('#')
        && text[1..]
            .chars()
            .all(|character| character.is_ascii_hexdigit())
}

/// 編集しているテーマ(id)の値を path・value で書き換えた配列．書き換えられなければ None
pub fn edited(themes: Option<&Value>, id: &str, path: &str, value: &Value) -> Option<Value> {
    let mut elements = themes?.as_array()?.clone();
    let element = elements
        .iter_mut()
        .find(|element| element.get("id").and_then(Value::as_str) == Some(id))?
        .as_object_mut()?;
    let name = field(path);
    match path {
        FONT_NAME => {
            let font = value.as_str()?;
            if font.is_empty() {
                element.remove("fontName");
            } else {
                element.insert("fontName".into(), Value::String(font.to_string()));
            }
        }
        CORNER_RADIUS => {
            element.insert(name.into(), json!(value.as_f64()?));
        }
        BRANCH_STYLE => {
            element.insert(name.into(), Value::String(value.as_str()?.to_string()));
        }
        _ if COLORS.iter().any(|(color, _)| *color == path) => {
            let color = value.as_str()?;
            if !is_hex_color(color) {
                return None;
            }
            element.insert(name.into(), Value::String(color.to_uppercase()));
        }
        _ => return None,
    }
    Some(Value::Array(elements))
}

/// 編集しているテーマ(id)の path の値を value にして，設定のファイルの customThemes に書く．書き換えられない値なら None
pub fn write<S: SettingsStore>(
    model: &mut SettingsModel<S>,
    id: &str,
    path: &str,
    value: &Value,
) -> Option<Result<(), StoreError>> {
    let changed = edited(model.value(THEMES), id, path, value)?;
    Some(model.set(THEMES, changed))
}

/// 名前を書き換えた配列．空の名前は None(macOS と同じく名前を入れないと保存しない)
pub fn renamed(themes: Option<&Value>, id: &str, name: &str, maximum: usize) -> Option<Value> {
    let name: String = name.trim().chars().take(maximum).collect();
    if name.is_empty() {
        return None;
    }
    let mut elements = themes?.as_array()?.clone();
    let element = elements
        .iter_mut()
        .find(|element| element.get("id").and_then(Value::as_str) == Some(id))?
        .as_object_mut()?;
    element.insert("name".into(), Value::String(name));
    Some(Value::Array(elements))
}

/// 新しいテーマを後ろに足した配列(使うテーマにもする)
pub fn appended(themes: Option<&Value>, theme: Map<String, Value>) -> Value {
    let mut elements = themes
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    elements.push(Value::Object(theme));
    Value::Array(elements)
}

/// テーマを消した配列
pub fn removed(themes: Option<&Value>, id: &str) -> Option<Value> {
    let mut elements = themes?.as_array()?.clone();
    elements.retain(|element| element.get("id").and_then(Value::as_str) != Some(id));
    Some(Value::Array(elements))
}

/// source を写して新しい id と名前にしたテーマ
pub fn copy(source: &Value, id: String, name: String) -> Option<Map<String, Value>> {
    let mut theme = source.as_object()?.clone();
    theme.insert("id".into(), Value::String(id));
    theme.insert("name".into(), Value::String(name));
    Some(theme)
}

/// 既成のテーマの色を写した新しいテーマ(色は「#RRGGBB」)
pub fn from_colors(
    id: String,
    name: String,
    base: &str,
    colors: [(&str, String); 7],
    corner_radius: f64,
) -> Map<String, Value> {
    let mut theme = Map::new();
    theme.insert("id".into(), Value::String(id));
    theme.insert("name".into(), Value::String(name));
    theme.insert("base".into(), Value::String(base.to_string()));
    for (name, color) in colors {
        theme.insert(name.into(), Value::String(color));
    }
    theme.insert("cornerRadius".into(), json!(corner_radius));
    theme.insert("branchStyle".into(), Value::String("curved".into()));
    theme
}

/// 新しいテーマの id．seed(時刻など)から UUID の形の文字列を作る
pub fn new_id(seed: u128) -> String {
    let hex = format!("{seed:032X}");
    format!(
        "{}-{}-{}-{}-{}",
        &hex[0..8],
        &hex[8..12],
        &hex[12..16],
        &hex[16..20],
        &hex[20..32]
    )
}

/// 設定のファイルのテーマを，候補ウィンドウに渡す形(ipc::CustomTheme)にする
pub fn to_wire(value: &Value) -> Option<ipc::CustomTheme> {
    let color = |name: &str| {
        let (red, green, blue) = rgb(value.get(name)?.as_str()?)?;
        Some(ipc::Color { red, green, blue })
    };
    Some(ipc::CustomTheme {
        base: value.get("base")?.as_str()?.to_string(),
        surface: color("surface")?,
        text: color("text")?,
        text_muted: color("textMuted")?,
        selection: color("selection")?,
        selection_text: color("selectionText")?,
        correction: color("correction")?,
        line: color("line")?,
        font_name: value
            .get("fontName")
            .and_then(Value::as_str)
            .map(str::to_string),
        corner_radius: value
            .get("cornerRadius")
            .and_then(Value::as_f64)
            .unwrap_or(0.0),
        straight_branches: value.get("branchStyle").and_then(Value::as_str) == Some("straight"),
    })
}

/// 0〜1 の色を「#RRGGBB」にする
pub fn hex(red: f32, green: f32, blue: f32) -> String {
    let channel = |value: f32| (value.clamp(0.0, 1.0) * 255.0).round() as u8;
    format!(
        "#{:02X}{:02X}{:02X}",
        channel(red),
        channel(green),
        channel(blue)
    )
}

/// 赤・緑・青を「#RRGGBB」にする(色を選ぶ窓で選んだ色を書く値)
pub fn hex_of((red, green, blue): (u8, u8, u8)) -> String {
    format!("#{red:02X}{green:02X}{blue:02X}")
}

/// 赤・緑・青を Win32 の COLORREF(0x00BBGGRR)にする
pub fn colorref((red, green, blue): (u8, u8, u8)) -> u32 {
    u32::from(red) | (u32::from(green) << 8) | (u32::from(blue) << 16)
}

/// Win32 の COLORREF(0x00BBGGRR)を赤・緑・青にする
pub fn from_colorref(value: u32) -> (u8, u8, u8) {
    (
        (value & 0xFF) as u8,
        ((value >> 8) & 0xFF) as u8,
        ((value >> 16) & 0xFF) as u8,
    )
}

/// 「#RRGGBB」を赤・緑・青にする
pub fn rgb(text: &str) -> Option<(u8, u8, u8)> {
    if !is_hex_color(text) {
        return None;
    }
    let value = u32::from_str_radix(&text[1..], 16).ok()?;
    Some(((value >> 16) as u8, (value >> 8) as u8, value as u8))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn themes() -> Value {
        json!([
            {"id": "a", "name": "夕焼け", "base": "automatic", "surface": "#2B1B17", "text": "#FFE8D6", "textMuted": "#C9A68F",
             "selection": "#FF7A3D", "selectionText": "#1B0F0B", "correction": "#FFB070", "line": "#5A3A2E",
             "cornerRadius": 10.0, "branchStyle": "curved"},
            {"id": "b", "name": "海", "base": "platinum", "surface": "#FFFFFF", "text": "#000000", "textMuted": "#555555",
             "selection": "#0040FF", "selectionText": "#FFFFFF", "correction": "#FF0000", "line": "#CCCCCC",
             "fontName": "Meiryo UI", "cornerRadius": 0.0, "branchStyle": "straight"}
        ])
    }

    #[test]
    fn 新しいテーマの名前は重ならない() {
        let themes = serde_json::json!([
            {"id": "a", "name": "新しいテーマ"},
            {"id": "b", "name": "新しいテーマ 2"},
        ]);
        let list = entries(Some(&themes));
        assert_eq!(unique_name("新しいテーマ", &list), "新しいテーマ 3");
        assert_eq!(unique_name("夜", &list), "夜");
    }

    #[test]
    fn 使っているカスタムテーマの名前() {
        let themes = serde_json::json!([{"id": "a", "name": "夜"}]);
        assert_eq!(active_name(Some(&themes), "a").as_deref(), Some("夜"));
        assert_eq!(active_name(Some(&themes), ""), None);
        assert_eq!(active_name(Some(&themes), "z"), None);
    }

    #[test]
    fn 一覧と編集の値を読む() {
        let entries = entries(Some(&themes()));
        assert_eq!(
            table(&entries, Some("b")),
            vec![
                vec!["夕焼け".to_string(), String::new()],
                vec!["海".to_string(), "使用中".to_string()]
            ]
        );
        let values = values(entries.get(1), "");
        assert_eq!(values[ID], "b");
        assert_eq!(values["customTheme.surface"], "#FFFFFF");
        assert_eq!(values[FONT_NAME], "Meiryo UI");
        assert_eq!(values[BRANCH_STYLE], "straight");
        assert_eq!(super::values(None, "")[ID], "");
    }

    #[test]
    fn 色と形と書体を書き換える() {
        let changed = edited(Some(&themes()), "a", "customTheme.text", &json!("#abcdef")).unwrap();
        assert_eq!(changed[0]["text"], "#ABCDEF");
        assert_eq!(
            edited(Some(&themes()), "a", "customTheme.text", &json!("red")),
            None
        );
        let changed = edited(Some(&themes()), "b", FONT_NAME, &json!("")).unwrap();
        assert!(changed[1].get("fontName").is_none());
        let changed = edited(Some(&themes()), "a", CORNER_RADIUS, &json!(4)).unwrap();
        assert_eq!(changed[0]["cornerRadius"], 4.0);
        assert_eq!(edited(Some(&themes()), "x", CORNER_RADIUS, &json!(4)), None);
    }

    #[test]
    fn 名前を変え_複製し_消す() {
        assert_eq!(renamed(Some(&themes()), "a", "  ", 32), None);
        assert_eq!(
            renamed(Some(&themes()), "a", " 朝焼け ", 32).unwrap()[0]["name"],
            "朝焼け"
        );
        let copy = copy(&themes()[0], "c".into(), "夕焼け のコピー".into()).unwrap();
        let added = appended(Some(&themes()), copy);
        assert_eq!(added[2]["id"], "c");
        assert_eq!(added[2]["surface"], "#2B1B17");
        assert_eq!(
            removed(Some(&added), "a")
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            2
        );
    }

    #[test]
    fn 候補ウィンドウに渡す形にする() {
        let wire = to_wire(&themes()[1]).unwrap();
        assert_eq!(wire.base, "platinum");
        assert_eq!(
            wire.selection,
            ipc::Color {
                red: 0,
                green: 0x40,
                blue: 0xFF
            }
        );
        assert_eq!(wire.font_name.as_deref(), Some("Meiryo UI"));
        assert!(wire.straight_branches);
        assert_eq!(new_id(1).len(), 36);
    }

    #[test]
    fn 色の書き方() {
        assert_eq!(hex(1.0, 0.5, 0.0), "#FF8000");
        assert_eq!(rgb("#FF8000"), Some((255, 128, 0)));
        assert_eq!(rgb("FF8000"), None);
        assert_eq!(hex_of((0x33, 0x66, 0x99)), "#336699");
        assert_eq!(hex_of((0, 0x0A, 0xFF)), "#000AFF");
    }

    #[test]
    fn 色を選ぶ窓の色を赤_緑_青と行き来する() {
        assert_eq!(colorref((0x12, 0x34, 0x56)), 0x0056_3412);
        assert_eq!(from_colorref(0x0056_3412), (0x12, 0x34, 0x56));
        let current = rgb("#2B1B17").unwrap();
        assert_eq!(hex_of(from_colorref(colorref(current))), "#2B1B17");
    }

    #[test]
    fn 選んだ色を編集しているテーマに書いて保存する() {
        use crate::catalog::Catalog;
        use crate::store::fake::FakeStore;
        use std::cell::RefCell;

        let fields = |value: Value| value.as_object().cloned().unwrap();
        let store = FakeStore {
            current: RefCell::new(fields(
                json!({"customThemes": themes(), "customThemeID": "a"}),
            )),
            defaults: fields(json!({"customThemes": [], "customThemeID": null})),
            ..Default::default()
        };
        let mut catalog = Catalog::load().unwrap();
        catalog.fields = vec![THEMES.to_string(), ACTIVE.to_string()];
        let mut model = SettingsModel::load(store, &catalog).unwrap();

        // 色を選ぶ窓で #336699 を選ぶ(actions.rs の After::ChooseColor と同じ値)
        let chosen = Value::String(hex_of(from_colorref(colorref((0x33, 0x66, 0x99)))));
        write(&mut model, "a", "customTheme.text", &chosen)
            .unwrap()
            .unwrap();
        let written = model.store().writes.borrow().last().cloned().unwrap();
        assert_eq!(written.keys().collect::<Vec<_>>(), vec![THEMES]);
        assert_eq!(written[THEMES][0]["text"], "#336699");
        assert_eq!(written[THEMES][0]["surface"], "#2B1B17");
        assert_eq!(written[THEMES][1], themes()[1]);
        assert_eq!(model.value(THEMES).unwrap()[0]["text"], "#336699");
        assert_eq!(
            values(entries(model.value(THEMES)).first(), "")["customTheme.text"],
            "#336699"
        );

        // 色でない値や，無いテーマは書かない
        let count = model.store().writes.borrow().len();
        assert!(write(&mut model, "a", "customTheme.text", &json!("blue")).is_none());
        assert!(write(&mut model, "z", "customTheme.text", &chosen).is_none());
        assert_eq!(model.store().writes.borrow().len(), count);
    }
}
