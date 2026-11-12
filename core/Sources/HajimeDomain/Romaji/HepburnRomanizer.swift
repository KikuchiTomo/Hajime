/// かなをヘボン式のローマ字にする(「とうきょう」→ toukyou，「しんぶん」→ shinbun)．変換マクロの `{reading|romaji}` に使う．
///
/// 名前やファイル名に使えるよう，長音の印は付けず(おう は ou のまま)，「ん」はいつも n にする．
/// 「っ」は次の子音を重ね(っち は tchi)，「ー」は前の母音を重ねる．かなでない文字はそのまま残す
public enum HepburnRomanizer {
    public static func romaji(from text: String) -> String {
        let characters = Array(KanaWidth.hiragana(from: text))
        var result = ""
        var index = 0
        var sokuon = false
        while index < characters.count {
            let character = characters[index]
            if character == "っ" {
                sokuon = true
                index += 1
                continue
            }
            if character == "ー" {
                result += result.last.flatMap { vowels.contains($0) ? String($0) : nil } ?? "-"
                sokuon = false
                index += 1
                continue
            }
            let pair = index + 1 < characters.count ? String(characters[index...index + 1]) : nil
            let (syllable, length): (String?, Int) = if let pair, let spelled = digraphs[pair] { (spelled, 2) } else { (monographs[character], 1) }
            guard let syllable else {
                result.append(character)
                sokuon = false
                index += 1
                continue
            }
            if sokuon, let first = syllable.first, !vowels.contains(first), first != "n" || syllable.count > 1 {
                // ち・ちゃ の前は t を重ねる(ヘボン式)
                result += syllable.hasPrefix("ch") ? "t" : String(first)
            }
            sokuon = false
            result += syllable
            index += length
        }
        return result
    }

    private static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]

    private static let monographs: [Character: String] = {
        let rows: [(String, [String])] = [
            ("あいうえお", ["a", "i", "u", "e", "o"]), ("かきくけこ", ["ka", "ki", "ku", "ke", "ko"]),
            ("さしすせそ", ["sa", "shi", "su", "se", "so"]), ("たちつてと", ["ta", "chi", "tsu", "te", "to"]),
            ("なにぬねの", ["na", "ni", "nu", "ne", "no"]), ("はひふへほ", ["ha", "hi", "fu", "he", "ho"]),
            ("まみむめも", ["ma", "mi", "mu", "me", "mo"]), ("やゆよ", ["ya", "yu", "yo"]),
            ("らりるれろ", ["ra", "ri", "ru", "re", "ro"]), ("わゐゑをん", ["wa", "i", "e", "o", "n"]),
            ("がぎぐげご", ["ga", "gi", "gu", "ge", "go"]), ("ざじずぜぞ", ["za", "ji", "zu", "ze", "zo"]),
            ("だぢづでど", ["da", "ji", "zu", "de", "do"]), ("ばびぶべぼ", ["ba", "bi", "bu", "be", "bo"]),
            ("ぱぴぷぺぽ", ["pa", "pi", "pu", "pe", "po"]), ("ぁぃぅぇぉ", ["a", "i", "u", "e", "o"]),
            ("ゃゅょゎゕゖゔ", ["ya", "yu", "yo", "wa", "ka", "ke", "vu"]),
        ]
        var table: [Character: String] = [:]
        for (kana, spellings) in rows {
            for (character, spelling) in zip(kana, spellings) { table[character] = spelling }
        }
        return table
    }()

    /// 小さい字と組む 2 字の音
    private static let digraphs: [String: String] = {
        var table: [String: String] = [:]
        // き + ゃ → kya のように，子音に y を挟む行
        let palatal: [(Character, String)] = [
            ("き", "ky"), ("に", "ny"), ("ひ", "hy"), ("み", "my"), ("り", "ry"), ("ぎ", "gy"), ("び", "by"), ("ぴ", "py"),
            ("し", "sh"), ("ち", "ch"), ("じ", "j"), ("ぢ", "j"),
        ]
        for (head, consonant) in palatal {
            for (small, vowel) in zip("ゃゅょ", ["a", "u", "o"]) { table[String([head, small])] = consonant + vowel }
        }
        let others: [String: String] = [
            "しぇ": "she", "ちぇ": "che", "じぇ": "je", "いぇ": "ye", "てぃ": "ti", "でぃ": "di", "とぅ": "tu", "どぅ": "du",
            "てゅ": "tyu", "でゅ": "dyu", "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "ふゅ": "fyu",
            "うぃ": "wi", "うぇ": "we", "うぉ": "wo", "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo",
            "つぁ": "tsa", "つぃ": "tsi", "つぇ": "tse", "つぉ": "tso", "くぁ": "kwa", "ぐぁ": "gwa",
        ]
        table.merge(others) { _, new in new }
        return table
    }()
}
