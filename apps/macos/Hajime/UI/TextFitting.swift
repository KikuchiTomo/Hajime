import AppKit

/// 文字を決まった幅に収める．候補ウィンドウの幅には上限があるので(size.candidate.max-width)，長い文の候補は末尾を「…」で省く
enum TextFitting {
    /// 文字の行の箱(書体の ascender から descender まで)の縦の真ん中を midY に合わせて描く．
    /// 日本語の字を代わりの書体で描くと NSString の行の高さが変わり，行の高さで真ん中に置くと字が上下にずれるので，書体の値でベースラインを決める．
    /// ベースラインと x は整数に丸め，文字の輪郭をぼかさない．上下が反転した(isFlipped の)ビューでもそうでないビューでも使える
    static func draw(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, midY: CGFloat) {
        guard let font = attributes[.font] as? NSFont else { return }
        let flipped = NSGraphicsContext.current?.isFlipped ?? true
        let offset = (font.ascender + font.descender) / 2
        let baseline = (flipped ? midY + offset : midY - offset).rounded()
        NSAttributedString(string: text, attributes: attributes)
            .draw(with: NSRect(x: x.rounded(), y: baseline, width: CGFloat.greatestFiniteMagnitude, height: 0), options: [], context: nil)
    }

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

    /// text の頭から width に入る 1 行の字数(少なくとも 1 字)．英数字の語は空白・「-」・「_」のあとで分け，語が 1 行に入らなければ途中で分ける．
    /// 日本語はどの字のあいだでも分けるが，句読点などを行の頭に置かない．
    /// Unicode の名前(SMILING FACE WITH ...)・ショートコード(:face_with_hand_over_mouth:)・見出しの名前を折り返すのに使う．
    /// Windows の候補ウィンドウ(scene::fitting::line_break)と同じ決め方にする
    static func lineBreak(_ text: Substring, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> Int {
        let characters = Array(text)
        guard String(characters).size(withAttributes: attributes).width > width else { return characters.count }
        // characters[..<low] は入る(1 字目は入らなくても置く)．characters[..<high] は入らない
        var low = 1, high = characters.count
        while high - low > 1 {
            let middle = (low + high) / 2
            if String(characters[..<middle]).size(withAttributes: attributes).width <= width { low = middle } else { high = middle }
        }
        return stride(from: low, through: 1, by: -1).first { canBreak(characters, at: $0) } ?? low
    }

    /// 幅 width で折り返した行．行の頭と末尾の空白は除く．maxLines を超える分は，最後の行の末尾を「…」にして省く
    static func wrapped(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat, maxLines: Int = .max) -> [String] {
        var lines: [String] = []
        var rest = Substring(text)
        while !rest.isEmpty, lines.count < maxLines {
            let count = lineBreak(rest, attributes: attributes, width: width)
            if lines.count == maxLines - 1, count < rest.count {
                lines.append(truncated(String(rest), attributes: attributes, width: width))
                break
            }
            lines.append(String(rest.prefix(count)).trimmingCharacters(in: .whitespaces))
            rest = rest.dropFirst(count).drop { $0 == " " }
        }
        return lines
    }

    /// characters[end - 1] と characters[end] のあいだで行を分けてよいか．英数字の語の途中と，行の頭に置かない字の前では分けない
    private static func canBreak(_ characters: [Character], at end: Int) -> Bool {
        guard end < characters.count else { return true }
        let before = characters[end - 1], after = characters[end]
        if lineStartForbidden.contains(after) { return false }
        if before == " " || before == "-" || before == "_" || after == " " { return true }
        return !(before.isASCII && after.isASCII)
    }

    /// 行の頭に置かない字
    private static let lineStartForbidden: Set<Character> = Set("、。，．・：；？！ー…‥）」』】〕〉》,.:;!?)]}")

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
