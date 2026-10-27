#![forbid(unsafe_code)]

//! 部品の操作(page::Event)を，設定の読み書きとエンジンへの頼みにする．
//! モーダルの窓(知らせ・ファイルを選ぶ窓)は状態を借りている間に出さず，After にして手続きの外で出す

use super::ffi::{self, Window};
use super::page::{DictionaryAction, Event, ThemeAction};
use super::window::{with_app, App};
use super::Store;
use crate::engine::FileOutcome;
use crate::files::FileTask;
use crate::list::{Item, ListSpec};
use crate::model::SettingsModel;
use crate::options;
use crate::pages::{Action, DictionaryList, Page};
use crate::store::StoreError;
use crate::strings::{
    association, dictionaries, features, keys, more, rule_list, settings, sync as sync_text,
    windows as text,
};
use ipc::{
    ContrastPair, DictionaryAddResult, DictionaryEntry, FileFailure, RequestBody, SymbolItem,
    SymbolKind, SymbolOrigin, SymbolSaveResult, SyncStatus,
};
use std::borrow::Cow;

/// 窓の外に出してから行うこと(借りている間にモーダルの窓を出さない)
pub enum After {
    Message {
        text: Cow<'static, str>,
        warning: bool,
    },
    /// 件数などを含む知らせ
    Notice(String),
    OpenSettingsFile,
    /// ファイルを選ぶ窓を出してから，読み込む・書き出す
    File(FileTask),
    /// フォルダを選ぶ窓を出してから，同期のフォルダにする
    ChooseSyncFolder,
    /// 色を選ぶ窓を出してから，path の色を変える
    ChooseColor {
        path: &'static str,
        current: String,
    },
    /// アプリの実行ファイルを選ぶ窓を出してから，一覧の入力欄に名前を入れる
    ChooseApp {
        path: &'static str,
    },
    /// ファイルを選ぶ窓を出してから，辞書を取り込む
    ImportDictionary {
        list: DictionaryList,
        replacing: Option<String>,
    },
}

pub fn run_after(window: Window, after: Option<After>) {
    match after {
        Some(After::Message { text, warning }) => {
            ffi::message(window, settings::WINDOW_TITLE, &text, warning)
        }
        Some(After::Notice(text)) => ffi::message(window, settings::WINDOW_TITLE, &text, false),
        Some(After::OpenSettingsFile) => {
            if let Some(path) = settings_file().filter(|path| path.exists()) {
                ffi::open_with_default_app(&path);
            }
        }
        Some(After::ChooseApp { path }) => {
            let filter = crate::files::APP_FILTER;
            let Some(file) = ffi::choose_file(window, true, "", filter.name, filter.pattern) else {
                return;
            };
            // 除外設定はアプリを実行ファイルの名前(小文字)で見分ける
            let name = std::path::Path::new(&file)
                .file_name()
                .map(|name| name.to_string_lossy().to_lowercase())
                .unwrap_or_default();
            with_app(|app| {
                app.view.set_list_input(path, 0, &name);
                ffi::invalidate(app.window);
            });
        }
        Some(After::ImportDictionary { list, replacing }) => {
            let filter = crate::files::TEXT_FILTER;
            let Some(path) = ffi::choose_file(window, true, "", filter.name, filter.pattern) else {
                return;
            };
            let after = with_app(|app| app.import_dictionary(list, path, replacing)).flatten();
            run_after(window, after);
        }
        Some(After::ChooseColor { path, current }) => {
            let Some((red, green, blue)) = ffi::choose_color(window, crate::themes::rgb(&current))
            else {
                return;
            };
            let value = serde_json::Value::String(format!("#{red:02X}{green:02X}{blue:02X}"));
            let after = with_app(|app| {
                app.handle(Event::Set {
                    path,
                    value,
                    clears: None,
                })
            })
            .flatten();
            run_after(window, after);
        }
        Some(After::ChooseSyncFolder) => {
            let Some(path) = ffi::choose_folder(window) else {
                return;
            };
            let after =
                with_app(|app| app.request_sync(RequestBody::SetSyncFolder { path })).flatten();
            run_after(window, after);
        }
        Some(After::File(task)) => {
            let Some(name) = with_app(|app| task.default_name(&app.catalog)) else {
                return;
            };
            let filter = task.filter();
            let Some(path) =
                ffi::choose_file(window, task.is_import(), &name, filter.name, filter.pattern)
            else {
                return;
            };
            let after = with_app(|app| app.run_file(task, path)).flatten();
            run_after(window, after);
        }
        None => {}
    }
    with_app(|app| ffi::invalidate(app.window));
}

/// 設定のファイルの置き場所(エンジンの S90Persistence と同じ %APPDATA%\s90.tokyo\IME\settings.json)
fn settings_file() -> Option<std::path::PathBuf> {
    std::env::var_os("APPDATA").map(|base| {
        std::path::PathBuf::from(base)
            .join("s90.tokyo")
            .join("IME")
            .join("settings.json")
    })
}

impl App {
    /// 開いているページが設定の値のほかに出すもの(統計・登録した単語)を読む
    pub(super) fn read_extras(&mut self) {
        let Some(model) = &self.model else { return };
        match self.view.page {
            Page::Usage => {
                if let Ok(usage) = model.store().read_usage() {
                    self.extras.usage = usage;
                }
            }
            Page::Appearance => {
                // 初めは今使っているカスタムテーマを編集する
                if self.editing_theme.is_none() {
                    self.editing_theme = model
                        .value(crate::themes::ACTIVE)
                        .and_then(serde_json::Value::as_str)
                        .map(str::to_string);
                }
                self.check_theme();
            }
            Page::Sync => {
                if let Ok(status) = model.store().read_sync() {
                    self.show_sync(&status);
                }
            }
            Page::Symbols => {
                for kind in [SymbolKind::Sequence, SymbolKind::Reading] {
                    if let Ok(items) = model.store().read_symbol_items(kind) {
                        *self.extras.symbol_rows_mut(kind) = items.iter().map(symbol_row).collect();
                        match kind {
                            SymbolKind::Sequence => self.sequences = items,
                            SymbolKind::Reading => self.readings = items,
                        }
                    }
                }
            }
            Page::Dictionary => {
                if let Ok(entries) = model.store().read_user_dictionary() {
                    self.extras.dictionary = entries
                        .iter()
                        .map(|entry| vec![entry.reading.clone(), entry.word.clone()])
                        .collect();
                    self.dictionary = entries;
                }
            }
            _ => {}
        }
    }

    /// 頼みが失敗したときの後始末．つながらないならつなぎ直しに回し，ほかは書けなかったと知らせる
    fn failure(&mut self, error: StoreError) -> Option<After> {
        if error == StoreError::Unavailable {
            self.disconnect();
            return None;
        }
        if let Some(model) = self.model.as_mut() {
            if model.reload().is_err() {
                self.disconnect();
                return None;
            }
        }
        Some(failed())
    }

    pub(super) fn handle(&mut self, event: Event) -> Option<After> {
        if let Event::ListAdd {
            spec,
            limit,
            item,
            replacing,
        } = &event
        {
            return self.add_to_list(spec, limit.limit(&self.catalog), item, *replacing);
        }
        if let Event::ChooseApp { path } = event {
            return Some(After::ChooseApp { path });
        }
        if matches!(
            event,
            Event::SymbolSave { .. } | Event::SymbolRemove { .. } | Event::SymbolToggle { .. }
        ) {
            return self.edit_symbols(event);
        }
        // 同期の値は設定のファイルの項目ではないので，同期の要求にして頼む
        if let Event::Set { path, value, .. } = &event {
            if crate::sync::is_sync_path(path) {
                let body = crate::sync::request(path, value)?;
                return self.request_sync(body);
            }
            if crate::themes::is_theme_path(path) {
                return self.edit_theme(path, value);
            }
        }
        match event {
            Event::ThemeList {
                action,
                index,
                name: _,
            } => self.theme_list(action, index),
            Event::ThemeSelected(index) => {
                let entries =
                    crate::themes::entries(self.model.as_ref()?.value(crate::themes::THEMES));
                self.editing_theme =
                    index.and_then(|index| entries.get(index).map(|entry| entry.id.clone()));
                self.check_theme();
                self.refresh();
                None
            }
            Event::ChooseColor { path, current } => Some(After::ChooseColor { path, current }),
            other => self.handle_other(other),
        }
    }

    fn handle_other(&mut self, event: Event) -> Option<After> {
        if let Event::DictionaryList {
            list,
            action,
            index,
        } = event
        {
            return self.edit_dictionary_list(list, action, index);
        }
        match &event {
            Event::Action(Action::SyncNow) => return self.request_sync(RequestBody::SyncNow),
            Event::Action(Action::ChooseSyncFolder) => return Some(After::ChooseSyncFolder),
            Event::SyncToggleFields(indices) => {
                let changes: Vec<RequestBody> = indices
                    .iter()
                    .filter_map(|index| self.sync_rows.get(*index))
                    .map(|row| RequestBody::SetSyncLocalField {
                        field: row.field.clone(),
                        is_local: !row.local,
                    })
                    .collect();
                let mut after = None;
                for body in changes {
                    after = self.request_sync(body);
                    if after.is_some() {
                        break;
                    }
                }
                return after;
            }
            _ => {}
        }
        let model = self.model.as_mut()?;
        let result = match event {
            Event::Set {
                path,
                value,
                clears,
            } => model.set_clearing(path, value, clears),
            Event::Reset(path) => model.reset(path),
            Event::ListRemove { spec, indices } => {
                let list = spec.remove(model.value(spec.path), &indices);
                model.set(spec.path, list)
            }
            Event::ListAdd { .. }
            | Event::SymbolSave { .. }
            | Event::SymbolRemove { .. }
            | Event::SymbolToggle { .. }
            | Event::SyncToggleFields(_)
            | Event::DictionaryList { .. }
            | Event::ThemeList { .. }
            | Event::ThemeSelected(_)
            | Event::ChooseColor { .. }
            | Event::ChooseApp { .. }
            | Event::Action(Action::SyncNow | Action::ChooseSyncFolder) => return None,
            Event::DictionaryAdd { item, replacing } => {
                let entry = DictionaryEntry {
                    reading: item.first().cloned().unwrap_or_default(),
                    word: item.get(1).cloned().unwrap_or_default(),
                };
                // 書き換えるときは，新しい単語を登録できてから元の単語を消す(登録できなければ元のまま)
                let old = replacing
                    .and_then(|index| self.dictionary.get(index).cloned())
                    .filter(|old| *old != entry);
                let result = model.store().add_user_dictionary_entry(entry);
                if let (Ok(DictionaryAddResult::Added), Some(old)) = (&result, old) {
                    if let Err(error) = model.store().remove_user_dictionary_entry(old) {
                        return self.failure(error);
                    }
                }
                let result = match result {
                    Err(error) => return self.failure(error),
                    Ok(result) => result,
                };
                let after = match result {
                    DictionaryAddResult::Added => {
                        self.view.clear_list_inputs("");
                        None
                    }
                    DictionaryAddResult::AlreadyRegistered => {
                        Some(rule_list::ALREADY_REGISTERED.into())
                    }
                    DictionaryAddResult::Invalid => {
                        Some(crate::strings::limited::invalid_entry(&self.catalog.limits).into())
                    }
                    DictionaryAddResult::Full => Some(rule_list::FULL.into()),
                };
                self.read_extras();
                self.refresh();
                return after.map(|text| After::Message {
                    text,
                    warning: true,
                });
            }
            Event::DictionaryRemove(indices) => {
                let entries: Vec<DictionaryEntry> = indices
                    .iter()
                    .filter_map(|index| self.dictionary.get(*index).cloned())
                    .collect();
                // 消せなかった語があっても残りは消す
                let error = entries
                    .into_iter()
                    .filter_map(|entry| model.store().remove_user_dictionary_entry(entry).err())
                    .last();
                if let Some(error) = error {
                    return self.failure(error);
                }
                self.read_extras();
                self.refresh();
                return None;
            }
            Event::Preview { text, preceding } => {
                let shown = if text.trim().is_empty() {
                    String::new()
                } else {
                    model
                        .store()
                        .preview_language(&text, &preceding)
                        .map(|words| crate::engine::preview_text(&words))
                        .unwrap_or_default()
                };
                self.view.show_preview(&shown);
                return None;
            }
            Event::Action(Action::RestoreDefaults) => model.restore_defaults(),
            Event::Action(Action::RestoreKeymap) => load_preset(model, STANDARD_PRESET),
            Event::LoadPreset(preset) => load_preset(model, preset),
            Event::Action(Action::ResetLearning) => {
                if let Err(error) = model.store().reset_learning() {
                    return self.failure(error);
                }
                self.refresh();
                return Some(After::Message {
                    text: settings::LEARNING_RESET.into(),
                    warning: false,
                });
            }
            Event::Action(Action::OpenSettingsFile) => return Some(After::OpenSettingsFile),
            Event::Action(Action::File(task)) => return Some(After::File(task)),
            Event::Action(Action::ResetUsage) => {
                if let Err(error) = model.store().reset_usage() {
                    return self.failure(error);
                }
                self.read_extras();
                self.refresh();
                return None;
            }
        };
        // 書けなかったときは今の値を読み直して部品を戻す
        let after = match result {
            Err(error) => self.failure(error),
            Ok(()) => None,
        };
        self.refresh();
        after
    }

    /// 辞書の一覧の操作．名前などの書き換え・切り替え・並べ替えは設定の値を書き，取り込みと削除はエンジンに頼む
    fn edit_dictionary_list(
        &mut self,
        list: DictionaryList,
        action: DictionaryAction,
        index: Option<usize>,
    ) -> Option<After> {
        let model = self.model.as_mut()?;
        let path = list.path();
        let current = model.value(path).cloned();
        let entries = crate::dictionaries::entries(list, current.as_ref());
        let chosen = index.and_then(|index| entries.get(index));
        let changed = match (&action, index) {
            (DictionaryAction::Import, _) => {
                let limit = match list {
                    DictionaryList::Imported => self.catalog.limits.imported_dictionaries,
                    DictionaryList::Association => self.catalog.limits.association_dictionaries,
                };
                if entries.len() >= limit {
                    return Some(After::Notice(match list {
                        DictionaryList::Imported => dictionaries::too_many(limit),
                        DictionaryList::Association => association::too_many(limit),
                    }));
                }
                return Some(After::ImportDictionary {
                    list,
                    replacing: None,
                });
            }
            (DictionaryAction::Reimport, _) => {
                let entry = chosen.filter(|entry| !entry.is_bundled)?;
                return Some(After::ImportDictionary {
                    list,
                    replacing: Some(entry.id.clone()),
                });
            }
            (DictionaryAction::Remove, _) => {
                // 同梱の辞書は消せない(オフにはできる)
                let entry = chosen.filter(|entry| !entry.is_bundled)?;
                let outcome = model.store().remove_dictionary(list, entry.id.clone());
                return self.finish_dictionary(list, outcome, false);
            }
            (DictionaryAction::Update(inputs), Some(index)) => {
                match crate::dictionaries::update(list, current.as_ref(), index, inputs) {
                    Some(value) => value,
                    None => {
                        return Some(After::Message {
                            text: text::INVALID_APP.into(),
                            warning: true,
                        })
                    }
                }
            }
            (DictionaryAction::Toggle, Some(index)) => {
                crate::dictionaries::toggle(current.as_ref(), index)?
            }
            (DictionaryAction::MoveUp, Some(index)) => {
                crate::dictionaries::moved(current.as_ref(), index, -1)?
            }
            (DictionaryAction::MoveDown, Some(index)) => {
                crate::dictionaries::moved(current.as_ref(), index, 1)?
            }
            _ => return None,
        };
        let result = model.set(path, changed);
        let after = result.err().and_then(|error| self.failure(error));
        self.refresh();
        after
    }

    /// 選んだファイルを辞書として取り込む
    fn import_dictionary(
        &mut self,
        list: DictionaryList,
        path: String,
        replacing: Option<String>,
    ) -> Option<After> {
        let outcome = self
            .model
            .as_ref()?
            .store()
            .import_dictionary(list, path, replacing);
        self.finish_dictionary(list, outcome, true)
    }

    /// 取り込み・削除の結果を知らせ，設定を読み直す
    fn finish_dictionary(
        &mut self,
        list: DictionaryList,
        outcome: Result<FileOutcome, StoreError>,
        importing: bool,
    ) -> Option<After> {
        let outcome = match outcome {
            Err(error) => return self.failure(error),
            Ok(outcome) => outcome,
        };
        if self.model.as_mut()?.reload().is_err() {
            self.disconnect();
            return None;
        }
        self.refresh();
        let import_failed = match list {
            DictionaryList::Imported => dictionaries::IMPORT_FAILED,
            DictionaryList::Association => association::IMPORT_FAILED,
        };
        match outcome {
            FileOutcome::Imported(count) => Some(After::Notice(match list {
                DictionaryList::Imported => dictionaries::imported(count),
                DictionaryList::Association => association::imported(count),
            })),
            FileOutcome::Failed(FileFailure::WriteFailed) => Some(failed()),
            FileOutcome::Failed(_) if importing => Some(After::Message {
                text: import_failed.into(),
                warning: true,
            }),
            FileOutcome::Failed(_) | FileOutcome::Done => None,
        }
    }

    /// 編集しているカスタムテーマの色・形・書体を変える
    fn edit_theme(&mut self, path: &str, value: &serde_json::Value) -> Option<After> {
        let id = self.editing_theme.clone()?;
        let model = self.model.as_mut()?;
        let changed = crate::themes::edited(model.value(crate::themes::THEMES), &id, path, value)?;
        if let Err(error) = model.set(crate::themes::THEMES, changed) {
            return self.failure(error);
        }
        self.check_theme();
        self.refresh();
        None
    }

    /// 編集しているカスタムテーマの読みやすさをエンジンに確かめてもらう(macOS の CustomThemeEditor の読みやすさ)
    fn check_theme(&mut self) {
        self.extras.theme_report = String::new();
        let Some(model) = &self.model else { return };
        let entries = crate::themes::entries(model.value(crate::themes::THEMES));
        let Some(entry) = self
            .editing_theme
            .as_deref()
            .and_then(|id| entries.iter().find(|entry| entry.id == id))
        else {
            return;
        };
        let Ok(issues) = model.store().check_custom_theme(&entry.value) else {
            return;
        };
        self.extras.theme_report = issues
            .iter()
            .map(|issue| {
                let (name, ground) = match issue.pair {
                    ContrastPair::Text => (more::TEXT, more::SURFACE),
                    ContrastPair::TextMuted => (more::TEXT_MUTED, more::SURFACE),
                    ContrastPair::SelectionText => (more::SELECTION_TEXT, more::SELECTION),
                    ContrastPair::Correction => (more::CORRECTION, more::SURFACE),
                };
                more::low_contrast(name, ground, issue.ratio, issue.minimum)
            })
            .collect::<Vec<_>>()
            .join("\n");
    }

    /// カスタムテーマの一覧の操作(macOS の AppearancePage と SettingsModel の draftCustomTheme など)
    fn theme_list(&mut self, action: ThemeAction, index: Option<usize>) -> Option<After> {
        let limit = self.catalog.limits.custom_themes;
        let name_limit = self.catalog.limits.theme_name_length;
        let dark = self.theme.dark;
        let model = self.model.as_mut()?;
        let themes = model.value(crate::themes::THEMES).cloned();
        let active = model
            .value(crate::themes::ACTIVE)
            .and_then(serde_json::Value::as_str)
            .map(str::to_string);
        let entries = crate::themes::entries(themes.as_ref());
        let chosen = index.and_then(|index| entries.get(index));
        let full = || Some(After::Notice(more::themes_full(limit)));
        let seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |elapsed| elapsed.as_nanos());
        let mut changes: Vec<(&'static str, serde_json::Value)> = Vec::new();
        let mut editing = self.editing_theme.clone();
        match action {
            ThemeAction::Rename(name) => {
                let id = &chosen?.id;
                match crate::themes::renamed(themes.as_ref(), id, &name, name_limit) {
                    Some(changed) => changes.push((crate::themes::THEMES, changed)),
                    None => {
                        return Some(After::Message {
                            text: more::INVALID_THEME.into(),
                            warning: true,
                        })
                    }
                }
            }
            ThemeAction::Create | ThemeAction::DuplicateCurrent => {
                if entries.len() >= limit {
                    return full();
                }
                let id = crate::themes::new_id(seed);
                let active_entry = active
                    .as_deref()
                    .and_then(|active| entries.iter().find(|entry| entry.id == active));
                let theme_name = model
                    .value("theme")
                    .and_then(serde_json::Value::as_str)
                    .unwrap_or("automatic")
                    .to_string();
                let source_name = active_entry.map_or_else(
                    || options::label_of(options::THEMES, &theme_name).to_string(),
                    |entry| entry.name.clone(),
                );
                let name: String = match action {
                    ThemeAction::Create => {
                        crate::themes::unique_name(more::NEW_THEME_NAME, &entries)
                    }
                    _ => more::copy_name(&source_name),
                }
                .chars()
                .take(name_limit)
                .collect();
                let theme = match active_entry {
                    Some(entry) => crate::themes::copy(&entry.value, id.clone(), name)?,
                    None => preset_theme(&theme_name, id.clone(), name, dark),
                };
                changes.push((
                    crate::themes::THEMES,
                    crate::themes::appended(themes.as_ref(), theme),
                ));
                changes.push((crate::themes::ACTIVE, serde_json::Value::String(id.clone())));
                editing = Some(id);
            }
            ThemeAction::Use => {
                let entry = chosen?;
                changes.push((
                    crate::themes::ACTIVE,
                    serde_json::Value::String(entry.id.clone()),
                ));
            }
            ThemeAction::Duplicate => {
                if entries.len() >= limit {
                    return full();
                }
                let entry = chosen?;
                let id = crate::themes::new_id(seed);
                let name: String = more::copy_name(&entry.name)
                    .chars()
                    .take(name_limit)
                    .collect();
                let theme = crate::themes::copy(&entry.value, id.clone(), name)?;
                changes.push((
                    crate::themes::THEMES,
                    crate::themes::appended(themes.as_ref(), theme),
                ));
                changes.push((crate::themes::ACTIVE, serde_json::Value::String(id.clone())));
                editing = Some(id);
            }
            ThemeAction::Delete => {
                let entry = chosen?;
                changes.push((
                    crate::themes::THEMES,
                    crate::themes::removed(themes.as_ref(), &entry.id)?,
                ));
                if active.as_deref() == Some(entry.id.as_str()) {
                    changes.push((crate::themes::ACTIVE, serde_json::Value::Null));
                }
                if editing.as_deref() == Some(entry.id.as_str()) {
                    editing = None;
                }
            }
        }
        if let Err(error) = model.set_all(&changes) {
            return self.failure(error);
        }
        self.editing_theme = editing;
        self.check_theme();
        self.refresh();
        None
    }

    /// 同期の状態を画面の値にする
    fn show_sync(&mut self, status: &SyncStatus) {
        self.sync_values = crate::sync::values(status);
        self.extras.sync_folder = status
            .folder_name
            .clone()
            .unwrap_or_else(|| sync_text::NO_FOLDER.to_string());
        self.extras.last_synced = status
            .last_synced_at
            .as_deref()
            .and_then(crate::sync::parse_time)
            .map(|time| crate::sync::format_time(ffi::local_time(time).unwrap_or(time)))
            .unwrap_or_else(|| NO_TIME.to_string());
        self.sync_rows = crate::sync::field_rows(status);
        self.extras.sync_fields = crate::sync::field_table(&self.sync_rows);
    }

    /// 同期の要求をエンジンに頼み，返った状態を画面に出す
    pub(super) fn request_sync(&mut self, body: RequestBody) -> Option<After> {
        let result = self.model.as_ref()?.store().sync(body);
        match result {
            Err(error) => self.failure(error),
            Ok(status) => {
                self.show_sync(&status);
                self.refresh();
                None
            }
        }
    }

    /// 記号の決まりを重ねる・外す・切り替える．終わったら一覧を読み直す
    fn edit_symbols(&mut self, event: Event) -> Option<After> {
        let model = self.model.as_ref()?;
        let store = model.store();
        let items = match &event {
            Event::SymbolSave { kind, .. }
            | Event::SymbolRemove { kind, .. }
            | Event::SymbolToggle { kind, .. } => match kind {
                SymbolKind::Sequence => &self.sequences,
                SymbolKind::Reading => &self.readings,
            },
            _ => return None,
        };
        let selected = |indices: &[usize]| -> Vec<SymbolItem> {
            indices
                .iter()
                .filter_map(|index| items.get(*index).cloned())
                .collect()
        };
        let mut notice = None;
        let result = match event {
            Event::SymbolSave {
                kind,
                item,
                replacing,
            } => {
                let input = item.first().cloned().unwrap_or_default();
                let output = item.get(1).cloned().unwrap_or_default();
                // 選んで書き換えている決まりは，その入力を置き換える(既定の決まりの入力は変えられない)
                let old = replacing
                    .and_then(|index| items.get(index))
                    .map(|item| item.input.clone());
                // 無効にしていた決まりを書き換えたときも無効のまま
                let enabled = items
                    .iter()
                    .find(|existing| {
                        Some(&existing.input) == old.as_ref() || existing.input == input
                    })
                    .is_none_or(|existing| existing.is_enabled);
                store
                    .save_symbol_rule(kind, input, output, enabled, old)
                    .map(|result| {
                        notice = match result {
                            SymbolSaveResult::Saved => None,
                            SymbolSaveResult::Invalid => {
                                Some(symbol_invalid(kind, &self.catalog.limits).into())
                            }
                            SymbolSaveResult::Full => Some(rule_list::FULL.into()),
                        };
                    })
            }
            Event::SymbolRemove { kind, indices } => {
                let inputs = selected(&indices)
                    .into_iter()
                    .map(|item| item.input)
                    .collect();
                store.remove_symbol_rules(kind, inputs)
            }
            Event::SymbolToggle { kind, indices } => {
                selected(&indices).into_iter().try_for_each(|item| {
                    store
                        .save_symbol_rule(kind, item.input, item.output, !item.is_enabled, None)
                        .map(|_| ())
                })
            }
            _ => Ok(()),
        };
        if let Err(error) = result {
            return self.failure(error);
        }
        if notice.is_none() {
            self.view.clear_symbol_inputs();
        }
        self.read_extras();
        self.refresh();
        notice.map(|text: Cow<'static, str>| After::Message {
            text,
            warning: true,
        })
    }

    /// 選んだファイルを読み込む・書き出す．読み込んだら設定と辞書を読み直す
    fn run_file(&mut self, task: FileTask, path: String) -> Option<After> {
        let model = self.model.as_mut()?;
        let outcome = model.store().run_file(task, path);
        let outcome = match outcome {
            Err(error) => return self.failure(error),
            Ok(outcome) => outcome,
        };
        if task.is_import() {
            if model.reload().is_err() {
                self.disconnect();
                return None;
            }
            self.read_extras();
            self.refresh();
        }
        match outcome {
            FileOutcome::Done => task.done().map(|text| After::Message {
                text: text.into(),
                warning: false,
            }),
            FileOutcome::Imported(added) => Some(After::Notice(task.imported(added))),
            FileOutcome::Failed(_) => Some(After::Message {
                text: task.failed().into(),
                warning: true,
            }),
        }
    }

    /// 一覧に行を足す．上限を超える・形が誤っていて残らないときは知らせる
    fn add_to_list(
        &mut self,
        spec: &ListSpec,
        limit: usize,
        item: &Item,
        replacing: Option<usize>,
    ) -> Option<After> {
        if !spec.is_valid(item) {
            return Some(After::Message {
                text: spec.invalid.resolve(&self.catalog.limits),
                warning: true,
            });
        }
        let model = self.model.as_mut()?;
        // 選んで書き換えている行は，消してから足す(同じ位置ではなく，ほかの行と同じく決まりの並びで足す)
        let current = match replacing {
            Some(index) => Some(spec.remove(model.value(spec.path), &[index])),
            None => model.value(spec.path).cloned(),
        };
        let items = spec.items(current.as_ref());
        let is_new = !items.iter().any(|existing| spec.same_key(existing, item));
        if is_new && items.len() >= limit {
            return Some(After::Message {
                text: rule_list::FULL.into(),
                warning: true,
            });
        }
        // いつも英語にする語といつも日本語にする語は，足した語をもう一方から除く(macOS と同じ)
        let mut changes = vec![(spec.path, spec.upsert(current.as_ref(), item))];
        if let (Some(other), Some(word)) = (spec.exclusive_with, item.first()) {
            changes.push((other, ListSpec::without(model.value(other), word)));
        }
        let result = model.set_all(&changes);
        let kept = spec.contains(model.value(spec.path), item);
        let after = match result {
            Err(error) => self.failure(error),
            Ok(()) if !kept => Some(After::Message {
                text: spec.invalid.resolve(&self.catalog.limits),
                warning: true,
            }),
            Ok(()) => {
                self.view.clear_list_inputs(spec.path);
                None
            }
        };
        self.refresh();
        after
    }
}

/// 標準のひな形の値(KeymapPreset.standard)
const STANDARD_PRESET: &str = "standard";

/// ひな形を読んで keymap の項目に書く
fn load_preset(model: &mut SettingsModel<Store>, preset: &str) -> Result<(), StoreError> {
    let fields = model.store().read_keymap_preset(preset)?;
    let keymap = fields.get("keymap").cloned().ok_or(StoreError::Malformed)?;
    model.set("keymap", keymap)
}

/// 今の表の問題を文にする．調べられなければ空
pub fn keymap_report(model: &SettingsModel<Store>) -> String {
    let Some(keymap) = model.value("keymap").cloned() else {
        return String::new();
    };
    let entries: Vec<(String, String, String)> = keymap
        .as_array()
        .map(|rows| {
            rows.iter()
                .map(|row| {
                    let text = |name: &str| {
                        row.get(name)
                            .and_then(serde_json::Value::as_str)
                            .unwrap_or("")
                            .to_string()
                    };
                    (text("state"), text("key"), text("command"))
                })
                .collect()
        })
        .unwrap_or_default();
    let mut values = crate::store::Fields::new();
    values.insert("keymap".to_string(), keymap);
    model
        .store()
        .check_keymap(&values)
        .map(|report| crate::keys::report_lines(&report, &entries).join("\n"))
        .unwrap_or_default()
}

/// 確かめてから行う操作の題と文
pub fn confirmation(event: &Event) -> Option<(String, String)> {
    let name = |preset: &str| {
        keys::PRESETS
            .iter()
            .find(|(value, _)| *value == preset)
            .map_or(preset, |(_, label)| label)
            .to_string()
    };
    match event {
        Event::LoadPreset(preset) => Some((
            keys::LOAD_PRESET_TITLE.to_string(),
            keys::load_preset_message(&name(preset)),
        )),
        Event::Action(Action::RestoreKeymap) => Some((
            keys::RESTORE_TITLE.to_string(),
            keys::RESTORE_MESSAGE.to_string(),
        )),
        Event::ThemeList {
            action: ThemeAction::Delete,
            name,
            ..
        } => Some((
            settings::WINDOW_TITLE.to_string(),
            more::confirm_delete_theme(name),
        )),
        _ => None,
    }
}

/// 既成のテーマの色を写したカスタムテーマ(macOS の SettingsModel.customTheme(from:) と同じ)．
/// 色は候補ウィンドウと同じ解き方で，今の画面の明暗の色にする
fn preset_theme(
    theme: &str,
    id: String,
    name: String,
    dark: bool,
) -> serde_json::Map<String, serde_json::Value> {
    use candidate_ui::theme::{Color, ResolvedTheme, SystemLook};
    let resolved = ResolvedTheme::resolve(
        theme,
        None,
        &SystemLook {
            dark,
            ..SystemLook::default()
        },
    );
    let hex = |color: Color| crate::themes::hex(color.red, color.green, color.blue);
    crate::themes::from_colors(
        id,
        name,
        theme,
        [
            ("surface", hex(resolved.surface)),
            ("text", hex(resolved.text)),
            ("textMuted", hex(resolved.text_muted)),
            ("selection", hex(resolved.selection)),
            ("selectionText", hex(resolved.selection_text)),
            ("correction", hex(resolved.correction)),
            ("line", hex(resolved.line)),
        ],
        f64::from(resolved.corner_radius),
    )
}

/// 一度も同期していないときの時刻(macOS の SyncPage と同じ)
const NO_TIME: &str = "—";

/// 記号の一覧の 1 行(入力・記号・状態)．状態は無効と，既定から変えた・足した印
fn symbol_row(item: &SymbolItem) -> Vec<String> {
    let origin = match item.origin {
        SymbolOrigin::Standard => None,
        SymbolOrigin::Changed => Some(features::CHANGED),
        SymbolOrigin::Added => Some(features::ADDED),
    };
    let state: Vec<&str> = (!item.is_enabled)
        .then_some(text::DISABLED)
        .into_iter()
        .chain(origin)
        .collect();
    vec![item.input.clone(), item.output.clone(), state.join("・")]
}

fn symbol_invalid(kind: SymbolKind, limits: &crate::catalog::Limits) -> String {
    match kind {
        SymbolKind::Sequence => crate::strings::limited::invalid_symbol(limits),
        SymbolKind::Reading => crate::strings::limited::invalid_reading_symbol(limits),
    }
}

fn failed() -> After {
    After::Message {
        text: settings::SAVE_FAILED.into(),
        warning: true,
    }
}
