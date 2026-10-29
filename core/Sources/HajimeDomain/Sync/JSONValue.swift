/// JSON の値．設定のファイルの形を項目ごとに扱う(形式のバージョンの移し替え，同期，知らない項目の保持)ために使う
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // 整数で表せる数は整数で書く(候補の数などが 5.0 にならないように)
            if value.rounded() == value, abs(value) < 1e15 { try container.encode(Int64(value)) } else { try container.encode(value) }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue: CustomStringConvertible, CustomDebugStringConvertible {
    // 設定の値にはユーザー辞書の語などの入力内容が入るので，ログには形だけを出す
    public var description: String {
        switch self {
        case .null: "null"
        case .bool: "bool"
        case .number: "number"
        case .string(let value): "string(length: \(value.count))"
        case .array(let value): "array(\(value.count))"
        case .object(let value): "object(\(value.count))"
        }
    }

    public var debugDescription: String { description }
}
