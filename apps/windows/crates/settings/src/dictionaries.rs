#![forbid(unsafe_code)]

//! 取り込んだ辞書・連想の辞書の一覧(macOS の ImportedDictionariesView・AssociationSection)．
//! 一覧は設定のファイルの配列(importedDictionaries・associationDictionaries)をそのまま読み書きする．
//! 名前・分野・使う場面・オン・オフ・並びはここで変え，取り込みと削除(索引のファイルがある)はエンジンに頼む

use crate::pages::DictionaryList;
use crate::strings::{association, dictionaries, windows};
use serde_json::{json, Map, Value};

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
    /// アプリに同梱した辞書(消せない)
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
        None => ("always".to_string(), Vec::new()),
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

/// 表の行(名前・内容・状態)
pub fn table(list: DictionaryList, entries: &[Entry]) -> Vec<Vec<String>> {
    entries
        .iter()
        .map(|entry| {
            let summary = match list {
                DictionaryList::Imported => {
                    let condition = match entry.condition.as_str() {
                        "apps" => dictionaries::apps_condition(entry.apps.len()),
                        "context" => dictionaries::CONTEXT.to_string(),
                        _ => dictionaries::ALWAYS.to_string(),
                    };
                    dictionaries::summary(&entry.field, entry.count, &condition)
                }
                DictionaryList::Association => association::summary(entry.count),
            };
            let state = if entry.is_enabled {
                ""
            } else {
                windows::DISABLED
            };
            vec![entry.name.clone(), summary, state.to_string()]
        })
        .collect()
}

/// 入力欄に出す値(名前・分野・使う場面・アプリ)．連想の辞書は名前だけ
pub fn inputs(list: DictionaryList, entry: &Entry) -> Vec<String> {
    match list {
        DictionaryList::Imported => vec![
            entry.name.clone(),
            entry.field.clone(),
            entry.condition.clone(),
            entry.apps.join(", "),
        ],
        DictionaryList::Association => vec![entry.name.clone()],
    }
}

/// 入力欄の値で index の辞書を書き換えた配列．アプリの名前が正しくなければ None
pub fn update(
    list: DictionaryList,
    value: Option<&Value>,
    index: usize,
    inputs: &[String],
) -> Option<Value> {
    let mut elements = value?.as_array()?.clone();
    let element = elements.get_mut(index)?.as_object_mut()?;
    let name = inputs.first()?.trim();
    if !name.is_empty() {
        element.insert("name".into(), Value::String(name.to_string()));
    }
    if list == DictionaryList::Imported {
        element.insert(
            "field".into(),
            Value::String(inputs.get(1)?.trim().to_string()),
        );
        let condition = match inputs.get(2)?.as_str() {
            "apps" => {
                let apps = parse_apps(inputs.get(3)?)?;
                json!({ "apps": { "_0": apps } })
            }
            "context" => json!({ "context": {} }),
            _ => json!({ "always": {} }),
        };
        element.insert("condition".into(), condition);
    }
    Some(Value::Array(elements))
}

/// 「code.exe, notepad.exe」を実行ファイルの名前の並びにする(小文字)．英数字・「.」・「-」・「_」でない名前があれば None
pub fn parse_apps(text: &str) -> Option<Vec<String>> {
    text.split([',', '、'])
        .map(|name| name.trim().to_lowercase())
        .filter(|name| !name.is_empty())
        .map(|name| {
            name.chars()
                .all(|character| character.is_ascii_alphanumeric() || ".-_".contains(character))
                .then_some(name)
        })
        .collect()
}

/// index の辞書のオン・オフを切り替えた配列
pub fn toggle(value: Option<&Value>, index: usize) -> Option<Value> {
    let mut elements = value?.as_array()?.clone();
    let element: &mut Map<String, Value> = elements.get_mut(index)?.as_object_mut()?;
    let enabled = element
        .get("isEnabled")
        .and_then(Value::as_bool)
        .unwrap_or(true);
    element.insert("isEnabled".into(), Value::Bool(!enabled));
    Some(Value::Array(elements))
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
            {"id": "b", "name": "法律", "field": "", "isEnabled": false, "condition": {"apps": {"_0": ["code.exe"]}}, "wordCount": 12}
        ])
    }

    #[test]
    fn 設定の配列を行と表にする() {
        let entries = entries(DictionaryList::Imported, Some(&imported()));
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[1].apps, vec!["code.exe".to_string()]);
        assert_eq!(
            table(DictionaryList::Imported, &entries),
            vec![
                vec![
                    "電気".to_string(),
                    "電気・3 語・常に".to_string(),
                    String::new()
                ],
                vec![
                    "法律".to_string(),
                    "12 語・選んだアプリ 1 個".to_string(),
                    "無効".to_string()
                ],
            ]
        );
        assert_eq!(
            inputs(DictionaryList::Imported, &entries[1]),
            vec!["法律", "", "apps", "code.exe"]
        );
        let association = json!([{"id": "w", "name": "日本語 WordNet", "isEnabled": true, "groupCount": 0, "isBundled": true}]);
        let entries = super::entries(DictionaryList::Association, Some(&association));
        assert!(entries[0].is_bundled);
        assert_eq!(
            table(DictionaryList::Association, &entries)[0][1],
            "0 件の意味"
        );
    }

    #[test]
    fn 名前と分野と使う場面を書き換える() {
        let inputs = ["電気の語", "電気", "apps", "Code.exe, notepad.exe"].map(String::from);
        let updated = update(DictionaryList::Imported, Some(&imported()), 0, &inputs).unwrap();
        assert_eq!(updated[0]["name"], "電気の語");
        assert_eq!(
            updated[0]["condition"],
            json!({"apps": {"_0": ["code.exe", "notepad.exe"]}})
        );
        assert_eq!(updated[1], imported()[1]);
        let bad = ["電気", "", "apps", "../x"].map(String::from);
        assert_eq!(
            update(DictionaryList::Imported, Some(&imported()), 0, &bad),
            None
        );
        // 名前を空にしても名前は消さない
        let empty = ["", "", "context", ""].map(String::from);
        let updated = update(DictionaryList::Imported, Some(&imported()), 0, &empty).unwrap();
        assert_eq!(updated[0]["name"], "電気");
        assert_eq!(updated[0]["condition"], json!({"context": {}}));
    }

    #[test]
    fn 切り替えと並べ替え() {
        let toggled = toggle(Some(&imported()), 1).unwrap();
        assert_eq!(toggled[1]["isEnabled"], true);
        let moved_up = moved(Some(&imported()), 1, -1).unwrap();
        assert_eq!(moved_up[0]["id"], "b");
        assert_eq!(moved(Some(&imported()), 0, -1), None);
        assert_eq!(moved(Some(&imported()), 1, 1), None);
    }
}
