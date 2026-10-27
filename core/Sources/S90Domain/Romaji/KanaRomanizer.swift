/// かなの読みを，打てばその読みになるローマ字のキーの並びに直す(ローマ字表を逆に引く)．
///
/// かなの単位で直した読み(KanaEditSearch)を，キーの単位で直した読みと同じ道筋(キーの並びから組み立て直す)で扱うために使う．
/// かなごとに，その字になるいちばん短い綴りを使う(同じ長さなら x・l で始まらないもの，そのあとは辞書順)．
/// 「ん」は「nn」，「っ」は次の字の子音を重ねる(重ねられなければ「xtu」)．読み戻して元の読みにならなければ nil
public enum KanaRomanizer {
    /// 標準のローマ字表で直す(キーの訂正 KeyEditSearch と同じ表)
    public static func keys(for reading: String) -> String? {
        let spellings = standardSpellings
        let longest = standardLongest
        let characters = Array(reading)
        var pieces: [String] = []
        var index = 0
        var pendingSokuon = false
        while index < characters.count {
            if characters[index] == "っ" {
                // 「っ」が続くときは前のものを xtu にする
                if pendingSokuon { pieces.append("xtu") }
                pendingSokuon = true
                index += 1
                continue
            }
            if characters[index] == "ん" {
                if pendingSokuon { pieces.append("xtu") }
                pendingSokuon = false
                pieces.append("nn")
                index += 1
                continue
            }
            guard let (length, spelling) = (1...min(longest, characters.count - index)).reversed().lazy
                .compactMap({ length in spellings[String(characters[index..<(index + length)])].map { (length, $0) } }).first
            else { return nil }
            if pendingSokuon {
                // 子音で始まる綴りならその子音を重ねる(か → kka)．母音・n で始まる綴りは重ねられないので xtu
                if let first = spelling.first, !"aiueon-".contains(first) {
                    pieces.append(String(first))
                } else {
                    pieces.append("xtu")
                }
                pendingSokuon = false
            }
            pieces.append(spelling)
            index += length
        }
        if pendingSokuon { pieces.append("xtu") }
        let keys = pieces.joined()
        // 打って同じ読みになるか確かめる(綴りの組み合わせで別の読みになるもの: n のあとに母音・y が続くなど)
        var composition = Composition(table: .standard)
        for key in keys { composition.insertRomaji(key) }
        return composition.conversionReading == reading ? keys : nil
    }

    /// かな 1 字のいちばん短い綴り．「っ」「ん」「ー」も綴りにする(音の近さを測るのに使う)．打てない字は nil
    public static func spelling(of kana: Character) -> String? {
        switch kana {
        case "っ": "xtu"
        case "ん": "nn"
        default: standardSpellings[String(kana)]
        }
    }

    /// 標準のローマ字表で 1 字になるかな(音の近さで置き換える先)
    public static let singleKana: [Character] = standardSpellings.keys.filter { $0.count == 1 }.map { Character($0) }.sorted() + ["っ", "ん"]

    private static let standardSpellings = spellings(of: .standard)
    private static let standardLongest = standardSpellings.keys.map(\.count).max() ?? 1

    /// かな → いちばん短い綴り．記号を出す綴り(z + 記号)は使わない
    private static func spellings(of table: RomajiTable) -> [String: String] {
        var result: [String: String] = [:]
        for (keys, kana) in table.entries where keys.allSatisfy({ $0.isLetter || $0 == "-" }) && kana.allSatisfy(isKana) {
            if let existing = result[kana], !isBetter(keys, than: existing) { continue }
            result[kana] = keys
        }
        return result
    }

    /// ひらがなと長音(記号を出す綴りは使わない)
    private static func isKana(_ character: Character) -> Bool {
        character == "ー" || character.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) }
    }

    private static func isBetter(_ keys: String, than other: String) -> Bool {
        if keys.count != other.count { return keys.count < other.count }
        let isSmall = { (spelling: String) in spelling.hasPrefix("x") || spelling.hasPrefix("l") }
        if isSmall(keys) != isSmall(other) { return !isSmall(keys) }
        return keys < other
    }
}
