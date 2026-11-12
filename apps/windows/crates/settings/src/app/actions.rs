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
use crate::pages::{Action, DictionaryList, Page, TryKind};
use crate::store::StoreError;
use crate::strings::{
    association, dictionaries, features, keys, more, rule_list, settings, sync as sync_text,
    windows as text,
};
use ipc::{
    DictionaryAddResult, DictionaryEntry, FileFailure, RequestBody, SymbolItem, SymbolKind,
    SymbolOrigin, SymbolSaveResult, SyncStatus, WordClass,
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
    /// コマンドのシートの行き先を選ぶ窓を出す(application ならアプリの実行ファイルだけを出す)
    ChooseCommandTarget {
        application: bool,
    },
    OpenSettingsFile,
    /// 初期設定ウィザードを開く(同じ実行ファイルを --setup で起動する)
    OpenSetup,
    /// URL を既定のブラウザで開く
    OpenUrl(String),
    /// ファイルを選ぶ窓を出してから，読み込む・書き出す
    File(FileTask),
    /// フォルダを選ぶ窓を出してから，同期のフォルダにする
    ChooseSyncFolder,
    /// 色を選ぶ窓を出してから，path の色を変える
    ChooseColor {
        path: &'static str,
        current: String,
    },
    /// アプリの実行ファイルを選ぶ窓を出してから(いくつも選べる)，一覧に足す
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
        Some(After::OpenSetup) => {
            // 見本の値で開いた画面からは，ウィザードも見本の値で開く(利用者の設定に触れない)
            if with_app(|app| app.offline).unwrap_or(false) {
                super::launch_settings(&[super::SETUP, super::OFFLINE]);
            } else {
                super::launch_settings(&[super::SETUP]);
            }
        }
        Some(After::OpenUrl(url)) => ffi::open_url(&url),
        Some(After::OpenSettingsFile) => {
            // 見本の値で開いたときは，利用者の設定のファイルを開かない
            if with_app(|app| app.offline).unwrap_or(false) {
                return;
            }
            if let Some(path) = settings_file().filter(|path| path.exists()) {
                ffi::open_with_default_app(&path);
            }
        }
        Some(After::ChooseApp { path }) => {
            let filter = crate::files::APP_FILTER;
            let files = ffi::choose_files(window, filter.name, filter.pattern);
            if files.is_empty() {
                return;
            }
            // 除外設定はアプリを実行ファイルの名前(小文字)で見分ける
            let names: Vec<String> = files
                .iter()
                .filter_map(|file| std::path::Path::new(file).file_name())
                .map(|name| name.to_string_lossy().to_lowercase())
                .collect();
            // 選んだアプリは，表の下で選んでいる動作でそのまま足す(macOS の ExclusionsPage と同じ)
            let after = with_app(|app| {
                let after = app.add_apps(path, &names);
                ffi::invalidate(app.window);
                after
            })
            .flatten();
            run_after(window, after);
        }
        Some(After::ChooseCommandTarget { application }) => {
            let (name, pattern) = if application {
                let filter = crate::files::APP_FILTER;
                (filter.name, filter.pattern)
            } else {
                (text::ALL_FILES, "*.*")
            };
            let Some(file) = ffi::choose_file(window, true, "", name, pattern) else {
                return;
            };
            with_app(|app| app.sheet_choose(&file));
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
            let Some(chosen) = ffi::choose_color(window, crate::themes::rgb(&current)) else {
                return;
            };
            let value = serde_json::Value::String(crate::themes::hex_of(chosen));
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

/// 設定のファイルの置き場所(エンジンの HajimePersistence と同じ %APPDATA%\haji.men\IME\settings.json)
fn settings_file() -> Option<std::path::PathBuf> {
    std::env::var_os("APPDATA").map(|base| {
        std::path::PathBuf::from(base)
            .join("haji.men")
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
                self.check_theme();
                self.check_draft();
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
                        .map(|entry| {
                            vec![
                                entry.reading.clone(),
                                entry.word.clone(),
                                word_class_label(entry.word_class).to_string(),
                                entry.comment.clone().unwrap_or_default(),
                            ]
                        })
                        .collect();
                    self.dictionary = entries;
                }
            }
            _ => {}
        }
    }

    /// 頼みが失敗したときの後始末．つながらないならつなぎ直しに回し，ほかは書けなかったと知らせる
    pub(super) fn failure(&mut self, error: StoreError) -> Option<After> {
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
        if let Event::OpenUrl(url) = event {
            return Some(After::OpenUrl(url));
        }
        if let Event::EditCommand(index) = event {
            self.open_command_sheet(index);
            return None;
        }
        if let Event::ListMove {
            spec,
            index,
            offset,
        } = event
        {
            return self.move_in_list(&spec, index, offset);
        }
        if let Event::ListSet {
            spec,
            index,
            field,
            value,
        } = event
        {
            return self.set_in_list(&spec, index, field, &value);
        }
        if let Event::Notice(text) = event {
            return Some(After::Message {
                text: text.into(),
                warning: true,
            });
        }
        if event == Event::Relayout {
            self.arrange();
            return None;
        }
        if matches!(
            event,
            Event::SymbolSave { .. } | Event::SymbolRemove { .. } | Event::SymbolToggle { .. }
        ) {
            return self.edit_symbols(event);
        }
        // 同期の値は設定のファイルの項目ではないので，同期の要求にして頼む
        if let Event::Set { path, value, .. } = &event {
            // 画面の中だけの値(開いている一覧など)は書かずに覚える
            if crate::pages::is_view_path(path) {
                self.view_values.insert((*path).to_string(), value.clone());
                self.refresh();
                return None;
            }
            if crate::sync::is_sync_path(path) {
                let body = crate::sync::request(path, value)?;
                return self.request_sync(body);
            }
            // カスタムテーマの名前・色・形・書体は編集の画面の下書きに書く(保存するまで設定のファイルに書かない)
            if crate::themes::is_theme_path(path) {
                return self.edit_draft(path, value);
            }
        }
        match event {
            Event::ThemeList {
                action,
                index,
                name: _,
            } => self.theme_list(action, index),
            Event::ThemeEditor(action) => self.editor_action(action),
            Event::Action(Action::CreateTheme) => self.theme_list(ThemeAction::Create, None),
            Event::Action(Action::DuplicateCurrentTheme) => {
                self.theme_list(ThemeAction::DuplicateCurrent, None)
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
            Event::Action(Action::OpenSetup) => return Some(After::OpenSetup),
            Event::Action(Action::CheckForUpdates) => {
                super::update::start_check(self);
                return None;
            }
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
            Event::ListToggle { spec, indices } => {
                let list = spec.toggle_enabled(model.value(spec.path), &indices);
                model.set(spec.path, list)
            }
            Event::ListAdd { .. }
            | Event::SymbolSave { .. }
            | Event::SymbolRemove { .. }
            | Event::SymbolToggle { .. }
            | Event::SyncToggleFields(_)
            | Event::DictionaryList { .. }
            | Event::ThemeList { .. }
            | Event::ThemeEditor(_)
            | Event::ChooseColor { .. }
            | Event::ChooseApp { .. }
            | Event::OpenUrl(_)
            | Event::Notice(_)
            | Event::EditCommand(_)
            | Event::ListMove { .. }
            | Event::ListSet { .. }
            | Event::Relayout
            | Event::Action(
                Action::SyncNow
                | Action::ChooseSyncFolder
                | Action::OpenSetup
                | Action::CheckForUpdates
                | Action::CreateTheme
                | Action::DuplicateCurrentTheme,
            ) => return None,
            Event::DictionaryAdd { item, replacing } => {
                let entry = DictionaryEntry {
                    reading: item.first().cloned().unwrap_or_default(),
                    word: item.get(1).cloned().unwrap_or_default(),
                    word_class: item.get(2).and_then(|value| word_class(value)),
                    comment: item
                        .get(3)
                        .map(|comment| comment.trim().to_string())
                        .filter(|comment| !comment.is_empty()),
                };
                // 書き換えるときは，新しい単語を登録できてから元の単語を消す(登録できなければ元のまま)．
                // 読みと単語が同じなら，エンジンが品詞を書き換えるので消さない
                let old = replacing
                    .and_then(|index| self.dictionary.get(index).cloned())
                    .filter(|old| old.reading != entry.reading || old.word != entry.word);
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
            Event::Preview {
                kind: TryKind::Macros,
                text,
                preceding,
                draft,
            } => {
                let shown = macro_preview(model, &text, &preceding, &draft);
                self.extras.macro_preview.clone_from(&shown);
                self.view.show_preview(TryKind::Macros, &shown);
                return None;
            }
            Event::Preview {
                kind: TryKind::Language,
                text,
                preceding,
                ..
            } => {
                let shown = if text.trim().is_empty() {
                    crate::engine::PreviewShown::default()
                } else {
                    model
                        .store()
                        .preview_language(&text, &preceding)
                        .map(|words| crate::engine::preview_text(&words))
                        .unwrap_or_default()
                };
                self.view.show_preview(TryKind::Language, &shown);
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
            Event::Action(Action::ResetPaletteHistory) => {
                if let Err(error) = model.store().reset_palette_history() {
                    return self.failure(error);
                }
                return Some(After::Message {
                    text: text::PALETTE_HISTORY_CLEARED.into(),
                    warning: false,
                });
            }
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

    /// カスタムテーマごとに読みやすさをエンジンに確かめてもらう(一覧の行の注意の印．macOS の CustomThemeRow の lowContrastPairs)
    fn check_theme(&mut self) {
        self.extras.theme_warnings.clear();
        let Some(model) = &self.model else { return };
        let entries = crate::themes::entries(model.value(crate::themes::THEMES));
        self.extras.theme_warnings = entries
            .iter()
            .map(|entry| {
                model
                    .store()
                    .check_custom_theme(&entry.value)
                    .is_ok_and(|issues| !issues.is_empty())
            })
            .collect();
    }

    /// 今使っているテーマ(カスタムテーマか既成のテーマ)を写したカスタムテーマ．id と名前は新しくする
    /// (macOS の SettingsModel の draftCustomTheme・duplicateCurrentTheme の source)
    fn current_theme_copy(
        &self,
        id: String,
        name: impl FnOnce(&str) -> String,
    ) -> Option<serde_json::Value> {
        let model = self.model.as_ref()?;
        let entries = crate::themes::entries(model.value(crate::themes::THEMES));
        let active = model
            .value(crate::themes::ACTIVE)
            .and_then(serde_json::Value::as_str)
            .and_then(|active| entries.iter().find(|entry| entry.id == active));
        let theme_name = model
            .value(crate::themes::BASE_THEME)
            .and_then(serde_json::Value::as_str)
            .unwrap_or("automatic")
            .to_string();
        let source_name = active.map_or_else(
            || options::label_of(options::THEMES, &theme_name).to_string(),
            |entry| entry.name.clone(),
        );
        let name: String = name(&source_name)
            .chars()
            .take(self.catalog.limits.theme_name_length)
            .collect();
        let theme = match active {
            Some(entry) => crate::themes::copy(&entry.value, id, name)?,
            None => preset_theme(&theme_name, id, name, self.theme.dark),
        };
        Some(serde_json::Value::Object(theme))
    }

    /// カスタムテーマの一覧の操作(macOS の AppearancePage と SettingsModel の draftCustomTheme など)
    fn theme_list(&mut self, action: ThemeAction, index: Option<usize>) -> Option<After> {
        let limit = self.catalog.limits.custom_themes;
        let name_limit = self.catalog.limits.theme_name_length;
        let entries = crate::themes::entries(self.model.as_ref()?.value(crate::themes::THEMES));
        let chosen = index.and_then(|index| entries.get(index));
        let full = entries.len() >= limit;
        // 複製したテーマ(保存して使う．macOS の SettingsModel.duplicate)
        let copy = match action {
            // 今のテーマを写した下書きを編集の画面で開く．保存するまで一覧に足さない(macOS の draftCustomTheme)
            ThemeAction::Create => {
                if full {
                    return Some(After::Notice(more::themes_full(limit)));
                }
                let draft = self.current_theme_copy(crate::themes::new_id(seed()), |_| {
                    more::NEW_THEME_NAME.to_string()
                })?;
                self.open_theme_editor(draft, true);
                return None;
            }
            ThemeAction::Edit => {
                self.open_theme_editor(chosen?.value.clone(), false);
                return None;
            }
            ThemeAction::Use => {
                let id = serde_json::Value::String(chosen?.id.clone());
                let model = self.model.as_mut()?;
                if let Err(error) = model.set(crate::themes::ACTIVE, id) {
                    return self.failure(error);
                }
                self.refresh();
                return None;
            }
            ThemeAction::Delete => {
                let entry = chosen?;
                let model = self.model.as_mut()?;
                let mut changes = vec![(
                    crate::themes::THEMES,
                    crate::themes::removed(model.value(crate::themes::THEMES), &entry.id)?,
                )];
                if model
                    .value(crate::themes::ACTIVE)
                    .and_then(serde_json::Value::as_str)
                    == Some(entry.id.as_str())
                {
                    changes.push((crate::themes::ACTIVE, serde_json::Value::Null));
                }
                if let Err(error) = model.set_all(&changes) {
                    return self.failure(error);
                }
                self.check_theme();
                self.refresh();
                return None;
            }
            ThemeAction::DuplicateCurrent => {
                self.current_theme_copy(crate::themes::new_id(seed()), more::copy_name)?
            }
            ThemeAction::Duplicate => {
                let entry = chosen?;
                let name = more::copy_name(&entry.name)
                    .chars()
                    .take(name_limit)
                    .collect();
                serde_json::Value::Object(crate::themes::copy(
                    &entry.value,
                    crate::themes::new_id(seed()),
                    name,
                )?)
            }
        };
        let model = self.model.as_mut()?;
        let changed = match crate::themes::saved(
            model.value(crate::themes::THEMES),
            &copy,
            limit,
            name_limit,
        ) {
            Ok(changed) => changed,
            Err(crate::themes::SaveError::Full) => {
                return Some(After::Notice(more::themes_full(limit)))
            }
            Err(crate::themes::SaveError::Name) => {
                return Some(After::Message {
                    text: more::INVALID_THEME.into(),
                    warning: true,
                })
            }
        };
        let id = copy.get("id").cloned().unwrap_or(serde_json::Value::Null);
        if let Err(error) = model.set_all(&[
            (crate::themes::THEMES, changed),
            (crate::themes::ACTIVE, id),
        ]) {
            return self.failure(error);
        }
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

    /// 表の index 番目の行の field 番目の欄を value にし，その行を選んだままにする(除外設定の動作の Picker)
    fn set_in_list(
        &mut self,
        spec: &ListSpec,
        index: usize,
        field: usize,
        value: &str,
    ) -> Option<After> {
        let model = self.model.as_mut()?;
        let list = spec.set_field_at(model.value(spec.path), index, field, value)?;
        if let Err(error) = model.set(spec.path, list) {
            return self.failure(error);
        }
        self.refresh();
        let now = self.now();
        self.view.select_list_row(spec.path, index, now);
        None
    }

    /// 選んだ行を offset だけ動かし，動かした行を選んだままにする(除外設定の優先度．macOS の ExclusionsPage)
    fn move_in_list(&mut self, spec: &ListSpec, index: usize, offset: isize) -> Option<After> {
        let model = self.model.as_mut()?;
        let list = spec.move_by(model.value(spec.path), index, offset)?;
        if let Err(error) = model.set(spec.path, list) {
            return self.failure(error);
        }
        self.refresh();
        let now = self.now();
        if let Some(target) = index.checked_add_signed(offset) {
            self.view.select_list_row(spec.path, target, now);
        }
        None
    }

    /// 選んだアプリ(実行ファイルの名前)を，表の下で選んでいる動作で除外設定に足す．知らせは最初の 1 つだけ出す
    pub(super) fn add_apps(&mut self, path: &'static str, names: &[String]) -> Option<After> {
        let (spec, limit) = self.view.list_spec(path)?;
        let profile = self.view.list_choice(path, 1).unwrap_or_default();
        let mut notice = None;
        for name in names {
            let item = spec.make(&[name.clone(), profile.to_string()]);
            let after = self.add_to_list(&spec, limit.limit(&self.catalog), &item, None);
            if notice.is_none() {
                notice = after;
            }
        }
        notice
    }

    /// シートのコマンドを保存する．書き換えるコマンドは id で引き，同じ位置のまま書き換える(同じ読みの
    /// コマンドがあっても書き換えるのはその 1 つ)．保存できたら true．エンジンが受け付けなければシートに文を出す
    pub(super) fn save_command(&mut self) -> (bool, Option<After>) {
        let Some(sheet) = self.sheet.as_ref() else {
            return (false, None);
        };
        let draft = sheet.draft.clone();
        let index = sheet.index;
        if !draft.is_valid() {
            return (false, None);
        }
        let Some((spec, limit)) = self.view.list_spec(crate::pages::COMMANDS) else {
            return (false, None);
        };
        let limit = limit.limit(&self.catalog);
        let Some(model) = self.model.as_mut() else {
            return (false, None);
        };
        let item = draft.item();
        let current = model.value(spec.path);
        let list = match (&draft.id, index) {
            (Some(id), _) => spec.replace_id(current, id, &item),
            // id の無いコマンド(エンジンが振る前)は行の番号で書き換える
            (None, Some(index)) => spec.replace_at(current, index, &item),
            (None, None) if spec.items(current).len() >= limit => {
                return (
                    false,
                    Some(After::Message {
                        text: rule_list::FULL.into(),
                        warning: true,
                    }),
                );
            }
            (None, None) => Some(spec.upsert(current, &item)),
        };
        // 書き換えるコマンドが消えていたら(同期で変わったなど)，新しく足す
        let list = list.unwrap_or_else(|| spec.upsert(current, &item));
        if let Err(error) = model.set(spec.path, list) {
            return (false, self.failure(error));
        }
        let items = spec.items(model.value(spec.path));
        let kept = items.contains(&item);
        self.refresh();
        if !kept {
            if let Some(sheet) = self.sheet.as_mut() {
                sheet.rejected = true;
            }
            return (false, None);
        }
        // 書き換えた・足したコマンドを選んだままにする(macOS の表は id で選んだ行を残す)
        let row = index.unwrap_or(items.len().saturating_sub(1));
        let now = self.now();
        self.view.select_list_row(spec.path, row, now);
        (true, None)
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
        // 選んで書き換えている行は，ほかの行と重なるときだけ消してから足す(重なる行に重ねる)
        let current = match replacing {
            Some(index) => Some(spec.remove(model.value(spec.path), &[index])),
            None => model.value(spec.path).cloned(),
        };
        // 書き換える行の欄に無い値(id・isEnabled など)は引き継ぐ
        let base = replacing.and_then(|index| spec.element_at(model.value(spec.path), index));
        let items = spec.items(current.as_ref());
        let is_new = !items.iter().any(|existing| spec.same_key(existing, item));
        if is_new && items.len() >= limit {
            return Some(After::Message {
                text: rule_list::FULL.into(),
                warning: true,
            });
        }
        // いつも英語にする語といつも日本語にする語は，足した語をもう一方から除く(macOS と同じ)
        // 選んだ行の書き換えは，ほかの行と重ならなければ同じ位置のまま書き換える(macOS と同じ．キー設定の表は
        // 下の行が勝つので，末尾へ動かすと効き方が変わる)
        let edited =
            replacing.and_then(|index| spec.replace_at(model.value(spec.path), index, item));
        let mut changes = vec![(
            spec.path,
            edited.unwrap_or_else(|| spec.upsert_with(current.as_ref(), item, base.as_ref())),
        )];
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

/// 試す語と読みに変換マクロを当てた結果．つながらなければ空
pub fn macro_preview(
    model: &SettingsModel<Store>,
    text: &str,
    reading: &str,
    draft: &str,
) -> crate::engine::PreviewShown {
    model
        .store()
        .preview_macros(text, reading, draft)
        .map(|results| crate::engine::macro_preview_text(&results, !draft.trim().is_empty()))
        .unwrap_or_default()
}

/// 入れるたびに変わる書き方(UUID・乱数・選ぶ)．macOS と同じく，ページを開いたときの例を 1 つ出したままにする
const CHANGING_TEMPLATES: &[&str] = &["{uuid}", "{random:1-6}", "{alnum:8}", "{pick:はい,いいえ}"];

/// 単語に書ける書き方を今入れたときの値(macOS の TemplateReference)．エンジンが変換マクロを試すときと
/// 同じ値(日時・乱数)で置き換える．入れるたびに変わる書き方は，前に求めた値があればそのまま使う．読めなければ空
pub fn template_values(model: &SettingsModel<Store>, previous: &[String]) -> Vec<String> {
    let expand = |template: &str| -> Option<String> {
        model
            .store()
            .preview_macros("", "", template)
            .ok()
            .and_then(|results| results.into_iter().next())
    };
    crate::strings::extras::TEMPLATE_ROWS
        .iter()
        .enumerate()
        .map(|(index, (syntax, _))| {
            let kept = previous.get(index).filter(|value| !value.is_empty());
            match kept {
                Some(value) if CHANGING_TEMPLATES.contains(syntax) => value.clone(),
                _ => expand(syntax).unwrap_or_default(),
            }
        })
        .collect()
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
/// キー設定の表の問題の文と，行ごとの問題(行の印に使う)
pub fn keymap_report(model: &SettingsModel<Store>) -> (String, Vec<ipc::KeymapRowIssue>) {
    let Some(keymap) = model.value("keymap").cloned() else {
        return (String::new(), Vec::new());
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
        .map(|report| {
            (
                crate::keys::report_lines(&report, &entries).join("\n"),
                report.rows,
            )
        })
        .unwrap_or_default()
}

/// 今のキー設定の表と同じひな形(keys::PRESETS の番号)．どれとも違えば None(macOS の KeymapPreset.matching)
pub fn matching_preset(model: &SettingsModel<Store>) -> Option<usize> {
    let current = model.value("keymap")?;
    keys::PRESETS.iter().position(|(preset, _)| {
        model
            .store()
            .read_keymap_preset(preset)
            .ok()
            .and_then(|fields| fields.get("keymap").cloned())
            .is_some_and(|keymap| &keymap == current)
    })
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
        // macOS の PalettePage と同じく，消す前に尋ねる
        Event::Action(Action::ResetPaletteHistory) => Some((
            crate::strings::palette::CLEAR_HISTORY_QUESTION.to_string(),
            crate::strings::palette::CLEAR_HISTORY_NOTE.to_string(),
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

/// 新しいカスタムテーマの id の種(今の時刻)
pub(super) fn seed() -> u128 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_nanos())
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
        // 角を丸めないテーマ(プラチナ・デスク)は 0 にする(macOS の customTheme(from:))
        if resolved.is_rounded() {
            f64::from(resolved.corner_radius)
        } else {
            0.0
        },
    )
}

/// 一度も同期していないときの時刻(macOS の SyncPage と同じ)
const NO_TIME: &str = "—";

/// 記号の一覧の 1 行(入力・記号・状態)．状態は無効と，既定から変えた・足した印
/// 品詞の欄の値(設定のファイルに書く名前)を通信の品詞にする．知らない値なら None(エンジンが名詞にする)
fn word_class(value: &str) -> Option<WordClass> {
    serde_json::from_value(serde_json::Value::String(value.to_string())).ok()
}

/// 表に出す品詞の名前．品詞の無い語(古いエンジンが返したもの)は名詞として出す
fn word_class_label(word_class: Option<WordClass>) -> &'static str {
    let value = word_class
        .and_then(|class| serde_json::to_value(class).ok())
        .and_then(|value| value.as_str().map(str::to_string))
        .unwrap_or_default();
    options::WORD_CLASSES
        .iter()
        .find(|(raw, _)| *raw == value)
        .or(options::WORD_CLASSES.first())
        .map_or("", |(_, label)| label)
}

fn symbol_row(item: &SymbolItem) -> Vec<String> {
    let origin = match item.origin {
        SymbolOrigin::Standard => None,
        SymbolOrigin::Changed => Some(features::CHANGED),
        SymbolOrigin::Added => Some(features::ADDED),
    };
    // 入力・記号・有効の印・札(変更あり・追加)．有効は表の「有効」の列，札は記号の右に小さく出す(macOS と同じ)
    let enabled = if item.is_enabled {
        crate::pages::ENABLED_CELL
    } else {
        ""
    };
    vec![
        item.input.clone(),
        item.output.clone(),
        enabled.to_string(),
        origin.unwrap_or_default().to_string(),
    ]
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
