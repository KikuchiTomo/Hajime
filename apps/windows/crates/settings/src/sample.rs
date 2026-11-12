#![forbid(unsafe_code)]

//! 見本のエンジン(--offline)．エンジンにつながずに，見本の値(fixtures/sample.json)で設定の画面を開く．
//! 書いた値は覚えるだけで，設定のファイルにもエンジンにも届かない(画面の確かめと見本の撮影のため)．
//! 見本の値は core の既定値(Settings.swift・DefaultSettings.swift)を写したもので，既定値の出どころではない

use crate::engine::Engine;
use crate::store::Fields;
use ipc::{
    DictionaryAddResult, DictionaryEntry, FileFailure, KeymapReport, PreviewWord, RequestBody,
    ResponseBody, SymbolItem, SymbolKind, SymbolOrigin, SymbolSaveResult, SyncGroupState,
    SyncStatus, WordClass,
};
use serde_json::Value;
use std::sync::Mutex;

const SOURCE: &str = include_str!("../fixtures/sample.json");

struct State {
    current: Fields,
    defaults: Fields,
    dictionary: Vec<DictionaryEntry>,
    sequences: Vec<SymbolItem>,
    readings: Vec<SymbolItem>,
    usage: Fields,
    first_candidate_rate: Option<f64>,
    sync: SyncStatus,
}

pub struct SampleEngine {
    state: Mutex<State>,
}

impl Default for SampleEngine {
    fn default() -> Self {
        Self::new()
    }
}

impl SampleEngine {
    pub fn new() -> Self {
        let source: Value = serde_json::from_str(SOURCE).unwrap_or(Value::Null);
        let object = |value: &Value| value.as_object().cloned().unwrap_or_default();
        let defaults = object(&source["defaults"]);
        let mut current = defaults.clone();
        current.extend(object(&source["changes"]));
        let extras = &source["extras"];
        let dictionary =
            serde_json::from_value(extras["userDictionary"].clone()).unwrap_or_default();
        let symbols = |kind: &str| -> Vec<SymbolItem> {
            extras["symbols"][kind]
                .as_array()
                .map(|rows| rows.iter().filter_map(symbol).collect())
                .unwrap_or_default()
        };
        let sync = serde_json::from_value(extras["sync"].clone()).unwrap_or(SyncStatus {
            is_enabled: false,
            folder_path: None,
            folder_name: None,
            groups: Vec::new(),
            local_fields: Vec::new(),
            last_synced_at: None,
            is_syncing: false,
            problem: None,
        });
        Self {
            state: Mutex::new(State {
                current,
                defaults,
                dictionary,
                sequences: symbols("sequence"),
                readings: symbols("reading"),
                usage: object(&extras["usage"]["values"]),
                first_candidate_rate: extras["usage"]["firstCandidateRate"].as_f64(),
                sync,
            }),
        }
    }
}

/// 見本の記号の行(入力・記号・有効か・出どころ)
fn symbol(row: &Value) -> Option<SymbolItem> {
    Some(SymbolItem {
        input: row[0].as_str()?.to_string(),
        output: row[1].as_str()?.to_string(),
        is_enabled: row[2].as_bool()?,
        origin: match row[3].as_str()? {
            "changed" => SymbolOrigin::Changed,
            "added" => SymbolOrigin::Added,
            _ => SymbolOrigin::Standard,
        },
    })
}

fn fields(values: &Fields) -> ResponseBody {
    ResponseBody::SettingsFields {
        values: serde_json::to_string(values).unwrap_or_default(),
    }
}

fn pick(source: &Fields, names: &[String]) -> Fields {
    names
        .iter()
        .map(|name| {
            (
                name.clone(),
                source.get(name).cloned().unwrap_or(Value::Null),
            )
        })
        .collect()
}

impl Engine for SampleEngine {
    fn request(&self, body: RequestBody) -> Option<ResponseBody> {
        let mut state = self.state.lock().ok()?;
        let state = &mut *state;
        Some(match body {
            RequestBody::ReadSettingsFields { names, defaults } => {
                let source = if defaults {
                    &state.defaults
                } else {
                    &state.current
                };
                fields(&pick(source, &names))
            }
            RequestBody::WriteSettingsFields { values } => {
                let values: Fields = serde_json::from_str(&values).ok()?;
                state.current.extend(values.clone());
                fields(&values)
            }
            RequestBody::ReadKeymapPreset { .. } => {
                fields(&pick(&state.defaults, &["keymap".to_string()]))
            }
            RequestBody::CheckKeymap { .. } => ResponseBody::KeymapReport {
                report: KeymapReport {
                    rows: Vec::new(),
                    missing: Vec::new(),
                },
            },
            RequestBody::CheckCustomTheme { .. } => {
                ResponseBody::ThemeReport { issues: Vec::new() }
            }
            RequestBody::ReadUsage => ResponseBody::Usage {
                values: serde_json::to_string(&state.usage).unwrap_or_default(),
                first_candidate_rate: state.first_candidate_rate,
            },
            RequestBody::ResetUsage => {
                state.usage.clear();
                state.first_candidate_rate = None;
                ResponseBody::Done
            }
            RequestBody::ResetLearning | RequestBody::ResetPaletteHistory => ResponseBody::Done,
            RequestBody::PreviewLanguage { text, .. } => ResponseBody::LanguagePreview {
                words: text
                    .split_whitespace()
                    .map(|word| PreviewWord {
                        typed: word.to_string(),
                        shown: word.to_string(),
                        language: "english".to_string(),
                    })
                    .collect(),
            },
            // 見本では {text} と {reading} だけを差し込む(ほかの書き方はエンジンが置き換える)
            RequestBody::PreviewMacros {
                text,
                reading,
                pattern,
            } => {
                let (word, reading) = if text.trim().is_empty() {
                    ("東京", "とうきょう")
                } else {
                    (text.trim(), reading.trim())
                };
                let apply = |form: &str| form.replace("{text}", word).replace("{reading}", reading);
                let results = match pattern {
                    Some(pattern) => vec![apply(&pattern)],
                    None => state
                        .current
                        .get("macros")
                        .and_then(Value::as_array)
                        .into_iter()
                        .flatten()
                        .filter(|macro_| macro_["isEnabled"].as_bool().unwrap_or(true))
                        .filter_map(|macro_| macro_["pattern"].as_str().map(apply))
                        .collect(),
                };
                ResponseBody::MacroPreview { results }
            }
            RequestBody::ReadUserDictionary { offset, limit } => {
                let start = (offset as usize).min(state.dictionary.len());
                let end = start
                    .saturating_add(limit as usize)
                    .min(state.dictionary.len());
                ResponseBody::UserDictionary {
                    entries: state.dictionary[start..end].to_vec(),
                    total: u32::try_from(state.dictionary.len()).unwrap_or(u32::MAX),
                }
            }
            // エンジンと同じく，読みと単語の組で 1 語とみなし，同じ組を別の品詞で足すと品詞を書き換える
            RequestBody::AddUserDictionaryEntry { mut entry } => {
                entry.word_class = entry.word_class.or(Some(WordClass::Noun));
                let same = state.dictionary.iter_mut().find(|existing| {
                    existing.reading == entry.reading && existing.word == entry.word
                });
                let result = match same {
                    Some(existing) if *existing == entry => DictionaryAddResult::AlreadyRegistered,
                    Some(existing) => {
                        existing.word_class = entry.word_class;
                        existing.comment = entry.comment;
                        DictionaryAddResult::Added
                    }
                    None => {
                        state.dictionary.push(entry);
                        DictionaryAddResult::Added
                    }
                };
                ResponseBody::DictionaryAdded { result }
            }
            RequestBody::RemoveUserDictionaryEntry { entry } => {
                state.dictionary.retain(|existing| {
                    existing.reading != entry.reading || existing.word != entry.word
                });
                ResponseBody::Done
            }
            RequestBody::ReadSymbolItems { kind } => ResponseBody::SymbolItems {
                items: symbols(state, kind).clone(),
            },
            RequestBody::SaveSymbolRule {
                kind,
                input,
                output,
                is_enabled,
                replacing,
            } => {
                let items = symbols(state, kind);
                let key = replacing.unwrap_or_else(|| input.clone());
                let origin = match items.iter().find(|item| item.input == key) {
                    Some(item) if item.origin == SymbolOrigin::Added => SymbolOrigin::Added,
                    Some(_) => SymbolOrigin::Changed,
                    None => SymbolOrigin::Added,
                };
                items.retain(|item| item.input != key);
                items.push(SymbolItem {
                    input,
                    output,
                    is_enabled,
                    origin,
                });
                ResponseBody::SymbolSaved {
                    result: SymbolSaveResult::Saved,
                }
            }
            RequestBody::RemoveSymbolRules { kind, inputs } => {
                symbols(state, kind).retain(|item| !inputs.contains(&item.input));
                ResponseBody::Done
            }
            RequestBody::ReadSync | RequestBody::SyncNow => ResponseBody::SyncStatus {
                status: state.sync.clone(),
            },
            RequestBody::SetSyncEnabled { enabled } => {
                state.sync.is_enabled = enabled;
                ResponseBody::SyncStatus {
                    status: state.sync.clone(),
                }
            }
            RequestBody::SetSyncScope { group, scope } => {
                if let Some(entry) = state
                    .sync
                    .groups
                    .iter_mut()
                    .find(|entry| entry.group == group)
                {
                    entry.scope = scope;
                } else {
                    state.sync.groups.push(SyncGroupState {
                        group,
                        scope,
                        fields: Vec::new(),
                    });
                }
                ResponseBody::SyncStatus {
                    status: state.sync.clone(),
                }
            }
            RequestBody::SetSyncLocalField { field, is_local } => {
                state
                    .sync
                    .local_fields
                    .retain(|existing| *existing != field);
                if is_local {
                    state.sync.local_fields.push(field);
                }
                ResponseBody::SyncStatus {
                    status: state.sync.clone(),
                }
            }
            // 見本では単語の登録を頼まれない(登録の欄は空のまま開く)
            RequestBody::TakeWordRegistration => ResponseBody::WordRegistration {
                word: None,
                reading: None,
            },
            // 辞書は見本の一覧から消すだけ(索引のファイルは無い)
            RequestBody::RemoveDictionary { id } => {
                remove_dictionary(state, "importedDictionaries", &id)
            }
            RequestBody::RemoveAssociationDictionary { id } => {
                remove_dictionary(state, "associationDictionaries", &id)
            }
            // 辞書の取り込みは見本ではファイルを読まない(読めなかったことにする)
            RequestBody::ImportDictionary { .. }
            | RequestBody::ImportAssociationDictionary { .. } => ResponseBody::FileFailed {
                reason: FileFailure::Unreadable,
            },
            // ファイルの読み書きは見本では行わない(何も変えずに済んだことにする)
            RequestBody::ImportRuleList { .. }
            | RequestBody::ImportProfileRules { .. }
            | RequestBody::ImportUserDictionary { .. }
            | RequestBody::ImportSettings { .. } => ResponseBody::Imported {
                added: 0,
                skipped: 0,
            },
            _ => ResponseBody::Done,
        })
    }
}

/// 見本の辞書の一覧(path)から id の辞書を外す
fn remove_dictionary(state: &mut State, path: &str, id: &str) -> ResponseBody {
    let Some(Value::Array(list)) = state.current.get_mut(path) else {
        return ResponseBody::FileFailed {
            reason: FileFailure::UnknownDictionary,
        };
    };
    let before = list.len();
    list.retain(|element| element.get("id").and_then(Value::as_str) != Some(id));
    if list.len() == before {
        return ResponseBody::FileFailed {
            reason: FileFailure::UnknownDictionary,
        };
    }
    ResponseBody::Done
}

fn symbols(state: &mut State, kind: SymbolKind) -> &mut Vec<SymbolItem> {
    match kind {
        SymbolKind::Sequence => &mut state.sequences,
        SymbolKind::Reading => &mut state.readings,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::engine::EngineStore;
    use crate::store::SettingsStore;

    #[test]
    fn 見本の値には設定のファイルの項目がすべてある() {
        let catalog = crate::catalog::Catalog::load().unwrap();
        let store = EngineStore::new(SampleEngine::new());
        let defaults = store.read(&catalog.fields, true).unwrap();
        for name in &catalog.fields {
            assert!(
                defaults
                    .get(name)
                    .is_some_and(|value| !value.is_null() || name == "customThemeID"),
                "{name}"
            );
        }
    }

    #[test]
    fn 書いた値を覚えて読み返す() {
        let store = EngineStore::new(SampleEngine::new());
        let mut values = Fields::new();
        values.insert("liveConversion".into(), Value::Bool(false));
        store.write(&values).unwrap();
        let read = store.read(&["liveConversion".to_string()], false).unwrap();
        assert_eq!(read["liveConversion"], Value::Bool(false));
        let defaults = store.read(&["liveConversion".to_string()], true).unwrap();
        assert_eq!(defaults["liveConversion"], Value::Bool(true));
        assert!(!store.read_user_dictionary().unwrap().is_empty());
        assert_eq!(store.take_word_registration(), Ok(None));
        assert!(!store
            .read_symbol_items(SymbolKind::Reading)
            .unwrap()
            .is_empty());
    }

    #[test]
    fn 見本の辞書を一覧から消す() {
        use crate::engine::FileOutcome;
        use crate::pages::DictionaryList;
        let store = EngineStore::new(SampleEngine::new());
        let path = "importedDictionaries".to_string();
        let count = |store: &EngineStore<SampleEngine>| {
            let values = store.read(std::slice::from_ref(&path), false).unwrap();
            crate::dictionaries::entries(DictionaryList::Imported, values.get(&path)).len()
        };
        let before = count(&store);
        assert!(before >= 2);
        let id = "D0000000-0000-0000-0000-000000000002".to_string();
        assert_eq!(
            store.remove_dictionary(DictionaryList::Imported, id.clone()),
            Ok(FileOutcome::Done)
        );
        assert_eq!(count(&store), before - 1);
        assert_eq!(
            store.remove_dictionary(DictionaryList::Imported, id),
            Ok(FileOutcome::Failed(FileFailure::UnknownDictionary))
        );
        assert_eq!(
            store.import_dictionary(DictionaryList::Imported, "C:\\a.txt".into(), None),
            Ok(FileOutcome::Failed(FileFailure::Unreadable))
        );
    }
}
