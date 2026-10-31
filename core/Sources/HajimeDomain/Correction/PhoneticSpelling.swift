/// 英単語を発音どおりに綴った誤り(「foto」→ photo，「fone」→ phone，「kat」→ cat，「grafik」→ graphic)の，正しい綴りの候補．
///
/// 綴りの誤りの補正(英単語の辞書の候補)は 1〜2 文字の打ち間違いを直すもので，「f」と「ph」のように
/// 音が同じで綴りの長さが変わる誤りは拾いにくい．音の同じ綴りの組を置き換えて，辞書にある綴りを探す(辞書で確かめるのは呼び出し側)
public enum PhoneticSpelling {
    /// 音が同じか近い綴りの組(左を右に置き換える)
    static let rules: [(from: String, to: String)] = [
        ("f", "ph"), ("ph", "f"), ("k", "c"), ("c", "k"), ("k", "ck"), ("ck", "k"), ("k", "ch"), ("s", "c"), ("c", "s"),
        ("z", "s"), ("s", "z"), ("i", "y"), ("y", "i"), ("u", "oo"), ("oo", "u"), ("ks", "x"), ("x", "ks"), ("kw", "qu"),
        ("j", "g"), ("g", "j"), ("sh", "ti"), ("shon", "tion"), ("er", "re"), ("re", "er"), ("ee", "ea"), ("ea", "ee"),
        ("o", "ou"), ("ai", "ay"), ("w", "wh"), ("r", "wr"), ("n", "kn"), ("t", "th"), ("d", "dd"), ("l", "ll"), ("s", "ss"),
    ]

    /// 置き換えを最大 depth 回したつづり．元のつづりと重なりは除き，置き換えの少ない順に並べる．
    /// 多くなりすぎないよう DefaultSettings.maximumPhoneticVariants まで
    public static func variants(of word: String, depth: Int = 2) -> [String] {
        let lowered = word.lowercased()
        guard lowered.count >= DefaultSettings.minimumPhoneticWordLength, lowered.count <= DefaultSettings.maximumPhoneticWordLength,
            lowered.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
        var seen: Set<String> = [lowered]
        var frontier = [lowered]
        var result: [String] = []
        for _ in 0..<depth {
            var next: [String] = []
            for spelling in frontier {
                for variant in replacements(of: spelling) where seen.insert(variant).inserted {
                    next.append(variant)
                    result.append(variant)
                    if result.count >= DefaultSettings.maximumPhoneticVariants { return result }
                }
            }
            frontier = next
        }
        return result
    }

    /// 1 か所だけ置き換えたつづり
    static func replacements(of spelling: String) -> [String] {
        let characters = Array(spelling)
        var result: [String] = []
        for (from, to) in rules {
            let pattern = Array(from)
            var index = 0
            while index + pattern.count <= characters.count {
                if Array(characters[index..<(index + pattern.count)]) == pattern {
                    result.append(String(characters[..<index]) + to + String(characters[(index + pattern.count)...]))
                }
                index += 1
            }
        }
        return result
    }
}
