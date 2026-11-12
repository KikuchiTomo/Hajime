/// 読みが数字だけのときに候補に出す，数字の別の書き方(丸数字・括弧付き・漢数字・ローマ数字)．
///
/// 読みは半角か全角の数字だけ．0 で始まる 2 桁以上(電話番号や郵便番号の一部)・小数・符号の付いた数は書き換えない．
/// 書き方ごとに書ける範囲があり，範囲の外の数ではその書き方を出さない(丸数字は 0〜50 など)
public enum NumberForms {
    /// 書き方の種類．設定で種類ごとに出すかを選ぶ
    public enum Kind: String, Sendable, CaseIterable {
        /// 白丸(⓪〜㊿)と黒丸(⓿〜⓴)
        case circled
        /// 括弧付き(⑴〜⒇)とピリオド付き(⒈〜⒛)
        case parenthesized
        /// 位取り(二〇二六)・位付き(二千二十六)・大字(弐千弐拾六)
        case kanji
        /// ローマ数字(Ⅰ〜Ⅻ，ⅩⅢ など．大文字と小文字)
        case roman
    }

    /// 読みを書き換えた候補．kinds の順(Kind.allCases の順)に並べる．書き換えられなければ空
    public static func candidates(for reading: String, kinds: Set<Kind>) -> [String] {
        guard !kinds.isEmpty, let digits = digits(of: reading) else { return [] }
        var result: [String] = []
        for kind in Kind.allCases where kinds.contains(kind) {
            for text in forms(of: digits, kind: kind) where !result.contains(text) {
                result.append(text)
            }
        }
        return result
    }

    /// 読みの数字(0〜9 の値の並び)．数字だけでない読み・0 で始まる 2 桁以上・長すぎる読みは nil
    static func digits(of reading: String) -> [Int]? {
        var digits: [Int] = []
        for scalar in reading.unicodeScalars {
            switch scalar.value {
            case 0x30...0x39: digits.append(Int(scalar.value - 0x30))
            case 0xFF10...0xFF19: digits.append(Int(scalar.value - 0xFF10))
            default: return nil
            }
        }
        guard !digits.isEmpty, digits.count <= DefaultSettings.maximumNumberFormDigits, digits.count == 1 || digits[0] != 0 else { return nil }
        return digits
    }

    private static func forms(of digits: [Int], kind: Kind) -> [String] {
        let value = digits.reduce(0) { $0 * 10 + $1 }
        switch kind {
        case .circled: return [whiteCircled(value), blackCircled(value)].compactMap { $0 }
        case .parenthesized: return [parenthesized(value), withFullStop(value)].compactMap { $0 }
        case .kanji: return [positional(digits), withUnits(digits, numerals: plainNumerals), formal(digits)].compactMap { $0 }
        case .roman: return [roman(value, uppercase: true), roman(value, uppercase: false)].compactMap { $0 }
        }
    }

    // MARK: - 丸数字と括弧付き

    /// ⓪ U+24EA，①〜⑳ U+2460〜，㉑〜㉟ U+3251〜，㊱〜㊿ U+32B1〜
    static func whiteCircled(_ value: Int) -> String? {
        switch value {
        case 0: scalar(0x24EA)
        case 1...20: scalar(0x2460 + value - 1)
        case 21...35: scalar(0x3251 + value - 21)
        case 36...50: scalar(0x32B1 + value - 36)
        default: nil
        }
    }

    /// ⓿ U+24FF，❶〜❿ U+2776〜，⓫〜⓴ U+24EB〜
    static func blackCircled(_ value: Int) -> String? {
        switch value {
        case 0: scalar(0x24FF)
        case 1...10: scalar(0x2776 + value - 1)
        case 11...20: scalar(0x24EB + value - 11)
        default: nil
        }
    }

    /// ⑴〜⒇ U+2474〜
    static func parenthesized(_ value: Int) -> String? {
        (1...20).contains(value) ? scalar(0x2474 + value - 1) : nil
    }

    /// ⒈〜⒛ U+2488〜
    static func withFullStop(_ value: Int) -> String? {
        (1...20).contains(value) ? scalar(0x2488 + value - 1) : nil
    }

    // MARK: - 漢数字

    static let plainNumerals: [Character] = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
    /// 大字で書き換える数字(壱・弐・参)．ほかの数字はふつうの漢数字のまま書く
    private static let formalNumerals: [Character] = ["〇", "壱", "弐", "参", "四", "五", "六", "七", "八", "九"]
    /// 4 桁の中の位(千・百・十)と，4 桁ごとの位(万・億・兆)
    private static let smallUnits: [Character?] = ["千", "百", "十", nil]
    private static let largeUnits: [Character?] = [nil, "万", "億", "兆"]

    /// 位取りの漢数字(2026 → 二〇二六)．1 桁の数は位付きと同じなので出さない
    static func positional(_ digits: [Int]) -> String? {
        guard digits.count > 1 else { return nil }
        return String(digits.map { plainNumerals[$0] })
    }

    /// 位付きの漢数字(2026 → 二千二十六，10000 → 一万，11000 → 一万一千)．十・百の前と，先頭の千の前の「一」は書かない
    static func withUnits(_ digits: [Int], numerals: [Character], tenUnit: Character = "十", writesLeadingOne: Bool = false) -> String? {
        if digits == [0] { return String(numerals[0]) }
        var text = ""
        let groups = stride(from: digits.count, to: 0, by: -4).map { Array(digits[max(0, $0 - 4)..<$0]) }.reversed()
        for (offset, group) in groups.enumerated() {
            let groupIndex = groups.count - 1 - offset
            guard group.contains(where: { $0 != 0 }) else { continue }
            let padded = Array(repeating: 0, count: 4 - group.count) + group
            for (position, digit) in padded.enumerated() where digit != 0 {
                let unit = position == 2 ? tenUnit : smallUnits[position]
                let omitsOne = digit == 1 && unit != nil && !writesLeadingOne && (position != 0 || text.isEmpty)
                if !omitsOne { text.append(numerals[digit]) }
                if let unit { text.append(unit) }
            }
            if let unit = largeUnits[groupIndex] { text.append(unit) }
        }
        return text
    }

    /// 大字(2026 → 弐千弐拾六，10 → 壱拾)．書き換えを防ぐため，位の前の 1 も「壱」と書く．0 は書かない
    static func formal(_ digits: [Int]) -> String? {
        guard digits != [0] else { return nil }
        return withUnits(digits, numerals: formalNumerals, tenUnit: "拾", writesLeadingOne: true)
    }

    // MARK: - ローマ数字

    /// 1〜12 は 1 文字のローマ数字(Ⅰ U+2160〜，ⅰ U+2170〜)．13〜3999 は十の位から上を Ⅹ Ⅼ Ⅽ Ⅾ Ⅿ の文字で書き，
    /// 一の位を 1 文字のローマ数字にする(13 → ⅩⅢ，2026 → ⅯⅯⅩⅩⅥ)
    static func roman(_ value: Int, uppercase: Bool) -> String? {
        let base = uppercase ? 0x2160 : 0x2170
        switch value {
        case 1...12:
            return scalar(base + value - 1)
        case 13...3999:
            var rest = value - value % 10
            var text = ""
            for symbol in romanSymbols {
                while rest >= symbol.value {
                    for offset in symbol.offsets { text += scalar(base + offset) ?? "" }
                    rest -= symbol.value
                }
            }
            if value % 10 != 0 { text += scalar(base + value % 10 - 1) ?? "" }
            return text
        default:
            return nil
        }
    }

    /// 十の位から上を書く文字の並び．offsets は Ⅰ(U+2160)からの差(Ⅹ 9，Ⅼ 12，Ⅽ 13，Ⅾ 14，Ⅿ 15)
    private static let romanSymbols: [(value: Int, offsets: [Int])] = [
        (1000, [15]), (900, [13, 15]), (500, [14]), (400, [13, 14]), (100, [13]), (90, [9, 13]),
        (50, [12]), (40, [9, 12]), (10, [9]),
    ]

    private static func scalar(_ value: Int) -> String? {
        Unicode.Scalar(UInt32(value)).map { String(Character($0)) }
    }
}
