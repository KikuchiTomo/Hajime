/// 長い文の文節を，分岐図に 1 つずつ出すまとまりに分ける．
/// 文節の数が上限までなら分けない．超えるときは，上限までの文節を 1 つのまとまりにし，
/// 後ろ半分に句点や読点で終わる文節があれば，そこで切る(文の切れ目とまとまりの切れ目をそろえる)
public enum SegmentGrouping {
    /// texts は文節ごとの今の文字．size は 1 つのまとまりの文節の数の上限(0 以下なら分けない)
    public static func groups(texts: [String], size: Int) -> [Range<Int>] {
        guard size > 0, texts.count > size else { return texts.isEmpty ? [] : [0..<texts.count] }
        var result: [Range<Int>] = []
        var start = 0
        while texts.count - start > size {
            let limit = start + size
            // 切れ目を探すのは後ろ半分だけ(短いまとまりを作りすぎない)
            let earliest = start + (size + 1) / 2
            let candidates = (earliest...limit).reversed()
            let end = candidates.first { ends(texts[$0 - 1], with: sentenceEnds) } ?? candidates.first { ends(texts[$0 - 1], with: clauseEnds) } ?? limit
            result.append(start..<end)
            start = end
        }
        result.append(start..<texts.count)
        return result
    }

    /// index の文節が入っているまとまり
    public static func group(containing index: Int, texts: [String], size: Int) -> Range<Int>? {
        groups(texts: texts, size: size).first { $0.contains(index) }
    }

    private static let sentenceEnds: Set<Character> = ["。", "．", "！", "？", "!", "?"]
    private static let clauseEnds: Set<Character> = ["、", "，", ",", "；", "："]

    private static func ends(_ text: String, with marks: Set<Character>) -> Bool {
        text.last.map(marks.contains) ?? false
    }
}
