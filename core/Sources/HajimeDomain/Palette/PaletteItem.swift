/// 絵文字と記号のパレットに並べる 1 つの文字(同梱の表 data/palette/palette.tsv の 1 行)
public struct PaletteItem: Sendable, Equatable, Hashable {
    /// 種類．並びはパレットの種類の切り替えの順
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        case emoji
        case symbol
        case kaomoji

        /// マス目のマスの形
        public var cellShape: PaletteCellShape { self == .kaomoji ? .wide : .square }
    }

    /// 日本語の名前を定めたところ(表の「名前の出どころ」の列)
    public enum NameSource: String, Sendable, Hashable {
        /// CLDR の名前
        case cldr
        /// Hajime IME が付けた名前(tools/palette/names.txt・Unicode の名前の形から作った名前・囲み文字の中の文字)
        case hajime
    }

    public var kind: Kind
    public var category: PaletteCategory
    /// 入れる文字．絵文字は肌の色を変えていない形．顔文字は何文字もある
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
    /// 日本語の名前を定めたところ．顔文字と名前の無い項目は nil
    public var nameSource: NameSource?

    public init(kind: Kind, category: PaletteCategory, text: String, version: EmojiVersion? = nil, japaneseName: String = "", nameReading: String = "",
                englishName: String = "", readings: [String] = [], keywords: [String] = [], shortcodes: [String] = [], skinTones: [String] = [],
                nameSource: NameSource? = nil) {
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
        self.nameSource = nameSource
    }

    /// 肌の色を選んだときに入れる文字．肌の色を変えられない絵文字は text のまま
    public func text(skinTone: SkinTone) -> String {
        guard let index = SkinTone.allTones.firstIndex(of: skinTone), skinTones.indices.contains(index) else { return text }
        return skinTones[index]
    }

    /// 肌の色を変えられるか
    public var hasSkinTones: Bool { !skinTones.isEmpty }
}

/// パレットのマスの形．顔文字は横に長いので，四角いマスをいくつかつなげた広いマスに並べる．
/// 形の違う種類は，ピン留め・よく使う文字・探した結果でも同じマス目に混ぜない
public enum PaletteCellShape: String, Sendable, Hashable, CaseIterable {
    case square
    case wide
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

/// パレットのまとまり．絵文字は Unicode の絵文字のまとまり，記号は tools/palette/symbols.txt のまとまり，
/// 顔文字は Mozc の顔文字のまとまりと読みから tools/palette/build.py が決めたまとまり．並びはパレットのタブの順
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
    case joy
    case sorrow
    case sweat
    case anger
    case surprise
    case greeting
    case animals
    case otherFaces

    public var kind: PaletteItem.Kind {
        switch self {
        case .smileys, .people, .nature, .food, .travel, .activities, .objects, .symbols, .flags: .emoji
        case .punctuation, .brackets, .arrows, .math, .letters, .units, .enclosed, .shapes, .lines, .misc: .symbol
        case .joy, .sorrow, .sweat, .anger, .surprise, .greeting, .animals, .otherFaces: .kaomoji
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
        case .activities: "アクティビティ"
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
        case .joy: "笑顔"
        case .sorrow: "悲しみ"
        case .sweat: "焦り"
        case .anger: "怒り"
        case .surprise: "驚き"
        case .greeting: "挨拶と動作"
        case .animals: "動物"
        case .otherFaces: "その他の顔文字"
        }
    }

    /// タブにアイコンを描けないときに代わりに見せる，まとまりを表す文字．顔文字は短い顔(タブの幅に収まらなければ描く側が縮める)
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
        case .joy: "^^"
        case .sorrow: "T_T"
        case .sweat: "^^;"
        case .anger: "`д´"
        case .surprise: "ﾟдﾟ"
        case .greeting: "ﾉｼ"
        case .animals: "ΦωΦ"
        case .otherFaces: "☆彡"
        }
    }
}

extension EmojiVersion {
    /// Windows のこのビルドの絵文字の書体が描けるバージョン(DefaultSettings.windowsEmojiVersions)
    public static func supportedOnWindows(build: Int) -> EmojiVersion {
        let table = DefaultSettings.windowsEmojiVersions
        return table.last { build >= $0.build }?.version ?? table.first?.version ?? EmojiVersion(major: 0, minor: 0)
    }
}
