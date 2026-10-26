#![forbid(unsafe_code)]

//! 使い方の記録(エンジンの UsageCounts)を画面に出す文字にする

use crate::pages::Stat;
use serde_json::{Map, Value};

/// エンジンから読んだ回数(UsageCounts の JSON)と，選び直さずに確定した割合
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Usage {
    pub counts: Map<String, Value>,
    pub first_candidate_rate: Option<f64>,
}

impl Usage {
    fn count(&self, name: &str) -> u64 {
        self.counts.get(name).and_then(Value::as_u64).unwrap_or(0)
    }

    /// 画面に出す値．macOS の UsageTab と同じ書き方
    pub fn text(&self, stat: Stat) -> String {
        match stat {
            Stat::FirstCandidateRate => self.first_candidate_rate.map_or_else(
                || "-".to_string(),
                |rate| format!("{}%", (rate * 100.0).round() as i64),
            ),
            Stat::Commits => self.count("commits").to_string(),
            Stat::ConversionsOpened => self.count("conversionsOpened").to_string(),
            Stat::SegmentsChanged => self.count("segmentsChanged").to_string(),
            Stat::ReadingCorrections => format!(
                "{} / {}",
                self.count("readingCorrections"),
                self.count("readingCorrectionsUndone")
            ),
            Stat::EnglishCorrections => format!(
                "{} / {}",
                self.count("englishCorrections"),
                self.count("englishCorrectionsUndone")
            ),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn 回数と割合を書く() {
        let usage = Usage {
            counts: json!({"commits": 12, "readingCorrections": 3, "readingCorrectionsUndone": 1})
                .as_object()
                .unwrap()
                .clone(),
            first_candidate_rate: Some(0.756),
        };
        assert_eq!(usage.text(Stat::FirstCandidateRate), "76%");
        assert_eq!(usage.text(Stat::Commits), "12");
        assert_eq!(usage.text(Stat::ReadingCorrections), "3 / 1");
        assert_eq!(usage.text(Stat::EnglishCorrections), "0 / 0");
    }

    #[test]
    fn 確定していなければ割合を出さない() {
        assert_eq!(Usage::default().text(Stat::FirstCandidateRate), "-");
    }
}
