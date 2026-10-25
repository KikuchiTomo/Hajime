extension RomajiTable {
    /// 標準のローマ字表．macOS の日本語入力と Google 日本語入力でよく使われる綴りをまとめた．
    /// 促音(子音の重ね打ち)と「n」「nn」の扱いは Composition が行うので，ここには書かない．
    public static let standard = RomajiTable(entries: makeStandardEntries())

    private static func makeStandardEntries() -> [String: String] {
        var table: [String: String] = [:]
        let vowels = ["a", "i", "u", "e", "o"]

        // 子音 + 母音．空の文字列は「その段に字が無い」ことを表す
        let rows: [(String, [String])] = [
            ("", ["あ", "い", "う", "え", "お"]),
            ("k", ["か", "き", "く", "け", "こ"]),
            ("s", ["さ", "し", "す", "せ", "そ"]),
            ("t", ["た", "ち", "つ", "て", "と"]),
            ("n", ["な", "に", "ぬ", "ね", "の"]),
            ("h", ["は", "ひ", "ふ", "へ", "ほ"]),
            ("m", ["ま", "み", "む", "め", "も"]),
            ("y", ["や", "い", "ゆ", "いぇ", "よ"]),
            ("r", ["ら", "り", "る", "れ", "ろ"]),
            ("w", ["わ", "うぃ", "う", "うぇ", "を"]),
            ("g", ["が", "ぎ", "ぐ", "げ", "ご"]),
            ("z", ["ざ", "じ", "ず", "ぜ", "ぞ"]),
            ("d", ["だ", "ぢ", "づ", "で", "ど"]),
            ("b", ["ば", "び", "ぶ", "べ", "ぼ"]),
            ("p", ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ"]),
            ("f", ["ふぁ", "ふぃ", "ふ", "ふぇ", "ふぉ"]),
            ("v", ["ゔぁ", "ゔぃ", "ゔ", "ゔぇ", "ゔぉ"]),
            ("j", ["じゃ", "じ", "じゅ", "じぇ", "じょ"]),
            ("l", ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ"]),
            ("x", ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ"]),
            ("q", ["くぁ", "くぃ", "く", "くぇ", "くぉ"]),
            ("c", ["か", "し", "く", "せ", "こ"]),
        ]
        for (consonant, kana) in rows {
            for (vowel, letter) in zip(vowels, kana) where !letter.isEmpty {
                table[consonant + vowel] = letter
            }
        }

        // 拗音．「ky」+ 母音 → き + 小さいや行
        let smallY = ["ゃ", "ぃ", "ゅ", "ぇ", "ょ"]
        let youon: [(String, String)] = [
            ("ky", "き"), ("sy", "し"), ("ty", "ち"), ("ny", "に"), ("hy", "ひ"),
            ("my", "み"), ("ry", "り"), ("gy", "ぎ"), ("zy", "じ"), ("dy", "ぢ"),
            ("by", "び"), ("py", "ぴ"), ("cy", "ち"), ("fy", "ふ"), ("vy", "ゔ"),
            ("jy", "じ"),
        ]
        for (prefix, head) in youon {
            for (vowel, small) in zip(vowels, smallY) {
                table[prefix + vowel] = head + small
            }
        }

        // し・ち・つ・て・で などの別の綴り
        let extra: [String: String] = [
            "sha": "しゃ", "shi": "し", "shu": "しゅ", "she": "しぇ", "sho": "しょ",
            "cha": "ちゃ", "chi": "ち", "chu": "ちゅ", "che": "ちぇ", "cho": "ちょ",
            "tsa": "つぁ", "tsi": "つぃ", "tsu": "つ", "tse": "つぇ", "tso": "つぉ",
            "tha": "てゃ", "thi": "てぃ", "thu": "てゅ", "the": "てぇ", "tho": "てょ",
            "dha": "でゃ", "dhi": "でぃ", "dhu": "でゅ", "dhe": "でぇ", "dho": "でょ",
            "twa": "とぁ", "twi": "とぃ", "twu": "とぅ", "twe": "とぇ", "two": "とぉ",
            "dwa": "どぁ", "dwi": "どぃ", "dwu": "どぅ", "dwe": "どぇ", "dwo": "どぉ",
            "wha": "うぁ", "whi": "うぃ", "whu": "う", "whe": "うぇ", "who": "うぉ",
            "kwa": "くぁ", "gwa": "ぐぁ",
            "si": "し", "ti": "ち", "tu": "つ", "hu": "ふ", "zi": "じ", "di": "ぢ", "du": "づ",
            "ji": "じ", "fu": "ふ",
            "xya": "ゃ", "xyu": "ゅ", "xyo": "ょ", "lya": "ゃ", "lyu": "ゅ", "lyo": "ょ",
            "xtu": "っ", "ltu": "っ", "xtsu": "っ", "ltsu": "っ",
            "xwa": "ゎ", "lwa": "ゎ", "xka": "ゕ", "xke": "ゖ",
            "n'": "ん", "xn": "ん",
            "-": "ー",
        ]
        table.merge(extra) { _, new in new }
        return table
    }
}
