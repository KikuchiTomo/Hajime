/// 利用者が変えられる設定．項目の既定値はここに書き，DefaultSettings.settings はそれをそのまま使う．
/// 項目の一覧は apps/docs-site/content/docs/settings.md
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
    /// 英字入力で，ローマ字として読める語を日本語にして見せる(英字入力のライブ変換．R-05)
    public var englishInputLiveConversion = false
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
    /// 読みがこの文字数以下のときはライブ変換しない(Space で変換する)．0 なら長さによらずライブ変換する
    public var liveConversionSkipLength = DefaultSettings.liveConversionSkipLength
    /// 英単語にしない読みの長さ(文字)．ローマ字として読んだかながこの文字数以下なら，英単語の綴りでも日本語として読む．0 は長さで区別しない
    public var englishSkipLength = DefaultSettings.englishSkipLength
    /// 打鍵が止まってから打ち間違いを見直すまでの時間(秒)
    public var correctionDelay = DefaultSettings.liveCorrectionDelay
    /// 打鍵が止まって見直すときに，打ち間違いを探す時間の上限(秒)．過ぎたらその入力は見直さない
    public var reviewCorrectionTimeout = DefaultSettings.reviewCorrectionTimeout
    /// Space で変換したあとに，打ち間違いを探す時間の上限(秒)．過ぎたら補正をあきらめ，変換はそのまま
    public var lateCorrectionTimeout = DefaultSettings.lateCorrectionTimeout
    /// 補正を Esc で戻した語句を「直さない語句」に覚え，次から直さない
    public var remembersRejectedCorrections = false
    /// 打ち間違いを直す基準
    public var correctionSensitivity = CorrectionSensitivity.standard
    /// 直すほど確かでないとき，「もしかして」と示す
    public var showsSuggestions = true
    /// 打ち間違いの補正のうち，誤りの種類ごとのオン・オフ，直さない語，置き換えの決まり
    public var correction = CorrectionCustomization()
    /// 英字で打った語を英語にするか日本語にするかの見分け方(英字入力(自動)とローマ字入力の英単語)
    public var wordLanguage = WordLanguageSettings()
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
    /// 手の置き場所が横にずれたまま打った並びを直す(HandShift．試験的)
    public var handShiftCorrection = false
    /// うろ覚えで読みを少し違えた外来語(しゅみれーしょん → シミュレーション)を候補に出す(LooseReadings)
    public var looseReadings = false
    /// 発音どおりに綴った英単語(foto → photo)を候補に出す(PhoneticSpelling)
    public var phoneticSpelling = false
    /// ユーザー辞書の語の `{datetime:...}` などを，入れるときの値に置き換える(TextTemplate)
    public var dynamicDictionary = false
    /// 連想変換のキーで出す一覧に，選んでいる語を整えた形(変換マクロ)を並べる
    public var conversionMacros = false
    public var macros: [ConversionMacro] = DefaultSettings.conversionMacros
    /// 読みで呼び出すコマンド(ランチャー)を使う．同期しない(SyncGroup.commands)
    public var launcherCommands = false
    public var commands: [LauncherCommand] = []
    /// かなで打った外来語は，英語のつづり(「Live変換」)よりカタカナ(「ライブ変換」)を先に出す
    public var prefersKatakana = true
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
    /// 読み(「らむだ」)から LaTeX のコマンド(「\lambda」)の候補を出す
    public var latexConversion = false
    /// 連想変換(R-18)．オフなら連想変換のキーはふつうの変換と同じに動く
    public var association = true
    /// 連想の一覧に出す語の数
    public var associationLimit = DefaultSettings.associationLimit
    /// 選んでいる候補に連想があるとき，候補の窓の足元に知らせる
    public var showsAssociationHint = true

    /// かな漢字変換に使う Zenzai のモデル
    public var zenzaiModel = ZenzaiModelChoice.accurate

    // MARK: 辞書と学習
    /// 確定した候補から学ぶか
    public var learning = LearningMode.enabled
    /// 利用者が登録した語
    public var userDictionary: [UserDictionaryEntry] = []
    /// 取り込んだ辞書．並び順が優先度．語は Application Support の dictionaries/ にある索引のファイルに置く
    public var importedDictionaries: [ImportedDictionary] = []
    /// 取り込んだ連想の辞書(R-18)．並び順が優先度．語は Application Support の associations/ にある索引のファイルに置く
    public var associationDictionaries: [AssociationDictionary] = [DefaultSettings.bundledAssociationDictionary]
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
    /// 読み込んだファイルの形式のバージョン(SettingsSchema)．今より新しいバージョンのファイルを開いたときは，そのバージョンのまま書き戻す
    public var schemaVersion = SettingsSchema.currentVersion
    /// このバージョンが知らない項目．新しいバージョンで書いた設定を古いバージョンで開いて保存しても失わないよう，そのまま書き戻す
    public var unknownFields: [String: JSONValue] = [:]

    public init() {}

    /// この長さの読みをライブ変換するか(ライブ変換がオンで，ライブ変換しない長さより長い)
    public func liveConverts(readingLength: Int) -> Bool {
        liveConversion && readingLength > liveConversionSkipLength
    }

    /// 範囲の外の値を範囲に収め，使えない値を捨てる．設定のファイルや書き出した JSON を読むときに通す
    /// (手で書き換えたファイルや別のバージョンのファイルでも，画面や変換がおかしくならないように)
    public mutating func clampToValidRanges() {
        func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T { min(max(value, range.lowerBound), range.upperBound) }
        listCandidatesPerPage = clamp(listCandidatesPerPage, DefaultSettings.candidatesPerPageRange)
        branchCandidatesPerPage = clamp(branchCandidatesPerPage, DefaultSettings.candidatesPerPageRange)
        associationLimit = clamp(associationLimit, DefaultSettings.associationLimitRange)
        var associationIDs = Set<String>()
        associationDictionaries = associationDictionaries.filter { $0.hasValidIdentity && associationIDs.insert($0.id).inserted }
            // 同梱の辞書は 1 つだけで，一覧から外れていたら先頭に戻す(消せない．使わないときはオフにする)
            .filter { $0.isBundled == ($0.id == DefaultSettings.bundledAssociationDictionary.id) }
        if !associationDictionaries.contains(where: \.isBundled) {
            associationDictionaries.insert(DefaultSettings.bundledAssociationDictionary, at: 0)
        }
        associationDictionaries = Array(associationDictionaries.prefix(DefaultSettings.maximumAssociationDictionaries))
        liveConversionSkipLength = clamp(liveConversionSkipLength, DefaultSettings.liveConversionSkipLengthRange)
        englishSkipLength = clamp(englishSkipLength, DefaultSettings.englishSkipLengthRange)
        liveConversionDelay = clamp(liveConversionDelay.isFinite ? liveConversionDelay : DefaultSettings.liveConversionSettleDelay, DefaultSettings.liveConversionDelayRange)
        correctionDelay = clamp(correctionDelay.isFinite ? correctionDelay : DefaultSettings.liveCorrectionDelay, DefaultSettings.correctionDelayRange)
        correctionDelay = max(correctionDelay, liveConversionDelay)
        reviewCorrectionTimeout = clamp(reviewCorrectionTimeout.isFinite ? reviewCorrectionTimeout : DefaultSettings.reviewCorrectionTimeout, DefaultSettings.reviewCorrectionTimeoutRange)
        lateCorrectionTimeout = clamp(lateCorrectionTimeout.isFinite ? lateCorrectionTimeout : DefaultSettings.lateCorrectionTimeout, DefaultSettings.lateCorrectionTimeoutRange)
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
        var macroIDs = Set<String>()
        macros = Array(macros.filter { $0.isValid && macroIDs.insert($0.id).inserted }.prefix(DefaultSettings.maximumMacros))
        var commandIDs = Set<String>()
        commands = Array(commands.filter { $0.isValid && commandIDs.insert($0.id).inserted }.prefix(DefaultSettings.maximumCommands))
        keymap.clampToValidRanges()
        wordLanguage.clampToValidRanges()
    }

    /// コマンド(SyncGroup.commands の項目)だけを current のものにした設定．
    /// 設定のファイルの読み込みや，設定の画面でない接続からの書き込みで，コマンドを書き換えさせないために使う
    public func keepingCommands(of current: Settings) -> Settings {
        var result = self
        result.launcherCommands = current.launcherCommands
        result.commands = current.commands
        return result
    }

    /// 使っているカスタムテーマ．選んでいなければ nil
    public var activeCustomTheme: CustomTheme? {
        customThemeID.flatMap { id in customThemes.first { $0.id == id } }
    }

    /// アプリの入力の扱い(記号を半角・コマンドを英字・IME を使わない)．決まりが無ければ標準
    public func profile(forApplication identifier: String?) -> AppProfile {
        rule(forApplication: identifier) { !$0.setsModeOnFocus }?.profile ?? .standard
    }

    /// 入力先をアプリに移したときのモードの扱い(IME をオフ・オン・オンオフを記憶)．決まりが無ければ標準(切り替えない)
    public func modeProfile(forApplication identifier: String?) -> AppProfile {
        rule(forApplication: identifier) { $0.setsModeOnFocus }?.profile ?? .standard
    }

    /// アプリに合う決まりのうち，いちばん上のもの．
    /// 大文字と小文字は区別しない．Windows の実行ファイルの名前は書き方がそろわない(WindowsTerminal.exe と windowsterminal.exe)
    private func rule(forApplication identifier: String?, where kind: (AppProfile) -> Bool) -> ProfileRule? {
        guard let identifier = identifier?.lowercased() else { return nil }
        return profileRules.first { kind($0.profile) && identifier.hasPrefix($0.applicationPrefix.lowercased()) }
    }
}

extension Settings: CustomStringConvertible, CustomDebugStringConvertible {
    // ユーザー辞書の語を含むので，ログには語の数だけを出す(docs/dev/SECURITY-MODEL.md)
    public var description: String { "Settings(userDictionary: \(userDictionary.count) 語, commands: \(commands.count))" }
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
        case inputStyle, keyboardLayout, customRomaji, liveConversion, englishInputLiveConversion, wordLanguage, yenKey, punctuation, brackets, slash, spaceWidth, numberWidth, punctuationCommits, keymap
        case keypadDirect, symbolRules, correction, okuriganaStyle, calculation, postalCodeConversion, handwriting, misreadings, prefersKatakana
        case alphabetWidth, shiftStartsAlphabet, listCandidatesPerPage, branchCandidatesPerPage, liveConversionDelay, liveConversionSkipLength, englishSkipLength, correctionDelay
        case correctionSensitivity, showsSuggestions, modeIndicatorDuration, customThemes, customThemeID, terminalCommands
        case reviewCorrectionTimeout, lateCorrectionTimeout, remembersRejectedCorrections
        case typoCorrection, candidatePresentation, initialFocus, suggestionDisplay, showsVariantRow, showsKeyHints, numberKeySelection, dateConversion, homophoneNotes, misuseNotes, proofreading, symbolConversion, emojiConversion, latexConversion
        case association, associationLimit, showsAssociationHint, zenzaiModel
        case learning, userDictionary, importedDictionaries, associationDictionaries, recordsUsage
        case theme, candidateFontSize, showsModeIndicator
        case escapeSwitchesToDirect, restrainsLiveConversionInCode, profileRules
        case handShiftCorrection, looseReadings, phoneticSpelling, dynamicDictionary, conversionMacros, macros, launcherCommands, commands
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
        read(.englishInputLiveConversion, into: \.englishInputLiveConversion)
        read(.wordLanguage, into: \.wordLanguage)
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
        read(.prefersKatakana, into: \.prefersKatakana)
        read(.alphabetWidth, into: \.alphabetWidth)
        read(.shiftStartsAlphabet, into: \.shiftStartsAlphabet)
        read(.listCandidatesPerPage, into: \.listCandidatesPerPage)
        read(.branchCandidatesPerPage, into: \.branchCandidatesPerPage)
        read(.liveConversionDelay, into: \.liveConversionDelay)
        read(.liveConversionSkipLength, into: \.liveConversionSkipLength)
        read(.englishSkipLength, into: \.englishSkipLength)
        read(.correctionDelay, into: \.correctionDelay)
        read(.correctionSensitivity, into: \.correctionSensitivity)
        read(.reviewCorrectionTimeout, into: \.reviewCorrectionTimeout)
        read(.lateCorrectionTimeout, into: \.lateCorrectionTimeout)
        read(.remembersRejectedCorrections, into: \.remembersRejectedCorrections)
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
        read(.latexConversion, into: \.latexConversion)
        read(.association, into: \.association)
        read(.associationLimit, into: \.associationLimit)
        read(.showsAssociationHint, into: \.showsAssociationHint)
        read(.zenzaiModel, into: \.zenzaiModel)
        read(.learning, into: \.learning)
        readList(.userDictionary, into: \.userDictionary)
        readList(.importedDictionaries, into: \.importedDictionaries)
        // 同期のファイルから来た設定でもファイルの名前に使うので，形の違う id は捨てる
        settings.importedDictionaries.removeAll { !$0.hasValidIdentity }
        readList(.associationDictionaries, into: \.associationDictionaries)
        read(.recordsUsage, into: \.recordsUsage)
        read(.theme, into: \.theme)
        read(.candidateFontSize, into: \.candidateFontSize)
        read(.showsModeIndicator, into: \.showsModeIndicator)
        read(.escapeSwitchesToDirect, into: \.escapeSwitchesToDirect)
        read(.restrainsLiveConversionInCode, into: \.restrainsLiveConversionInCode)
        readList(.profileRules, into: \.profileRules)
        read(.handShiftCorrection, into: \.handShiftCorrection)
        read(.looseReadings, into: \.looseReadings)
        read(.phoneticSpelling, into: \.phoneticSpelling)
        read(.dynamicDictionary, into: \.dynamicDictionary)
        read(.conversionMacros, into: \.conversionMacros)
        readList(.macros, into: \.macros)
        read(.launcherCommands, into: \.launcherCommands)
        readList(.commands, into: \.commands)
        // 形式のバージョンと，このバージョンが知らない項目
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
        try container.encode(englishInputLiveConversion, forKey: .englishInputLiveConversion)
        try container.encode(wordLanguage, forKey: .wordLanguage)
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
        try container.encode(prefersKatakana, forKey: .prefersKatakana)
        try container.encode(alphabetWidth, forKey: .alphabetWidth)
        try container.encode(shiftStartsAlphabet, forKey: .shiftStartsAlphabet)
        try container.encode(listCandidatesPerPage, forKey: .listCandidatesPerPage)
        try container.encode(branchCandidatesPerPage, forKey: .branchCandidatesPerPage)
        try container.encode(liveConversionDelay, forKey: .liveConversionDelay)
        try container.encode(liveConversionSkipLength, forKey: .liveConversionSkipLength)
        try container.encode(englishSkipLength, forKey: .englishSkipLength)
        try container.encode(correctionDelay, forKey: .correctionDelay)
        try container.encode(correctionSensitivity, forKey: .correctionSensitivity)
        try container.encode(reviewCorrectionTimeout, forKey: .reviewCorrectionTimeout)
        try container.encode(lateCorrectionTimeout, forKey: .lateCorrectionTimeout)
        try container.encode(remembersRejectedCorrections, forKey: .remembersRejectedCorrections)
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
        try container.encode(latexConversion, forKey: .latexConversion)
        try container.encode(association, forKey: .association)
        try container.encode(associationLimit, forKey: .associationLimit)
        try container.encode(showsAssociationHint, forKey: .showsAssociationHint)
        try container.encode(zenzaiModel, forKey: .zenzaiModel)
        try container.encode(learning, forKey: .learning)
        try container.encode(userDictionary, forKey: .userDictionary)
        try container.encode(importedDictionaries, forKey: .importedDictionaries)
        try container.encode(associationDictionaries, forKey: .associationDictionaries)
        try container.encode(recordsUsage, forKey: .recordsUsage)
        try container.encode(theme, forKey: .theme)
        try container.encode(candidateFontSize, forKey: .candidateFontSize)
        try container.encode(showsModeIndicator, forKey: .showsModeIndicator)
        try container.encode(escapeSwitchesToDirect, forKey: .escapeSwitchesToDirect)
        try container.encode(restrainsLiveConversionInCode, forKey: .restrainsLiveConversionInCode)
        try container.encode(profileRules, forKey: .profileRules)
        try container.encode(handShiftCorrection, forKey: .handShiftCorrection)
        try container.encode(looseReadings, forKey: .looseReadings)
        try container.encode(phoneticSpelling, forKey: .phoneticSpelling)
        try container.encode(dynamicDictionary, forKey: .dynamicDictionary)
        try container.encode(conversionMacros, forKey: .conversionMacros)
        try container.encode(macros, forKey: .macros)
        try container.encode(launcherCommands, forKey: .launcherCommands)
        try container.encode(commands, forKey: .commands)
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

    /// ¥ キーが配列の設定で入れる文字が，この設定で選べる文字(¥ か \\)か．
    /// 選べる文字のときだけ設定で決め，Shift などで配列が別の文字(JIS 配列の Shift+¥ の |)を入れるときは，その文字をそのまま使う
    public static func isChoosable(_ text: String) -> Bool {
        text == backslash || text == yen
    }

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
