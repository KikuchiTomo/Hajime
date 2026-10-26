/// 利用者が変えられる設定．項目の既定値はここに書き，DefaultSettings.settings はそれをそのまま使う．
/// 項目の一覧は docs/user/reference/settings.md
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
    /// 日本語のモードで Shift を押して打った英字の幅
    public var alphabetWidth = CharacterWidth.halfwidth
    /// Shift を押して英字を打ったら，Space か記号を打つまで英字のまま入れる(「Python」と打てる)
    public var shiftStartsAlphabet = false
    /// 句読点を打ったら，その句読点まで確定する
    public var punctuationCommits = false
    /// キー設定の表(R-17)．状態 × キー × コマンドの行．切り替えのキーも変換中のキーもここに書く
    public var keymap = KeymapPreset.standard.keymap
    /// テンキーで打った数字と記号は，日本語のモードでも半角で，組み立てずにそのまま確定する
    public var keypadDirect = true
    /// 利用者が変えた記号の決まり(「->」→「→」，「やじるし」→「→」)．既定の決まりに重ねる
    public var symbolRules: [SymbolRule] = []

    // MARK: 変換
    /// 補正の強さ(R-02)
    public var typoCorrection = TypoCorrectionLevel.standard
    /// 候補の出し方(ADR 0007)
    public var candidatePresentation = CandidatePresentation.automatic
    /// Space で変換したときに最初に選ぶ文節
    public var initialFocus = InitialFocus.start
    /// 打っているあいだに候補の窓を出すか
    public var suggestionDisplay = SuggestionDisplay.whenLiveConversionOff
    /// 一覧の 1 ページの候補の数
    public var listCandidatesPerPage = DefaultSettings.candidatesPerPage
    /// 分岐図の下の枝に出す候補の数
    public var branchCandidatesPerPage = DefaultSettings.latticeCandidatesPerSegment
    /// ライブ変換で，打鍵が止まってから漢字にするまでの時間(秒)
    public var liveConversionDelay = DefaultSettings.liveConversionSettleDelay
    /// 打鍵が止まってから打ち間違いを見直すまでの時間(秒)
    public var correctionDelay = DefaultSettings.liveCorrectionDelay
    /// 打ち間違いを直す基準
    public var correctionSensitivity = CorrectionSensitivity.standard
    /// 直すほど確かでないとき，「もしかして」と示す
    public var showsSuggestions = true
    /// 打ち間違いの補正のうち，誤りの種類ごとのオン・オフ，直さない語，置き換えの決まり
    public var correction = CorrectionCustomization()
    /// 送り仮名の付け方(本則・許容)のどちらを先に出すか
    public var okuriganaStyle = OkuriganaStyle.standard
    /// 「1+2*3=」のような式を計算した結果を候補に出す
    public var calculation = true
    /// 郵便番号(「100-0001」)から住所を候補に出す
    public var postalCodeConversion = true
    /// 手書きで文字を探す窓を使う(キー操作の「手書き」で開く)
    public var handwriting = false
    /// よくある読み違い(「ふいんき」→ 雰囲気)の正しい語を候補に出し，「もしかして」で示す
    public var misreadings = true
    /// 一覧の上に字種の行を出す(R-03)
    public var showsVariantRow = true
    /// 分岐図の足元にキーの案内(候補・文節・文節の長さ・区切り)を出す
    public var showsKeyHints = true
    /// 番号キーで候補を選ぶ
    public var numberKeySelection = true
    /// 「きょう」「いま」などを日付や時刻に変換する候補を出す
    public var dateConversion = true
    /// 同音異義語の使い分けを分岐図に添える
    public var homophoneNotes = true
    /// 誤用とされる言い回しに注釈を添える
    public var misuseNotes = false
    /// ら抜き言葉・さ入れ言葉・二重敬語・重言に注釈を添える(校正支援)
    public var proofreading = true
    /// 「やじるし」などの読みから記号の候補を出す
    public var symbolConversion = true
    /// 読みから絵文字の候補を出す
    public var emojiConversion = true

    // MARK: 辞書と学習
    /// 確定した候補から学ぶか
    public var learning = LearningMode.enabled
    /// 利用者が登録した語
    public var userDictionary: [UserDictionaryEntry] = []
    /// 取り込んだ辞書．並び順が優先度．語は Application Support の dictionaries/ にある索引のファイルに置く
    public var importedDictionaries: [ImportedDictionary] = []
    /// 使い方を記録する(回数だけを端末の中に)
    public var recordsUsage = true

    // MARK: 見た目
    public var theme = ThemePreference.automatic
    public var candidateFontSize = 15.0
    /// 日本語と英数を切り替えたときに，入力位置の近くにモードを出す
    public var showsModeIndicator = true
    /// モードの表示を出しておく時間(秒)
    public var modeIndicatorDuration = 0.8
    /// 保存したカスタムテーマ
    public var customThemes: [CustomTheme] = []
    /// 使っているカスタムテーマの ID．nil なら theme の既成のテーマ
    public var customThemeID: String?

    // MARK: アプリごと
    /// 組み立てていないときの Escape で英数に切り替える(Vim のノーマルモードに戻るとき．R-06)
    public var escapeSwitchesToDirect = false
    /// ターミナルで，行の頭のコマンドの名前を英字のまま入れる(R-07)
    public var terminalCommands = true
    /// エディタとターミナルでライブ変換を控えめにする(R-06)．打鍵が止まるまで読みのまま見せ，英数字を打っているあいだは変換しない
    public var restrainsLiveConversionInCode = true
    /// アプリの識別子(macOS はバンドル ID)の前方一致からプロファイルを決める規則．先にあるものを優先する
    public var profileRules: [ProfileRule] = DefaultSettings.terminalRules + DefaultSettings.programmingRules

    // MARK: 形式
    /// 読み込んだファイルの形式の版(SettingsSchema)．今より新しい版のファイルを開いたときは，その版のまま書き戻す
    public var schemaVersion = SettingsSchema.currentVersion
    /// この版が知らない項目．新しい版で書いた設定を古い版で開いて保存しても失わないよう，そのまま書き戻す
    public var unknownFields: [String: JSONValue] = [:]

    public init() {}

    /// 範囲の外の値を範囲に収め，使えない値を捨てる．設定のファイルや書き出した JSON を読むときに通す
    /// (手で書き換えたファイルや別の版のファイルでも，画面や変換がおかしくならないように)
    public mutating func clampToValidRanges() {
        func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T { min(max(value, range.lowerBound), range.upperBound) }
        listCandidatesPerPage = clamp(listCandidatesPerPage, DefaultSettings.candidatesPerPageRange)
        branchCandidatesPerPage = clamp(branchCandidatesPerPage, DefaultSettings.candidatesPerPageRange)
        liveConversionDelay = clamp(liveConversionDelay.isFinite ? liveConversionDelay : DefaultSettings.liveConversionSettleDelay, DefaultSettings.liveConversionDelayRange)
        correctionDelay = clamp(correctionDelay.isFinite ? correctionDelay : DefaultSettings.liveCorrectionDelay, DefaultSettings.correctionDelayRange)
        correctionDelay = max(correctionDelay, liveConversionDelay)
        modeIndicatorDuration = clamp(modeIndicatorDuration.isFinite ? modeIndicatorDuration : 0.8, DefaultSettings.modeIndicatorDurationRange)
        candidateFontSize = clamp(candidateFontSize.isFinite ? candidateFontSize : 15, DefaultSettings.candidateFontSizeRange)
        var themeIDs = Set<String>()
        customThemes = Array(customThemes.filter { $0.isValid && themeIDs.insert($0.id).inserted }.prefix(DefaultSettings.maximumCustomThemes))
        if activeCustomTheme == nil { customThemeID = nil }
        var symbolKeys = Set<String>()
        // 同じ入力の決まりは後のものを残す
        symbolRules = Array(symbolRules.reversed().filter { $0.isValid && symbolKeys.insert("\($0.kind.rawValue):\($0.input)").inserted }.reversed()
            .prefix(DefaultSettings.maximumSymbolRules))
        correction.rules = Array(correction.rules.filter(\.isValid).prefix(DefaultSettings.maximumCorrectionRules))
        correction.exceptions = Array(correction.exceptions.filter(RuleListEditing.isValidException).prefix(DefaultSettings.maximumCorrectionRules))
        profileRules = Array(profileRules.filter { ProfileRuleCSV.isValidIdentifier($0.applicationPrefix) }.prefix(DefaultSettings.maximumProfileRules))
        keymap.clampToValidRanges()
    }

    /// 使っているカスタムテーマ．選んでいなければ nil
    public var activeCustomTheme: CustomTheme? {
        customThemeID.flatMap { id in customThemes.first { $0.id == id } }
    }

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

/// 名前の決まっていない項目を読み書きするための鍵
private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension Settings: Codable {
    /// 設定のファイルの項目の名前．同期の範囲(SyncGroup)もこの名前で決める
    public static var fieldNames: Set<String> { Set(CodingKeys.allCases.map(\.rawValue)) }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case inputStyle, keyboardLayout, customRomaji, liveConversion, yenKey, punctuation, brackets, slash, spaceWidth, numberWidth, punctuationCommits, keymap
        case keypadDirect, symbolRules, correction, okuriganaStyle, calculation, postalCodeConversion, handwriting, misreadings
        case alphabetWidth, shiftStartsAlphabet, listCandidatesPerPage, branchCandidatesPerPage, liveConversionDelay, correctionDelay
        case correctionSensitivity, showsSuggestions, modeIndicatorDuration, customThemes, customThemeID, terminalCommands
        case typoCorrection, candidatePresentation, initialFocus, suggestionDisplay, showsVariantRow, showsKeyHints, numberKeySelection, dateConversion, homophoneNotes, misuseNotes, proofreading, symbolConversion, emojiConversion
        case learning, userDictionary, importedDictionaries, recordsUsage
        case theme, candidateFontSize, showsModeIndicator
        case escapeSwitchesToDirect, restrainsLiveConversionInCode, profileRules
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
        read(.keymap, into: \.keymap)
        read(.keypadDirect, into: \.keypadDirect)
        readList(.symbolRules, into: \.symbolRules)
        read(.correction, into: \.correction)
        read(.okuriganaStyle, into: \.okuriganaStyle)
        read(.calculation, into: \.calculation)
        read(.postalCodeConversion, into: \.postalCodeConversion)
        read(.handwriting, into: \.handwriting)
        read(.misreadings, into: \.misreadings)
        read(.alphabetWidth, into: \.alphabetWidth)
        read(.shiftStartsAlphabet, into: \.shiftStartsAlphabet)
        read(.listCandidatesPerPage, into: \.listCandidatesPerPage)
        read(.branchCandidatesPerPage, into: \.branchCandidatesPerPage)
        read(.liveConversionDelay, into: \.liveConversionDelay)
        read(.correctionDelay, into: \.correctionDelay)
        read(.correctionSensitivity, into: \.correctionSensitivity)
        read(.showsSuggestions, into: \.showsSuggestions)
        read(.modeIndicatorDuration, into: \.modeIndicatorDuration)
        readList(.customThemes, into: \.customThemes)
        read(.customThemeID, into: \.customThemeID)
        read(.terminalCommands, into: \.terminalCommands)
        read(.typoCorrection, into: \.typoCorrection)
        read(.candidatePresentation, into: \.candidatePresentation)
        read(.initialFocus, into: \.initialFocus)
        read(.suggestionDisplay, into: \.suggestionDisplay)
        read(.showsVariantRow, into: \.showsVariantRow)
        read(.showsKeyHints, into: \.showsKeyHints)
        read(.numberKeySelection, into: \.numberKeySelection)
        read(.dateConversion, into: \.dateConversion)
        read(.homophoneNotes, into: \.homophoneNotes)
        read(.misuseNotes, into: \.misuseNotes)
        read(.proofreading, into: \.proofreading)
        read(.symbolConversion, into: \.symbolConversion)
        read(.emojiConversion, into: \.emojiConversion)
        read(.learning, into: \.learning)
        readList(.userDictionary, into: \.userDictionary)
        readList(.importedDictionaries, into: \.importedDictionaries)
        // 同期のファイルから来た設定でもファイルの名前に使うので，形の違う id は捨てる
        settings.importedDictionaries.removeAll { !$0.hasValidIdentity }
        read(.recordsUsage, into: \.recordsUsage)
        read(.theme, into: \.theme)
        read(.candidateFontSize, into: \.candidateFontSize)
        read(.showsModeIndicator, into: \.showsModeIndicator)
        read(.escapeSwitchesToDirect, into: \.escapeSwitchesToDirect)
        read(.restrainsLiveConversionInCode, into: \.restrainsLiveConversionInCode)
        readList(.profileRules, into: \.profileRules)
        // 形式の版と，この版が知らない項目
        let others = try decoder.container(keyedBy: AnyKey.self)
        if let version = try? others.decodeIfPresent(Int.self, forKey: AnyKey(stringValue: SettingsSchema.versionKey)) {
            settings.schemaVersion = max(version, SettingsSchema.currentVersion)
        }
        let known = Self.fieldNames.union([SettingsSchema.versionKey])
        for key in others.allKeys where !known.contains(key.stringValue) {
            if let value = try? others.decode(JSONValue.self, forKey: key) { settings.unknownFields[key.stringValue] = value }
        }
        settings.clampToValidRanges()
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
        try container.encode(keymap, forKey: .keymap)
        try container.encode(keypadDirect, forKey: .keypadDirect)
        try container.encode(symbolRules, forKey: .symbolRules)
        try container.encode(correction, forKey: .correction)
        try container.encode(okuriganaStyle, forKey: .okuriganaStyle)
        try container.encode(calculation, forKey: .calculation)
        try container.encode(postalCodeConversion, forKey: .postalCodeConversion)
        try container.encode(handwriting, forKey: .handwriting)
        try container.encode(misreadings, forKey: .misreadings)
        try container.encode(alphabetWidth, forKey: .alphabetWidth)
        try container.encode(shiftStartsAlphabet, forKey: .shiftStartsAlphabet)
        try container.encode(listCandidatesPerPage, forKey: .listCandidatesPerPage)
        try container.encode(branchCandidatesPerPage, forKey: .branchCandidatesPerPage)
        try container.encode(liveConversionDelay, forKey: .liveConversionDelay)
        try container.encode(correctionDelay, forKey: .correctionDelay)
        try container.encode(correctionSensitivity, forKey: .correctionSensitivity)
        try container.encode(showsSuggestions, forKey: .showsSuggestions)
        try container.encode(modeIndicatorDuration, forKey: .modeIndicatorDuration)
        try container.encode(customThemes, forKey: .customThemes)
        try container.encodeIfPresent(customThemeID, forKey: .customThemeID)
        try container.encode(terminalCommands, forKey: .terminalCommands)
        try container.encode(typoCorrection, forKey: .typoCorrection)
        try container.encode(candidatePresentation, forKey: .candidatePresentation)
        try container.encode(initialFocus, forKey: .initialFocus)
        try container.encode(suggestionDisplay, forKey: .suggestionDisplay)
        try container.encode(showsVariantRow, forKey: .showsVariantRow)
        try container.encode(showsKeyHints, forKey: .showsKeyHints)
        try container.encode(numberKeySelection, forKey: .numberKeySelection)
        try container.encode(dateConversion, forKey: .dateConversion)
        try container.encode(homophoneNotes, forKey: .homophoneNotes)
        try container.encode(misuseNotes, forKey: .misuseNotes)
        try container.encode(proofreading, forKey: .proofreading)
        try container.encode(symbolConversion, forKey: .symbolConversion)
        try container.encode(emojiConversion, forKey: .emojiConversion)
        try container.encode(learning, forKey: .learning)
        try container.encode(userDictionary, forKey: .userDictionary)
        try container.encode(importedDictionaries, forKey: .importedDictionaries)
        try container.encode(recordsUsage, forKey: .recordsUsage)
        try container.encode(theme, forKey: .theme)
        try container.encode(candidateFontSize, forKey: .candidateFontSize)
        try container.encode(showsModeIndicator, forKey: .showsModeIndicator)
        try container.encode(escapeSwitchesToDirect, forKey: .escapeSwitchesToDirect)
        try container.encode(restrainsLiveConversionInCode, forKey: .restrainsLiveConversionInCode)
        try container.encode(profileRules, forKey: .profileRules)
        var others = encoder.container(keyedBy: AnyKey.self)
        try others.encode(max(schemaVersion, SettingsSchema.currentVersion), forKey: AnyKey(stringValue: SettingsSchema.versionKey))
        for (key, value) in unknownFields where !Self.fieldNames.contains(key) && key != SettingsSchema.versionKey {
            try others.encode(value, forKey: AnyKey(stringValue: key))
        }
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
    /// 標準(すりガラス．ライトとダークに合わせる)
    case automatic
    case platinum
    case desk
    /// 以前の値．標準と同じに読む
    case native
    case washi
    case neon
    case terminal
    case nordic
    case contrast
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
