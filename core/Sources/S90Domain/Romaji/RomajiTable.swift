/// ローマ字からかなへの表．キーは小文字の英字と記号の並び．
public struct RomajiTable: Sendable {
    public let entries: [String: String]
    /// どれかのキーの途中になっている並び(「ky」「ts」など)
    let prefixes: Set<String>
    let longestKey: Int

    public init(entries: [String: String]) {
        self.entries = entries
        var prefixes = Set<String>()
        for key in entries.keys {
            var prefix = ""
            for character in key.dropLast() {
                prefix.append(character)
                prefixes.insert(prefix)
            }
        }
        self.prefixes = prefixes
        self.longestKey = entries.keys.map(\.count).max() ?? 0
    }

    /// 標準の表に，利用者が足した綴りを重ねた表．同じ綴りは利用者のものを使う
    public static func standard(adding rules: [RomajiRule]) -> RomajiTable {
        guard !rules.isEmpty else { return .standard }
        var entries = RomajiTable.standard.entries
        for rule in rules where rule.isValid { entries[rule.keys] = rule.kana }
        return RomajiTable(entries: entries)
    }

    func isPrefix(_ sequence: String) -> Bool {
        prefixes.contains(sequence)
    }
}

/// 利用者が足したローマ字の綴り(「wyi」→「ゐ」など)
public struct RomajiRule: Sendable, Equatable, Codable, Hashable {
    public var keys: String
    public var kana: String

    public init(keys: String, kana: String) {
        self.keys = keys
        self.kana = kana
    }

    /// 綴りは英小文字・「-」・「'」の 1〜4 文字，かなは 1〜6 文字(ATOK と同じ上限)
    public var isValid: Bool {
        (1...DefaultSettings.maximumRomajiKeysLength).contains(keys.count)
            && keys.allSatisfy { ($0.isASCII && $0.isLowercase && $0.isLetter) || $0 == "-" || $0 == "'" }
            && (1...DefaultSettings.maximumRomajiKanaLength).contains(kana.count)
    }
}

extension RomajiRule: CustomStringConvertible, CustomDebugStringConvertible {
    // 利用者が足した綴りは設定の中身なので，ログには長さだけを出す
    public var description: String { "RomajiRule(keysLength: \(keys.count), kanaLength: \(kana.count))" }
    public var debugDescription: String { description }
}
