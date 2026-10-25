import S90Application
import S90Domain

/// 読みごとに決まった候補を返す変換エンジン．変換の質はエンジンの性能なので，core のテストでは固定する
@MainActor
public final class FakeConverter: KanaKanjiConverting {
    public var table: [String: [(text: String, readingCount: Int?)]]
    /// 文節格子のための，読みの先頭の文節の候補．点数は並び順から付ける(先が高い)
    public var clauseTable: [String: [(text: String, readingCount: Int)]]
    /// 文節の候補の点数が 1 つ下がるごとにいくつ下がるか．既定の 3 は確信度が高い差．読みごとに変えられる
    public var clauseScoreStep: [String: Double] = [:]
    public private(set) var committed: [Candidate] = []
    public private(set) var endCount = 0
    /// 読みごとの点数(読みとしてのもっともらしさ)．無い読みは 0
    public var scores: [String: Double] = [:]

    public init(_ table: [String: [(text: String, readingCount: Int?)]] = [:], clauses: [String: [(text: String, readingCount: Int)]] = [:]) {
        self.table = table
        self.clauseTable = clauses
    }

    public func clauseCandidates(for reading: String) -> [Candidate] {
        guard !reading.isEmpty else { return [] }
        return (clauseTable[reading] ?? []).enumerated().map { index, entry in
            Candidate(text: entry.text, readingCount: entry.readingCount, origin: .engine(id: 1000 + index), score: -Double(index) * (clauseScoreStep[reading] ?? 3))
        }
    }

    /// 候補の文字列ごとの末尾の語．ライブ変換で打っている途中の語をかなのまま見せるかの確認に使う
    public var trailingWords: [String: Candidate.TrailingWord] = [:]

    public func candidates(for reading: String) -> [Candidate] {
        // 本物と同じく，空の読みには空の配列を返す
        guard !reading.isEmpty else { return [] }
        return (table[reading] ?? []).enumerated().map { index, entry in
            Candidate(text: entry.text, readingCount: entry.readingCount ?? reading.count, origin: .engine(id: index), score: scores[reading] ?? 0,
                      trailingWord: trailingWords[entry.text])
        }
    }

    public func plausibility(of reading: String) -> Double { scores[reading] ?? (table[reading] == nil ? -.infinity : 0) }
    /// 打ったキーごとの，打ち間違いを直した読みの候補
    public var corrections: [String: [ReadingCorrection]] = [:]
    public func typoCorrections(forKeys keys: String) -> [ReadingCorrection] { corrections[keys] ?? [] }
    public private(set) var leftContext: String?
    public func setLeftContext(_ text: String?) { leftContext = text }
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
