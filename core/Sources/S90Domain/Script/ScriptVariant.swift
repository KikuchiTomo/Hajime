/// 変換候補の上の「種類」の行に並ぶ文字の種類(R-03)．並び順は画面の並び順と同じ．
public enum ScriptVariant: String, Sendable, Equatable, Codable, CaseIterable {
    case hiragana
    case katakana
    case halfwidthKatakana
    case fullwidthRoman
    case halfwidthRoman

    /// 種類の行に出す名前
    public var label: String {
        switch self {
        case .hiragana: "そのまま"
        case .katakana: "カタカナ"
        case .halfwidthKatakana: "ｶﾀｶﾅ"
        case .fullwidthRoman: "全角英数"
        case .halfwidthRoman: "半角英数"
        }
    }

    /// 読みをこの種類に変える．英数の 2 種類は打ったキー(rawKeys)が分かるときだけ作れる
    public func apply(to composition: Composition) -> String? {
        let reading = composition.conversionReading
        switch self {
        case .hiragana:
            return reading
        case .katakana:
            return KanaWidth.katakana(from: reading)
        case .halfwidthKatakana:
            return KanaWidth.halfwidthKatakana(from: KanaWidth.katakana(from: reading))
        case .fullwidthRoman:
            return composition.rawKeys.flatMap { $0.isEmpty ? nil : KanaWidth.fullwidthASCII(from: $0) }
        case .halfwidthRoman:
            return composition.rawKeys.flatMap { $0.isEmpty ? nil : $0 }
        }
    }
}

/// かなの種類と文字の幅の変換．OS の変換機能(applyingTransform など)は使わず，表で行う．
/// OS ごとに結果が変わらないようにするため(.claude/skills/s90-swift/SKILL.md)．
public enum KanaWidth {
    private static let hiraganaRange: ClosedRange<UInt32> = 0x3041...0x3096
    private static let hiraganaToKatakanaOffset: UInt32 = 0x60
    private static let asciiRange: ClosedRange<UInt32> = 0x21...0x7E
    private static let fullwidthASCIIOffset: UInt32 = 0xFEE0

    public static func katakana(from text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            guard hiraganaRange.contains(scalar.value),
                let converted = Unicode.Scalar(scalar.value + hiraganaToKatakanaOffset) else { return scalar }
            return converted
        }))
    }

    /// カタカナ(ァ〜ヶ)の文字か
    public static func isKatakana(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (hiraganaRange.lowerBound + hiraganaToKatakanaOffset...hiraganaRange.upperBound + hiraganaToKatakanaOffset).contains($0.value) }
    }

    /// カタカナをひらがなにする(ァ〜ヶ)．ほかの文字はそのまま
    public static func hiragana(from text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            let katakana = (hiraganaRange.lowerBound + hiraganaToKatakanaOffset)...(hiraganaRange.upperBound + hiraganaToKatakanaOffset)
            guard katakana.contains(scalar.value), let converted = Unicode.Scalar(scalar.value - hiraganaToKatakanaOffset) else { return scalar }
            return converted
        }))
    }

    public static func fullwidthASCII(from text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            if scalar == " " { return "\u{3000}" }
            guard asciiRange.contains(scalar.value),
                let converted = Unicode.Scalar(scalar.value + fullwidthASCIIOffset) else { return scalar }
            return converted
        }))
    }

    public static func halfwidthKatakana(from katakana: String) -> String {
        var result = ""
        for character in katakana {
            if let half = halfwidthTable[character] {
                result += half
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static let halfwidthTable: [Character: String] = {
        let pairs: [(String, String)] = [
            ("アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン",
             "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜｦﾝ"),
            ("ァィゥェォャュョッー。「」、・", "ｧｨｩｪｫｬｭｮｯｰ｡｢｣､･"),
        ]
        var table: [Character: String] = [:]
        for (full, half) in pairs {
            for (f, h) in zip(full, half) { table[f] = String(h) }
        }
        // 濁点・半濁点は 2 文字になる
        let voiced = "ガギグゲゴザジズゼゾダヂヅデドバビブベボ"
        let voicedBase = "ｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾊﾋﾌﾍﾎ"
        for (f, h) in zip(voiced, voicedBase) { table[f] = String(h) + "ﾞ" }
        for (f, h) in zip("パピプペポ", "ﾊﾋﾌﾍﾎ") { table[f] = String(h) + "ﾟ" }
        table["ヴ"] = "ｳﾞ"
        return table
    }()
}
