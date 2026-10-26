#![forbid(unsafe_code)]

//! 設定の読み書きの口．設定のファイルはエンジンが持つので，画面は項目の名前と JSON の値で読み書きを頼む
//! (readSettingsFields・writeSettingsFields)．テストでは別の実装に差し替える

use serde_json::{Map, Value};
use thiserror::Error;

/// 項目の名前から値への JSON のオブジェクト．形は設定のファイル(settings.json)と同じ
pub type Fields = Map<String, Value>;

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum StoreError {
    #[error("エンジンにつながらない")]
    Unavailable,
    #[error("応答が大きすぎる")]
    TooLarge,
    #[error("エンジンが断った")]
    Rejected,
    #[error("応答を読めない")]
    Malformed,
}

pub trait SettingsStore {
    /// names の項目を読む．defaults が true なら既定値を読む
    fn read(&self, names: &[String], defaults: bool) -> Result<Fields, StoreError>;
    /// values の項目を書く．書いた項目の値(範囲の外の値は直した値)を返す
    fn write(&self, values: &Fields) -> Result<Fields, StoreError>;
}

/// 読めた項目と，1 つだけで頼んでも応答の上限を超えて読めなかった項目
#[derive(Debug, Default, Clone, PartialEq)]
pub struct ReadResult {
    pub fields: Fields,
    pub unreadable: Vec<String>,
}

/// names の項目をすべて読む．応答の上限を超えたら半分ずつに分けて頼み直す
pub fn read_all(
    store: &dyn SettingsStore,
    names: &[String],
    defaults: bool,
) -> Result<ReadResult, StoreError> {
    let mut result = ReadResult::default();
    read_into(store, names, defaults, &mut result)?;
    Ok(result)
}

fn read_into(
    store: &dyn SettingsStore,
    names: &[String],
    defaults: bool,
    result: &mut ReadResult,
) -> Result<(), StoreError> {
    if names.is_empty() {
        return Ok(());
    }
    match store.read(names, defaults) {
        Ok(fields) => {
            result.fields.extend(fields);
            Ok(())
        }
        Err(StoreError::TooLarge) if names.len() == 1 => {
            result.unreadable.extend(names.iter().cloned());
            Ok(())
        }
        Err(StoreError::TooLarge) => {
            let (first, second) = names.split_at(names.len() / 2);
            read_into(store, first, defaults, result)?;
            read_into(store, second, defaults, result)
        }
        Err(error) => Err(error),
    }
}

#[cfg(test)]
pub(crate) mod fake {
    use super::*;
    use std::cell::RefCell;

    /// 覚えた値を返すだけの口．大きな項目を含む頼みは断る(応答の上限の代わり)
    #[derive(Default)]
    pub struct FakeStore {
        pub current: RefCell<Fields>,
        pub defaults: Fields,
        pub too_large: Vec<String>,
        pub writes: RefCell<Vec<Fields>>,
        pub fails: bool,
    }

    impl SettingsStore for FakeStore {
        fn read(&self, names: &[String], defaults: bool) -> Result<Fields, StoreError> {
            if self.fails {
                return Err(StoreError::Unavailable);
            }
            if names.iter().any(|name| self.too_large.contains(name)) {
                return Err(StoreError::TooLarge);
            }
            let source = if defaults {
                self.defaults.clone()
            } else {
                self.current.borrow().clone()
            };
            Ok(names
                .iter()
                .map(|name| {
                    (
                        name.clone(),
                        source.get(name).cloned().unwrap_or(Value::Null),
                    )
                })
                .collect())
        }

        fn write(&self, values: &Fields) -> Result<Fields, StoreError> {
            if self.fails {
                return Err(StoreError::Unavailable);
            }
            self.writes.borrow_mut().push(values.clone());
            self.current.borrow_mut().extend(values.clone());
            Ok(values.clone())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::fake::FakeStore;
    use super::*;
    use serde_json::json;
    use std::cell::RefCell;

    fn names(list: &[&str]) -> Vec<String> {
        list.iter().map(|name| name.to_string()).collect()
    }

    #[test]
    fn 大きすぎる項目を分けて読む() {
        let store = FakeStore {
            current: RefCell::new(
                json!({"a": 1, "b": 2, "c": 3, "d": 4})
                    .as_object()
                    .unwrap()
                    .clone(),
            ),
            too_large: names(&["c"]),
            ..Default::default()
        };
        let result = read_all(&store, &names(&["a", "b", "c", "d"]), false).unwrap();
        assert_eq!(result.fields.len(), 3);
        assert_eq!(result.unreadable, names(&["c"]));
    }

    #[test]
    fn つながらなければ失敗を返す() {
        let store = FakeStore {
            fails: true,
            ..Default::default()
        };
        assert_eq!(
            read_all(&store, &names(&["a"]), false),
            Err(StoreError::Unavailable)
        );
    }
}
