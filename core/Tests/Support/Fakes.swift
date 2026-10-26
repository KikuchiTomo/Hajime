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
    /// 候補の文字列ごとの語の並び(本物のエンジンの候補が持つもの)．直した語句の位置を求めるのに使う
    public var candidateWords: [String: [Candidate.Word]] = [:]

    public func candidates(for reading: String) -> [Candidate] {
        // 本物と同じく，空の読みには空の配列を返す
        guard !reading.isEmpty else { return [] }
        return (table[reading] ?? []).enumerated().map { index, entry in
            Candidate(text: entry.text, readingCount: entry.readingCount ?? reading.count, origin: .engine(id: index), score: scores[reading] ?? 0,
                      trailingWord: trailingWords[entry.text], words: candidateWords[entry.text] ?? [])
        }
    }

    /// 読みごとの語の並び(文節の区切りを決める)
    public var words: [String: [Candidate.Word]] = [:]
    public var languageModelScores: [String: Double] = [:]
    public var predictionTexts: [String: [String]] = [:]
    public func segmentationWords(for reading: String) -> [Candidate.Word] { words[reading] ?? [] }
    public func languageModelScores(forKeys keys: [String]) -> [Double?] { keys.map { languageModelScores[$0] } }
    public func predictions(for reading: String) -> [Candidate] {
        (predictionTexts[reading] ?? []).map { Candidate(text: $0, readingCount: reading.count, origin: .variant(.hiragana)) }
    }
    public func plausibility(of reading: String) -> Double { scores[reading] ?? (table[reading] == nil ? -.infinity : 0) }
    /// 打ったキーごとの，打ち間違いを直した読みの候補
    public var corrections: [String: [ReadingCorrection]] = [:]
    public func typoCorrections(forKeys keys: String) -> [ReadingCorrection] { corrections[keys] ?? [] }
    public private(set) var leftContext: String?
    public func setLeftContext(_ text: String?) { leftContext = text }
    public func didCommit(_ candidate: Candidate) {
        committed.append(candidate)
        // 本物と同じく，学習を使わない変換で確定した語は学ばない(取り消すものに数えない)
        if !learningSuspended { committedInComposition.append(candidate) }
    }
    /// 取り込んだ辞書から渡された語(最後に渡されたもの)
    public private(set) var auxiliaryWords: [AuxiliaryWord] = []
    public func setAuxiliaryWords(_ words: [AuxiliaryWord]) { auxiliaryWords = words }
    public func endComposition() {
        endCount += 1
        learningSuspended = false
        if !committedInComposition.isEmpty { lastCommitted = committedInComposition }
        committedInComposition = []
    }

    /// 学習から消した候補
    public private(set) var forgotten: [Candidate] = []
    /// 学習を使わずに変換しているか(入力を終えると戻る)
    public private(set) var learningSuspended = false
    /// 学習を使わずに変換したことがあるか
    public private(set) var suspendCount = 0
    private var committedInComposition: [Candidate] = []
    private var lastCommitted: [Candidate] = []

    public func forget(_ candidate: Candidate) { forgotten.append(candidate) }

    public func forgetLastCommit() -> Bool {
        guard !lastCommitted.isEmpty else { return false }
        forgotten += lastCommitted
        lastCommitted = []
        return true
    }

    public func suspendLearningUntilEnd() {
        learningSuspended = true
        suspendCount += 1
    }
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

/// 決まった日付を返す暦．2026 年 10 月 26 日(月) 14:05 を今日とし，ずらした日は日だけを足す(月をまたがない範囲で使う)
@MainActor
public final class FakeCalendar: CalendarReading {
    public init() {}
    public func now() -> CalendarDate { CalendarDate(year: 2026, month: 10, day: 26, weekday: 2, hour: 14, minute: 5) }
    public func day(offsetFromToday offset: Int) -> CalendarDate {
        CalendarDate(year: 2026, month: 10, day: 26 + offset, weekday: (2 + offset - 1) % 7 + 1)
    }
}

/// 辞書の id と語ごとに決まったまとまりを返す連想の辞書(R-18)．本物の索引のファイルと同じく，まとまりの語は引いた語を除いたもの
@MainActor
public final class FakeAssociationLookup: AssociationLookup {
    public var groups: [String: [String: [AssociationGroup]]]
    /// 引いた語(引いた順)
    public private(set) var queries: [String] = []

    public init(_ groups: [String: [String: [AssociationGroup]]] = [:]) {
        self.groups = groups
    }

    public func groups(for word: String, in dictionary: AssociationDictionary) -> [AssociationGroup] {
        queries.append(word)
        return groups[dictionary.id]?[word] ?? []
    }
}
