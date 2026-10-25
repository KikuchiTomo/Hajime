/// 入力方式(R-05)
public enum InputStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// ローマ字入力
    case romaji
    /// JIS かな配列のかな入力
    case kana
    /// 英語のまま入力し，ローマ字として読める並びには日本語の候補を出す(EN 入力)．Tab で日本語にする
    case english
}

/// 句読点の組み合わせ
public enum PunctuationStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// 、。
    case toutenKuten
    /// ，．
    case commaPeriod
    /// 、．
    case toutenPeriod
    /// ，。
    case commaKuten

    public var comma: String {
        switch self {
        case .toutenKuten, .toutenPeriod: "、"
        case .commaPeriod, .commaKuten: "，"
        }
    }

    public var period: String {
        switch self {
        case .toutenKuten, .commaKuten: "。"
        case .commaPeriod, .toutenPeriod: "．"
        }
    }
}

/// [ ] で入れる括弧
public enum BracketStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// 「」
    case corner
    /// ［］
    case square

    public var open: String { self == .corner ? "「" : "［" }
    public var close: String { self == .corner ? "」" : "］" }
}

/// / で入れる文字
public enum SlashStyle: String, Sendable, Equatable, Codable, CaseIterable {
    /// ・
    case nakaguro
    /// ／
    case slash

    public var text: String { self == .nakaguro ? "・" : "／" }
}

/// 文字の幅
public enum CharacterWidth: String, Sendable, Equatable, Codable, CaseIterable {
    case halfwidth
    case fullwidth
}

/// 確定した候補から学ぶか
public enum LearningMode: String, Sendable, Equatable, Codable, CaseIterable {
    /// 学んで，学んだことを使う
    case enabled
    /// 学んだことは使うが，新しくは学ばない
    case readOnly
    /// 学ばず，学んだことも使わない
    case disabled
}

/// 利用者が登録した語
public struct UserDictionaryEntry: Sendable, Equatable, Codable, Hashable {
    /// 読み(ひらがな)
    public var reading: String
    public var word: String

    public init(reading: String, word: String) {
        self.reading = reading
        self.word = word
    }

    /// 読みはひらがなと長音だけ，語は空でなく，どちらも上限の長さ以内
    public var isValid: Bool {
        !reading.isEmpty && !word.isEmpty
            && reading.count <= DefaultSettings.maximumUserDictionaryReadingLength
            && word.count <= DefaultSettings.maximumUserDictionaryWordLength
            && reading.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || $0 == "ー" }
    }
}
