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
        }
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
