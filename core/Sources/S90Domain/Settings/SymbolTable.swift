/// 日本語のモードで記号のキーを押したときに読みに入れる文字．
public enum SymbolTable {
    /// プロファイルによらず全角にする記号．句読点は日本語の文の中でしか使わないため
    private static let common: [Character: String] = [
        ",": "、",
        ".": "。",
    ]

    /// 通常のプロファイルだけで全角にする記号．プログラミングでは半角のまま使う(R-06)
    private static let standardOnly: [Character: String] = [
        "[": "「", "]": "」", "/": "・", "~": "〜",
        "!": "！", "?": "？", "(": "（", ")": "）",
        ":": "：", ";": "；", "{": "｛", "}": "｝",
        "<": "＜", ">": "＞", "\"": "”", "'": "’",
        "&": "＆", "%": "％", "#": "＃", "$": "＄",
        "@": "＠", "*": "＊", "+": "＋", "=": "＝",
        "^": "＾", "_": "＿", "|": "｜", "`": "｀",
    ]

    public static func text(for character: Character, profile: AppProfile) -> String {
        if let mapped = common[character] { return mapped }
        if !profile.prefersHalfwidthSymbols, let mapped = standardOnly[character] { return mapped }
        return String(character)
    }
}
