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
///
/// 記号と日付は上から DefaultSettings.symbolCandidateOffset 番目に差し込む．
/// 第 1 候補(ライブ変換で見える文字)は変えず，よく使う語より前に並ばないようにする
@MainActor
public final class SupplementedConverter: KanaKanjiConverting {
    private let base: any KanaKanjiConverting
    private let settings: any SettingsReading
    private let calendar: any CalendarReading
    /// ユーザー辞書を読みで引く表．設定のユーザー辞書が変わったときだけ作り直す
    private var dictionaryIndex: (source: [UserDictionaryEntry], words: [String: [String]]) = ([], [:])

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
    public func segmentationWords(for reading: String) -> [Candidate.Word] { base.segmentationWords(for: reading) }
    public func typoCorrections(forKeys keys: String) -> [ReadingCorrection] { base.typoCorrections(forKeys: keys) }
    public func setLeftContext(_ text: String?) { base.setLeftContext(text) }
    public func didCommit(_ candidate: Candidate) { base.didCommit(candidate) }
    public func endComposition() { base.endComposition() }

    private func supplement(_ candidates: [Candidate], reading: String) -> [Candidate] {
        let current = settings.current
        var result = Okurigana.reorder(candidates, style: current.okuriganaStyle)
        let userWords = userDictionaryWords(for: reading, in: current.userDictionary)
        insert(userWords, into: &result, at: 0, reading: reading, origin: .userDictionary)
        var extra: [String] = []
        if current.symbolConversion { extra += SymbolDictionary.symbols(for: reading, rules: current.symbolRules) }
        if current.dateConversion {
            extra += DateExpressions.candidates(for: reading, now: calendar.now(), day: calendar.day(offsetFromToday:))
        }
        insert(extra, into: &result, at: DefaultSettings.symbolCandidateOffset, reading: reading, origin: .symbol)
        if current.misreadings, let entry = Misreadings.entry(for: reading) {
            insert([entry.word], into: &result, at: 1, reading: reading, origin: .symbol)
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
