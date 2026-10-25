/// タイプミスを補正するかどうかの判定(R-02)．英単語かどうかは呼び出し側が調べて渡す．
public struct TypoCorrectionRule: Sendable {
    public var level: TypoCorrectionLevel

    public init(level: TypoCorrectionLevel) {
        self.level = level
    }

    /// 補正の対象として調べる並び．ローマ字として読めない並びがあり，英字だけを打ったときに限る
    public func candidateKeys(in composition: Composition) -> String? {
        guard level != .off,
            composition.containsInvalidRomaji,
            let keys = composition.rawKeys,
            keys.count >= DefaultSettings.minimumCorrectionLength,
            keys.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return keys
    }

    /// keys が英単語ならそのまま，綴りの誤りなら近い単語を補正の結果として返す
    public func correction(for keys: String, isWord: Bool, suggestions: [String]) -> String? {
        if isWord { return keys }
        guard level == .standard else { return nil }
        return suggestions.first { suggestion in
            suggestion.count >= DefaultSettings.minimumCorrectionLength
                && suggestion.allSatisfy({ $0.isASCII && $0.isLetter })
                && EditDistance.damerauLevenshtein(keys.lowercased(), suggestion.lowercased())
                    <= DefaultSettings.maximumCorrectionDistance
        }
    }
}

public enum EditDistance {
    /// 隣り合う 2 文字の入れ替えを 1 回と数える編集距離(制限付き Damerau–Levenshtein)
    public static func damerauLevenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { table[i][0] = i }
        for j in 0...b.count { table[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
                }
            }
        }
        return table[a.count][b.count]
    }
}
