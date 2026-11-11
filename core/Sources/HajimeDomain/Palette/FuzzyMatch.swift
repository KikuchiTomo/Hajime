/// 短い名前や読みに向けたあいまいな照合．打った文字が順に含まれていれば当たりとし，
/// 先頭や語の頭で当たるほど，また文字が続いて当たるほど高い点にする．あいだに飛ばした文字の分は点を引く．
///
/// 点の付け方は，飛ばした文字の数に比例して引く局所的な並べ合わせ(動的計画法)で求める．値は DefaultSettings.fuzzyMatchScores
public enum FuzzyMatch {
    /// 当たり方．後ろほど強い
    public enum Kind: Int, Sendable, Comparable {
        /// 飛び飛びに含む(「tsup」が「thumbsup」に)
        case scattered
        /// 途中に続けて含む
        case substring
        /// 語の頭から続けて含む(「joy」が「tears of joy」に)
        case wordPrefix
        /// 頭から続けて含む
        case prefix
        /// 同じ
        case exact

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Match: Sendable, Equatable {
        public var kind: Kind
        public var score: Int

        public init(kind: Kind, score: Int) {
            self.kind = kind
            self.score = score
        }
    }

    /// 照らし合わせる前の形にそろえる．英字は小文字に，カタカナはひらがなにする
    public static func normalized(_ text: String) -> [Unicode.Scalar] {
        Array(KanaWidth.hiragana(from: text.lowercased()).unicodeScalars)
    }

    /// pattern が text に当たるか．どちらも normalized でそろえたもの．当たらなければ nil
    public static func match(_ pattern: [Unicode.Scalar], in text: [Unicode.Scalar]) -> Match? {
        guard !pattern.isEmpty, pattern.count <= text.count, let score = alignmentScore(pattern, in: text) else { return nil }
        if pattern.count == text.count {
            return Match(kind: pattern == text ? .exact : .scattered, score: score)
        }
        if text.starts(with: pattern) { return Match(kind: .prefix, score: score) }
        var contains = false
        for start in 1...(text.count - pattern.count) where text[start] == pattern[0] && text[start..<(start + pattern.count)].elementsEqual(pattern) {
            if isBoundary(text[start - 1]) { return Match(kind: .wordPrefix, score: score) }
            contains = true
        }
        return Match(kind: contains ? .substring : .scattered, score: score)
    }

    /// 語の区切りとみなす文字
    private static func isBoundary(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isWhitespace || "-_:./(),&'+".unicodeScalars.contains(scalar)
    }

    /// その位置で当たったときに足す点．文字列の頭と空白のあとは高く，区切りの記号のあとはその次に高くする
    private static func bonus(at index: Int, in text: [Unicode.Scalar]) -> Int {
        let scores = DefaultSettings.fuzzyMatchScores
        guard index > 0 else { return scores.boundaryWhite }
        let previous = text[index - 1]
        if previous.properties.isWhitespace { return scores.boundaryWhite }
        return isBoundary(previous) ? scores.boundary : 0
    }

    /// pattern の文字を順に text に当てたときのいちばん高い点．順に含まなければ nil
    private static func alignmentScore(_ pattern: [Unicode.Scalar], in text: [Unicode.Scalar]) -> Int? {
        // 順に含むかを先に確かめる(含まないものに表を作らない)
        var next = 0
        for scalar in text where next < pattern.count && scalar == pattern[next] {
            next += 1
        }
        guard next == pattern.count else { return nil }

        let scores = DefaultSettings.fuzzyMatchScores
        let unmatched = Int.min / 4
        let bonuses = text.indices.map { bonus(at: $0, in: text) }
        // previous[j]: パターンの前の文字を text[j] で当てたときの最高点．chunk[j]: そこで続いている当たりの頭の加点
        var previous = [Int](repeating: unmatched, count: text.count)
        var chunk = [Int](repeating: 0, count: text.count)
        for j in text.indices where text[j] == pattern[0] {
            previous[j] = scores.match + bonuses[j] * scores.firstCharacterMultiplier
            chunk[j] = bonuses[j]
        }
        for i in 1..<pattern.count {
            var current = [Int](repeating: unmatched, count: text.count)
            var currentChunk = [Int](repeating: 0, count: text.count)
            // gapped: 2 文字以上前(あいだに飛ばした文字がある)で前の文字を当てたときの最高点から，飛ばした分を引いたもの
            var gapped = unmatched
            for j in 1..<text.count {
                if j >= 2 {
                    gapped = max(gapped + scores.gapExtension, previous[j - 2] == unmatched ? unmatched : previous[j - 2] + scores.gapStart)
                }
                guard j >= i, text[j] == pattern[i] else { continue }
                if previous[j - 1] > unmatched {
                    // 続けて当たった．続きの頭の加点と続いた加点の大きい方を足す
                    let bonus = max(chunk[j - 1], bonuses[j], scores.consecutive)
                    current[j] = previous[j - 1] + scores.match + bonus
                    currentChunk[j] = chunk[j - 1]
                }
                if gapped > unmatched, gapped + scores.match + bonuses[j] > current[j] {
                    current[j] = gapped + scores.match + bonuses[j]
                    currentChunk[j] = bonuses[j]
                }
            }
            previous = current
            chunk = currentChunk
        }
        let best = previous.max() ?? unmatched
        return best > unmatched ? best : nil
    }
}
