public enum WireProtocol {
    public static let version: UInt32 = 4
    public static let maximumMessageBytes = 262144
    public static let keyResponseMilliseconds = 50
    public static let conversionResponseMilliseconds = 250
    public static let reconnectMilliseconds = 2000
    public static let engineStallMilliseconds = 3000
    public static let maximumLateKeys = 16
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
    public var canReplacePrecedingText: Bool?
    public var canShowMenu: Bool?
    public var canRequestWordRegistration: Bool?

    public init(applicationId: String? = nil, isSecure: Bool, precedingText: String? = nil, caret: WireRect? = nil, canReplacePrecedingText: Bool? = nil, canShowMenu: Bool? = nil, canRequestWordRegistration: Bool? = nil) {
        self.applicationId = applicationId
        self.isSecure = isSecure
        self.precedingText = precedingText
        self.caret = caret
        self.canReplacePrecedingText = canReplacePrecedingText
        self.canShowMenu = canShowMenu
        self.canRequestWordRegistration = canRequestWordRegistration
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
    case setComposition(segments: [WireTextSegment], caret: UInt32?, panelAnchor: UInt32?, replacedLength: UInt32?)
    case selectMode(mode: WireInputMode)
    case requestReconversion(maximumLength: UInt32)
    case requestWordRegistration(maximumLength: UInt32)
    case showMenu

    private enum CodingKeys: String, CodingKey {
        case type, text, segments, caret, panelAnchor, replacedLength, mode, maximumLength
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .type)
        switch kind {
        case "commit":
            self = try .commit(text: container.decode(String.self, forKey: .text))
        case "setComposition":
            self = try .setComposition(segments: container.decode([WireTextSegment].self, forKey: .segments), caret: container.decodeIfPresent(UInt32.self, forKey: .caret), panelAnchor: container.decodeIfPresent(UInt32.self, forKey: .panelAnchor), replacedLength: container.decodeIfPresent(UInt32.self, forKey: .replacedLength))
        case "selectMode":
            self = try .selectMode(mode: container.decode(WireInputMode.self, forKey: .mode))
        case "requestReconversion":
            self = try .requestReconversion(maximumLength: container.decode(UInt32.self, forKey: .maximumLength))
        case "requestWordRegistration":
            self = try .requestWordRegistration(maximumLength: container.decode(UInt32.self, forKey: .maximumLength))
        case "showMenu":
            self = .showMenu
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
        case .setComposition(let segments, let caret, let panelAnchor, let replacedLength):
            try container.encode("setComposition", forKey: .type)
            try container.encode(segments, forKey: .segments)
            try container.encodeIfPresent(caret, forKey: .caret)
            try container.encodeIfPresent(panelAnchor, forKey: .panelAnchor)
            try container.encodeIfPresent(replacedLength, forKey: .replacedLength)
        case .selectMode(let mode):
            try container.encode("selectMode", forKey: .type)
            try container.encode(mode, forKey: .mode)
        case .requestReconversion(let maximumLength):
            try container.encode("requestReconversion", forKey: .type)
            try container.encode(maximumLength, forKey: .maximumLength)
        case .requestWordRegistration(let maximumLength):
            try container.encode("requestWordRegistration", forKey: .type)
            try container.encode(maximumLength, forKey: .maximumLength)
        case .showMenu:
            try container.encode("showMenu", forKey: .type)
        }
    }
}

extension WireEditOperation: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .commit: "WireEditOperation.commit"
        case .setComposition: "WireEditOperation.setComposition"
        case .selectMode: "WireEditOperation.selectMode"
        case .requestReconversion: "WireEditOperation.requestReconversion"
        case .requestWordRegistration: "WireEditOperation.requestWordRegistration"
        case .showMenu: "WireEditOperation.showMenu"
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
    public var handwriting: Bool?
    public var palette: Bool?

    public init(theme: String, inputStyle: String, liveConversion: Bool, showsModeIndicator: Bool, showsKeyHints: Bool, candidateFontSize: Double, handwriting: Bool? = nil, palette: Bool? = nil) {
        self.theme = theme
        self.inputStyle = inputStyle
        self.liveConversion = liveConversion
        self.showsModeIndicator = showsModeIndicator
        self.showsKeyHints = showsKeyHints
        self.candidateFontSize = candidateFontSize
        self.handwriting = handwriting
        self.palette = palette
    }
}

extension WireSettingsSnapshot: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSettingsSnapshot" }
    public var debugDescription: String { description }
}

public enum WireMenuCommand: Sendable, Equatable, Codable {
    case toggleLiveConversion
    case openSettings
    case openUserDictionary

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
        case "openUserDictionary":
            self = .openUserDictionary
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
        case .openUserDictionary:
            try container.encode("openUserDictionary", forKey: .type)
        }
    }
}

extension WireMenuCommand: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .toggleLiveConversion: "WireMenuCommand.toggleLiveConversion"
        case .openSettings: "WireMenuCommand.openSettings"
        case .openUserDictionary: "WireMenuCommand.openUserDictionary"
        }
    }
    public var debugDescription: String { description }
}

public enum WirePointerTarget: Sendable, Equatable, Codable {
    case segment(index: UInt32)
    case alternative(index: UInt32)
    case variant(index: UInt32)
    case entry(index: UInt32)
    case listVariant(index: UInt32)
    case comment(index: UInt32)

    private enum CodingKeys: String, CodingKey {
        case type, index
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .type)
        switch kind {
        case "segment":
            self = try .segment(index: container.decode(UInt32.self, forKey: .index))
        case "alternative":
            self = try .alternative(index: container.decode(UInt32.self, forKey: .index))
        case "variant":
            self = try .variant(index: container.decode(UInt32.self, forKey: .index))
        case "entry":
            self = try .entry(index: container.decode(UInt32.self, forKey: .index))
        case "listVariant":
            self = try .listVariant(index: container.decode(UInt32.self, forKey: .index))
        case "comment":
            self = try .comment(index: container.decode(UInt32.self, forKey: .index))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "知らない種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .segment(let index):
            try container.encode("segment", forKey: .type)
            try container.encode(index, forKey: .index)
        case .alternative(let index):
            try container.encode("alternative", forKey: .type)
            try container.encode(index, forKey: .index)
        case .variant(let index):
            try container.encode("variant", forKey: .type)
            try container.encode(index, forKey: .index)
        case .entry(let index):
            try container.encode("entry", forKey: .type)
            try container.encode(index, forKey: .index)
        case .listVariant(let index):
            try container.encode("listVariant", forKey: .type)
            try container.encode(index, forKey: .index)
        case .comment(let index):
            try container.encode("comment", forKey: .type)
            try container.encode(index, forKey: .index)
        }
    }
}

extension WirePointerTarget: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .segment: "WirePointerTarget.segment"
        case .alternative: "WirePointerTarget.alternative"
        case .variant: "WirePointerTarget.variant"
        case .entry: "WirePointerTarget.entry"
        case .listVariant: "WirePointerTarget.listVariant"
        case .comment: "WirePointerTarget.comment"
        }
    }
    public var debugDescription: String { description }
}

public enum WireRuleList: String, Sendable, Equatable, Codable, CaseIterable {
    case correctionRules
    case exceptions
    case englishWords
    case japaneseWords
    case romaji
    case symbolSequences
    case symbolReadings
    case englishTerms
    case hiddenPredictions
}

extension WireRuleList: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireRuleList.\(rawValue)" }
    public var debugDescription: String { description }
}

public enum WireSyncProblem: String, Sendable, Equatable, Codable, CaseIterable {
    case failed
    case unreadable
    case folderUnavailable
}

extension WireSyncProblem: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSyncProblem.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireSyncGroupState: Sendable, Equatable, Codable {
    public var group: String
    public var scope: String
    public var fields: [String]

    public init(group: String, scope: String, fields: [String]) {
        self.group = group
        self.scope = scope
        self.fields = fields
    }
}

extension WireSyncGroupState: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSyncGroupState" }
    public var debugDescription: String { description }
}

public struct WireSyncStatus: Sendable, Equatable, Codable {
    public var isEnabled: Bool
    public var folderPath: String?
    public var folderName: String?
    public var groups: [WireSyncGroupState]
    public var localFields: [String]
    public var lastSyncedAt: String?
    public var isSyncing: Bool
    public var problem: WireSyncProblem?

    public init(isEnabled: Bool, folderPath: String? = nil, folderName: String? = nil, groups: [WireSyncGroupState], localFields: [String], lastSyncedAt: String? = nil, isSyncing: Bool, problem: WireSyncProblem? = nil) {
        self.isEnabled = isEnabled
        self.folderPath = folderPath
        self.folderName = folderName
        self.groups = groups
        self.localFields = localFields
        self.lastSyncedAt = lastSyncedAt
        self.isSyncing = isSyncing
        self.problem = problem
    }
}

extension WireSyncStatus: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSyncStatus" }
    public var debugDescription: String { description }
}

public enum WireImportKind: String, Sendable, Equatable, Codable, CaseIterable {
    case userDictionary
    case dictionary
    case association
}

extension WireImportKind: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireImportKind.\(rawValue)" }
    public var debugDescription: String { description }
}

public enum WireImportFormat: String, Sendable, Equatable, Codable, CaseIterable {
    case tabSeparated
    case commaSeparated
    case skk
    case propertyList
}

extension WireImportFormat: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireImportFormat.\(rawValue)" }
    public var debugDescription: String { description }
}

public enum WireImportColumn: String, Sendable, Equatable, Codable, CaseIterable {
    case reading
    case word
    case wordClass
    case comment
    case meaning
    case words
}

extension WireImportColumn: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireImportColumn.\(rawValue)" }
    public var debugDescription: String { description }
}

public enum WireImportRowStatus: String, Sendable, Equatable, Codable, CaseIterable {
    case ok
    case defaultedWordClass
    case unreadable
}

extension WireImportRowStatus: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireImportRowStatus.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireImportPreviewRow: Sendable, Equatable, Codable {
    public var line: UInt32
    public var cells: [String]
    public var status: WireImportRowStatus

    public init(line: UInt32, cells: [String], status: WireImportRowStatus) {
        self.line = line
        self.cells = cells
        self.status = status
    }
}

extension WireImportPreviewRow: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireImportPreviewRow" }
    public var debugDescription: String { description }
}

public struct WireImportPreview: Sendable, Equatable, Codable {
    public var format: WireImportFormat
    public var columns: [WireImportColumn]
    public var rows: [WireImportPreviewRow]
    public var importable: UInt32
    public var defaulted: UInt32
    public var unreadable: UInt32

    public init(format: WireImportFormat, columns: [WireImportColumn], rows: [WireImportPreviewRow], importable: UInt32, defaulted: UInt32, unreadable: UInt32) {
        self.format = format
        self.columns = columns
        self.rows = rows
        self.importable = importable
        self.defaulted = defaulted
        self.unreadable = unreadable
    }
}

extension WireImportPreview: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireImportPreview" }
    public var debugDescription: String { description }
}

public struct WireImportedDictionaryInfo: Sendable, Equatable, Codable {
    public var id: String
    public var name: String
    public var wordCount: UInt32

    public init(id: String, name: String, wordCount: UInt32) {
        self.id = id
        self.name = name
        self.wordCount = wordCount
    }
}

extension WireImportedDictionaryInfo: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireImportedDictionaryInfo" }
    public var debugDescription: String { description }
}

public struct WireAssociationDictionaryInfo: Sendable, Equatable, Codable {
    public var id: String
    public var name: String
    public var groupCount: UInt32

    public init(id: String, name: String, groupCount: UInt32) {
        self.id = id
        self.name = name
        self.groupCount = groupCount
    }
}

extension WireAssociationDictionaryInfo: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireAssociationDictionaryInfo" }
    public var debugDescription: String { description }
}

public enum WireFileFailure: String, Sendable, Equatable, Codable, CaseIterable {
    case invalidPath
    case notFound
    case tooLarge
    case unreadable
    case empty
    case notSettings
    case tooMany
    case unknownDictionary
    case writeFailed
    case busy
}

extension WireFileFailure: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireFileFailure.\(rawValue)" }
    public var debugDescription: String { description }
}

public enum WireSymbolKind: String, Sendable, Equatable, Codable, CaseIterable {
    case sequence
    case reading
}

extension WireSymbolKind: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSymbolKind.\(rawValue)" }
    public var debugDescription: String { description }
}

public enum WireSymbolOrigin: String, Sendable, Equatable, Codable, CaseIterable {
    case standard
    case changed
    case added
}

extension WireSymbolOrigin: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSymbolOrigin.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireSymbolItem: Sendable, Equatable, Codable {
    public var input: String
    public var output: String
    public var isEnabled: Bool
    public var origin: WireSymbolOrigin

    public init(input: String, output: String, isEnabled: Bool, origin: WireSymbolOrigin) {
        self.input = input
        self.output = output
        self.isEnabled = isEnabled
        self.origin = origin
    }
}

extension WireSymbolItem: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSymbolItem" }
    public var debugDescription: String { description }
}

public enum WireSymbolSaveResult: String, Sendable, Equatable, Codable, CaseIterable {
    case saved
    case invalid
    case full
}

extension WireSymbolSaveResult: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSymbolSaveResult.\(rawValue)" }
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

public enum WireContrastPair: String, Sendable, Equatable, Codable, CaseIterable {
    case text
    case textMuted
    case selectionText
    case correction
}

extension WireContrastPair: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireContrastPair.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireContrastIssue: Sendable, Equatable, Codable {
    public var pair: WireContrastPair
    public var ratio: Double
    public var minimum: Double

    public init(pair: WireContrastPair, ratio: Double, minimum: Double) {
        self.pair = pair
        self.ratio = ratio
        self.minimum = minimum
    }
}

extension WireContrastIssue: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireContrastIssue" }
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

public enum WireWordClass: String, Sendable, Equatable, Codable, CaseIterable {
    case noun
    case properNoun
    case personName
    case surname
    case givenName
    case organization
    case place
    case symbol
    case suruNoun
    case adjectivalNoun
    case adverb
    case interjection
    case abbreviation
}

extension WireWordClass: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireWordClass.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireDictionaryEntry: Sendable, Equatable, Codable {
    public var reading: String
    public var word: String
    public var wordClass: WireWordClass?
    public var comment: String?

    public init(reading: String, word: String, wordClass: WireWordClass? = nil, comment: String? = nil) {
        self.reading = reading
        self.word = word
        self.wordClass = wordClass
        self.comment = comment
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
    case activate(session: UInt32, context: WireFieldContext)
    case deactivate(session: UInt32)
    case wake(session: UInt32, context: WireFieldContext)
    case openHandwriting(session: UInt32, context: WireFieldContext)
    case openPalette(session: UInt32, context: WireFieldContext)
    case reconvert(session: UInt32, text: String, reading: String?, context: WireFieldContext)
    case caret(session: UInt32, rect: WireRect, composition: WireRect?)
    case readSettings
    case writeSettings(settings: WireSettingsSnapshot)
    case menu(command: WireMenuCommand)
    case readSync
    case setSyncFolder(path: String)
    case setSyncEnabled(enabled: Bool)
    case setSyncScope(group: String, scope: String)
    case setSyncLocalField(field: String, isLocal: Bool)
    case syncNow
    case importDictionary(path: String, replacing: String?)
    case removeDictionary(id: String)
    case importAssociationDictionary(path: String, replacing: String?)
    case removeAssociationDictionary(id: String)
    case exportSettings(path: String)
    case importSettings(path: String)
    case importProfileRules(path: String)
    case exportProfileRules(path: String)
    case importRuleList(list: WireRuleList, path: String)
    case exportRuleList(list: WireRuleList, path: String)
    case readSymbolItems(kind: WireSymbolKind)
    case saveSymbolRule(kind: WireSymbolKind, input: String, output: String, isEnabled: Bool, replacing: String?)
    case removeSymbolRules(kind: WireSymbolKind, inputs: [String])
    case previewImport(kind: WireImportKind, path: String)
    case importUserDictionary(path: String)
    case exportUserDictionary(path: String)
    case handwritingChosen(text: String)
    case handwritingClosed
    case chooseCandidate(target: WirePointerTarget)
    case choosePalette(target: WirePaletteTarget)
    case readSettingsFields(names: [String], defaults: Bool)
    case writeSettingsFields(values: String)
    case readKeymapPreset(preset: String)
    case checkKeymap(values: String)
    case checkCustomTheme(theme: String)
    case resetLearning
    case readUsage
    case resetUsage
    case resetPaletteHistory
    case previewLanguage(text: String, precedingText: String?)
    case previewMacros(text: String, reading: String, pattern: String?)
    case readUserDictionary(offset: UInt32, limit: UInt32)
    case addUserDictionaryEntry(entry: WireDictionaryEntry)
    case removeUserDictionaryEntry(entry: WireDictionaryEntry)
    case mergeUserDictionary(entries: [WireDictionaryEntry])
    case openWordRegistration(text: String, reading: String?)
    case takeWordRegistration

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, session, input, context, mode, text, reading, rect, composition, settings, command, path, enabled, group, scope, field, isLocal, replacing, id, list, kind, output, isEnabled, inputs, target, names, defaults, values, preset, theme, precedingText, pattern, offset, limit, entry, entries
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
        case "activate":
            self = try .activate(session: container.decode(UInt32.self, forKey: .session), context: container.decode(WireFieldContext.self, forKey: .context))
        case "deactivate":
            self = try .deactivate(session: container.decode(UInt32.self, forKey: .session))
        case "wake":
            self = try .wake(session: container.decode(UInt32.self, forKey: .session), context: container.decode(WireFieldContext.self, forKey: .context))
        case "openHandwriting":
            self = try .openHandwriting(session: container.decode(UInt32.self, forKey: .session), context: container.decode(WireFieldContext.self, forKey: .context))
        case "openPalette":
            self = try .openPalette(session: container.decode(UInt32.self, forKey: .session), context: container.decode(WireFieldContext.self, forKey: .context))
        case "reconvert":
            self = try .reconvert(session: container.decode(UInt32.self, forKey: .session), text: container.decode(String.self, forKey: .text), reading: container.decodeIfPresent(String.self, forKey: .reading), context: container.decode(WireFieldContext.self, forKey: .context))
        case "caret":
            self = try .caret(session: container.decode(UInt32.self, forKey: .session), rect: container.decode(WireRect.self, forKey: .rect), composition: container.decodeIfPresent(WireRect.self, forKey: .composition))
        case "readSettings":
            self = .readSettings
        case "writeSettings":
            self = try .writeSettings(settings: container.decode(WireSettingsSnapshot.self, forKey: .settings))
        case "menu":
            self = try .menu(command: container.decode(WireMenuCommand.self, forKey: .command))
        case "readSync":
            self = .readSync
        case "setSyncFolder":
            self = try .setSyncFolder(path: container.decode(String.self, forKey: .path))
        case "setSyncEnabled":
            self = try .setSyncEnabled(enabled: container.decode(Bool.self, forKey: .enabled))
        case "setSyncScope":
            self = try .setSyncScope(group: container.decode(String.self, forKey: .group), scope: container.decode(String.self, forKey: .scope))
        case "setSyncLocalField":
            self = try .setSyncLocalField(field: container.decode(String.self, forKey: .field), isLocal: container.decode(Bool.self, forKey: .isLocal))
        case "syncNow":
            self = .syncNow
        case "importDictionary":
            self = try .importDictionary(path: container.decode(String.self, forKey: .path), replacing: container.decodeIfPresent(String.self, forKey: .replacing))
        case "removeDictionary":
            self = try .removeDictionary(id: container.decode(String.self, forKey: .id))
        case "importAssociationDictionary":
            self = try .importAssociationDictionary(path: container.decode(String.self, forKey: .path), replacing: container.decodeIfPresent(String.self, forKey: .replacing))
        case "removeAssociationDictionary":
            self = try .removeAssociationDictionary(id: container.decode(String.self, forKey: .id))
        case "exportSettings":
            self = try .exportSettings(path: container.decode(String.self, forKey: .path))
        case "importSettings":
            self = try .importSettings(path: container.decode(String.self, forKey: .path))
        case "importProfileRules":
            self = try .importProfileRules(path: container.decode(String.self, forKey: .path))
        case "exportProfileRules":
            self = try .exportProfileRules(path: container.decode(String.self, forKey: .path))
        case "importRuleList":
            self = try .importRuleList(list: container.decode(WireRuleList.self, forKey: .list), path: container.decode(String.self, forKey: .path))
        case "exportRuleList":
            self = try .exportRuleList(list: container.decode(WireRuleList.self, forKey: .list), path: container.decode(String.self, forKey: .path))
        case "readSymbolItems":
            self = try .readSymbolItems(kind: container.decode(WireSymbolKind.self, forKey: .kind))
        case "saveSymbolRule":
            self = try .saveSymbolRule(kind: container.decode(WireSymbolKind.self, forKey: .kind), input: container.decode(String.self, forKey: .input), output: container.decode(String.self, forKey: .output), isEnabled: container.decode(Bool.self, forKey: .isEnabled), replacing: container.decodeIfPresent(String.self, forKey: .replacing))
        case "removeSymbolRules":
            self = try .removeSymbolRules(kind: container.decode(WireSymbolKind.self, forKey: .kind), inputs: container.decode([String].self, forKey: .inputs))
        case "previewImport":
            self = try .previewImport(kind: container.decode(WireImportKind.self, forKey: .kind), path: container.decode(String.self, forKey: .path))
        case "importUserDictionary":
            self = try .importUserDictionary(path: container.decode(String.self, forKey: .path))
        case "exportUserDictionary":
            self = try .exportUserDictionary(path: container.decode(String.self, forKey: .path))
        case "handwritingChosen":
            self = try .handwritingChosen(text: container.decode(String.self, forKey: .text))
        case "handwritingClosed":
            self = .handwritingClosed
        case "chooseCandidate":
            self = try .chooseCandidate(target: container.decode(WirePointerTarget.self, forKey: .target))
        case "choosePalette":
            self = try .choosePalette(target: container.decode(WirePaletteTarget.self, forKey: .target))
        case "readSettingsFields":
            self = try .readSettingsFields(names: container.decode([String].self, forKey: .names), defaults: container.decode(Bool.self, forKey: .defaults))
        case "writeSettingsFields":
            self = try .writeSettingsFields(values: container.decode(String.self, forKey: .values))
        case "readKeymapPreset":
            self = try .readKeymapPreset(preset: container.decode(String.self, forKey: .preset))
        case "checkKeymap":
            self = try .checkKeymap(values: container.decode(String.self, forKey: .values))
        case "checkCustomTheme":
            self = try .checkCustomTheme(theme: container.decode(String.self, forKey: .theme))
        case "resetLearning":
            self = .resetLearning
        case "readUsage":
            self = .readUsage
        case "resetUsage":
            self = .resetUsage
        case "resetPaletteHistory":
            self = .resetPaletteHistory
        case "previewLanguage":
            self = try .previewLanguage(text: container.decode(String.self, forKey: .text), precedingText: container.decodeIfPresent(String.self, forKey: .precedingText))
        case "previewMacros":
            self = try .previewMacros(text: container.decode(String.self, forKey: .text), reading: container.decode(String.self, forKey: .reading), pattern: container.decodeIfPresent(String.self, forKey: .pattern))
        case "readUserDictionary":
            self = try .readUserDictionary(offset: container.decode(UInt32.self, forKey: .offset), limit: container.decode(UInt32.self, forKey: .limit))
        case "addUserDictionaryEntry":
            self = try .addUserDictionaryEntry(entry: container.decode(WireDictionaryEntry.self, forKey: .entry))
        case "removeUserDictionaryEntry":
            self = try .removeUserDictionaryEntry(entry: container.decode(WireDictionaryEntry.self, forKey: .entry))
        case "mergeUserDictionary":
            self = try .mergeUserDictionary(entries: container.decode([WireDictionaryEntry].self, forKey: .entries))
        case "openWordRegistration":
            self = try .openWordRegistration(text: container.decode(String.self, forKey: .text), reading: container.decodeIfPresent(String.self, forKey: .reading))
        case "takeWordRegistration":
            self = .takeWordRegistration
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
        case .activate(let session, let context):
            try container.encode("activate", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(context, forKey: .context)
        case .deactivate(let session):
            try container.encode("deactivate", forKey: .type)
            try container.encode(session, forKey: .session)
        case .wake(let session, let context):
            try container.encode("wake", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(context, forKey: .context)
        case .openHandwriting(let session, let context):
            try container.encode("openHandwriting", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(context, forKey: .context)
        case .openPalette(let session, let context):
            try container.encode("openPalette", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(context, forKey: .context)
        case .reconvert(let session, let text, let reading, let context):
            try container.encode("reconvert", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(reading, forKey: .reading)
            try container.encode(context, forKey: .context)
        case .caret(let session, let rect, let composition):
            try container.encode("caret", forKey: .type)
            try container.encode(session, forKey: .session)
            try container.encode(rect, forKey: .rect)
            try container.encodeIfPresent(composition, forKey: .composition)
        case .readSettings:
            try container.encode("readSettings", forKey: .type)
        case .writeSettings(let settings):
            try container.encode("writeSettings", forKey: .type)
            try container.encode(settings, forKey: .settings)
        case .menu(let command):
            try container.encode("menu", forKey: .type)
            try container.encode(command, forKey: .command)
        case .readSync:
            try container.encode("readSync", forKey: .type)
        case .setSyncFolder(let path):
            try container.encode("setSyncFolder", forKey: .type)
            try container.encode(path, forKey: .path)
        case .setSyncEnabled(let enabled):
            try container.encode("setSyncEnabled", forKey: .type)
            try container.encode(enabled, forKey: .enabled)
        case .setSyncScope(let group, let scope):
            try container.encode("setSyncScope", forKey: .type)
            try container.encode(group, forKey: .group)
            try container.encode(scope, forKey: .scope)
        case .setSyncLocalField(let field, let isLocal):
            try container.encode("setSyncLocalField", forKey: .type)
            try container.encode(field, forKey: .field)
            try container.encode(isLocal, forKey: .isLocal)
        case .syncNow:
            try container.encode("syncNow", forKey: .type)
        case .importDictionary(let path, let replacing):
            try container.encode("importDictionary", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(replacing, forKey: .replacing)
        case .removeDictionary(let id):
            try container.encode("removeDictionary", forKey: .type)
            try container.encode(id, forKey: .id)
        case .importAssociationDictionary(let path, let replacing):
            try container.encode("importAssociationDictionary", forKey: .type)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(replacing, forKey: .replacing)
        case .removeAssociationDictionary(let id):
            try container.encode("removeAssociationDictionary", forKey: .type)
            try container.encode(id, forKey: .id)
        case .exportSettings(let path):
            try container.encode("exportSettings", forKey: .type)
            try container.encode(path, forKey: .path)
        case .importSettings(let path):
            try container.encode("importSettings", forKey: .type)
            try container.encode(path, forKey: .path)
        case .importProfileRules(let path):
            try container.encode("importProfileRules", forKey: .type)
            try container.encode(path, forKey: .path)
        case .exportProfileRules(let path):
            try container.encode("exportProfileRules", forKey: .type)
            try container.encode(path, forKey: .path)
        case .importRuleList(let list, let path):
            try container.encode("importRuleList", forKey: .type)
            try container.encode(list, forKey: .list)
            try container.encode(path, forKey: .path)
        case .exportRuleList(let list, let path):
            try container.encode("exportRuleList", forKey: .type)
            try container.encode(list, forKey: .list)
            try container.encode(path, forKey: .path)
        case .readSymbolItems(let kind):
            try container.encode("readSymbolItems", forKey: .type)
            try container.encode(kind, forKey: .kind)
        case .saveSymbolRule(let kind, let input, let output, let isEnabled, let replacing):
            try container.encode("saveSymbolRule", forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encode(input, forKey: .input)
            try container.encode(output, forKey: .output)
            try container.encode(isEnabled, forKey: .isEnabled)
            try container.encodeIfPresent(replacing, forKey: .replacing)
        case .removeSymbolRules(let kind, let inputs):
            try container.encode("removeSymbolRules", forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encode(inputs, forKey: .inputs)
        case .previewImport(let kind, let path):
            try container.encode("previewImport", forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encode(path, forKey: .path)
        case .importUserDictionary(let path):
            try container.encode("importUserDictionary", forKey: .type)
            try container.encode(path, forKey: .path)
        case .exportUserDictionary(let path):
            try container.encode("exportUserDictionary", forKey: .type)
            try container.encode(path, forKey: .path)
        case .handwritingChosen(let text):
            try container.encode("handwritingChosen", forKey: .type)
            try container.encode(text, forKey: .text)
        case .handwritingClosed:
            try container.encode("handwritingClosed", forKey: .type)
        case .chooseCandidate(let target):
            try container.encode("chooseCandidate", forKey: .type)
            try container.encode(target, forKey: .target)
        case .choosePalette(let target):
            try container.encode("choosePalette", forKey: .type)
            try container.encode(target, forKey: .target)
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
        case .checkCustomTheme(let theme):
            try container.encode("checkCustomTheme", forKey: .type)
            try container.encode(theme, forKey: .theme)
        case .resetLearning:
            try container.encode("resetLearning", forKey: .type)
        case .readUsage:
            try container.encode("readUsage", forKey: .type)
        case .resetUsage:
            try container.encode("resetUsage", forKey: .type)
        case .resetPaletteHistory:
            try container.encode("resetPaletteHistory", forKey: .type)
        case .previewLanguage(let text, let precedingText):
            try container.encode("previewLanguage", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(precedingText, forKey: .precedingText)
        case .previewMacros(let text, let reading, let pattern):
            try container.encode("previewMacros", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(reading, forKey: .reading)
            try container.encodeIfPresent(pattern, forKey: .pattern)
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
        case .openWordRegistration(let text, let reading):
            try container.encode("openWordRegistration", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(reading, forKey: .reading)
        case .takeWordRegistration:
            try container.encode("takeWordRegistration", forKey: .type)
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
        case .activate: "WireRequestBody.activate"
        case .deactivate: "WireRequestBody.deactivate"
        case .wake: "WireRequestBody.wake"
        case .openHandwriting: "WireRequestBody.openHandwriting"
        case .openPalette: "WireRequestBody.openPalette"
        case .reconvert: "WireRequestBody.reconvert"
        case .caret: "WireRequestBody.caret"
        case .readSettings: "WireRequestBody.readSettings"
        case .writeSettings: "WireRequestBody.writeSettings"
        case .menu: "WireRequestBody.menu"
        case .readSync: "WireRequestBody.readSync"
        case .setSyncFolder: "WireRequestBody.setSyncFolder"
        case .setSyncEnabled: "WireRequestBody.setSyncEnabled"
        case .setSyncScope: "WireRequestBody.setSyncScope"
        case .setSyncLocalField: "WireRequestBody.setSyncLocalField"
        case .syncNow: "WireRequestBody.syncNow"
        case .importDictionary: "WireRequestBody.importDictionary"
        case .removeDictionary: "WireRequestBody.removeDictionary"
        case .importAssociationDictionary: "WireRequestBody.importAssociationDictionary"
        case .removeAssociationDictionary: "WireRequestBody.removeAssociationDictionary"
        case .exportSettings: "WireRequestBody.exportSettings"
        case .importSettings: "WireRequestBody.importSettings"
        case .importProfileRules: "WireRequestBody.importProfileRules"
        case .exportProfileRules: "WireRequestBody.exportProfileRules"
        case .importRuleList: "WireRequestBody.importRuleList"
        case .exportRuleList: "WireRequestBody.exportRuleList"
        case .readSymbolItems: "WireRequestBody.readSymbolItems"
        case .saveSymbolRule: "WireRequestBody.saveSymbolRule"
        case .removeSymbolRules: "WireRequestBody.removeSymbolRules"
        case .previewImport: "WireRequestBody.previewImport"
        case .importUserDictionary: "WireRequestBody.importUserDictionary"
        case .exportUserDictionary: "WireRequestBody.exportUserDictionary"
        case .handwritingChosen: "WireRequestBody.handwritingChosen"
        case .handwritingClosed: "WireRequestBody.handwritingClosed"
        case .chooseCandidate: "WireRequestBody.chooseCandidate"
        case .choosePalette: "WireRequestBody.choosePalette"
        case .readSettingsFields: "WireRequestBody.readSettingsFields"
        case .writeSettingsFields: "WireRequestBody.writeSettingsFields"
        case .readKeymapPreset: "WireRequestBody.readKeymapPreset"
        case .checkKeymap: "WireRequestBody.checkKeymap"
        case .checkCustomTheme: "WireRequestBody.checkCustomTheme"
        case .resetLearning: "WireRequestBody.resetLearning"
        case .readUsage: "WireRequestBody.readUsage"
        case .resetUsage: "WireRequestBody.resetUsage"
        case .resetPaletteHistory: "WireRequestBody.resetPaletteHistory"
        case .previewLanguage: "WireRequestBody.previewLanguage"
        case .previewMacros: "WireRequestBody.previewMacros"
        case .readUserDictionary: "WireRequestBody.readUserDictionary"
        case .addUserDictionaryEntry: "WireRequestBody.addUserDictionaryEntry"
        case .removeUserDictionaryEntry: "WireRequestBody.removeUserDictionaryEntry"
        case .mergeUserDictionary: "WireRequestBody.mergeUserDictionary"
        case .openWordRegistration: "WireRequestBody.openWordRegistration"
        case .takeWordRegistration: "WireRequestBody.takeWordRegistration"
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
    case syncStatus(status: WireSyncStatus)
    case dictionaryImported(dictionary: WireImportedDictionaryInfo)
    case associationImported(dictionary: WireAssociationDictionaryInfo)
    case importPreview(preview: WireImportPreview)
    case imported(added: UInt32, skipped: UInt32)
    case fileFailed(reason: WireFileFailure)
    case symbolItems(items: [WireSymbolItem])
    case symbolSaved(result: WireSymbolSaveResult)
    case settingsFields(values: String)
    case keymapReport(report: WireKeymapReport)
    case themeReport(issues: [WireContrastIssue])
    case usage(values: String, firstCandidateRate: Double?)
    case languagePreview(words: [WirePreviewWord])
    case macroPreview(results: [String])
    case userDictionary(entries: [WireDictionaryEntry], total: UInt32)
    case dictionaryAdded(result: WireDictionaryAddResult)
    case dictionaryMerged(added: UInt32)
    case error(code: WireErrorCode)
    case wordRegistration(word: String?, reading: String?)

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, session, state, handled, operations, settings, status, dictionary, preview, added, skipped, reason, items, result, values, report, issues, firstCandidateRate, words, results, entries, total, code, word, reading
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
        case "syncStatus":
            self = try .syncStatus(status: container.decode(WireSyncStatus.self, forKey: .status))
        case "dictionaryImported":
            self = try .dictionaryImported(dictionary: container.decode(WireImportedDictionaryInfo.self, forKey: .dictionary))
        case "associationImported":
            self = try .associationImported(dictionary: container.decode(WireAssociationDictionaryInfo.self, forKey: .dictionary))
        case "importPreview":
            self = try .importPreview(preview: container.decode(WireImportPreview.self, forKey: .preview))
        case "imported":
            self = try .imported(added: container.decode(UInt32.self, forKey: .added), skipped: container.decode(UInt32.self, forKey: .skipped))
        case "fileFailed":
            self = try .fileFailed(reason: container.decode(WireFileFailure.self, forKey: .reason))
        case "symbolItems":
            self = try .symbolItems(items: container.decode([WireSymbolItem].self, forKey: .items))
        case "symbolSaved":
            self = try .symbolSaved(result: container.decode(WireSymbolSaveResult.self, forKey: .result))
        case "settingsFields":
            self = try .settingsFields(values: container.decode(String.self, forKey: .values))
        case "keymapReport":
            self = try .keymapReport(report: container.decode(WireKeymapReport.self, forKey: .report))
        case "themeReport":
            self = try .themeReport(issues: container.decode([WireContrastIssue].self, forKey: .issues))
        case "usage":
            self = try .usage(values: container.decode(String.self, forKey: .values), firstCandidateRate: container.decodeIfPresent(Double.self, forKey: .firstCandidateRate))
        case "languagePreview":
            self = try .languagePreview(words: container.decode([WirePreviewWord].self, forKey: .words))
        case "macroPreview":
            self = try .macroPreview(results: container.decode([String].self, forKey: .results))
        case "userDictionary":
            self = try .userDictionary(entries: container.decode([WireDictionaryEntry].self, forKey: .entries), total: container.decode(UInt32.self, forKey: .total))
        case "dictionaryAdded":
            self = try .dictionaryAdded(result: container.decode(WireDictionaryAddResult.self, forKey: .result))
        case "dictionaryMerged":
            self = try .dictionaryMerged(added: container.decode(UInt32.self, forKey: .added))
        case "error":
            self = try .error(code: container.decode(WireErrorCode.self, forKey: .code))
        case "wordRegistration":
            self = try .wordRegistration(word: container.decodeIfPresent(String.self, forKey: .word), reading: container.decodeIfPresent(String.self, forKey: .reading))
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
        case .syncStatus(let status):
            try container.encode("syncStatus", forKey: .type)
            try container.encode(status, forKey: .status)
        case .dictionaryImported(let dictionary):
            try container.encode("dictionaryImported", forKey: .type)
            try container.encode(dictionary, forKey: .dictionary)
        case .associationImported(let dictionary):
            try container.encode("associationImported", forKey: .type)
            try container.encode(dictionary, forKey: .dictionary)
        case .importPreview(let preview):
            try container.encode("importPreview", forKey: .type)
            try container.encode(preview, forKey: .preview)
        case .imported(let added, let skipped):
            try container.encode("imported", forKey: .type)
            try container.encode(added, forKey: .added)
            try container.encode(skipped, forKey: .skipped)
        case .fileFailed(let reason):
            try container.encode("fileFailed", forKey: .type)
            try container.encode(reason, forKey: .reason)
        case .symbolItems(let items):
            try container.encode("symbolItems", forKey: .type)
            try container.encode(items, forKey: .items)
        case .symbolSaved(let result):
            try container.encode("symbolSaved", forKey: .type)
            try container.encode(result, forKey: .result)
        case .settingsFields(let values):
            try container.encode("settingsFields", forKey: .type)
            try container.encode(values, forKey: .values)
        case .keymapReport(let report):
            try container.encode("keymapReport", forKey: .type)
            try container.encode(report, forKey: .report)
        case .themeReport(let issues):
            try container.encode("themeReport", forKey: .type)
            try container.encode(issues, forKey: .issues)
        case .usage(let values, let firstCandidateRate):
            try container.encode("usage", forKey: .type)
            try container.encode(values, forKey: .values)
            try container.encodeIfPresent(firstCandidateRate, forKey: .firstCandidateRate)
        case .languagePreview(let words):
            try container.encode("languagePreview", forKey: .type)
            try container.encode(words, forKey: .words)
        case .macroPreview(let results):
            try container.encode("macroPreview", forKey: .type)
            try container.encode(results, forKey: .results)
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
        case .wordRegistration(let word, let reading):
            try container.encode("wordRegistration", forKey: .type)
            try container.encodeIfPresent(word, forKey: .word)
            try container.encodeIfPresent(reading, forKey: .reading)
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
        case .syncStatus: "WireResponseBody.syncStatus"
        case .dictionaryImported: "WireResponseBody.dictionaryImported"
        case .associationImported: "WireResponseBody.associationImported"
        case .importPreview: "WireResponseBody.importPreview"
        case .imported: "WireResponseBody.imported"
        case .fileFailed: "WireResponseBody.fileFailed"
        case .symbolItems: "WireResponseBody.symbolItems"
        case .symbolSaved: "WireResponseBody.symbolSaved"
        case .settingsFields: "WireResponseBody.settingsFields"
        case .keymapReport: "WireResponseBody.keymapReport"
        case .themeReport: "WireResponseBody.themeReport"
        case .usage: "WireResponseBody.usage"
        case .languagePreview: "WireResponseBody.languagePreview"
        case .macroPreview: "WireResponseBody.macroPreview"
        case .userDictionary: "WireResponseBody.userDictionary"
        case .dictionaryAdded: "WireResponseBody.dictionaryAdded"
        case .dictionaryMerged: "WireResponseBody.dictionaryMerged"
        case .error: "WireResponseBody.error"
        case .wordRegistration: "WireResponseBody.wordRegistration"
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

public enum WireCommandKind: String, Sendable, Equatable, Codable, CaseIterable {
    case openApplication
    case openURL
    case openFile
    case runShortcut
}

extension WireCommandKind: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireCommandKind.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireCandidateEntry: Sendable, Equatable, Codable {
    public var text: String
    public var annotation: String?
    public var correctedStart: UInt32?
    public var correctedLength: UInt32?
    public var command: WireCommandKind?
    public var hasComment: Bool?
    public var detail: String?

    public init(text: String, annotation: String? = nil, correctedStart: UInt32? = nil, correctedLength: UInt32? = nil, command: WireCommandKind? = nil, hasComment: Bool? = nil, detail: String? = nil) {
        self.text = text
        self.annotation = annotation
        self.correctedStart = correctedStart
        self.correctedLength = correctedLength
        self.command = command
        self.hasComment = hasComment
        self.detail = detail
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

public enum WireNoteTone: String, Sendable, Equatable, Codable, CaseIterable {
    case correction
    case suggestion
    case info
}

extension WireNoteTone: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireNoteTone.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireNote: Sendable, Equatable, Codable {
    public var tone: WireNoteTone
    public var title: String
    public var subject: String?
    public var key: String?
    public var keyAction: String?
    public var text: String

    public init(tone: WireNoteTone, title: String, subject: String? = nil, key: String? = nil, keyAction: String? = nil, text: String) {
        self.tone = tone
        self.title = title
        self.subject = subject
        self.key = key
        self.keyAction = keyAction
        self.text = text
    }
}

extension WireNote: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireNote" }
    public var debugDescription: String { description }
}

public struct WirePrediction: Sendable, Equatable, Codable {
    public var typed: String
    public var completion: String
    public var key: String?

    public init(typed: String, completion: String, key: String? = nil) {
        self.typed = typed
        self.completion = completion
        self.key = key
    }
}

extension WirePrediction: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePrediction" }
    public var debugDescription: String { description }
}

public struct WireAssociationHeading: Sendable, Equatable, Codable {
    public var headword: String
    public var label: String
    public var group: UInt32
    public var groupCount: UInt32

    public init(headword: String, label: String, group: UInt32, groupCount: UInt32) {
        self.headword = headword
        self.label = label
        self.group = group
        self.groupCount = groupCount
    }
}

extension WireAssociationHeading: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireAssociationHeading" }
    public var debugDescription: String { description }
}

public enum WirePartOfSpeech: String, Sendable, Equatable, Codable, CaseIterable {
    case noun
    case verb
    case adjective
    case adjectivalNoun
    case adverb
    case prenominal
    case conjunction
    case interjection
    case pronoun
    case prefix
    case suffix
}

extension WirePartOfSpeech: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePartOfSpeech.\(rawValue)" }
    public var debugDescription: String { description }
}

public enum WireMeaningPlacement: String, Sendable, Equatable, Codable, CaseIterable {
    case side
    case below
}

extension WireMeaningPlacement: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireMeaningPlacement.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WireHomophoneSense: Sendable, Equatable, Codable {
    public var meaning: String
    public var example: String?

    public init(meaning: String, example: String? = nil) {
        self.meaning = meaning
        self.example = example
    }
}

extension WireHomophoneSense: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireHomophoneSense" }
    public var debugDescription: String { description }
}

public struct WireHomophoneNote: Sendable, Equatable, Codable {
    public var word: String
    public var partOfSpeech: WirePartOfSpeech?
    public var senses: [WireHomophoneSense]
    public var others: [String]

    public init(word: String, partOfSpeech: WirePartOfSpeech? = nil, senses: [WireHomophoneSense], others: [String]) {
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.senses = senses
        self.others = others
    }
}

extension WireHomophoneNote: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireHomophoneNote" }
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
    public var note: WireNote?
    public var hints: [WireKeyHint]?
    public var association: WireAssociationHeading?
    public var associationHint: String?
    public var associationKey: String?
    public var homophone: WireHomophoneNote?
    public var showsNumbers: Bool?
    public var meaningPlacement: WireMeaningPlacement?
    public var columnLength: UInt32?

    public init(variants: [WireCandidateVariant], selectedVariant: UInt32? = nil, entries: [WireCandidateEntry], selectedEntry: UInt32? = nil, focus: WireCandidateFocus, position: UInt32, total: UInt32, note: WireNote? = nil, hints: [WireKeyHint]? = nil, association: WireAssociationHeading? = nil, associationHint: String? = nil, associationKey: String? = nil, homophone: WireHomophoneNote? = nil, showsNumbers: Bool? = nil, meaningPlacement: WireMeaningPlacement? = nil, columnLength: UInt32? = nil) {
        self.variants = variants
        self.selectedVariant = selectedVariant
        self.entries = entries
        self.selectedEntry = selectedEntry
        self.focus = focus
        self.position = position
        self.total = total
        self.note = note
        self.hints = hints
        self.association = association
        self.associationHint = associationHint
        self.associationKey = associationKey
        self.homophone = homophone
        self.showsNumbers = showsNumbers
        self.meaningPlacement = meaningPlacement
        self.columnLength = columnLength
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
    public var homophone: WireHomophoneNote?
    public var alternativeNotes: [String?]
    public var alternativeCommands: [WireCommandKind?]?
    public var alternativeComments: [Bool]?
    public var alternativeDetails: [String?]?
    public var sourceName: String?
    public var split: WireBranchSplit?

    public init(text: String, alternatives: [String], selectedAlternative: UInt32? = nil, variants: [String], selectedVariant: UInt32? = nil, isFocused: Bool, isUncertain: Bool, isDecided: Bool, isCorrected: Bool? = nil, preview: String? = nil, shorter: String? = nil, longer: String? = nil, usageNote: String? = nil, homophone: WireHomophoneNote? = nil, alternativeNotes: [String?], alternativeCommands: [WireCommandKind?]? = nil, alternativeComments: [Bool]? = nil, alternativeDetails: [String?]? = nil, sourceName: String? = nil, split: WireBranchSplit? = nil) {
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
        self.homophone = homophone
        self.alternativeNotes = alternativeNotes
        self.alternativeCommands = alternativeCommands
        self.alternativeComments = alternativeComments
        self.alternativeDetails = alternativeDetails
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
    public var note: WireNote?
    public var hints: [WireKeyHint]
    public var association: WireAssociationHeading?
    public var associationHint: String?
    public var associationKey: String?
    public var meaningPlacement: WireMeaningPlacement?

    public init(columns: [WireBranchColumn], position: UInt32, total: UInt32, note: WireNote? = nil, hints: [WireKeyHint], association: WireAssociationHeading? = nil, associationHint: String? = nil, associationKey: String? = nil, meaningPlacement: WireMeaningPlacement? = nil) {
        self.columns = columns
        self.position = position
        self.total = total
        self.note = note
        self.hints = hints
        self.association = association
        self.associationHint = associationHint
        self.associationKey = associationKey
        self.meaningPlacement = meaningPlacement
    }
}

extension WireBranchMap: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireBranchMap" }
    public var debugDescription: String { description }
}

public enum WirePaletteKind: String, Sendable, Equatable, Codable, CaseIterable {
    case emoji
    case symbol
    case kaomoji
}

extension WirePaletteKind: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePaletteKind.\(rawValue)" }
    public var debugDescription: String { description }
}

public enum WireSkinTone: String, Sendable, Equatable, Codable, CaseIterable {
    case none
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark
}

extension WireSkinTone: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WireSkinTone.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WirePaletteMode: Sendable, Equatable, Codable {
    public var kind: WirePaletteKind
    public var title: String
    public var isSelected: Bool

    public init(kind: WirePaletteKind, title: String, isSelected: Bool) {
        self.kind = kind
        self.title = title
        self.isSelected = isSelected
    }
}

extension WirePaletteMode: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePaletteMode" }
    public var debugDescription: String { description }
}

public struct WirePaletteTab: Sendable, Equatable, Codable {
    public var section: String
    public var title: String
    public var symbol: String
    public var isSelected: Bool

    public init(section: String, title: String, symbol: String, isSelected: Bool) {
        self.section = section
        self.title = title
        self.symbol = symbol
        self.isSelected = isSelected
    }
}

extension WirePaletteTab: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePaletteTab" }
    public var debugDescription: String { description }
}

public struct WirePaletteCell: Sendable, Equatable, Codable {
    public var text: String
    public var name: String
    public var isPinned: Bool

    public init(text: String, name: String, isPinned: Bool) {
        self.text = text
        self.name = name
        self.isPinned = isPinned
    }
}

extension WirePaletteCell: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePaletteCell" }
    public var debugDescription: String { description }
}

public struct WirePaletteRow: Sendable, Equatable, Codable {
    public var index: UInt32
    public var cells: [WirePaletteCell]
    public var startsSection: Bool
    public var sectionTitle: String

    public init(index: UInt32, cells: [WirePaletteCell], startsSection: Bool, sectionTitle: String) {
        self.index = index
        self.cells = cells
        self.startsSection = startsSection
        self.sectionTitle = sectionTitle
    }
}

extension WirePaletteRow: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePaletteRow" }
    public var debugDescription: String { description }
}

public struct WirePalettePosition: Sendable, Equatable, Codable {
    public var row: UInt32
    public var column: UInt32

    public init(row: UInt32, column: UInt32) {
        self.row = row
        self.column = column
    }
}

extension WirePalettePosition: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePalettePosition" }
    public var debugDescription: String { description }
}

public struct WirePalettePreview: Sendable, Equatable, Codable {
    public var text: String
    public var japaneseName: String
    public var englishName: String
    public var shortcodes: [String]
    public var readings: [String]
    public var codePoints: String
    public var isPinned: Bool
    public var nameSource: String?
    public var englishNameSource: String?

    public init(text: String, japaneseName: String, englishName: String, shortcodes: [String], readings: [String], codePoints: String, isPinned: Bool, nameSource: String? = nil, englishNameSource: String? = nil) {
        self.text = text
        self.japaneseName = japaneseName
        self.englishName = englishName
        self.shortcodes = shortcodes
        self.readings = readings
        self.codePoints = codePoints
        self.isPinned = isPinned
        self.nameSource = nameSource
        self.englishNameSource = englishNameSource
    }
}

extension WirePalettePreview: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePalettePreview" }
    public var debugDescription: String { description }
}

public struct WirePalettePreviewFields: Sendable, Equatable, Codable {
    public var unicodeName: Bool
    public var readings: Bool
    public var shortcodes: Bool
    public var codePoints: Bool

    public init(unicodeName: Bool, readings: Bool, shortcodes: Bool, codePoints: Bool) {
        self.unicodeName = unicodeName
        self.readings = readings
        self.shortcodes = shortcodes
        self.codePoints = codePoints
    }
}

extension WirePalettePreviewFields: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePalettePreviewFields" }
    public var debugDescription: String { description }
}

public struct WirePaletteSkinTonePicker: Sendable, Equatable, Codable {
    public var options: [String]
    public var selected: UInt32

    public init(options: [String], selected: UInt32) {
        self.options = options
        self.selected = selected
    }
}

extension WirePaletteSkinTonePicker: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePaletteSkinTonePicker" }
    public var debugDescription: String { description }
}

public enum WirePaletteContentMotion: String, Sendable, Equatable, Codable, CaseIterable {
    case next
    case previous
    case down
    case up
}

extension WirePaletteContentMotion: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePaletteContentMotion.\(rawValue)" }
    public var debugDescription: String { description }
}

public struct WirePaletteMotion: Sendable, Equatable, Codable {
    public var selectionFrom: WirePalettePosition?
    public var modeFrom: WirePaletteKind?
    public var tabFrom: String?
    public var content: WirePaletteContentMotion?
    public var opensPicker: Bool
    public var togglesPin: Bool

    public init(selectionFrom: WirePalettePosition? = nil, modeFrom: WirePaletteKind? = nil, tabFrom: String? = nil, content: WirePaletteContentMotion? = nil, opensPicker: Bool, togglesPin: Bool) {
        self.selectionFrom = selectionFrom
        self.modeFrom = modeFrom
        self.tabFrom = tabFrom
        self.content = content
        self.opensPicker = opensPicker
        self.togglesPin = togglesPin
    }
}

extension WirePaletteMotion: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePaletteMotion" }
    public var debugDescription: String { description }
}

public struct WirePalettePanel: Sendable, Equatable, Codable {
    public var modes: [WirePaletteMode]
    public var query: String
    public var placeholder: String
    public var tabs: [WirePaletteTab]
    public var heading: String
    public var rows: [WirePaletteRow]
    public var rowCount: UInt32
    public var firstRow: UInt32
    public var columns: UInt32
    public var visibleRows: UInt32
    public var selection: WirePalettePosition?
    public var preview: WirePalettePreview?
    public var showsPreview: Bool
    public var skinTone: WireSkinTone
    public var skinTonePicker: WirePaletteSkinTonePicker?
    public var message: String?
    public var hints: [WireKeyHint]
    public var cellSize: Double
    public var cellsPerRow: UInt32?
    public var motion: WirePaletteMotion?
    public var previewFields: WirePalettePreviewFields?

    public init(modes: [WirePaletteMode], query: String, placeholder: String, tabs: [WirePaletteTab], heading: String, rows: [WirePaletteRow], rowCount: UInt32, firstRow: UInt32, columns: UInt32, visibleRows: UInt32, selection: WirePalettePosition? = nil, preview: WirePalettePreview? = nil, showsPreview: Bool, skinTone: WireSkinTone, skinTonePicker: WirePaletteSkinTonePicker? = nil, message: String? = nil, hints: [WireKeyHint], cellSize: Double, cellsPerRow: UInt32? = nil, motion: WirePaletteMotion? = nil, previewFields: WirePalettePreviewFields? = nil) {
        self.modes = modes
        self.query = query
        self.placeholder = placeholder
        self.tabs = tabs
        self.heading = heading
        self.rows = rows
        self.rowCount = rowCount
        self.firstRow = firstRow
        self.columns = columns
        self.visibleRows = visibleRows
        self.selection = selection
        self.preview = preview
        self.showsPreview = showsPreview
        self.skinTone = skinTone
        self.skinTonePicker = skinTonePicker
        self.message = message
        self.hints = hints
        self.cellSize = cellSize
        self.cellsPerRow = cellsPerRow
        self.motion = motion
        self.previewFields = previewFields
    }
}

extension WirePalettePanel: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "WirePalettePanel" }
    public var debugDescription: String { description }
}

public enum WirePaletteTarget: Sendable, Equatable, Codable {
    case cell(row: UInt32, column: UInt32)
    case hover(row: UInt32, column: UInt32)
    case tab(section: String)
    case mode(kind: WirePaletteKind)
    case scroll(rows: Int32)
    case skinTone(tone: WireSkinTone)
    case skinToneButton
    case pin
    case close

    private enum CodingKeys: String, CodingKey {
        case type, row, column, section, kind, rows, tone
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .type)
        switch kind {
        case "cell":
            self = try .cell(row: container.decode(UInt32.self, forKey: .row), column: container.decode(UInt32.self, forKey: .column))
        case "hover":
            self = try .hover(row: container.decode(UInt32.self, forKey: .row), column: container.decode(UInt32.self, forKey: .column))
        case "tab":
            self = try .tab(section: container.decode(String.self, forKey: .section))
        case "mode":
            self = try .mode(kind: container.decode(WirePaletteKind.self, forKey: .kind))
        case "scroll":
            self = try .scroll(rows: container.decode(Int32.self, forKey: .rows))
        case "skinTone":
            self = try .skinTone(tone: container.decode(WireSkinTone.self, forKey: .tone))
        case "skinToneButton":
            self = .skinToneButton
        case "pin":
            self = .pin
        case "close":
            self = .close
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "知らない種類")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .cell(let row, let column):
            try container.encode("cell", forKey: .type)
            try container.encode(row, forKey: .row)
            try container.encode(column, forKey: .column)
        case .hover(let row, let column):
            try container.encode("hover", forKey: .type)
            try container.encode(row, forKey: .row)
            try container.encode(column, forKey: .column)
        case .tab(let section):
            try container.encode("tab", forKey: .type)
            try container.encode(section, forKey: .section)
        case .mode(let kind):
            try container.encode("mode", forKey: .type)
            try container.encode(kind, forKey: .kind)
        case .scroll(let rows):
            try container.encode("scroll", forKey: .type)
            try container.encode(rows, forKey: .rows)
        case .skinTone(let tone):
            try container.encode("skinTone", forKey: .type)
            try container.encode(tone, forKey: .tone)
        case .skinToneButton:
            try container.encode("skinToneButton", forKey: .type)
        case .pin:
            try container.encode("pin", forKey: .type)
        case .close:
            try container.encode("close", forKey: .type)
        }
    }
}

extension WirePaletteTarget: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .cell: "WirePaletteTarget.cell"
        case .hover: "WirePaletteTarget.hover"
        case .tab: "WirePaletteTarget.tab"
        case .mode: "WirePaletteTarget.mode"
        case .scroll: "WirePaletteTarget.scroll"
        case .skinTone: "WirePaletteTarget.skinTone"
        case .skinToneButton: "WirePaletteTarget.skinToneButton"
        case .pin: "WirePaletteTarget.pin"
        case .close: "WirePaletteTarget.close"
        }
    }
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
    case showNote(note: WireNote, anchor: WireRect?)
    case showPrediction(prediction: WirePrediction?, anchor: WireRect?)
    case showMode(mode: WireInputMode, anchor: WireRect?, label: String?)
    case showHandwriting(anchor: WireRect?, recognitionDelayMilliseconds: UInt32, recognitionTimeoutMilliseconds: UInt32)
    case hideHandwriting
    case showPalette(panel: WirePalettePanel, anchor: WireRect?)
    case hidePalette
    case move(anchor: WireRect, composition: WireRect?)
    case hide

    private enum CodingKeys: String, CodingKey {
        case type, protocolVersion, presentation, list, anchor, map, note, prediction, mode, label, recognitionDelayMilliseconds, recognitionTimeoutMilliseconds, panel, composition
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
            self = try .showNote(note: container.decode(WireNote.self, forKey: .note), anchor: container.decodeIfPresent(WireRect.self, forKey: .anchor))
        case "showPrediction":
            self = try .showPrediction(prediction: container.decodeIfPresent(WirePrediction.self, forKey: .prediction), anchor: container.decodeIfPresent(WireRect.self, forKey: .anchor))
        case "showMode":
            self = try .showMode(mode: container.decode(WireInputMode.self, forKey: .mode), anchor: container.decodeIfPresent(WireRect.self, forKey: .anchor), label: container.decodeIfPresent(String.self, forKey: .label))
        case "showHandwriting":
            self = try .showHandwriting(anchor: container.decodeIfPresent(WireRect.self, forKey: .anchor), recognitionDelayMilliseconds: container.decode(UInt32.self, forKey: .recognitionDelayMilliseconds), recognitionTimeoutMilliseconds: container.decode(UInt32.self, forKey: .recognitionTimeoutMilliseconds))
        case "hideHandwriting":
            self = .hideHandwriting
        case "showPalette":
            self = try .showPalette(panel: container.decode(WirePalettePanel.self, forKey: .panel), anchor: container.decodeIfPresent(WireRect.self, forKey: .anchor))
        case "hidePalette":
            self = .hidePalette
        case "move":
            self = try .move(anchor: container.decode(WireRect.self, forKey: .anchor), composition: container.decodeIfPresent(WireRect.self, forKey: .composition))
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
        case .showNote(let note, let anchor):
            try container.encode("showNote", forKey: .type)
            try container.encode(note, forKey: .note)
            try container.encodeIfPresent(anchor, forKey: .anchor)
        case .showPrediction(let prediction, let anchor):
            try container.encode("showPrediction", forKey: .type)
            try container.encodeIfPresent(prediction, forKey: .prediction)
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
        case .showPalette(let panel, let anchor):
            try container.encode("showPalette", forKey: .type)
            try container.encode(panel, forKey: .panel)
            try container.encodeIfPresent(anchor, forKey: .anchor)
        case .hidePalette:
            try container.encode("hidePalette", forKey: .type)
        case .move(let anchor, let composition):
            try container.encode("move", forKey: .type)
            try container.encode(anchor, forKey: .anchor)
            try container.encodeIfPresent(composition, forKey: .composition)
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
        case .showPrediction: "WireUiCommand.showPrediction"
        case .showMode: "WireUiCommand.showMode"
        case .showHandwriting: "WireUiCommand.showHandwriting"
        case .hideHandwriting: "WireUiCommand.hideHandwriting"
        case .showPalette: "WireUiCommand.showPalette"
        case .hidePalette: "WireUiCommand.hidePalette"
        case .move: "WireUiCommand.move"
        case .hide: "WireUiCommand.hide"
        }
    }
    public var debugDescription: String { description }
}
