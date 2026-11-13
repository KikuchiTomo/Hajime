#![forbid(unsafe_code)]

//! 初期設定のページと選ぶ値(macOS の OnboardingPage・OnboardingSpotlight・OnboardingModel)．OS に依らない
//! (窓は app::wizard，実演の台本は demo)．
//! 開いたときは今の設定に推奨の値を重ね，「はじめる」で初期設定が受け持つ項目だけをまとめて書く(macOS と同じ)．
//! キー設定の表と補正の強さは，1 つの選択を複数の値に写す

use crate::options::{self, Choice};
use crate::strings::{choice, more, settings, windows_wizard as notes, wizard as text};
use serde_json::{json, Value};

/// 初期設定のページ(並んでいる順．macOS と同じ)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Step {
    ModeSwitch,
    /// アプリごとの入力モード(除外設定の IME をオフ・オン・オンオフを記憶)の紹介
    AppModes,
    Correction,
    Theme,
    LiveConversion,
    /// 候補の出し方と最初に選ぶ文節
    Presentation,
    Characters,
    Features,
    /// 既定ではオフの試験的な機能
    Extras,
}

impl Step {
    pub const ALL: [Step; 9] = [
        Step::ModeSwitch,
        Step::AppModes,
        Step::Correction,
        Step::Theme,
        Step::LiveConversion,
        Step::Presentation,
        Step::Characters,
        Step::Features,
        Step::Extras,
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

    pub fn is_first(self) -> bool {
        self.previous().is_none()
    }

    pub fn is_last(self) -> bool {
        self.next().is_none()
    }

    pub fn title(self) -> &'static str {
        match self {
            Step::ModeSwitch => text::MODE_TITLE,
            Step::AppModes => text::APP_MODES_TITLE,
            Step::Correction => text::CORRECTION_TITLE,
            Step::Theme => text::THEME_TITLE,
            Step::LiveConversion => text::LIVE_TITLE,
            Step::Presentation => text::PRESENTATION_TITLE,
            Step::Characters => text::CHARACTERS_TITLE,
            Step::Features => text::FEATURES_TITLE,
            Step::Extras => text::EXTRAS_TITLE,
        }
    }

    /// 見出しの下に添える 1 行(macOS の OnboardingPage.detail)．選択肢と左の実演で分かるページには添えない
    pub fn detail(self) -> Option<&'static str> {
        match self {
            Step::AppModes => Some(text::APP_MODES_DETAIL),
            Step::Theme => Some(text::THEME_DETAIL),
            Step::ModeSwitch
            | Step::Extras
            | Step::Correction
            | Step::LiveConversion
            | Step::Presentation
            | Step::Characters
            | Step::Features => None,
        }
    }

    /// ページに並べるもの(上から順)
    pub fn items(self) -> Vec<Item> {
        match self {
            Step::ModeSwitch => vec![Item::Cards(Field::Switch, SWITCH_CARDS)],
            // 紹介だけ．選ぶのは設定の画面の除外設定
            Step::AppModes => vec![Item::Info(APP_MODES)],
            Step::Correction => vec![Item::Cards(Field::Correction, CORRECTION_CARDS)],
            Step::Theme => vec![Item::Themes],
            Step::LiveConversion => vec![
                Item::Cards(LIVE, LIVE_CARDS),
                Item::Seconds {
                    title: text::LIVE_DELAY,
                    field: LIVE_DELAY,
                },
            ],
            Step::Presentation => vec![
                Item::Cards(Field::Path("candidatePresentation"), PRESENTATION_CARDS),
                Item::Picker(Picker {
                    title: text::INITIAL_FOCUS,
                    field: Field::Path("initialFocus"),
                    choices: options::INITIAL_FOCUS,
                    recommended: Some("start"),
                    framed: false,
                }),
            ],
            Step::Characters => CHARACTERS
                .iter()
                .map(|(title, path, choices)| {
                    Item::Picker(Picker {
                        title,
                        field: Field::Path(path),
                        choices,
                        recommended: None,
                        framed: true,
                    })
                })
                .collect(),
            Step::Features => vec![Item::Spotlight(FEATURES)],
            Step::Extras => vec![Item::Spotlight(EXTRAS)],
        }
    }

    /// 機能を紹介するページなら，並べる機能
    pub fn spots(self) -> &'static [Spot] {
        match self {
            Step::Features => FEATURES,
            Step::Extras => EXTRAS,
            _ => &[],
        }
    }
}

/// 選んだ値を書く先
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Field {
    /// 設定の 1 つの項目
    Path(&'static str),
    /// 英数とかなの切り替え方(キー設定の表の行)
    Switch,
    /// 自動補正(typoCorrection と correctionSensitivity)
    Correction,
}

/// ライブ変換を使うか(値は "true" か "false")
pub const LIVE: Field = Field::Path("liveConversion");
/// ライブ変換で漢字にするまでの時間(秒)
pub const LIVE_DELAY: Field = Field::Path("liveConversionDelay");
/// 外観のテーマ
pub const THEME: Field = Field::Path("theme");

/// 選択肢のカード(macOS の OptionCard)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Card {
    pub value: &'static str,
    pub title: &'static str,
    pub detail: Option<&'static str>,
    pub recommended: bool,
}

/// 入力モード表示(macOS の InfoCard の枠に入れる文字)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mark {
    /// 英数(A)
    Direct,
    /// 日本語(あ)
    Japanese,
    /// 両方を並べる(Aあ)
    Both,
}

/// 紹介だけのカード(macOS の InfoCard)．どう動くかは左の実演で見せる
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Info {
    pub mark: Mark,
    pub title: &'static str,
}

/// 名前とメニューの行(macOS の CharacterRow と，最初に選ぶ文節の LabeledContent)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Picker {
    pub title: &'static str,
    pub field: Field,
    pub choices: &'static [Choice],
    /// 推奨の値(メニューの名前に「(推奨)」を添える)
    pub recommended: Option<&'static str>,
    /// カードの背景に載せる(入力する文字の行)
    pub framed: bool,
}

/// 機能の紹介の項目(macOS の OnboardingSpotlight)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Spot {
    /// オンとオフを切り替える設定の項目
    pub path: &'static str,
    pub title: &'static str,
    /// 舞台の下のタグに出す説明
    pub detail: &'static str,
}

/// ページに並べるもの
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Item {
    /// 1 つを選ぶカード
    Cards(Field, &'static [Card]),
    /// 説明だけのカード
    Info(&'static [Info]),
    /// テーマの見本のカード(THEME_ORDER)
    Themes,
    /// 秒の値のスライダー(ライブ変換がオフなら使えない)
    Seconds {
        title: &'static str,
        field: Field,
    },
    Picker(Picker),
    /// 機能の一覧(アイコン・名前・スイッチ)
    Spotlight(&'static [Spot]),
}

/// 切り替えの値(ウィザードだけのもの．キー設定の表の行に写す)．分けるのが推奨(macOS の ModeSwitchStyle.recommended)
pub const SWITCH_SEPARATE: &str = "separate";
pub const SWITCH_SINGLE: &str = "single";
const SWITCH_CARDS: &[Card] = &[
    Card {
        value: SWITCH_SEPARATE,
        title: notes::MODE_SEPARATE,
        detail: None,
        recommended: true,
    },
    Card {
        value: SWITCH_SINGLE,
        title: notes::MODE_SINGLE,
        detail: None,
        recommended: false,
    },
];

/// 無変換キー・変換キーで分けるときに足す行(状態を書いた行は いつでも の行に勝つ．
/// 半角/全角キーの行は残すので，どちらの使い方でも半角/全角キーで切り替えられる)
const SEPARATE_ROWS: [(&str, &str, &str); 2] = [
    ("idle", "Muhenkan", "directMode"),
    ("direct", "Henkan", "japaneseMode"),
];

/// アプリごとの入力モード(macOS と同じ並び．名前は除外設定の選択肢と同じ)
const APP_MODES: &[Info] = &[
    Info {
        mark: Mark::Direct,
        title: "IME をオフ",
    },
    Info {
        mark: Mark::Japanese,
        title: "IME をオン",
    },
    Info {
        mark: Mark::Both,
        title: "IME のオンオフを記憶",
    },
];

/// 自動補正．はじめの 3 つは typoCorrection を standard にして強さを選び，直さないは typoCorrection を off にする
const CORRECTION_CARDS: &[Card] = &[
    Card {
        value: "cautious",
        title: "慎重",
        detail: Some(notes::CORRECTION_CAUTIOUS_DETAIL),
        recommended: false,
    },
    Card {
        value: "standard",
        title: "標準",
        detail: Some(notes::CORRECTION_STANDARD_DETAIL),
        recommended: true,
    },
    Card {
        value: "aggressive",
        title: "積極的",
        detail: Some(notes::CORRECTION_AGGRESSIVE_DETAIL),
        recommended: false,
    },
    Card {
        value: "off",
        title: text::CORRECTION_OFF,
        detail: None,
        recommended: false,
    },
];

const LIVE_CARDS: &[Card] = &[
    Card {
        value: "true",
        title: text::LIVE_ON,
        detail: None,
        recommended: true,
    },
    Card {
        value: "false",
        title: text::LIVE_OFF,
        detail: None,
        recommended: false,
    },
];

const PRESENTATION_CARDS: &[Card] = &[
    Card {
        value: "automatic",
        title: "分岐図",
        detail: Some(notes::PRESENTATION_AUTOMATIC_DETAIL),
        recommended: true,
    },
    Card {
        value: "segmentList",
        title: "一覧",
        detail: Some(notes::PRESENTATION_SEGMENT_LIST_DETAIL),
        recommended: false,
    },
    Card {
        value: "list",
        title: "文全体の一覧",
        detail: Some(notes::PRESENTATION_LIST_DETAIL),
        recommended: false,
    },
];

/// 入力する文字の行(名前・項目・選択肢．macOS の初期設定と同じ 7 つ)
const CHARACTERS: &[(&str, &str, &[Choice])] = &[
    (settings::PUNCTUATION, "punctuation", options::PUNCTUATION),
    (settings::BRACKETS, "brackets", options::BRACKETS),
    (settings::SLASH, "slash", options::SLASH),
    (choice::YEN_KEY, "yenKey", options::YEN_KEY),
    (settings::SPACE_WIDTH, "spaceWidth", options::WIDTHS),
    (settings::NUMBER_WIDTH, "numberWidth", options::WIDTHS),
    (more::ALPHABET_WIDTH, "alphabetWidth", options::WIDTHS),
];

/// テーマのカードの並び(core の ThemePreference の並びから，標準と同じ見た目の native を除いたもの．macOS と同じ)
pub const THEME_ORDER: [&str; 8] = [
    "automatic",
    "platinum",
    "desk",
    "washi",
    "neon",
    "terminal",
    "nordic",
    "contrast",
];

/// テーマの名前
pub fn theme_label(name: &str) -> &'static str {
    options::THEMES
        .iter()
        .find(|(value, _)| *value == name)
        .map_or("", |(_, label)| *label)
}

/// 紹介する便利な機能
pub const FEATURES: &[Spot] = &[
    Spot {
        path: "association",
        title: text::ASSOCIATION,
        detail: text::ASSOCIATION_DETAIL,
    },
    Spot {
        path: "calculation",
        title: text::CALCULATION,
        detail: text::CALCULATION_DETAIL,
    },
    Spot {
        path: "postalCodeConversion",
        title: text::POSTAL_CODE,
        detail: text::POSTAL_CODE_DETAIL,
    },
    Spot {
        path: "dateConversion",
        title: text::DATE,
        detail: text::DATE_DETAIL,
    },
];

/// 紹介する試験的な機能(既定ではオフ)
pub const EXTRAS: &[Spot] = &[
    Spot {
        path: "looseReadings",
        title: crate::strings::extras::LOOSE_READINGS,
        detail: crate::strings::extras::LOOSE_READINGS_NOTE,
    },
    Spot {
        path: "phoneticSpelling",
        title: crate::strings::extras::PHONETIC_SPELLING,
        detail: crate::strings::extras::PHONETIC_SPELLING_NOTE,
    },
    Spot {
        path: "handShiftCorrection",
        title: crate::strings::extras::HAND_SHIFT,
        detail: crate::strings::extras::HAND_SHIFT_NOTE,
    },
    Spot {
        path: "conversionMacros",
        title: text::MACROS,
        detail: text::MACROS_DETAIL,
    },
    Spot {
        path: "dynamicDictionary",
        title: text::DYNAMIC_DICTIONARY,
        detail: text::DYNAMIC_DICTIONARY_DETAIL,
    },
    Spot {
        path: "launcherCommands",
        title: text::COMMANDS,
        detail: text::COMMANDS_DETAIL,
    },
];

/// 初期設定で選ぶライブ変換の時間の推奨(core の DefaultSettings.onboardingLiveConversionDelay)
pub const ONBOARDING_LIVE_DELAY: f64 = 0.5;

/// 選んでいる値．開いたときは今の設定に推奨の値を重ねたもの(macOS の OnboardingPage.recommended)
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Choices {
    values: Vec<(Field, String)>,
    toggles: Vec<(&'static str, bool)>,
    /// 時間の値(秒)
    numbers: Vec<(Field, f64)>,
    /// カスタムテーマを使っている．テーマのカードを選ぶまで残す(macOS の customThemeID)
    custom_theme: bool,
    /// 実演に使う今の設定の値(書かない)
    correction_delay: Option<f64>,
    font_size: Option<f64>,
}

/// 設定の値を読む口(SettingsModel を渡す．テストでは表を渡す)
pub trait Read {
    fn value(&self, path: &str) -> Option<&Value>;
}

impl Choices {
    /// 今の設定から作り，初期設定が推奨する値を重ねる
    pub fn load(read: &dyn Read) -> Self {
        let text = |path: &str| read.value(path).and_then(Value::as_str).unwrap_or_default();
        let mut choices = Self {
            correction_delay: read.value("correctionDelay").and_then(Value::as_f64),
            font_size: read.value("candidateFontSize").and_then(Value::as_f64),
            ..Self::default()
        };
        choices.select(Field::Switch, SWITCH_SEPARATE);
        choices.select(Field::Correction, "standard");
        choices.select(LIVE, "true");
        choices.set_seconds(LIVE_DELAY, ONBOARDING_LIVE_DELAY);
        choices.select(Field::Path("candidatePresentation"), "automatic");
        choices.select(Field::Path("initialFocus"), "start");
        // テーマは今の値のまま(以前の値 native はカードに無いので，どれも選ばない．macOS と同じ)
        choices.select(THEME, text("theme"));
        choices.custom_theme = read
            .value(crate::themes::ACTIVE)
            .and_then(Value::as_str)
            .is_some_and(|id| !id.is_empty());
        for (_, path, list) in CHARACTERS {
            let current = text(path);
            let value = list
                .iter()
                .find(|(value, _)| *value == current)
                .or(list.first())
                .map_or("", |(value, _)| *value);
            choices.select(Field::Path(path), value);
        }
        for spot in FEATURES.iter().chain(EXTRAS) {
            let on = read
                .value(spot.path)
                .and_then(Value::as_bool)
                .unwrap_or(false);
            choices.set_toggle(spot.path, on);
        }
        choices
    }

    pub fn value(&self, field: Field) -> &str {
        self.values
            .iter()
            .find(|(candidate, _)| *candidate == field)
            .map_or("", |(_, value)| value.as_str())
    }

    pub fn select(&mut self, field: Field, value: &str) {
        if field == THEME {
            self.custom_theme = false;
        }
        match self
            .values
            .iter_mut()
            .find(|(candidate, _)| *candidate == field)
        {
            Some((_, current)) => *current = value.to_string(),
            None => self.values.push((field, value.to_string())),
        }
    }

    /// テーマのカードを選んでいるか(カスタムテーマを使っているあいだはどれも選んでいない)
    pub fn theme_selected(&self, name: &str) -> bool {
        !self.custom_theme && self.value(THEME) == name
    }

    /// 候補の窓を描くテーマ(以前の値と知らない値は標準)
    pub fn theme(&self) -> &str {
        match self.value(THEME) {
            name if THEME_ORDER.contains(&name) => name,
            _ => THEME_ORDER[0],
        }
    }

    pub fn is_on(&self, path: &str) -> bool {
        self.toggles
            .iter()
            .any(|(candidate, on)| *candidate == path && *on)
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

    /// ライブ変換を使うか
    pub fn live(&self) -> bool {
        self.value(LIVE) == "true"
    }

    pub fn seconds(&self, field: Field) -> f64 {
        self.numbers
            .iter()
            .find(|(candidate, _)| *candidate == field)
            .map_or(0.0, |(_, value)| *value)
    }

    pub fn set_seconds(&mut self, field: Field, seconds: f64) {
        match self
            .numbers
            .iter_mut()
            .find(|(candidate, _)| *candidate == field)
        {
            Some((_, current)) => *current = seconds,
            None => self.numbers.push((field, seconds)),
        }
    }

    /// 補正を探すまでの時間(秒．実演で待つ)
    pub fn correction_delay(&self) -> Option<f64> {
        self.correction_delay
    }

    /// 候補の文字の大きさ(実演の候補の窓)
    pub fn font_size(&self) -> Option<f64> {
        self.font_size
    }

    /// 初期設定が受け持つ項目だけを設定の値にする(macOS の OnboardingModel.apply)．今の値と同じものは含めない
    pub fn changes(&self, read: &dyn Read) -> Vec<(&'static str, Value)> {
        let mut changes: Vec<(&'static str, Value)> = vec![(
            "keymap",
            with_switch(
                read.value("keymap"),
                self.value(Field::Switch) == SWITCH_SEPARATE,
            ),
        )];
        // 直さないときも，強さは開いたときの推奨のまま書く(macOS と同じ)
        let (level, sensitivity) = match self.value(Field::Correction) {
            "off" => ("off", "standard"),
            "cautious" => ("standard", "cautious"),
            "aggressive" => ("standard", "aggressive"),
            _ => ("standard", "standard"),
        };
        changes.push(("typoCorrection", json!(level)));
        changes.push(("correctionSensitivity", json!(sensitivity)));
        if !self.value(THEME).is_empty() {
            changes.push(("theme", json!(self.value(THEME))));
        }
        if !self.custom_theme {
            changes.push((crate::themes::ACTIVE, Value::Null));
        }
        changes.push(("liveConversion", Value::Bool(self.live())));
        changes.push((
            "liveConversionDelay",
            crate::model::number(self.seconds(LIVE_DELAY)),
        ));
        for path in ["candidatePresentation", "initialFocus"]
            .into_iter()
            .chain(CHARACTERS.iter().map(|(_, path, _)| *path))
        {
            changes.push((path, json!(self.value(Field::Path(path)))));
        }
        for spot in FEATURES.iter().chain(EXTRAS) {
            changes.push((spot.path, Value::Bool(self.is_on(spot.path))));
        }
        changes.retain(|(path, value)| match read.value(path) {
            Some(current) => !crate::model::same(current, value),
            None => !value.is_null(),
        });
        changes
    }
}

impl<S: crate::store::SettingsStore> Read for crate::model::SettingsModel<S> {
    fn value(&self, path: &str) -> Option<&Value> {
        crate::model::SettingsModel::value(self, path)
    }
}

fn is_separate_row(row: &Value, (state, key, command): (&str, &str, &str)) -> bool {
    row.get("state").and_then(Value::as_str) == Some(state)
        && row.get("key").and_then(Value::as_str) == Some(key)
        && row.get("command").and_then(Value::as_str) == Some(command)
}

/// キー設定の表に，無変換キー・変換キーで分ける行があるか
pub fn uses_separate_keys(keymap: Option<&Value>) -> bool {
    let rows = keymap.and_then(Value::as_array);
    SEPARATE_ROWS
        .iter()
        .all(|wanted| rows.is_some_and(|rows| rows.iter().any(|row| is_separate_row(row, *wanted))))
}

/// キー設定の表から分ける行を外し，separate なら表の最後に足す(ほかの行は変えない)
pub fn with_switch(keymap: Option<&Value>, separate: bool) -> Value {
    let mut rows: Vec<Value> = keymap
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .filter(|row| {
            !SEPARATE_ROWS
                .iter()
                .any(|wanted| is_separate_row(row, *wanted))
        })
        .collect();
    if separate {
        rows.extend(
            SEPARATE_ROWS.iter().map(
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

    struct Table(HashMap<&'static str, Value>);

    impl Read for Table {
        fn value(&self, path: &str) -> Option<&Value> {
            self.0.get(path)
        }
    }

    fn table() -> Table {
        Table(HashMap::from([
            ("candidatePresentation", json!("list")),
            ("initialFocus", json!("automatic")),
            ("liveConversionDelay", json!(0.7)),
            ("liveConversion", json!(false)),
            ("typoCorrection", json!("conservative")),
            ("correctionSensitivity", json!("cautious")),
            ("theme", json!("washi")),
            ("customThemeID", json!("my-theme")),
            ("inputStyle", json!("kana")),
            ("punctuation", json!("commaPeriod")),
            ("brackets", json!("square")),
            ("association", json!(true)),
            ("calculation", json!(false)),
            ("remembersRejectedCorrections", json!(true)),
            (
                "keymap",
                json!([{"state": "anywhere", "key": "Enter", "command": "commit"}]),
            ),
        ]))
    }

    #[test]
    fn ページは_macos_と同じ_9_つを同じ順に並べる() {
        assert_eq!(Step::ALL.len(), 9);
        assert_eq!(Step::ModeSwitch.previous(), None);
        assert_eq!(Step::ModeSwitch.next(), Some(Step::AppModes));
        assert_eq!(Step::Theme.next(), Some(Step::LiveConversion));
        assert_eq!(Step::Extras.next(), None);
        assert!(Step::Extras.is_last() && Step::ModeSwitch.is_first());
        assert!(Step::ALL
            .iter()
            .all(|step| !step.title().is_empty() && step.detail() != Some("")));
        assert_eq!(Step::Features.spots().len(), 4);
        assert_eq!(Step::Extras.spots().len(), 6);
    }

    #[test]
    fn 開くと推奨の値を選び_ほかは今の値にする() {
        let choices = Choices::load(&table());
        assert_eq!(choices.value(Field::Switch), SWITCH_SEPARATE);
        assert_eq!(choices.value(Field::Correction), "standard");
        assert!(choices.live());
        assert_eq!(choices.seconds(LIVE_DELAY), ONBOARDING_LIVE_DELAY);
        assert_eq!(
            choices.value(Field::Path("candidatePresentation")),
            "automatic"
        );
        assert_eq!(choices.value(Field::Path("initialFocus")), "start");
        // 推奨の無い項目は今の値．知らない値は先頭
        assert_eq!(choices.value(Field::Path("punctuation")), "commaPeriod");
        assert_eq!(choices.value(Field::Path("brackets")), "square");
        assert_eq!(choices.value(Field::Path("slash")), "nakaguro");
        assert!(choices.is_on("association"));
        assert!(!choices.is_on("calculation"));
        // カスタムテーマを使っているあいだは，どのテーマのカードも選んでいない
        assert!(!choices.theme_selected("washi"));
        assert_eq!(choices.theme(), "washi");
    }

    #[test]
    fn はじめるで書くのは初期設定が受け持つ項目だけ() {
        let read = table();
        let choices = Choices::load(&read);
        let changes = choices.changes(&read);
        let paths: Vec<&str> = changes.iter().map(|(path, _)| *path).collect();
        // 入力方式と取り消した補正の学習は初期設定に無いので書かない
        assert!(!paths.contains(&"inputStyle"));
        assert!(!paths.contains(&"remembersRejectedCorrections"));
        // 選ばなかったテーマとカスタムテーマはそのまま
        assert!(!paths.contains(&"theme"));
        assert!(!paths.contains(&"customThemeID"));
        let value = |path: &str| {
            changes
                .iter()
                .find(|(candidate, _)| *candidate == path)
                .map(|(_, value)| value.clone())
        };
        assert_eq!(value("typoCorrection"), Some(json!("standard")));
        assert_eq!(value("correctionSensitivity"), Some(json!("standard")));
        assert_eq!(value("liveConversion"), Some(json!(true)));
        assert_eq!(value("liveConversionDelay"), Some(json!(0.5)));
        assert_eq!(value("initialFocus"), Some(json!("start")));
        assert_eq!(value("punctuation"), None);
        assert!(uses_separate_keys(value("keymap").as_ref()));
    }

    #[test]
    fn テーマを選ぶとカスタムテーマを外す() {
        let read = table();
        let mut choices = Choices::load(&read);
        choices.select(THEME, "neon");
        assert!(choices.theme_selected("neon"));
        let changes = choices.changes(&read);
        assert!(changes.contains(&("theme", json!("neon"))));
        assert!(changes.contains(&(crate::themes::ACTIVE, Value::Null)));
    }

    #[test]
    fn 補正の選択を補正の程度と強さに写す() {
        let read = table();
        let mut choices = Choices::load(&read);
        choices.select(Field::Correction, "aggressive");
        let changes = choices.changes(&read);
        assert!(changes.contains(&("typoCorrection", json!("standard"))));
        assert!(changes.contains(&("correctionSensitivity", json!("aggressive"))));
        choices.select(Field::Correction, "off");
        let changes = choices.changes(&read);
        assert!(changes.contains(&("typoCorrection", json!("off"))));
        assert!(changes.contains(&("correctionSensitivity", json!("standard"))));
    }

    #[test]
    fn 無変換と変換の行を足し外す() {
        let read = table();
        let mut choices = Choices::load(&read);
        let changes = choices.changes(&read);
        let keymap = &changes
            .iter()
            .find(|(path, _)| *path == "keymap")
            .unwrap()
            .1;
        assert_eq!(keymap.as_array().unwrap().len(), 3);
        // 2 度足しても重ならない
        let again = with_switch(Some(keymap), true);
        assert_eq!(again.as_array().unwrap().len(), 3);
        let removed = with_switch(Some(keymap), false);
        assert_eq!(removed, read.0["keymap"]);
        assert!(!uses_separate_keys(Some(&removed)));
        // 1 つのキーで切り替えるなら，今の表のまま(書かない)
        choices.select(Field::Switch, SWITCH_SINGLE);
        assert!(!choices
            .changes(&read)
            .iter()
            .any(|(path, _)| *path == "keymap"));
    }

    #[test]
    fn 以前のテーマの値は選ぶまで残し_標準の見た目で見せる() {
        let mut read = table();
        read.0.insert("theme", json!("native"));
        read.0.remove("customThemeID");
        let choices = Choices::load(&read);
        assert!(!choices.theme_selected("automatic"));
        assert_eq!(choices.theme(), "automatic");
        assert!(!choices
            .changes(&read)
            .iter()
            .any(|(path, _)| *path == "theme"));
    }

    #[test]
    fn 各ページに並べるものがある() {
        for step in Step::ALL {
            assert!(!step.items().is_empty(), "{step:?}");
        }
        assert_eq!(Step::Characters.items().len(), 7);
        assert_eq!(theme_label("desk"), "夜のデスク");
    }
}
