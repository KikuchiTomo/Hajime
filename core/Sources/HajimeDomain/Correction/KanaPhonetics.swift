/// かな 1 字どうしの音の近さ．かなをローマ字の綴り(KanaRomanizer)で子音と母音に分け，違いを足す．
///
/// 子音が違えば 1，母音が違えば 1．ただし音として近い違いは 0.5 にする:
/// 半母音(y・w)があるかないかだけの違い(ゆ yu と い i，や ya と あ a)，拗音かどうかだけの違い(き ki と きゃ kya)，
/// 清音と濁音・半濁音の違い(か と が，は と ば・ぱ)．ふ(f)は は行(h)と同じ子音とみなす．
/// 特殊拍(っ・ん・ー)は母音を持たないものとして扱う
public enum KanaPhonetics {
    public static func distance(_ a: Character, _ b: Character) -> Double? {
        guard a != b else { return 0 }
        guard let left = parts(of: a), let right = parts(of: b) else { return nil }
        return consonantDistance(left.consonant, right.consonant) + (left.vowel == right.vowel ? 0 : 1)
    }

    private static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]

    private static func parts(of kana: Character) -> (consonant: String, vowel: Character?)? {
        switch kana {
        case "っ": return ("q", nil)
        case "ん": return ("N", nil)
        case "ー": return ("H", nil)
        default: break
        }
        guard let spelling = KanaRomanizer.spelling(of: kana), let last = spelling.last else { return nil }
        guard vowels.contains(last) else { return (spelling, nil) }
        return (normalized(String(spelling.dropLast())), last)
    }

    /// 同じ子音を表す綴りをそろえる(ふ f → h)
    private static func normalized(_ consonant: String) -> String {
        consonant == "f" ? "h" : consonant
    }

    private static let voicing: [String: String] = ["g": "k", "z": "s", "j": "s", "d": "t", "b": "h", "p": "h", "v": "h"]

    private static func consonantDistance(_ a: String, _ b: String) -> Double {
        guard a != b else { return 0 }
        // 半母音があるかないか(y・w と無し)，拗音かどうか(k と ky)
        let glides: Set<String> = ["y", "w"]
        if (a.isEmpty && glides.contains(b)) || (b.isEmpty && glides.contains(a)) { return 0.5 }
        if a + "y" == b || b + "y" == a { return 0.5 }
        // 清音と濁音・半濁音
        if (voicing[a] ?? a) == (voicing[b] ?? b) { return 0.5 }
        return 1
    }
}
