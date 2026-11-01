#![forbid(unsafe_code)]

//! 初期設定ウィザードの実演の台本．キーを打つ・変換する・候補を選ぶ様子を，時間で進む場面(Beat)の並びにする．
//! 選んだ値(Choices)で台本を作り直すので，選ぶとすぐ実演に出る．OS に依らない(描くのは app::wizard)．
//! 実演の文字は台本に書いた見本だけで，利用者の入力は使わない

use crate::strings::wizard as text;
use crate::wizard::{Choices, Field, Step, SWITCH_HENKAN};
use ipc::{
    AssociationHeading, BranchColumn, BranchMap, CandidateEntry, CandidateFocus, CandidateList,
    KeyHint,
};
use tokens::motion::settings_windows as motion;

/// 入力中の文字の見え方(下線の種類)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Style {
    /// 確定した文字(下線なし)
    Plain,
    /// 入力中の文字(細い下線)
    Typing,
    /// 変換した文節(細い下線)
    Converted,
    /// 選んでいる文節(太い下線)
    Focused,
    /// 補正した文字(点線)
    Corrected,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Run {
    pub text: String,
    pub style: Style,
}

/// 入力モード(札に出す)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Japanese,
    English,
}

/// 候補ウィンドウ
#[derive(Debug, Clone, PartialEq)]
pub enum Popup {
    Branch(BranchMap),
    List(CandidateList),
}

/// 実演の 1 コマ
#[derive(Debug, Clone, PartialEq)]
pub struct Frame {
    /// 文書の中の文字(確定したものと入力中のもの)
    pub runs: Vec<Run>,
    pub mode: Mode,
    /// 押しているキー
    pub key: Option<&'static str>,
    pub popup: Option<Popup>,
    /// 候補ウィンドウを見分ける番号(変わったら描き直す)
    pub popup_id: u32,
    /// ライブ変換が漢字にするのを待っている(コマの中の進み具合を帯で出す)
    pub waiting: bool,
    /// 何をしているかの説明
    pub caption: Option<&'static str>,
}

impl Default for Frame {
    fn default() -> Self {
        Self {
            runs: Vec::new(),
            mode: Mode::Japanese,
            key: None,
            popup: None,
            popup_id: 0,
            waiting: false,
            caption: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
struct Beat {
    /// ミリ秒
    duration: f64,
    frame: Frame,
}

/// 実演の台本．初めから終わりまで進んだら繰り返す
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Script {
    beats: Vec<Beat>,
    /// 結果を見せるコマ(動きを減らす設定のときはこれだけを出す)
    result: usize,
}

/// 台本の今の位置
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Position {
    pub beat: usize,
    /// コマの中の進み具合(0〜1)
    pub progress: f32,
    /// コマに入ってからのミリ秒
    pub elapsed: f64,
    /// 次のコマまでのミリ秒
    pub remaining: f64,
}

impl Script {
    pub fn is_empty(&self) -> bool {
        self.beats.is_empty()
    }

    pub fn total(&self) -> f64 {
        self.beats.iter().map(|beat| beat.duration).sum()
    }

    /// 始めてから elapsed ミリ秒たったときの位置(繰り返す)
    pub fn position(&self, elapsed: f64) -> Option<Position> {
        let total = self.total();
        if total <= 0.0 {
            return None;
        }
        let mut time = elapsed.max(0.0) % total;
        for (index, beat) in self.beats.iter().enumerate() {
            if time < beat.duration {
                return Some(Position {
                    beat: index,
                    progress: (time / beat.duration) as f32,
                    elapsed: time,
                    remaining: beat.duration - time,
                });
            }
            time -= beat.duration;
        }
        None
    }

    pub fn frame(&self, beat: usize) -> Option<&Frame> {
        self.beats.get(beat).map(|beat| &beat.frame)
    }

    pub fn result(&self) -> Option<&Frame> {
        self.frame(self.result)
    }

    pub fn result_index(&self) -> usize {
        self.result
    }
}

/// 今日の日付(日付の実演に使う)．weekday は 0 が日曜
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Today {
    pub year: u16,
    pub month: u16,
    pub day: u16,
    pub weekday: u16,
}

/// 令和 n 年は西暦 n + 2018 年(core の DateExpressions と同じ)
const REIWA_OFFSET: u16 = 2018;
const WEEKDAYS: [&str; 7] = ["日", "月", "火", "水", "木", "金", "土"];

impl Today {
    /// 年・月・日(とそれより後ろ)から．曜日は暦から求める
    pub fn from_fields(fields: [u16; 6]) -> Self {
        let [year, month, day, ..] = fields;
        let days = days_from_civil(i64::from(year), i64::from(month), i64::from(day));
        // 1970/1/1 は木曜
        let weekday = (days + 4).rem_euclid(7) as u16;
        Self {
            year,
            month,
            day,
            weekday,
        }
    }
}

/// 1970/1/1 からの日数(グレゴリオ暦)
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = year.div_euclid(400);
    let of_era = year - era * 400;
    let shifted = (month + 9) % 12;
    let of_year = (153 * shifted + 2) / 5 + day - 1;
    let of_era_day = of_era * 365 + of_era / 4 - of_era / 100 + of_year;
    era * 146_097 + of_era_day - 719_468
}

/// UNIX 時刻(秒)を UTC の年・月・日・時・分・秒にする
pub fn utc_fields(seconds: u64) -> [u16; 6] {
    let days = (seconds / 86_400) as i64 + 719_468;
    let rest = seconds % 86_400;
    let era = days.div_euclid(146_097);
    let of_era = days - era * 146_097;
    let year_of_era = (of_era - of_era / 1460 + of_era / 36_524 - of_era / 146_096) / 365;
    let of_year = of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let shifted = (5 * of_year + 2) / 153;
    let day = of_year - (153 * shifted + 2) / 5 + 1;
    let month = if shifted < 10 {
        shifted + 3
    } else {
        shifted - 9
    };
    let year = year_of_era + era * 400 + i64::from(month <= 2);
    [
        year as u16,
        month as u16,
        day as u16,
        (rest / 3600) as u16,
        (rest / 60 % 60) as u16,
        (rest % 60) as u16,
    ]
}

/// ローマ字の区切り(打つキーと，打ち終えたときのかな)
type Unit = (&'static str, &'static str);

const YOUKOSO: &[Unit] = &[("yo", "よ"), ("u", "う"), ("ko", "こ"), ("so", "そ")];
const WATASHINO: &[Unit] = &[("wa", "わ"), ("ta", "た"), ("shi", "し"), ("no", "の")];
const NAMAEHA: &[Unit] = &[("na", "な"), ("ma", "ま"), ("e", "え"), ("ha", "は")];
const NAKANODESU: &[Unit] = &[
    ("na", "な"),
    ("ka", "か"),
    ("no", "の"),
    ("de", "で"),
    ("su", "す"),
];
const NIHONGO: &[Unit] = &[("ni", "に"), ("ho", "ほ"), ("nn", "ん"), ("go", "ご")];
const KYOUHA: &[Unit] = &[("kyo", "きょ"), ("u", "う"), ("ha", "は")];
const IITENKI: &[Unit] = &[
    ("i", "い"),
    ("i", "い"),
    ("te", "て"),
    ("nn", "ん"),
    ("ki", "き"),
];
/// 「う」を 2 度打った(ダブルタイプ)
const ARIGATOU_TYPO: &[Unit] = &[
    ("a", "あ"),
    ("ri", "り"),
    ("ga", "が"),
    ("to", "と"),
    ("o", "お"),
    ("u", "う"),
];
const TOUKYOU: &[Unit] = &[("to", "と"), ("u", "う"), ("kyo", "きょ"), ("u", "う")];
const KYOU: &[Unit] = &[("kyo", "きょ"), ("u", "う")];
const CALCULATION: &[Unit] = &[
    ("1", "1"),
    ("+", "+"),
    ("2", "2"),
    ("*", "*"),
    ("3", "3"),
    ("=", "="),
];
const POSTAL: &[Unit] = &[
    ("1", "1"),
    ("0", "0"),
    ("0", "0"),
    ("-", "-"),
    ("0", "0"),
    ("0", "0"),
    ("0", "0"),
    ("1", "1"),
];

/// ローマ字かかなか
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Keys {
    Romaji,
    Kana,
}

/// 台本を書く道具．今のコマを変えながら場面を足す
struct Builder {
    beats: Vec<Beat>,
    frame: Frame,
    keys: Keys,
    result: Option<usize>,
}

impl Builder {
    fn new(keys: Keys) -> Self {
        Self {
            beats: Vec::new(),
            frame: Frame::default(),
            keys,
            result: None,
        }
    }

    fn push(&mut self, duration: f32) {
        self.beats.push(Beat {
            duration: f64::from(duration),
            frame: self.frame.clone(),
        });
        self.frame.key = None;
        self.frame.waiting = false;
    }

    /// 入力中の文字(最後の Typing の続き)に足す
    fn append_typing(&mut self, added: &str) {
        match self.frame.runs.last_mut() {
            Some(run) if run.style == Style::Typing => run.text.push_str(added),
            _ => self.frame.runs.push(Run {
                text: added.into(),
                style: Style::Typing,
            }),
        }
    }

    fn pop_typing(&mut self, count: usize) {
        if let Some(run) = self.frame.runs.last_mut() {
            for _ in 0..count {
                run.text.pop();
            }
        }
    }

    /// かなを打つ．ローマ字のときは 1 文字ずつ打ち，区切りを打ち終えたらかなにする
    fn type_units(&mut self, units: &[Unit]) {
        for (keys, kana) in units {
            match self.keys {
                Keys::Romaji if keys.chars().count() > 1 || keys != kana => {
                    let count = keys.chars().count();
                    for (index, key) in keys.chars().enumerate() {
                        if index + 1 < count {
                            self.append_typing(&key.to_string());
                            self.push(motion::WIZARD_KEY);
                        }
                    }
                    self.pop_typing(count - 1);
                    self.append_typing(kana);
                }
                _ => self.append_typing(kana),
            }
            self.push(motion::WIZARD_KEY);
        }
    }

    /// 英数モードで打つ(そのまま確定する)
    fn type_direct(&mut self, letters: &str) {
        for letter in letters.chars() {
            match self.frame.runs.last_mut() {
                Some(run) if run.style == Style::Plain => run.text.push(letter),
                _ => self.frame.runs.push(Run {
                    text: letter.into(),
                    style: Style::Plain,
                }),
            }
            self.push(motion::WIZARD_KEY);
        }
    }

    /// キーを押して見せる
    fn key(&mut self, label: &'static str) {
        self.frame.key = Some(label);
        self.push(motion::WIZARD_KEY_PRESS);
    }

    fn pause(&mut self, duration: f32) {
        self.push(duration);
    }

    fn caption(&mut self, caption: &'static str) {
        self.frame.caption = Some(caption);
    }

    fn popup(&mut self, popup: Option<Popup>) {
        self.frame.popup = popup;
        self.frame.popup_id += 1;
    }

    /// 入力中・変換中の文字を確定する
    fn commit(&mut self) {
        let text: String = self
            .frame
            .runs
            .iter()
            .map(|run| run.text.as_str())
            .collect();
        self.frame.runs = vec![Run {
            text,
            style: Style::Plain,
        }];
        self.popup(None);
    }

    /// 入力中・変換中の文字(確定した文字より後ろ)を置き換える
    fn replace_composition(&mut self, runs: &[(&str, Style)]) {
        self.frame.runs.retain(|run| run.style == Style::Plain);
        self.frame.runs.extend(runs.iter().map(|(text, style)| Run {
            text: (*text).into(),
            style: *style,
        }));
    }

    /// 結果を見せて止まる(ここを結果のコマにする)
    fn hold(&mut self) {
        self.result = Some(self.beats.len());
        self.push(motion::WIZARD_HOLD);
    }

    fn finish(mut self) -> Script {
        if self.beats.is_empty() {
            return Script::default();
        }
        let result = self.result.unwrap_or(self.beats.len() - 1);
        // 繰り返す前に文書を空にする間
        self.frame = Frame {
            mode: self.frame.mode,
            ..Frame::default()
        };
        self.push(motion::WIZARD_PAUSE);
        Script {
            beats: self.beats,
            result,
        }
    }
}

fn column(text: &str) -> BranchColumn {
    BranchColumn {
        text: text.into(),
        alternatives: vec![],
        selected_alternative: None,
        variants: vec![],
        selected_variant: None,
        is_focused: false,
        is_uncertain: false,
        is_decided: false,
        is_corrected: None,
        preview: None,
        shorter: None,
        longer: None,
        usage_note: None,
        alternative_notes: vec![],
        source_name: None,
        split: None,
    }
}

fn hints() -> Vec<KeyHint> {
    text::HINTS
        .iter()
        .map(|(keys, label)| KeyHint {
            keys: (*keys).into(),
            label: (*label).into(),
        })
        .collect()
}

/// 文節を並べた分岐図．focused の文節に候補の枝を出し，selected を選ぶ
fn branch(columns: &[&str], focused: usize, alternatives: &[&str], selected: usize) -> Popup {
    Popup::Branch(BranchMap {
        columns: columns
            .iter()
            .enumerate()
            .map(|(index, text)| {
                if index == focused {
                    BranchColumn {
                        alternatives: alternatives.iter().map(|text| (*text).into()).collect(),
                        selected_alternative: Some(selected as u32),
                        is_focused: true,
                        ..column(alternatives.get(selected).copied().unwrap_or(text))
                    }
                } else {
                    column(text)
                }
            })
            .collect(),
        position: selected as u32 + 1,
        total: alternatives.len() as u32,
        note: None,
        hints: hints(),
        association: None,
        association_hint: None,
    })
}

fn list(entries: &[&str], selected: usize, association: Option<&str>) -> Popup {
    Popup::List(CandidateList {
        variants: vec![],
        selected_variant: None,
        entries: entries
            .iter()
            .map(|text| CandidateEntry {
                text: (*text).into(),
                annotation: None,
                corrected_start: None,
                corrected_length: None,
            })
            .collect(),
        selected_entry: Some(selected as u32),
        focus: CandidateFocus::Candidate,
        position: selected as u32 + 1,
        total: entries.len() as u32,
        note: None,
        association: association.map(|headword| AssociationHeading {
            headword: headword.into(),
            label: text::ASSOCIATION_LABEL.into(),
            group: 0,
            group_count: 1,
        }),
        association_hint: None,
    })
}

/// 候補の窓(分岐図か一覧)
fn candidates(
    branch_map: bool,
    columns: &[&str],
    focused: usize,
    alternatives: &[&str],
    selected: usize,
) -> Popup {
    if branch_map {
        branch(columns, focused, alternatives, selected)
    } else {
        list(alternatives, selected, None)
    }
}

/// 変換した文節を下線つきで並べる(focused を太く)
fn segments<'a>(columns: &[&'a str], focused: usize) -> Vec<(&'a str, Style)> {
    columns
        .iter()
        .enumerate()
        .map(|(index, text)| {
            let style = if index == focused {
                Style::Focused
            } else {
                Style::Converted
            };
            (*text, style)
        })
        .collect()
}

const NAME_COLUMNS: [&str; 3] = ["私の", "名前は", "中野です"];
const NAME_ALTERNATIVES: [&str; 4] = ["中野です", "中のです", "仲のです", "那珂のです"];

/// step の実演．選んだ値で台本を変える
pub fn script(step: Step, choices: &Choices, today: Today) -> Script {
    let keys = if choices.value(Field::Path("inputStyle")) == "kana" {
        Keys::Kana
    } else {
        Keys::Romaji
    };
    let branch_map = choices.value(Field::Path("candidatePresentation")) == "automatic";
    let mut b = Builder::new(keys);
    match step {
        Step::Welcome => {
            b.type_units(YOUKOSO);
            b.key(text::KEY_ENTER);
            b.commit();
            b.hold();
        }
        Step::Switch => {
            let henkan = choices.value(Field::Switch) == SWITCH_HENKAN;
            let (to_english, to_japanese) = if henkan {
                (text::KEY_MUHENKAN, text::KEY_HENKAN)
            } else {
                (text::KEY_HANKAKU, text::KEY_HANKAKU)
            };
            b.key(to_english);
            b.frame.mode = Mode::English;
            b.caption(text::CAPTION_ENGLISH);
            b.pause(motion::WIZARD_KEY);
            b.type_direct("Windows ");
            b.key(to_japanese);
            b.frame.mode = Mode::Japanese;
            b.caption(text::CAPTION_JAPANESE);
            b.pause(motion::WIZARD_KEY);
            b.type_units(NIHONGO);
            b.key(text::KEY_ENTER);
            b.commit();
            b.hold();
        }
        Step::AppModes => {
            // メモ帳(IME のオンオフを記憶)で日本語を打ち，ターミナル(IME をオフ)に切り替えると英語になり，
            // メモ帳に戻すと日本語に戻る(macOS の初期設定と同じ)
            b.caption(text::CAPTION_APP_NOTES);
            b.type_units(KYOUHA);
            b.key(text::KEY_SPACE);
            b.replace_composition(&[("今日は", Style::Converted)]);
            b.pause(motion::WIZARD_KEY);
            b.key(text::KEY_ENTER);
            b.commit();
            b.pause(motion::WIZARD_KEY);
            b.frame.runs.clear();
            b.frame.mode = Mode::English;
            b.caption(text::CAPTION_APP_TERMINAL);
            b.pause(motion::WIZARD_KEY);
            b.type_direct("git status");
            b.pause(motion::WIZARD_PAUSE);
            b.frame.runs = vec![Run {
                text: "今日は".into(),
                style: Style::Plain,
            }];
            b.frame.mode = Mode::Japanese;
            b.caption(text::CAPTION_APP_BACK);
            b.hold();
        }
        Step::Characters => {
            let (comma, period) = match choices.value(Field::Path("punctuation")) {
                "commaPeriod" => ("，", "．"),
                "toutenPeriod" => ("、", "．"),
                "commaKuten" => ("，", "。"),
                _ => ("、", "。"),
            };
            b.caption(if keys == Keys::Kana {
                text::CAPTION_KANA
            } else {
                text::CAPTION_ROMAJI
            });
            b.type_units(KYOUHA);
            b.type_units(&[(",", comma)]);
            b.type_units(IITENKI);
            b.type_units(&[(".", period)]);
            b.hold();
        }
        Step::LiveConversion => {
            let live = choices.is_on("liveConversion");
            let delay = choices
                .value(Field::Path("liveConversionDelay"))
                .parse::<f32>()
                .unwrap_or(0.5)
                * 1000.0;
            b.type_units(WATASHINO);
            if live {
                b.frame.waiting = true;
                b.push(delay);
                b.replace_composition(&[("私の", Style::Typing)]);
                b.caption(text::CAPTION_LIVE);
                b.pause(motion::WIZARD_PAUSE);
                b.type_units(NAMAEHA);
                b.frame.waiting = true;
                b.push(delay);
                b.replace_composition(&[("私の名前は", Style::Typing)]);
                b.hold();
            } else {
                b.type_units(NAMAEHA);
                b.caption(text::CAPTION_SPACE);
                b.pause(motion::WIZARD_PAUSE);
                b.key(text::KEY_SPACE);
                b.replace_composition(&segments(&["私の", "名前は"], 0));
                b.hold();
            }
        }
        Step::Window | Step::Appearance => {
            b.frame.runs.push(Run {
                text: "私の名前は".into(),
                style: Style::Plain,
            });
            b.type_units(NAKANODESU);
            b.key(text::KEY_SPACE);
            b.replace_composition(&segments(&["中野です"], 0));
            b.popup(Some(candidates(
                branch_map,
                &["私の", "名前は", "中野です"],
                2,
                &NAME_ALTERNATIVES,
                0,
            )));
            b.pause(motion::WIZARD_PAUSE);
            b.key(text::KEY_DOWN);
            b.replace_composition(&segments(&["中のです"], 0));
            b.popup(Some(candidates(
                branch_map,
                &["私の", "名前は", "中のです"],
                2,
                &NAME_ALTERNATIVES,
                1,
            )));
            b.pause(motion::WIZARD_PAUSE);
            b.key(text::KEY_UP);
            b.replace_composition(&segments(&["中野です"], 0));
            b.popup(Some(candidates(
                branch_map,
                &["私の", "名前は", "中野です"],
                2,
                &NAME_ALTERNATIVES,
                0,
            )));
            b.hold();
            b.key(text::KEY_ENTER);
            b.commit();
            b.pause(motion::WIZARD_PAUSE);
        }
        Step::Focus => {
            b.type_units(WATASHINO);
            b.type_units(NAMAEHA);
            b.type_units(NAKANODESU);
            b.key(text::KEY_SPACE);
            let start = match choices.value(Field::Path("initialFocus")) {
                "start" => 0,
                _ => 2,
            };
            let alternatives: [&[&str]; 3] = [
                &["私の", "渡しの", "わたしの"],
                &["名前は", "名まえは", "なまえは"],
                &NAME_ALTERNATIVES,
            ];
            let show = |b: &mut Builder, focused: usize| {
                b.replace_composition(&segments(&NAME_COLUMNS, focused));
                b.popup(Some(candidates(
                    branch_map,
                    &NAME_COLUMNS,
                    focused,
                    alternatives[focused],
                    0,
                )));
            };
            show(&mut b, start);
            b.caption(text::CAPTION_FOCUS);
            b.hold();
            let (key, order) = if start == 0 {
                (text::KEY_RIGHT, [1, 2])
            } else {
                (text::KEY_LEFT, [1, 0])
            };
            for focused in order {
                b.key(key);
                show(&mut b, focused);
                b.pause(motion::WIZARD_PAUSE);
            }
        }
        Step::Correction => {
            let corrects = matches!(
                choices.value(Field::Correction),
                "cautious" | "standard" | "aggressive"
            );
            b.caption(text::CAPTION_TYPO);
            b.type_units(ARIGATOU_TYPO);
            b.pause(motion::WIZARD_PAUSE);
            if corrects {
                b.replace_composition(&[("ありがと", Style::Typing), ("う", Style::Corrected)]);
                b.caption(text::CAPTION_CORRECTED);
                b.pause(motion::WIZARD_PAUSE);
                b.key(text::KEY_SPACE);
                b.replace_composition(&segments(&["ありがとう"], 0));
            } else {
                b.key(text::KEY_SPACE);
                b.replace_composition(&segments(&["有難おう"], 0));
                b.caption(text::CAPTION_NOT_CORRECTED);
            }
            b.hold();
        }
        Step::Features => features(&mut b, choices, today, branch_map),
        Step::Extras | Step::Done => {}
    }
    b.finish()
}

/// 便利な機能を順に見せる(オフの機能は，変換しても出ないことを見せる)
fn features(b: &mut Builder, choices: &Choices, today: Today, branch_map: bool) {
    let on = |path| choices.is_on(path);
    // 連想: 変換した語から ⇧↑ で続く語を出す
    b.caption(text::ASSOCIATION);
    b.type_units(TOUKYOU);
    b.key(text::KEY_SPACE);
    b.replace_composition(&segments(&["東京"], 0));
    b.popup(Some(candidates(
        branch_map,
        &["東京"],
        0,
        &["東京", "今日"],
        0,
    )));
    b.pause(motion::WIZARD_PAUSE);
    if on("association") {
        b.key(text::KEY_ASSOCIATE);
        b.popup(Some(list(&["タワー", "駅", "都", "大学"], 0, Some("東京"))));
        b.pause(motion::WIZARD_PAUSE);
        b.key(text::KEY_DOWN);
        b.replace_composition(&[("東京", Style::Converted), ("駅", Style::Focused)]);
        b.popup(Some(list(&["タワー", "駅", "都", "大学"], 1, Some("東京"))));
        b.hold();
    } else {
        b.caption(text::CAPTION_OFF);
        b.pause(motion::WIZARD_HOLD);
    }
    b.key(text::KEY_ENTER);
    b.commit();
    b.frame.runs.clear();
    b.pause(motion::WIZARD_PAUSE);

    // 計算: 式を打って「=」で答え
    b.caption(text::CALCULATION);
    b.type_units(CALCULATION);
    b.key(text::KEY_SPACE);
    if on("calculation") {
        b.replace_composition(&segments(&["7"], 0));
        b.popup(Some(list(&["7", "1+2*3=7", "1+2*3="], 0, None)));
    } else {
        b.replace_composition(&segments(&["1+2*3="], 0));
        b.caption(text::CAPTION_OFF);
    }
    b.pause(motion::WIZARD_HOLD);
    b.key(text::KEY_ENTER);
    b.commit();
    b.frame.runs.clear();
    b.pause(motion::WIZARD_PAUSE);

    // 郵便番号: 区切りのある番号を住所に
    b.caption(text::POSTAL_CODE);
    b.type_units(POSTAL);
    b.key(text::KEY_SPACE);
    if on("postalCodeConversion") {
        b.replace_composition(&segments(&["東京都千代田区千代田"], 0));
        b.popup(Some(list(&["東京都千代田区千代田", "100-0001"], 0, None)));
    } else {
        b.replace_composition(&segments(&["100-0001"], 0));
        b.caption(text::CAPTION_OFF);
    }
    b.pause(motion::WIZARD_HOLD);
    b.key(text::KEY_ENTER);
    b.commit();
    b.frame.runs.clear();
    b.pause(motion::WIZARD_PAUSE);

    // 日付: 「きょう」を今日の日付に
    b.caption(text::DATE);
    b.type_units(KYOU);
    b.key(text::KEY_SPACE);
    b.replace_composition(&segments(&["今日"], 0));
    let mut dates = vec!["今日".to_string(), "京".to_string()];
    if on("dateConversion") {
        let Today {
            year,
            month,
            day,
            weekday,
        } = today;
        dates.extend([
            format!("{year}/{month}/{day}"),
            format!("{year}年{month}月{day}日"),
            format!(
                "令和{}年{month}月{day}日",
                year.saturating_sub(REIWA_OFFSET)
            ),
            format!(
                "{month}/{day}({})",
                WEEKDAYS[usize::from(weekday) % WEEKDAYS.len()]
            ),
        ]);
    }
    let entries: Vec<&str> = dates.iter().map(String::as_str).collect();
    b.popup(Some(list(&entries, 0, None)));
    b.pause(motion::WIZARD_PAUSE);
    if on("dateConversion") {
        for selected in [1, 2, 3] {
            b.key(text::KEY_DOWN);
            let shown = entries[selected + 1];
            b.replace_composition(&[(shown, Style::Focused)]);
            b.popup(Some(list(&entries, selected + 1, None)));
        }
        b.hold();
    } else {
        b.caption(text::CAPTION_OFF);
        b.pause(motion::WIZARD_HOLD);
    }
    b.key(text::KEY_ENTER);
    b.commit();
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wizard::{Read, SWITCH_TOGGLE};
    use serde_json::{json, Value};
    use std::collections::HashMap;

    struct Table(HashMap<&'static str, Value>);

    impl Read for Table {
        fn value(&self, path: &str) -> Option<&Value> {
            self.0.get(path)
        }
        fn is_default(&self, _: &str) -> bool {
            true
        }
    }

    const TODAY: Today = Today {
        year: 2026,
        month: 10,
        day: 28,
        weekday: 3,
    };

    fn choices() -> Choices {
        Choices::load(&Table(HashMap::from([
            ("liveConversion", json!(true)),
            ("inputStyle", json!("romaji")),
            ("typoCorrection", json!("standard")),
            ("association", json!(true)),
            ("calculation", json!(true)),
            ("postalCodeConversion", json!(true)),
            ("dateConversion", json!(true)),
        ])))
    }

    fn text_of(frame: &Frame) -> String {
        frame.runs.iter().map(|run| run.text.as_str()).collect()
    }

    fn frames(script: &Script) -> Vec<&Frame> {
        (0..script.beats.len())
            .filter_map(|beat| script.frame(beat))
            .collect()
    }

    #[test]
    fn ローマ字を1文字ずつ打ってかなにする() {
        let script = script(Step::Welcome, &choices(), TODAY);
        let texts: Vec<String> = frames(&script).into_iter().map(text_of).collect();
        assert_eq!(texts[0], "y");
        assert_eq!(texts[1], "よ");
        assert_eq!(texts[2], "よう");
        assert_eq!(text_of(script.result().unwrap()), "ようこそ");
        assert_eq!(script.result().unwrap().runs[0].style, Style::Plain);
    }

    #[test]
    fn 台本を繰り返す() {
        let script = script(Step::Welcome, &choices(), TODAY);
        let total = script.total();
        let first = script.position(10.0).unwrap();
        let again = script.position(total + 10.0).unwrap();
        assert_eq!(first.beat, again.beat);
        assert!(first.remaining > 0.0);
    }

    #[test]
    fn ライブ変換は選んだ時間だけ待ってから漢字にする() {
        let mut choices = choices();
        choices.select(Field::Path("liveConversionDelay"), "0.8");
        let script = script(Step::LiveConversion, &choices, TODAY);
        let waiting = script.beats.iter().find(|beat| beat.frame.waiting).unwrap();
        assert_eq!(waiting.duration, 800.0);
        assert_eq!(text_of(script.result().unwrap()), "私の名前は");
        choices.set_toggle("liveConversion", false);
        let off = super::script(Step::LiveConversion, &choices, TODAY);
        assert!(off.beats.iter().all(|beat| !beat.frame.waiting));
    }

    #[test]
    fn 候補の窓は選んだ形で出す() {
        let mut choices = choices();
        let shown = script(Step::Window, &choices, TODAY);
        assert!(matches!(
            shown.result().unwrap().popup,
            Some(Popup::Branch(_))
        ));
        choices.select(Field::Path("candidatePresentation"), "list");
        let shown = script(Step::Window, &choices, TODAY);
        assert!(matches!(
            shown.result().unwrap().popup,
            Some(Popup::List(_))
        ));
    }

    #[test]
    fn 最初に選ぶ文節を選んだ値にする() {
        let mut choices = choices();
        let focused = |choices: &Choices| {
            let script = script(Step::Focus, choices, TODAY);
            let frame = script.result().unwrap().clone();
            frame
                .runs
                .iter()
                .position(|run| run.style == Style::Focused)
                .unwrap()
        };
        assert_eq!(focused(&choices), 0);
        choices.select(Field::Path("initialFocus"), "end");
        assert_eq!(focused(&choices), 2);
    }

    #[test]
    fn 補正をオフにすると直さない() {
        let mut choices = choices();
        let corrected = |choices: &Choices| {
            script(Step::Correction, choices, TODAY)
                .beats
                .iter()
                .any(|beat| {
                    beat.frame
                        .runs
                        .iter()
                        .any(|run| run.style == Style::Corrected)
                })
        };
        assert!(corrected(&choices));
        choices.select(Field::Correction, "off");
        assert!(!corrected(&choices));
    }

    #[test]
    fn 切り替えのキーを選んだ方式にする() {
        let mut choices = choices();
        let keys = |choices: &Choices| -> Vec<&'static str> {
            script(Step::Switch, choices, TODAY)
                .beats
                .iter()
                .filter_map(|beat| beat.frame.key)
                .collect()
        };
        choices.select(Field::Switch, SWITCH_TOGGLE);
        assert_eq!(keys(&choices)[0], text::KEY_HANKAKU);
        choices.select(Field::Switch, SWITCH_HENKAN);
        assert_eq!(keys(&choices)[..2], [text::KEY_MUHENKAN, text::KEY_HENKAN]);
    }

    #[test]
    fn 日付は今日の日付を出しオフなら出さない() {
        let mut choices = choices();
        let has_date = |choices: &Choices| {
            script(Step::Features, choices, TODAY)
                .beats
                .iter()
                .any(|beat| text_of(&beat.frame).contains("2026年10月28日"))
        };
        assert!(has_date(&choices));
        assert!(script(Step::Features, &choices, TODAY)
            .beats
            .iter()
            .any(|beat| text_of(&beat.frame) == "令和8年10月28日"));
        choices.set_toggle("dateConversion", false);
        assert!(!has_date(&choices));
    }

    #[test]
    fn 句読点は選んだものにする() {
        let mut choices = choices();
        choices.select(Field::Path("punctuation"), "commaPeriod");
        let script = script(Step::Characters, &choices, TODAY);
        assert_eq!(text_of(script.result().unwrap()), "きょうは，いいてんき．");
    }

    #[test]
    fn 暦と曜日を求める() {
        // 2026-10-28T00:00:00Z
        assert_eq!(utc_fields(1_793_145_600), [2026, 10, 28, 0, 0, 0]);
        assert_eq!(utc_fields(951_782_400), [2000, 2, 29, 0, 0, 0]);
        assert_eq!(Today::from_fields([2026, 10, 28, 0, 0, 0]), TODAY);
        assert_eq!(Today::from_fields([1970, 1, 1, 0, 0, 0]).weekday, 4);
    }

    #[test]
    fn アプリを切り替えるとモードが変わる() {
        let script = script(Step::AppModes, &choices(), TODAY);
        let modes: Vec<Mode> = frames(&script).iter().map(|frame| frame.mode).collect();
        assert!(modes.contains(&Mode::English));
        assert_eq!(
            script.result().map(|frame| frame.mode),
            Some(Mode::Japanese)
        );
    }

    #[test]
    fn 最後のページには実演が無い() {
        assert!(script(Step::Done, &choices(), TODAY).is_empty());
    }
}
