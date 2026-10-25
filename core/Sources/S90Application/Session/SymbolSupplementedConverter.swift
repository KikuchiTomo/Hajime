import S90Domain

/// 変換エンジンの候補に，読みから引く記号(SymbolDictionary)を足す．
/// 「やじるし」→「→」のように，エンジンの辞書に無い記号も候補に出すため．
///
/// 記号は上から DefaultSettings.symbolCandidateOffset 番目に差し込む．
/// 第 1 候補(ライブ変換で見える文字)は変えず，よく使う語より前に記号が並ばないようにする
@MainActor
public final class SymbolSupplementedConverter: KanaKanjiConverting {
    private let base: any KanaKanjiConverting

    public init(_ base: any KanaKanjiConverting) {
        self.base = base
    }

    public func candidates(for reading: String) -> [Candidate] {
        supplement(base.candidates(for: reading), reading: reading)
    }

    public func clauseCandidates(for reading: String) -> [Candidate] {
        // 文節の候補は読みの先頭の一部なので，記号は読み全体と一致するときだけ足す
        supplement(base.clauseCandidates(for: reading), reading: reading)
    }

    public func plausibility(of reading: String) -> Double { base.plausibility(of: reading) }
    public func setLeftContext(_ text: String?) { base.setLeftContext(text) }
    public func didCommit(_ candidate: Candidate) { base.didCommit(candidate) }
    public func endComposition() { base.endComposition() }

    private func supplement(_ candidates: [Candidate], reading: String) -> [Candidate] {
        let symbols = SymbolDictionary.symbols(for: reading)
            .filter { symbol in !candidates.contains { $0.text == symbol } }
            .map { Candidate(text: $0, readingCount: reading.count, origin: .symbol) }
        guard !symbols.isEmpty else { return candidates }
        var result = candidates
        result.insert(contentsOf: symbols, at: min(DefaultSettings.symbolCandidateOffset, result.count))
        return result
    }
}
