#![forbid(unsafe_code)]

//! エンジン(s90-engine-host)への頼みを，設定の読み書きの口(SettingsStore)と操作(学習の消去・統計)にする．
//! パイプでの受け渡しは Engine の実装(app)が受け持ち，ここは要求と応答の形だけを扱う

use crate::files::FileTask;
use crate::options;
use crate::pages::DictionaryList;
use crate::store::{Fields, SettingsStore, StoreError};
use crate::usage::Usage;
use ipc::{
    ContrastIssue, DictionaryAddResult, DictionaryEntry, ErrorCode, FileFailure, KeymapReport,
    PreviewWord, RequestBody, ResponseBody, SymbolItem, SymbolKind, SymbolSaveResult, SyncStatus,
};

/// 要求を 1 つ送って応答を待つ口．応答が無い(つながらない・時間切れ)ときは None
pub trait Engine {
    fn request(&self, body: RequestBody) -> Option<ResponseBody>;

    /// ファイルの読み書きを頼む．読み終えるまで時間がかかるので，ふつうの要求より長く待つ
    fn request_file(&self, body: RequestBody) -> Option<ResponseBody> {
        self.request(body)
    }
}

/// ファイルの読み書きの結果
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileOutcome {
    Done,
    /// 読み込んで足した件数
    Imported(u32),
    Failed(FileFailure),
}

pub struct EngineStore<E: Engine> {
    engine: E,
}

impl<E: Engine> EngineStore<E> {
    pub fn new(engine: E) -> Self {
        Self { engine }
    }

    fn send(&self, body: RequestBody) -> Result<ResponseBody, StoreError> {
        match self.engine.request(body) {
            None => Err(StoreError::Unavailable),
            Some(ResponseBody::Error {
                code: ErrorCode::TooLarge,
            }) => Err(StoreError::TooLarge),
            Some(ResponseBody::Error { .. }) => Err(StoreError::Rejected),
            Some(response) => Ok(response),
        }
    }

    fn done(&self, body: RequestBody) -> Result<(), StoreError> {
        match self.send(body)? {
            ResponseBody::Done => Ok(()),
            _ => Err(StoreError::Malformed),
        }
    }

    /// ファイルを読み込む・書き出す(path は利用者が窓で選んだ場所)
    pub fn run_file(&self, task: FileTask, path: String) -> Result<FileOutcome, StoreError> {
        match self.engine.request_file(task.request(path)) {
            None => Err(StoreError::Unavailable),
            Some(ResponseBody::Done) => Ok(FileOutcome::Done),
            Some(ResponseBody::Imported { added, .. }) => Ok(FileOutcome::Imported(added)),
            Some(ResponseBody::FileFailed { reason }) => Ok(FileOutcome::Failed(reason)),
            Some(ResponseBody::Error { .. }) => Err(StoreError::Rejected),
            Some(_) => Err(StoreError::Malformed),
        }
    }

    pub fn reset_learning(&self) -> Result<(), StoreError> {
        self.done(RequestBody::ResetLearning)
    }

    pub fn reset_usage(&self) -> Result<(), StoreError> {
        self.done(RequestBody::ResetUsage)
    }

    /// 英字で打った文の語ごとに，英語のまま入るか日本語になるかを試す
    pub fn preview_language(
        &self,
        text: &str,
        preceding: &str,
    ) -> Result<Vec<PreviewWord>, StoreError> {
        match self.send(RequestBody::PreviewLanguage {
            text: text.to_string(),
            preceding_text: (!preceding.is_empty()).then(|| preceding.to_string()),
        })? {
            ResponseBody::LanguagePreview { words } => Ok(words),
            _ => Err(StoreError::Malformed),
        }
    }

    /// 登録した単語をすべて読む．1 回に返す数はエンジンが決めるので，返らなかった分を続けて頼む
    pub fn read_user_dictionary(&self) -> Result<Vec<DictionaryEntry>, StoreError> {
        let mut entries = Vec::new();
        loop {
            let offset = u32::try_from(entries.len()).map_err(|_| StoreError::TooLarge)?;
            match self.send(RequestBody::ReadUserDictionary {
                offset,
                limit: u32::MAX,
            })? {
                ResponseBody::UserDictionary {
                    entries: page,
                    total,
                } => {
                    let done = page.is_empty();
                    entries.extend(page);
                    if done || entries.len() >= total as usize {
                        return Ok(entries);
                    }
                }
                _ => return Err(StoreError::Malformed),
            }
        }
    }

    pub fn add_user_dictionary_entry(
        &self,
        entry: DictionaryEntry,
    ) -> Result<DictionaryAddResult, StoreError> {
        match self.send(RequestBody::AddUserDictionaryEntry { entry })? {
            ResponseBody::DictionaryAdded { result } => Ok(result),
            _ => Err(StoreError::Malformed),
        }
    }

    pub fn remove_user_dictionary_entry(&self, entry: DictionaryEntry) -> Result<(), StoreError> {
        self.done(RequestBody::RemoveUserDictionaryEntry { entry })
    }

    /// 辞書のファイルを取り込む(replacing を渡すとその辞書を取り込み直す)．取り込んだ件数か失敗の理由を返す
    pub fn import_dictionary(
        &self,
        list: DictionaryList,
        path: String,
        replacing: Option<String>,
    ) -> Result<FileOutcome, StoreError> {
        let body = match list {
            DictionaryList::Imported => RequestBody::ImportDictionary { path, replacing },
            DictionaryList::Association => {
                RequestBody::ImportAssociationDictionary { path, replacing }
            }
        };
        match self.engine.request_file(body) {
            None => Err(StoreError::Unavailable),
            Some(ResponseBody::DictionaryImported { dictionary }) => {
                Ok(FileOutcome::Imported(dictionary.word_count))
            }
            Some(ResponseBody::AssociationImported { dictionary }) => {
                Ok(FileOutcome::Imported(dictionary.group_count))
            }
            Some(ResponseBody::FileFailed { reason }) => Ok(FileOutcome::Failed(reason)),
            Some(ResponseBody::Error { .. }) => Err(StoreError::Rejected),
            Some(_) => Err(StoreError::Malformed),
        }
    }

    /// 辞書を一覧と索引から消す
    pub fn remove_dictionary(
        &self,
        list: DictionaryList,
        id: String,
    ) -> Result<FileOutcome, StoreError> {
        let body = match list {
            DictionaryList::Imported => RequestBody::RemoveDictionary { id },
            DictionaryList::Association => RequestBody::RemoveAssociationDictionary { id },
        };
        match self.engine.request_file(body) {
            None => Err(StoreError::Unavailable),
            Some(ResponseBody::Done) => Ok(FileOutcome::Done),
            Some(ResponseBody::FileFailed { reason }) => Ok(FileOutcome::Failed(reason)),
            Some(ResponseBody::Error { .. }) => Err(StoreError::Rejected),
            Some(_) => Err(StoreError::Malformed),
        }
    }

    /// カスタムテーマ(設定のファイルと同じ形)の読みにくい組み合わせ
    pub fn check_custom_theme(
        &self,
        theme: &serde_json::Value,
    ) -> Result<Vec<ContrastIssue>, StoreError> {
        let theme = serde_json::to_string(theme).map_err(|_| StoreError::Malformed)?;
        match self.send(RequestBody::CheckCustomTheme { theme })? {
            ResponseBody::ThemeReport { issues } => Ok(issues),
            _ => Err(StoreError::Malformed),
        }
    }

    /// 同期の状態を読む
    pub fn read_sync(&self) -> Result<SyncStatus, StoreError> {
        self.sync(RequestBody::ReadSync)
    }

    /// 同期の設定を変える・今すぐ同期する(setSync…・syncNow)．変えたあとの状態を返す
    pub fn sync(&self, body: RequestBody) -> Result<SyncStatus, StoreError> {
        match self.send(body)? {
            ResponseBody::SyncStatus { status } => Ok(status),
            _ => Err(StoreError::Malformed),
        }
    }

    /// 記号の一覧(既定の決まりに利用者の決まりを重ねたもの)
    pub fn read_symbol_items(&self, kind: SymbolKind) -> Result<Vec<SymbolItem>, StoreError> {
        match self.send(RequestBody::ReadSymbolItems { kind })? {
            ResponseBody::SymbolItems { items } => Ok(items),
            _ => Err(StoreError::Malformed),
        }
    }

    /// 記号の決まりを重ねる(既定の決まりを変える・足す・有効にする・無効にする)
    pub fn save_symbol_rule(
        &self,
        kind: SymbolKind,
        input: String,
        output: String,
        is_enabled: bool,
        replacing: Option<String>,
    ) -> Result<SymbolSaveResult, StoreError> {
        match self.send(RequestBody::SaveSymbolRule {
            kind,
            input,
            output,
            is_enabled,
            replacing,
        })? {
            ResponseBody::SymbolSaved { result } => Ok(result),
            _ => Err(StoreError::Malformed),
        }
    }

    /// 重ねた記号の決まりを外す(既定の決まりは既定に戻り，足した決まりは消える)
    pub fn remove_symbol_rules(
        &self,
        kind: SymbolKind,
        inputs: Vec<String>,
    ) -> Result<(), StoreError> {
        self.done(RequestBody::RemoveSymbolRules { kind, inputs })
    }

    /// キー設定のひな形を，keymap の項目として読む
    pub fn read_keymap_preset(&self, preset: &str) -> Result<Fields, StoreError> {
        match self.send(RequestBody::ReadKeymapPreset {
            preset: preset.to_string(),
        })? {
            ResponseBody::SettingsFields { values } => parse(&values),
            _ => Err(StoreError::Malformed),
        }
    }

    /// keymap の項目の表の問題を調べる
    pub fn check_keymap(&self, values: &Fields) -> Result<KeymapReport, StoreError> {
        let values = serde_json::to_string(values).map_err(|_| StoreError::Malformed)?;
        match self.send(RequestBody::CheckKeymap { values })? {
            ResponseBody::KeymapReport { report } => Ok(report),
            _ => Err(StoreError::Malformed),
        }
    }

    pub fn read_usage(&self) -> Result<Usage, StoreError> {
        match self.send(RequestBody::ReadUsage)? {
            ResponseBody::Usage {
                values,
                first_candidate_rate,
            } => Ok(Usage {
                counts: parse(&values)?,
                first_candidate_rate,
            }),
            _ => Err(StoreError::Malformed),
        }
    }
}

impl<E: Engine> SettingsStore for EngineStore<E> {
    fn read(&self, names: &[String], defaults: bool) -> Result<Fields, StoreError> {
        match self.send(RequestBody::ReadSettingsFields {
            names: names.to_vec(),
            defaults,
        })? {
            ResponseBody::SettingsFields { values } => parse(&values),
            _ => Err(StoreError::Malformed),
        }
    }

    fn write(&self, values: &Fields) -> Result<Fields, StoreError> {
        let values = serde_json::to_string(values).map_err(|_| StoreError::Malformed)?;
        match self.send(RequestBody::WriteSettingsFields { values })? {
            ResponseBody::SettingsFields { values } => parse(&values),
            _ => Err(StoreError::Malformed),
        }
    }
}

/// 試した結果を 1 行の文にする(「make → make(英語)」を全角の空白で区切る)
pub fn preview_text(words: &[PreviewWord]) -> String {
    words
        .iter()
        .map(|word| {
            let language = options::WORD_LANGUAGES
                .iter()
                .find(|(value, _)| *value == word.language)
                .map_or(word.language.as_str(), |(_, label)| label);
            format!("{} → {}({language})", word.typed, word.shown)
        })
        .collect::<Vec<_>>()
        .join("\u{3000}")
}

fn parse(values: &str) -> Result<Fields, StoreError> {
    serde_json::from_str(values).map_err(|_| StoreError::Malformed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    /// 決めた応答を返し，受けた要求を覚える
    struct Scripted {
        response: Option<ResponseBody>,
        requests: RefCell<Vec<RequestBody>>,
    }

    impl Engine for &Scripted {
        fn request(&self, body: RequestBody) -> Option<ResponseBody> {
            self.requests.borrow_mut().push(body);
            self.response.clone()
        }
    }

    fn scripted(response: Option<ResponseBody>) -> Scripted {
        Scripted {
            response,
            requests: RefCell::new(Vec::new()),
        }
    }

    #[test]
    fn 項目を名前で読む() {
        let engine = scripted(Some(ResponseBody::SettingsFields {
            values: r#"{"liveConversion":true}"#.to_string(),
        }));
        let store = EngineStore::new(&engine);
        let fields = store.read(&["liveConversion".to_string()], true).unwrap();
        assert_eq!(fields["liveConversion"], serde_json::json!(true));
        assert_eq!(
            engine.requests.borrow()[0],
            RequestBody::ReadSettingsFields {
                names: vec!["liveConversion".to_string()],
                defaults: true
            }
        );
    }

    #[test]
    fn 大きすぎる応答は分けて読み直せるように知らせる() {
        let engine = scripted(Some(ResponseBody::Error {
            code: ErrorCode::TooLarge,
        }));
        let store = EngineStore::new(&engine);
        assert_eq!(store.read(&[], false), Err(StoreError::TooLarge));
    }

    #[test]
    fn 応答が無ければつながらない() {
        let engine = scripted(None);
        assert_eq!(
            EngineStore::new(&engine).reset_learning(),
            Err(StoreError::Unavailable)
        );
    }

    #[test]
    fn ファイルの読み込みの結果を件数か失敗の理由にする() {
        let task = FileTask::ImportRuleList(ipc::RuleList::Romaji);
        let engine = scripted(Some(ResponseBody::Imported {
            added: 3,
            skipped: 1,
        }));
        let store = EngineStore::new(&engine);
        assert_eq!(
            store.run_file(task, "C:\\r.tsv".into()),
            Ok(FileOutcome::Imported(3))
        );
        assert_eq!(
            engine.requests.borrow()[0],
            task.request("C:\\r.tsv".into())
        );
        let engine = scripted(Some(ResponseBody::FileFailed {
            reason: FileFailure::TooLarge,
        }));
        assert_eq!(
            EngineStore::new(&engine).run_file(task, String::new()),
            Ok(FileOutcome::Failed(FileFailure::TooLarge))
        );
        let engine = scripted(None);
        assert_eq!(
            EngineStore::new(&engine).run_file(FileTask::ExportSettings, String::new()),
            Err(StoreError::Unavailable)
        );
    }

    #[test]
    fn 記号の決まりを書き換える要求と結果() {
        let engine = scripted(Some(ResponseBody::SymbolSaved {
            result: SymbolSaveResult::Full,
        }));
        let store = EngineStore::new(&engine);
        assert_eq!(
            store.save_symbol_rule(SymbolKind::Sequence, "->".into(), "⇒".into(), false, None),
            Ok(SymbolSaveResult::Full)
        );
        assert_eq!(
            engine.requests.borrow()[0],
            RequestBody::SaveSymbolRule {
                kind: SymbolKind::Sequence,
                input: "->".into(),
                output: "⇒".into(),
                is_enabled: false,
                replacing: None
            }
        );
        let engine = scripted(Some(ResponseBody::Done));
        assert_eq!(
            EngineStore::new(&engine).read_symbol_items(SymbolKind::Reading),
            Err(StoreError::Malformed)
        );
    }

    #[test]
    fn 辞書の取り込みと削除は一覧ごとの要求にする() {
        let engine = scripted(Some(ResponseBody::AssociationImported {
            dictionary: ipc::AssociationDictionaryInfo {
                id: "a".into(),
                name: "類語".into(),
                group_count: 7,
            },
        }));
        let store = EngineStore::new(&engine);
        assert_eq!(
            store.import_dictionary(DictionaryList::Association, "C:\\a.txt".into(), None),
            Ok(FileOutcome::Imported(7))
        );
        assert_eq!(
            engine.requests.borrow()[0],
            RequestBody::ImportAssociationDictionary {
                path: "C:\\a.txt".into(),
                replacing: None
            }
        );
        let engine = scripted(Some(ResponseBody::Done));
        assert_eq!(
            EngineStore::new(&engine).remove_dictionary(DictionaryList::Imported, "x".into()),
            Ok(FileOutcome::Done)
        );
        assert_eq!(
            engine.requests.borrow()[0],
            RequestBody::RemoveDictionary { id: "x".into() }
        );
    }

    #[test]
    fn 統計を読む() {
        let engine = scripted(Some(ResponseBody::Usage {
            values: r#"{"commits":4}"#.to_string(),
            first_candidate_rate: Some(0.5),
        }));
        let usage = EngineStore::new(&engine).read_usage().unwrap();
        assert_eq!(usage.text(crate::pages::Stat::Commits), "4");
        assert_eq!(usage.first_candidate_rate, Some(0.5));
    }

    #[test]
    fn 試した結果を文にする() {
        let words = vec![
            PreviewWord {
                typed: "make".into(),
                shown: "make".into(),
                language: "english".into(),
            },
            PreviewWord {
                typed: "sushi".into(),
                shown: "すし".into(),
                language: "japanese".into(),
            },
        ];
        assert_eq!(
            preview_text(&words),
            "make → make(英語)\u{3000}sushi → すし(日本語)"
        );
    }

    #[test]
    fn 前の文字列が空なら送らない() {
        let engine = scripted(Some(ResponseBody::LanguagePreview { words: Vec::new() }));
        EngineStore::new(&engine)
            .preview_language("make", "")
            .unwrap();
        assert_eq!(
            engine.requests.borrow()[0],
            RequestBody::PreviewLanguage {
                text: "make".into(),
                preceding_text: None
            }
        );
    }

    /// 登録した単語を total 個持ち，頼まれた範囲を返す
    struct Dictionary {
        total: usize,
    }

    impl Engine for Dictionary {
        fn request(&self, body: RequestBody) -> Option<ResponseBody> {
            let RequestBody::ReadUserDictionary { offset, limit } = body else {
                return None;
            };
            let start = (offset as usize).min(self.total);
            let end = (start + limit as usize).min(self.total);
            Some(ResponseBody::UserDictionary {
                entries: (start..end)
                    .map(|index| DictionaryEntry {
                        reading: format!("よみ{index}"),
                        word: format!("語{index}"),
                    })
                    .collect(),
                total: self.total as u32,
            })
        }
    }

    #[test]
    fn 登録した単語を分けてすべて読む() {
        let store = EngineStore::new(Dictionary { total: 1203 });
        let entries = store.read_user_dictionary().unwrap();
        assert_eq!(entries.len(), 1203);
        assert_eq!(entries[1202].word, "語1202");
        assert!(EngineStore::new(Dictionary { total: 0 })
            .read_user_dictionary()
            .unwrap()
            .is_empty());
    }

    #[test]
    fn 違う応答は読めない() {
        let engine = scripted(Some(ResponseBody::Done));
        assert_eq!(
            EngineStore::new(&engine).read_usage(),
            Err(StoreError::Malformed)
        );
    }
}
