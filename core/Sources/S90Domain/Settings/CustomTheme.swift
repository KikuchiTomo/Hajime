/// 利用者が色や形を決めて保存したテーマ．元にしたテーマ(base)の描き方(角丸か立体の枠か)を使い，色と書体と形を上書きする
public struct CustomTheme: Sendable, Equatable, Hashable, Codable {
    /// 枝の線の形
    public enum BranchStyle: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
        case curved
        case straight
    }

    public var id: String
    public var name: String
    public var base: ThemePreference
    public var surface: HexColor
    public var text: HexColor
    public var textMuted: HexColor
    public var selection: HexColor
    public var selectionText: HexColor
    public var correction: HexColor
    public var line: HexColor
    /// 候補の書体の名前(PostScript 名)．nil なら元のテーマの書体
    public var fontName: String?
    /// 角の丸さ(pt)．0 で四角
    public var cornerRadius: Double
    public var branchStyle: BranchStyle

    public init(id: String, name: String, base: ThemePreference, surface: HexColor, text: HexColor, textMuted: HexColor, selection: HexColor,
                selectionText: HexColor, correction: HexColor, line: HexColor, fontName: String? = nil,
                cornerRadius: Double = DefaultSettings.customThemeCornerRadius, branchStyle: BranchStyle = .curved) {
        self.id = id
        self.name = name
        self.base = base
        self.surface = surface
        self.text = text
        self.textMuted = textMuted
        self.selection = selection
        self.selectionText = selectionText
        self.correction = correction
        self.line = line
        self.fontName = fontName
        self.cornerRadius = cornerRadius
        self.branchStyle = branchStyle
    }

    /// 名前が空でなく長すぎず，角の丸さが範囲の中か．読み込んだテーマはこれを満たすものだけを使う
    public var isValid: Bool {
        !id.isEmpty && id.count <= 64 && !name.isEmpty && name.count <= DefaultSettings.maximumThemeNameLength
            && DefaultSettings.customThemeCornerRadiusRange.contains(cornerRadius)
            && (fontName.map { !$0.isEmpty && $0.count <= 128 } ?? true)
    }
}

/// 「#RRGGBB」の形の色
public struct HexColor: Sendable, Equatable, Hashable, Codable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init?(_ text: String) {
        let digits = text.hasPrefix("#") ? text.dropFirst() : Substring(text)
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    public var hex: String {
        let digits = "0123456789ABCDEF".map { $0 }
        return "#" + [red, green, blue].map { "\(digits[Int($0 >> 4)])\(digits[Int($0 & 0x0F)])" }.joined()
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let color = HexColor(text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "色は #RRGGBB の形"))
        }
        self = color
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
