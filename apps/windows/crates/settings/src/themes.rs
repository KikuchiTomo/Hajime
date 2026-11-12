#![forbid(unsafe_code)]

//! カスタムテーマ(macOS の AppearancePage・CustomThemeEditor)．設定のファイルの customThemes と customThemeID をそのまま読み書きする．
//! 編集の画面では，テーマの下書きの名前・色・形・書体を「customTheme.」で始まる道筋の値にし，ほかのページと同じ部品で出して
//! 書き換える．「保存」を押すまで設定のファイルには書かない(saved)

use crate::store::Fields;
use crate::strings::more;
use ipc::{ContrastIssue, ContrastPair};
use serde_json::{json, Map, Value};

pub const THEMES: &str = "customThemes";
pub const ACTIVE: &str = "customThemeID";
/// 既成のテーマを選ぶ設定(カスタムテーマを使っているときは，その名前を選んだ状態で見せる)
pub const BASE_THEME: &str = "theme";

/// カスタムテーマが 1 つも無い(一覧の代わりに知らせを出す)
pub const EMPTY: &str = "customTheme.empty";
/// まだ作れる(上限まで作っていない)
pub const ROOM: &str = "customTheme.room";
const PREFIX: &str = "customTheme.";

/// 編集できる値(道筋の後ろと設定のファイルの名前が同じ)
pub const NAME: &str = "customTheme.name";
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

/// 読みやすさを確かめる組み合わせの数(ipc::ContrastPair の数．編集の画面の知らせの行の数)
pub const CONTRAST_PAIRS: usize = 4;

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

/// 一覧の値(「customTheme.」の道筋)．count は今あるテーマの数，limit は作れる数の上限
pub fn list_values(count: usize, limit: usize) -> Fields {
    let mut values = Fields::new();
    values.insert(EMPTY.into(), Value::Bool(count == 0));
    values.insert(ROOM.into(), Value::Bool(count < limit));
    values
}

/// 編集しているテーマの下書きの値(「customTheme.」の道筋)
pub fn draft_values(draft: &Value) -> Fields {
    let mut values = Fields::new();
    for name in std::iter::once(NAME)
        .chain(COLORS.iter().map(|(path, _)| *path))
        .chain([CORNER_RADIUS, BRANCH_STYLE])
    {
        if let Some(value) = draft.get(field(name)) {
            values.insert(name.into(), value.clone());
        }
    }
    let font = draft.get("fontName").and_then(Value::as_str).unwrap_or("");
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

/// 下書き(テーマ)の path の値を value にする．書き換えられない値なら None．
/// 名前は打ったまま持ち，空白を除くのは保存するとき(macOS の CustomThemeEditor の trimmedName)
pub fn edit(draft: &mut Value, path: &str, value: &Value) -> Option<()> {
    let element = draft.as_object_mut()?;
    let name = field(path);
    match path {
        NAME => {
            element.insert(name.into(), Value::String(value.as_str()?.to_string()));
        }
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
    Some(())
}

/// 保存する名前(前後の空白を除き，上限の長さで切る)
pub fn trimmed_name(draft: &Value, maximum: usize) -> String {
    draft
        .get("name")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .chars()
        .take(maximum)
        .collect()
}

/// 保存できないわけ(macOS の SettingsModel.saveCustomTheme)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SaveError {
    /// 名前が空
    Name,
    /// 上限まで作っている(新しいテーマを足せない)
    Full,
}

/// 下書きを保存した配列．同じ id のテーマがあれば置き換え，無ければ後ろに足す(macOS の saveCustomTheme)．
/// 名前は前後の空白を除き，上限の長さで切る
pub fn saved(
    themes: Option<&Value>,
    draft: &Value,
    limit: usize,
    name_limit: usize,
) -> Result<Value, SaveError> {
    let name = trimmed_name(draft, name_limit);
    if name.is_empty() {
        return Err(SaveError::Name);
    }
    let mut theme = draft.clone();
    if let Some(element) = theme.as_object_mut() {
        element.insert("name".into(), Value::String(name));
    }
    let id = draft.get("id").and_then(Value::as_str);
    let mut elements = themes
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let count = elements.len();
    match elements
        .iter_mut()
        .find(|element| element.get("id").and_then(Value::as_str) == id)
    {
        Some(element) => *element = theme,
        None if count >= limit => return Err(SaveError::Full),
        None => elements.push(theme),
    }
    Ok(Value::Array(elements))
}

/// 色(path)が読みにくい組み合わせに入るか(macOS の CustomThemeEditor の色の行の印)
pub fn warns(path: &str, pairs: &[ContrastPair]) -> bool {
    let pair = match field(path) {
        "text" => ContrastPair::Text,
        "textMuted" => ContrastPair::TextMuted,
        "selection" | "selectionText" => ContrastPair::SelectionText,
        "correction" => ContrastPair::Correction,
        _ => return false,
    };
    pairs.contains(&pair)
}

/// 読みにくい組み合わせの知らせの文(UIStrings.More.lowContrast)
pub fn issue_text(issue: &ContrastIssue) -> String {
    let (name, ground) = match issue.pair {
        ContrastPair::Text => (more::TEXT, more::SURFACE),
        ContrastPair::TextMuted => (more::TEXT_MUTED, more::SURFACE),
        ContrastPair::SelectionText => (more::SELECTION_TEXT, more::SELECTION),
        ContrastPair::Correction => (more::CORRECTION, more::SURFACE),
    };
    more::low_contrast(name, ground, issue.ratio, issue.minimum)
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
    fn 使っているカスタムテーマの名前() {
        let themes = serde_json::json!([{"id": "a", "name": "夜"}]);
        assert_eq!(active_name(Some(&themes), "a").as_deref(), Some("夜"));
        assert_eq!(active_name(Some(&themes), ""), None);
        assert_eq!(active_name(Some(&themes), "z"), None);
    }

    #[test]
    fn 一覧と下書きの値を読む() {
        assert_eq!(list_values(0, 50)[EMPTY], true);
        assert_eq!(list_values(2, 50)[EMPTY], false);
        assert_eq!(list_values(2, 50)[ROOM], true);
        assert_eq!(list_values(50, 50)[ROOM], false);
        let values = draft_values(&themes()[1]);
        assert_eq!(values[NAME], "海");
        assert_eq!(values["customTheme.surface"], "#FFFFFF");
        assert_eq!(values[FONT_NAME], "Meiryo UI");
        assert_eq!(values[BRANCH_STYLE], "straight");
        assert_eq!(draft_values(&themes()[0])[FONT_NAME], "");
    }

    #[test]
    fn 下書きの名前と色と形と書体を書き換える() {
        let mut draft = themes()[0].clone();
        edit(&mut draft, "customTheme.text", &json!("#abcdef")).unwrap();
        assert_eq!(draft["text"], "#ABCDEF");
        assert_eq!(edit(&mut draft, "customTheme.text", &json!("red")), None);
        assert_eq!(draft["text"], "#ABCDEF");
        edit(&mut draft, CORNER_RADIUS, &json!(4)).unwrap();
        assert_eq!(draft["cornerRadius"], 4.0);
        edit(&mut draft, NAME, &json!(" 朝焼け ")).unwrap();
        assert_eq!(draft["name"], " 朝焼け ");
        assert_eq!(trimmed_name(&draft, 2), "朝焼");
        let mut second = themes()[1].clone();
        edit(&mut second, FONT_NAME, &json!("")).unwrap();
        assert!(second.get("fontName").is_none());
        assert_eq!(edit(&mut second, "customTheme.base", &json!("x")), None);
    }

    #[test]
    fn 下書きを保存すると置き換えるか足す() {
        let mut draft = themes()[0].clone();
        edit(&mut draft, NAME, &json!("  朝焼け  ")).unwrap();
        let changed = saved(Some(&themes()), &draft, 50, 40).unwrap();
        assert_eq!(changed.as_array().unwrap().len(), 2);
        assert_eq!(changed[0]["name"], "朝焼け");
        assert_eq!(changed[1], themes()[1]);
        let copy = copy(&themes()[0], "c".into(), "夕焼け のコピー".into()).unwrap();
        let added = saved(Some(&themes()), &Value::Object(copy.clone()), 50, 40).unwrap();
        assert_eq!(added[2]["id"], "c");
        assert_eq!(added[2]["surface"], "#2B1B17");
        // 上限まで作っていれば足せない(置き換えはできる)．名前が空なら保存しない
        assert_eq!(
            saved(Some(&themes()), &Value::Object(copy), 2, 40),
            Err(SaveError::Full)
        );
        assert!(saved(Some(&themes()), &draft, 2, 40).is_ok());
        edit(&mut draft, NAME, &json!("   ")).unwrap();
        assert_eq!(saved(Some(&themes()), &draft, 50, 40), Err(SaveError::Name));
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
    fn 読みにくい組み合わせに入る色に印を付ける() {
        let pairs = [ContrastPair::SelectionText];
        assert!(warns("customTheme.selection", &pairs));
        assert!(warns("customTheme.selectionText", &pairs));
        assert!(!warns("customTheme.text", &pairs));
        assert!(!warns("customTheme.line", &[ContrastPair::Text]));
        let text = issue_text(&ContrastIssue {
            pair: ContrastPair::TextMuted,
            ratio: 2.2,
            minimum: 4.5,
        });
        assert_eq!(
            text,
            "補助の文字と背景の色が近く、読みにくくなっています。コントラスト比は 2.2 で、4.5 以上が目安です。"
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
    fn 選んだ色を下書きに書き_保存すると設定のファイルに書く() {
        use crate::catalog::Catalog;
        use crate::model::SettingsModel;
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

        // 色を選ぶ窓で #336699 を選ぶ(actions.rs の After::ChooseColor と同じ値)．保存するまでは書かない
        let mut draft = entries(model.value(THEMES))[0].value.clone();
        let chosen = Value::String(hex_of(from_colorref(colorref((0x33, 0x66, 0x99)))));
        edit(&mut draft, "customTheme.text", &chosen).unwrap();
        assert_eq!(draft_values(&draft)["customTheme.text"], "#336699");
        assert!(model.store().writes.borrow().is_empty());

        // 保存すると customThemes と使うテーマを書く(macOS の saveCustomTheme)
        let changed = saved(model.value(THEMES), &draft, 50, 40).unwrap();
        model
            .set_all(&[(THEMES, changed), (ACTIVE, Value::String("a".into()))])
            .unwrap();
        let written = model.store().writes.borrow().last().cloned().unwrap();
        assert_eq!(written[THEMES][0]["text"], "#336699");
        assert_eq!(written[THEMES][0]["surface"], "#2B1B17");
        assert_eq!(written[THEMES][1], themes()[1]);
        assert_eq!(model.value(THEMES).unwrap()[0]["text"], "#336699");

        // 色でない値は下書きにも書かない
        assert!(edit(&mut draft, "customTheme.text", &json!("blue")).is_none());
        assert_eq!(draft["text"], "#336699");
    }
}
