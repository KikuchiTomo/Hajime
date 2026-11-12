import Foundation

/// 入れるときに中身を決める語(TextTemplate)の値にかける変換．`{text|upper}` のように `|` のあとに名前を書き，左から順にかける
public enum TextFilter: String, Sendable, CaseIterable {
    /// 英字を大文字・小文字にする．先頭の 1 文字だけ大文字にする
    case upper, lower, capitalize
    /// ひらがなとカタカナ
    case katakana, hiragana
    /// 半角カタカナ・全角英数・半角英数
    case halfwidth, fullwidth, ascii
    /// かなをヘボン式のローマ字にする(HepburnRomanizer)
    case romaji
    /// 英語の語の書き方(snake_case・camelCase・PascalCase・kebab-case)
    case snake, camel, pascal, kebab
    /// URL に入れられる形(UTF-8 のパーセントエンコード)
    case url
    /// 文字数
    case length
    /// 数字の並びを漢数字(2026 → 二千二十六)・1 字ずつの漢数字(二〇二六)・大字(弐千弐拾六)・3 桁区切り(1,234)・丸数字(⑫)にする(NumberForms)．
    /// 書けない数(大きすぎる数・丸数字の 51 以上など)と，小数点のあとの数字はそのまま
    case kansuji, kanjidigits, daiji, comma, circled
    /// HTML に入れられる形(& < > " ' を文字参照に)
    case html
    /// UTF-8 の Base64
    case base64

    public func apply(to value: String) -> String {
        switch self {
        case .upper: value.uppercased()
        case .lower: value.lowercased()
        case .capitalize: value.prefix(1).uppercased() + value.dropFirst()
        case .katakana: KanaWidth.katakana(from: value)
        case .hiragana: KanaWidth.hiragana(from: value)
        case .halfwidth: KanaWidth.halfwidthKatakana(from: KanaWidth.katakana(from: value))
        case .fullwidth: KanaWidth.fullwidthASCII(from: value)
        case .ascii: KanaWidth.halfwidthASCII(from: value)
        case .romaji: HepburnRomanizer.romaji(from: value)
        case .snake: Self.words(of: value).map { $0.lowercased() }.joined(separator: "_")
        case .kebab: Self.words(of: value).map { $0.lowercased() }.joined(separator: "-")
        case .camel:
            Self.words(of: value).enumerated().map { $0.offset == 0 ? $0.element.lowercased() : Self.capitalized($0.element) }.joined()
        case .pascal: Self.words(of: value).map(Self.capitalized).joined()
        case .url: Self.percentEncoded(value)
        case .length: String(value.count)
        case .kansuji: Self.replacingNumbers(in: value) { NumberForms.withUnits(Self.significant($0), numerals: NumberForms.plainNumerals) }
        case .kanjidigits: Self.replacingNumbers(in: value) { String($0.map { NumberForms.plainNumerals[$0] }) }
        case .daiji: Self.replacingNumbers(in: value) { NumberForms.formal(Self.significant($0)) }
        case .circled: Self.replacingNumbers(in: value) { NumberForms.whiteCircled(Self.significant($0).reduce(0) { $0 * 10 + $1 }) }
        case .comma: Self.replacingNumbers(in: value) { Self.grouped($0) }
        case .html: Self.htmlEscaped(value)
        case .base64: Data(value.utf8).base64EncodedString()
        }
    }

    /// 半角か全角の数字の並びを，transform で書き換える(0〜9 の値の並びを渡す)．nil ならそのまま残す．
    /// 小数点のあとの並びと，DefaultSettings.maximumNumberFormDigits より長い並びは書き換えない
    private static func replacingNumbers(in text: String, _ transform: ([Int]) -> String?) -> String {
        var result = ""
        var run: [Character] = []
        var previous: Character?
        func flush() {
            defer { run = [] }
            guard !run.isEmpty else { return }
            let digits = run.compactMap(digitValue)
            let isFraction = previous == "." || previous == "．"
            if !isFraction, digits.count <= DefaultSettings.maximumNumberFormDigits, let replaced = transform(digits) {
                result += replaced
            } else {
                result += String(run)
            }
        }
        for character in text {
            if digitValue(character) != nil {
                run.append(character)
                continue
            }
            flush()
            result.append(character)
            previous = character
        }
        flush()
        return result
    }

    private static func digitValue(_ character: Character) -> Int? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        switch scalar.value {
        case 0x30...0x39: return Int(scalar.value - 0x30)
        case 0xFF10...0xFF19: return Int(scalar.value - 0xFF10)
        default: return nil
        }
    }

    /// 先頭の 0 を除いた並び(0 だけなら [0])
    private static func significant(_ digits: [Int]) -> [Int] {
        let trimmed = Array(digits.drop { $0 == 0 })
        return trimmed.isEmpty ? [0] : trimmed
    }

    /// 3 桁ごとに , を入れる(1234567 → 1,234,567)．4 桁より短ければ nil
    private static func grouped(_ digits: [Int]) -> String? {
        guard digits.count > 3 else { return nil }
        var text = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { text.append(",") }
            text += String(digit)
        }
        return text
    }

    private static func htmlEscaped(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }

    private static func capitalized(_ word: String) -> String {
        word.prefix(1).uppercased() + word.dropFirst().lowercased()
    }

    /// 語に分ける．空白と記号(_ - . / など)で区切り，英字の小文字から大文字に変わるところ(helloWorld)と，
    /// 大文字の続きの最後の大文字の前(HTTPServer → HTTP・Server)でも区切る．英字でない文字(かな・漢字)は語の中に残す
    private static func words(of text: String) -> [String] {
        var words: [String] = []
        var current: [Character] = []
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if character.isWhitespace || (character.isASCII && !character.isLetter && !character.isNumber) {
                if !current.isEmpty { words.append(String(current)) }
                current = []
                continue
            }
            if let previous = current.last, character.isUppercase {
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && next?.isLowercase == true) {
                    words.append(String(current))
                    current = []
                }
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(String(current)) }
        return words
    }

    /// RFC 3986 の予約されていない文字(英数字と - _ . ~)のほかを，UTF-8 のバイトごとに %XX にする
    private static func percentEncoded(_ text: String) -> String {
        var result = ""
        for byte in text.utf8 {
            let character = Character(Unicode.Scalar(byte))
            if byte < 0x80, character.isLetter || character.isNumber || "-_.~".contains(character) {
                result.append(character)
            } else {
                let hex = String(byte, radix: 16, uppercase: true)
                result += "%" + (hex.count < 2 ? "0" + hex : hex)
            }
        }
        return result
    }
}
