#![forbid(unsafe_code)]

//! 同期のページ(macOS の SyncPage)．同期の状態は設定のファイルの項目ではないので，
//! 「sync.」で始まる道筋の値にして，ほかのページと同じ部品(オン・オフ，選ぶ欄)で出す．
//! 変えたときは道筋から同期の要求を作ってエンジンに頼む

use crate::options::SYNC_SCOPES;
use crate::store::Fields;
use crate::strings::sync;
use ipc::{RequestBody, SyncProblem, SyncStatus};
use serde_json::Value;

/// 同期する(オン・オフ)
pub const ENABLED: &str = "sync.enabled";
/// 選んだフォルダの名前(選んでいなければ空)
pub const FOLDER: &str = "sync.folder";
/// 同期できなかった理由(failed・unreadable．無ければ空)
pub const PROBLEM: &str = "sync.problem";
/// まとまりの範囲の道筋の頭(「sync.scope.input」)
const SCOPE: &str = "sync.scope.";

pub const PROBLEM_FAILED: &str = "failed";
pub const PROBLEM_UNREADABLE: &str = "unreadable";

const SYNCED: &str = "synced";
const LOCAL: &str = "local";

/// まとまりの範囲の道筋
pub fn scope_path(group: &str) -> String {
    format!("{SCOPE}{group}")
}

/// 同期の状態を，画面の部品が読む値にする
pub fn values(status: &SyncStatus) -> Fields {
    let mut values = Fields::new();
    values.insert(ENABLED.into(), Value::Bool(status.is_enabled));
    values.insert(
        FOLDER.into(),
        Value::String(status.folder_name.clone().unwrap_or_default()),
    );
    let problem = match status.problem {
        None => "",
        Some(SyncProblem::Unreadable) => PROBLEM_UNREADABLE,
        Some(SyncProblem::Failed | SyncProblem::FolderUnavailable) => PROBLEM_FAILED,
    };
    values.insert(PROBLEM.into(), Value::String(problem.into()));
    for group in &status.groups {
        values.insert(scope_path(&group.group), Value::String(group.scope.clone()));
    }
    values
}

/// 部品で変えた値から同期の要求を作る．同期の道筋でなければ None
pub fn request(path: &str, value: &Value) -> Option<RequestBody> {
    if path == ENABLED {
        return Some(RequestBody::SetSyncEnabled {
            enabled: value.as_bool()?,
        });
    }
    let group = path.strip_prefix(SCOPE)?;
    let scope = value.as_str()?;
    SYNC_SCOPES
        .iter()
        .any(|(value, _)| *value == scope)
        .then(|| RequestBody::SetSyncScope {
            group: group.to_string(),
            scope: scope.to_string(),
        })
}

/// 同期の道筋か
pub fn is_sync_path(path: &str) -> bool {
    path.starts_with("sync.")
}

/// 項目ごとの同期の表の 1 行
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FieldRow {
    pub field: String,
    /// この PC だけで持つ
    pub local: bool,
}

/// 項目ごとに選べる行．同期するまとまりのうち，項目が 2 つ以上あるものの項目(macOS の「項目ごとに選択」と同じ)
pub fn field_rows(status: &SyncStatus) -> Vec<FieldRow> {
    status
        .groups
        .iter()
        .filter(|group| group.scope == SYNCED && group.fields.len() > 1)
        .flat_map(|group| group.fields.iter())
        .map(|field| FieldRow {
            field: field.clone(),
            local: status.local_fields.contains(field),
        })
        .collect()
}

/// 表の行(項目の名前・範囲の名前)
pub fn field_table(rows: &[FieldRow]) -> Vec<Vec<String>> {
    let scope_name = |value: &str| {
        SYNC_SCOPES
            .iter()
            .find(|(scope, _)| *scope == value)
            .map_or(value, |(_, name)| name)
            .to_string()
    };
    rows.iter()
        .map(|row| {
            vec![
                sync::field_label(&row.field).to_string(),
                scope_name(if row.local { LOCAL } else { SYNCED }),
            ]
        })
        .collect()
}

/// 最後に同期した時刻(ISO 8601 の UTC．「2026-10-27T01:02:03Z」)を年・月・日・時・分・秒にする
pub fn parse_time(text: &str) -> Option<[u16; 6]> {
    let text = text.strip_suffix('Z')?;
    let (date, time) = text.split_once('T')?;
    let mut parts = date
        .split('-')
        .chain(time.split(':'))
        .map(|part| part.parse::<u16>().ok());
    let mut result = [0u16; 6];
    for slot in &mut result {
        *slot = parts.next()??;
    }
    parts.next().is_none().then_some(result)
}

/// 年・月・日・時・分を出す形
pub fn format_time([year, month, day, hour, minute, _]: [u16; 6]) -> String {
    format!("{year}/{month:02}/{day:02} {hour:02}:{minute:02}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use ipc::SyncGroupState;

    fn status() -> SyncStatus {
        SyncStatus {
            is_enabled: true,
            folder_path: Some("C:\\Dropbox\\s90".into()),
            folder_name: Some("s90".into()),
            groups: vec![
                SyncGroupState {
                    group: "input".into(),
                    scope: "synced".into(),
                    fields: vec!["inputStyle".into(), "liveConversion".into()],
                },
                SyncGroupState {
                    group: "keys".into(),
                    scope: "synced".into(),
                    fields: vec!["keymap".into()],
                },
                SyncGroupState {
                    group: "appearance".into(),
                    scope: "local".into(),
                    fields: vec!["theme".into(), "candidateFontSize".into()],
                },
            ],
            local_fields: vec!["liveConversion".into()],
            last_synced_at: Some("2026-10-27T01:02:03Z".into()),
            is_syncing: false,
            problem: Some(SyncProblem::FolderUnavailable),
        }
    }

    #[test]
    fn 同期の状態を部品の値にする() {
        let values = values(&status());
        assert_eq!(values[ENABLED], Value::Bool(true));
        assert_eq!(values[FOLDER], Value::String("s90".into()));
        assert_eq!(values[PROBLEM], Value::String(PROBLEM_FAILED.into()));
        assert_eq!(
            values["sync.scope.appearance"],
            Value::String("local".into())
        );
    }

    #[test]
    fn 変えた値から同期の要求を作る() {
        assert_eq!(
            request(ENABLED, &Value::Bool(false)),
            Some(RequestBody::SetSyncEnabled { enabled: false })
        );
        assert_eq!(
            request("sync.scope.keys", &Value::String("local".into())),
            Some(RequestBody::SetSyncScope {
                group: "keys".into(),
                scope: "local".into()
            })
        );
        assert_eq!(
            request("sync.scope.keys", &Value::String("both".into())),
            None
        );
        assert_eq!(request("liveConversion", &Value::Bool(true)), None);
    }

    #[test]
    fn 項目ごとの行は同期するまとまりの項目が2つ以上のときだけ() {
        let rows = field_rows(&status());
        assert_eq!(
            rows,
            vec![
                FieldRow {
                    field: "inputStyle".into(),
                    local: false
                },
                FieldRow {
                    field: "liveConversion".into(),
                    local: true
                },
            ]
        );
        assert_eq!(
            field_table(&rows),
            vec![
                vec!["入力方式".to_string(), "同期する".to_string()],
                vec!["ライブ変換".to_string(), "この PC だけ".to_string()],
            ]
        );
    }

    #[test]
    fn 時刻を読む() {
        assert_eq!(
            parse_time("2026-10-27T01:02:03Z"),
            Some([2026, 10, 27, 1, 2, 3])
        );
        assert_eq!(parse_time("2026-10-27"), None);
        assert_eq!(format_time([2026, 1, 2, 3, 4, 5]), "2026/01/02 03:04");
    }
}
