use serde::{Deserialize, Serialize};
use std::fmt;

pub const PROTOCOL_VERSION: u32 = 1;
pub const MAXIMUM_MESSAGE_BYTES: usize = 262144;

const REDACTED: &str = "<伏せた>";

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum InputMode {
    Japanese,
    Direct,
}

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

#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum Key {
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

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct KeyInput {
    pub key: Key,
    pub modifiers: Modifiers,
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

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct FieldContext {
    #[serde(rename = "applicationId")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub application_id: Option<String>,
    #[serde(rename = "isSecure")]
    pub is_secure: bool,
    #[serde(rename = "precedingText")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preceding_text: Option<String>,
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

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct SessionState {
    pub mode: InputMode,
    #[serde(rename = "isComposing")]
    pub is_composing: bool,
    #[serde(rename = "consumedKeys")]
    pub consumed_keys: Vec<KeyChord>,
    #[serde(rename = "wakeAfterMilliseconds")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wake_after_milliseconds: Option<u32>,
    #[serde(rename = "precedingTextLength")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preceding_text_length: Option<u32>,
    #[serde(rename = "keyboardLayout")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub keyboard_layout: Option<String>,
}

impl fmt::Debug for SessionState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SessionState")
            .field("mode", &self.mode)
            .field("isComposing", &self.is_composing)
            .field("consumedKeys", &self.consumed_keys)
            .field("wakeAfterMilliseconds", &self.wake_after_milliseconds)
            .field("precedingTextLength", &self.preceding_text_length)
            .field("keyboardLayout", &REDACTED)
            .finish()
    }
}

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

#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum EditOperation {
    Commit {
        text: String,
    },
    SetComposition {
        segments: Vec<TextSegment>,
    },
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

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ErrorCode {
    UnsupportedVersion,
    UnknownSession,
    TooManySessions,
    Malformed,
    TooLarge,
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct SettingsSnapshot {
    pub theme: String,
    #[serde(rename = "inputStyle")]
    pub input_style: String,
    #[serde(rename = "liveConversion")]
    pub live_conversion: bool,
    #[serde(rename = "showsModeIndicator")]
    pub shows_mode_indicator: bool,
    #[serde(rename = "showsKeyHints")]
    pub shows_key_hints: bool,
    #[serde(rename = "candidateFontSize")]
    pub candidate_font_size: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub handwriting: Option<bool>,
}

impl fmt::Debug for SettingsSnapshot {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SettingsSnapshot")
            .field("theme", &REDACTED)
            .field("inputStyle", &REDACTED)
            .field("liveConversion", &self.live_conversion)
            .field("showsModeIndicator", &self.shows_mode_indicator)
            .field("showsKeyHints", &self.shows_key_hints)
            .field("candidateFontSize", &self.candidate_font_size)
            .field("handwriting", &self.handwriting)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum MenuCommand {
    ToggleLiveConversion,
    OpenSettings,
}

impl fmt::Debug for MenuCommand {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ToggleLiveConversion => f.write_str("ToggleLiveConversion"),
            Self::OpenSettings => f.write_str("OpenSettings"),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RuleList {
    CorrectionRules,
    Exceptions,
    EnglishWords,
    JapaneseWords,
    Romaji,
    SymbolSequences,
    SymbolReadings,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SyncProblem {
    Failed,
    Unreadable,
    FolderUnavailable,
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct SyncGroupState {
    pub group: String,
    pub scope: String,
    pub fields: Vec<String>,
}

impl fmt::Debug for SyncGroupState {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SyncGroupState")
            .field("group", &REDACTED)
            .field("scope", &REDACTED)
            .field("fields", &REDACTED)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct SyncStatus {
    #[serde(rename = "isEnabled")]
    pub is_enabled: bool,
    #[serde(rename = "folderPath")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub folder_path: Option<String>,
    #[serde(rename = "folderName")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub folder_name: Option<String>,
    pub groups: Vec<SyncGroupState>,
    #[serde(rename = "localFields")]
    pub local_fields: Vec<String>,
    #[serde(rename = "lastSyncedAt")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_synced_at: Option<String>,
    #[serde(rename = "isSyncing")]
    pub is_syncing: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub problem: Option<SyncProblem>,
}

impl fmt::Debug for SyncStatus {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SyncStatus")
            .field("isEnabled", &self.is_enabled)
            .field("folderPath", &REDACTED)
            .field("folderName", &REDACTED)
            .field("groups", &self.groups)
            .field("localFields", &REDACTED)
            .field("lastSyncedAt", &REDACTED)
            .field("isSyncing", &self.is_syncing)
            .field("problem", &self.problem)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct ImportedDictionaryInfo {
    pub id: String,
    pub name: String,
    #[serde(rename = "wordCount")]
    pub word_count: u32,
}

impl fmt::Debug for ImportedDictionaryInfo {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ImportedDictionaryInfo")
            .field("id", &REDACTED)
            .field("name", &REDACTED)
            .field("wordCount", &self.word_count)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FileFailure {
    InvalidPath,
    NotFound,
    TooLarge,
    Unreadable,
    Empty,
    NotSettings,
    TooMany,
    UnknownDictionary,
    WriteFailed,
    Busy,
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct SymbolDefault {
    pub input: String,
    pub output: String,
}

impl fmt::Debug for SymbolDefault {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SymbolDefault")
            .field("input", &REDACTED)
            .field("output", &REDACTED)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct KeymapRowIssue {
    pub row: u32,
    #[serde(rename = "hiddenBy")]
    pub hidden_by: Vec<u32>,
    #[serde(rename = "hiddenStates")]
    pub hidden_states: Vec<String>,
    #[serde(rename = "blocksTyping")]
    pub blocks_typing: bool,
}

impl fmt::Debug for KeymapRowIssue {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KeymapRowIssue")
            .field("row", &self.row)
            .field("hiddenBy", &self.hidden_by)
            .field("hiddenStates", &REDACTED)
            .field("blocksTyping", &self.blocks_typing)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct KeymapMissing {
    pub state: String,
    pub command: String,
}

impl fmt::Debug for KeymapMissing {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KeymapMissing")
            .field("state", &REDACTED)
            .field("command", &REDACTED)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct KeymapReport {
    pub rows: Vec<KeymapRowIssue>,
    pub missing: Vec<KeymapMissing>,
}

impl fmt::Debug for KeymapReport {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("KeymapReport")
            .field("rows", &self.rows)
            .field("missing", &self.missing)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct PreviewWord {
    pub typed: String,
    pub shown: String,
    pub language: String,
}

impl fmt::Debug for PreviewWord {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("PreviewWord")
            .field("typed", &REDACTED)
            .field("shown", &REDACTED)
            .field("language", &REDACTED)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct DictionaryEntry {
    pub reading: String,
    pub word: String,
}

impl fmt::Debug for DictionaryEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("DictionaryEntry")
            .field("reading", &REDACTED)
            .field("word", &REDACTED)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum DictionaryAddResult {
    Added,
    AlreadyRegistered,
    Invalid,
    Full,
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum RequestBody {
    Hello {
        #[serde(rename = "protocolVersion")]
        protocol_version: u32,
    },
    OpenSession,
    CloseSession {
        session: u32,
    },
    Key {
        session: u32,
        input: KeyInput,
        context: FieldContext,
    },
    SetMode {
        session: u32,
        mode: InputMode,
    },
    Deactivate {
        session: u32,
    },
    Wake {
        session: u32,
        context: FieldContext,
    },
    OpenHandwriting {
        session: u32,
        context: FieldContext,
    },
    Caret {
        session: u32,
        rect: Rect,
    },
    ReadSettings,
    WriteSettings {
        settings: SettingsSnapshot,
    },
    Menu {
        command: MenuCommand,
    },
    ReadSync,
    SetSyncFolder {
        path: String,
    },
    SetSyncEnabled {
        enabled: bool,
    },
    SetSyncScope {
        group: String,
        scope: String,
    },
    SetSyncLocalField {
        field: String,
        #[serde(rename = "isLocal")]
        is_local: bool,
    },
    SyncNow,
    ImportDictionary {
        path: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        replacing: Option<String>,
    },
    RemoveDictionary {
        id: String,
    },
    ExportSettings {
        path: String,
    },
    ImportSettings {
        path: String,
    },
    ImportProfileRules {
        path: String,
    },
    ExportProfileRules {
        path: String,
    },
    ImportRuleList {
        list: RuleList,
        path: String,
    },
    ExportRuleList {
        list: RuleList,
        path: String,
    },
    ReadSymbolDefaults,
    ImportUserDictionary {
        path: String,
    },
    ExportUserDictionary {
        path: String,
    },
    HandwritingChosen {
        text: String,
    },
    HandwritingClosed,
    ReadSettingsFields {
        names: Vec<String>,
        defaults: bool,
    },
    WriteSettingsFields {
        values: String,
    },
    ReadKeymapPreset {
        preset: String,
    },
    CheckKeymap {
        values: String,
    },
    ResetLearning,
    ReadUsage,
    ResetUsage,
    PreviewLanguage {
        text: String,
        #[serde(rename = "precedingText")]
        #[serde(default, skip_serializing_if = "Option::is_none")]
        preceding_text: Option<String>,
    },
    ReadUserDictionary {
        offset: u32,
        limit: u32,
    },
    AddUserDictionaryEntry {
        entry: DictionaryEntry,
    },
    RemoveUserDictionaryEntry {
        entry: DictionaryEntry,
    },
    MergeUserDictionary {
        entries: Vec<DictionaryEntry>,
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
            Self::OpenHandwriting { session, context, .. } => f
                .debug_struct("OpenHandwriting")
                .field("session", session)
                .field("context", context)
                .finish(),
            Self::Caret { session, rect, .. } => f
                .debug_struct("Caret")
                .field("session", session)
                .field("rect", rect)
                .finish(),
            Self::ReadSettings => f.write_str("ReadSettings"),
            Self::WriteSettings { settings, .. } => f
                .debug_struct("WriteSettings")
                .field("settings", settings)
                .finish(),
            Self::Menu { command, .. } => f
                .debug_struct("Menu")
                .field("command", command)
                .finish(),
            Self::ReadSync => f.write_str("ReadSync"),
            Self::SetSyncFolder { .. } => f
                .debug_struct("SetSyncFolder")
                .field("path", &REDACTED)
                .finish(),
            Self::SetSyncEnabled { enabled, .. } => f
                .debug_struct("SetSyncEnabled")
                .field("enabled", enabled)
                .finish(),
            Self::SetSyncScope { .. } => f
                .debug_struct("SetSyncScope")
                .field("group", &REDACTED)
                .field("scope", &REDACTED)
                .finish(),
            Self::SetSyncLocalField { is_local, .. } => f
                .debug_struct("SetSyncLocalField")
                .field("field", &REDACTED)
                .field("isLocal", is_local)
                .finish(),
            Self::SyncNow => f.write_str("SyncNow"),
            Self::ImportDictionary { .. } => f
                .debug_struct("ImportDictionary")
                .field("path", &REDACTED)
                .field("replacing", &REDACTED)
                .finish(),
            Self::RemoveDictionary { .. } => f
                .debug_struct("RemoveDictionary")
                .field("id", &REDACTED)
                .finish(),
            Self::ExportSettings { .. } => f
                .debug_struct("ExportSettings")
                .field("path", &REDACTED)
                .finish(),
            Self::ImportSettings { .. } => f
                .debug_struct("ImportSettings")
                .field("path", &REDACTED)
                .finish(),
            Self::ImportProfileRules { .. } => f
                .debug_struct("ImportProfileRules")
                .field("path", &REDACTED)
                .finish(),
            Self::ExportProfileRules { .. } => f
                .debug_struct("ExportProfileRules")
                .field("path", &REDACTED)
                .finish(),
            Self::ImportRuleList { list, .. } => f
                .debug_struct("ImportRuleList")
                .field("list", list)
                .field("path", &REDACTED)
                .finish(),
            Self::ExportRuleList { list, .. } => f
                .debug_struct("ExportRuleList")
                .field("list", list)
                .field("path", &REDACTED)
                .finish(),
            Self::ReadSymbolDefaults => f.write_str("ReadSymbolDefaults"),
            Self::ImportUserDictionary { .. } => f
                .debug_struct("ImportUserDictionary")
                .field("path", &REDACTED)
                .finish(),
            Self::ExportUserDictionary { .. } => f
                .debug_struct("ExportUserDictionary")
                .field("path", &REDACTED)
                .finish(),
            Self::HandwritingChosen { .. } => f
                .debug_struct("HandwritingChosen")
                .field("text", &REDACTED)
                .finish(),
            Self::HandwritingClosed => f.write_str("HandwritingClosed"),
            Self::ReadSettingsFields { defaults, .. } => f
                .debug_struct("ReadSettingsFields")
                .field("names", &REDACTED)
                .field("defaults", defaults)
                .finish(),
            Self::WriteSettingsFields { .. } => f
                .debug_struct("WriteSettingsFields")
                .field("values", &REDACTED)
                .finish(),
            Self::ReadKeymapPreset { .. } => f
                .debug_struct("ReadKeymapPreset")
                .field("preset", &REDACTED)
                .finish(),
            Self::CheckKeymap { .. } => f
                .debug_struct("CheckKeymap")
                .field("values", &REDACTED)
                .finish(),
            Self::ResetLearning => f.write_str("ResetLearning"),
            Self::ReadUsage => f.write_str("ReadUsage"),
            Self::ResetUsage => f.write_str("ResetUsage"),
            Self::PreviewLanguage { .. } => f
                .debug_struct("PreviewLanguage")
                .field("text", &REDACTED)
                .field("precedingText", &REDACTED)
                .finish(),
            Self::ReadUserDictionary { offset, limit, .. } => f
                .debug_struct("ReadUserDictionary")
                .field("offset", offset)
                .field("limit", limit)
                .finish(),
            Self::AddUserDictionaryEntry { entry, .. } => f
                .debug_struct("AddUserDictionaryEntry")
                .field("entry", entry)
                .finish(),
            Self::RemoveUserDictionaryEntry { entry, .. } => f
                .debug_struct("RemoveUserDictionaryEntry")
                .field("entry", entry)
                .finish(),
            Self::MergeUserDictionary { entries, .. } => f
                .debug_struct("MergeUserDictionary")
                .field("entries", entries)
                .finish(),
        }
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct Request {
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
    Edit {
        handled: bool,
        operations: Vec<EditOperation>,
        state: SessionState,
    },
    Done,
    Settings {
        settings: SettingsSnapshot,
    },
    SyncStatus {
        status: SyncStatus,
    },
    DictionaryImported {
        dictionary: ImportedDictionaryInfo,
    },
    Imported {
        added: u32,
        skipped: u32,
    },
    FileFailed {
        reason: FileFailure,
    },
    SymbolDefaults {
        sequences: Vec<SymbolDefault>,
        readings: Vec<SymbolDefault>,
    },
    SettingsFields {
        values: String,
    },
    KeymapReport {
        report: KeymapReport,
    },
    Usage {
        values: String,
        #[serde(rename = "firstCandidateRate")]
        #[serde(default, skip_serializing_if = "Option::is_none")]
        first_candidate_rate: Option<f64>,
    },
    LanguagePreview {
        words: Vec<PreviewWord>,
    },
    UserDictionary {
        entries: Vec<DictionaryEntry>,
        total: u32,
    },
    DictionaryAdded {
        result: DictionaryAddResult,
    },
    DictionaryMerged {
        added: u32,
    },
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
            Self::Settings { settings, .. } => f
                .debug_struct("Settings")
                .field("settings", settings)
                .finish(),
            Self::SyncStatus { status, .. } => f
                .debug_struct("SyncStatus")
                .field("status", status)
                .finish(),
            Self::DictionaryImported { dictionary, .. } => f
                .debug_struct("DictionaryImported")
                .field("dictionary", dictionary)
                .finish(),
            Self::Imported { added, skipped, .. } => f
                .debug_struct("Imported")
                .field("added", added)
                .field("skipped", skipped)
                .finish(),
            Self::FileFailed { reason, .. } => f
                .debug_struct("FileFailed")
                .field("reason", reason)
                .finish(),
            Self::SymbolDefaults { sequences, readings, .. } => f
                .debug_struct("SymbolDefaults")
                .field("sequences", sequences)
                .field("readings", readings)
                .finish(),
            Self::SettingsFields { .. } => f
                .debug_struct("SettingsFields")
                .field("values", &REDACTED)
                .finish(),
            Self::KeymapReport { report, .. } => f
                .debug_struct("KeymapReport")
                .field("report", report)
                .finish(),
            Self::Usage { first_candidate_rate, .. } => f
                .debug_struct("Usage")
                .field("values", &REDACTED)
                .field("firstCandidateRate", first_candidate_rate)
                .finish(),
            Self::LanguagePreview { words, .. } => f
                .debug_struct("LanguagePreview")
                .field("words", words)
                .finish(),
            Self::UserDictionary { entries, total, .. } => f
                .debug_struct("UserDictionary")
                .field("entries", entries)
                .field("total", total)
                .finish(),
            Self::DictionaryAdded { result, .. } => f
                .debug_struct("DictionaryAdded")
                .field("result", result)
                .finish(),
            Self::DictionaryMerged { added, .. } => f
                .debug_struct("DictionaryMerged")
                .field("added", added)
                .finish(),
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub annotation: Option<String>,
    #[serde(rename = "correctedStart")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub corrected_start: Option<u32>,
    #[serde(rename = "correctedLength")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub corrected_length: Option<u32>,
}

impl fmt::Debug for CandidateEntry {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CandidateEntry")
            .field("text", &REDACTED)
            .field("annotation", &REDACTED)
            .field("correctedStart", &self.corrected_start)
            .field("correctedLength", &self.corrected_length)
            .finish()
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CandidateFocus {
    Candidate,
    Variants,
}

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
    #[serde(rename = "isCorrected")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub is_corrected: Option<bool>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub split: Option<BranchSplit>,
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
            .field("isCorrected", &self.is_corrected)
            .field("preview", &REDACTED)
            .field("shorter", &REDACTED)
            .field("longer", &REDACTED)
            .field("usageNote", &REDACTED)
            .field("alternativeNotes", &REDACTED)
            .field("sourceName", &REDACTED)
            .field("split", &self.split)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct BranchSplit {
    pub pieces: Vec<String>,
}

impl fmt::Debug for BranchSplit {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("BranchSplit")
            .field("pieces", &REDACTED)
            .finish()
    }
}

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

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct BranchMap {
    pub columns: Vec<BranchColumn>,
    pub position: u32,
    pub total: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
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

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct Color {
    pub red: u8,
    pub green: u8,
    pub blue: u8,
}

impl fmt::Debug for Color {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Color")
            .field("red", &self.red)
            .field("green", &self.green)
            .field("blue", &self.blue)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct CustomTheme {
    pub base: String,
    pub surface: Color,
    pub text: Color,
    #[serde(rename = "textMuted")]
    pub text_muted: Color,
    pub selection: Color,
    #[serde(rename = "selectionText")]
    pub selection_text: Color,
    pub correction: Color,
    pub line: Color,
    #[serde(rename = "fontName")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub font_name: Option<String>,
    #[serde(rename = "cornerRadius")]
    pub corner_radius: f64,
    #[serde(rename = "straightBranches")]
    pub straight_branches: bool,
}

impl fmt::Debug for CustomTheme {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("CustomTheme")
            .field("base", &REDACTED)
            .field("surface", &self.surface)
            .field("text", &self.text)
            .field("textMuted", &self.text_muted)
            .field("selection", &self.selection)
            .field("selectionText", &self.selection_text)
            .field("correction", &self.correction)
            .field("line", &self.line)
            .field("fontName", &REDACTED)
            .field("cornerRadius", &self.corner_radius)
            .field("straightBranches", &self.straight_branches)
            .finish()
    }
}

#[derive(Clone, PartialEq, Serialize, Deserialize)]
pub struct Presentation {
    pub theme: String,
    #[serde(rename = "fontSize")]
    pub font_size: f64,
    #[serde(rename = "modeIndicatorMilliseconds")]
    pub mode_indicator_milliseconds: u32,
    #[serde(rename = "customTheme")]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub custom_theme: Option<CustomTheme>,
}

impl fmt::Debug for Presentation {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Presentation")
            .field("theme", &REDACTED)
            .field("fontSize", &self.font_size)
            .field("modeIndicatorMilliseconds", &self.mode_indicator_milliseconds)
            .field("customTheme", &self.custom_theme)
            .finish()
    }
}

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
    ShowNote {
        text: String,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        anchor: Option<Rect>,
    },
    ShowMode {
        mode: InputMode,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        anchor: Option<Rect>,
        #[serde(default, skip_serializing_if = "Option::is_none")]
        label: Option<String>,
    },
    ShowHandwriting {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        anchor: Option<Rect>,
        #[serde(rename = "recognitionDelayMilliseconds")]
        recognition_delay_milliseconds: u32,
        #[serde(rename = "recognitionTimeoutMilliseconds")]
        recognition_timeout_milliseconds: u32,
    },
    HideHandwriting,
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
                .field("label", &REDACTED)
                .finish(),
            Self::ShowHandwriting { anchor, recognition_delay_milliseconds, recognition_timeout_milliseconds, .. } => f
                .debug_struct("ShowHandwriting")
                .field("anchor", anchor)
                .field("recognitionDelayMilliseconds", recognition_delay_milliseconds)
                .field("recognitionTimeoutMilliseconds", recognition_timeout_milliseconds)
                .finish(),
            Self::HideHandwriting => f.write_str("HideHandwriting"),
            Self::Move { anchor, .. } => f
                .debug_struct("Move")
                .field("anchor", anchor)
                .finish(),
            Self::Hide => f.write_str("Hide"),
        }
    }
}
