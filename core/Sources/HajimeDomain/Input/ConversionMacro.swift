import Foundation

/// 変換マクロ．変換中に選んでいる語を，決まった形に整える(「東京」→「【東京】」「東京(とうきょう)」)．
/// 連想変換のキーで出す一覧の「整形」のまとまりに並ぶ(AssociationFinder)．形は TextTemplate の書き方で，`{text}` が選んでいる語，`{reading}` がその読み．
/// 日時・乱数・変換(`{reading|romaji}`)など，動的なユーザー辞書と同じ書き方をすべて使える
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

    /// 選んでいる語に当てはめた文字列．values は日時と乱数の作り方(語と読みは text と reading にする)
    public func apply(text: String, reading: String, values: TextTemplate.Values = .init()) -> String {
        var values = values
        values.text = text
        values.reading = reading
        return TextTemplate.expand(pattern, values: values)
    }

    /// 語と読みを並べる形(ルビ・読みを添える形)か．かなの語では語と読みが同じになるので出さないことがある(ConversionMacros.results)
    public var annotatesReading: Bool {
        let names = TextTemplate.names(in: pattern)
        return names.contains("text") && names.contains("reading")
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
    /// 選んでいる語に，使えるマクロをすべて当てはめた文字列(元の語と同じもの・重なるものは除く)．
    /// skipsSameReading なら，語が読みと同じ(かなの語)ときに語と読みを並べる形を除く(「とうきょう(とうきょう)」を出さない)
    public static func results(text: String, reading: String, macros: [ConversionMacro], values: TextTemplate.Values = .init(),
                               skipsSameReading: Bool = false) -> [String] {
        var seen: Set<String> = [text]
        let sameReading = skipsSameReading && KanaWidth.hiragana(from: text) == KanaWidth.hiragana(from: reading)
        return macros.filter { $0.isEnabled && $0.isValid && !(sameReading && $0.annotatesReading) }
            .map { $0.apply(text: text, reading: reading, values: values) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
