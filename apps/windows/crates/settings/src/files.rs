#![forbid(unsafe_code)]

//! ファイルの読み込みと書き出し(macOS の SettingsWindowController の importRuleList などと同じ操作)．
//! 画面はファイルを選ぶだけで，読み書きはエンジンが行う(設定の形と上限をエンジンだけが知るため)

use crate::catalog::Catalog;
use crate::strings::{more, settings, windows};
use ipc::{RequestBody, RuleList};

/// ファイルとやり取りする操作
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileTask {
    ImportSettings,
    ExportSettings,
    ImportUserDictionary,
    ExportUserDictionary,
    ImportProfileRules,
    ExportProfileRules,
    ImportRuleList(RuleList),
    ExportRuleList(RuleList),
}

/// ファイルを選ぶ窓に出す種類(名前と，「;」で区切った拡張子の型)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FileFilter {
    pub name: &'static str,
    pub pattern: &'static str,
}

const JSON: FileFilter = FileFilter {
    name: windows::JSON_FILES,
    pattern: "*.json",
};
const TEXT: FileFilter = FileFilter {
    name: windows::TEXT_FILES,
    pattern: "*.txt;*.tsv;*.csv",
};
const CSV: FileFilter = FileFilter {
    name: windows::CSV_FILES,
    pattern: "*.csv;*.txt",
};

impl FileTask {
    /// 読み込む(開く窓)なら true，書き出す(保存の窓)なら false
    pub fn is_import(self) -> bool {
        matches!(
            self,
            FileTask::ImportSettings
                | FileTask::ImportUserDictionary
                | FileTask::ImportProfileRules
                | FileTask::ImportRuleList(_)
        )
    }

    pub fn filter(self) -> FileFilter {
        match self {
            FileTask::ImportSettings | FileTask::ExportSettings => JSON,
            FileTask::ImportProfileRules | FileTask::ExportProfileRules => CSV,
            _ => TEXT,
        }
    }

    /// 書き出すときの既定のファイルの名前(読み込みでは空)
    pub fn default_name(self, catalog: &Catalog) -> String {
        match self {
            FileTask::ExportSettings => more::EXPORT_SETTINGS_FILE_NAME.to_string(),
            FileTask::ExportUserDictionary => settings::EXPORT_FILE_NAME.to_string(),
            FileTask::ExportProfileRules => more::EXPORT_CSV_FILE_NAME.to_string(),
            FileTask::ExportRuleList(list) => catalog.export_file_name(list).unwrap_or_default(),
            _ => String::new(),
        }
    }

    /// エンジンに頼む要求
    pub fn request(self, path: String) -> RequestBody {
        match self {
            FileTask::ImportSettings => RequestBody::ImportSettings { path },
            FileTask::ExportSettings => RequestBody::ExportSettings { path },
            FileTask::ImportUserDictionary => RequestBody::ImportUserDictionary { path },
            FileTask::ExportUserDictionary => RequestBody::ExportUserDictionary { path },
            FileTask::ImportProfileRules => RequestBody::ImportProfileRules { path },
            FileTask::ExportProfileRules => RequestBody::ExportProfileRules { path },
            FileTask::ImportRuleList(list) => RequestBody::ImportRuleList { list, path },
            FileTask::ExportRuleList(list) => RequestBody::ExportRuleList { list, path },
        }
    }

    /// 読み込めた件数の知らせ
    pub fn imported(self, added: u32) -> String {
        match self {
            FileTask::ImportUserDictionary => settings::imported(added),
            _ => more::imported_rules(added),
        }
    }

    /// 終わったときの知らせ(件数の無いもの)．無ければ知らせない
    pub fn done(self) -> Option<&'static str> {
        match self {
            FileTask::ImportSettings => Some(more::SETTINGS_IMPORTED),
            _ => None,
        }
    }

    /// できなかったときの知らせ
    pub fn failed(self) -> &'static str {
        match self {
            FileTask::ImportSettings => more::SETTINGS_IMPORT_FAILED,
            FileTask::ExportSettings => more::SETTINGS_EXPORT_FAILED,
            FileTask::ImportProfileRules => more::CSV_FAILED,
            task if task.is_import() => settings::IMPORT_FAILED,
            _ => settings::EXPORT_FAILED,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 読み込みと書き出しを見分けて要求にする() {
        let task = FileTask::ImportRuleList(RuleList::Romaji);
        assert!(task.is_import());
        assert!(!FileTask::ExportSettings.is_import());
        assert_eq!(
            task.request("C:\\a.tsv".into()),
            RequestBody::ImportRuleList {
                list: RuleList::Romaji,
                path: "C:\\a.tsv".into()
            }
        );
    }

    #[test]
    fn 書き出しの既定の名前は目録と文言から決める() {
        let catalog = Catalog::load().unwrap();
        assert_eq!(
            FileTask::ExportRuleList(RuleList::Romaji).default_name(&catalog),
            "romaji.tsv"
        );
        assert_eq!(
            FileTask::ExportSettings.default_name(&catalog),
            more::EXPORT_SETTINGS_FILE_NAME
        );
        assert!(FileTask::ImportSettings.default_name(&catalog).is_empty());
    }

    #[test]
    fn 失敗の知らせを操作ごとに選ぶ() {
        assert_eq!(
            FileTask::ImportSettings.failed(),
            more::SETTINGS_IMPORT_FAILED
        );
        assert_eq!(
            FileTask::ExportUserDictionary.failed(),
            settings::EXPORT_FAILED
        );
        assert_eq!(
            FileTask::ImportRuleList(RuleList::Exceptions).failed(),
            settings::IMPORT_FAILED
        );
        assert_eq!(
            FileTask::ImportUserDictionary.imported(3),
            "3 語を追加しました"
        );
        assert_eq!(
            FileTask::ImportProfileRules.imported(2),
            "2 件を追加しました"
        );
    }
}
