/// 英字で打った語を，英語のまま入れるか日本語にするか(R-05 の英字入力(自動)，R-02 のローマ字入力の英単語)
public enum WordLanguage: String, Sendable, Equatable, Codable, CaseIterable {
    case english
    case japanese
}

/// 語の前が何か．英語か日本語かを見分ける手がかり
public enum WordLanguageContext: String, Sendable, Equatable, Codable, CaseIterable {
    /// 文や行の頭(前に何も無い)
    case sentenceStart
    /// 前が英語
    case afterEnglish
    /// 前が日本語
    case afterJapanese

    /// 入力位置の前の文字列から決める．空白を飛ばした最後の文字が英数字なら英語，かな・漢字なら日本語，
    /// 何も無いか改行なら文の頭．記号は手がかりにならないので文の頭として扱う
    public static func of(precedingText text: String?) -> WordLanguageContext {
        guard let last = text?.last(where: { $0 != " " && $0 != "\u{3000}" && $0 != "\t" }) else { return .sentenceStart }
        if last.isASCII, last.isLetter || last.isNumber { return .afterEnglish }
        if WordLanguageJudge.isJapanese(last) { return .afterJapanese }
        return .sentenceStart
    }
}

/// 利用者が足す見分け方の決まり．「make は前が英語なら英語」のように，語と前の手がかりから決める
public struct WordLanguageRule: Sendable, Equatable, Codable, Hashable {
    /// 英字の語(小文字で比べる)
    public var word: String
    public var context: WordLanguageContext
    public var language: WordLanguage

    public init(word: String, context: WordLanguageContext, language: WordLanguage) {
        self.word = word
        self.context = context
        self.language = language
    }

    public var isValid: Bool { WordLanguageSettings.isValidWord(word) }
}

/// 英語か日本語かを見分ける設定(R-05，R-02)
public struct WordLanguageSettings: Sendable, Equatable, Codable {
    /// いつも英語にする語
    public var englishWords: [String] = []
    /// いつも日本語にする語
    public var japaneseWords: [String] = []
    /// 見分け方の決まり
    public var rules: [WordLanguageRule] = []
    /// 英語にも日本語にも読める語(「make」)を，前の語で見分ける
    public var usesContext = true
    /// 不適切な語(「死ね」)を第 1 候補に出さない．英字入力(自動)では，前が日本語でなければそうした語を日本語にしない
    public var avoidsOffensive = true

    public init() {}

    /// 語として足せるか．英字だけで，長すぎないもの
    public static func isValidWord(_ word: String) -> Bool {
        !word.isEmpty && word.count <= DefaultSettings.maximumWordLanguageWordLength && word.allSatisfy { $0.isASCII && $0.isLetter }
    }

    /// 形の誤った語と決まりを捨て，数を上限に収める
    public mutating func clampToValidRanges() {
        func clean(_ words: [String]) -> [String] {
            var seen = Set<String>()
            return Array(words.map { $0.lowercased() }.filter { Self.isValidWord($0) && seen.insert($0).inserted }.prefix(DefaultSettings.maximumWordLanguageEntries))
        }
        englishWords = clean(englishWords)
        japaneseWords = clean(japaneseWords)
        var seenRules = Set<String>()
        rules = Array(rules.map { WordLanguageRule(word: $0.word.lowercased(), context: $0.context, language: $0.language) }
            // 同じ語と手がかりの決まりは後のものを残す
            .reversed().filter { $0.isValid && seenRules.insert("\($0.word):\($0.context.rawValue)").inserted }.reversed()
            .prefix(DefaultSettings.maximumWordLanguageEntries))
    }

    private enum CodingKeys: String, CodingKey {
        case englishWords, japaneseWords, rules, usesContext, avoidsOffensive
    }

    /// 無い項目と読めない項目は既定値のままにする(Settings と同じ)．崩れた決まりは 1 つずつ飛ばす
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var value = WordLanguageSettings()
        if let words = try? container.decodeIfPresent([String].self, forKey: .englishWords) { value.englishWords = words }
        if let words = try? container.decodeIfPresent([String].self, forKey: .japaneseWords) { value.japaneseWords = words }
        if var list = try? container.nestedUnkeyedContainer(forKey: .rules) {
            var rules: [WordLanguageRule] = []
            while !list.isAtEnd {
                if let rule = try? list.decode(WordLanguageRule.self) {
                    rules.append(rule)
                } else if (try? list.decode(SkippedValue.self)) == nil {
                    break
                }
            }
            value.rules = rules
        }
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .usesContext) { value.usesContext = flag }
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .avoidsOffensive) { value.avoidsOffensive = flag }
        value.clampToValidRanges()
        self = value
    }
}

/// 読めない要素を読み飛ばすための型
private struct SkippedValue: Decodable {}

extension WordLanguageSettings: CustomStringConvertible, CustomDebugStringConvertible {
    // 利用者の足した語は入力内容と同じに扱うので，ログには数だけを出す
    public var description: String {
        "WordLanguageSettings(englishWords: \(englishWords.count), japaneseWords: \(japaneseWords.count), rules: \(rules.count))"
    }
    public var debugDescription: String { description }
}

/// 英字で打った 1 語を英語にするか日本語にするかを決める．手がかりは呼び出し側が調べて渡す(Evidence)
public struct WordLanguageJudge: Sendable {
    /// 語について調べたこと
    public struct Evidence: Sendable, Equatable {
        /// 打った英字
        public var keys: String
        /// 英語の辞書にある語か
        public var isEnglishWord: Bool
        /// ローマ字として読んだ読み．読めなければ nil
        public var reading: String?
        /// 読みを変換したときのもっともらしさを読みの文字数で割ったもの．大きいほど日本語らしい
        public var plausibilityPerCharacter: Double?
        /// 読みか第 1 候補が不適切な語か(「しね」→「死ね」)
        public var isOffensive: Bool

        public init(keys: String, isEnglishWord: Bool, reading: String?, plausibilityPerCharacter: Double?, isOffensive: Bool) {
            self.keys = keys
            self.isEnglishWord = isEnglishWord
            self.reading = reading
            self.plausibilityPerCharacter = plausibilityPerCharacter
            self.isOffensive = isOffensive
        }
    }

    /// どの入力方式で見分けるか．英語にも日本語にも読める語を，手がかりが無いときにどちらにするかが違う
    public enum Mode: Sendable {
        /// 英字入力のライブ変換．英語の辞書にある語は英語，ほかのローマ字として読める語は日本語(もっともらしさも前の語も見ない)
        case dictionaryOnly
        /// 英字入力(自動)．英語を打つのが主なので，迷ったら英語
        case englishFirst
        /// ローマ字入力．日本語を打つのが主なので，迷ったら日本語．英語の辞書にない語は必ず日本語
        case japaneseFirst
    }

    public var settings: WordLanguageSettings
    public var mode: Mode
    /// 英単語にしない読みの長さ(設定)．ローマ字として読んだかながこの文字数以下の語は，前が英語でなければ日本語にする
    public var japaneseReadingLength: Int

    public init(settings: WordLanguageSettings, mode: Mode, japaneseReadingLength: Int = DefaultSettings.englishSkipLength) {
        self.settings = settings
        self.mode = mode
        self.japaneseReadingLength = japaneseReadingLength
    }

    /// 英語か日本語か．次の順に決める
    /// 1. 利用者が足した「いつも英語」「いつも日本語」の語(英字入力のライブ変換では 3 のあと，英語の辞書の語は英語)
    /// 2. 利用者が足した見分け方の決まり(語と前の手がかり)
    /// 3. ローマ字として読めなければ英語
    /// 3a. 読みが短い語(設定の英単語にしない文字数以下．「make」→ まけ)は，前が英語でなければ日本語
    /// 4. 英語の辞書にない語は，英字入力(自動)では日本語らしければ日本語(読みのもっともらしさ)，ローマ字入力では日本語
    /// 5. 英語にも日本語にも読める語(「make」「shine」)は，前の語で見分ける(設定)．前が英語なら英語，前が日本語なら日本語
    /// 6. 手がかりが無ければ，不適切な語(「しね」)は英語にし，ほかは入力方式の主な言語にする
    public func decide(_ evidence: Evidence, context: WordLanguageContext) -> WordLanguage {
        let word = evidence.keys.lowercased()
        if settings.englishWords.contains(word) { return .english }
        if settings.japaneseWords.contains(word) { return .japanese }
        if let rule = settings.rules.last(where: { $0.word == word && $0.context == context }) { return rule.language }
        guard evidence.reading != nil else { return .english }
        if mode == .dictionaryOnly { return evidence.isEnglishWord ? .english : .japanese }
        // ローマ字入力では，短い語(「no」)は前が英語でも日本語にする
        if mode == .japaneseFirst, word.count <= DefaultSettings.maximumJapaneseFirstShortWordLength, !evidence.isOffensive { return .japanese }
        // 読みが短い語(「make」→ まけ)は，前が英語でなければ日本語にする(設定)．前が英語なら下の前の語の見分けに任せる
        if let reading = evidence.reading, reading.count <= japaneseReadingLength, !evidence.isOffensive,
           !(settings.usesContext && context == .afterEnglish) { return .japanese }
        guard evidence.isEnglishWord else {
            switch mode {
            case .dictionaryOnly: return .japanese
            case .japaneseFirst: return .japanese
            case .englishFirst:
                let plausibility = evidence.plausibilityPerCharacter ?? -.infinity
                return plausibility >= DefaultSettings.minimumJapanesePlausibilityPerCharacter ? .japanese : .english
            }
        }
        if settings.usesContext {
            switch context {
            case .afterEnglish: return .english
            case .afterJapanese: return .japanese
            case .sentenceStart: break
            }
        }
        if settings.avoidsOffensive, evidence.isOffensive { return .english }
        return mode == .englishFirst ? .english : .japanese
    }

    /// かな・漢字か(日本語の文の手がかり)
    public static func isJapanese(_ character: Character) -> Bool {
        character.unicodeScalars.contains {
            (0x3041...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value)
                || (0xFF66...0xFF9D).contains($0.value)
        }
    }
}

/// 第 1 候補に出さない不適切な語．英語の語がローマ字として読めてしまう(「shine」→「しね」)ときに，
/// 打った人の意図に反してそうした語を出さないため．読みと書き方の両方で引く
public enum OffensiveWords {
    /// 読み(ひらがな)
    public static let readings: Set<String> = ["しね", "ころす", "ぶっころす", "くたばれ", "しんでしまえ", "うせろ"]
    /// 書き方
    public static let texts: Set<String> = ["死ね", "氏ね", "殺す", "ぶっ殺す", "ブッ殺す", "くたばれ", "死んでしまえ", "失せろ"]

    public static func isOffensive(reading: String) -> Bool { readings.contains(reading) }
    public static func isOffensive(text: String) -> Bool { texts.contains(text) }
}
