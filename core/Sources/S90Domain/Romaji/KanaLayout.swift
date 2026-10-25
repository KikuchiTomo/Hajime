/// JIS かな配列．キーの刻印(英数のときに入る文字．JIS キーボードの位置)から，かなを引く(R-05)．
///
/// キーの刻印で引くのは，キーボードの配列の設定(US・JIS)によらず，同じ位置のキーから同じかなを入れるため．
/// 刻印はアダプタがキーの位置から決める(macOS は仮想キーコード)
public enum KanaLayout {
    /// 刻印と，Shift なし・Shift ありのかな
    private static let jis: [String: (normal: String, shifted: String?)] = [
        "1": ("ぬ", nil), "2": ("ふ", nil), "3": ("あ", "ぁ"), "4": ("う", "ぅ"), "5": ("え", "ぇ"),
        "6": ("お", "ぉ"), "7": ("や", "ゃ"), "8": ("ゆ", "ゅ"), "9": ("よ", "ょ"), "0": ("わ", "を"),
        "-": ("ほ", nil), "^": ("へ", nil), "¥": ("ー", nil),
        "q": ("た", nil), "w": ("て", nil), "e": ("い", "ぃ"), "r": ("す", nil), "t": ("か", nil),
        "y": ("ん", nil), "u": ("な", nil), "i": ("に", nil), "o": ("ら", nil), "p": ("せ", nil),
        "@": ("゛", nil), "[": ("゜", "「"),
        "a": ("ち", nil), "s": ("と", nil), "d": ("し", nil), "f": ("は", nil), "g": ("き", nil),
        "h": ("く", nil), "j": ("ま", nil), "k": ("の", nil), "l": ("り", nil), ";": ("れ", nil),
        ":": ("け", nil), "]": ("む", "」"),
        "z": ("つ", "っ"), "x": ("さ", nil), "c": ("そ", nil), "v": ("ひ", nil), "b": ("こ", nil),
        "n": ("み", nil), "m": ("も", nil), ",": ("ね", "、"), ".": ("る", "。"), "/": ("め", "・"), "_": ("ろ", nil),
    ]

    public static func kana(forKey key: String, shift: Bool) -> String? {
        guard let entry = jis[key] else { return nil }
        return shift ? (entry.shifted ?? entry.normal) : entry.normal
    }

    /// 濁点(゛)・半濁点(゜)を前のかなと合わせる．合わせられなければ nil
    public static func combine(_ base: Character, with mark: Character) -> Character? {
        switch mark {
        case "゛": voiced[base]
        case "゜": semiVoiced[base]
        default: nil
        }
    }

    private static let voiced: [Character: Character] = {
        var table: [Character: Character] = [:]
        for (plain, marked) in zip("かきくけこさしすせそたちつてとはひふへほ", "がぎぐげござじずぜぞだぢづでどばびぶべぼ") {
            table[plain] = marked
        }
        table["う"] = "ゔ"
        return table
    }()

    private static let semiVoiced: [Character: Character] = Dictionary(uniqueKeysWithValues: zip("はひふへほ", "ぱぴぷぺぽ"))
}
