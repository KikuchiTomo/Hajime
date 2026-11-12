/// 文節格子の文節を 1 か所だけほかの候補に替えた文．文全体の候補の一覧に入れる．
///
/// エンジンの文全体の候補は，点数の近い文から順に並ぶので，同じ文節の言い換え(「パイソンで」「Pythonで」)ばかりが上に来て，
/// ほかの文節で迷っていた字(「書こう」)が一覧に出ないことがある．一覧では文節を選び直せないので，
/// 文節ごとの候補で 1 か所だけ替えた文を，迷う文節から順に並べて，どの文節の言い換えも上のほうで選べるようにする
public enum SegmentSubstitution {
    /// lattice の文節を 1 か所だけ替えた文．候補の順位ごとに，迷う文節(第 1 候補と 2 番目の差が小さい)から並べる．
    /// 各文節の 2 番目から perSegment 個までを使う．文節が 1 つなら空(文全体の候補と同じになるため)
    public static func sentences(from lattice: SegmentLattice, perSegment: Int) -> [Candidate] {
        let segments = lattice.segments
        guard segments.count > 1, perSegment > 0 else { return [] }
        let readingCount = segments.reduce(0) { $0 + $1.readingLength }
        // 迷う文節から．差が同じなら前の文節から
        let order = segments.indices.sorted { (segments[$0].confidenceGap, $0) < (segments[$1].confidenceGap, $1) }
        var seen: Set<String> = [lattice.text]
        var result: [Candidate] = []
        for rank in 1...perSegment {
            for index in order where segments[index].candidates.count > rank {
                var parts = segments.map(\.selected)
                parts[index] = segments[index].candidates[rank]
                let text = parts.map(\.text).joined()
                guard seen.insert(text).inserted else { continue }
                var candidate = Candidate(text: text, readingCount: readingCount, origin: .combined)
                // 確定したら，分岐図で確定したときと同じく文節ごとの候補を学ぶ
                candidate.learnedParts = parts.flatMap { $0.isFromEngine ? [$0] : $0.learnedParts }
                result.append(candidate)
            }
        }
        return result
    }

    /// 文全体の候補(engine)の 2 番目から，替えた文(substitutions)と 1 つずつ交互に並べる．同じ字は先に出たほうだけ残す
    public static func interleave(_ engine: [Candidate], with substitutions: [Candidate]) -> [Candidate] {
        guard let first = engine.first else { return substitutions }
        var result = [first]
        var seen: Set<String> = [first.text]
        var rest = engine.dropFirst().makeIterator()
        var others = substitutions.makeIterator()
        var exhausted = (rest: false, others: false)
        while !(exhausted.rest && exhausted.others) {
            for takesSubstitution in [true, false] {
                let next = takesSubstitution ? others.next() : rest.next()
                guard let next else {
                    if takesSubstitution { exhausted.others = true } else { exhausted.rest = true }
                    continue
                }
                if seen.insert(next.text).inserted { result.append(next) }
            }
        }
        return result
    }
}
