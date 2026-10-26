#![forbid(unsafe_code)]

//! 決まりの一覧(補正の置き換え・直さない語句・ローマ字・いつも英語/日本語にする語・見分け方の決まり)の編集．
//! 一覧は設定のファイルの JSON の配列のまま扱い，足す・消すは新しい配列を作ってエンジンに書いてもらう．
//! 形の確かめはエンジンが設定のファイルを読むときと同じに行うので，書いたあとに残っていなければ形が誤っている

use crate::options::Choice;
use serde_json::{Map, Value};

/// 一覧の 1 つの欄
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Field {
    /// オブジェクトの名前．None なら一覧は文字列の配列(欄は 1 つだけ)
    pub name: Option<&'static str>,
    pub label: &'static str,
    /// 選ぶ欄の選択肢．None なら打つ欄
    pub choices: Option<&'static [Choice]>,
    /// 行を見分ける欄か(同じ値の行は置き換える)
    pub key: bool,
    /// キーの書き方の欄(keys::canonical で整え，読めなければ足さない)
    pub notation: bool,
}

impl Field {
    /// 文字列の配列の欄
    pub const fn text(label: &'static str) -> Self {
        Self {
            name: None,
            label,
            choices: None,
            key: true,
            notation: false,
        }
    }

    pub const fn named(name: &'static str, label: &'static str, key: bool) -> Self {
        Self {
            name: Some(name),
            label,
            choices: None,
            key,
            notation: false,
        }
    }

    pub const fn choice(
        name: &'static str,
        label: &'static str,
        choices: &'static [Choice],
        key: bool,
    ) -> Self {
        Self {
            name: Some(name),
            label,
            choices: Some(choices),
            key,
            notation: false,
        }
    }

    /// キーの書き方の欄
    pub const fn key_notation(name: &'static str, label: &'static str, key: bool) -> Self {
        Self {
            name: Some(name),
            label,
            choices: None,
            key,
            notation: true,
        }
    }

    /// 画面に出す文字(選ぶ欄は選択肢の名前，キーは Windows の名前)
    pub fn display(&self, value: &str) -> String {
        if self.notation {
            return crate::keys::display(value);
        }
        self.choices
            .and_then(|choices| choices.iter().find(|(raw, _)| *raw == value))
            .map_or_else(|| value.to_string(), |(_, label)| (*label).to_string())
    }
}

/// 一覧の形
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ListSpec {
    /// 値の道筋(「correction.rules」)
    pub path: &'static str,
    pub fields: &'static [Field],
    /// 一覧が空のときの文
    pub empty: &'static str,
    /// 形が誤っていて残らなかったときの文
    pub invalid: crate::strings::Text,
    /// 打つ欄を足す前に小文字にするか(英語と日本語の語)
    pub lowercase: bool,
    /// 足した語と同じ語を，この一覧からは除く(いつも英語にする語といつも日本語にする語)
    pub exclusive_with: Option<&'static str>,
}

/// 一覧の 1 行(欄ごとの値．選ぶ欄は設定のファイルに書く値)
pub type Item = Vec<String>;

impl ListSpec {
    fn is_strings(&self) -> bool {
        self.fields
            .first()
            .is_some_and(|field| field.name.is_none())
    }

    /// 配列を行にする．形の合わない要素は飛ばす
    pub fn items(&self, list: Option<&Value>) -> Vec<Item> {
        let Some(Value::Array(elements)) = list else {
            return Vec::new();
        };
        elements
            .iter()
            .filter_map(|element| self.item(element))
            .collect()
    }

    fn item(&self, element: &Value) -> Option<Item> {
        if self.is_strings() {
            return element.as_str().map(|text| vec![text.to_string()]);
        }
        self.fields
            .iter()
            .map(|field| {
                field
                    .name
                    .and_then(|name| element.get(name))
                    .and_then(Value::as_str)
                    .map(str::to_string)
            })
            .collect()
    }

    /// 入力欄の値から行を作る．打つ欄は前後の空白を除く
    pub fn make(&self, values: &[String]) -> Item {
        self.fields
            .iter()
            .zip(values)
            .map(|(field, value)| {
                let value = value.trim();
                if field.notation {
                    crate::keys::canonical(value).unwrap_or_else(|| value.to_string())
                } else if field.choices.is_none() && self.lowercase {
                    value.to_lowercase()
                } else {
                    value.to_string()
                }
            })
            .collect()
    }

    fn element(&self, item: &Item) -> Value {
        if self.is_strings() {
            return Value::String(item.first().cloned().unwrap_or_default());
        }
        let mut object = Map::new();
        for (field, value) in self.fields.iter().zip(item) {
            if let Some(name) = field.name {
                object.insert(name.to_string(), Value::String(value.clone()));
            }
        }
        Value::Object(object)
    }

    /// 行を見分ける欄が同じか．見分ける欄の無い一覧(キー設定の表)は同じ行を何度でも足せる
    pub fn same_key(&self, a: &Item, b: &Item) -> bool {
        self.fields.iter().any(|field| field.key)
            && self
                .fields
                .iter()
                .enumerate()
                .filter(|(_, field)| field.key)
                .all(|(index, _)| a.get(index) == b.get(index))
    }

    /// 行を足した配列．見分ける欄が同じ行があれば置き換える
    pub fn upsert(&self, list: Option<&Value>, item: &Item) -> Value {
        let mut items = self.items(list);
        match items
            .iter()
            .position(|existing| self.same_key(existing, item))
        {
            Some(index) => items[index] = item.clone(),
            None => items.push(item.clone()),
        }
        self.array(&items)
    }

    /// 文字列の配列から text を除いた配列(exclusive_with の一覧に使う)
    pub fn without(list: Option<&Value>, text: &str) -> Value {
        let elements = match list {
            Some(Value::Array(elements)) => elements.clone(),
            _ => Vec::new(),
        };
        Value::Array(
            elements
                .into_iter()
                .filter(|element| element.as_str() != Some(text))
                .collect(),
        )
    }

    /// indices の行を除いた配列
    pub fn remove(&self, list: Option<&Value>, indices: &[usize]) -> Value {
        let items: Vec<Item> = self
            .items(list)
            .into_iter()
            .enumerate()
            .filter(|(index, _)| !indices.contains(index))
            .map(|(_, item)| item)
            .collect();
        self.array(&items)
    }

    fn array(&self, items: &[Item]) -> Value {
        Value::Array(items.iter().map(|item| self.element(item)).collect())
    }

    pub fn contains(&self, list: Option<&Value>, item: &Item) -> bool {
        self.items(list).contains(item)
    }

    /// 画面の側で確かめられる形(キーの書き方)が合っているか
    pub fn is_valid(&self, item: &Item) -> bool {
        self.fields
            .iter()
            .zip(item)
            .all(|(field, value)| !field.notation || crate::keys::canonical(value).is_some())
    }

    /// 打つ欄が埋まっているか(足すボタンを使えるか)
    pub fn is_filled(&self, values: &[String]) -> bool {
        self.fields
            .iter()
            .zip(values)
            .all(|(field, value)| field.choices.is_some() || !value.trim().is_empty())
    }

    /// 表に出す文字
    pub fn display(&self, item: &Item) -> Vec<String> {
        self.fields
            .iter()
            .zip(item)
            .map(|(field, value)| field.display(value))
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    const RULE_FIELDS: &[Field] = &[
        Field::named("typed", "打った英字", true),
        Field::named("word", "置き換える語句", false),
    ];
    const RULES: ListSpec = ListSpec {
        path: "correction.rules",
        fields: RULE_FIELDS,
        empty: "",
        invalid: crate::strings::Text::Fixed(""),
        lowercase: false,
        exclusive_with: None,
    };

    const WORD_FIELDS: &[Field] = &[Field::text("英字で打つ語")];
    const WORDS: ListSpec = ListSpec {
        path: "wordLanguage.englishWords",
        fields: WORD_FIELDS,
        empty: "",
        invalid: crate::strings::Text::Fixed(""),
        lowercase: true,
        exclusive_with: Some("wordLanguage.japaneseWords"),
    };

    const LANGUAGES: &[Choice] = &[("english", "英語"), ("japanese", "日本語")];
    const CONTEXTS: &[Choice] = &[("afterEnglish", "英語"), ("afterJapanese", "日本語")];
    const LANGUAGE_FIELDS: &[Field] = &[
        Field::named("word", "語", true),
        Field::choice("context", "前", CONTEXTS, true),
        Field::choice("language", "結果", LANGUAGES, false),
    ];
    const LANGUAGE_RULES: ListSpec = ListSpec {
        path: "wordLanguage.rules",
        fields: LANGUAGE_FIELDS,
        empty: "",
        invalid: crate::strings::Text::Fixed(""),
        lowercase: true,
        exclusive_with: None,
    };

    fn texts(values: &[&str]) -> Vec<String> {
        values.iter().map(|value| value.to_string()).collect()
    }

    #[test]
    fn オブジェクトの配列を行にする() {
        let list = json!([{"typed": "teh", "word": "the"}, 3]);
        assert_eq!(RULES.items(Some(&list)), vec![texts(&["teh", "the"])]);
    }

    #[test]
    fn 見分ける欄が同じ行は置き換える() {
        let list = json!([{"typed": "teh", "word": "the"}]);
        let item = RULES.make(&texts(&[" teh ", "THE"]));
        assert_eq!(
            RULES.upsert(Some(&list), &item),
            json!([{"typed": "teh", "word": "THE"}])
        );
        let other = RULES.make(&texts(&["adn", "and"]));
        assert_eq!(
            RULES.upsert(Some(&list), &other).as_array().unwrap().len(),
            2
        );
    }

    #[test]
    fn 選ぶ欄も見分けに使う() {
        let list = json!([{"word": "make", "context": "afterEnglish", "language": "english"}]);
        let japanese = LANGUAGE_RULES.make(&texts(&["Make", "afterJapanese", "japanese"]));
        assert_eq!(
            LANGUAGE_RULES
                .upsert(Some(&list), &japanese)
                .as_array()
                .unwrap()
                .len(),
            2
        );
        let changed = LANGUAGE_RULES.make(&texts(&["make", "afterEnglish", "japanese"]));
        assert_eq!(
            LANGUAGE_RULES.upsert(Some(&list), &changed),
            json!([{"word": "make", "context": "afterEnglish", "language": "japanese"}])
        );
        assert_eq!(
            LANGUAGE_RULES.display(&changed),
            texts(&["make", "英語", "日本語"])
        );
    }

    #[test]
    fn 文字列の配列は小文字にして足す() {
        let item = WORDS.make(&texts(&["Swift"]));
        assert_eq!(WORDS.upsert(None, &item), json!(["swift"]));
        assert!(WORDS.contains(Some(&json!(["swift"])), &item));
        assert_eq!(
            ListSpec::without(Some(&json!(["swift", "rust"])), "swift"),
            json!(["rust"])
        );
    }

    const KEYMAP_FIELDS: &[Field] = &[
        Field::choice("state", "状態", CONTEXTS, false),
        Field::key_notation("key", "キー", false),
        Field::choice("command", "コマンド", LANGUAGES, false),
    ];
    const KEYMAP: ListSpec = ListSpec {
        path: "keymap",
        fields: KEYMAP_FIELDS,
        empty: "",
        invalid: crate::strings::Text::Fixed(""),
        lowercase: false,
        exclusive_with: None,
    };

    #[test]
    fn キー設定の表は同じ行も後ろに足す() {
        let list = json!([{"state": "afterEnglish", "key": "Enter", "command": "english"}]);
        let item = KEYMAP.make(&texts(&["afterEnglish", "enter", "english"]));
        assert_eq!(item[1], "Enter");
        assert_eq!(
            KEYMAP.upsert(Some(&list), &item).as_array().unwrap().len(),
            2
        );
        assert!(KEYMAP.is_valid(&item));
        assert!(!KEYMAP.is_valid(&KEYMAP.make(&texts(&["afterEnglish", "Hyper k", "english"]))));
        assert_eq!(
            KEYMAP.display(&KEYMAP.make(&texts(&["afterEnglish", "alt k", "english"])))[1],
            "Alt K"
        );
    }

    #[test]
    fn 選んだ行を消す() {
        let list = json!(["a", "b", "c"]);
        assert_eq!(WORDS.remove(Some(&list), &[0, 2]), json!(["b"]));
    }

    #[test]
    fn 打つ欄をすべて埋める() {
        assert!(!RULES.is_filled(&texts(&["teh", " "])));
        assert!(RULES.is_filled(&texts(&["teh", "the"])));
        assert!(LANGUAGE_RULES.is_filled(&texts(&["make", "", ""])));
    }
}
