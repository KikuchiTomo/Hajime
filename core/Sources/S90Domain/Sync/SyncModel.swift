import Foundation

/// 同期するときの設定のまとまり(R-15)．まとまりごとに「同期する」「この Mac だけ」を選べる
public enum SyncGroup: String, Sendable, Equatable, Codable, CaseIterable, CodingKeyRepresentable {
    case input
    case keyboard
    case keys
    case conversion
    case correction
    case symbols
    case dictionary
    case appearance
    case exclusions
    case usage

    /// このまとまりに入る設定のファイルの項目の名前(Settings の CodingKeys)
    public var fieldNames: [String] {
        switch self {
        case .input:
            ["inputStyle", "customRomaji", "liveConversion", "yenKey", "punctuation", "brackets", "slash", "spaceWidth", "numberWidth",
             "alphabetWidth", "shiftStartsAlphabet", "punctuationCommits", "keypadDirect"]
        case .keyboard: ["keyboardLayout", "modeKeys"]
        case .keys: ["conversionKeys"]
        case .conversion:
            ["typoCorrection", "candidatePresentation", "initialFocus", "listCandidatesPerPage", "branchCandidatesPerPage",
             "liveConversionDelay", "correctionDelay", "correctionSensitivity", "showsSuggestions", "okuriganaStyle", "calculation",
             "misreadings", "showsVariantRow", "numberKeySelection", "dateConversion", "symbolConversion", "emojiConversion", "learning"]
        case .correction: ["correction"]
        case .symbols: ["symbolRules"]
        case .dictionary: ["userDictionary"]
        case .appearance: ["theme", "candidateFontSize", "showsModeIndicator", "modeIndicatorDuration", "customThemes", "customThemeID"]
        case .exclusions: ["escapeSwitchesToDirect", "terminalCommands", "profileRules"]
        case .usage: ["recordsUsage"]
        }
    }

    /// 既定の範囲．キーボードや画面の大きさ，使うアプリは Mac ごとに違ってよいので，この Mac だけにする
    public var defaultScope: SyncScope {
        switch self {
        case .keyboard, .appearance, .exclusions, .usage: .local
        case .input, .keys, .conversion, .correction, .symbols, .dictionary: .synced
        }
    }
}

/// まとまりを同期するか
public enum SyncScope: String, Sendable, Equatable, Codable, CaseIterable {
    case synced
    /// この Mac だけで持つ
    case local
}

/// この Mac の同期の記録．同期のファイルとは別に，この Mac にだけ置く
public struct SyncLedger: Sendable, Equatable, Codable {
    /// まとまりを最後にこの Mac で変えた時刻
    public var groupModifiedAt: [SyncGroup: Date] = [:]
    /// ユーザー辞書の語を登録した時刻(「読み<タブ>語」で引く)
    public var dictionaryAddedAt: [String: Date] = [:]
    /// 消した語と時刻(墓標)．ほかの Mac にも消したことを伝える
    public var dictionaryTombstones: [String: Date] = [:]
    public var lastSyncedAt: Date?

    public init() {}
}

/// 同期のファイルの中身．どの Mac も同じ形で読み書きする
public struct SyncDocument: Sendable, Equatable, Codable {
    public struct GroupPayload: Sendable, Equatable, Codable {
        public var modifiedAt: Date
        public var values: [String: JSONValue]
    }

    public struct DictionaryEntry: Sendable, Equatable, Codable {
        public var reading: String
        public var word: String
        public var addedAt: Date
    }

    public static let currentVersion = 1
    public var version = SyncDocument.currentVersion
    public var groups: [SyncGroup: GroupPayload] = [:]
    public var dictionary: [DictionaryEntry] = []
    public var dictionaryModifiedAt: Date = .distantPast
    public var tombstones: [String: Date] = [:]

    public init() {}
}

extension SyncDocument: CustomStringConvertible, CustomDebugStringConvertible {
    // ユーザー辞書の語を含むので，ログには数だけを出す
    public var description: String { "SyncDocument(groups: \(groups.count), dictionary: \(dictionary.count) 語)" }
    public var debugDescription: String { description }
}
