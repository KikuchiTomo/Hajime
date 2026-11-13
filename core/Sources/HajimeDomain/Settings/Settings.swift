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
    /// 数字のあとの「.」「,」を句読点にせず，ピリオドとカンマで入れる(「3.14」「1,000」)．幅は直前の数字に合わせる
    public var numberSeparators = true
    /// 英数字のあとの「-」を長音にせず，ハイフンで入れる(「A-1」「3-4」)．読みの先頭の「-」に数字を続けたとき(「-3」)も
    public var alphanumericHyphen = true
    /// 句読点を打ったら，その句読点まで確定する
    public var punctuationCommits = false
    /// ？ と ！ を打ったら，その記号まで確定する
    public var questionExclamationCommits = false
    /// キー設定の表(R-17)．状態 × キー × コマンドの行．切り替えのキーも変換中のキーもここに書く
    public var keymap = KeymapPreset.standard.keymap
    /// テンキーで打った数字と記号は，日本語のモードでも半角で，組み立てずにそのまま確定する
    public var keypadDirect = true
    /// テンキーの数字と記号を半角のまま読みに入れ，テンキーの Enter で式を計算する(計算の結果を第 1 候補にして変換する)．
    /// オンのときは keypadDirect の「そのまま確定」より先に効く
    public var keypadCalculation = false
    /// 英数に変えるキー(F9・F10 など)を続けて押すと，英字を 入力どおり → 大文字 → 小文字 → 先頭だけ大文字 の順に変える
    public var cyclesLetterCase = true
    /// 利用者が変えた記号の決まり(「->」→「→」，「やじるし」→「→」)．既定の決まりに重ねる
    public var symbolRules: [SymbolRule] = []

    // MARK: 変換
    /// 補正の強さ(R-02)
    public var typoCorrection = TypoCorrectionLevel.standard
    /// 候補の出し方(ADR 0007)
    public var candidatePresentation = CandidatePresentation.automatic
    /// Space で変換したときに最初に選ぶ文節
    public var initialFocus = InitialFocus.start
    /// 打っているあいだに，読みを変換した候補の窓を出すか
    public var suggestionDisplay = SuggestionDisplay.whenLiveConversionOff
    /// 打っているあいだに，打っている語句に続く予測を，変換の候補とは別の小さな窓に出すか
    public var predictionDisplay = SuggestionDisplay.whenLiveConversionOff
    /// 入力中の候補がこの件数以下なら窓を出さない．0 なら候補があれば出す
    public var suggestionSkipCount = 0
    /// 入力中の予測で，確定した履歴(学習)にある語句を先に出すか
    public var predictionPrefersHistory = true
    /// 打ち間違いを直した読み(直して見せている読みと「もしかして」と示した読み)からも予測するか．オフなら直しているあいだは予測を出さない
    public var predictionFromCorrection = true
    /// 予測に表示しない語句．入力中の予測の窓に出した語句をキー(キー設定の表の「予測に表示しない」)で足し，設定の画面で消せる
    public var hiddenPredictions: [String] = []
    /// 一覧の 1 ページの候補の数
    public var listCandidatesPerPage = DefaultSettings.candidatesPerPage
    /// 分岐図の下の枝に出す候補の数
    public var branchCandidatesPerPage = DefaultSettings.latticeCandidatesPerSegment
    /// 候補を表に広げたとき(キー設定の表の「候補を表に広げる」)の列の数．1 列の行の数は一覧の候補の数
    public var candidateGridColumns = DefaultSettings.candidateGridColumns
    /// 候補を送り続けて最初のページを越えたら，候補を表に広げる(目当ての候補が最初のページに無かったので，まとめて見せる)
    public var expandsGridOnPaging = false
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
    /// 絵文字と記号のパレットを使う(キー操作の「絵文字のパレット」「記号のパレット」で開く．R-26)
    public var palette = true
    /// パレットで文字を入れたら閉じる．⇧Enter はこの設定によらず閉じずに続けて入れる
    public var paletteClosesAfterInsert = true
    /// パレットで選んだ文字を覚え，よく使う文字の行と探したときの並びに使う(端末の中にだけ保存する)
    public var paletteRecordsHistory = true
    /// よくある読み違い(「ふいんき」→ 雰囲気)の正しい語を候補に出し，「もしかして」で示す
    public var misreadings = true
    /// 手の置き場所が横にずれたまま打った並びを直す(HandShift．試験的)
    public var handShiftCorrection = false
    /// うろ覚えで読みを少し違えた外来語(しゅみれーしょん → シミュレーション)を候補に出す(LooseReadings)
    public var looseReadings = false
    /// 発音どおりに綴った英単語(foto → photo)を候補に出す(PhoneticSpelling)
    public var phoneticSpelling = false
    /// 英語の語の辞書(R-24)の語を，決まった書き方(api → API，openai → OpenAI)で候補に出す
    public var englishTermCandidates = true
    /// 利用者が足した英語の語(同梱の辞書に無い語)．決まった書き方で書く
    public var englishTerms: [String] = []
    /// ユーザー辞書の語の `{datetime:...}` などを，入れるときの値に置き換える(TextTemplate)
    public var dynamicDictionary = false
    /// 連想変換のキーで出す一覧に，選んでいる語を整えた形(変換マクロ)を並べる
    public var conversionMacros = false
    public var macros: [ConversionMacro] = DefaultSettings.conversionMacros
    /// かなの語(語が読みと同じ)には，語と読みを並べる変換マクロ(ルビ・読みを添える形)を出さない
    public var macroSkipsSameReading = true
    /// 読みで呼び出すコマンド(ランチャー)を使う．同期しない(SyncGroup.commands)
    public var launcherCommands = false
    public var commands: [LauncherCommand] = []
    /// かなで打った外来語は，英語のつづり(「Live変換」)よりカタカナ(「ライブ変換」)を先に出す
    public var prefersKatakana = true
    /// 一覧の上に字種の行を出す(R-03)
    public var showsVariantRow = true
    /// 候補ウィンドウの足元にキーの案内を出す(分岐図の候補・文節・文節の長さ・区切り，一覧の文字種，入力中の候補の窓の選び始めるキー)
    public var showsKeyHints = true
    /// 分岐図の表示項目を減らす．文字種の枝は文字種を選んでいるあいだだけ，候補の先の枝(語の意味・連想)は連想変換のキーで開いたあとだけ出す．
    /// 畳んでいる枝には，続きがある印だけを出す
    public var showsFewerItems = false
    /// 番号キーで候補を選ぶ
    public var numberKeySelection = true
    /// 「きょう」「いま」などを日付や時刻に変換する候補を出す
    public var dateConversion = true
    /// 語の意味と同音異義語の使い分けを候補の窓に添える(R-08)
    public var homophoneNotes = true
    /// 語の意味を候補の右に出すか，下に出すか
    public var meaningPlacement = MeaningPlacement.side
    /// 語の意味をいくつまで出すか(辞書の順)
    public var meaningSenseLimit = DefaultSettings.meaningSenseLimit
    /// 語の意味の見出しに品詞(「動詞」)を添える
    public var showsPartOfSpeech = true
    /// 意味ごとに使い方の例(「写真を撮る」)を添える
    public var showsUsageExamples = true
    /// 同じ読みのほかの語(同音語)を添える
    public var showsHomophones = true
    /// 誤用とされる言い回しに注釈を添える
    public var misuseNotes = false
    /// ら抜き言葉・さ入れ言葉・二重敬語・重言に注釈を添える(校正支援)
    public var proofreading = true
    /// 「やじるし」などの読みから記号の候補を出す
    public var symbolConversion = true
    /// 文節の読みが絵文字の読みと同じとき(「びーる」)，絵文字(🍺)を変換したときの候補に出す(EmojiPlacement)
    public var emojiConversion = true
    /// 文節が絵文字にできる語と助詞などでできているとき(「ねこが」)，語を絵文字にした候補(🐈が)を変換したときの候補に出す
    public var emojiWordConversion = true
    /// 絵文字の候補を出す位置(1 から数えた何番目か)．第 1 候補にはしないので 2 から
    public var emojiCandidatePosition = DefaultSettings.emojiCandidatePosition
    /// 絵文字の候補を出す数の上限
    public var emojiCandidateCount = DefaultSettings.emojiCandidateCount
    /// 絵文字の候補の横に，絵文字の名前(CLDR の日本語の名前．😄 なら「笑顔」)を控えめに添える
    public var showsEmojiNames = true
    /// 読み(「らむだ」)から LaTeX のコマンド(「\lambda」)の候補を出す
    public var latexConversion = false
    /// 読みが数字だけのとき(「21」)，丸数字などに書き換えた候補(「㉑」)を出す(NumberForms)．出す書き方は下の 4 つで選ぶ
    public var numberFormConversion = true
    /// 丸数字(⓪〜㊿)と黒丸の数字(⓿〜⓴)
    public var numberFormCircled = true
    /// 括弧付き(⑴〜⒇)とピリオド付き(⒈〜⒛)の数字
    public var numberFormParenthesized = true
    /// 漢数字(位取りの二〇二六，位付きの二千二十六，大字の弐千弐拾六)
    public var numberFormKanji = true
    /// ローマ数字(Ⅰ〜Ⅻ，ⅩⅢ など)
    public var numberFormRoman = true
    /// 連想変換(R-18)．オフなら連想変換のキーはふつうの変換と同じに動く
    public var association = true
    /// 連想の一覧に出す語の数
    public var associationLimit = DefaultSettings.associationLimit
    /// 選んでいる候補に連想があるとき，候補の窓の足元に知らせる
    public var showsAssociationHint = true

    /// かな漢字変換に使う Zenzai モデル
    public var zenzaiModel = ZenzaiModelChoice.accurate
    /// 分岐図・文節ごとの一覧・入力中の候補の窓で，文節の候補を前後の語とのつながりで並べ替える(「を」のあとの「かこう」なら「書こう」を先に)
    public var contextualSegmentCandidates = true
    /// 文全体の候補の一覧に，分岐図の文節を 1 か所だけほかの候補に替えた文を入れる
    public var listSegmentAlternatives = true
    /// 変換の候補の 2 番目から後ろを，Zenzai の点数(検証木．ADR 0016)で前後の文脈に合う順に並べ替える．第 1 候補は変えない
    public var candidateReranking = true
    /// 別のモデル(jinen)でも変換し，読みにそろえてから Zenzai の結果と合わせる(ADR 0016 の案 2)．使うモデルの大きさか，使わないか．
    /// 2 つのモデルの点数で上回れば第 1 候補に，そうでなければ 2 番目に置く．モデルが無ければ何もしない
    public var jinenModel = JinenModelChoice.automatic

    // MARK: 辞書と学習
    /// 確定した候補から学ぶか
    public var learning = LearningMode.enabled
    /// 利用者が登録した語
    public var userDictionary: [UserDictionaryEntry] = []
    /// 取り込んだ辞書．並び順が優先度．語は Application Support の dictionaries/ にある索引のファイルに置く
    public var importedDictionaries: [ImportedDictionary] = []
    /// 取り込んだ連想の辞書(R-18)．並び順が優先度．語は Application Support の associations/ にある索引のファイルに置く
    public var associationDictionaries: [AssociationDictionary] = [DefaultSettings.bundledAssociationDictionary]
    /// 同梱の専門用語の辞書(R-29)を使うか．通常の辞書にある語は，切っても出る
    public var termDictionary = DefaultSettings.termDictionary
    /// 専門用語の辞書の分野ごとのオン・オフ(termDictionary がオンのときだけ効く)
    public var termFields = TermFieldSettings()
    /// 使い方を記録する(回数だけを端末の中に)
    public var recordsUsage = true

    // MARK: 見た目
    public var theme = ThemePreference.automatic
    public var candidateFontSize = 15.0
    /// 日本語と英数を切り替えたときに，入力位置の近くにモードを出す
    public var showsModeIndicator = true
    /// モードの表示を出しておく時間(秒)
    public var modeIndicatorDuration = 0.8
    /// パレットの列の数
    public var paletteColumns = DefaultSettings.paletteColumns
    /// パレットに一度に見せる行の数
    public var paletteRows = DefaultSettings.paletteRows
    /// パレットのマスの一辺(pt)．文字の大きさはこれに合わせる
    public var paletteCellSize = DefaultSettings.paletteCellSize
    /// パレットの下に，選んでいる文字の名前・読み・ショートコードを出す
    public var paletteShowsPreview = DefaultSettings.paletteShowsPreview
    /// パレットの説明に，Unicode の名前(並びの絵文字は CLDR の英語の名前)を出す
    public var paletteShowsUnicodeName = DefaultSettings.paletteShowsUnicodeName
    /// パレットの説明に，探すときに使える読みを出す
    public var paletteShowsReadings = DefaultSettings.paletteShowsReadings
    /// パレットの説明に，「:smile:」のショートコードを出す
    public var paletteShowsShortcodes = DefaultSettings.paletteShowsShortcodes
    /// パレットの説明に，「U+1F604」のコードポイントを出す(顔文字には出さない)
    public var paletteShowsCodePoints = DefaultSettings.paletteShowsCodePoints
    /// パレットのよく使う文字の行の数．0 なら出さない
    public var paletteFrequentRows = DefaultSettings.paletteFrequentRows
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

    /// 絵文字の候補の置き場所(文節全体と文節の中の語の絵文字に共通)．どちらも絵文字に変換しない設定なら nil
    public var emojiPlacement: EmojiPlacement? {
        emojiConversion || emojiWordConversion ? EmojiPlacement(index: emojiCandidatePosition - 1, count: emojiCandidateCount) : nil
    }

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
        candidateGridColumns = clamp(candidateGridColumns, DefaultSettings.candidateGridColumnsRange)
        associationLimit = clamp(associationLimit, DefaultSettings.associationLimitRange)
        meaningSenseLimit = clamp(meaningSenseLimit, DefaultSettings.meaningSenseLimitRange)
        emojiCandidatePosition = clamp(emojiCandidatePosition, DefaultSettings.emojiCandidatePositionRange)
        emojiCandidateCount = clamp(emojiCandidateCount, DefaultSettings.emojiCandidateCountRange)
        var associationIDs = Set<String>()
        associationDictionaries = associationDictionaries.filter { $0.hasValidIdentity && associationIDs.insert($0.id).inserted }
            // 同梱の辞書は 1 つだけで，一覧から外れていたら先頭に戻す(消せない．使わないときはオフにする)
            .filter { $0.isBundled == ($0.id == DefaultSettings.bundledAssociationDictionary.id) }
        if !associationDictionaries.contains(where: \.isBundled) {
            associationDictionaries.insert(DefaultSettings.bundledAssociationDictionary, at: 0)
        }
        associationDictionaries = Array(associationDictionaries.prefix(DefaultSettings.maximumAssociationDictionaries))
        liveConversionSkipLength = clamp(liveConversionSkipLength, DefaultSettings.liveConversionSkipLengthRange)
        suggestionSkipCount = clamp(suggestionSkipCount, DefaultSettings.suggestionSkipCountRange)
        englishSkipLength = clamp(englishSkipLength, DefaultSettings.englishSkipLengthRange)
        liveConversionDelay = clamp(liveConversionDelay.isFinite ? liveConversionDelay : DefaultSettings.liveConversionSettleDelay, DefaultSettings.liveConversionDelayRange)
        correctionDelay = clamp(correctionDelay.isFinite ? correctionDelay : DefaultSettings.liveCorrectionDelay, DefaultSettings.correctionDelayRange)
        correctionDelay = max(correctionDelay, liveConversionDelay)
        reviewCorrectionTimeout = clamp(reviewCorrectionTimeout.isFinite ? reviewCorrectionTimeout : DefaultSettings.reviewCorrectionTimeout, DefaultSettings.reviewCorrectionTimeoutRange)
        lateCorrectionTimeout = clamp(lateCorrectionTimeout.isFinite ? lateCorrectionTimeout : DefaultSettings.lateCorrectionTimeout, DefaultSettings.lateCorrectionTimeoutRange)
        modeIndicatorDuration = clamp(modeIndicatorDuration.isFinite ? modeIndicatorDuration : 0.8, DefaultSettings.modeIndicatorDurationRange)
        candidateFontSize = clamp(candidateFontSize.isFinite ? candidateFontSize : 15, DefaultSettings.candidateFontSizeRange)
        paletteColumns = clamp(paletteColumns, DefaultSettings.paletteColumnsRange)
        paletteRows = clamp(paletteRows, DefaultSettings.paletteRowsRange)
        paletteCellSize = clamp(paletteCellSize.isFinite ? paletteCellSize : DefaultSettings.paletteCellSize, DefaultSettings.paletteCellSizeRange)
        paletteFrequentRows = clamp(paletteFrequentRows, DefaultSettings.paletteFrequentRowsRange)
        var themeIDs = Set<String>()
        customThemes = Array(customThemes.filter { $0.isValid && themeIDs.insert($0.id).inserted }.prefix(DefaultSettings.maximumCustomThemes))
        if activeCustomTheme == nil { customThemeID = nil }
        var symbolKeys = Set<String>()
        // 同じ入力の決まりは後のものを残す
        symbolRules = Array(symbolRules.reversed().filter { $0.isValid && symbolKeys.insert("\($0.kind.rawValue):\($0.input)").inserted }.reversed()
            .prefix(DefaultSettings.maximumSymbolRules))
        correction.rules = Array(correction.rules.filter(\.isValid).prefix(DefaultSettings.maximumCorrectionRules))
        correction.exceptions = Array(correction.exceptions.filter(RuleListEditing.isValidException).prefix(DefaultSettings.maximumCorrectionRules))
        var hidden = Set<String>()
        hiddenPredictions = Array(hiddenPredictions.filter { RuleListEditing.isValidHiddenPrediction($0) && hidden.insert($0).inserted }
            .prefix(DefaultSettings.maximumHiddenPredictions))
        profileRules = Array(profileRules.filter { ProfileRuleCSV.isValidIdentifier($0.applicationPrefix) }.prefix(DefaultSettings.maximumProfileRules))
        var macroIDs = Set<String>()
        macros = Array(macros.filter { $0.isValid && macroIDs.insert($0.id).inserted }.prefix(DefaultSettings.maximumMacros))
        var commandIDs = Set<String>()
        commands = Array(commands.filter { $0.isValid && commandIDs.insert($0.id).inserted }.prefix(DefaultSettings.maximumCommands))
        var terms = Set<String>()
        englishTerms = Array(englishTerms.filter { EnglishTermDictionary.isValidTerm($0) && terms.insert($0).inserted }.prefix(DefaultSettings.maximumEnglishTerms))
        keymap.clampToValidRanges()
        wordLanguage.clampToValidRanges()
    }

    /// 数字を書き換える書き方(NumberForms)．数字の書き換えがオフなら空
    public var numberFormKinds: Set<NumberForms.Kind> {
        guard numberFormConversion else { return [] }
        let kinds: [(NumberForms.Kind, Bool)] = [
            (.circled, numberFormCircled), (.parenthesized, numberFormParenthesized), (.kanji, numberFormKanji), (.roman, numberFormRoman),
        ]
        return Set(kinds.filter(\.1).map(\.0))
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

    /// カスタムテーマを保存できない理由
    public enum CustomThemeRejection: Error, Sendable, Equatable {
        /// 名前が空か長すぎるなど，CustomTheme.isValid を満たさない
        case invalid
        /// 新しいテーマで，すでに上限(DefaultSettings.maximumCustomThemes)まである
        case full
    }

    /// カスタムテーマを保存して使う．同じ id のテーマがあれば置き換え，無ければ後ろに足す
    public mutating func saveCustomTheme(_ theme: CustomTheme) throws(CustomThemeRejection) {
        guard theme.isValid else { throw .invalid }
        if let index = customThemes.firstIndex(where: { $0.id == theme.id }) {
            customThemes[index] = theme
        } else {
            guard customThemes.count < DefaultSettings.maximumCustomThemes else { throw .full }
            customThemes.append(theme)
        }
        customThemeID = theme.id
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
        case keypadDirect, questionExclamationCommits, keypadCalculation, cyclesLetterCase, symbolRules, correction, okuriganaStyle, calculation, postalCodeConversion, handwriting, misreadings, prefersKatakana
        case alphabetWidth, shiftStartsAlphabet, numberSeparators, alphanumericHyphen, listCandidatesPerPage, branchCandidatesPerPage, candidateGridColumns, expandsGridOnPaging, liveConversionDelay, liveConversionSkipLength, englishSkipLength, correctionDelay
        case correctionSensitivity, showsSuggestions, modeIndicatorDuration, customThemes, customThemeID, terminalCommands
        case reviewCorrectionTimeout, lateCorrectionTimeout, remembersRejectedCorrections
        case typoCorrection, candidatePresentation, initialFocus, suggestionDisplay, predictionDisplay, suggestionSkipCount, predictionPrefersHistory, predictionFromCorrection, hiddenPredictions, showsVariantRow, showsKeyHints, showsFewerItems, numberKeySelection, dateConversion, homophoneNotes, meaningPlacement, meaningSenseLimit, showsPartOfSpeech, showsUsageExamples, showsHomophones, misuseNotes, proofreading, symbolConversion, emojiConversion, emojiWordConversion, emojiCandidatePosition, emojiCandidateCount, showsEmojiNames, latexConversion
        case numberFormConversion, numberFormCircled, numberFormParenthesized, numberFormKanji, numberFormRoman
        case association, associationLimit, showsAssociationHint, zenzaiModel, contextualSegmentCandidates, listSegmentAlternatives, candidateReranking,
             jinenModel
        case learning, userDictionary, importedDictionaries, associationDictionaries, termDictionary, termFields, recordsUsage
        case theme, candidateFontSize, showsModeIndicator
        case escapeSwitchesToDirect, restrainsLiveConversionInCode, profileRules
        case handShiftCorrection, looseReadings, phoneticSpelling, dynamicDictionary, conversionMacros, macros, macroSkipsSameReading, launcherCommands, commands
        case englishTermCandidates, englishTerms
        case palette, paletteClosesAfterInsert, paletteRecordsHistory, paletteColumns, paletteRows, paletteCellSize, paletteShowsPreview, paletteFrequentRows
        case paletteShowsUnicodeName, paletteShowsReadings, paletteShowsShortcodes, paletteShowsCodePoints
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
        read(.questionExclamationCommits, into: \.questionExclamationCommits)
        read(.keypadCalculation, into: \.keypadCalculation)
        read(.cyclesLetterCase, into: \.cyclesLetterCase)
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
        read(.numberSeparators, into: \.numberSeparators)
        read(.alphanumericHyphen, into: \.alphanumericHyphen)
        read(.listCandidatesPerPage, into: \.listCandidatesPerPage)
        read(.branchCandidatesPerPage, into: \.branchCandidatesPerPage)
        read(.candidateGridColumns, into: \.candidateGridColumns)
        read(.expandsGridOnPaging, into: \.expandsGridOnPaging)
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
        // 予測を別の窓に分ける前の設定のファイルには無い．それまでは入力中の候補の窓に予測を混ぜていたので，同じ設定にする
        settings.predictionDisplay = settings.suggestionDisplay
        read(.predictionDisplay, into: \.predictionDisplay)
        read(.suggestionSkipCount, into: \.suggestionSkipCount)
        read(.predictionPrefersHistory, into: \.predictionPrefersHistory)
        read(.predictionFromCorrection, into: \.predictionFromCorrection)
        readList(.hiddenPredictions, into: \.hiddenPredictions)
        read(.showsVariantRow, into: \.showsVariantRow)
        read(.showsKeyHints, into: \.showsKeyHints)
        read(.showsFewerItems, into: \.showsFewerItems)
        read(.numberKeySelection, into: \.numberKeySelection)
        read(.dateConversion, into: \.dateConversion)
        read(.homophoneNotes, into: \.homophoneNotes)
        read(.meaningPlacement, into: \.meaningPlacement)
        read(.meaningSenseLimit, into: \.meaningSenseLimit)
        read(.showsPartOfSpeech, into: \.showsPartOfSpeech)
        read(.showsUsageExamples, into: \.showsUsageExamples)
        read(.showsHomophones, into: \.showsHomophones)
        read(.misuseNotes, into: \.misuseNotes)
        read(.proofreading, into: \.proofreading)
        read(.symbolConversion, into: \.symbolConversion)
        read(.emojiConversion, into: \.emojiConversion)
        read(.emojiWordConversion, into: \.emojiWordConversion)
        read(.emojiCandidatePosition, into: \.emojiCandidatePosition)
        read(.emojiCandidateCount, into: \.emojiCandidateCount)
        read(.showsEmojiNames, into: \.showsEmojiNames)
        read(.latexConversion, into: \.latexConversion)
        read(.numberFormConversion, into: \.numberFormConversion)
        read(.numberFormCircled, into: \.numberFormCircled)
        read(.numberFormParenthesized, into: \.numberFormParenthesized)
        read(.numberFormKanji, into: \.numberFormKanji)
        read(.numberFormRoman, into: \.numberFormRoman)
        read(.association, into: \.association)
        read(.associationLimit, into: \.associationLimit)
        read(.showsAssociationHint, into: \.showsAssociationHint)
        read(.zenzaiModel, into: \.zenzaiModel)
        read(.contextualSegmentCandidates, into: \.contextualSegmentCandidates)
        read(.listSegmentAlternatives, into: \.listSegmentAlternatives)
        read(.candidateReranking, into: \.candidateReranking)
        read(.jinenModel, into: \.jinenModel)
        read(.learning, into: \.learning)
        readList(.userDictionary, into: \.userDictionary)
        readList(.importedDictionaries, into: \.importedDictionaries)
        // 同期のファイルから来た設定でもファイルの名前に使うので，形の違う id は捨てる
        settings.importedDictionaries.removeAll { !$0.hasValidIdentity }
        readList(.associationDictionaries, into: \.associationDictionaries)
        read(.termDictionary, into: \.termDictionary)
        read(.termFields, into: \.termFields)
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
        read(.macroSkipsSameReading, into: \.macroSkipsSameReading)
        read(.launcherCommands, into: \.launcherCommands)
        readList(.commands, into: \.commands)
        read(.englishTermCandidates, into: \.englishTermCandidates)
        readList(.englishTerms, into: \.englishTerms)
        read(.palette, into: \.palette)
        read(.paletteClosesAfterInsert, into: \.paletteClosesAfterInsert)
        read(.paletteRecordsHistory, into: \.paletteRecordsHistory)
        read(.paletteColumns, into: \.paletteColumns)
        read(.paletteRows, into: \.paletteRows)
        read(.paletteCellSize, into: \.paletteCellSize)
        read(.paletteShowsPreview, into: \.paletteShowsPreview)
        read(.paletteFrequentRows, into: \.paletteFrequentRows)
        read(.paletteShowsUnicodeName, into: \.paletteShowsUnicodeName)
        read(.paletteShowsReadings, into: \.paletteShowsReadings)
        read(.paletteShowsShortcodes, into: \.paletteShowsShortcodes)
        read(.paletteShowsCodePoints, into: \.paletteShowsCodePoints)
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
        try container.encode(questionExclamationCommits, forKey: .questionExclamationCommits)
        try container.encode(keypadCalculation, forKey: .keypadCalculation)
        try container.encode(cyclesLetterCase, forKey: .cyclesLetterCase)
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
        try container.encode(numberSeparators, forKey: .numberSeparators)
        try container.encode(alphanumericHyphen, forKey: .alphanumericHyphen)
        try container.encode(listCandidatesPerPage, forKey: .listCandidatesPerPage)
        try container.encode(branchCandidatesPerPage, forKey: .branchCandidatesPerPage)
        try container.encode(candidateGridColumns, forKey: .candidateGridColumns)
        try container.encode(expandsGridOnPaging, forKey: .expandsGridOnPaging)
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
        try container.encode(predictionDisplay, forKey: .predictionDisplay)
        try container.encode(suggestionSkipCount, forKey: .suggestionSkipCount)
        try container.encode(predictionPrefersHistory, forKey: .predictionPrefersHistory)
        try container.encode(predictionFromCorrection, forKey: .predictionFromCorrection)
        try container.encode(hiddenPredictions, forKey: .hiddenPredictions)
        try container.encode(showsVariantRow, forKey: .showsVariantRow)
        try container.encode(showsKeyHints, forKey: .showsKeyHints)
        try container.encode(showsFewerItems, forKey: .showsFewerItems)
        try container.encode(numberKeySelection, forKey: .numberKeySelection)
        try container.encode(dateConversion, forKey: .dateConversion)
        try container.encode(homophoneNotes, forKey: .homophoneNotes)
        try container.encode(meaningPlacement, forKey: .meaningPlacement)
        try container.encode(meaningSenseLimit, forKey: .meaningSenseLimit)
        try container.encode(showsPartOfSpeech, forKey: .showsPartOfSpeech)
        try container.encode(showsUsageExamples, forKey: .showsUsageExamples)
        try container.encode(showsHomophones, forKey: .showsHomophones)
        try container.encode(misuseNotes, forKey: .misuseNotes)
        try container.encode(proofreading, forKey: .proofreading)
        try container.encode(symbolConversion, forKey: .symbolConversion)
        try container.encode(emojiConversion, forKey: .emojiConversion)
        try container.encode(emojiWordConversion, forKey: .emojiWordConversion)
        try container.encode(emojiCandidatePosition, forKey: .emojiCandidatePosition)
        try container.encode(emojiCandidateCount, forKey: .emojiCandidateCount)
        try container.encode(showsEmojiNames, forKey: .showsEmojiNames)
        try container.encode(latexConversion, forKey: .latexConversion)
        try container.encode(numberFormConversion, forKey: .numberFormConversion)
        try container.encode(numberFormCircled, forKey: .numberFormCircled)
        try container.encode(numberFormParenthesized, forKey: .numberFormParenthesized)
        try container.encode(numberFormKanji, forKey: .numberFormKanji)
        try container.encode(numberFormRoman, forKey: .numberFormRoman)
        try container.encode(association, forKey: .association)
        try container.encode(associationLimit, forKey: .associationLimit)
        try container.encode(showsAssociationHint, forKey: .showsAssociationHint)
        try container.encode(zenzaiModel, forKey: .zenzaiModel)
        try container.encode(contextualSegmentCandidates, forKey: .contextualSegmentCandidates)
        try container.encode(listSegmentAlternatives, forKey: .listSegmentAlternatives)
        try container.encode(candidateReranking, forKey: .candidateReranking)
        try container.encode(jinenModel, forKey: .jinenModel)
        try container.encode(learning, forKey: .learning)
        try container.encode(userDictionary, forKey: .userDictionary)
        try container.encode(importedDictionaries, forKey: .importedDictionaries)
        try container.encode(associationDictionaries, forKey: .associationDictionaries)
        try container.encode(termDictionary, forKey: .termDictionary)
        try container.encode(termFields, forKey: .termFields)
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
        try container.encode(macroSkipsSameReading, forKey: .macroSkipsSameReading)
        try container.encode(launcherCommands, forKey: .launcherCommands)
        try container.encode(commands, forKey: .commands)
        try container.encode(englishTermCandidates, forKey: .englishTermCandidates)
        try container.encode(englishTerms, forKey: .englishTerms)
        try container.encode(palette, forKey: .palette)
        try container.encode(paletteClosesAfterInsert, forKey: .paletteClosesAfterInsert)
        try container.encode(paletteRecordsHistory, forKey: .paletteRecordsHistory)
        try container.encode(paletteColumns, forKey: .paletteColumns)
        try container.encode(paletteRows, forKey: .paletteRows)
        try container.encode(paletteCellSize, forKey: .paletteCellSize)
        try container.encode(paletteShowsPreview, forKey: .paletteShowsPreview)
        try container.encode(paletteFrequentRows, forKey: .paletteFrequentRows)
        try container.encode(paletteShowsUnicodeName, forKey: .paletteShowsUnicodeName)
        try container.encode(paletteShowsReadings, forKey: .paletteShowsReadings)
        try container.encode(paletteShowsShortcodes, forKey: .paletteShowsShortcodes)
        try container.encode(paletteShowsCodePoints, forKey: .paletteShowsCodePoints)
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

    /// キー配列が入れる文字(Shift だけを効かせた文字)を，この設定で決めるか．¥ のときだけ決める．
    /// Shift などで配列が別の文字(JIS 配列の Shift+¥ の |)を入れるときと，配列がもともと入れる \\ は，その文字をそのまま使う
    public static func isChoosable(_ text: String) -> Bool {
        text == yen
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
