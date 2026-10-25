import S90Domain

/// 変換エンジンの候補に，エンジンが出さない候補を足す．
///
/// - ユーザー辞書の語: 読みが一致すれば先頭に置く．登録した語は選びたい語なので
/// - 記号(SymbolDictionary): 「やじるし」→「→」など
/// - 日付と時刻(DateExpressions): 「きょう」→「2026/10/26」など
///
/// 記号と日付は上から DefaultSettings.symbolCandidateOffset 番目に差し込む．
/// 第 1 候補(ライブ変換で見える文字)は変えず，よく使う語より前に並ばないようにする
@MainActor
public final class SupplementedConverter: KanaKanjiConverting {
    private let base: any KanaKanjiConverting
    private let settings: any SettingsReading
    private let calendar: any CalendarReading

    public init(_ base: any KanaKanjiConverting, settings: any SettingsReading, calendar: any CalendarReading) {
        self.base = base
        self.settings = settings
        self.calendar = calendar
    }

    public func candidates(for reading: String) -> [Candidate] {
        supplement(base.candidates(for: reading), reading: reading)
    }

    public func clauseCandidates(for reading: String) -> [Candidate] {
        // 文節の候補は読みの先頭の一部なので，足す候補は読み全体と一致するときだけ足す
        supplement(base.clauseCandidates(for: reading), reading: reading)
    }

    public func plausibility(of reading: String) -> Double { base.plausibility(of: reading) }
    public func typoCorrections(forKeys keys: String) -> [ReadingCorrection] { base.typoCorrections(forKeys: keys) }
    public func setLeftContext(_ text: String?) { base.setLeftContext(text) }
    public func didCommit(_ candidate: Candidate) { base.didCommit(candidate) }
    public func endComposition() { base.endComposition() }

    private func supplement(_ candidates: [Candidate], reading: String) -> [Candidate] {
        let current = settings.current
        var result = candidates
        let userWords = current.userDictionary.filter { $0.reading == reading && $0.isValid }.map(\.word)
        insert(userWords, into: &result, at: 0, reading: reading, origin: .userDictionary)
        var extra: [String] = []
        if current.symbolConversion { extra += SymbolDictionary.symbols(for: reading) }
        if current.dateConversion {
            extra += DateExpressions.candidates(for: reading, now: calendar.now(), day: calendar.day(offsetFromToday:))
        }
        insert(extra, into: &result, at: DefaultSettings.symbolCandidateOffset, reading: reading, origin: .symbol)
        return result
    }

    private func insert(_ texts: [String], into candidates: inout [Candidate], at position: Int, reading: String, origin: CandidateOrigin) {
        var seen = Set(candidates.map(\.text))
        let added = texts.filter { seen.insert($0).inserted }.map { Candidate(text: $0, readingCount: reading.count, origin: origin) }
        guard !added.isEmpty else { return }
        candidates.insert(contentsOf: added, at: min(position, candidates.count))
    }
}
