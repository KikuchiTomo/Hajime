import Foundation

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

extension HexColor {
    /// WCAG 2.2 の相対輝度(tools/tokens/check_contrast.py と同じ式)
    public var relativeLuminance: Double {
        func linear(_ channel: UInt8) -> Double {
            let value = Double(channel) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.2 のコントラスト比(1〜21)
    public func contrastRatio(with other: HexColor) -> Double {
        let (lighter, darker) = (max(relativeLuminance, other.relativeLuminance), min(relativeLuminance, other.relativeLuminance))
        return (lighter + 0.05) / (darker + 0.05)
    }
}

extension CustomTheme {
    /// 文字と地のコントラストを確かめる組み合わせ．基準は design/tokens/tokens.json の既成のテーマと同じ
    public enum ContrastPair: Sendable, Equatable, CaseIterable {
        /// 文字と背景
        case text
        /// 補助の文字と背景
        case textMuted
        /// 選択中の文字と選択の色
        case selectionText
        /// 修正の印と背景
        case correction

        /// 求めるコントラスト比．文字は 4.5，印(下線)は 3
        public var minimum: Double {
            self == .correction ? DefaultSettings.minimumMarkContrast : DefaultSettings.minimumTextContrast
        }
    }

    public func contrastRatio(of pair: ContrastPair) -> Double {
        switch pair {
        case .text: text.contrastRatio(with: surface)
        case .textMuted: textMuted.contrastRatio(with: surface)
        case .selectionText: selectionText.contrastRatio(with: selection)
        case .correction: correction.contrastRatio(with: surface)
        }
    }

    /// 基準に届かず読みにくい組み合わせ
    public var lowContrastPairs: [ContrastPair] {
        ContrastPair.allCases.filter { contrastRatio(of: $0) < $0.minimum }
    }
}
