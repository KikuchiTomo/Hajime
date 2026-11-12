import AppKit

/// 文字を決まった幅に収める．候補ウィンドウの幅には上限があるので(size.candidate.max-width)，長い文の候補は末尾を「…」で省く
enum TextFitting {
    /// 幅に収まるよう末尾を「…」で省く．省く位置は二分探索で決め，測る回数を文字数の対数に抑える(長い文でも打鍵を遅らせない)
    static func truncated(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> String {
        guard text.size(withAttributes: attributes).width > width else { return text }
        let characters = Array(text)
        var low = 0, high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if (String(characters[..<middle]) + "…").size(withAttributes: attributes).width <= width {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low == 0 ? "" : String(characters[..<low]) + "…"
    }

    /// 幅に収まるよう省く．keeping より後ろの字(ほかの候補と違うところ)をなるべく見せるため，先に頭を「…」で省き，
    /// それでも入らなければ末尾も省く．keeping が 0 なら末尾だけを省く
    static func truncated(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat, keeping index: Int) -> String {
        guard text.size(withAttributes: attributes).width > width else { return text }
        let characters = Array(text)
        let keep = min(index, characters.count)
        guard keep > 0 else { return truncated(text, attributes: attributes, width: width) }
        func fits(_ start: Int) -> Bool { ("…" + String(characters[start...])).size(withAttributes: attributes).width <= width }
        guard fits(keep) else { return truncated("…" + String(characters[keep...]), attributes: attributes, width: width) }
        // 頭を省く字数をなるべく少なくする(start が大きいほど短い)
        var low = 1, high = keep
        while low < high {
            let middle = (low + high) / 2
            if fits(middle) { high = middle } else { low = middle + 1 }
        }
        return "…" + String(characters[low...])
    }

    /// ほかの候補と頭から同じ字数(いちばん長く一致する候補との)．一覧で，候補ごとに違うところを見せるのに使う
    static func sharedPrefixLength(of text: String, among others: [String]) -> Int {
        let characters = Array(text)
        var longest = 0
        for other in others where other != text {
            var count = 0
            for (a, b) in zip(characters, other) {
                guard a == b else { break }
                count += 1
            }
            longest = max(longest, count)
        }
        return longest
    }
}
