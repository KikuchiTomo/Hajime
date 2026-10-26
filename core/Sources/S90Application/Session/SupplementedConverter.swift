import S90Domain

/// 変換エンジンの候補に，エンジンが出さない候補を足す．
///
/// - ユーザー辞書の語: 読みが一致すれば先頭に置く．登録した語は選びたい語なので．
///   エンジンにもユーザー辞書を渡している(文の中の語として使うため)が，エンジンは辞書の語の続きになる読みしか
///   たどらないので，辞書に無い読みの語は出ない．読み全体が一致する語はここで確実に出す(同じ語は重ねない)
/// - 記号(SymbolDictionary): 「やじるし」→「→」など
/// - 日付と時刻(DateExpressions): 「きょう」→「2026/10/26」など
/// - 計算(Calculator): 「1+2*3=」→「7」「1+2*3=7」．結果を先頭に置く(式を打って「=」を打つのは計算したいときなので)
/// - よくある読み違い(Misreadings): 「ふいんき」→「雰囲気」を 2 番目に置く
/// - 送り仮名(Okurigana): 本則か許容の選んだ方を先に並べる
/// - 郵便番号(PostalCode): 「100-0001」→「東京都千代田区千代田」．区切りがあれば先頭に，無ければ 2 番目に置く(7 桁の数字のこともあるので)
///
/// - 取り込んだ辞書の語(R-16): 読みの中の部分ごとに，効いている辞書から語を引いてエンジンに渡す(setAuxiliaryWords)．
///   どの辞書を効かせるかは DictionaryActivation が決める(アプリの条件，文脈の条件)
///
/// 記号と日付は上から DefaultSettings.symbolCandidateOffset 番目に差し込む．
/// 第 1 候補(ライブ変換で見える文字)は変えず，よく使う語より前に並ばないようにする
@MainActor
public final class SupplementedConverter: KanaKanjiConverting {
    private let base: any KanaKanjiConverting
    private let settings: any SettingsReading
    private let calendar: any CalendarReading
    private let postalCodes: (any PostalCodeLooking)?
    /// ユーザー辞書を読みで引く表．設定のユーザー辞書が変わったときだけ作り直す
    private var dictionaryIndex: (source: [UserDictionaryEntry], words: [String: [String]]) = ([], [:])
    /// 取り込んだ辞書を引くもの．無ければ取り込んだ辞書は使わない
    private let lookup: (any DictionaryLookup)?
    private var applicationID: String?
    /// 最近確定した，取り込んだ辞書の語の辞書の id(新しいものが後ろ)．文脈の条件に使う
    private var recentDictionaryCommits: [String] = []
    /// 今エンジンに渡している語と，その語の辞書の名前
    private var auxiliary: [AuxiliaryWord] = []
    private var auxiliarySources: [DictionaryWord: Source] = [:]
    /// 読みごとに引いた語と，その語の辞書．効いている辞書が変わったときと，入力を終えたときに捨てる
    private var auxiliaryCache: (active: [DictionaryActivation.Active], lookups: [String: Lookup]) = ([], [:])

    private struct Source {
        var id: String
        var name: String
    }

    private struct Lookup {
        var words: [AuxiliaryWord]
        var sources: [DictionaryWord: Source]
    }

    public init(_ base: any KanaKanjiConverting, settings: any SettingsReading, calendar: any CalendarReading,
                postalCodes: (any PostalCodeLooking)? = nil, dictionaries: (any DictionaryLookup)? = nil) {
        self.base = base
        self.settings = settings
        self.calendar = calendar
        self.postalCodes = postalCodes
        self.lookup = dictionaries
    }

    public func candidates(for reading: String) -> [Candidate] {
        prepareAuxiliaryWords(for: reading)
        return supplement(base.candidates(for: reading), reading: reading)
    }

    public func clauseCandidates(for reading: String) -> [Candidate] {
        prepareAuxiliaryWords(for: reading)
        // 文節の候補は読みの先頭の一部なので，足す候補は読み全体と一致するときだけ足す
        return supplement(base.clauseCandidates(for: reading), reading: reading)
    }

    public func setApplication(_ identifier: String?) {
        applicationID = identifier
        base.setApplication(identifier)
    }

    public func sourceName(of text: String, reading: String) -> String? {
        auxiliary.first { text.contains($0.word.word) && reading.contains($0.word.reading) }
            .flatMap { auxiliarySources[$0.word]?.name }
    }

    // MARK: - 取り込んだ辞書(R-16)

    /// 読みの中の部分ごとに効いている辞書から語を引き，変わっていればエンジンに渡す
    private func prepareAuxiliaryWords(for reading: String) {
        guard let lookup else { return }
        let dictionaries = settings.current.importedDictionaries
        let hits = Dictionary(recentDictionaryCommits.map { ($0, 1) }, uniquingKeysWith: +)
        let active = DictionaryActivation.active(dictionaries, applicationID: applicationID, recentHits: hits)
        if active != auxiliaryCache.active { auxiliaryCache = (active, [:]) }
        let found = auxiliaryCache.lookups[reading] ?? Self.lookUp(reading, in: active, lookup: lookup)
        auxiliaryCache.lookups[reading] = found
        auxiliarySources = found.sources
        guard found.words != auxiliary else { return }
        auxiliary = found.words
        base.setAuxiliaryWords(found.words)
    }

    /// reading の中の部分(長さ DefaultSettings.maximumImportedReadingLength まで)を，効いている辞書で引く．
    /// 同じ語が複数の辞書にあれば，優先度の高い方を使う
    private static func lookUp(_ reading: String, in active: [DictionaryActivation.Active], lookup: any DictionaryLookup) -> Lookup {
        guard !active.isEmpty else { return Lookup(words: [], sources: [:]) }
        let characters = Array(reading)
        var best: [DictionaryWord: Float] = [:]
        var sources: [DictionaryWord: Source] = [:]
        for start in characters.indices {
            for length in 1...min(DefaultSettings.maximumImportedReadingLength, characters.count - start) {
                let part = String(characters[start..<(start + length)])
                for entry in active {
                    for word in lookup.words(reading: part, in: entry.dictionary) where best[word].map({ entry.costOffset > $0 }) ?? true {
                        best[word] = entry.costOffset
                        sources[word] = Source(id: entry.dictionary.id, name: entry.dictionary.displayName)
                    }
                }
            }
        }
        let words = best.map { AuxiliaryWord(word: $0.key, costOffset: $0.value) }
            .sorted { ($0.word.reading, $0.word.word) < ($1.word.reading, $1.word.word) }
        return Lookup(words: words, sources: sources)
    }

    /// 確定した候補に取り込んだ辞書の語があれば，その辞書を最近使ったものとして数える
    private func recordDictionaryCommit(_ candidate: Candidate) {
        let ids = Set(auxiliary.filter { candidate.text.contains($0.word.word) }.compactMap { auxiliarySources[$0.word]?.id })
        guard !ids.isEmpty else { return }
        recentDictionaryCommits.append(contentsOf: ids.sorted())
        recentDictionaryCommits = Array(recentDictionaryCommits.suffix(DefaultSettings.importedDictionaryContextWindow))
    }

    public func plausibility(of reading: String) -> Double { base.plausibility(of: reading) }
    public func segmentationWords(for reading: String) -> [Candidate.Word] { base.segmentationWords(for: reading) }
    public func typoCorrections(forKeys keys: String) -> [ReadingCorrection] { base.typoCorrections(forKeys: keys) }
    public func setLeftContext(_ text: String?) { base.setLeftContext(text) }
    public func didCommit(_ candidate: Candidate) {
        recordDictionaryCommit(candidate)
        base.didCommit(candidate)
    }
    public func setAuxiliaryWords(_ words: [AuxiliaryWord]) { base.setAuxiliaryWords(words) }
    public func endComposition() {
        auxiliaryCache.lookups = [:]
        base.endComposition()
    }

    private func supplement(_ candidates: [Candidate], reading: String) -> [Candidate] {
        let current = settings.current
        var result = Okurigana.reorder(candidates, style: current.okuriganaStyle)
        let userWords = userDictionaryWords(for: reading, in: current.userDictionary)
        insert(userWords, into: &result, at: 0, reading: reading, origin: .userDictionary)
        // 読み全体と一致する取り込んだ辞書の語は，エンジンの候補の順に関わらず前の方に出るようにここで足す．
        // 既定の 1 番目は変えず，その次に優先度の順で並べる
        let importedWords = auxiliary.filter { $0.word.reading == reading }.sorted { $0.costOffset > $1.costOffset }.map(\.word.word)
        insert(importedWords, into: &result, at: DefaultSettings.importedWordCandidateOffset, reading: reading, origin: .userDictionary)
        var extra: [String] = []
        if current.symbolConversion { extra += SymbolDictionary.symbols(for: reading, rules: current.symbolRules) }
        if current.dateConversion {
            extra += DateExpressions.candidates(for: reading, now: calendar.now(), day: calendar.day(offsetFromToday:))
        }
        insert(extra, into: &result, at: DefaultSettings.symbolCandidateOffset, reading: reading, origin: .symbol)
        if current.misreadings, let entry = Misreadings.entry(for: reading) {
            insert([entry.word], into: &result, at: 1, reading: reading, origin: .symbol)
        }
        if current.postalCodeConversion, let postalCodes, let query = PostalCode.query(for: reading) {
            insert(postalCodes.addresses(for: query.code), into: &result, at: query.hasSeparator ? 0 : 1, reading: reading, origin: .symbol)
        }
        if current.calculation, let calculation = Calculator.evaluate(reading: reading) {
            insert([calculation.result, calculation.expression + "=" + calculation.result], into: &result, at: 0, reading: reading, origin: .symbol)
        }
        return result
    }

    private func userDictionaryWords(for reading: String, in entries: [UserDictionaryEntry]) -> [String] {
        // 設定を写しても配列の中身は共有されるので，変わっていなければ比べるのはすぐ済む
        if dictionaryIndex.source != entries {
            dictionaryIndex = (entries, Dictionary(grouping: entries.filter(\.isValid), by: \.reading).mapValues { $0.map(\.word) })
        }
        return dictionaryIndex.words[reading] ?? []
    }

    private func insert(_ texts: [String], into candidates: inout [Candidate], at position: Int, reading: String, origin: CandidateOrigin) {
        var seen = Set(candidates.map(\.text))
        let added = texts.filter { seen.insert($0).inserted }.map { Candidate(text: $0, readingCount: reading.count, origin: origin) }
        guard !added.isEmpty else { return }
        candidates.insert(contentsOf: added, at: min(position, candidates.count))
    }
}
