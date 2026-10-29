/// アプリの扱いの規則(ProfileRule)を CSV で読み書きする．1 行は「アプリの ID,扱い」．
///
/// 扱いは standard・programming・terminal・direct か，設定の画面の名前(標準・記号を半角・コマンドを英字・IME を使わない)．
/// 見出しの行，# で始まる行，空の行，形の誤った行は読み飛ばす
public enum ProfileRuleCSV {
    public static let header = "app_id,mode"

    /// 読める規則を返す．同じアプリの ID は先の行を使う
    public static func parse(_ text: String) -> [ProfileRule] {
        var seen = Set<String>()
        var rules: [ProfileRule] = []
        for trimmed in ruleLines(text) {
            let columns = trimmed.split(separator: ",", omittingEmptySubsequences: false).map(trim)
            guard columns.count == 2, let profile = profile(named: columns[1]), isValidIdentifier(columns[0]),
                seen.insert(columns[0]).inserted else { continue }
            rules.append(ProfileRule(applicationPrefix: columns[0], profile: profile))
            if rules.count == DefaultSettings.maximumProfileRules { break }
        }
        return rules
    }

    /// 読み込んだ規則を先頭に足す．同じアプリの ID の規則は読み込んだほうに置き換える
    public static func merge(_ imported: [ProfileRule], into settings: inout Settings) {
        let identifiers = Set(imported.map(\.applicationPrefix))
        settings.profileRules.removeAll { identifiers.contains($0.applicationPrefix) }
        settings.profileRules.insert(contentsOf: imported, at: 0)
        settings.clampToValidRanges()
    }

    public static func write(_ rules: [ProfileRule]) -> String {
        ([header] + rules.map { "\($0.applicationPrefix),\($0.profile.rawValue)" }).joined(separator: "\n") + "\n"
    }

    /// バンドル ID として使える文字だけか(英数字・「.」・「-」・「_」，長さの上限あり)
    public static func isValidIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.count <= DefaultSettings.maximumApplicationIdentifierLength
            && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
    }

    /// 規則として読む行(見出し・# で始まる行・空の行を除く)の数
    public static func ruleLineCount(_ text: String) -> Int {
        ruleLines(text).count
    }

    private static func ruleLines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map(trim).filter { !$0.isEmpty && !$0.hasPrefix("#") && $0.lowercased() != header }
    }

    private static func trim(_ text: Substring) -> String {
        String(text.drop { $0 == " " || $0 == "\t" }.reversed().drop { $0 == " " || $0 == "\t" || $0 == "\r" }.reversed())
    }

    private static func profile(named name: String) -> AppProfile? {
        AppProfile(rawValue: name) ?? aliases[name]
    }

    /// 扱いの別名．書き出しは値(standard など)だけを書くが，手で書いた CSV のために日本語の名前も読む．
    /// 設定の画面の名前を変えても読めるよう，画面の文言とは別にここで決める
    static let aliases: [String: AppProfile] = [
        "標準": .standard, "記号を半角": .programming, "コマンドを英字": .terminal, "IME を使わない": .direct,
    ]
}
