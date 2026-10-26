public enum WireProtocol {
    public static let version: UInt32 = 1
    public static let maximumMessageBytes = 262144
}

public enum WireInputMode: String, Sendable, Equatable, Codable, CaseIterable {
    case japanese
    case direct
}

extension WireInputMode: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireInputMode.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireModifiers: Sendable, Equatable, Codable {
    public var shift: Bool
    public var control: Bool
    public var alt: Bool

    public init(shift: Bool, control: Bool, alt: Bool) {
        self.shift = shift
        self.control = control
        self.alt = alt
    }
}

extension WireModifiers: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireModifiers" }
    public var debugDescription: String { description }
}

public enum WireKey: Sendable, Equatable, Codable {
    case character(text: String)
    case space
    case enter
    case backspace
    case delete
    case escape
    case tab
    case up
    case down
    case left
    case right
    case home
    case end
    case pageUp
    case pageDown
    case eisu
    case kana
    case yen
    case function(number: UInt8)
    case hankakuZenkaku
    case henkan
    case muhenkan

    private enum CodingKeys: String, CodingKey {
        case kind, text, number
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "character":
            self = try .character(text: container.decode(String.self, forKey: .text))
        case "space":
            self = .space
        case "enter":
            self = .enter
        case "backspace":
            self = .backspace
        case "delete":
            self = .delete
        case "escape":
            self = .escape
        case "tab":
            self = .tab
        case "up":
            self = .up
        case "down":
            self = .down
        case "left":
            self = .left
        case "right":
            self = .right
        case "home":
            self = .home
        case "end":
            self = .end
        case "pageUp":
            self = .pageUp
        case "pageDown":
            self = .pageDown
        case "eisu":
            self = .eisu
        case "kana":
            self = .kana
        case "yen":
            self = .yen
        case "function":
            self = try .function(number: container.decode(UInt8.self, forKey: .number))
        case "hankakuZenkaku":
            self = .hankakuZenkaku
        case "henkan":
            self = .henkan
        case "muhenkan":
            self = .muhenkan
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "知らない種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .character(let text):
            try container.encode("character", forKey: .kind)
            try container.encode(text, forKey: .text)
        case .space:
            try container.encode("space", forKey: .kind)
        case .enter:
            try container.encode("enter", forKey: .kind)
        case .backspace:
            try container.encode("backspace", forKey: .kind)
        case .delete:
            try container.encode("delete", forKey: .kind)
        case .escape:
            try container.encode("escape", forKey: .kind)
        case .tab:
            try container.encode("tab", forKey: .kind)
        case .up:
            try container.encode("up", forKey: .kind)
        case .down:
            try container.encode("down", forKey: .kind)
        case .left:
            try container.encode("left", forKey: .kind)
        case .right:
            try container.encode("right", forKey: .kind)
        case .home:
            try container.encode("home", forKey: .kind)
        case .end:
            try container.encode("end", forKey: .kind)
        case .pageUp:
            try container.encode("pageUp", forKey: .kind)
        case .pageDown:
            try container.encode("pageDown", forKey: .kind)
        case .eisu:
            try container.encode("eisu", forKey: .kind)
        case .kana:
            try container.encode("kana", forKey: .kind)
        case .yen:
            try container.encode("yen", forKey: .kind)
        case .function(let number):
            try container.encode("function", forKey: .kind)
            try container.encode(number, forKey: .number)
        case .hankakuZenkaku:
            try container.encode("hankakuZenkaku", forKey: .kind)
        case .henkan:
            try container.encode("henkan", forKey: .kind)
        case .muhenkan:
            try container.encode("muhenkan", forKey: .kind)
        }
    }
}

extension WireKey: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .character: "WireKey.character"
        case .space: "WireKey.space"
        case .enter: "WireKey.enter"
        case .backspace: "WireKey.backspace"
        case .delete: "WireKey.delete"
        case .escape: "WireKey.escape"
        case .tab: "WireKey.tab"
        case .up: "WireKey.up"
        case .down: "WireKey.down"
        case .left: "WireKey.left"
        case .right: "WireKey.right"
        case .home: "WireKey.home"
        case .end: "WireKey.end"
        case .pageUp: "WireKey.pageUp"
        case .pageDown: "WireKey.pageDown"
        case .eisu: "WireKey.eisu"
        case .kana: "WireKey.kana"
        case .yen: "WireKey.yen"
        case .function: "WireKey.function"
        case .hankakuZenkaku: "WireKey.hankakuZenkaku"
        case .henkan: "WireKey.henkan"
        case .muhenkan: "WireKey.muhenkan"
        }
    }
    public var debugDescription: String { description }
}

public struct WireKeyInput: Sendable, Equatable, Codable {
    public var key: WireKey
    public var modifiers: WireModifiers
    public var keyLabel: String?
    public var isKeypad: Bool

    public init(key: WireKey, modifiers: WireModifiers, keyLabel: String? = nil, isKeypad: Bool) {
        self.key = key
        self.modifiers = modifiers
        self.keyLabel = keyLabel
        self.isKeypad = isKeypad
    }
}

extension WireKeyInput: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireKeyInput" }
    public var debugDescription: String { description }
}

public struct WireKeyChord: Sendable, Equatable, Codable {
    public var key: WireKey
    public var modifiers: WireModifiers

    public init(key: WireKey, modifiers: WireModifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}

extension WireKeyChord: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireKeyChord" }
    public var debugDescription: String { description }
}

public struct WireRect: Sendable, Equatable, Codable {
    public var x: Int32
    public var y: Int32
    public var width: Int32
    public var height: Int32

    public init(x: Int32, y: Int32, width: Int32, height: Int32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

extension WireRect: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireRect" }
    public var debugDescription: String { description }
}

public struct WireFieldContext: Sendable, Equatable, Codable {
    public var applicationId: String?
    public var isSecure: Bool
    public var precedingText: String?
    public var caret: WireRect?

    public init(applicationId: String? = nil, isSecure: Bool, precedingText: String? = nil, caret: WireRect? = nil) {
        self.applicationId = applicationId
        self.isSecure = isSecure
        self.precedingText = precedingText
        self.caret = caret
    }
}

extension WireFieldContext: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireFieldContext" }
    public var debugDescription: String { description }
}

public struct WireSessionState: Sendable, Equatable, Codable {
    public var mode: WireInputMode
    public var isComposing: Bool
    public var consumedKeys: [WireKeyChord]
    public var wakeAfterMilliseconds: UInt32?
    public var precedingTextLength: UInt32?
    public var keyboardLayout: String?

    public init(mode: WireInputMode, isComposing: Bool, consumedKeys: [WireKeyChord], wakeAfterMilliseconds: UInt32? = nil, precedingTextLength: UInt32? = nil, keyboardLayout: String? = nil) {
        self.mode = mode
        self.isComposing = isComposing
        self.consumedKeys = consumedKeys
        self.wakeAfterMilliseconds = wakeAfterMilliseconds
        self.precedingTextLength = precedingTextLength
        self.keyboardLayout = keyboardLayout
    }
}

extension WireSessionState: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSessionState" }
    public var debugDescription: String { description }
}

public enum WireTextStyle: String, Sendable, Equatable, Codable, CaseIterable {
    case reading
    case converted
    case focused
    case correction
}

extension WireTextStyle: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireTextStyle.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireTextSegment: Sendable, Equatable, Codable {
    public var text: String
    public var style: WireTextStyle

    public init(text: String, style: WireTextStyle) {
        self.text = text
        self.style = style
    }
}

extension WireTextSegment: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireTextSegment" }
    public var debugDescription: String { description }
}

public enum WireEditOperation: Sendable, Equatable, Codable {
    case commit(text: String)
    case setComposition(segments: [WireTextSegment])
    case selectMode(mode: WireInputMode)

    private enum CodingKeys: String, CodingKey {
        case type, text, segments, mode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .type)
        switch kind {
        case "commit":
            self = try .commit(text: container.decode(String.self, forKey: .text))
        case "setComposition":
            self = try .setComposition(segments: container.decode([WireTextSegment].self, forKey: .segments))
        case "selectMode":
            self = try .selectMode(mode: container.decode(WireInputMode.self, forKey: .mode))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "知らない種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .commit(let text):
            try container.encode("commit", forKey: .type)
            try container.encode(text, forKey: .text)
        case .setComposition(let segments):
            try container.encode("setComposition", forKey: .type)
            try container.encode(segments, forKey: .segments)
        case .selectMode(let mode):
            try container.encode("selectMode", forKey: .type)
            try container.encode(mode, forKey: .mode)
        }
    }
}

extension WireEditOperation: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .commit: "WireEditOperation.commit"
        case .setComposition: "WireEditOperation.setComposition"
        case .selectMode: "WireEditOperation.selectMode"
        }
    }
    public var debugDescription: String { description }
}

public enum WireErrorCode: String, Sendable, Equatable, Codable, CaseIterable {
    case unsupportedVersion
    case unknownSession
    case tooManySessions
    case malformed
    case tooLarge
}

extension WireErrorCode: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireErrorCode.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireSettingsSnapshot: Sendable, Equatable, Codable {
    public var theme: String
    public var inputStyle: String
    public var liveConversion: Bool
    public var showsModeIndicator: Bool
    public var showsKeyHints: Bool
    public var candidateFontSize: Double

    public init(theme: String, inputStyle: String, liveConversion: Bool, showsModeIndicator: Bool, showsKeyHints: Bool, candidateFontSize: Double) {
        self.theme = theme
        self.inputStyle = inputStyle
        self.liveConversion = liveConversion
        self.showsModeIndicator = showsModeIndicator
        self.showsKeyHints = showsKeyHints
        self.candidateFontSize = candidateFontSize
    }
}

extension WireSettingsSnapshot: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSettingsSnapshot" }
    public var debugDescription: String { description }
}

public enum WireMenuCommand: Sendable, Equatable, Codable {
    case toggleLiveConversion
    case openSettings

    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .type)
        switch kind {
        case "toggleLiveConversion":
            self = .toggleLiveConversion
        case "openSettings":
            self = .openSettings
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "知らない種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .toggleLiveConversion:
            try container.encode("toggleLiveConversion", forKey: .type)
        case .openSettings:
            try container.encode("openSettings", forKey: .type)
        }
    }
}

extension WireMenuCommand: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .toggleLiveConversion: "WireMenuCommand.toggleLiveConversion"
        case .openSettings: "WireMenuCommand.openSettings"
        }
    }
    public var debugDescription: String { description }
}

public struct WireKeymapRowIssue: Sendable, Equatable, Codable {
    public var row: UInt32
    public var hiddenBy: [UInt32]
    public var hiddenStates: [String]
    public var blocksTyping: Bool

    public init(row: UInt32, hiddenBy: [UInt32], hiddenStates: [String], blocksTyping: Bool) {
        self.row = row
        self.hiddenBy = hiddenBy
        self.hiddenStates = hiddenStates
        self.blocksTyping = blocksTyping
    }
}

extension WireKeymapRowIssue: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireKeymapRowIssue" }
    public var debugDescription: String { description }
}

public struct WireKeymapMissing: Sendable, Equatable, Codable {
    public var state: String
    public var command: String

    public init(state: String, command: String) {
        self.state = state
        self.command = command
    }
}

extension WireKeymapMissing: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireKeymapMissing" }
    public var debugDescription: String { description }
}

public struct WireKeymapReport: Sendable, Equatable, Codable {
    public var rows: [WireKeymapRowIssue]
    public var missing: [WireKeymapMissing]

    public init(rows: [WireKeymapRowIssue], missing: [WireKeymapMissing]) {
        self.rows = rows
        self.missing = missing
    }
}

extension WireKeymapReport: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireKeymapReport" }
    public var debugDescription: String { description }
}

public struct WirePreviewWord: Sendable, Equatable, Codable {
    public var typed: String
    public var shown: String
    public var language: String

    public init(typed: String, shown: String, language: String) {
        self.typed = typed
        self.shown = shown
        self.language = language
    }
}

extension WirePreviewWord: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePreviewWord" }
    public var debugDescription: String { description }
}

public struct WireDictionaryEntry: Sendable, Equatable, Codable {
    public var reading: String
    public var word: String

    public init(reading: String, word: String) {
        self.reading = reading
        self.word = word
    }
}

extension WireDictionaryEntry: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireDictionaryEntry" }
    public var debugDescription: String { description }
}

public enum WireDictionaryAddResult: String, Sendable, Equatable, Codable, CaseIterable {
    case added
    case alreadyRegistered
    case invalid
    case full
}

extension WireDictionaryAddResult: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireDictionaryAddResult.\(rawValue)" }
    public var debugDescription: String { description }
}

public enum WireRequestBody: Sendable, Equatable, Codable {
    case hello(protocolVersion: UInt32)
    case openSession
    case closeSession(session: UInt32)
    case key(session: UInt32, input: WireKeyInput, context: WireFieldContext)
    case setMode(session: UInt32, mode: WireInputMode)
    case deactivate(session: UInt32)
    case wake(session: UInt32, context: WireFieldContext)
    case caret(session: UInt32, rect: WireRect)
    case readSettings
    case writeSettings(settings: WireSettingsSnapshot)
    case menu(command: WireMenuCommand)
    case handwritingChosen(text: String)
    case handwritingClosed
    case readSettingsFields(names: [String], defaults: Bool)
    case writeSettingsFields(values: String)
    case readKeymapPreset(preset: String)
    case checkKeymap(values: String)
    case resetLearning
    case readUsage
    case resetUsage
    case previewLanguage(text: String, precedingText: String?)
    case readUserDictionary(offset: UInt32, limit: UInt32)
    case addUserDictionaryEntry(entry: WireDictionaryEntry)
    case removeUserDictionaryEntry(entry: WireDictionaryEntry)
    case mergeUserDictionary(entries: [WireDictionaryEntry])

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, session, input, context, mode, rect, settings, command, text, names, defaults, values, preset, precedingText, offset, limit, entry, entries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .type)
        switch kind {
        case "hello":
            self = try .hello(protocolVersion: container.decode(UInt32.self, forKey: .protocolVersion))
        case "openSession":
            self = .openSession
        case "closeSession":
            self = try .closeSession(session: container.decode(UInt32.self, forKey: .session))
        case "key":
            self = try .key(session: container.decode(UInt32.self, forKey: .session), input: container.decode(WireKeyInput.self, forKey: .input), context: container.decode(WireFieldContext.self, forKey: .context))
        case "setMode":
            self = try .setMode(session: container.decode(UInt32.self, forKey: .session), mode: container.decode(WireInputMode.self, forKey: .mode))
        case "deactivate":
            self = try .deactivate(session: container.decode(UInt32.self, forKey: .session))
        case "wake":
            self = try .wake(session: container.decode(UInt32.self, forKey: .session), context: container.decode(WireFieldContext.self, forKey: .context))
        case "caret":
            self = try .caret(session: container.decode(UInt32.self, forKey: .session), rect: container.decode(WireRect.self, forKey: .rect))
        case "readSettings":
            self = .readSettings
        case "writeSettings":
            self = try .writeSettings(settings: container.decode(WireSettingsSnapshot.self, forKey: .settings))
        case "menu":
            self = try .menu(command: container.decode(WireMenuCommand.self, forKey: .command))
        case "handwritingChosen":
            self = try .handwritingChosen(text: container.decode(String.self, forKey: .text))
        case "handwritingClosed":
            self = .handwritingClosed
        case "readSettingsFields":
            self = try .readSettingsFields(names: container.decode([String].self, forKey: .names), defaults: container.decode(Bool.self, forKey: .defaults))
        case "writeSettingsFields":
            self = try .writeSettingsFields(values: container.decode(String.self, forKey: .values))
        case "readKeymapPreset":
            self = try .readKeymapPreset(preset: container.decode(String.self, forKey: .preset))
        case "checkKeymap":
            self = try .checkKeymap(values: container.decode(String.self, forKey: .values))
        case "resetLearning":
            self = .resetLearning
        case "readUsage":
            self = .readUsage
        case "resetUsage":
            self = .resetUsage
        case "previewLanguage":
            self = try .previewLanguage(text: container.decode(String.self, forKey: .text), precedingText: container.decodeIfPresent(String.self, forKey: .precedingText))
        case "readUserDictionary":
            self = try .readUserDictionary(offset: container.decode(UInt32.self, forKey: .offset), limit: container.decode(UInt32.self, forKey: .limit))
        case "addUserDictionaryEntry":
            self = try .addUserDictionaryEntry(entry: container.decode(WireDictionaryEntry.self, forKey: .entry))
        case "removeUserDictionaryEntry":
            self = try .removeUserDictionaryEntry(entry: container.decode(WireDictionaryEntry.self, forKey: .entry))
        case "mergeUserDictionary":
            self = try .mergeUserDictionary(entries: container.decode([WireDictionaryEntry].self, forKey: .entries))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "知らない種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let protocolVersion):
            try container.encode("hello", forKey: .type)
            try container.encode(protocolVersion, forKey: .protocolVersion)
        case .openSession:
            try container.encode("openSession", forKey: .type)
        case .closeSession(let session):
            try container.encode("closeSession", forKey: .type)
            try container.encode(session, forKey: .session)
        case .key(let session, let input, let context):
            try container.encode("key", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(input, forKey: .input)
            try container.encode(context, forKey: .context)
        case .setMode(let session, let mode):
            try container.encode("setMode", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(mode, forKey: .mode)
        case .deactivate(let session):
            try container.encode("deactivate", forKey: .type)
            try container.encode(session, forKey: .session)
        case .wake(let session, let context):
            try container.encode("wake", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(context, forKey: .context)
        case .caret(let session, let rect):
            try container.encode("caret", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(rect, forKey: .rect)
        case .readSettings:
            try container.encode("readSettings", forKey: .type)
        case .writeSettings(let settings):
            try container.encode("writeSettings", forKey: .type)
            try container.encode(settings, forKey: .settings)
        case .menu(let command):
            try container.encode("menu", forKey: .type)
            try container.encode(command, forKey: .command)
        case .handwritingChosen(let text):
            try container.encode("handwritingChosen", forKey: .type)
            try container.encode(text, forKey: .text)
        case .handwritingClosed:
            try container.encode("handwritingClosed", forKey: .type)
        case .readSettingsFields(let names, let defaults):
            try container.encode("readSettingsFields", forKey: .type)
            try container.encode(names, forKey: .names)
            try container.encode(defaults, forKey: .defaults)
        case .writeSettingsFields(let values):
            try container.encode("writeSettingsFields", forKey: .type)
            try container.encode(values, forKey: .values)
        case .readKeymapPreset(let preset):
            try container.encode("readKeymapPreset", forKey: .type)
            try container.encode(preset, forKey: .preset)
        case .checkKeymap(let values):
            try container.encode("checkKeymap", forKey: .type)
            try container.encode(values, forKey: .values)
        case .resetLearning:
            try container.encode("resetLearning", forKey: .type)
        case .readUsage:
            try container.encode("readUsage", forKey: .type)
        case .resetUsage:
            try container.encode("resetUsage", forKey: .type)
        case .previewLanguage(let text, let precedingText):
            try container.encode("previewLanguage", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(precedingText, forKey: .precedingText)
        case .readUserDictionary(let offset, let limit):
            try container.encode("readUserDictionary", forKey: .type)
            try container.encode(offset, forKey: .offset)
            try container.encode(limit, forKey: .limit)
        case .addUserDictionaryEntry(let entry):
            try container.encode("addUserDictionaryEntry", forKey: .type)
            try container.encode(entry, forKey: .entry)
        case .removeUserDictionaryEntry(let entry):
            try container.encode("removeUserDictionaryEntry", forKey: .type)
            try container.encode(entry, forKey: .entry)
        case .mergeUserDictionary(let entries):
            try container.encode("mergeUserDictionary", forKey: .type)
            try container.encode(entries, forKey: .entries)
        }
    }
}

extension WireRequestBody: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .hello: "WireRequestBody.hello"
        case .openSession: "WireRequestBody.openSession"
        case .closeSession: "WireRequestBody.closeSession"
        case .key: "WireRequestBody.key"
        case .setMode: "WireRequestBody.setMode"
        case .deactivate: "WireRequestBody.deactivate"
        case .wake: "WireRequestBody.wake"
        case .caret: "WireRequestBody.caret"
        case .readSettings: "WireRequestBody.readSettings"
        case .writeSettings: "WireRequestBody.writeSettings"
        case .menu: "WireRequestBody.menu"
        case .handwritingChosen: "WireRequestBody.handwritingChosen"
        case .handwritingClosed: "WireRequestBody.handwritingClosed"
        case .readSettingsFields: "WireRequestBody.readSettingsFields"
        case .writeSettingsFields: "WireRequestBody.writeSettingsFields"
        case .readKeymapPreset: "WireRequestBody.readKeymapPreset"
        case .checkKeymap: "WireRequestBody.checkKeymap"
        case .resetLearning: "WireRequestBody.resetLearning"
        case .readUsage: "WireRequestBody.readUsage"
        case .resetUsage: "WireRequestBody.resetUsage"
        case .previewLanguage: "WireRequestBody.previewLanguage"
        case .readUserDictionary: "WireRequestBody.readUserDictionary"
        case .addUserDictionaryEntry: "WireRequestBody.addUserDictionaryEntry"
        case .removeUserDictionaryEntry: "WireRequestBody.removeUserDictionaryEntry"
        case .mergeUserDictionary: "WireRequestBody.mergeUserDictionary"
        }
    }
    public var debugDescription: String { description }
}

public struct WireRequest: Sendable, Equatable, Codable {
    public var id: UInt32
    public var body: WireRequestBody

    public init(id: UInt32, body: WireRequestBody) {
        self.id = id
        self.body = body
    }
}

extension WireRequest: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireRequest" }
    public var debugDescription: String { description }
}

public enum WireResponseBody: Sendable, Equatable, Codable {
    case hello(protocolVersion: UInt32)
    case sessionOpened(session: UInt32, state: WireSessionState)
    case edit(handled: Bool, operations: [WireEditOperation], state: WireSessionState)
    case done
    case settings(settings: WireSettingsSnapshot)
    case settingsFields(values: String)
    case keymapReport(report: WireKeymapReport)
    case usage(values: String, firstCandidateRate: Double?)
    case languagePreview(words: [WirePreviewWord])
    case userDictionary(entries: [WireDictionaryEntry], total: UInt32)
    case dictionaryAdded(result: WireDictionaryAddResult)
    case dictionaryMerged(added: UInt32)
    case error(code: WireErrorCode)

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, session, state, handled, operations, settings, values, report, firstCandidateRate, words, entries, total, result, added, code
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .type)
        switch kind {
        case "hello":
            self = try .hello(protocolVersion: container.decode(UInt32.self, forKey: .protocolVersion))
        case "sessionOpened":
            self = try .sessionOpened(session: container.decode(UInt32.self, forKey: .session), state: container.decode(WireSessionState.self, forKey: .state))
        case "edit":
            self = try .edit(handled: container.decode(Bool.self, forKey: .handled), operations: container.decode([WireEditOperation].self, forKey: .operations), state: container.decode(WireSessionState.self, forKey: .state))
        case "done":
            self = .done
        case "settings":
            self = try .settings(settings: container.decode(WireSettingsSnapshot.self, forKey: .settings))
        case "settingsFields":
            self = try .settingsFields(values: container.decode(String.self, forKey: .values))
        case "keymapReport":
            self = try .keymapReport(report: container.decode(WireKeymapReport.self, forKey: .report))
        case "usage":
            self = try .usage(values: container.decode(String.self, forKey: .values), firstCandidateRate: container.decodeIfPresent(Double.self, forKey: .firstCandidateRate))
        case "languagePreview":
            self = try .languagePreview(words: container.decode([WirePreviewWord].self, forKey: .words))
        case "userDictionary":
            self = try .userDictionary(entries: container.decode([WireDictionaryEntry].self, forKey: .entries), total: container.decode(UInt32.self, forKey: .total))
        case "dictionaryAdded":
            self = try .dictionaryAdded(result: container.decode(WireDictionaryAddResult.self, forKey: .result))
        case "dictionaryMerged":
            self = try .dictionaryMerged(added: container.decode(UInt32.self, forKey: .added))
        case "error":
            self = try .error(code: container.decode(WireErrorCode.self, forKey: .code))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "知らない種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let protocolVersion):
            try container.encode("hello", forKey: .type)
            try container.encode(protocolVersion, forKey: .protocolVersion)
        case .sessionOpened(let session, let state):
            try container.encode("sessionOpened", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(state, forKey: .state)
        case .edit(let handled, let operations, let state):
            try container.encode("edit", forKey: .type)
            try container.encode(handled, forKey: .handled)
            try container.encode(operations, forKey: .operations)
            try container.encode(state, forKey: .state)
        case .done:
            try container.encode("done", forKey: .type)
        case .settings(let settings):
            try container.encode("settings", forKey: .type)
            try container.encode(settings, forKey: .settings)
        case .settingsFields(let values):
            try container.encode("settingsFields", forKey: .type)
            try container.encode(values, forKey: .values)
        case .keymapReport(let report):
            try container.encode("keymapReport", forKey: .type)
            try container.encode(report, forKey: .report)
        case .usage(let values, let firstCandidateRate):
            try container.encode("usage", forKey: .type)
            try container.encode(values, forKey: .values)
            try container.encodeIfPresent(firstCandidateRate, forKey: .firstCandidateRate)
        case .languagePreview(let words):
            try container.encode("languagePreview", forKey: .type)
            try container.encode(words, forKey: .words)
        case .userDictionary(let entries, let total):
            try container.encode("userDictionary", forKey: .type)
            try container.encode(entries, forKey: .entries)
            try container.encode(total, forKey: .total)
        case .dictionaryAdded(let result):
            try container.encode("dictionaryAdded", forKey: .type)
            try container.encode(result, forKey: .result)
        case .dictionaryMerged(let added):
            try container.encode("dictionaryMerged", forKey: .type)
            try container.encode(added, forKey: .added)
        case .error(let code):
            try container.encode("error", forKey: .type)
            try container.encode(code, forKey: .code)
        }
    }
}

extension WireResponseBody: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .hello: "WireResponseBody.hello"
        case .sessionOpened: "WireResponseBody.sessionOpened"
        case .edit: "WireResponseBody.edit"
        case .done: "WireResponseBody.done"
        case .settings: "WireResponseBody.settings"
        case .settingsFields: "WireResponseBody.settingsFields"
        case .keymapReport: "WireResponseBody.keymapReport"
        case .usage: "WireResponseBody.usage"
        case .languagePreview: "WireResponseBody.languagePreview"
        case .userDictionary: "WireResponseBody.userDictionary"
        case .dictionaryAdded: "WireResponseBody.dictionaryAdded"
        case .dictionaryMerged: "WireResponseBody.dictionaryMerged"
        case .error: "WireResponseBody.error"
        }
    }
    public var debugDescription: String { description }
}

public struct WireResponse: Sendable, Equatable, Codable {
    public var id: UInt32
    public var body: WireResponseBody

    public init(id: UInt32, body: WireResponseBody) {
        self.id = id
        self.body = body
    }
}

extension WireResponse: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireResponse" }
    public var debugDescription: String { description }
}

public struct WireCandidateVariant: Sendable, Equatable, Codable {
    public var label: String
    public var isAvailable: Bool

    public init(label: String, isAvailable: Bool) {
        self.label = label
        self.isAvailable = isAvailable
    }
}

extension WireCandidateVariant: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireCandidateVariant" }
    public var debugDescription: String { description }
}

public struct WireCandidateEntry: Sendable, Equatable, Codable {
    public var text: String
    public var annotation: String?
    public var correctedStart: UInt32?
    public var correctedLength: UInt32?

    public init(text: String, annotation: String? = nil, correctedStart: UInt32? = nil, correctedLength: UInt32? = nil) {
        self.text = text
        self.annotation = annotation
        self.correctedStart = correctedStart
        self.correctedLength = correctedLength
    }
}

extension WireCandidateEntry: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireCandidateEntry" }
    public var debugDescription: String { description }
}

public enum WireCandidateFocus: String, Sendable, Equatable, Codable, CaseIterable {
    case candidate
    case variants
}

extension WireCandidateFocus: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireCandidateFocus.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireCandidateList: Sendable, Equatable, Codable {
    public var variants: [WireCandidateVariant]
    public var selectedVariant: UInt32?
    public var entries: [WireCandidateEntry]
    public var selectedEntry: UInt32?
    public var focus: WireCandidateFocus
    public var position: UInt32
    public var total: UInt32
    public var note: String?

    public init(variants: [WireCandidateVariant], selectedVariant: UInt32? = nil, entries: [WireCandidateEntry], selectedEntry: UInt32? = nil, focus: WireCandidateFocus, position: UInt32, total: UInt32, note: String? = nil) {
        self.variants = variants
        self.selectedVariant = selectedVariant
        self.entries = entries
        self.selectedEntry = selectedEntry
        self.focus = focus
        self.position = position
        self.total = total
        self.note = note
    }
}

extension WireCandidateList: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireCandidateList" }
    public var debugDescription: String { description }
}

public struct WireBranchColumn: Sendable, Equatable, Codable {
    public var text: String
    public var alternatives: [String]
    public var selectedAlternative: UInt32?
    public var variants: [String]
    public var selectedVariant: UInt32?
    public var isFocused: Bool
    public var isUncertain: Bool
    public var isDecided: Bool
    public var isCorrected: Bool?
    public var preview: String?
    public var shorter: String?
    public var longer: String?
    public var usageNote: String?
    public var alternativeNotes: [String?]
    public var sourceName: String?
    public var split: WireBranchSplit?

    public init(text: String, alternatives: [String], selectedAlternative: UInt32? = nil, variants: [String], selectedVariant: UInt32? = nil, isFocused: Bool, isUncertain: Bool, isDecided: Bool, isCorrected: Bool? = nil, preview: String? = nil, shorter: String? = nil, longer: String? = nil, usageNote: String? = nil, alternativeNotes: [String?], sourceName: String? = nil, split: WireBranchSplit? = nil) {
        self.text = text
        self.alternatives = alternatives
        self.selectedAlternative = selectedAlternative
        self.variants = variants
        self.selectedVariant = selectedVariant
        self.isFocused = isFocused
        self.isUncertain = isUncertain
        self.isDecided = isDecided
        self.isCorrected = isCorrected
        self.preview = preview
        self.shorter = shorter
        self.longer = longer
        self.usageNote = usageNote
        self.alternativeNotes = alternativeNotes
        self.sourceName = sourceName
        self.split = split
    }
}

extension WireBranchColumn: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireBranchColumn" }
    public var debugDescription: String { description }
}

public struct WireBranchSplit: Sendable, Equatable, Codable {
    public var pieces: [String]

    public init(pieces: [String]) {
        self.pieces = pieces
    }
}

extension WireBranchSplit: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireBranchSplit" }
    public var debugDescription: String { description }
}

public struct WireKeyHint: Sendable, Equatable, Codable {
    public var keys: String
    public var label: String

    public init(keys: String, label: String) {
        self.keys = keys
        self.label = label
    }
}

extension WireKeyHint: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireKeyHint" }
    public var debugDescription: String { description }
}

public struct WireBranchMap: Sendable, Equatable, Codable {
    public var columns: [WireBranchColumn]
    public var position: UInt32
    public var total: UInt32
    public var note: String?
    public var hints: [WireKeyHint]

    public init(columns: [WireBranchColumn], position: UInt32, total: UInt32, note: String? = nil, hints: [WireKeyHint]) {
        self.columns = columns
        self.position = position
        self.total = total
        self.note = note
        self.hints = hints
    }
}

extension WireBranchMap: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireBranchMap" }
    public var debugDescription: String { description }
}

public struct WireColor: Sendable, Equatable, Codable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

extension WireColor: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireColor" }
    public var debugDescription: String { description }
}

public struct WireCustomTheme: Sendable, Equatable, Codable {
    public var base: String
    public var surface: WireColor
    public var text: WireColor
    public var textMuted: WireColor
    public var selection: WireColor
    public var selectionText: WireColor
    public var correction: WireColor
    public var line: WireColor
    public var fontName: String?
    public var cornerRadius: Double
    public var straightBranches: Bool

    public init(base: String, surface: WireColor, text: WireColor, textMuted: WireColor, selection: WireColor, selectionText: WireColor, correction: WireColor, line: WireColor, fontName: String? = nil, cornerRadius: Double, straightBranches: Bool) {
        self.base = base
        self.surface = surface
        self.text = text
        self.textMuted = textMuted
        self.selection = selection
        self.selectionText = selectionText
        self.correction = correction
        self.line = line
        self.fontName = fontName
        self.cornerRadius = cornerRadius
        self.straightBranches = straightBranches
    }
}

extension WireCustomTheme: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireCustomTheme" }
    public var debugDescription: String { description }
}

public struct WirePresentation: Sendable, Equatable, Codable {
    public var theme: String
    public var fontSize: Double
    public var modeIndicatorMilliseconds: UInt32
    public var customTheme: WireCustomTheme?

    public init(theme: String, fontSize: Double, modeIndicatorMilliseconds: UInt32, customTheme: WireCustomTheme? = nil) {
        self.theme = theme
        self.fontSize = fontSize
        self.modeIndicatorMilliseconds = modeIndicatorMilliseconds
        self.customTheme = customTheme
    }
}

extension WirePresentation: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePresentation" }
    public var debugDescription: String { description }
}

public enum WireUiCommand: Sendable, Equatable, Codable {
    case hello(protocolVersion: UInt32)
    case setPresentation(presentation: WirePresentation)
    case showCandidates(list: WireCandidateList, anchor: WireRect?)
    case showBranchMap(map: WireBranchMap, anchor: WireRect?)
    case showNote(text: String, anchor: WireRect?)
    case showMode(mode: WireInputMode, anchor: WireRect?, label: String?)
    case showHandwriting(anchor: WireRect?, recognitionDelayMilliseconds: UInt32, recognitionTimeoutMilliseconds: UInt32)
    case hideHandwriting
    case move(anchor: WireRect)
    case hide

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, presentation, list, anchor, map, text, mode, label, recognitionDelayMilliseconds, recognitionTimeoutMilliseconds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .type)
        switch kind {
        case "hello":
            self = try .hello(protocolVersion: container.decode(UInt32.self, forKey: .protocolVersion))
        case "setPresentation":
            self = try .setPresentation(presentation: container.decode(WirePresentation.self, forKey: .presentation))
        case "showCandidates":
            self = try .showCandidates(list: container.decode(WireCandidateList.self, forKey: .list), anchor: container.decodeIfPresent(WireRect.self, forKey: .anchor))
        case "showBranchMap":
            self = try .showBranchMap(map: container.decode(WireBranchMap.self, forKey: .map), anchor: container.decodeIfPresent(WireRect.self, forKey: .anchor))
        case "showNote":
            self = try .showNote(text: container.decode(String.self, forKey: .text), anchor: container.decodeIfPresent(WireRect.self, forKey: .anchor))
        case "showMode":
            self = try .showMode(mode: container.decode(WireInputMode.self, forKey: .mode), anchor: container.decodeIfPresent(WireRect.self, forKey: .anchor), label: container.decodeIfPresent(String.self, forKey: .label))
        case "showHandwriting":
            self = try .showHandwriting(anchor: container.decodeIfPresent(WireRect.self, forKey: .anchor), recognitionDelayMilliseconds: container.decode(UInt32.self, forKey: .recognitionDelayMilliseconds), recognitionTimeoutMilliseconds: container.decode(UInt32.self, forKey: .recognitionTimeoutMilliseconds))
        case "hideHandwriting":
            self = .hideHandwriting
        case "move":
            self = try .move(anchor: container.decode(WireRect.self, forKey: .anchor))
        case "hide":
            self = .hide
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "知らない種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let protocolVersion):
            try container.encode("hello", forKey: .type)
            try container.encode(protocolVersion, forKey: .protocolVersion)
        case .setPresentation(let presentation):
            try container.encode("setPresentation", forKey: .type)
            try container.encode(presentation, forKey: .presentation)
        case .showCandidates(let list, let anchor):
            try container.encode("showCandidates", forKey: .type)
            try container.encode(list, forKey: .list)
            try container.encodeIfPresent(anchor, forKey: .anchor)
        case .showBranchMap(let map, let anchor):
            try container.encode("showBranchMap", forKey: .type)
            try container.encode(map, forKey: .map)
            try container.encodeIfPresent(anchor, forKey: .anchor)
        case .showNote(let text, let anchor):
            try container.encode("showNote", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(anchor, forKey: .anchor)
        case .showMode(let mode, let anchor, let label):
            try container.encode("showMode", forKey: .type)
            try container.encode(mode, forKey: .mode)
            try container.encodeIfPresent(anchor, forKey: .anchor)
            try container.encodeIfPresent(label, forKey: .label)
        case .showHandwriting(let anchor, let recognitionDelayMilliseconds, let recognitionTimeoutMilliseconds):
            try container.encode("showHandwriting", forKey: .type)
            try container.encodeIfPresent(anchor, forKey: .anchor)
            try container.encode(recognitionDelayMilliseconds, forKey: .recognitionDelayMilliseconds)
            try container.encode(recognitionTimeoutMilliseconds, forKey: .recognitionTimeoutMilliseconds)
        case .hideHandwriting:
            try container.encode("hideHandwriting", forKey: .type)
        case .move(let anchor):
            try container.encode("move", forKey: .type)
            try container.encode(anchor, forKey: .anchor)
        case .hide:
            try container.encode("hide", forKey: .type)
        }
    }
}

extension WireUiCommand: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .hello: "WireUiCommand.hello"
        case .setPresentation: "WireUiCommand.setPresentation"
        case .showCandidates: "WireUiCommand.showCandidates"
        case .showBranchMap: "WireUiCommand.showBranchMap"
        case .showNote: "WireUiCommand.showNote"
        case .showMode: "WireUiCommand.showMode"
        case .showHandwriting: "WireUiCommand.showHandwriting"
        case .hideHandwriting: "WireUiCommand.hideHandwriting"
        case .move: "WireUiCommand.move"
        case .hide: "WireUiCommand.hide"
        }
    }
    public var debugDescription: String { description }
}
