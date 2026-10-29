/// 送り仮名をどちらの付け方で出すか(内閣告示「送り仮名の付け方」の本則と許容)
public enum OkuriganaStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// 本則を先に出す(行う，表す，現れる)
    case standard
    /// 許容を先に出す(行なう，表わす，現われる)
    case allowed
    /// 変換エンジンの順のまま
    case engine
}

/// 送り仮名の本則と許容の組．両方が候補にあれば，選んだ付け方を先に並べ，片方しか無ければもう片方を足す．
///
/// 組は「送り仮名の付け方」(昭和 48 年内閣告示)で本則と許容が並べて示されている語から，よく使う動詞を選んで書いた．
/// 活用で語尾が変わるので，語幹と，そのあとに続く語尾の文字(endings)で照らし合わせる
public enum Okurigana {
    struct Pair {
        var standardStem: String
        var allowedStem: String
        var endings: String
    }

    static let pairs: [Pair] = [
        Pair(standardStem: "行", allowedStem: "行な", endings: "わいうえおっ"),
        Pair(standardStem: "表", allowedStem: "表わ", endings: "さしすせそ"),
        Pair(standardStem: "著", allowedStem: "著わ", endings: "さしすせそ"),
        Pair(standardStem: "現", allowedStem: "現わ", endings: "れ"),
        Pair(standardStem: "断", allowedStem: "断わ", endings: "らりるれろっ"),
        Pair(standardStem: "賜", allowedStem: "賜わ", endings: "らりるれろっ"),
        Pair(standardStem: "浮か", allowedStem: "浮", endings: "ばびぶべぼん"),
        Pair(standardStem: "生ま", allowedStem: "生", endings: "れ"),
        Pair(standardStem: "押さ", allowedStem: "押", endings: "え"),
        Pair(standardStem: "捕ら", allowedStem: "捕", endings: "え"),
        Pair(standardStem: "積も", allowedStem: "積", endings: "らりるれろっ"),
        Pair(standardStem: "聞こ", allowedStem: "聞", endings: "え"),
        Pair(standardStem: "起こ", allowedStem: "起", endings: "らりるれろっ"),
        Pair(standardStem: "落と", allowedStem: "落", endings: "さしすせそ"),
        Pair(standardStem: "暮ら", allowedStem: "暮", endings: "さしすせそ"),
        Pair(standardStem: "当た", allowedStem: "当", endings: "らりるれろっ"),
        Pair(standardStem: "終わ", allowedStem: "終", endings: "らりるれろっ"),
        Pair(standardStem: "変わ", allowedStem: "変", endings: "らりるれろっ"),
    ]

    /// text の中の，もう一方の付け方の語を style の付け方に書き換える．書き換える語が無ければ nil．
    ///
    /// 語幹の前が漢字なら熟語の一部(「代表し」の「表し」)なので書き換えない．
    /// 許容へ書き換えるとき，「行っ」は「行った(いった)」と区別できないので書き換えない
    public static func rewrite(_ text: String, to style: OkuriganaStyle) -> String? {
        guard style != .engine else { return nil }
        var characters = Array(text)
        var changed = false
        for pair in pairs {
            // 候補のほとんどは語幹を含まないので，含まない組は語尾ごとに照らし合わせない(分岐図を出すたびに候補の数だけ呼ぶため)
            let fromStem = style == .standard ? pair.allowedStem : pair.standardStem
            guard (changed ? String(characters) : text).contains(fromStem) else { continue }
            for ending in pair.endings {
                if style == .allowed, pair.standardStem == "行", ending == "っ" { continue }
                let (from, to) = style == .standard
                    ? (Array(pair.allowedStem + String(ending)), Array(pair.standardStem + String(ending)))
                    : (Array(pair.standardStem + String(ending)), Array(pair.allowedStem + String(ending)))
                var index = 0
                while index + from.count <= characters.count {
                    let matches = characters[index..<(index + from.count)].elementsEqual(from)
                    let afterKanji = index > 0 && isKanji(characters[index - 1])
                    if matches, !afterKanji {
                        characters.replaceSubrange(index..<(index + from.count), with: to)
                        index += to.count
                        changed = true
                    } else {
                        index += 1
                    }
                }
            }
        }
        return changed ? String(characters) : nil
    }

    private static func isKanji(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) || $0 == "々" }
    }

    /// 候補を，選んだ付け方の語が先に来るように並べ替える．もう一方しか無い候補には，選んだ付け方の候補を前に足す
    public static func reorder(_ candidates: [Candidate], style: OkuriganaStyle) -> [Candidate] {
        guard style != .engine else { return candidates }
        var result: [Candidate] = []
        var seen = Set<String>()
        for candidate in candidates {
            if let preferred = rewrite(candidate.text, to: style), !seen.contains(preferred) {
                // 選んだ付け方の候補が後ろにあればそれを，無ければ書き換えた候補を，この位置に置く
                let existing = candidates.first { $0.text == preferred }
                result.append(existing ?? Candidate(text: preferred, readingCount: candidate.readingCount, origin: .combined))
                seen.insert(preferred)
            }
            if seen.insert(candidate.text).inserted { result.append(candidate) }
        }
        return result
    }
}
