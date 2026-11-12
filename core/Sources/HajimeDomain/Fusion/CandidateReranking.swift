/// 候補を，文脈を見る言語モデルの点数(検証木．ADR 0016)で並べ替える規則．
///
/// - 第 1 候補は変えない．第 1 候補は Zenzai が文脈と読みで確かめたもので，ライブ変換で見えている文字と同じにするため
/// - 並べ替えるのは，2 番目より後ろの「エンジンが出した，読み全体の候補」(エンジンの語をつないだ候補と，文の候補から切り出した文節を含む)だけ．足す候補(Zenzai を使わない変換の候補など)もここに混ぜる
/// - それ以外の候補(記号・ユーザー辞書の語・コマンド・読みの一部の候補など)は元の位置に残す．置き場所を決めた候補を動かさないため
/// - 並べ替える候補のうち点数の無いもの(採点の上限に入らなかったもの)は，点数のある候補のあとに元の順で置く
/// - 促音の切れ端を漢字とつないだ候補(SokuonFragments)は並べ替えず，並べ替えたあとも同じ読みの数のほかの候補の下に置く．
///   検証木は「はっ再」「じゅっ分」のような書き方を高く採点することがあるため
/// - 足した候補で並べ替える候補が増えたぶんは，並べ替える候補の最後の位置のすぐ後ろに入れる
public enum CandidateReranking {
    /// 並べ替える候補か．エンジンが出した，読み全体の候補(エンジンの語をつないだ候補と，文の候補から切り出した文節を含む)
    public static func isRerankable(_ candidate: Candidate, readingCount: Int) -> Bool {
        guard candidate.readingCount == readingCount, !SokuonFragments.isBroken(candidate), !SokuonFragments.isFragmented(candidate) else { return false }
        switch candidate.origin {
        case .engine, .combined, .sentencePart: return true
        default: return false
        }
    }

    /// 採点する表記．第 1 候補は並べ替えないので含めない．前ほど優先して採点されるので，今の候補を先に，足す候補をあとに置く
    public static func textsToScore(_ candidates: [Candidate], adding additions: [Candidate], readingCount: Int) -> [String] {
        rerankable(candidates, adding: additions, readingCount: readingCount).pool.map(\.text)
    }

    /// - Parameters:
    ///   - candidates: 候補(よさそうな順)
    ///   - additions: 足す候補．candidates に同じ表記があれば足さない．並べ替える候補に当たらないものは使わない
    ///   - readingCount: 読み全体の文字数
    ///   - score: 表記の点数(大きいほどよい)．採点していなければ nil
    public static func reranked(_ candidates: [Candidate], adding additions: [Candidate], readingCount: Int,
                                score: (String) -> Double?) -> [Candidate] {
        guard !candidates.isEmpty else { return [] }
        let (slots, pool) = rerankable(candidates, adding: additions, readingCount: readingCount)
        let scored = pool.enumerated().compactMap { offset, candidate in score(candidate.text).map { (offset, candidate, $0) } }
        // 点数が同じなら元の順を保つ(並べ替えのたびに順が揺れないように)
        let ordered = scored.sorted { $0.2 != $1.2 ? $0.2 > $1.2 : $0.0 < $1.0 }.map(\.1) + pool.filter { score($0.text) == nil }
        var result = candidates
        for (slot, candidate) in zip(slots, ordered) {
            result[slot] = candidate
        }
        let extra = ordered.dropFirst(slots.count)
        result.insert(contentsOf: extra, at: slots.last.map { $0 + 1 } ?? 1)
        return SokuonFragments.cleaned(result)
    }

    /// 並べ替える候補の位置(第 1 候補を除く)と，足す候補を合わせた並べ替える候補(表記の重なりを除く)
    private static func rerankable(_ candidates: [Candidate], adding additions: [Candidate], readingCount: Int) -> (slots: [Int], pool: [Candidate]) {
        var seen = Set(candidates.prefix(1).map(\.text))
        var slots: [Int] = []
        var pool: [Candidate] = []
        for (index, candidate) in candidates.enumerated().dropFirst() where isRerankable(candidate, readingCount: readingCount) {
            guard seen.insert(candidate.text).inserted else { continue }
            slots.append(index)
            pool.append(candidate)
        }
        for candidate in additions where isRerankable(candidate, readingCount: readingCount) && !candidates.contains(where: { $0.text == candidate.text }) {
            guard seen.insert(candidate.text).inserted else { continue }
            pool.append(candidate)
        }
        return (slots, pool)
    }
}
