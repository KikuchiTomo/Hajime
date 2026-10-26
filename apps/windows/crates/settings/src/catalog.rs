#![forbid(unsafe_code)]

//! 設定の項目の名前と，値の範囲・上限．core の DefaultSettings から作った写し(protocol/settings-catalog.json)を読む．
//! 既定値は写さず，エンジンに頼んで読む

use serde::Deserialize;

const SOURCE: &str = include_str!("../../../../../protocol/settings-catalog.json");

/// 値を選べる範囲(下限と上限)
#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
pub struct Range(pub f64, pub f64);

impl Range {
    pub fn lower(&self) -> f64 {
        self.0
    }

    pub fn upper(&self) -> f64 {
        self.1
    }

    pub fn clamp(&self, value: f64) -> f64 {
        value.clamp(self.0, self.1)
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Ranges {
    pub candidates_per_page: Range,
    pub live_conversion_delay: Range,
    pub correction_delay: Range,
    pub mode_indicator_duration: Range,
    pub candidate_font_size: Range,
    pub custom_theme_corner_radius: Range,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Limits {
    pub settings_file_bytes: u64,
    pub usage_file_bytes: u64,
    pub rule_list_file_bytes: u64,
    pub user_dictionary_file_bytes: u64,
    pub profile_rule_file_bytes: u64,
    pub romaji_keys_length: usize,
    pub romaji_kana_length: usize,
    pub romaji_rules: usize,
    pub symbol_rules: usize,
    pub correction_rules: usize,
    pub exception_length: usize,
    pub word_language_entries: usize,
    pub word_language_word_length: usize,
    pub user_dictionary_entries: usize,
    pub user_dictionary_reading_length: usize,
    pub user_dictionary_word_length: usize,
    pub profile_rules: usize,
    pub application_identifier_length: usize,
    pub custom_themes: usize,
    pub theme_name_length: usize,
    pub imported_dictionaries: usize,
    pub keymap_entries: usize,
}

/// 設定の画面がエンジンを待つ時間(秒)
#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Timing {
    /// 応答を待つ時間
    pub response_timeout: f64,
    /// つながらないときにつなぎ直す間隔
    pub reconnect_interval: f64,
}

impl Timing {
    pub fn response_timeout(&self) -> std::time::Duration {
        std::time::Duration::from_secs_f64(self.response_timeout.max(0.0))
    }

    pub fn reconnect_interval(&self) -> std::time::Duration {
        std::time::Duration::from_secs_f64(self.reconnect_interval.max(0.0))
    }
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Catalog {
    /// 設定のファイルの項目の名前(Settings の CodingKeys)
    pub fields: Vec<String>,
    pub ranges: Ranges,
    /// 秒の項目を選ぶ刻み(DefaultSettings.secondsStep)
    pub seconds_step: f64,
    pub limits: Limits,
    pub timing: Timing,
}

impl Catalog {
    pub fn load() -> Result<Self, serde_json::Error> {
        serde_json::from_str(SOURCE)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 写しを読める() {
        let catalog = Catalog::load().unwrap();
        assert!(catalog.fields.iter().any(|name| name == "liveConversion"));
        assert!(
            catalog.ranges.candidates_per_page.lower() < catalog.ranges.candidates_per_page.upper()
        );
        assert!(catalog.limits.custom_themes > 0);
        assert!(catalog.timing.response_timeout().as_secs_f64() > 0.0);
    }

    #[test]
    fn 範囲に収める() {
        let range = Range(0.1, 1.5);
        assert_eq!(range.clamp(3.0), 1.5);
        assert_eq!(range.clamp(-1.0), 0.1);
    }
}
