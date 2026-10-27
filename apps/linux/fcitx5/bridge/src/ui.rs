//! エンジンが候補ウィンドウへ送る指示(UiCommand)を受け取り，Fcitx 5 の候補の一覧に出せる形にして持つ．
//! Windows では別のプロセスの候補ウィンドウが受け取る指示を，Linux ではアドオンが受け取って Fcitx 5 に描かせる(ADR 0012)

use ipc::framing::read_message;
use ipc::timing::RECONNECT_MILLISECONDS;
use ipc::{BranchMap, CandidateList, UiCommand};
use std::io::Write;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

/// Fcitx 5 に出す候補の一覧と案内
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Panel {
    pub candidates: Vec<String>,
    /// 選んでいる候補(candidates の位置)
    pub selected: Option<usize>,
    /// 候補の上に出す案内(注釈・誤用の注意など)
    pub note: String,
    /// 候補の下に出すキーの案内
    pub hints: String,
    /// 1 つ目の候補の位置と，候補の総数(「3 / 12」)
    pub position: Option<(u32, u32)>,
}

impl Panel {
    /// 指示を当てる．候補に関係しない指示(書体・モードの札・手書き)は持たない
    pub fn apply(&mut self, command: UiCommand) {
        match command {
            UiCommand::ShowCandidates { list, .. } => *self = Self::from_list(list),
            UiCommand::ShowBranchMap { map, .. } => *self = Self::from_map(map),
            UiCommand::Hide => *self = Self::default(),
            // Fcitx5 の案内は文字の行なので，部品を 1 行の文にしたものを出す
            UiCommand::ShowNote { note, .. } => self.note = note.text,
            _ => {}
        }
    }

    fn from_list(list: CandidateList) -> Self {
        Self {
            candidates: list.entries.into_iter().map(|entry| entry.text).collect(),
            selected: list.selected_entry.map(|index| index as usize),
            note: list.note.map(|note| note.text).unwrap_or_default(),
            hints: String::new(),
            position: Some((list.position, list.total)),
        }
    }

    /// 分岐図は，選んでいる文節の候補(語の候補のあとに，カタカナなどの種類)を一覧にする
    fn from_map(map: BranchMap) -> Self {
        let Some(column) = map.columns.into_iter().find(|column| column.is_focused) else {
            return Self::default();
        };
        let alternatives = column.alternatives.len();
        let selected = column
            .selected_variant
            .map(|index| alternatives + index as usize)
            .or(column.selected_alternative.map(|index| index as usize));
        let note = column
            .usage_note
            .or(map.note.map(|note| note.text))
            .unwrap_or_default();
        let hints = map
            .hints
            .iter()
            .map(|hint| format!("{} {}", hint.keys, hint.label))
            .collect::<Vec<_>>()
            .join("　");
        Self {
            candidates: column
                .alternatives
                .into_iter()
                .chain(column.variants)
                .collect(),
            selected,
            note,
            hints,
            position: Some((map.position, map.total)),
        }
    }
}

/// 候補の一覧を受け取り続ける．変わったら notify に 1 バイト書く(アドオンはその読み口を Fcitx 5 の事象の輪で見る)
pub struct Receiver {
    panel: Arc<Mutex<Panel>>,
}

impl Receiver {
    pub fn start(path: PathBuf, notify: UnixStream) -> std::io::Result<Self> {
        let panel = Arc::new(Mutex::new(Panel::default()));
        let shared = Arc::clone(&panel);
        std::thread::Builder::new()
            .name("s90-candidate-receiver".into())
            .spawn(move || receive(&path, &shared, notify))?;
        Ok(Self { panel })
    }

    pub fn panel(&self) -> Panel {
        self.panel
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
            .clone()
    }
}

fn receive(path: &std::path::Path, panel: &Mutex<Panel>, mut notify: UnixStream) {
    loop {
        if let Ok(mut stream) = ipc::unix::connect(path) {
            while let Ok(command) = read_message::<_, UiCommand>(&mut stream) {
                panel
                    .lock()
                    .unwrap_or_else(PoisonError::into_inner)
                    .apply(command);
                // 知らせが溜まっていても 1 回読めば足りるので，書けなくてもよい
                let _ = notify.write(&[1]);
            }
            // 切れたら候補を消す(エンジンが止まった)
            *panel.lock().unwrap_or_else(PoisonError::into_inner) = Panel::default();
            let _ = notify.write(&[1]);
        }
        std::thread::sleep(Duration::from_millis(RECONNECT_MILLISECONDS));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ipc::{BranchColumn, CandidateEntry, CandidateFocus, KeyHint};

    fn column(focused: bool) -> BranchColumn {
        BranchColumn {
            text: "天気".into(),
            alternatives: vec!["天気".into(), "転機".into()],
            selected_alternative: Some(1),
            variants: vec!["テンキ".into()],
            selected_variant: None,
            is_focused: focused,
            is_uncertain: false,
            is_decided: false,
            is_corrected: None,
            preview: None,
            shorter: None,
            longer: None,
            usage_note: None,
            alternative_notes: vec![None, None],
            source_name: None,
            split: None,
        }
    }

    #[test]
    fn 分岐図は選んでいる文節の候補と種類を一覧にする() {
        let mut panel = Panel::default();
        panel.apply(UiCommand::ShowBranchMap {
            map: BranchMap {
                columns: vec![column(false), column(true)],
                position: 2,
                total: 3,
                note: Some(ipc::Note {
                    tone: ipc::NoteTone::Info,
                    title: "案内".into(),
                    subject: None,
                    key: None,
                    key_action: None,
                    text: "案内".into(),
                }),
                hints: vec![KeyHint {
                    keys: "⇧←→".into(),
                    label: "区切り調整".into(),
                }],
                association: None,
                association_hint: None,
            },
            anchor: None,
        });
        assert_eq!(panel.candidates, ["天気", "転機", "テンキ"]);
        assert_eq!(panel.selected, Some(1));
        assert_eq!(panel.note, "案内");
        assert_eq!(panel.hints, "⇧←→ 区切り調整");
        assert_eq!(panel.position, Some((2, 3)));
    }

    #[test]
    fn 一覧の候補を出し_隠すと消す() {
        let mut panel = Panel::default();
        panel.apply(UiCommand::ShowCandidates {
            list: CandidateList {
                variants: vec![],
                selected_variant: None,
                entries: vec![CandidateEntry {
                    text: "→".into(),
                    annotation: None,
                    corrected_start: None,
                    corrected_length: None,
                }],
                selected_entry: Some(0),
                focus: CandidateFocus::Candidate,
                position: 1,
                total: 1,
                note: None,
                association: None,
                association_hint: None,
            },
            anchor: None,
        });
        assert_eq!(panel.candidates, ["→"]);
        panel.apply(UiCommand::Hide);
        assert_eq!(panel, Panel::default());
    }
}
