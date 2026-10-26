// このファイルは tools/protocol/generate.py が protocol/schema.json から作る．手で直さない．

use serde::{Deserialize, Serialize};
use std::fmt;

/// 通信の形式の版．DLL とエンジンの版が違えば接続を断る
pub const PROTOCOL_VERSION: u32 = 1;
/// 1 つのメッセージの大きさの上限(バイト)．超えたら接続を切る(docs/dev/SECURITY-MODEL.md)
pub const MAXIMUM_MESSAGE_BYTES: usize = 262144;

/// 入力の中身を持つ値をログに出すときに，中身の代わりに出す
const REDACTED: &str = "<伏せた>";

/// 入力のモード．日本語か英数か
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum InputMode {
    Japanese,
    Direct,
}

/// 押していた修飾キー．Windows の Alt は core の option にあたる
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct Modifiers {
    pub shift: bool,
    pub control: bool,
    pub alt: bool,
}

impl fmt::Debug for Modifiers {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Modifiers")
            .field("shift", &self.shift)
            .field("control", &self.control)
            .field("alt", &self.alt)
            .finish()
    }
}

/// 押したキー．core の KeyEvent.Key と 1 対 1 に対応する
#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Key {
    /// 配列に従って入力された文字(Shift を含む)
    Character {
        text: String,
    },
    Space,
    Enter,
    Backspace,
    Delete,
    Escape,
    Tab,
    Up,
    Down,
    Left,
    Right,
    Home,
    End,
    PageUp,
    PageDown,
    Eisu,
    Kana,
    Yen,
    /// ファンクションキー(F1〜F24 の番号)
    Function {
        number: u8,
    },
    HankakuZenkaku,
    Henkan,
    Muhenkan,
}

impl fmt::Debug for Key {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Character { .. } => f
                .debug_struct("Character")
                .field("text", &REDACTED)
                .finish(),
            Self::Space => f.write_str("Space"),
            Self::Enter => f.write_str("Enter"),
            Self::Backspace => f.write_str("Backspace"),
            Self::Delete => f.write_str("Delete"),
            Self::Escape => f.write_str("Escape"),
            Self::Tab => f.write_str("Tab"),
            Self::Up => f.write_str("Up"),
            Self::Down => f.write_str("Down"),
            Self::Left => f.write_str("Left"),
            Self::Right => f.write_str("Right"),
            Self::Home => f.write_str("Home"),
            Self::End => f.write_str("End"),
            Self::PageUp => f.write_str("PageUp"),
            Self::PageDown => f.write_str("PageDown"),
            Self::Eisu => f.write_str("Eisu"),
            Self::Kana => f.write_str("Kana"),
            Self::Yen => f.write_str("Yen"),
            Self::Function { number, .. } => f
                .debug_struct("Function")
                .field("number", number)
                .finish(),
            Self::HankakuZenkaku => f.write_str("HankakuZenkaku"),
            Self::Henkan => f.write_str("Henkan"),
            Self::Muhenkan => f.write_str("Muhenkan"),
        }
    }
}

/// キーの入力ひとつ
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct KeyInput {
    pub key: Key,
    pub modifiers: Modifiers,
    /// 押したキーの JIS キーボードでの刻印(かな入力に使う)
    #[serde(rename = "keyLabel")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub key_label: Option<String>,
    #[serde(rename = "isKeypad")]
    pub is_keypad: bool,
}

impl fmt::Debug for KeyInput {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KeyInput")
            .field("key", &self.key)
            .field("modifiers", &self.modifiers)
            .field("keyLabel", &REDACTED)
            .field("isKeypad", &self.is_keypad)
            .finish()
    }
}

/// キーと修飾キーの組み合わせ．DLL が OnTestKeyDown で使う表の 1 行
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct KeyChord {
    pub key: Key,
    pub modifiers: Modifiers,
}

impl fmt::Debug for KeyChord {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KeyChord")
            .field("key", &self.key)
            .field("modifiers", &self.modifiers)
            .finish()
    }
}

/// 画面の座標(物理ピクセル)の四角．候補ウィンドウを出す位置に使う
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct Rect {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
}

impl fmt::Debug for Rect {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Rect")
            .field("x", &self.x)
            .field("y", &self.y)
            .field("width", &self.width)
            .field("height", &self.height)
            .finish()
    }
}

/// 入力先の情報．DLL がキーごとに作って送る
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct FieldContext {
    /// 入力先のアプリの実行ファイルの名前(小文字)．アプリごとの設定を選ぶのに使う
    #[serde(rename = "applicationId")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub application_id: Option<String>,
    /// パスワード欄など(InputScope)．true なら変換も学習もしない
    #[serde(rename = "isSecure")]
    pub is_secure: bool,
    /// 入力位置の前の文字列．打ち始めのときだけ入れる
    #[serde(rename = "precedingText")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preceding_text: Option<String>,
    /// 入力位置の四角．分からなければ省く
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub caret: Option<Rect>,
}

impl fmt::Debug for FieldContext {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("FieldContext")
            .field("applicationId", &REDACTED)
            .field("isSecure", &self.is_secure)
            .field("precedingText", &REDACTED)
            .field("caret", &self.caret)
            .finish()
    }
}

/// DLL が持つ状態の写し．OnTestKeyDown をエンジンに問い合わせずに答えるのに使う
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionState {
    pub mode: InputMode,
    /// 文字を組み立てているか．組み立て中は修飾キーだけの押下を除くすべてのキーを受け取る
    #[serde(rename = "isComposing")]
    pub is_composing: bool,
    /// 組み立てていないときに受け取るキー(キー設定の表で今の状態に割り当てたもの)．日本語のモードでは修飾キーなしの文字も受け取る
    #[serde(rename = "consumedKeys")]
    pub consumed_keys: Vec<KeyChord>,
    /// この時間だけ打鍵が止まったら wake を送る(ライブ変換・打ち間違いの見直し)．待たなくてよければ省く
    #[serde(rename = "wakeAfterMilliseconds")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wake_after_milliseconds: Option<u32>,
}

impl fmt::Debug for SessionState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SessionState")
            .field("mode", &self.mode)
            .field("isComposing", &self.is_composing)
            .field("consumedKeys", &self.consumed_keys)
            .field("wakeAfterMilliseconds", &self.wake_after_milliseconds)
            .finish()
    }
}

/// 組み立て中の文字の区間の見せ方
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TextStyle {
    Reading,
    Converted,
    Focused,
    Correction,
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct TextSegment {
    pub text: String,
    pub style: TextStyle,
}

impl fmt::Debug for TextSegment {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("TextSegment")
            .field("text", &REDACTED)
            .field("style", &self.style)
            .finish()
    }
}

/// DLL が入力欄に行う操作
#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum EditOperation {
    /// 文字を確定して入力欄に入れる
    Commit {
        text: String,
    },
    /// 組み立て中の文字を出す(空なら消す)
    SetComposition {
        segments: Vec<TextSegment>,
    },
    /// OS のモードの表示(言語バー・キーボードのオンとオフ)を合わせる
    SelectMode {
        mode: InputMode,
    },
}

impl fmt::Debug for EditOperation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Commit { .. } => f
                .debug_struct("Commit")
                .field("text", &REDACTED)
                .finish(),
            Self::SetComposition { segments, .. } => f
                .debug_struct("SetComposition")
                .field("segments", segments)
                .finish(),
            Self::SelectMode { mode, .. } => f
                .debug_struct("SelectMode")
                .field("mode", mode)
                .finish(),
        }
    }
}

/// エンジンが要求を断った理由
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ErrorCode {
    UnsupportedVersion,
    UnknownSession,
    TooManySessions,
    Malformed,
}

/// DLL からエンジンへの要求
#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum RequestBody {
    /// 接続して最初に送る
    Hello {
        #[serde(rename = "protocolVersion")]
        protocol_version: u32,
    },
    /// 入力欄(TSF のスレッド)ごとのセッションを作る
    OpenSession,
    CloseSession {
        session: u32,
    },
    Key {
        session: u32,
        input: KeyInput,
        context: FieldContext,
    },
    /// 言語バーなど，キー以外でモードが変わった
    SetMode {
        session: u32,
        mode: InputMode,
    },
    /// 入力欄からフォーカスが外れた．組み立て中の文字を確定する
    Deactivate {
        session: u32,
    },
    /// wakeAfterMilliseconds だけ打鍵が止まった
    Wake {
        session: u32,
        context: FieldContext,
    },
    /// 組み立て中の文字の位置が変わった．候補ウィンドウを動かす
    Caret {
        session: u32,
        rect: Rect,
    },
}

impl fmt::Debug for RequestBody {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Hello { protocol_version, .. } => f
                .debug_struct("Hello")
                .field("protocolVersion", protocol_version)
                .finish(),
            Self::OpenSession => f.write_str("OpenSession"),
            Self::CloseSession { session, .. } => f
                .debug_struct("CloseSession")
                .field("session", session)
                .finish(),
            Self::Key { session, input, context, .. } => f
                .debug_struct("Key")
                .field("session", session)
                .field("input", input)
                .field("context", context)
                .finish(),
            Self::SetMode { session, mode, .. } => f
                .debug_struct("SetMode")
                .field("session", session)
                .field("mode", mode)
                .finish(),
            Self::Deactivate { session, .. } => f
                .debug_struct("Deactivate")
                .field("session", session)
                .finish(),
            Self::Wake { session, context, .. } => f
                .debug_struct("Wake")
                .field("session", session)
                .field("context", context)
                .finish(),
            Self::Caret { session, rect, .. } => f
                .debug_struct("Caret")
                .field("session", session)
                .field("rect", rect)
                .finish(),
        }
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct Request {
    /// 応答と組にする番号．時間切れで捨てた応答を読み飛ばすのに使う
    pub id: u32,
    pub body: RequestBody,
}

impl fmt::Debug for Request {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Request")
            .field("id", &self.id)
            .field("body", &self.body)
            .finish()
    }
}

/// エンジンから DLL への応答
#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum ResponseBody {
    Hello {
        #[serde(rename = "protocolVersion")]
        protocol_version: u32,
    },
    SessionOpened {
        session: u32,
        state: SessionState,
    },
    /// キーなどを処理した結果
    Edit {
        /// false ならキーを入力先のアプリにそのまま渡す
        handled: bool,
        operations: Vec<EditOperation>,
        state: SessionState,
    },
    Done,
    Error {
        code: ErrorCode,
    },
}

impl fmt::Debug for ResponseBody {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Hello { protocol_version, .. } => f
                .debug_struct("Hello")
                .field("protocolVersion", protocol_version)
                .finish(),
            Self::SessionOpened { session, state, .. } => f
                .debug_struct("SessionOpened")
                .field("session", session)
                .field("state", state)
                .finish(),
            Self::Edit { handled, operations, state, .. } => f
                .debug_struct("Edit")
                .field("handled", handled)
                .field("operations", operations)
                .field("state", state)
                .finish(),
            Self::Done => f.write_str("Done"),
            Self::Error { code, .. } => f
                .debug_struct("Error")
                .field("code", code)
                .finish(),
        }
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct Response {
    pub id: u32,
    pub body: ResponseBody,
}

impl fmt::Debug for Response {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Response")
            .field("id", &self.id)
            .field("body", &self.body)
            .finish()
    }
}

/// 候補の一覧の上の種類の行の 1 つ
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct CandidateVariant {
    pub label: String,
    #[serde(rename = "isAvailable")]
    pub is_available: bool,
}

impl fmt::Debug for CandidateVariant {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CandidateVariant")
            .field("label", &REDACTED)
            .field("isAvailable", &self.is_available)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct CandidateEntry {
    pub text: String,
    /// 「入力のまま」などの添え書き
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub annotation: Option<String>,
}

impl fmt::Debug for CandidateEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CandidateEntry")
            .field("text", &REDACTED)
            .field("annotation", &REDACTED)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CandidateFocus {
    Candidate,
    Variants,
}

/// 候補の一覧．core の CandidatePanel と同じ内容
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct CandidateList {
    pub variants: Vec<CandidateVariant>,
    #[serde(rename = "selectedVariant")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected_variant: Option<u32>,
    pub entries: Vec<CandidateEntry>,
    #[serde(rename = "selectedEntry")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected_entry: Option<u32>,
    pub focus: CandidateFocus,
    pub position: u32,
    pub total: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

impl fmt::Debug for CandidateList {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CandidateList")
            .field("variants", &self.variants)
            .field("selectedVariant", &self.selected_variant)
            .field("entries", &self.entries)
            .field("selectedEntry", &self.selected_entry)
            .field("focus", &self.focus)
            .field("position", &self.position)
            .field("total", &self.total)
            .field("note", &REDACTED)
            .finish()
    }
}

/// 分岐図の文節ひとつ．core の LatticePanel.Column と同じ内容
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct BranchColumn {
    pub text: String,
    pub alternatives: Vec<String>,
    #[serde(rename = "selectedAlternative")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected_alternative: Option<u32>,
    pub variants: Vec<String>,
    #[serde(rename = "selectedVariant")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub selected_variant: Option<u32>,
    #[serde(rename = "isFocused")]
    pub is_focused: bool,
    #[serde(rename = "isUncertain")]
    pub is_uncertain: bool,
    #[serde(rename = "isDecided")]
    pub is_decided: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preview: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub shorter: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub longer: Option<String>,
    #[serde(rename = "usageNote")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub usage_note: Option<String>,
    #[serde(rename = "alternativeNotes")]
    pub alternative_notes: Vec<Option<String>>,
    #[serde(rename = "sourceName")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_name: Option<String>,
}

impl fmt::Debug for BranchColumn {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("BranchColumn")
            .field("text", &REDACTED)
            .field("alternatives", &REDACTED)
            .field("selectedAlternative", &self.selected_alternative)
            .field("variants", &REDACTED)
            .field("selectedVariant", &self.selected_variant)
            .field("isFocused", &self.is_focused)
            .field("isUncertain", &self.is_uncertain)
            .field("isDecided", &self.is_decided)
            .field("preview", &REDACTED)
            .field("shorter", &REDACTED)
            .field("longer", &REDACTED)
            .field("usageNote", &REDACTED)
            .field("alternativeNotes", &REDACTED)
            .field("sourceName", &REDACTED)
            .finish()
    }
}

/// 分岐図の足元に出すキーの案内(「⇧← 入れ」)
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct KeyHint {
    pub keys: String,
    pub label: String,
}

impl fmt::Debug for KeyHint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KeyHint")
            .field("keys", &REDACTED)
            .field("label", &REDACTED)
            .finish()
    }
}

/// 分岐図(ADR 0007)．core の LatticePanel と同じ内容
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct BranchMap {
    pub columns: Vec<BranchColumn>,
    pub position: u32,
    pub total: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    /// 足元のキーの案内．出さない設定のときは空
    pub hints: Vec<KeyHint>,
}

impl fmt::Debug for BranchMap {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("BranchMap")
            .field("columns", &self.columns)
            .field("position", &self.position)
            .field("total", &self.total)
            .field("note", &REDACTED)
            .field("hints", &self.hints)
            .finish()
    }
}

/// 候補ウィンドウの見た目の設定．つないだときと設定が変わったときに送る
#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct Presentation {
    /// テーマの名前(settings.json の theme と同じ値)
    pub theme: String,
    /// 候補の文字の大きさ(pt)
    #[serde(rename = "fontSize")]
    pub font_size: f64,
    /// モードの札を出しておく時間
    #[serde(rename = "modeIndicatorMilliseconds")]
    pub mode_indicator_milliseconds: u32,
}

impl fmt::Debug for Presentation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Presentation")
            .field("theme", &REDACTED)
            .field("fontSize", &self.font_size)
            .field("modeIndicatorMilliseconds", &self.mode_indicator_milliseconds)
            .finish()
    }
}

/// エンジンから候補ウィンドウのプロセスへの指示
#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum UiCommand {
    Hello {
        #[serde(rename = "protocolVersion")]
        protocol_version: u32,
    },
    SetPresentation {
        presentation: Presentation,
    },
    ShowCandidates {
        list: CandidateList,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        anchor: Option<Rect>,
    },
    ShowBranchMap {
        map: BranchMap,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        anchor: Option<Rect>,
    },
    /// 入力位置の近くに短い案内を出す
    ShowNote {
        text: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        anchor: Option<Rect>,
    },
    /// モードを切り替えたことを知らせる札
    ShowMode {
        mode: InputMode,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        anchor: Option<Rect>,
    },
    Move {
        anchor: Rect,
    },
    Hide,
}

impl fmt::Debug for UiCommand {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Hello { protocol_version, .. } => f
                .debug_struct("Hello")
                .field("protocolVersion", protocol_version)
                .finish(),
            Self::SetPresentation { presentation, .. } => f
                .debug_struct("SetPresentation")
                .field("presentation", presentation)
                .finish(),
            Self::ShowCandidates { list, anchor, .. } => f
                .debug_struct("ShowCandidates")
                .field("list", list)
                .field("anchor", anchor)
                .finish(),
            Self::ShowBranchMap { map, anchor, .. } => f
                .debug_struct("ShowBranchMap")
                .field("map", map)
                .field("anchor", anchor)
                .finish(),
            Self::ShowNote { anchor, .. } => f
                .debug_struct("ShowNote")
                .field("text", &REDACTED)
                .field("anchor", anchor)
                .finish(),
            Self::ShowMode { mode, anchor, .. } => f
                .debug_struct("ShowMode")
                .field("mode", mode)
                .field("anchor", anchor)
                .finish(),
            Self::Move { anchor, .. } => f
                .debug_struct("Move")
                .field("anchor", anchor)
                .finish(),
            Self::Hide => f.write_str("Hide"),
        }
    }
}
