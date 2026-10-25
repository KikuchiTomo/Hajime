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
}
