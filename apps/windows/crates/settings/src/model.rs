#![forbid(unsafe_code)]

//! 画面に出す設定の値と，その書き換え．値は項目の名前と「correction.english」のような点で区切った道筋で引く．
//! 値を変えるときは，その項目(最上位の名前)をまるごとエンジンに書いてもらい，返った値を覚える

use crate::catalog::Catalog;
use crate::store::{read_all, Fields, SettingsStore, StoreError};
use serde_json::{Number, Value};

/// 「既定に戻す」(すべて)で戻さない項目．登録した語と取り込んだ辞書は辞書の画面で消す(macOS の restoreDefaults と同じ)
pub const KEPT_ON_RESTORE: &[&str] = &["userDictionary", "importedDictionaries"];

/// 一度に書く項目の数．応答の上限(256KB)を超えないよう，すべてを戻すときは分けて書く
const WRITE_BATCH: usize = 8;

pub struct SettingsModel<S: SettingsStore> {
    store: S,
    names: Vec<String>,
    current: Fields,
    defaults: Fields,
    /// 大きすぎて読めなかった項目．画面では変えられないようにする
    unreadable: Vec<String>,
}

impl<S: SettingsStore> SettingsModel<S> {
    pub fn load(store: S, catalog: &Catalog) -> Result<Self, StoreError> {
        let names = catalog.fields.clone();
        let current = read_all(&store, &names, false)?;
        let defaults = read_all(&store, &names, true)?;
        let mut unreadable = current.unreadable;
        unreadable.extend(defaults.unreadable);
        Ok(Self {
            store,
            names,
            current: current.fields,
            defaults: defaults.fields,
            unreadable,
        })
    }

    /// エンジンが設定を変えたとき(キーでライブ変換を切り替えたなど)に読み直す
    pub fn reload(&mut self) -> Result<(), StoreError> {
        let result = read_all(&self.store, &self.names, false)?;
        self.current = result.fields;
        Ok(())
    }

    pub fn store(&self) -> &S {
        &self.store
    }

    pub fn value(&self, path: &str) -> Option<&Value> {
        lookup(&self.current, path)
    }

    pub fn default_value(&self, path: &str) -> Option<&Value> {
        lookup(&self.defaults, path)
    }

    pub fn bool(&self, path: &str) -> bool {
        self.value(path).and_then(Value::as_bool).unwrap_or(false)
    }

    pub fn text(&self, path: &str) -> &str {
        self.value(path).and_then(Value::as_str).unwrap_or("")
    }

    pub fn number(&self, path: &str) -> f64 {
        self.value(path).and_then(Value::as_f64).unwrap_or(0.0)
    }

    pub fn is_readable(&self, path: &str) -> bool {
        !self.unreadable.iter().any(|name| name == field_name(path))
    }

    /// 既定から変えたか．数は 15 と 15.0 を同じとみなす
    pub fn is_default(&self, path: &str) -> bool {
        match (self.value(path), self.default_value(path)) {
            (Some(current), Some(default)) => same(current, default),
            (None, None) => true,
            (Some(Value::Null), None) | (None, Some(Value::Null)) => true,
            _ => false,
        }
    }

    pub fn set(&mut self, path: &str, value: Value) -> Result<(), StoreError> {
        self.set_clearing(path, value, None)
    }

    /// 値を書き，clears の項目があれば同じ頼みの中で空(null)にする
    pub fn set_clearing(
        &mut self,
        path: &str,
        value: Value,
        clears: Option<&str>,
    ) -> Result<(), StoreError> {
        let mut changes = vec![(path, value)];
        changes.extend(clears.map(|cleared| (cleared, Value::Null)));
        self.set_all(&changes)
    }

    /// いくつかの値を 1 つの頼みで書く．同じ項目の中の道筋はまとめて項目ごと書く
    pub fn set_all(&mut self, changes: &[(&str, Value)]) -> Result<(), StoreError> {
        let mut values = Fields::new();
        for (path, value) in changes {
            let name = field_name(path);
            let field = values
                .entry(name.to_string())
                .or_insert_with(|| self.current.get(name).cloned().unwrap_or(Value::Null));
            assign(field, rest(path), value.clone());
        }
        let written = self.store.write(&values)?;
        self.current.extend(written);
        Ok(())
    }

    pub fn set_bool(&mut self, path: &str, value: bool) -> Result<(), StoreError> {
        self.set(path, Value::Bool(value))
    }

    pub fn set_text(&mut self, path: &str, value: &str) -> Result<(), StoreError> {
        self.set(path, Value::String(value.to_string()))
    }

    pub fn set_number(&mut self, path: &str, value: f64) -> Result<(), StoreError> {
        self.set(path, number(value))
    }

    /// 1 つの項目を既定に戻す
    pub fn reset(&mut self, path: &str) -> Result<(), StoreError> {
        let value = self.default_value(path).cloned().unwrap_or(Value::Null);
        self.set(path, value)
    }

    /// 登録した語と取り込んだ辞書を除き，すべてを既定に戻す
    pub fn restore_defaults(&mut self) -> Result<(), StoreError> {
        let names: Vec<&String> = self
            .names
            .iter()
            .filter(|name| !KEPT_ON_RESTORE.contains(&name.as_str()))
            .filter(|name| !self.unreadable.contains(name))
            .collect();
        for chunk in names.chunks(WRITE_BATCH) {
            let values: Fields = chunk
                .iter()
                .filter_map(|name| {
                    self.defaults
                        .get(name.as_str())
                        .map(|value| (name.to_string(), value.clone()))
                })
                .collect();
            let written = self.store.write(&values)?;
            self.current.extend(written);
        }
        Ok(())
    }
}

/// 道筋の最初の名前(設定のファイルの項目の名前)
pub fn field_name(path: &str) -> &str {
    path.split('.').next().unwrap_or(path)
}

fn rest(path: &str) -> Option<&str> {
    path.split_once('.').map(|(_, rest)| rest)
}

fn lookup<'a>(fields: &'a Fields, path: &str) -> Option<&'a Value> {
    let mut value = fields.get(field_name(path))?;
    if let Some(rest) = rest(path) {
        for key in rest.split('.') {
            value = value.get(key)?;
        }
    }
    Some(value)
}

fn assign(target: &mut Value, path: Option<&str>, value: Value) {
    let Some(path) = path else {
        *target = value;
        return;
    };
    let (key, rest) = match path.split_once('.') {
        Some((key, rest)) => (key, Some(rest)),
        None => (path, None),
    };
    if !target.is_object() {
        *target = Value::Object(Fields::new());
    }
    if let Value::Object(object) = target {
        let child = object.entry(key.to_string()).or_insert(Value::Null);
        assign(child, rest, value);
    }
}

/// 整数で表せる数は整数で書く(エンジンも同じに書く．候補の数が 5.0 にならないように)
pub fn number(value: f64) -> Value {
    if value.fract() == 0.0 && value.abs() < 1e15 {
        Value::Number(Number::from(value as i64))
    } else {
        Number::from_f64(value).map_or(Value::Null, Value::Number)
    }
}

/// 数を値として比べる(15 と 15.0 を同じとみなす)
pub fn same(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(x), Value::Number(y)) => x.as_f64() == y.as_f64(),
        (Value::Array(x), Value::Array(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(a, b)| same(a, b))
        }
        (Value::Object(x), Value::Object(y)) => {
            x.len() == y.len()
                && x.iter()
                    .all(|(key, a)| y.get(key).is_some_and(|b| same(a, b)))
        }
        _ => a == b,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::fake::FakeStore;
    use serde_json::json;
    use std::cell::RefCell;

    fn object(value: Value) -> Fields {
        value.as_object().cloned().unwrap()
    }

    fn catalog(fields: &[&str]) -> Catalog {
        let mut catalog = Catalog::load().unwrap();
        catalog.fields = fields.iter().map(|name| name.to_string()).collect();
        catalog
    }

    fn model() -> SettingsModel<FakeStore> {
        let store = FakeStore {
            current: RefCell::new(object(json!({
                "liveConversion": false,
                "candidateFontSize": 15,
                "correction": {"english": false, "japanese": true},
                "userDictionary": [{"reading": "あ", "word": "亜"}],
            }))),
            defaults: object(json!({
                "liveConversion": true,
                "candidateFontSize": 15.0,
                "correction": {"english": true, "japanese": true},
                "userDictionary": [],
            })),
            ..Default::default()
        };
        SettingsModel::load(
            store,
            &catalog(&[
                "liveConversion",
                "candidateFontSize",
                "correction",
                "userDictionary",
            ]),
        )
        .unwrap()
    }

    #[test]
    fn 道筋で値を引く() {
        let model = model();
        assert!(!model.bool("liveConversion"));
        assert!(!model.bool("correction.english"));
        assert!(model.bool("correction.japanese"));
        assert_eq!(model.number("candidateFontSize"), 15.0);
    }

    #[test]
    fn 既定から変えたかを数の書き方によらず見る() {
        let model = model();
        assert!(model.is_default("candidateFontSize"));
        assert!(!model.is_default("liveConversion"));
        assert!(!model.is_default("correction.english"));
        assert!(model.is_default("correction.japanese"));
    }

    #[test]
    fn 入れ子の値は項目をまるごと書く() {
        let mut model = model();
        model.set_bool("correction.english", true).unwrap();
        let writes = model.store().writes.borrow();
        assert_eq!(
            writes.last().unwrap(),
            &object(json!({"correction": {"english": true, "japanese": true}}))
        );
        drop(writes);
        assert!(model.is_default("correction"));
    }

    #[test]
    fn 一緒に外す項目も同じ頼みで書く() {
        let mut model = model();
        model
            .set_clearing("liveConversion", Value::Bool(true), Some("customThemeID"))
            .unwrap();
        assert_eq!(
            model.store().writes.borrow().last().unwrap(),
            &object(json!({"liveConversion": true, "customThemeID": null}))
        );
    }

    #[test]
    fn 同じ項目の中の値はまとめて書く() {
        let mut model = model();
        model
            .set_all(&[
                ("correction.english", Value::Bool(true)),
                ("correction.japanese", Value::Bool(false)),
            ])
            .unwrap();
        assert_eq!(
            model.store().writes.borrow().last().unwrap(),
            &object(json!({"correction": {"english": true, "japanese": false}}))
        );
    }

    #[test]
    fn 一つずつ既定に戻す() {
        let mut model = model();
        model.reset("liveConversion").unwrap();
        assert!(model.bool("liveConversion"));
    }

    #[test]
    fn すべて戻しても登録した語は残す() {
        let mut model = model();
        model.restore_defaults().unwrap();
        assert!(model.is_default("liveConversion"));
        assert!(model.is_default("correction"));
        assert_eq!(
            model
                .value("userDictionary")
                .unwrap()
                .as_array()
                .unwrap()
                .len(),
            1
        );
    }

    #[test]
    fn 整数の数は整数で書く() {
        assert_eq!(number(5.0), json!(5));
        assert_eq!(number(0.4), json!(0.4));
    }
}
