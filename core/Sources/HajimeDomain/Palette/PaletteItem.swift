/// 絵文字と記号のパレットに並べる 1 つの文字(同梱の表 data/palette/palette.tsv の 1 行)
public struct PaletteItem: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case emoji
        case symbol
    }

    public var kind: Kind
    public var category: PaletteCategory
    /// 入れる文字．絵文字は肌の色を変えていない形
    public var text: String
    /// 絵文字が入った Unicode の絵文字のバージョン．記号は nil
    public var version: EmojiVersion?
    public var japaneseName: String
    /// 日本語の名前の読み(ひらがな)．求められなかった名前は空
    public var nameReading: String
    public var englishName: String
    /// ひらがなの読み(名前の読みを含む)
    public var readings: [String]
    /// 漢字を含む日本語のキーワードと，英語のキーワード(小文字)
    public var keywords: [String]
    /// ショートコード(「:bow:」のコロンを除いた「bow」)
    public var shortcodes: [String]
    /// 肌の色を変えた形．明るい順に SkinTone.allTones と同じ数だけ並ぶ．変えられない絵文字は空
    public var skinTones: [String]

    public init(kind: Kind, category: PaletteCategory, text: String, version: EmojiVersion? = nil, japaneseName: String = "", nameReading: String = "",
                englishName: String = "", readings: [String] = [], keywords: [String] = [], shortcodes: [String] = [], skinTones: [String] = []) {
        self.kind = kind
        self.category = category
        self.text = text
        self.version = version
        self.japaneseName = japaneseName
        self.nameReading = nameReading
        self.englishName = englishName
        self.readings = readings
        self.keywords = keywords
        self.shortcodes = shortcodes
        self.skinTones = skinTones
    }

    /// 肌の色を選んだときに入れる文字．肌の色を変えられない絵文字は text のまま
    public func text(skinTone: SkinTone) -> String {
        guard let index = SkinTone.allTones.firstIndex(of: skinTone), skinTones.indices.contains(index) else { return text }
        return skinTones[index]
    }

    /// 肌の色を変えられるか
    public var hasSkinTones: Bool { !skinTones.isEmpty }
}

/// Unicode の絵文字のバージョン(「15.1」)
public struct EmojiVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    /// 「15.1」の形を読む
    public init?(_ text: some StringProtocol) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let major = Int(parts[0]), let minor = Int(parts[1]), major >= 0, minor >= 0 else { return nil }
        self.init(major: major, minor: minor)
    }

    public static func < (lhs: EmojiVersion, rhs: EmojiVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    public var description: String { "\(major).\(minor)" }
}

/// 絵文字の肌の色
public enum SkinTone: String, Sendable, Hashable, Codable, CaseIterable {
    /// 変えない(黄色の絵文字)
    case none
    case light
    case mediumLight
    case medium
    case mediumDark
    case dark

    /// 色を変える形の順(明るい順)．表の肌の色の形の並びと同じ
    public static let allTones: [SkinTone] = [.light, .mediumLight, .medium, .mediumDark, .dark]
}

/// パレットのまとまり．絵文字は Unicode の絵文字のまとまり，記号は tools/palette/symbols.txt のまとまり．並びはパレットのタブの順
public enum PaletteCategory: String, Sendable, Hashable, Codable, CaseIterable {
    case smileys
    case people
    case nature
    case food
    case travel
    case activities
    case objects
    case symbols
    case flags
    case punctuation
    case brackets
    case arrows
    case math
    case letters
    case units
    case enclosed
    case shapes
    case lines
    case misc

    public var kind: PaletteItem.Kind {
        switch self {
        case .smileys, .people, .nature, .food, .travel, .activities, .objects, .symbols, .flags: .emoji
        case .punctuation, .brackets, .arrows, .math, .letters, .units, .enclosed, .shapes, .lines, .misc: .symbol
        }
    }

    /// 見出しと読み上げに使う名前
    public var title: String {
        switch self {
        case .smileys: "顔と感情"
        case .people: "人と体"
        case .nature: "動物と自然"
        case .food: "食べ物と飲み物"
        case .travel: "旅行と場所"
        case .activities: "活動"
        case .objects: "物"
        case .symbols: "記号と標識"
        case .flags: "旗"
        case .punctuation: "句読点と約物"
        case .brackets: "括弧"
        case .arrows: "矢印"
        case .math: "数学"
        case .letters: "ギリシャ文字とキリル文字"
        case .units: "単位と通貨"
        case .enclosed: "囲み文字"
        case .shapes: "図形"
        case .lines: "罫線"
        case .misc: "その他の記号"
        }
    }

    /// タブにアイコンを描けないときに代わりに見せる，まとまりを表す文字
    public var symbol: String {
        switch self {
        case .smileys: "😀"
        case .people: "👋"
        case .nature: "🐻"
        case .food: "🍔"
        case .travel: "🚗"
        case .activities: "⚽"
        case .objects: "💡"
        case .symbols: "🔣"
        case .flags: "🏁"
        case .punctuation: "、"
        case .brackets: "「"
        case .arrows: "→"
        case .math: "±"
        case .letters: "α"
        case .units: "℃"
        case .enclosed: "①"
        case .shapes: "★"
        case .lines: "┼"
        case .misc: "♪"
        }
    }
}
