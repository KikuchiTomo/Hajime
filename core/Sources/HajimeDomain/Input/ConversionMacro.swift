import Foundation

/// 変換マクロ．変換中に選んでいる語を，決まった形に整える(「東京」→「【東京】」「東京(とうきょう)」)．
/// 連想変換のキーで出す一覧の「整形」のまとまりに並ぶ(AssociationFinder)．形は TextTemplate の書き方で，`{text}` が選んでいる語，`{reading}` がその読み
public struct ConversionMacro: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: String
    public var pattern: String
    public var isEnabled: Bool

    public init(id: String = UUID().uuidString, pattern: String, isEnabled: Bool = true) {
        self.id = id
        self.pattern = pattern
        self.isEnabled = isEnabled
    }

    /// 形の正しいマクロか．`{text}` か `{reading}` を含み，上限の長さ以内で，改行とタブを含まない
    public var isValid: Bool {
        UUID(uuidString: id) != nil && pattern.count <= DefaultSettings.maximumMacroPatternLength
            && (pattern.contains("{text") || pattern.contains("{reading"))
            && !pattern.contains(where: { $0.isNewline || $0 == "\t" })
    }

    /// 選んでいる語に当てはめた文字列
    public func apply(text: String, reading: String) -> String {
        TextTemplate.expand(pattern, values: .init(text: text, reading: reading))
    }
}

extension ConversionMacro {
    private enum CodingKeys: String, CodingKey {
        case id, pattern, isEnabled
    }

    /// Windows の設定の画面は一覧の行を id なしで足すので，id が無ければ作る
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
                  pattern: try container.decode(String.self, forKey: .pattern),
                  isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true)
    }
}

extension ConversionMacro: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "ConversionMacro(patternLength: \(pattern.count))" }
    public var debugDescription: String { description }
}

public enum ConversionMacros {
    /// 選んでいる語に，使えるマクロをすべて当てはめた文字列(元の語と同じもの・重なるものは除く)
    public static func results(text: String, reading: String, macros: [ConversionMacro]) -> [String] {
        var seen: Set<String> = [text]
        return macros.filter { $0.isEnabled && $0.isValid }
            .map { $0.apply(text: text, reading: reading) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
