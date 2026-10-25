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

    func isPrefix(_ sequence: String) -> Bool {
        prefixes.contains(sequence)
    }
}
