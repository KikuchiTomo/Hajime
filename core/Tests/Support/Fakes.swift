import S90Application
import S90Domain

/// 読みごとに決まった候補を返す変換エンジン．変換の質はエンジンの性能なので，core のテストでは固定する
@MainActor
public final class FakeConverter: KanaKanjiConverting {
    public var table: [String: [(text: String, readingCount: Int?)]]
    public private(set) var committed: [Candidate] = []
    public private(set) var endCount = 0

    public init(_ table: [String: [(text: String, readingCount: Int?)]] = [:]) {
        self.table = table
    }

    public func candidates(for reading: String) -> [Candidate] {
        // 本物と同じく，空の読みには空の配列を返す
        guard !reading.isEmpty else { return [] }
        return (table[reading] ?? []).enumerated().map { index, entry in
            Candidate(text: entry.text, readingCount: entry.readingCount ?? reading.count, origin: .engine(id: index))
        }
    }

    public func didCommit(_ candidate: Candidate) { committed.append(candidate) }
    public func endComposition() { endCount += 1 }
}

@MainActor
public final class FakeLexicon: EnglishLexicon {
    public var words: Set<String>
    public var suggestionTable: [String: [String]]

    public init(words: Set<String> = [], suggestions: [String: [String]] = [:]) {
        self.words = words
        self.suggestionTable = suggestions
    }

    public func isWord(_ text: String) -> Bool { words.contains(text.lowercased()) }
    public func suggestions(for text: String) -> [String] { suggestionTable[text] ?? [] }
}

@MainActor
public final class FakeSettings: SettingsStoring {
    public var current: Settings

    public init(_ settings: Settings = DefaultSettings.settings) {
        self.current = settings
    }

    public func update(_ change: (inout Settings) -> Void) throws { change(&current) }
}
