//! エンジンの 1 つのセッションにキーを送り，返ってきた編集の操作を Fcitx 5 に渡せる形にまとめる

use ipc::client::EngineClient;
use ipc::timing::ENGINE_STALL_MILLISECONDS;
use ipc::{EditOperation, ErrorCode, FieldContext, KeyInput, RequestBody, ResponseBody, TextStyle};
use std::time::Duration;

/// エンジンの返事を待つ時間の上限．Fcitx 5 のキーの処理は返事を待ってから受け取るかを決める(mozc の Fcitx 5 版と同じ)
const RESPONSE_TIMEOUT: Duration = Duration::from_millis(ENGINE_STALL_MILLISECONDS);

/// 1 回のキー(または wake)の結果
#[derive(Debug, Default, PartialEq)]
pub struct Output {
    /// キーをこちらで受け取ったか(false ならアプリに渡す)
    pub handled: bool,
    /// 確定する文字(複数の確定はつなげる)
    pub commit: String,
    /// 入力中の文字．preedit が None なら前のまま
    pub preedit: Option<Vec<(String, TextStyle)>>,
    /// この時間(ミリ秒)のあとに wake を送る．None なら送らない
    pub wake_after: Option<u32>,
    /// 組み立て中か
    pub is_composing: bool,
}

pub struct Session {
    client: EngineClient,
    session: Option<u32>,
    is_composing: bool,
}

impl Session {
    pub fn new(client: EngineClient) -> Self {
        Self {
            client,
            session: None,
            is_composing: false,
        }
    }

    pub fn key(&mut self, input: KeyInput, context: FieldContext) -> Output {
        let output = self.request(|session| RequestBody::Key {
            session,
            input: input.clone(),
            context: context.clone(),
        });
        match output {
            Some(output) => output,
            // エンジンが返事をしないとき，組み立て中ならキーをアプリに渡さない(読みの途中に文字が入るのを防ぐ)
            None => Output {
                handled: self.is_composing,
                is_composing: self.is_composing,
                ..Output::default()
            },
        }
    }

    pub fn wake(&mut self, context: FieldContext) -> Output {
        self.request(|session| RequestBody::Wake {
            session,
            context: context.clone(),
        })
        .unwrap_or_default()
    }

    /// 入力先から外れた．組み立て中の文字の扱いはエンジンが決め，確定する文字があれば返す
    pub fn deactivate(&mut self) -> Output {
        let output = self
            .request(|session| RequestBody::Deactivate { session })
            .unwrap_or_default();
        self.is_composing = false;
        output
    }

    /// セッションが無ければ開いて送る．エンジンが作り直されてセッションを知らないときは，開き直して 1 回だけ送り直す
    fn request(&mut self, body: impl Fn(u32) -> RequestBody) -> Option<Output> {
        for _ in 0..2 {
            let session = self.open()?;
            match self.client.send(body(session)).wait(RESPONSE_TIMEOUT)? {
                ResponseBody::Edit {
                    handled,
                    operations,
                    state,
                } => {
                    self.is_composing = state.is_composing;
                    return Some(Self::output(
                        handled,
                        operations,
                        state.is_composing,
                        state.wake_after_milliseconds,
                    ));
                }
                ResponseBody::Done => return Some(Output::default()),
                ResponseBody::Error {
                    code: ErrorCode::UnknownSession,
                } => self.session = None,
                _ => return None,
            }
        }
        None
    }

    fn open(&mut self) -> Option<u32> {
        if self.session.is_none() {
            if let ResponseBody::SessionOpened { session, state } = self
                .client
                .send(RequestBody::OpenSession)
                .wait(RESPONSE_TIMEOUT)?
            {
                self.is_composing = state.is_composing;
                self.session = Some(session);
            }
        }
        self.session
    }

    fn output(
        handled: bool,
        operations: Vec<EditOperation>,
        is_composing: bool,
        wake_after: Option<u32>,
    ) -> Output {
        let mut output = Output {
            handled,
            wake_after,
            is_composing,
            ..Output::default()
        };
        for operation in operations {
            match operation {
                EditOperation::Commit { text } => output.commit.push_str(&text),
                // 入力位置(caret)は Linux ではまだ扱わない(入力中の文字の末尾に置く)
                EditOperation::SetComposition { segments, .. } => {
                    output.preedit = Some(
                        segments
                            .into_iter()
                            .map(|segment| (segment.text, segment.style))
                            .collect(),
                    );
                }
                // 入力の切り替えは状態(mode)で，再変換は Linux ではまだ扱わない(ADR 0012)
                _ => {}
            }
        }
        output
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ipc::TextSegment;

    #[test]
    fn 確定はつなげ_入力中の文字は最後のものにする() {
        let operations = vec![
            EditOperation::Commit {
                text: "今日".into(),
            },
            EditOperation::Commit { text: "は".into() },
            EditOperation::SetComposition {
                segments: vec![TextSegment {
                    text: "てんき".into(),
                    style: TextStyle::Reading,
                }],
                caret: None,
            },
        ];
        let output = Session::output(true, operations, true, Some(300));
        assert_eq!(output.commit, "今日は");
        assert_eq!(
            output.preedit,
            Some(vec![("てんき".to_string(), TextStyle::Reading)])
        );
        assert_eq!(output.wake_after, Some(300));
        assert!(output.handled && output.is_composing);
    }
}
