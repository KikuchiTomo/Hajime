/// 同音異義語の使い分けの辞書(R-08)．japanese-usage-dictionary(data/usage/usage_dict.txt)の行を読む．
///
/// 行は「読み<タブ>語<タブ>活用<タブ>説明」．説明の中の意味の区切りは「\n」の 2 文字で書かれている．
/// 活用した形(「撮った」)にも当てはまるよう，語の漢字の部分(「撮」)と，送り仮名を除いた読み(「と」)で引く(UsageGuide.Homophone)
public struct UsageDictionary: Sendable, Equatable {
    struct Entry: Sendable, Equatable {
        /// 送り仮名を除いた読み
        var reading: String
        /// 辞書の読み(同じ読みの語の組の見出し)
        var groupReading: String
        var homophone: UsageGuide.Homophone
    }

    /// 読みごとの語(並びはファイルの順)
    private var groups: [String: [UsageGuide.Homophone]] = [:]
    /// 送り仮名を除いた読みの先頭の文字ごとの語．文節の読みの頭で絞ってから当てはめる
    private var entriesByInitial: [Character: [Entry]] = [:]

    public init(text: String) {
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 4, !fields[0].isEmpty, !fields[1].isEmpty else { continue }
            let reading = String(fields[0])
            let meaning = Self.firstMeaning(of: fields[3])
            let homophone = UsageGuide.Homophone(word: String(fields[1]), meaning: meaning.meaning, example: meaning.example)
            // 送り仮名の分だけ読みの後ろを除く(「撮る」「とる」→「と」)．語より読みが短い(当て字など)ときは読みのまま
            let okurigana = homophone.word.count - homophone.stem.count
            let stemReading = reading.count > okurigana ? String(reading.dropLast(okurigana)) : reading
            groups[reading, default: []].append(homophone)
            guard let initial = stemReading.first else { continue }
            entriesByInitial[initial, default: []].append(Entry(reading: stemReading, groupReading: reading, homophone: homophone))
        }
    }

    public var isEmpty: Bool { groups.isEmpty }

    /// 文節の候補 text(読み reading)に当てはまる語の使い分け．同じ読みの語が 1 つだけなら出さない．
    /// 候補が語の漢字の部分で始まり，その後ろ(送り仮名や助詞)が読みの後ろと同じときだけ当てはめる
    /// (「撮った」「とった」は「撮る」に当て，「足跡」「あしあと」は「足」に当てない)
    public func note(for text: String, reading: String) -> HomophoneNote? {
        guard let initial = reading.first, let entries = entriesByInitial[initial] else { return nil }
        let hit = entries.first { entry in
            text.hasPrefix(entry.homophone.stem) && reading.hasPrefix(entry.reading)
                && text.dropFirst(entry.homophone.stem.count) == reading.dropFirst(entry.reading.count)
        }
        guard let hit, let group = groups[hit.groupReading] else { return nil }
        let others = group.filter { $0.word != hit.homophone.word }.map(\.word)
        guard !others.isEmpty else { return nil }
        return HomophoneNote(word: hit.homophone.word, meaning: hit.homophone.meaning, example: hit.homophone.example, others: others)
    }

    /// 説明の最初の意味と，その使い方の例．説明の頭の注記(「〈「取る」とも〉」)と番号(「1. 」)を除き，
    /// 意味のあとのかぎ括弧(「写真を撮る」)を例として分ける．意味の終わりの句点は除く．「※」で始まる補足の行は飛ばす
    static func firstMeaning(of description: Substring) -> (meaning: String, example: String?) {
        for line in description.components(separatedBy: "\\n") {
            var text = Substring(line)
            if text.hasPrefix("〈"), let end = text.firstIndex(of: "〉") { text = text[text.index(after: end)...] }
            let digits = text.prefix { $0.isASCII && $0.isNumber }
            if !digits.isEmpty, text.dropFirst(digits.count).hasPrefix(". ") { text = text.dropFirst(digits.count + 2) }
            guard !text.isEmpty, !text.hasPrefix("※") else { continue }
            var meaning = text
            var example: String?
            // 句点のあとのかぎ括弧だけを例にする(意味の中のかぎ括弧は意味に残す)
            if let open = text.firstIndex(of: "「"), open != text.startIndex, text[text.index(before: open)] == "。",
               let close = Self.closingBracket(in: text[open...]) {
                meaning = text[..<open]
                example = String(text[text.index(after: open)..<close])
            }
            while meaning.last == "。" || meaning.last == " " { meaning = meaning.dropLast() }
            guard !meaning.isEmpty else { continue }
            return (String(meaning), example)
        }
        return (String(description), nil)
    }

    /// text の頭の「に対応する」の位置．中に入れ子のかぎ括弧があっても数えて合わせる
    private static func closingBracket(in text: Substring) -> Substring.Index? {
        var depth = 0
        for index in text.indices {
            switch text[index] {
            case "「": depth += 1
            case "」":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
        }
        return nil
    }
}
