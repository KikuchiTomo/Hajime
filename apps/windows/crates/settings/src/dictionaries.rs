#![forbid(unsafe_code)]

//! 取り込んだ辞書・連想の辞書の一覧(macOS の ImportedDictionariesView・AssociationSection)．
//! 一覧は設定のファイルの配列(importedDictionaries・associationDictionaries)をそのまま読み書きする．
//! 名前・分野・使う場面・アプリ・オン・オフ・並びはここで変え，取り込みと削除(索引のファイルがある)はエンジンに頼む

use crate::pages::DictionaryList;
use crate::strings::{association, dictionaries, windows};
use serde_json::{json, Map, Value};

/// 使う場面(DictionaryCondition)の名前．設定のファイルの書き方と同じ
pub const ALWAYS: &str = "always";
pub const APPS: &str = "apps";
pub const CONTEXT: &str = "context";

/// 一覧の 1 行
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub id: String,
    pub name: String,
    /// 分野(連想の辞書には無い)
    pub field: String,
    pub is_enabled: bool,
    /// 使う場面(always・apps・context)．連想の辞書は always
    pub condition: String,
    /// 使う場面が選んだアプリのときのアプリ
    pub apps: Vec<String>,
    /// 語の数(取り込んだ辞書)か意味の数(連想の辞書)
    pub count: u64,
    /// アプリに同梱した辞書(消せない・取り込み直せない)
    pub is_bundled: bool,
}

/// 設定の値の配列を行にする．形の合わない要素は飛ばす
pub fn entries(list: DictionaryList, value: Option<&Value>) -> Vec<Entry> {
    let Some(Value::Array(elements)) = value else {
        return Vec::new();
    };
    elements
        .iter()
        .filter_map(|element| entry(list, element))
        .collect()
}

fn entry(list: DictionaryList, element: &Value) -> Option<Entry> {
    let text = |key| {
        element
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string()
    };
    let condition = element.get("condition").and_then(Value::as_object);
    let (condition_name, apps) = match condition.and_then(|map| map.iter().next()) {
        Some((name, inner)) => (
            name.clone(),
            inner
                .get("_0")
                .and_then(Value::as_array)
                .map(|apps| {
                    apps.iter()
                        .filter_map(Value::as_str)
                        .map(str::to_string)
                        .collect()
                })
                .unwrap_or_default(),
        ),
        None => (ALWAYS.to_string(), Vec::new()),
    };
    let count_key = match list {
        DictionaryList::Imported => "wordCount",
        DictionaryList::Association => "groupCount",
    };
    Some(Entry {
        id: element.get("id")?.as_str()?.to_string(),
        name: text("name"),
        field: text("field"),
        is_enabled: element
            .get("isEnabled")
            .and_then(Value::as_bool)
            .unwrap_or(true),
        condition: condition_name,
        apps,
        count: element.get(count_key).and_then(Value::as_u64).unwrap_or(0),
        is_bundled: element
            .get("isBundled")
            .and_then(Value::as_bool)
            .unwrap_or(false),
    })
}

/// 行の名前の下に出す要約(macOS の UIStrings.Dictionaries.summary・UIStrings.Association.summary)
pub fn summary(list: DictionaryList, entry: &Entry) -> String {
    match list {
        DictionaryList::Imported => {
            let condition = match entry.condition.as_str() {
                APPS => dictionaries::apps_condition(entry.apps.len()),
                CONTEXT => dictionaries::CONTEXT.to_string(),
                _ => dictionaries::ALWAYS.to_string(),
            };
            dictionaries::summary(&entry.field, entry.count, &condition)
        }
        // 同梱の辞書は件数を数えていない(設定には 0 と書いてある)ので，件数のかわりに同梱と出す
        DictionaryList::Association if entry.is_bundled => windows::ASSOCIATION_BUNDLED.to_string(),
        DictionaryList::Association => association::summary(entry.count),
    }
}

/// index の辞書を change で書き換えた配列．index の辞書が無ければ None
fn changed(
    value: Option<&Value>,
    index: usize,
    change: impl FnOnce(&mut Map<String, Value>),
) -> Option<Value> {
    let mut elements = value?.as_array()?.clone();
    change(elements.get_mut(index)?.as_object_mut()?);
    Some(Value::Array(elements))
}

/// index の辞書の名前を変えた配列．空の名前(前後の空白だけを含む)にはしない(None)
pub fn renamed(value: Option<&Value>, index: usize, name: &str) -> Option<Value> {
    let name = name.trim();
    if name.is_empty() {
        return None;
    }
    changed(value, index, |element| {
        element.insert("name".into(), Value::String(name.to_string()));
    })
}

/// index の辞書の分野を変えた配列(空なら分野を付けない)
pub fn with_field(value: Option<&Value>, index: usize, field: &str) -> Option<Value> {
    changed(value, index, |element| {
        element.insert("field".into(), Value::String(field.trim().to_string()));
    })
}

/// index の辞書の使う場面を condition(always・apps・context)にした配列．
/// 選んだアプリに変えるとき，もともと選んだアプリならアプリをそのまま残す(macOS の ImportedDictionariesView と同じ)
pub fn with_condition(value: Option<&Value>, index: usize, condition: &str) -> Option<Value> {
    changed(value, index, |element| {
        let apps = current_apps(element);
        let condition = match (condition, apps) {
            (APPS, Some(apps)) => json!({ APPS: { "_0": apps } }),
            (APPS, None) => json!({ APPS: { "_0": [] } }),
            (CONTEXT, _) => json!({ CONTEXT: {} }),
            _ => json!({ ALWAYS: {} }),
        };
        element.insert("condition".into(), condition);
    })
}

/// 使う場面が選んだアプリならそのアプリ
fn current_apps(element: &Map<String, Value>) -> Option<Vec<Value>> {
    element
        .get("condition")?
        .get(APPS)?
        .get("_0")?
        .as_array()
        .cloned()
}

/// index の辞書の選んだアプリに names を足した配列．すでにあるアプリは足さない(macOS と同じ)．
/// 使う場面が選んだアプリでなければ None
pub fn with_apps(value: Option<&Value>, index: usize, names: &[String]) -> Option<Value> {
    let element = value?.as_array()?.get(index)?.as_object()?;
    let mut apps = current_apps(element)?;
    for name in names {
        let name = Value::String(name.clone());
        if !apps.contains(&name) {
            apps.push(name);
        }
    }
    changed(value, index, |element| {
        element.insert("condition".into(), json!({ APPS: { "_0": apps } }));
    })
}

/// index の辞書の選んだアプリから position 番目のアプリを外した配列
pub fn without_app(value: Option<&Value>, index: usize, position: usize) -> Option<Value> {
    let element = value?.as_array()?.get(index)?.as_object()?;
    let mut apps = current_apps(element)?;
    if position >= apps.len() {
        return None;
    }
    apps.remove(position);
    changed(value, index, |element| {
        element.insert("condition".into(), json!({ APPS: { "_0": apps } }));
    })
}

/// 選んだ実行ファイルの場所をアプリの名前(実行ファイルの名前の小文字)にする．
/// 英数字・「.」・「-」・「_」でない名前なら None(エンジンは入力先のアプリをこの名前で見分ける)
pub fn app_name(path: &str) -> Option<String> {
    let name = std::path::Path::new(path)
        .file_name()?
        .to_string_lossy()
        .to_lowercase();
    (!name.is_empty()
        && name
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || ".-_".contains(character)))
    .then_some(name)
}

/// index の辞書のオン・オフを切り替えた配列
pub fn toggle(value: Option<&Value>, index: usize) -> Option<Value> {
    changed(value, index, |element| {
        let enabled = element
            .get("isEnabled")
            .and_then(Value::as_bool)
            .unwrap_or(true);
        element.insert("isEnabled".into(), Value::Bool(!enabled));
    })
}

/// index の辞書を offset だけ動かした配列(上ほど優先する)．動かせなければ None
pub fn moved(value: Option<&Value>, index: usize, offset: isize) -> Option<Value> {
    let mut elements = value?.as_array()?.clone();
    let target = index.checked_add_signed(offset)?;
    (index < elements.len() && target < elements.len()).then(|| {
        elements.swap(index, target);
        Value::Array(elements)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn imported() -> Value {
        json!([
            {"id": "a", "name": "電気", "field": "電気", "isEnabled": true, "condition": {"always": {}}, "wordCount": 3},
            {"id": "b", "name": "法律", "field": "", "isEnabled": false, "condition": {"apps": {"_0": ["code.exe"]}}, "wordCount": 12},
            {"id": "c", "name": "医療", "field": "医療", "isEnabled": true, "condition": {"context": {}}, "wordCount": 5}
        ])
    }

    #[test]
    fn 設定の配列を行と要約にする() {
        let entries = entries(DictionaryList::Imported, Some(&imported()));
        assert_eq!(entries.len(), 3);
        assert_eq!(entries[1].apps, vec!["code.exe".to_string()]);
        assert!(!entries[1].is_enabled);
        let summaries: Vec<String> = entries
            .iter()
            .map(|entry| summary(DictionaryList::Imported, entry))
            .collect();
        assert_eq!(
            summaries,
            vec![
                "電気・3 件・常に",
                "12 件・選んだアプリ 1 個",
                "医療・5 件・文脈に合わせる"
            ]
        );
        let association = json!([
            {"id": "w", "name": "日本語 WordNet", "isEnabled": true, "groupCount": 0, "isBundled": true},
            {"id": "x", "name": "類語", "isEnabled": true, "groupCount": 42}
        ]);
        let entries = super::entries(DictionaryList::Association, Some(&association));
        assert!(entries[0].is_bundled);
        assert_eq!(
            summary(DictionaryList::Association, &entries[0]),
            windows::ASSOCIATION_BUNDLED
        );
        assert_eq!(
            summary(DictionaryList::Association, &entries[1]),
            "42 件の意味"
        );
        // 形の合わない要素(id の無いもの)は飛ばし，配列でなければ空
        let broken = json!([{"name": "id なし"}, {"id": "y", "name": "ok"}]);
        assert_eq!(entries_len(&broken), 1);
        assert!(super::entries(DictionaryList::Imported, Some(&json!({}))).is_empty());
    }

    fn entries_len(value: &Value) -> usize {
        entries(DictionaryList::Imported, Some(value)).len()
    }

    #[test]
    fn 名前と分野を書き換える() {
        let renamed = renamed(Some(&imported()), 0, "  電気の語 ").unwrap();
        assert_eq!(renamed[0]["name"], "電気の語");
        assert_eq!(renamed[1], imported()[1]);
        // 名前を空にしても名前は消さない
        assert_eq!(super::renamed(Some(&imported()), 0, "   "), None);
        assert_eq!(super::renamed(Some(&imported()), 9, "x"), None);
        let field = with_field(Some(&imported()), 1, " 法律 ").unwrap();
        assert_eq!(field[1]["field"], "法律");
        let cleared = with_field(Some(&imported()), 0, "").unwrap();
        assert_eq!(cleared[0]["field"], "");
    }

    #[test]
    fn 使う場面を切り替える() {
        // 常に → 選んだアプリ: アプリは空で始める
        let apps = with_condition(Some(&imported()), 0, APPS).unwrap();
        assert_eq!(apps[0]["condition"], json!({"apps": {"_0": []}}));
        // 選んだアプリ → 選んだアプリ: アプリを残す
        let same = with_condition(Some(&imported()), 1, APPS).unwrap();
        assert_eq!(same[1]["condition"], imported()[1]["condition"]);
        let context = with_condition(Some(&imported()), 1, CONTEXT).unwrap();
        assert_eq!(context[1]["condition"], json!({"context": {}}));
        let always = with_condition(Some(&imported()), 2, ALWAYS).unwrap();
        assert_eq!(always[2]["condition"], json!({"always": {}}));
        let entries = entries(DictionaryList::Imported, Some(&context));
        assert_eq!(entries[1].condition, CONTEXT);
        assert!(entries[1].apps.is_empty());
    }

    #[test]
    fn 選んだアプリを足して外す() {
        let names = ["notepad.exe".to_string(), "code.exe".to_string()];
        let added = with_apps(Some(&imported()), 1, &names).unwrap();
        // すでにあるアプリは足さない
        assert_eq!(
            added[1]["condition"],
            json!({"apps": {"_0": ["code.exe", "notepad.exe"]}})
        );
        // 使う場面が選んだアプリでなければ足さない
        assert_eq!(with_apps(Some(&imported()), 0, &names), None);
        let removed = without_app(Some(&added), 1, 0).unwrap();
        assert_eq!(
            removed[1]["condition"],
            json!({"apps": {"_0": ["notepad.exe"]}})
        );
        assert_eq!(without_app(Some(&added), 1, 5), None);
        assert_eq!(without_app(Some(&imported()), 0, 0), None);
    }

    #[test]
    fn 実行ファイルの場所をアプリの名前にする() {
        assert_eq!(
            app_name("C:\\Program Files\\Code\\Code.exe"),
            Some("code.exe".to_string())
        );
        assert_eq!(
            app_name("C:\\x\\my-app_1.EXE"),
            Some("my-app_1.exe".to_string())
        );
        assert_eq!(app_name("C:\\x\\メモ帳.exe"), None);
        assert_eq!(app_name("C:\\x\\a b.exe"), None);
        assert_eq!(app_name(""), None);
    }

    #[test]
    fn 切り替えと並べ替え() {
        let toggled = toggle(Some(&imported()), 1).unwrap();
        assert_eq!(toggled[1]["isEnabled"], true);
        let toggled = toggle(Some(&imported()), 0).unwrap();
        assert_eq!(toggled[0]["isEnabled"], false);
        // isEnabled の無い辞書はオンとして扱う
        let missing = json!([{"id": "a", "name": "x"}]);
        assert_eq!(toggle(Some(&missing), 0).unwrap()[0]["isEnabled"], false);
        assert_eq!(toggle(Some(&imported()), 3), None);
        let moved_up = moved(Some(&imported()), 1, -1).unwrap();
        assert_eq!(moved_up[0]["id"], "b");
        assert_eq!(moved_up[1]["id"], "a");
        let moved_down = moved(Some(&imported()), 1, 1).unwrap();
        assert_eq!(moved_down[2]["id"], "b");
        assert_eq!(moved(Some(&imported()), 0, -1), None);
        assert_eq!(moved(Some(&imported()), 2, 1), None);
        assert_eq!(moved(None, 0, 1), None);
    }
}
