#![forbid(unsafe_code)]

//! 初期設定ウィザードのページと選ぶ値．OS に依らない(窓は app::wizard，実演の台本は demo)．
//! 値はエンジンの設定の項目に書く．キー設定の表と補正の強さは，1 つの選択を複数の値に写す

use crate::options::{self, Choice};
use crate::strings::wizard as text;
use serde_json::{json, Value};

/// ウィザードのページ(並んでいる順)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Step {
    Welcome,
    Switch,
    Characters,
    LiveConversion,
    Window,
    Focus,
    Correction,
    Features,
    Appearance,
    Done,
}

impl Step {
    pub const ALL: [Step; 10] = [
        Step::Welcome,
        Step::Switch,
        Step::Characters,
        Step::LiveConversion,
        Step::Window,
        Step::Focus,
        Step::Correction,
        Step::Features,
        Step::Appearance,
        Step::Done,
    ];

    pub fn index(self) -> usize {
        Self::ALL.iter().position(|step| *step == self).unwrap_or(0)
    }

    pub fn next(self) -> Option<Step> {
        Self::ALL.get(self.index() + 1).copied()
    }

    pub fn previous(self) -> Option<Step> {
        self.index().checked_sub(1).map(|index| Self::ALL[index])
    }

    pub fn title(self) -> &'static str {
        match self {
            Step::Welcome => text::WELCOME_TITLE,
            Step::Switch => text::SWITCH_TITLE,
            Step::Characters => text::CHARACTERS_TITLE,
            Step::LiveConversion => text::LIVE_TITLE,
            Step::Window => text::WINDOW_STEP_TITLE,
            Step::Focus => text::FOCUS_TITLE,
            Step::Correction => text::CORRECTION_TITLE,
            Step::Features => text::FEATURES_TITLE,
            Step::Appearance => text::APPEARANCE_TITLE,
            Step::Done => text::DONE_TITLE,
        }
    }

    pub fn description(self) -> &'static str {
        match self {
            Step::Welcome => text::WELCOME_TEXT,
            Step::Switch => text::SWITCH_TEXT,
            Step::Characters => text::CHARACTERS_TEXT,
            Step::LiveConversion => text::LIVE_TEXT,
            Step::Window => text::WINDOW_TEXT,
            Step::Focus => text::FOCUS_TEXT,
            Step::Correction => text::CORRECTION_TEXT,
            Step::Features => text::FEATURES_TEXT,
            Step::Appearance => text::APPEARANCE_TEXT,
            Step::Done => text::DONE_TEXT,
        }
    }

    /// 選ぶもの(上から順)
    pub fn groups(self) -> Vec<Group> {
        match self {
            Step::Welcome | Step::Done => vec![],
            Step::Switch => vec![Group::radio(None, Field::Switch, SWITCH)],
            Step::Characters => vec![
                Group::radio(
                    Some(text::INPUT_STYLE),
                    Field::Path("inputStyle"),
                    &options::INPUT_STYLES[..2],
                ),
                Group::radio(
                    Some(text::PUNCTUATION),
                    Field::Path("punctuation"),
                    options::PUNCTUATION,
                ),
            ],
            Step::LiveConversion => vec![
                Group::toggle(text::LIVE_CONVERSION, "liveConversion"),
                Group::radio(
                    Some(text::LIVE_DELAY),
                    Field::Path("liveConversionDelay"),
                    LIVE_DELAYS,
                ),
            ],
            Step::Window => vec![Group::radio(
                None,
                Field::Path("candidatePresentation"),
                options::PRESENTATIONS,
            )],
            Step::Focus => vec![Group::radio(
                None,
                Field::Path("initialFocus"),
                options::INITIAL_FOCUS,
            )],
            Step::Correction => vec![
                Group::radio(None, Field::Correction, CORRECTION),
                Group::toggle(
                    crate::strings::more::REMEMBERS_REJECTED_CORRECTIONS,
                    "remembersRejectedCorrections",
                ),
            ],
            Step::Features => FEATURES
                .iter()
                .map(|(path, title)| Group::toggle(title, path))
                .collect(),
            Step::Appearance => vec![Group::radio(None, Field::Path("theme"), options::THEMES)],
        }
    }
}

/// 選んだ値を書く先
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Field {
    /// 設定の 1 つの項目
    Path(&'static str),
    /// 英語と日本語の切り替え方(キー設定の表の行)
    Switch,
    /// 打ち間違いの補正の強さ(typoCorrection と correctionSensitivity)
    Correction,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GroupKind {
    /// 1 つを選ぶ
    Radio(&'static [Choice]),
    /// オン・オフ
    Toggle,
}

/// 選ぶもののまとまり
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Group {
    pub title: Option<&'static str>,
    pub field: Field,
    pub kind: GroupKind,
}

impl Group {
    fn radio(title: Option<&'static str>, field: Field, choices: &'static [Choice]) -> Self {
        Self {
            title,
            field,
            kind: GroupKind::Radio(choices),
        }
    }

    fn toggle(title: &'static str, path: &'static str) -> Self {
        Self {
            title: Some(title),
            field: Field::Path(path),
            kind: GroupKind::Toggle,
        }
    }
}

/// 切り替えのキー(値はウィザードだけのもの．キー設定の表の行に写す)
pub const SWITCH_TOGGLE: &str = "toggle";
pub const SWITCH_HENKAN: &str = "henkan";
const SWITCH: &[Choice] = &[
    (SWITCH_TOGGLE, text::SWITCH_TOGGLE),
    (SWITCH_HENKAN, text::SWITCH_HENKAN),
];

/// 変換・無変換で切り替えるときに足す行(状態を書いた行は いつでも の行に勝つ)
const HENKAN_ROWS: [(&str, &str, &str); 2] = [
    ("idle", "Muhenkan", "directMode"),
    ("direct", "Henkan", "japaneseMode"),
];

/// ライブ変換で漢字にするまでの時間(秒)の選択肢
const LIVE_DELAYS: &[Choice] = &[
    ("0.3", text::DELAY_SHORT),
    ("0.5", text::DELAY_STANDARD),
    ("0.8", text::DELAY_LONG),
    ("1.2", text::DELAY_LONGER),
];

/// 補正の強さ．typoCorrection と correctionSensitivity の組
const CORRECTION: &[Choice] = &[
    ("off", text::CORRECTION_OFF),
    ("conservative", text::CORRECTION_ENGLISH),
    ("cautious", text::CORRECTION_CAUTIOUS),
    ("standard", text::CORRECTION_STANDARD),
    ("aggressive", text::CORRECTION_AGGRESSIVE),
];

/// 紹介する便利な機能(項目と名前)
pub const FEATURES: &[(&str, &str)] = &[
    ("association", text::ASSOCIATION),
    ("calculation", text::CALCULATION),
    ("postalCodeConversion", text::POSTAL_CODE),
    ("dateConversion", text::DATE),
];

/// 推奨する値(利用者が決めたもの)
pub fn recommended(field: Field) -> Option<&'static str> {
    match field {
        Field::Path("candidatePresentation") => Some("automatic"),
        Field::Path("initialFocus") => Some("start"),
        Field::Path("liveConversionDelay") => Some("0.5"),
        _ => None,
    }
}

/// 選択肢の説明(無ければ None)
pub fn choice_note(field: Field, value: &str) -> Option<&'static str> {
    match (field, value) {
        (Field::Switch, SWITCH_TOGGLE) => Some(text::SWITCH_TOGGLE_NOTE),
        (Field::Switch, SWITCH_HENKAN) => Some(text::SWITCH_HENKAN_NOTE),
        (Field::Path("candidatePresentation"), "automatic") => Some(text::BRANCH_NOTE),
        (Field::Path("candidatePresentation"), "list") => Some(text::LIST_NOTE),
        (Field::Path("initialFocus"), "start") => Some(text::FOCUS_START_NOTE),
        (Field::Path("initialFocus"), "end") => Some(text::FOCUS_END_NOTE),
        (Field::Path("initialFocus"), "automatic") => Some(text::FOCUS_AUTOMATIC_NOTE),
        (Field::Correction, "off") => Some(text::CORRECTION_OFF_NOTE),
        (Field::Correction, "conservative") => Some(text::CORRECTION_ENGLISH_NOTE),
        (Field::Correction, "standard") => Some(text::CORRECTION_JAPANESE_NOTE),
        _ => None,
    }
}

/// 選んでいる値．エンジンから読んだ値から作り，選ぶたびに変える
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Choices {
    values: Vec<(Field, String)>,
    toggles: Vec<(&'static str, bool)>,
}

/// 設定の値を読む口(SettingsModel を渡す．テストでは表を渡す)
pub trait Read {
    fn value(&self, path: &str) -> Option<&Value>;
    /// 既定の値のままか
    fn is_default(&self, path: &str) -> bool;
}

impl Choices {
    /// 今の設定から作る．推奨のある項目は，既定のままなら推奨の値にする
    pub fn load(read: &dyn Read) -> Self {
        let mut choices = Self::default();
        for step in Step::ALL {
            for group in step.groups() {
                match (group.field, group.kind) {
                    (Field::Path(path), GroupKind::Toggle) => {
                        let on = read.value(path).and_then(Value::as_bool).unwrap_or(false);
                        choices.toggles.push((path, on));
                    }
                    (field, GroupKind::Radio(list)) => {
                        let current = current_value(read, field);
                        let value = match (field, recommended(field)) {
                            (Field::Path(path), Some(value)) if read.is_default(path) => {
                                value.to_string()
                            }
                            _ => current,
                        };
                        let value = nearest(list, field, &value);
                        choices.values.push((field, value));
                    }
                    (_, GroupKind::Toggle) => {}
                }
            }
        }
        choices
    }

    pub fn value(&self, field: Field) -> &str {
        self.values
            .iter()
            .find(|(candidate, _)| *candidate == field)
            .map_or("", |(_, value)| value.as_str())
    }

    pub fn is_on(&self, path: &str) -> bool {
        self.toggles
            .iter()
            .any(|(candidate, on)| *candidate == path && *on)
    }

    pub fn select(&mut self, field: Field, value: &str) {
        match self
            .values
            .iter_mut()
            .find(|(candidate, _)| *candidate == field)
        {
            Some((_, current)) => *current = value.to_string(),
            None => self.values.push((field, value.to_string())),
        }
    }

    pub fn set_toggle(&mut self, path: &'static str, on: bool) {
        match self
            .toggles
            .iter_mut()
            .find(|(candidate, _)| *candidate == path)
        {
            Some((_, current)) => *current = on,
            None => self.toggles.push((path, on)),
        }
    }

    /// step で選ぶ値を設定の値にする．今の値と同じものは含めない
    pub fn changes(&self, step: Step, read: &dyn Read) -> Vec<(&'static str, Value)> {
        let mut changes = Vec::new();
        for group in step.groups() {
            match (group.field, group.kind) {
                (Field::Path(path), GroupKind::Toggle) => {
                    changes.push((path, Value::Bool(self.is_on(path))));
                }
                (Field::Path(path), GroupKind::Radio(_)) => {
                    let value = self.value(group.field);
                    let value = match path {
                        "liveConversionDelay" => value
                            .parse::<f64>()
                            .ok()
                            .map_or(Value::Null, crate::model::number),
                        _ => Value::String(value.to_string()),
                    };
                    if !value.is_null() {
                        changes.push((path, value));
                    }
                    // 既成のテーマを選んだらカスタムテーマを外す(設定の画面の外観のページと同じ)
                    if path == "theme" {
                        changes.push((crate::themes::ACTIVE, Value::Null));
                    }
                }
                (Field::Switch, _) => {
                    let keymap = with_switch(
                        read.value("keymap"),
                        self.value(Field::Switch) == SWITCH_HENKAN,
                    );
                    changes.push(("keymap", keymap));
                }
                (Field::Correction, _) => {
                    let (level, sensitivity) = split_correction(self.value(Field::Correction));
                    changes.push(("typoCorrection", json!(level)));
                    if let Some(sensitivity) = sensitivity {
                        changes.push(("correctionSensitivity", json!(sensitivity)));
                    }
                }
            }
        }
        changes.retain(|(path, value)| {
            read.value(path)
                .is_none_or(|current| !crate::model::same(current, value))
        });
        changes
    }
}

impl<S: crate::store::SettingsStore> Read for crate::model::SettingsModel<S> {
    fn value(&self, path: &str) -> Option<&Value> {
        crate::model::SettingsModel::value(self, path)
    }

    fn is_default(&self, path: &str) -> bool {
        crate::model::SettingsModel::is_default(self, path)
    }
}

/// 今の設定の値を，ウィザードの選択肢の値にする
fn current_value(read: &dyn Read, field: Field) -> String {
    let text = |path: &str| {
        read.value(path)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string()
    };
    match field {
        Field::Path("liveConversionDelay") => read
            .value("liveConversionDelay")
            .and_then(Value::as_f64)
            .map_or_else(String::new, |seconds| format!("{seconds}")),
        Field::Path(path) => text(path),
        Field::Switch => {
            if uses_henkan(read.value("keymap")) {
                SWITCH_HENKAN.into()
            } else {
                SWITCH_TOGGLE.into()
            }
        }
        Field::Correction => match text("typoCorrection").as_str() {
            "standard" => match text("correctionSensitivity").as_str() {
                "cautious" => "cautious".into(),
                "aggressive" => "aggressive".into(),
                _ => "standard".into(),
            },
            level => level.to_string(),
        },
    }
}

/// 選択肢の中で value に当たるもの．無ければ近いもの(時間)か先頭
fn nearest(list: &[Choice], field: Field, value: &str) -> String {
    if list.iter().any(|(candidate, _)| *candidate == value) {
        return value.to_string();
    }
    if field == Field::Path("liveConversionDelay") {
        if let Ok(seconds) = value.parse::<f64>() {
            let distance = |candidate: &str| {
                candidate
                    .parse::<f64>()
                    .map_or(f64::MAX, |other| (other - seconds).abs())
            };
            if let Some((candidate, _)) = list
                .iter()
                .min_by(|a, b| distance(a.0).total_cmp(&distance(b.0)))
            {
                return (*candidate).to_string();
            }
        }
    }
    list.first()
        .map(|(candidate, _)| (*candidate).to_string())
        .unwrap_or_default()
}

fn split_correction(value: &str) -> (&'static str, Option<&'static str>) {
    match value {
        "off" => ("off", None),
        "conservative" => ("conservative", None),
        "cautious" => ("standard", Some("cautious")),
        "aggressive" => ("standard", Some("aggressive")),
        _ => ("standard", Some("standard")),
    }
}

fn is_henkan_row(row: &Value, (state, key, command): (&str, &str, &str)) -> bool {
    row.get("state").and_then(Value::as_str) == Some(state)
        && row.get("key").and_then(Value::as_str) == Some(key)
        && row.get("command").and_then(Value::as_str) == Some(command)
}

/// キー設定の表に，変換・無変換で切り替える行があるか
pub fn uses_henkan(keymap: Option<&Value>) -> bool {
    let rows = keymap.and_then(Value::as_array);
    HENKAN_ROWS
        .iter()
        .all(|wanted| rows.is_some_and(|rows| rows.iter().any(|row| is_henkan_row(row, *wanted))))
}

/// キー設定の表から切り替えの行を外し，henkan なら表の最後に足す(ほかの行は変えない)
pub fn with_switch(keymap: Option<&Value>, henkan: bool) -> Value {
    let mut rows: Vec<Value> = keymap
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|row| !HENKAN_ROWS.iter().any(|wanted| is_henkan_row(row, *wanted)))
        .collect();
    if henkan {
        rows.extend(
            HENKAN_ROWS.iter().map(
                |(state, key, command)| json!({"state": state, "key": key, "command": command}),
            ),
        );
    }
    Value::Array(rows)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    struct Table(HashMap<&'static str, Value>, Vec<&'static str>);

    impl Read for Table {
        fn value(&self, path: &str) -> Option<&Value> {
            self.0.get(path)
        }
        fn is_default(&self, path: &str) -> bool {
            !self.1.contains(&path)
        }
    }

    fn table(changed: Vec<&'static str>) -> Table {
        Table(
            HashMap::from([
                ("candidatePresentation", json!("list")),
                ("initialFocus", json!("automatic")),
                ("liveConversionDelay", json!(0.7)),
                ("liveConversion", json!(true)),
                ("typoCorrection", json!("standard")),
                ("correctionSensitivity", json!("cautious")),
                ("theme", json!("washi")),
                ("inputStyle", json!("romaji")),
                ("punctuation", json!("commaPeriod")),
                ("association", json!(true)),
                ("calculation", json!(false)),
                ("remembersRejectedCorrections", json!(false)),
                (
                    "keymap",
                    json!([{"state": "anywhere", "key": "Enter", "command": "commit"}]),
                ),
            ]),
            changed,
        )
    }

    #[test]
    fn 既定のままなら推奨の値を選ぶ() {
        let choices = Choices::load(&table(vec![]));
        assert_eq!(
            choices.value(Field::Path("candidatePresentation")),
            "automatic"
        );
        assert_eq!(choices.value(Field::Path("initialFocus")), "start");
        assert_eq!(choices.value(Field::Path("liveConversionDelay")), "0.5");
        // 推奨の無い項目は今の値
        assert_eq!(choices.value(Field::Path("theme")), "washi");
        assert_eq!(choices.value(Field::Correction), "cautious");
        assert_eq!(choices.value(Field::Switch), SWITCH_TOGGLE);
        assert!(choices.is_on("association"));
        assert!(!choices.is_on("calculation"));
    }

    #[test]
    fn 変えてあれば今の値を残し時間は近い選択肢にする() {
        let choices = Choices::load(&table(vec![
            "candidatePresentation",
            "initialFocus",
            "liveConversionDelay",
        ]));
        assert_eq!(choices.value(Field::Path("candidatePresentation")), "list");
        assert_eq!(choices.value(Field::Path("initialFocus")), "automatic");
        assert_eq!(choices.value(Field::Path("liveConversionDelay")), "0.8");
    }

    #[test]
    fn 変えた値だけを書く() {
        let read = table(vec!["initialFocus"]);
        let mut choices = Choices::load(&read);
        assert!(choices.changes(Step::Focus, &read).is_empty());
        choices.select(Field::Path("initialFocus"), "start");
        assert_eq!(
            choices.changes(Step::Focus, &read),
            vec![("initialFocus", json!("start"))]
        );
        assert_eq!(
            choices.changes(Step::LiveConversion, &read),
            vec![("liveConversionDelay", json!(0.5))]
        );
        choices.select(Field::Correction, "aggressive");
        assert_eq!(
            choices.changes(Step::Correction, &read),
            vec![("correctionSensitivity", json!("aggressive"))]
        );
        choices.select(Field::Correction, "off");
        assert_eq!(
            choices.changes(Step::Correction, &read),
            vec![("typoCorrection", json!("off"))]
        );
    }

    #[test]
    fn 変換と無変換の行を足し外す() {
        let read = table(vec![]);
        let mut choices = Choices::load(&read);
        choices.select(Field::Switch, SWITCH_HENKAN);
        let changes = choices.changes(Step::Switch, &read);
        let keymap = &changes[0].1;
        assert_eq!(keymap.as_array().unwrap().len(), 3);
        assert!(uses_henkan(Some(keymap)));
        // 2 度足しても重ならない
        let again = with_switch(Some(keymap), true);
        assert_eq!(again.as_array().unwrap().len(), 3);
        let removed = with_switch(Some(keymap), false);
        assert_eq!(removed, read.0["keymap"]);
        assert!(!uses_henkan(Some(&removed)));
    }

    #[test]
    fn ページを行き来できる() {
        assert_eq!(Step::Welcome.previous(), None);
        assert_eq!(Step::Welcome.next(), Some(Step::Switch));
        assert_eq!(Step::Done.next(), None);
        assert_eq!(Step::Done.previous(), Some(Step::Appearance));
        assert!(Step::ALL.iter().all(|step| !step.title().is_empty()));
    }
}
