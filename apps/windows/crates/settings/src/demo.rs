#![forbid(unsafe_code)]

//! 初期設定の実演の台本(macOS の DemoScripts と同じ)．入力欄の文字(確定した文字と組み立て中の文字)と，その下に出す
//! 候補の窓(分岐図・一覧・案内)とモード表示を，時間で切り替わるコマの並びにする．選んでいる値で中身を変える．
//! 打っている途中の読みは，打ちかけのローマ字を含めて 1 キーずつ見せる．OS に依らない(描くのは app::wizard)．
//! 実演の文字は台本に書いた見本だけで，利用者の入力は使わない

use crate::strings::{windows_wizard as notes, wizard as text};
use crate::wizard::{Choices, Field, Mark, Step, SWITCH_SINGLE};
use candidate_ui::scene::sample;
use ipc::{
    AssociationHeading, BranchColumn, BranchMap, CandidateEntry, CandidateFocus, CandidateList,
    CommandKind, Note, NoteTone,
};
use tokens::motion::onboarding as motion;

/// 組み立て中の文字の見え方(下線の種類)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Style {
    /// 打っている読み(細い下線)
    Reading,
    /// 変換した文節(細い下線)
    Converted,
    /// 選んでいる文節(太い下線)
    Focused,
    /// 補正した文字(補正の色の点線)
    Correction,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Segment {
    pub text: String,
    pub style: Style,
}

/// 入力欄の下に出す窓
#[derive(Debug, Clone, PartialEq)]
pub enum Panel {
    Lattice(BranchMap),
    List(CandidateList),
    Note(Note),
}

/// 入力モード(タグに出す)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Direct,
    Japanese,
}

/// 実演の 1 コマ
#[derive(Debug, Clone, PartialEq)]
pub struct Frame {
    pub committed: String,
    pub marked: Vec<Segment>,
    pub panel: Option<Panel>,
    /// 文字の終わりの横に出すモード表示
    pub mode: Option<Mode>,
    /// 入力欄の上に出すアプリの名前(アプリを切り替える実演)
    pub application: Option<&'static str>,
    /// このコマで押したキー(入力欄の右上にキーキャップで出す)
    pub key: Option<&'static str>,
    /// このコマを見せておく時間(ミリ秒)
    pub duration: f64,
}

impl Frame {
    fn new(duration: f64) -> Self {
        Self {
            committed: String::new(),
            marked: Vec::new(),
            panel: None,
            mode: None,
            application: None,
            key: None,
            duration,
        }
    }

    fn committed(text: &str, duration: f64) -> Self {
        Self {
            committed: text.into(),
            ..Self::new(duration)
        }
    }

    fn with_mode(mut self, mode: Mode) -> Self {
        self.mode = Some(mode);
        self
    }

    fn with_key(mut self, key: &'static str) -> Self {
        self.key = Some(key);
        self
    }
}

/// 実演の台本．初めから終わりまで進んだら繰り返す
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Script {
    frames: Vec<Frame>,
}

/// 台本の今の位置
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Position {
    pub index: usize,
    /// コマに入ってからのミリ秒
    pub elapsed: f64,
    /// 次のコマまでのミリ秒
    pub remaining: f64,
}

impl Script {
    pub fn is_empty(&self) -> bool {
        self.frames.is_empty()
    }

    pub fn len(&self) -> usize {
        self.frames.len()
    }

    pub fn total(&self) -> f64 {
        self.frames.iter().map(|frame| frame.duration).sum()
    }

    /// 始めてから elapsed ミリ秒たったときの位置(繰り返す)
    pub fn position(&self, elapsed: f64) -> Option<Position> {
        let total = self.total();
        if total <= 0.0 {
            return None;
        }
        let mut time = elapsed.max(0.0) % total;
        for (index, frame) in self.frames.iter().enumerate() {
            if time < frame.duration {
                return Some(Position {
                    index,
                    elapsed: time,
                    remaining: frame.duration - time,
                });
            }
            time -= frame.duration;
        }
        None
    }

    pub fn frame(&self, index: usize) -> Option<&Frame> {
        self.frames.get(index)
    }

    /// 最後のコマ(動きを減らす設定のときはこれだけを見せる．macOS と同じ)
    pub fn last(&self) -> Option<&Frame> {
        self.frames.last()
    }
}

/// 今の日時(日付の実演に使う)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Today {
    pub year: u16,
    pub month: u16,
    pub day: u16,
    pub hour: u16,
    pub minute: u16,
    pub second: u16,
}

impl Today {
    pub fn from_fields([year, month, day, hour, minute, second]: [u16; 6]) -> Self {
        Self {
            year,
            month,
            day,
            hour,
            minute,
            second,
        }
    }
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

// MARK: - ローマ字

/// 子音(と拗音)の行．5 つは あ・い・う・え・お の段(空なら無い)
const ROWS: &[(&str, [&str; 5])] = &[
    ("", ["あ", "い", "う", "え", "お"]),
    ("k", ["か", "き", "く", "け", "こ"]),
    ("s", ["さ", "し", "す", "せ", "そ"]),
    ("t", ["た", "ち", "つ", "て", "と"]),
    ("n", ["な", "に", "ぬ", "ね", "の"]),
    ("h", ["は", "ひ", "ふ", "へ", "ほ"]),
    ("m", ["ま", "み", "む", "め", "も"]),
    ("y", ["や", "", "ゆ", "いぇ", "よ"]),
    ("r", ["ら", "り", "る", "れ", "ろ"]),
    ("w", ["わ", "うぃ", "う", "うぇ", "を"]),
    ("g", ["が", "ぎ", "ぐ", "げ", "ご"]),
    ("z", ["ざ", "じ", "ず", "ぜ", "ぞ"]),
    ("d", ["だ", "ぢ", "づ", "で", "ど"]),
    ("b", ["ば", "び", "ぶ", "べ", "ぼ"]),
    ("p", ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"]),
    ("f", ["ふぁ", "ふぃ", "ふ", "ふぇ", "ふぉ"]),
    ("v", ["ゔぁ", "ゔぃ", "ゔ", "ゔぇ", "ゔぉ"]),
    ("j", ["じゃ", "じ", "じゅ", "じぇ", "じょ"]),
    ("l", ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ"]),
    ("x", ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ"]),
    ("sh", ["しゃ", "し", "しゅ", "しぇ", "しょ"]),
    ("ch", ["ちゃ", "ち", "ちゅ", "ちぇ", "ちょ"]),
    ("ts", ["つぁ", "つぃ", "つ", "つぇ", "つぉ"]),
    ("th", ["てゃ", "てぃ", "てゅ", "てぇ", "てょ"]),
    ("dh", ["でゃ", "でぃ", "でゅ", "でぇ", "でょ"]),
    ("ky", ["きゃ", "きぃ", "きゅ", "きぇ", "きょ"]),
    ("sy", ["しゃ", "しぃ", "しゅ", "しぇ", "しょ"]),
    ("ty", ["ちゃ", "ちぃ", "ちゅ", "ちぇ", "ちょ"]),
    ("ny", ["にゃ", "にぃ", "にゅ", "にぇ", "にょ"]),
    ("hy", ["ひゃ", "ひぃ", "ひゅ", "ひぇ", "ひょ"]),
    ("my", ["みゃ", "みぃ", "みゅ", "みぇ", "みょ"]),
    ("ry", ["りゃ", "りぃ", "りゅ", "りぇ", "りょ"]),
    ("gy", ["ぎゃ", "ぎぃ", "ぎゅ", "ぎぇ", "ぎょ"]),
    ("zy", ["じゃ", "じぃ", "じゅ", "じぇ", "じょ"]),
    ("jy", ["じゃ", "じぃ", "じゅ", "じぇ", "じょ"]),
    ("dy", ["ぢゃ", "ぢぃ", "ぢゅ", "ぢぇ", "ぢょ"]),
    ("by", ["びゃ", "びぃ", "びゅ", "びぇ", "びょ"]),
    ("py", ["ぴゃ", "ぴぃ", "ぴゅ", "ぴぇ", "ぴょ"]),
    ("ly", ["ゃ", "ぃ", "ゅ", "ぇ", "ょ"]),
    ("xy", ["ゃ", "ぃ", "ゅ", "ぇ", "ょ"]),
];
const VOWELS: [char; 5] = ['a', 'i', 'u', 'e', 'o'];
/// 行に無いもの
const SPECIAL: &[(&str, &str)] = &[
    ("nn", "ん"),
    ("n'", "ん"),
    ("ltu", "っ"),
    ("xtu", "っ"),
    ("-", "ー"),
];

fn kana_of(romaji: &str) -> Option<&'static str> {
    if let Some((_, kana)) = SPECIAL.iter().find(|(keys, _)| *keys == romaji) {
        return Some(kana);
    }
    let vowel = romaji.chars().last()?;
    let column = VOWELS.iter().position(|candidate| *candidate == vowel)?;
    let consonant = &romaji[..romaji.len() - vowel.len_utf8()];
    ROWS.iter()
        .find(|(row, _)| *row == consonant)
        .map(|(_, kana)| kana[column])
        .filter(|kana| !kana.is_empty())
}

/// romaji で始まる綴りがあるか(まだ打ち続けられるか)
fn continues(romaji: &str) -> bool {
    let longer = |keys: &str| keys.len() > romaji.len() && keys.starts_with(romaji);
    SPECIAL.iter().any(|(keys, _)| longer(keys))
        || ROWS.iter().any(|(row, kana)| {
            VOWELS
                .iter()
                .zip(kana)
                .any(|(vowel, kana)| !kana.is_empty() && longer(&format!("{row}{vowel}")))
        })
}

/// keys を 1 つずつ打ったときの，組み立て中の読み(打ちかけのローマ字を含む．macOS の DemoScripts.readings)
pub fn readings(keys: &str) -> Vec<String> {
    let mut done = String::new();
    let mut pending = String::new();
    keys.chars()
        .map(|key| {
            pending.push(key);
            loop {
                if let Some(kana) = kana_of(&pending) {
                    done.push_str(kana);
                    pending.clear();
                    break;
                }
                if continues(&pending) {
                    break;
                }
                let mut chars = pending.chars();
                let Some(first) = chars.next() else { break };
                let rest: String = chars.collect();
                match rest.chars().next() {
                    // n のあとに母音・y・n 以外が来たら「ん」
                    Some(second) if first == 'n' && !"aiueoyn'".contains(second) => {
                        done.push('ん');
                    }
                    // 同じ子音が続いたら「っ」
                    Some(second) if first == second && !VOWELS.contains(&first) => {
                        done.push('っ');
                    }
                    // 綴りにならない字はそのまま
                    _ => done.push(first),
                }
                pending = rest;
                if pending.is_empty() {
                    break;
                }
            }
            format!("{done}{pending}")
        })
        .collect()
}

// MARK: - 部品

fn keystroke() -> f64 {
    f64::from(motion::KEYSTROKE)
}

fn hold() -> f64 {
    f64::from(motion::HOLD)
}

fn segments(texts: &[(&str, Style)]) -> Vec<Segment> {
    texts
        .iter()
        .map(|(text, style)| Segment {
            text: (*text).into(),
            style: *style,
        })
        .collect()
}

fn typing(keys: &str, committed: &str, mode: Option<Mode>) -> Vec<Frame> {
    readings(keys)
        .into_iter()
        .map(|reading| Frame {
            committed: committed.into(),
            marked: vec![Segment {
                text: reading,
                style: Style::Reading,
            }],
            mode,
            ..Frame::new(keystroke())
        })
        .collect()
}

fn converted(texts: &[(&str, Style)], committed: &str, panel: Option<Panel>) -> Frame {
    Frame {
        committed: committed.into(),
        marked: segments(texts),
        panel,
        ..Frame::new(hold())
    }
}

fn pause(frames: &[Frame], milliseconds: f64) -> Vec<Frame> {
    frames
        .last()
        .map(|frame| Frame {
            duration: milliseconds,
            ..frame.clone()
        })
        .into_iter()
        .collect()
}

fn entry(text: &str) -> CandidateEntry {
    CandidateEntry {
        text: text.into(),
        annotation: None,
        corrected_start: None,
        corrected_length: None,
        command: None,
        has_comment: None,
        detail: None,
    }
}

fn list(entries: Vec<CandidateEntry>, selected: usize) -> CandidateList {
    CandidateList {
        is_editing: None,
        variants: vec![],
        selected_variant: None,
        selected_entry: Some(selected as u32),
        focus: CandidateFocus::Candidate,
        position: selected as u32 + 1,
        total: entries.len() as u32,
        entries,
        note: None,
        hints: None,
        association: None,
        association_hint: None,
        association_key: None,
        homophone: None,
        shows_numbers: None,
        meaning_placement: None,
        column_length: None,
    }
}

fn note(tone: NoteTone, title: &str, subject: Option<&str>, key: &str, action: &str) -> Note {
    Note {
        tone,
        title: title.into(),
        subject: subject.map(Into::into),
        key: Some(key.into()),
        key_action: Some(action.into()),
        text: String::new(),
    }
}

fn heading(headword: &str, label: &str) -> AssociationHeading {
    AssociationHeading {
        headword: headword.into(),
        label: label.into(),
        group: 1,
        group_count: 1,
    }
}

/// 分岐図．focus の文節に候補の枝(alternatives の先頭を選ぶ)を出す
fn lattice(columns: &[(&str, &[&str])], focus: usize, uncertain: Option<usize>) -> BranchMap {
    BranchMap {
        columns: columns
            .iter()
            .enumerate()
            .map(|(index, (text, alternatives))| {
                let is_uncertain = uncertain == Some(index);
                if index == focus {
                    BranchColumn {
                        alternatives: alternatives.iter().map(|text| (*text).into()).collect(),
                        selected_alternative: Some(0),
                        is_focused: true,
                        is_uncertain,
                        ..sample::column(text)
                    }
                } else {
                    BranchColumn {
                        is_uncertain,
                        ..sample::column(text)
                    }
                }
            })
            .collect(),
        position: 1,
        total: columns.get(focus).map_or(0, |(_, list)| list.len() as u32),
        note: None,
        // 舞台の分岐図にはキーの案内を出さない(macOS の showsHints = false)
        hints: vec![],
        association: None,
        association_hint: None,
        association_key: None,
        meaning_placement: None,
        collapses_variants: None,
        collapses_detail: None,
        placed_hints: None,
    }
}

// MARK: - ページ

/// step の実演．spotlight(機能の紹介のページで見せている機能)があれば，その機能だけを(オフでも)見せる
/// app_mode は，アプリごとの入力モードのページでポインタを置いたカード(そのモードの動きを見せる)
pub fn script(
    step: Step,
    choices: &Choices,
    spotlight: Option<&str>,
    app_mode: Mark,
    today: Today,
) -> Script {
    if let Some(spot) =
        spotlight.and_then(|path| step.spots().iter().find(|spot| spot.path == path))
    {
        return Script {
            frames: spot_frames(spot.path, today),
        };
    }
    let frames = match step {
        Step::ModeSwitch => mode_switch(choices),
        Step::AppModes => app_modes(choices, app_mode),
        Step::Correction => correction(choices),
        Step::Theme => theme(),
        Step::LiveConversion => live_conversion(choices),
        Step::Presentation => presentation(choices),
        Step::Characters => characters(choices),
        // 機能の紹介のページは，オンにした機能を順に見せる
        Step::Features | Step::Extras => {
            let frames: Vec<Frame> = step
                .spots()
                .iter()
                .filter(|spot| choices.is_on(spot.path))
                .flat_map(|spot| spot_frames(spot.path, today))
                .collect();
            if frames.is_empty() {
                vec![Frame::new(hold())]
            } else {
                frames
            }
        }
    };
    Script { frames }
}

/// 日本語にするキーと英数に戻すキー(選んだ切り替え方で変わる．1 つのキーなら同じキーを押す)
fn switch_keys(choices: &Choices) -> (&'static str, &'static str) {
    if choices.value(Field::Switch) == SWITCH_SINGLE {
        (notes::DEMO_KEY_HANKAKU, notes::DEMO_KEY_HANKAKU)
    } else {
        (notes::DEMO_KEY_HENKAN, notes::DEMO_KEY_MUHENKAN)
    }
}

/// 英数で打ち，日本語にするキーで切り替えて打って変換し，英数に戻すキーで戻す(macOS の modeSwitch)
fn mode_switch(choices: &Choices) -> Vec<Frame> {
    let (to_japanese, to_direct) = switch_keys(choices);
    let english = notes::DEMO_DIRECT_TEXT;
    let mut frames = vec![Frame::new(hold() / 2.0).with_mode(Mode::Direct)];
    frames.extend(english.char_indices().map(|(index, letter)| {
        Frame::committed(&english[..index + letter.len_utf8()], keystroke()).with_mode(Mode::Direct)
    }));
    frames.push(
        Frame::committed(english, hold() / 2.0)
            .with_mode(Mode::Japanese)
            .with_key(to_japanese),
    );
    frames.extend(typing("nihongo", english, Some(Mode::Japanese)));
    frames.push(converted(&[("日本語", Style::Converted)], english, None));
    let done = format!("{english}日本語");
    frames.push(Frame::committed(&done, hold() / 2.0).with_mode(Mode::Japanese));
    frames.push(
        Frame::committed(&done, hold())
            .with_mode(Mode::Direct)
            .with_key(to_direct),
    );
    frames
}

/// アプリを切り替えたときに，モード表示が選んだカードのとおりに変わるのを見せる(macOS の appModes)
/// - IME をオフ: メモ帳で日本語を打ち，ターミナルに切り替えると英数になる
/// - IME をオン: ターミナルで英数を打ち，メモ帳に切り替えると日本語になる
/// - オンオフを記憶: メモ帳で英数に切り替えてからターミナルに移り，メモ帳に戻ると英数のまま
fn app_modes(choices: &Choices, app_mode: Mark) -> Vec<Frame> {
    let notes_app = notes::DEMO_NOTES;
    let terminal = text::DEMO_TERMINAL;
    let in_app = |frames: Vec<Frame>, application: &'static str| -> Vec<Frame> {
        frames
            .into_iter()
            .map(|frame| Frame {
                application: Some(application),
                ..frame
            })
            .collect()
    };
    // committed のあとに text を 1 字ずつ英数で打つ
    let typed = |text: &str, committed: &str| -> Vec<Frame> {
        text.char_indices()
            .map(|(index, letter)| {
                let shown = format!("{committed}{}", &text[..index + letter.len_utf8()]);
                Frame::committed(&shown, keystroke()).with_mode(Mode::Direct)
            })
            .collect()
    };
    let mut japanese = vec![Frame::new(hold() / 2.0).with_mode(Mode::Japanese)];
    japanese.extend(typing("kyouha", "", Some(Mode::Japanese)));
    japanese.push(converted(&[("今日は", Style::Converted)], "", None));
    japanese.push(Frame::committed("今日は", hold()).with_mode(Mode::Japanese));
    let mut direct = vec![Frame::new(hold() / 2.0).with_mode(Mode::Direct)];
    match app_mode {
        Mark::Japanese => {
            direct.extend(typed("ls", ""));
            direct.push(Frame::committed("ls", hold()).with_mode(Mode::Direct));
            let mut frames = in_app(direct, terminal);
            frames.extend(in_app(japanese, notes_app));
            frames
        }
        Mark::Both => {
            let (_, to_direct) = switch_keys(choices);
            japanese.push(
                Frame::committed("今日は", hold() / 2.0)
                    .with_mode(Mode::Direct)
                    .with_key(to_direct),
            );
            japanese.extend(typed("OK", "今日は"));
            let mut frames = in_app(japanese, notes_app);
            direct.extend(typed("ls", ""));
            frames.extend(in_app(direct, terminal));
            frames.extend(in_app(
                vec![Frame::committed("今日はOK", hold()).with_mode(Mode::Direct)],
                notes_app,
            ));
            frames
        }
        Mark::Direct => {
            let mut frames = in_app(japanese, notes_app);
            direct.extend(typed("git status", ""));
            direct.push(Frame::committed("git status", hold()).with_mode(Mode::Direct));
            frames.extend(in_app(direct, terminal));
            frames
        }
    }
}

fn correction(choices: &Choices) -> Vec<Frame> {
    let keys = "yorosikuonagaisimasu";
    let mut frames = typing(keys, "", None);
    let delay = choices
        .correction_delay()
        .map_or(hold() / 2.0, |seconds| seconds * 1000.0);
    frames.extend(pause(&frames, delay));
    let typed = readings(keys).pop().unwrap_or_default();
    match choices.value(Field::Correction) {
        "off" => frames.push(converted(
            &[("よろしくおながいします", Style::Converted)],
            "",
            None,
        )),
        "cautious" => {
            let shown = note(
                NoteTone::Suggestion,
                notes::NOTE_SUGGESTION,
                Some("よろしくお願いします"),
                notes::KEY_TAB,
                notes::NOTE_FIX,
            );
            frames.push(converted(
                &[("よろしくおながいします", Style::Converted)],
                "",
                Some(Panel::Note(shown)),
            ));
            frames.push(converted(
                &[("よろしくお願いします", Style::Converted)],
                "",
                None,
            ));
        }
        _ => {
            let shown = note(
                NoteTone::Correction,
                notes::NOTE_CORRECTION,
                Some(&typed),
                notes::KEY_ESCAPE,
                notes::NOTE_REVERT,
            );
            frames.push(converted(
                &[
                    ("よろしく", Style::Converted),
                    ("お願い", Style::Correction),
                    ("します", Style::Converted),
                ],
                "",
                Some(Panel::Note(shown)),
            ));
        }
    }
    frames
}

/// 選んだテーマの見本の分岐図(1 コマ)
fn theme() -> Vec<Frame> {
    let map = BranchMap {
        hints: vec![],
        ..sample::branch()
    };
    vec![converted(
        &[
            ("私の", Style::Converted),
            ("名前は", Style::Converted),
            ("中野です", Style::Focused),
        ],
        "",
        Some(Panel::Lattice(map)),
    )]
}

fn live_conversion(choices: &Choices) -> Vec<Frame> {
    let mut frames = typing("kyouhaiitenkidesune", "", None);
    if choices.live() {
        frames.extend(pause(
            &frames,
            choices.seconds(crate::wizard::LIVE_DELAY) * 1000.0,
        ));
        frames.push(converted(
            &[("今日はいい天気ですね", Style::Converted)],
            "",
            None,
        ));
    } else {
        frames.extend(pause(&frames, hold() / 2.0));
        let columns: [(&str, &[&str]); 3] = [
            ("今日は", &["今日は", "京は", "教派"]),
            ("いい", &["いい", "良い", "言い"]),
            ("天気ですね", &["天気ですね", "転機ですね"]),
        ];
        frames.push(converted(
            &[
                ("今日は", Style::Focused),
                ("いい", Style::Converted),
                ("天気ですね", Style::Converted),
            ],
            "",
            Some(Panel::Lattice(lattice(&columns, 0, None))),
        ));
    }
    frames.push(Frame::committed("今日はいい天気ですね", hold() / 2.0));
    frames
}

fn presentation(choices: &Choices) -> Vec<Frame> {
    let mut frames = typing("watasinonamaehanakanodesu", "", None);
    frames.extend(pause(&frames, hold() / 3.0));
    let focus = match choices.value(Field::Path("initialFocus")) {
        "start" => 0,
        _ => 2,
    };
    let names = ["私の", "名前は", "中野です"];
    let marked: Vec<(&str, Style)> = names
        .iter()
        .enumerate()
        .map(|(index, text)| {
            let style = if index == focus {
                Style::Focused
            } else {
                Style::Converted
            };
            (*text, style)
        })
        .collect();
    match choices.value(Field::Path("candidatePresentation")) {
        "segmentList" => {
            let entries = if focus == 0 {
                [names[0], "わたしの", "ワタシノ"]
            } else {
                [names[2], "中のです", "なかのです"]
            };
            let shown = list(entries.iter().map(|text| entry(text)).collect(), 0);
            frames.push(converted(&marked, "", Some(Panel::List(shown))));
        }
        "list" => {
            let entries = [
                "私の名前は中野です",
                "私の名前は中のです",
                "わたしのなまえはなかのです",
            ];
            let shown = list(entries.iter().map(|text| entry(text)).collect(), 0);
            frames.push(converted(
                &[(entries[0], Style::Focused)],
                "",
                Some(Panel::List(shown)),
            ));
        }
        _ => {
            let columns: [(&str, &[&str]); 3] = [
                ("私の", &["私の", "渡しの", "わたしの"]),
                ("名前は", &["名前は", "なまえは"]),
                (
                    "中野です",
                    &["中野です", "中のです", "仲のです", "那珂のです"],
                ),
            ];
            frames.push(converted(
                &marked,
                "",
                Some(Panel::Lattice(lattice(&columns, focus, Some(2)))),
            ));
        }
    }
    frames
}

/// 句読点・括弧・スラッシュ・数字の幅を選んだものにして，1 字ずつ入れる
fn characters(choices: &Choices) -> Vec<Frame> {
    let value = |path: &'static str| choices.value(Field::Path(path));
    let (comma, period) = match value("punctuation") {
        "commaPeriod" => ("，", "．"),
        "toutenPeriod" => ("、", "．"),
        "commaKuten" => ("，", "。"),
        _ => ("、", "。"),
    };
    let (open, close) = match value("brackets") {
        "square" => ("［", "］"),
        _ => ("「", "」"),
    };
    let slash = match value("slash") {
        "slash" => "／",
        _ => "・",
    };
    let fullwidth = value("numberWidth") == "fullwidth";
    let number = |digits: &str| -> String {
        if fullwidth {
            digits
                .chars()
                .map(|digit| char::from_u32(digit as u32 + 0xFEE0).unwrap_or(digit))
                .collect()
        } else {
            digits.into()
        }
    };
    let shown = format!(
        "{open}はい{close}{comma}{}時{slash}{}時{period}",
        number("10"),
        number("11")
    );
    let mut frames: Vec<Frame> = shown
        .char_indices()
        .map(|(index, letter)| {
            Frame::committed(&shown[..index + letter.len_utf8()], keystroke() * 2.0)
        })
        .collect();
    frames.push(Frame::committed(&shown, hold()));
    frames
}

// MARK: - 機能ごとの実演

/// 一覧の候補を from から to まで 1 つずつ選び，最後に確定する(commit が None なら確定しない)．
/// command はコマンドの候補の位置．一覧では種類のアイコンとタグを付け，選んでいるあいだは確定のキーで動くことを出す
struct Choosing<'a> {
    entries: &'a [&'a str],
    to: usize,
    heading: Option<AssociationHeading>,
    command: Option<usize>,
    commit: Option<&'a str>,
}

fn choosing(choosing: Choosing) -> Vec<Frame> {
    let rows: Vec<CandidateEntry> = choosing
        .entries
        .iter()
        .enumerate()
        .map(|(index, text)| {
            if Some(index) == choosing.command {
                CandidateEntry {
                    annotation: Some(candidate_ui::strings::COMMAND.into()),
                    command: Some(CommandKind::OpenApplication),
                    ..entry(text)
                }
            } else {
                entry(text)
            }
        })
        .collect();
    let mut frames = Vec::new();
    for selected in 0..=choosing.to {
        let chooses_command = Some(selected) == choosing.command;
        let mut shown = list(rows.clone(), selected);
        shown.association = choosing.heading.clone();
        if chooses_command {
            shown.note = Some(Note {
                key: Some(notes::KEY_ENTER.into()),
                key_action: Some(notes::NOTE_RUN.into()),
                ..note(NoteTone::Info, "", None, "", "")
            });
        }
        let text = if chooses_command {
            format!("{}{}", notes::COMMAND_MARK, choosing.entries[selected])
        } else {
            choosing.entries[selected].to_string()
        };
        let mut frame = converted(&[(&text, Style::Focused)], "", Some(Panel::List(shown)));
        // 選んでいる候補を動かすあいだは短く，最後の候補は長く見せる
        if selected != choosing.to {
            frame.duration = hold() / 2.0;
        }
        frames.push(frame);
    }
    if let Some(commit) = choosing.commit {
        frames.push(Frame::committed(commit, hold()));
    }
    frames
}

/// 打ちかけの字をそのまま 1 字ずつ見せる(数字や記号はローマ字の組み立てを通さない)
fn typing_literally(shown: &str) -> Vec<Frame> {
    shown
        .char_indices()
        .map(|(index, letter)| Frame {
            marked: segments(&[(&shown[..index + letter.len_utf8()], Style::Reading)]),
            ..Frame::new(keystroke() * 1.5)
        })
        .collect()
}

/// 一つの機能の実演．オンかどうかによらず，その機能が何をするかを見せる(macOS の DemoScripts.frames(for:))
pub fn spot_frames(path: &str, today: Today) -> Vec<Frame> {
    let pick = |entries: &[&str], to: usize, commit: Option<&str>| {
        choosing(Choosing {
            entries,
            to,
            heading: None,
            command: None,
            commit,
        })
    };
    match path {
        "association" => {
            let mut frames = typing("kawaii", "", None);
            frames.extend(pick(&["可愛い", "かわいい", "カワイイ"], 0, None));
            frames.extend(choosing(Choosing {
                entries: &["愛らしい", "可憐", "愛くるしい", "キュート"],
                to: 3,
                heading: Some(heading("可愛い", text::ASSOCIATION)),
                command: None,
                commit: Some("キュート"),
            }));
            frames
        }
        "calculation" => {
            let mut frames = typing_literally("1+2*3=");
            frames.extend(pick(&["7", "1+2*3=7"], 1, Some("1+2*3=7")));
            frames
        }
        "postalCodeConversion" => {
            let mut frames = typing_literally("100-0001");
            frames.extend(pick(
                &["東京都千代田区千代田", "100-0001"],
                0,
                Some("東京都千代田区千代田"),
            ));
            frames
        }
        "dateConversion" => {
            let long = format!("{}年{}月{}日", today.year, today.month, today.day);
            let short = format!("{}/{:02}/{:02}", today.year, today.month, today.day);
            let mut frames = typing("kyou", "", None);
            frames.extend(pick(&[&long, &short, "今日"], 1, Some(&short)));
            frames
        }
        "looseReadings" => {
            let example = crate::strings::extras::LOOSE_READINGS_EXAMPLE.1;
            let mut frames = typing("shanbu-", "", None);
            frames.extend(pick(
                &["シャンブー", example, "しゃんぶー"],
                1,
                Some(example),
            ));
            frames
        }
        "phoneticSpelling" => {
            let example = crate::strings::extras::PHONETIC_SPELLING_EXAMPLE.1;
            let mut frames = typing("kokoa", "", None);
            frames.extend(pick(&["ココア", example, "ここあ"], 1, Some(example)));
            frames
        }
        "handShiftCorrection" => {
            // 右手も左手も 1 キー右にずれたまま「konnichiha」と打った(QWERTY)
            let keys = "lpmmovjojs";
            let mut frames = typing(keys, "", None);
            frames.extend(pause(&frames, hold() / 2.0));
            let shown = note(
                NoteTone::Correction,
                notes::NOTE_CORRECTION,
                Some(keys),
                notes::KEY_ESCAPE,
                notes::NOTE_REVERT,
            );
            frames.push(converted(
                &[("こんにちは", Style::Correction)],
                "",
                Some(Panel::Note(shown)),
            ));
            frames.push(Frame::committed("こんにちは", hold()));
            frames
        }
        "conversionMacros" => {
            let mut frames = typing("toukyou", "", None);
            frames.extend(pick(&["東京", "とうきょう", "トウキョウ"], 0, None));
            frames.extend(choosing(Choosing {
                entries: &[
                    "「東京」",
                    "『東京』",
                    "【東京】",
                    "（東京）",
                    "東京（とうきょう）",
                ],
                to: 4,
                heading: Some(heading("東京", notes::MACRO_LABEL)),
                command: None,
                commit: Some("東京（とうきょう）"),
            }));
            frames
        }
        "dynamicDictionary" => {
            // 読み「ts」・単語「{datetime:YYYY-MM-DD hh:mm:ss}」を登録したとき
            let stamp = format!(
                "{:04}-{:02}-{:02} {:02}:{:02}:{:02}",
                today.year, today.month, today.day, today.hour, today.minute, today.second
            );
            let mut frames = typing_literally("ts");
            frames.extend(pick(&[&stamp, "ts", "TS"], 0, Some(&stamp)));
            frames
        }
        "launcherCommands" => {
            // 第 1 候補は語のまま．コマンドは 2 番目に並び，選んで確定したときだけ動く(文字は入らない)
            let mut frames = typing("kuro-do", "", None);
            frames.extend(choosing(Choosing {
                entries: &["クロード", text::COMMANDS_EXAMPLE, "黒戸"],
                to: 1,
                heading: None,
                command: Some(1),
                commit: None,
            }));
            frames.push(Frame::new(hold()));
            frames
        }
        _ => vec![Frame::new(hold())],
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::wizard::{Read, LIVE, LIVE_DELAY};
    use serde_json::{json, Value};
    use std::collections::HashMap;

    struct Table(HashMap<&'static str, Value>);

    impl Read for Table {
        fn value(&self, path: &str) -> Option<&Value> {
            self.0.get(path)
        }
    }

    const TODAY: Today = Today {
        year: 2026,
        month: 10,
        day: 28,
        hour: 9,
        minute: 5,
        second: 7,
    };

    fn choices() -> Choices {
        Choices::load(&Table(HashMap::from([
            ("correctionDelay", json!(0.8)),
            ("association", json!(true)),
            ("calculation", json!(true)),
        ])))
    }

    fn text_of(frame: &Frame) -> String {
        frame.committed.clone()
            + &frame
                .marked
                .iter()
                .map(|segment| segment.text.as_str())
                .collect::<String>()
    }

    fn frames(script: &Script) -> Vec<&Frame> {
        (0..script.len())
            .filter_map(|index| script.frame(index))
            .collect()
    }

    fn last(step: Step, choices: &Choices) -> Frame {
        script(step, choices, None, Mark::Direct, TODAY)
            .last()
            .unwrap()
            .clone()
    }

    /// 最後に窓を出したコマの窓
    fn last_panel(step: Step, choices: &Choices) -> Panel {
        frames(&script(step, choices, None, Mark::Direct, TODAY))
            .into_iter()
            .rev()
            .find_map(|frame| frame.panel.clone())
            .unwrap()
    }

    #[test]
    fn ローマ字は打ちかけのまま見せる() {
        assert_eq!(
            readings("kyouha"),
            ["k", "ky", "きょ", "きょう", "きょうh", "きょうは"]
        );
        assert_eq!(readings("nihongo").last().unwrap(), "にほんご");
        assert_eq!(readings("nihongo")[5], "にほんg");
        assert_eq!(
            readings("kyouhaiitenkidesune").last().unwrap(),
            "きょうはいいてんきですね"
        );
        assert_eq!(
            readings("yorosikuonagaisimasu").last().unwrap(),
            "よろしくおながいします"
        );
        assert_eq!(readings("shanbu-").last().unwrap(), "しゃんぶー");
        assert_eq!(readings("lpmmovjojs").last().unwrap(), "lpっもvじょjs");
        assert_eq!(readings("kokoa").last().unwrap(), "ここあ");
    }

    #[test]
    fn 台本を繰り返す() {
        let script = script(Step::ModeSwitch, &choices(), None, Mark::Direct, TODAY);
        let total = script.total();
        let first = script.position(10.0).unwrap();
        let again = script.position(total + 10.0).unwrap();
        assert_eq!(first.index, again.index);
        assert!(first.remaining > 0.0);
    }

    #[test]
    fn 補正の強さで直し方が変わる() {
        let mut choices = choices();
        let shown = |choices: &Choices| last_panel(Step::Correction, choices);
        let Panel::Note(standard) = shown(&choices) else {
            panic!("案内ではない")
        };
        assert_eq!(standard.tone, NoteTone::Correction);
        assert_eq!(standard.subject.as_deref(), Some("よろしくおながいします"));
        assert!(last(Step::Correction, &choices)
            .marked
            .iter()
            .any(|segment| segment.style == Style::Correction));
        choices.select(Field::Correction, "cautious");
        let Panel::Note(cautious) = shown(&choices) else {
            panic!("案内ではない")
        };
        assert_eq!(cautious.tone, NoteTone::Suggestion);
        assert_eq!(
            text_of(&last(Step::Correction, &choices)),
            "よろしくお願いします"
        );
        choices.select(Field::Correction, "off");
        let off = script(Step::Correction, &choices, None, Mark::Direct, TODAY);
        assert!(frames(&off).iter().all(|frame| frame.panel.is_none()));
        assert_eq!(text_of(off.last().unwrap()), "よろしくおながいします");
    }

    #[test]
    fn 補正は補正を探す時間だけ待つ() {
        let script = script(Step::Correction, &choices(), None, Mark::Direct, TODAY);
        assert!(frames(&script).iter().any(|frame| frame.duration == 800.0));
    }

    #[test]
    fn ライブ変換は選んだ時間だけ待ってから漢字にする() {
        let mut choices = choices();
        choices.set_seconds(LIVE_DELAY, 1.2);
        let on = script(Step::LiveConversion, &choices, None, Mark::Direct, TODAY);
        assert!(frames(&on).iter().any(|frame| frame.duration == 1200.0));
        assert!(frames(&on).iter().all(|frame| frame.panel.is_none()));
        choices.select(LIVE, "false");
        let Panel::Lattice(map) = last_panel(Step::LiveConversion, &choices) else {
            panic!("分岐図ではない")
        };
        assert_eq!(map.columns[0].alternatives, ["今日は", "京は", "教派"]);
    }

    #[test]
    fn 候補の出し方ごとに違う窓を出す() {
        let mut choices = choices();
        let mut shown = Vec::new();
        for value in ["automatic", "segmentList", "list"] {
            choices.select(Field::Path("candidatePresentation"), value);
            shown.push(last_panel(Step::Presentation, &choices));
        }
        assert!(matches!(shown[0], Panel::Lattice(_)));
        let (Panel::List(segment), Panel::List(whole)) = (&shown[1], &shown[2]) else {
            panic!("一覧ではない")
        };
        assert_eq!(segment.entries[0].text, "私の");
        assert_eq!(whole.entries[0].text, "私の名前は中野です");
    }

    #[test]
    fn 最初に選ぶ文節を選んだ値にする() {
        let mut choices = choices();
        let focused = |choices: &Choices| {
            last(Step::Presentation, choices)
                .marked
                .iter()
                .position(|segment| segment.style == Style::Focused)
                .unwrap()
        };
        assert_eq!(focused(&choices), 0);
        choices.select(Field::Path("initialFocus"), "end");
        assert_eq!(focused(&choices), 2);
        choices.select(Field::Path("candidatePresentation"), "segmentList");
        let Panel::List(segment) = last_panel(Step::Presentation, &choices) else {
            panic!("一覧ではない")
        };
        assert_eq!(segment.entries[0].text, "中野です");
    }

    #[test]
    fn 入力する文字は選んだ文字にする() {
        let mut choices = choices();
        assert_eq!(
            text_of(&last(Step::Characters, &choices)),
            "「はい」、10時・11時。"
        );
        choices.select(Field::Path("punctuation"), "commaPeriod");
        choices.select(Field::Path("brackets"), "square");
        choices.select(Field::Path("slash"), "slash");
        choices.select(Field::Path("numberWidth"), "fullwidth");
        assert_eq!(
            text_of(&last(Step::Characters, &choices)),
            "［はい］，１０時／１１時．"
        );
    }

    #[test]
    fn アプリを切り替えるとモードが選んだカードのとおりに変わる() {
        let last = |mark: Mark| {
            script(Step::AppModes, &choices(), None, mark, TODAY)
                .last()
                .unwrap()
                .clone()
        };
        // IME をオフ: ターミナルに切り替えると英数
        let off = last(Mark::Direct);
        assert_eq!(off.application, Some(text::DEMO_TERMINAL));
        assert_eq!(off.mode, Some(Mode::Direct));
        // IME をオン: メモ帳に切り替えると日本語
        let on = last(Mark::Japanese);
        assert_eq!(on.application, Some(notes::DEMO_NOTES));
        assert_eq!(on.mode, Some(Mode::Japanese));
        // 記憶: メモ帳で英数にしてから戻ると英数のまま
        let remembers = script(Step::AppModes, &choices(), None, Mark::Both, TODAY);
        assert!(frames(&remembers)
            .iter()
            .any(|frame| frame.key.is_some() && frame.application == Some(notes::DEMO_NOTES)));
        let back = remembers.last().unwrap();
        assert_eq!(back.application, Some(notes::DEMO_NOTES));
        assert_eq!(back.mode, Some(Mode::Direct));
    }

    #[test]
    fn 英数に戻すキーは切り替え方で変わる() {
        let mut choices = choices();
        let back = |choices: &Choices| {
            script(Step::ModeSwitch, choices, None, Mark::Direct, TODAY)
                .last()
                .unwrap()
                .key
        };
        assert_eq!(back(&choices), Some(notes::DEMO_KEY_MUHENKAN));
        choices.select(Field::Switch, SWITCH_SINGLE);
        assert_eq!(back(&choices), Some(notes::DEMO_KEY_HANKAKU));
    }

    #[test]
    fn 機能ごとの実演はオフでもその機能を見せる() {
        let choices = choices();
        for spot in crate::wizard::FEATURES.iter().chain(crate::wizard::EXTRAS) {
            let step = if crate::wizard::FEATURES.contains(spot) {
                Step::Features
            } else {
                Step::Extras
            };
            let shown = script(step, &choices, Some(spot.path), Mark::Direct, TODAY);
            assert!(shown.len() > 1, "{}", spot.path);
        }
        let date = script(
            Step::Features,
            &choices,
            Some("dateConversion"),
            Mark::Direct,
            TODAY,
        );
        assert_eq!(date.last().unwrap().committed, "2026/10/28");
        let stamp = script(
            Step::Extras,
            &choices,
            Some("dynamicDictionary"),
            Mark::Direct,
            TODAY,
        );
        assert_eq!(stamp.last().unwrap().committed, "2026-10-28 09:05:07");
        let commands = script(
            Step::Extras,
            &choices,
            Some("launcherCommands"),
            Mark::Direct,
            TODAY,
        );
        assert!(frames(&commands)
            .iter()
            .any(|frame| text_of(frame) == "▶ Claude を開く"));
    }

    #[test]
    fn 試験的な機能はオンにしたものを見せる() {
        let mut choices = choices();
        let off = script(Step::Extras, &choices, None, Mark::Direct, TODAY);
        assert_eq!(off.len(), 1);
        choices.set_toggle("phoneticSpelling", true);
        let on = script(Step::Extras, &choices, None, Mark::Direct, TODAY);
        assert!(frames(&on).iter().any(|frame| text_of(frame) == "cocoa"));
    }

    #[test]
    fn 暦を求める() {
        // 2026-10-28T00:00:00Z
        assert_eq!(utc_fields(1_793_145_600), [2026, 10, 28, 0, 0, 0]);
        assert_eq!(utc_fields(951_782_400), [2000, 2, 29, 0, 0, 0]);
    }
}
