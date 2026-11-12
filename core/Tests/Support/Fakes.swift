import HajimeApplication
import HajimeDomain

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
            Candidate(text: entry.text, readingCount: entry.readingCount, origin: .engine(id: 1000 + index), score: -Double(index) * (clauseScoreStep[reading] ?? 3),
                      words: candidateWords[entry.text] ?? [])
        }
    }

    /// 文節の読みだけの候補．本物は文節の読みだけを変換する．ここでは，その読みで始まる読みの文節の候補のうち，
    /// 長さが文節の読みと同じものを集める(文節の候補の表を後ろの読みごとに書いておけば，文節の読みだけでも同じ候補になる)
    public func segmentCandidates(for reading: String) -> [Candidate] {
        guard !reading.isEmpty else { return [] }
        var seen = Set<String>()
        let fromClauses = clauseTable.keys.sorted { ($0.count, $0) < ($1.count, $1) }.filter { $0.hasPrefix(reading) }
            .flatMap { clauseCandidates(for: $0) }
            .filter { $0.readingCount == reading.count && seen.insert($0.text).inserted }
        return fromClauses + candidates(for: reading).filter { $0.readingCount == reading.count && seen.insert($0.text).inserted }
    }

    /// 候補の文字列ごとの末尾の語．ライブ変換で打っている途中の語をかなのまま見せるかの確認に使う
    public var trailingWords: [String: Candidate.TrailingWord] = [:]
    /// 候補の文字列ごとの語の並び(本物のエンジンの候補が持つもの)．直した語句の位置を求めるのに使う
    public var candidateWords: [String: [Candidate.Word]] = [:]

    /// 入力中の表示を求めているか(setTyping)と，候補を求めた読みごとにそのときの値
    public private(set) var typing = false
    public private(set) var requests: [(reading: String, typing: Bool)] = []

    public func setTyping(_ typing: Bool) {
        self.typing = typing
    }

    public func candidates(for reading: String) -> [Candidate] {
        requests.append((reading, typing))
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
    /// 確定した履歴(学習)にある予測の語句
    public var learnedPredictions: Set<String> = []
    /// 予測をエンジンの候補(確定すると学ぶ)にするか．既定は学ばない候補
    public var predictionsAreLearnable = false
    public func predictions(for reading: String) -> [Candidate] {
        (predictionTexts[reading] ?? []).enumerated().map { index, text in
            var candidate = Candidate(text: text, readingCount: reading.count, origin: predictionsAreLearnable ? .engine(id: 2000 + index) : .variant(.hiragana))
            candidate.isLearned = learnedPredictions.contains(text)
            return candidate
        }
    }
    public func plausibility(of reading: String) -> Double { scores[reading] ?? (table[reading] == nil ? -.infinity : 0) }
    /// 打ったキーごとの，打ち間違いを直した読みの候補
    public var corrections: [String: [ReadingCorrection]] = [:]
    public func typoCorrections(forKeys keys: String) -> [ReadingCorrection] { corrections[keys] ?? [] }
    public private(set) var leftContext: String?
    public func setLeftContext(_ text: String?) { leftContext = text }
    public func didCommit(_ candidate: Candidate) {
        committedAnyInComposition = true
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
        // 本物と同じく，学ばなかった入力も最後の確定にする
        if committedAnyInComposition { lastCommitted = committedInComposition }
        committedAnyInComposition = false
        committedInComposition = []
    }

    /// 学習から消した候補
    public private(set) var forgotten: [Candidate] = []
    /// 学習を使わずに変換しているか(入力を終えると戻る)
    public private(set) var learningSuspended = false
    /// 学習を使わずに変換したことがあるか
    public private(set) var suspendCount = 0
    private var committedInComposition: [Candidate] = []
    private var committedAnyInComposition = false
    private var lastCommitted: [Candidate] = []
    /// 確定を取り消して，最後に確定した入力の候補を戻した回数
    public private(set) var reopenCount = 0
    public func reopenLastCommit() { reopenCount += 1 }

    public func forget(_ candidate: Candidate) { forgotten.append(candidate) }
    /// 読みの一部だけを学習から消したときの，候補と読みの範囲
    public private(set) var forgottenRanges: [(text: String, range: Range<Int>)] = []
    public func forget(_ candidate: Candidate, readingRange range: Range<Int>) { forgottenRanges.append((candidate.text, range)) }

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

/// 決まった意味の辞書を返す(R-08)
@MainActor
public final class FakeUsageDictionaryProvider: UsageDictionaryProviding {
    public let usageDictionary: UsageDictionary?

    public init(_ dictionary: UsageDictionary?) {
        usageDictionary = dictionary
    }
}

/// 決まった語を返す同梱の英語の語の辞書(R-24)
@MainActor
public final class FakeEnglishTermProvider: EnglishTermProviding {
    public let englishTerms: EnglishTermDictionary?

    public init(_ terms: [String]) {
        self.englishTerms = EnglishTermDictionary(terms: terms)
    }
}

/// 絵文字の表の代わり．読みごとの絵文字と名前を返し，確定した絵文字と読みを覚える
@MainActor
public final class FakeEmoji: EmojiLooking {
    public let table: [String: [String]]
    public let names: [String: String]
    public private(set) var committed: [(emoji: String, reading: String)] = []

    public init(_ table: [String: [String]], names: [String: String] = [:]) {
        self.table = table
        self.names = names
    }

    /// 文節の語(word)は覚えておく(テストで確かめる)．照らし合わせはパレットの表(EmojiRelevance)でするので，ここでは読みだけで引く
    public private(set) var words: [String: EmojiWord] = [:]
    public func emoji(for reading: String, word: EmojiWord, limit: Int) -> [String] {
        words[reading] = word
        return Array((table[reading] ?? []).prefix(limit))
    }
    public func name(of emoji: String) -> String? { names[emoji] }
    public func didCommit(_ emoji: String, reading: String) { committed.append((emoji, reading)) }
}

/// 決まった表を渡すパレットの表(R-26)．index を nil にすると読み込み中として振る舞う
@MainActor
public final class FakePaletteCatalog: PaletteCatalogProviding {
    public var index: PaletteIndex?

    public init(_ text: String) {
        self.index = PaletteIndex(catalog: PaletteCatalog(text: text))
    }
}

/// メモリの中だけに持つパレットの使い方
@MainActor
public final class FakePaletteUsageStore: PaletteUsageStoring {
    public private(set) var usage: PaletteUsage
    public private(set) var saveCount = 0

    public init(_ usage: PaletteUsage = PaletteUsage()) {
        self.usage = usage
    }

    public func update(_ change: (inout PaletteUsage) -> Void) {
        let before = usage
        change(&usage)
        if usage != before { saveCount += 1 }
    }
}

/// 表記ごとの点数を表から返す採点(検証木の代わり)．問い合わせを覚える
@MainActor
public final class FakeCandidateScorer: CandidateScoring {
    /// 表記 → 点数．無い表記は nil(採点できなかった)
    public var table: [String: Double]
    public private(set) var requests: [(texts: [String], reading: String, before: String, after: String)] = []

    public init(_ table: [String: Double] = [:]) {
        self.table = table
    }

    /// 採点が遅い環境として振る舞うか
    public var prefersPrecomputedScores = false
    /// scores で答えた問い(cachedScores が答える)
    private var answered: Set<[String]> = []

    public func scores(of texts: [String], reading: String, before: String, after: String) -> [Double?] {
        requests.append((texts, reading, before, after))
        answered.insert([reading, before, after] + texts)
        return texts.map { table[$0] }
    }

    public func cachedScores(of texts: [String], reading: String, before: String, after: String) -> [Double?]? {
        answered.contains([reading, before, after] + texts) ? texts.map { table[$0] } : nil
    }
}
