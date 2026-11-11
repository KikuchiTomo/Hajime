/// 日本語のモードで記号のキーを押したときに読みに入れる文字．
public enum SymbolTable {
    /// 通常のプロファイルだけで全角にする記号．プログラミングでは半角のまま使う(R-06)
    private static let standardOnly: [Character: String] = [
        "~": "〜",
        "!": "！", "?": "？", "(": "（", ")": "）",
        ":": "：", ";": "；", "{": "｛", "}": "｝",
        "<": "＜", ">": "＞", "\"": "”", "'": "’",
        "&": "＆", "%": "％", "#": "＃", "$": "＄",
        "@": "＠", "*": "＊", "+": "＋", "=": "＝",
        "^": "＾", "_": "＿", "|": "｜", "`": "｀",
    ]

    public static func text(for character: Character, profile: AppProfile, settings: Settings) -> String {
        // 句読点はプロファイルによらず設定の文字にする．日本語の文の中でしか使わないため
        switch character {
        case ",": return settings.punctuation.comma
        case ".": return settings.punctuation.period
        default: break
        }
        guard !profile.prefersHalfwidthSymbols else { return String(character) }
        switch character {
        case "[": return settings.brackets.open
        case "]": return settings.brackets.close
        case "/": return settings.slash.text
        default: return standardOnly[character] ?? String(character)
        }
    }

    /// 句読点か(設定の句読点の文字か)
    public static func isPunctuation(_ text: String, settings: Settings) -> Bool {
        text == settings.punctuation.comma || text == settings.punctuation.period
    }

    /// 数字のあとの「.」「,」(小数点と桁区切り．「3.14」「1,000」)．設定(numberSeparators)がオンで直前の文字が数字なら，
    /// その数字と同じ幅の「.」「,」(全角なら「．」「，」)．そうでなければ nil で，句読点にする
    public static func numberSeparator(for character: Character, after previous: Character?, settings: Settings) -> String? {
        guard settings.numberSeparators, character == "." || character == ",", let previous, let width = digitWidth(previous) else { return nil }
        return width == .fullwidth ? KanaWidth.fullwidthASCII(from: String(character)) : String(character)
    }

    /// 英数字のあとの「-」(ハイフン．「A-1」「3-4」)．設定(alphanumericHyphen)がオンで直前の文字が英数字なら，
    /// その文字と同じ幅の「-」(全角なら「－」)．そうでなければ nil で，長音にする
    public static func hyphen(after previous: Character?, settings: Settings) -> String? {
        guard settings.alphanumericHyphen, let previous, Composition.isAlphanumeric(previous) else { return nil }
        return previous.isASCII ? "-" : KanaWidth.fullwidthASCII(from: "-")
    }

    /// 読みの先頭に「-」で打った長音に数字を続けたとき(「-3」)，長音の代わりに置く符号．数字と同じ幅の「-」．
    /// 先頭の「-」は続く文字が決まるまで長音にしておく(「->」を「→」に，「--」を「ーー」にするため)．設定がオフなら nil
    public static func sign(before digit: Character, settings: Settings) -> String? {
        guard settings.alphanumericHyphen, let width = digitWidth(digit) else { return nil }
        return width == .fullwidth ? KanaWidth.fullwidthASCII(from: "-") : "-"
    }

    /// 数字(半角か全角)の幅．数字でなければ nil
    private static func digitWidth(_ character: Character) -> CharacterWidth? {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return nil }
        switch scalar.value {
        case 0x30...0x39: return .halfwidth
        case 0xFF10...0xFF19: return .fullwidth
        default: return nil
        }
    }
}
