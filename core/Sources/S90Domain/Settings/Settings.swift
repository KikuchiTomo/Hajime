/// 利用者が変えられる設定．項目の既定値はここに書き，DefaultSettings.settings はそれをそのまま使う．
///
/// 項目は Google 日本語入力・ATOK・macOS の日本語入力・Microsoft IME の設定を調べ，
/// 日本語の入力に効くものを選んだ(docs/user/reference/settings.md に，入れなかった項目とその理由がある)
public struct Settings: Sendable, Equatable {
    // MARK: 入力
    /// 入力方式(R-05)
    public var inputStyle = InputStyle.romaji
    /// 英字を打つときのキーボードの配列(ローマ字入力・EN 入力で打つ英字がこの配列になる)
    public var keyboardLayout = KeyboardLayout.system
    /// 利用者が足したローマ字の綴り．標準の表に重ねる
    public var customRomaji: [RomajiRule] = []
    /// ライブ変換(R-01)
    public var liveConversion = true
    /// JIS キーボードの ¥ キーで入れる文字(R-04)
    public var yenKey = YenKeyPolicy.alwaysBackslash
    /// 句読点の組み合わせ
    public var punctuation = PunctuationStyle.toutenKuten
    /// [ ] で入れる括弧
    public var brackets = BracketStyle.corner
    /// / で入れる文字
    public var slash = SlashStyle.nakaguro
    /// 日本語のモードで Space を押したときの空白の幅．Shift+Space で逆の幅になる
    public var spaceWidth = CharacterWidth.halfwidth
    /// 日本語のモードで打った数字の幅
    public var numberWidth = CharacterWidth.halfwidth
    /// 句読点を打ったら，その句読点まで確定する
    public var punctuationCommits = false
    /// 変換しているとき(分岐図)のキーの割り当て
    public var conversionKeys = KeyBindings.standard

    // MARK: 変換
    /// 補正の強さ(R-02)
    public var typoCorrection = TypoCorrectionLevel.standard
    /// 候補の出し方(ADR 0007)
    public var candidatePresentation = CandidatePresentation.automatic
    /// 一覧の上に字種の行を出す(R-03)
    public var showsVariantRow = true
    /// 番号キーで候補を選ぶ
    public var numberKeySelection = true
    /// 「きょう」「いま」などを日付や時刻に変換する候補を出す
    public var dateConversion = true
    /// 「やじるし」などの読みから記号の候補を出す
    public var symbolConversion = true
    /// 読みから絵文字の候補を出す
    public var emojiConversion = true

    // MARK: 辞書と学習
    /// 確定した候補から学ぶか
    public var learning = LearningMode.enabled
    /// 利用者が登録した語
    public var userDictionary: [UserDictionaryEntry] = []
    /// 使い方を記録する(回数だけを端末の中に)
    public var recordsUsage = true

    // MARK: 見た目
    public var theme = ThemePreference.automatic
    public var candidateFontSize = 15.0
    /// 日本語と英数を切り替えたときに，入力位置の近くにモードを出す
    public var showsModeIndicator = true

    // MARK: アプリごと
    /// 組み立てていないときの Escape で英数に切り替える(Vim のノーマルモードに戻るとき．R-06)
    public var escapeSwitchesToDirect = false
    /// アプリの識別子(macOS はバンドル ID)の前方一致からプロファイルを決める規則．先にあるものを優先する
    public var profileRules: [ProfileRule] = DefaultSettings.terminalRules + DefaultSettings.programmingRules

    public init() {}

    public func profile(forApplication identifier: String?) -> AppProfile {
        guard let identifier else { return .standard }
        return profileRules.first { identifier.hasPrefix($0.applicationPrefix) }?.profile ?? .standard
    }
}

extension Settings: CustomStringConvertible, CustomDebugStringConvertible {
    // ユーザー辞書の語を含むので，ログには語の数だけを出す(docs/dev/SECURITY-MODEL.md)
    public var description: String { "Settings(userDictionary: \(userDictionary.count) 語)" }
    public var debugDescription: String { description }
}

/// 読めない要素を読み飛ばすための型．どんな値でも読める
private struct Skipped: Decodable {}

extension Settings: Codable {
    private enum CodingKeys: String, CodingKey {
        case inputStyle, keyboardLayout, customRomaji, liveConversion, yenKey, punctuation, brackets, slash, spaceWidth, numberWidth, punctuationCommits, conversionKeys
        case typoCorrection, candidatePresentation, showsVariantRow, numberKeySelection, dateConversion, symbolConversion, emojiConversion
        case learning, userDictionary, recordsUsage
        case theme, candidateFontSize, showsModeIndicator
        case escapeSwitchesToDirect, profileRules
    }

    /// 項目を足しても古い設定ファイルを読めるよう，無い項目と読めない項目は既定値のままにする
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var settings = Settings()
        func read<Value: Decodable>(_ key: CodingKeys, into keyPath: WritableKeyPath<Settings, Value>) {
            if let value = try? container.decodeIfPresent(Value.self, forKey: key) {
                settings[keyPath: keyPath] = value
            }
        }
        /// 一覧は 1 つずつ読み，読めないものだけを飛ばす．1 つの崩れた語で辞書全体を失わないため
        func readList<Element: Decodable>(_ key: CodingKeys, into keyPath: WritableKeyPath<Settings, [Element]>) {
            guard var list = try? container.nestedUnkeyedContainer(forKey: key) else { return }
            var values: [Element] = []
            while !list.isAtEnd {
                if let value = try? list.decode(Element.self) {
                    values.append(value)
                } else if (try? list.decode(Skipped.self)) == nil {
                    break
                }
            }
            settings[keyPath: keyPath] = values
        }
        read(.inputStyle, into: \.inputStyle)
        read(.keyboardLayout, into: \.keyboardLayout)
        readList(.customRomaji, into: \.customRomaji)
        read(.liveConversion, into: \.liveConversion)
        read(.yenKey, into: \.yenKey)
        read(.punctuation, into: \.punctuation)
        read(.brackets, into: \.brackets)
        read(.slash, into: \.slash)
        read(.spaceWidth, into: \.spaceWidth)
        read(.numberWidth, into: \.numberWidth)
        read(.punctuationCommits, into: \.punctuationCommits)
        read(.conversionKeys, into: \.conversionKeys)
        settings.conversionKeys = settings.conversionKeys.filled()
        read(.typoCorrection, into: \.typoCorrection)
        read(.candidatePresentation, into: \.candidatePresentation)
        read(.showsVariantRow, into: \.showsVariantRow)
        read(.numberKeySelection, into: \.numberKeySelection)
        read(.dateConversion, into: \.dateConversion)
        read(.symbolConversion, into: \.symbolConversion)
        read(.emojiConversion, into: \.emojiConversion)
        read(.learning, into: \.learning)
        readList(.userDictionary, into: \.userDictionary)
        read(.recordsUsage, into: \.recordsUsage)
        read(.theme, into: \.theme)
        read(.candidateFontSize, into: \.candidateFontSize)
        read(.showsModeIndicator, into: \.showsModeIndicator)
        read(.escapeSwitchesToDirect, into: \.escapeSwitchesToDirect)
        readList(.profileRules, into: \.profileRules)
        self = settings
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inputStyle, forKey: .inputStyle)
        try container.encode(keyboardLayout, forKey: .keyboardLayout)
        try container.encode(customRomaji, forKey: .customRomaji)
        try container.encode(liveConversion, forKey: .liveConversion)
        try container.encode(yenKey, forKey: .yenKey)
        try container.encode(punctuation, forKey: .punctuation)
        try container.encode(brackets, forKey: .brackets)
        try container.encode(slash, forKey: .slash)
        try container.encode(spaceWidth, forKey: .spaceWidth)
        try container.encode(numberWidth, forKey: .numberWidth)
        try container.encode(punctuationCommits, forKey: .punctuationCommits)
        try container.encode(conversionKeys, forKey: .conversionKeys)
        try container.encode(typoCorrection, forKey: .typoCorrection)
        try container.encode(candidatePresentation, forKey: .candidatePresentation)
        try container.encode(showsVariantRow, forKey: .showsVariantRow)
        try container.encode(numberKeySelection, forKey: .numberKeySelection)
        try container.encode(dateConversion, forKey: .dateConversion)
        try container.encode(symbolConversion, forKey: .symbolConversion)
        try container.encode(emojiConversion, forKey: .emojiConversion)
        try container.encode(learning, forKey: .learning)
        try container.encode(userDictionary, forKey: .userDictionary)
        try container.encode(recordsUsage, forKey: .recordsUsage)
        try container.encode(theme, forKey: .theme)
        try container.encode(candidateFontSize, forKey: .candidateFontSize)
        try container.encode(showsModeIndicator, forKey: .showsModeIndicator)
        try container.encode(escapeSwitchesToDirect, forKey: .escapeSwitchesToDirect)
        try container.encode(profileRules, forKey: .profileRules)
    }
}

public struct ProfileRule: Sendable, Equatable, Codable, Hashable {
    public var applicationPrefix: String
    public var profile: AppProfile

    public init(applicationPrefix: String, profile: AppProfile) {
        self.applicationPrefix = applicationPrefix
        self.profile = profile
    }
}

public enum ThemePreference: String, Sendable, Equatable, Codable, CaseIterable {
    /// ライトモードで platinum，ダークモードで desk
    case automatic
    case platinum
    case desk
    case native
}

/// タイプミスの補正の強さ(R-02)
public enum TypoCorrectionLevel: String, Sendable, Equatable, Codable, CaseIterable {
    case off
    /// ローマ字として読めない並びが英単語そのものだったときだけ直す(「pyてょn」→「python」)
    case conservative
    /// 綴りの誤りも直す(「pthon」→「python」)
    case standard
}

/// JIS キーボードの ¥ キーで入れる文字(R-04)
public enum YenKeyPolicy: String, Sendable, Equatable, Codable, CaseIterable {
    case alwaysBackslash
    case alwaysYen
    /// プログラミング用・ターミナルのプロファイルでだけ \
    case backslashInProgramming

    public static let backslash = "\\"
    public static let yen = "¥"

    /// Option を押しているときは逆の文字にする
    public func character(profile: AppProfile, optionPressed: Bool) -> String {
        let prefersBackslash: Bool = switch self {
        case .alwaysBackslash: true
        case .alwaysYen: false
        case .backslashInProgramming: profile.prefersHalfwidthSymbols
        }
        return prefersBackslash != optionPressed ? Self.backslash : Self.yen
    }
}
