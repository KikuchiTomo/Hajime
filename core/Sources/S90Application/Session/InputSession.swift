import S90Domain

/// 入力欄ひとつぶんの入力の状態を進める．キーを受け取り，画面への操作(ClientAction)の列を返す．
///
/// 状態は 4 つある．
/// - 何も組み立てていない
/// - 読みを組み立てている(ライブ変換の結果か読みを表示する)
/// - 候補を一覧から選んでいる(候補ウィンドウを出す)
/// - 文節格子で文節ごとに候補を選んでいる(格子のウィンドウを出す)
/// - 連想の一覧から選んでいる(R-18．元の一覧か文節格子の上で，選んでいる文節を連想の語に置き換えて見せる)
///
/// キーの意味はキー設定の表(Keymap．R-17)で決める．表の状態は，何も組み立てていない(入力文字なし)・読みを組み立てている(入力中)・
/// 候補を選んでいる(変換中．一覧と文節格子の両方)と，英数モード(英数)
@MainActor
public final class InputSession {
    private enum Phase: Equatable {
        case composing
        case selecting(CandidateSelection)
        case lattice(SegmentLattice)
        /// 連想の一覧(R-18)．origin は連想に切り替える前の一覧か文節格子．Esc でそこに戻る
        indirect case association(AssociationList, origin: Phase)
    }


    private let converter: any KanaKanjiConverting
    private let lexicon: any EnglishLexicon
    private let settings: any SettingsReading

    public private(set) var mode: InputMode = .japanese
    /// 今の入力先のプロファイル(最後に受けたキーの文脈)．表示の決まり(R-06 のライブ変換を控えめにする)に使う
    private var profile = AppProfile.standard
    private var composition = Composition()
    /// ローマ字の表．利用者が足した綴りが変わったときだけ作り直す
    private var romajiTable: (rules: [RomajiRule], table: RomajiTable) = ([], .standard)
    /// 記号をまとめる決まり．利用者の変えた決まりが変わったときだけ作り直す
    private var symbolSequences: (rules: [SymbolRule], set: SymbolSequenceSet) = ([], .standard)
    private var phase: Phase = .composing
    /// 英単語の補正(R-02)
    private let corrector: EnglishWordCorrector
    /// ローマ字入力以外の入力方式．ローマ字入力は共通の処理が受け持つ
    private let styleHandlers: [InputStyle: any InputStyleHandling]
    /// 方式の側で文字を組み立てているもの(入力方式を途中で変えたときは，前の方式のものが残っていることがある)
    private var composingStyles: [any InputStyleHandling] { styleHandlers.values.filter(\.isComposing) }
    /// ターミナルで打っている行(R-07)
    private let terminal = TerminalLine()
    /// 前のキーのときの入力方式．メニューなどで変わったら，組み立て中の文字を確定する
    private var lastInputStyle: InputStyle?
    /// 日本語の打ち間違いの補正(R-02)
    private let readingCorrector: ReadingCorrector
    /// 打鍵が止まったか．止まるまでは打っている途中の語をかなのまま見せる(LiveConversionRule)
    private var isSettled = false
    /// Shift を押して英字を打ち始め，英字のまま入れているところか(設定 shiftStartsAlphabet)
    private var alphabetRun = false
    /// 訂正を求め終わるのを待って変換するところ(Space を押した)
    private var waitsForCorrections = false
    private var pendingConversionLearns = true
    /// 利用者が打っている途中に入れた文節の区切り(読みの先頭からの文字数)．分岐図ではここを必ず区切る
    private var forcedBoundaries: [Int] = []
    /// 分岐図で，注目している文節を数字で区切る状態か
    private var splitMode = false
    /// 英字入力の Tab で日本語にした語の英字．分岐図で Esc を押したら英字に戻す
    private var convertedFromEnglish: String?
    /// 組み立てを始めたときの，入力位置の前の文字列(打ち間違いの訂正の手がかり)
    private var compositionLeftContext: String?
    /// 見直した直後の表示か．打ち間違いの案内は見直した直後だけ出し，次のキーで消す
    /// (打つたびに直す前の文も変換すると，1 キーの処理が重くなるため)
    private var showsCorrectionNote = false
    /// 分岐図か一覧の足元に 1 回だけ出す案内(学習から消したとき)
    private var pendingNote: String?
    /// 入力文字なしで案内を出したか．出したら次のキーで消す
    private var showsTransientNote = false

    /// 使い方の記録(回数だけ)．記録しないときは nil
    private let usage: (any UsageRecording)?
    /// 連想変換の語を引く(R-18)
    private let associationFinder: AssociationFinder

    /// - Parameters:
    ///   - typoService: 打ち間違いの訂正を別のところで求めるもの．nil なら変換器で求める(テストと Zenzai の無いとき)
    ///   - associations: 取り込んだ連想の辞書を引くもの(R-18)．nil なら連想変換のキーはふつうの変換と同じに動く
    public init(converter: any KanaKanjiConverting, lexicon: any EnglishLexicon, settings: any SettingsReading, usage: (any UsageRecording)? = nil,
                typoService: (any TypoCorrecting)? = nil, associations: (any AssociationLookup)? = nil) {
        self.converter = converter
        self.lexicon = lexicon
        self.settings = settings
        self.usage = usage
        self.associationFinder = AssociationFinder(lookup: associations, settings: settings)
        let classifier = WordLanguageClassifier(lexicon: lexicon, converter: converter, settings: settings)
        self.corrector = EnglishWordCorrector(lexicon: lexicon, settings: settings, converter: converter, classifier: classifier)
        self.readingCorrector = ReadingCorrector(converter: converter, settings: settings, usesProvidedCorrections: typoService != nil)
        self.styleHandlers = [
            .english: EnglishInput(converter: converter, classifier: classifier, settings: settings, behavior: .manual),
            .englishAuto: EnglishInput(converter: converter, classifier: classifier, settings: settings, behavior: .automatic),
            .kana: KanaInput(),
        ]
    }

    public var isComposing: Bool { !composition.isEmpty || !composingStyles.isEmpty }

    // MARK: - 外からの操作

    public func handle(_ event: KeyEvent, context: InputContext) -> KeyResult {
        if context.isSecure {
            // パスワード欄では何もしない(docs/dev/SECURITY-MODEL.md)
            return .passThrough
        }
        showsCorrectionNote = false
        profile = context.profile
        // 変換を待たせているあいだに次のキーが来たら，待たせていた変換はやめる(次のキーを先に処理する)
        waitsForCorrections = false
        let hidesNote = showsTransientNote
        showsTransientNote = false
        var result = route(event, context: context)
        // 入力文字なしで出した案内(学習の取り消し)は，次のキーで消す
        if hidesNote { result.actions.insert(.hideCandidates, at: 0) }
        // ターミナルの行には，どの経路で確定した文字もアプリに渡ったキーも，ここで 1 か所で数える
        if context.profile == .terminal { terminal.didHandle(event, result: result) }
        return result
    }

    /// キーを振り分ける．キー設定の表(R-17)を先に引き，表に無いキーはふつうの処理に回す
    private func route(_ event: KeyEvent, context: InputContext) -> KeyResult {
        let command = lookUp(event)
        if let command, command.isTool {
            // 設定を開く・ライブ変換・手書き．入力メニューの操作を取り次がないアプリでも効くよう，キーで受ける
            return perform(command, event: event, context: context)
        }
        if command == nil, event.modifiers.contains(.command) {
            // 表に無い ⌘ の組み合わせはアプリのショートカット．組み立て中の文字は先に確定する
            return KeyResult(handled: false, actions: commitAll())
        }
        if context.profile == .direct {
            // IME を使わないアプリ(除外設定)では，日本語のモードでも英数のまま入れる
            return KeyResult(handled: false, actions: commitAll())
        }
        if let command, command.changesMode {
            return perform(command, event: event, context: context)
        }
        if command == nil, event.modifiers.contains(.option), case .character = event.key {
            // Option との組み合わせで入る特殊な文字(å など)は，アプリの配列に任せる
            return KeyResult(handled: false, actions: commitAll())
        }
        if command == nil, mode == .japanese, event.isKeypad, settings.current.keypadDirect, case .character(let character) = event.key {
            // テンキーの数字と記号は，組み立て中の文字を確定してから半角のまま確定する(設定)
            return KeyResult(handled: true, actions: commitAll() + [.commit(String(character))])
        }
        switch mode {
        case .direct: return handleDirect(event, context: context)
        case .japanese: return handleJapanese(event, command: command, context: context)
        }
    }

    /// OS の入力メニューなどでモードが変わった
    public func setMode(_ newMode: InputMode) -> [ClientAction] {
        guard newMode != mode else { return [] }
        let actions = commitAll()
        mode = newMode
        // 英数にしたあとは行の頭の判断と関係なくなるので行を終える(キーで英数にしたときは TerminalLine.didHandle が終える)
        if newMode == .direct { terminal.endLine() }
        return actions
    }

    /// 入力欄からフォーカスが外れた．組み立て中の文字は確定する
    /// OS が commitComposition と deactivateServer の両方で呼ぶことがあるので，何度呼んでも同じ結果になるようにする
    public func deactivate() -> [ClientAction] {
        let actions = commitAll()
        terminal.didLeave(committing: actions)
        return actions
    }

    /// キーの外で選んだ文字(手書きの窓の候補)を入れる．組み立て中の文字があれば先に確定し，選んだ文字で置き換えない
    public func insert(_ text: String) -> [ClientAction] {
        commitAll() + [.commit(text)]
    }

    /// 読みを組み立てていて，打鍵が止まるのを待っているか．待っていれば，止まったときに settle を呼ぶ．
    /// EN 入力の英字は変換して見せないので待たない
    public var awaitsSettle: Bool {
        // ライブ変換がオフでも，打鍵が止まったことは覚える．覚えないと打ち間違いの見直し(awaitsReview)が始まらず，
        // 直すことも「もしかして」と示すこともなくなる．ライブ変換がオフのときの表示は読みのまま変わらない
        !composition.isEmpty && phase == .composing && !isSettled
    }

    private func switchToDirectPassingEscape(actions: [ClientAction]) -> KeyResult {
        mode = .direct
        return KeyResult(handled: false, actions: actions + [.selectMode(.direct)] + modeIndicator(.direct))
    }

    /// 日本語入力と英数入力を切り替える(表の 日本語入力・英数入力・切り替え のコマンド)
    private func switchMode(to target: InputMode) -> KeyResult {
        guard target != mode else {
            // すでにそのモードなら，モードを出すだけ
            return KeyResult(handled: true, actions: modeIndicator(target))
        }
        let actions = target == .direct ? commitAll() : []
        mode = target
        if target == .direct { terminal.endLine() }
        return KeyResult(handled: true, actions: actions + [.selectMode(target)] + modeIndicator(target))
    }

    /// 入力位置の近くにモードを出す操作．設定で切っていれば出さない
    private func modeIndicator(_ mode: InputMode) -> [ClientAction] {
        settings.current.showsModeIndicator ? [.showModeIndicator(mode)] : []
    }

    /// 打鍵が止まった(DefaultSettings.liveConversionSettleDelay)．かなのまま見せていた語も変換して見せる
    public func settle(context: InputContext) -> [ClientAction] {
        guard awaitsSettle else { return [] }
        isSettled = true
        freezeWordsReadAsRomaji()
        return render(context: context)
    }

    /// 打鍵がさらに止まるのを待って，打ち間違いを見直すか．待っていれば，止まったときに review を呼ぶ
    public var awaitsReview: Bool {
        isSettled && phase == .composing && (corrector.active == nil || corrector.yieldsToJapanese(in: composition))
            && !readingCorrector.isReviewed(composition)
            && (settings.current.typoCorrection == .standard || settings.current.misreadings)
            && (composition.rawKeys?.count ?? 0) >= DefaultSettings.minimumKeysForLiveCorrection
    }

    /// 見直すために，別のところで求める訂正のキーの並びと左の文脈．求めるものが無ければ nil
    public var correctionRequest: (keys: [String], leftContext: String?)? {
        guard awaitsReview, let keys = readingCorrector.pendingKeys(for: composition) else { return nil }
        // 英単語より後ろだけを見直すときは，英単語までの部分も左の文脈にする
        guard let prefix = readingCorrector.unreviewedPrefix(of: composition) else { return (keys, compositionLeftContext) }
        return (keys, String(((compositionLeftContext ?? "") + prefix).suffix(DefaultSettings.maximumLeftContextLength)))
    }

    /// 別のところで求めた訂正を受け取る．そのあと review を呼ぶと見直す
    public func provideCorrections(_ corrections: [String: [ReadingCorrection]]) {
        readingCorrector.provide(corrections)
    }

    /// 打鍵が長く止まった(DefaultSettings.liveCorrectionDelay)．打ち間違いを見直し，直すか「もしかして」と示す．
    /// ターミナルの行の頭ではコマンドの名前を打っているかもしれないので見直さない(直すとコマンドとして流せなくなる．R-07)
    public func review(context: InputContext) -> [ClientAction] {
        guard awaitsReview, !(context.profile == .terminal && terminal.state.region == .lineStart) else { return [] }
        reviewReading()
        showsCorrectionNote = true
        return render(context: context)
    }

    // MARK: - 英数モード

    /// 英数モードのキー．切り替えのキーは表(route)が先に受けるので，ここに来るのは表に無いキー
    private func handleDirect(_ event: KeyEvent, context: InputContext) -> KeyResult {
        guard event.key == .yen else {
            // 表に無い英数・かな・半角/全角・変換・無変換などは，アプリに渡す
            return .passThrough
        }
        let text = settings.current.yenKey.character(profile: context.profile, optionPressed: event.modifiers.contains(.option))
        return KeyResult(handled: true, actions: [.commit(text)])
    }

    // MARK: - 日本語モード

    /// 日本語モードのキー．入力方式が前のキーから変わっていたら，組み立て中の文字を確定してから処理する
    private func handleJapanese(_ event: KeyEvent, command: KeymapCommand?, context: InputContext) -> KeyResult {
        isSettled = false
        let styleChange = adoptInputStyle()
        if !styleChange.isEmpty, !Self.continuesAfterStyleChange(event) {
            // メニューなどで入力方式が変わっていたら，前の方式の文字を確定する．Backspace・Escape・Enter・Space・矢印などは
            // 確定した文字に効いて意味が変わるので，確定だけにして飲み込む．文字・¥・英数・かなは新しい方式で続けて処理する
            return KeyResult(handled: true, actions: styleChange)
        }
        // 確定して状態が変わったので，表を引き直す
        let command = styleChange.isEmpty ? command : lookUp(event)
        let routed = routeJapanese(event, command: command, context: context)
        return KeyResult(handled: routed.handled, actions: styleChange + routed.actions)
    }

    /// 入力方式が変わった直後でも，そのまま新しい方式で処理するキー．
    /// 文字・¥・英数・かなは，確定した文字に効かないので続けて処理する．
    /// Space は前の方式の文字を変換するつもりで押したことが多く，新しい方式で空白を入れると意図と違うので，確定だけにする
    private static func continuesAfterStyleChange(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .character: !event.modifiers.contains(.control) && !event.modifiers.contains(.option)
        case .yen, .eisu, .kana, .hankakuZenkaku, .henkan, .muhenkan: true
        default: false
        }
    }

    /// 日本語モードのキー．次の順に回し，前の段で扱ったキーは後ろに回さない．
    /// 1. ターミナルの行(コマンドの行で英字をそのまま流す判断は，ほかの処理より先に要る．
    ///    行の長さと行の終わりは，処理の結果を見て TerminalLine.didHandle で数える)
    /// 2. 分岐図で文節を数字で区切っているところ
    /// 3. キー設定の表のコマンド(R-17)
    /// 4. 表に無い Control の組み合わせ
    /// 5. 分岐図の番号キー
    /// 6. 入力方式ごとの処理(EN 入力・かな入力)
    /// 7. ローマ字入力と共通の処理．文字は読みに足し，表に無いほかのキーは，組み立て中なら何もせず，組み立てていなければアプリに渡す
    private func routeJapanese(_ event: KeyEvent, command: KeymapCommand?, context: InputContext) -> KeyResult {
        if context.profile == .terminal, settings.current.terminalCommands, let result = applyTerminal(event) {
            return result
        }
        if splitMode, case .lattice(var lattice) = phase, let result = handleSplit(event, lattice: &lattice, context: context) {
            return result
        }
        if let command {
            return perform(command, event: event, context: context)
        }
        if event.modifiers.contains(.control) {
            return handleControl(event)
        }
        if case .lattice(var lattice) = phase, case .character(let character) = event.key,
            let result = selectInLattice(character, lattice: &lattice, context: context) {
            return result
        }
        if event.key == .escape, settings.current.escapeSwitchesToDirect, composition.isEmpty, !composingStyles.isEmpty {
            // EN 入力の英字を確定し，英数にして Escape をアプリに渡す(Vim のノーマルモードに 1 回で戻る)
            return switchToDirectPassingEscape(actions: commitAll())
        }
        if let result = applyInputStyle(event, context: context) {
            return result
        }
        switch event.key {
        case .yen:
            let text = settings.current.yenKey.character(profile: context.profile, optionPressed: event.modifiers.contains(.option))
            return insertLiteral(text, rawKey: nil, context: context)
        case .character(let character):
            return insertCharacter(character, context: context)
        case .escape where !isComposing && settings.current.escapeSwitchesToDirect:
            // Vim のノーマルモードに戻る Escape で英数にする(設定)．Escape そのものはアプリに渡す
            return switchToDirectPassingEscape(actions: [])
        case .function:
            // 表に無いファンクションキーはアプリに渡す
            return .passThrough
        default:
            // 表に無いほかのキーは，組み立て中なら何もしない(読みが入力先に混ざらないように)．組み立てていなければアプリに渡す
            return isComposing ? KeyResult(handled: true) : .passThrough
        }
    }

    // MARK: - キー設定の表(R-17)

    /// 今の状態でこのキーに割り当てたコマンド
    private func lookUp(_ event: KeyEvent) -> KeymapCommand? {
        guard let command = settings.current.keymap.command(for: event, in: keymapState) else { return nil }
        // 英字入力で読みを組み立てていないとき(英字を打っているとき・何も打っていないとき)は英語の入力と同じに動かすため，
        // 表は入力モードの切り替えと IME の機能にだけ使う
        if settings.current.inputStyle.typesLetters, composition.isEmpty, !command.changesMode, !command.isTool { return nil }
        // 手書き入力は設定でオンにしたときだけ
        if command == .handwriting, !settings.current.handwriting { return nil }
        return command
    }

    /// 表を引くときの今の状態
    private var keymapState: KeymapState {
        guard mode == .japanese else { return .direct }
        guard isComposing else { return .idle }
        switch phase {
        case .composing: return .composing
        case .selecting, .lattice, .association: return .converting
        }
    }

    /// 表のコマンドを行う．表は状態ごとに効くコマンドだけを返すので，ここではその状態でできることをする
    /// 入力メニューから手書き入力を開く．キーの「手書き入力」と同じく，組み立て中の文字を確定してから窓を開く．
    /// 手書き入力を使わない設定なら何もしない
    public func openHandwriting() -> [ClientAction] {
        guard settings.current.handwriting else { return [] }
        return commitAll() + [.showHandwriting]
    }

    private func perform(_ command: KeymapCommand, event: KeyEvent, context: InputContext) -> KeyResult {
        if case .association(let list, let origin) = phase, let result = performInAssociation(command, list: list, origin: origin, context: context) {
            return result
        }
        switch command {
        // IME の機能．入力メニューの操作を取り次がないアプリでも効くよう，キーで受ける
        case .openSettings: return KeyResult(handled: true, actions: commitAll() + [.openSettings])
        case .toggleLiveConversion: return KeyResult(handled: true, actions: commitAll() + [.toggleLiveConversion])
        case .handwriting: return KeyResult(handled: true, actions: commitAll() + [.showHandwriting])
        // 入力モード
        case .japaneseMode: return switchMode(to: .japanese)
        case .directMode: return switchMode(to: .direct)
        case .toggleMode: return switchMode(to: mode == .japanese ? .direct : .japanese)
        case .nextInputStyle:
            // 入力方式を順に切り替える(ローマ字 → かな → 英字)．英数のときは日本語に戻してから切り替える
            guard mode == .japanese else {
                mode = .japanese
                return KeyResult(handled: true, actions: [.selectMode(.japanese), .selectInputStyle(nextInputStyle())])
            }
            return KeyResult(handled: true, actions: commitAll() + [.selectInputStyle(nextInputStyle())])
        case .romajiStyle, .kanaStyle, .englishStyle, .englishAutoStyle:
            let style = command.inputStyle ?? .romaji
            guard mode == .japanese else {
                mode = .japanese
                return KeyResult(handled: true, actions: [.selectMode(.japanese), .selectInputStyle(style)])
            }
            return KeyResult(handled: true, actions: commitAll() + [.selectInputStyle(style)])
        case .cancelAndDirectMode:
            let actions = isComposing ? reset() : []
            mode = .direct
            terminal.endLine()
            return KeyResult(handled: true, actions: actions + [.selectMode(.direct)] + modeIndicator(.direct))
        // 文字の入力
        case .insertSpace: return insertSpace(.setting, event: event, context: context)
        case .insertAlternateSpace: return insertSpace(.alternate, event: event, context: context)
        case .insertHalfwidthSpace: return insertSpace(.halfwidth, event: event, context: context)
        case .insertFullwidthSpace: return insertSpace(.fullwidth, event: event, context: context)
        // 入力中
        case .convert: return convert(withoutLearning: false, context: context)
        case .convertWithoutLearning: return convert(withoutLearning: true, context: context)
        case .deleteBackward: return handleBackspace(context: context)
        case .insertBoundary:
            // 打っている途中に，今の位置を文節の区切りにする(分岐図でここを必ず区切る)
            let position = composition.kana.count
            if position > 0, !forcedBoundaries.contains(position) { forcedBoundaries.append(position) }
            return KeyResult(handled: true, actions: render(context: context))
        case .acceptSuggestion:
            // 「もしかして」と示していた読みに直す
            guard phase == .composing, readingCorrector.acceptSuggestion(&composition) else { return KeyResult(handled: true) }
            usage?.record(.readingCorrected)
            showsCorrectionNote = true
            return KeyResult(handled: true, actions: render(context: context))
        // 字種
        case .toHiragana: return selectVariant(.hiragana, context: context)
        case .toKatakana: return selectVariant(.katakana, context: context)
        case .toHalfwidthKatakana: return selectVariant(.halfwidthKatakana, context: context)
        case .toFullwidthAlphanumeric: return selectVariant(.fullwidthRoman, context: context)
        case .toHalfwidthAlphanumeric: return selectVariant(.halfwidthRoman, context: context)
        case .switchKanaType: return selectVariant(nextKanaType(), context: context)
        // 候補
        case .nextCandidate: return moveCandidate(.next, context: context)
        case .previousCandidate: return moveCandidate(.previous, context: context)
        case .nextCandidatePage: return moveCandidate(.nextPage, context: context)
        case .previousCandidatePage: return moveCandidate(.previousPage, context: context)
        case .firstCandidate: return moveCandidate(.first, context: context)
        case .lastCandidate: return moveCandidate(.last, context: context)
        case .associate: return associate(context: context)
        // 文節
        case .nextSegment: return moveSegment(.next, context: context)
        case .previousSegment: return moveSegment(.previous, context: context)
        case .firstSegment: return moveSegment(.first, context: context)
        case .lastSegment: return moveSegment(.last, context: context)
        case .nextUncertainSegment: return moveSegment(.nextUncertain, context: context)
        case .previousUncertainSegment: return moveSegment(.previousUncertain, context: context)
        case .extendSegment: return moveSegment(.extend, context: context)
        case .shrinkSegment: return moveSegment(.shrink, context: context)
        case .extendSegmentToWord: return moveSegment(.extendToWord, context: context)
        case .shrinkSegmentToWord: return moveSegment(.shrinkToWord, context: context)
        case .splitSegment: return moveSegment(.split, context: context)
        // 確定と取り消し
        case .commit: return KeyResult(handled: true, actions: commitAll())
        case .commitFirstSegment: return commitFirstSegment(context: context)
        case .cancel: return handleEscape(context: context)
        case .backToReading:
            phase = .composing
            return KeyResult(handled: true, actions: render(context: context))
        // 学習
        case .forgetCandidate:
            let candidate: Candidate? = switch phase {
            case .lattice(let lattice): lattice.focused.selected
            case .selecting: currentCandidate()
            case .composing, .association: nil
            }
            if let candidate, candidate.isFromEngine {
                converter.forget(candidate)
                pendingNote = PanelBuilder.candidateForgottenNote
            }
            return KeyResult(handled: true, actions: render(context: context))
        case .forgetLastCommit:
            guard converter.forgetLastCommit() else { return KeyResult(handled: true) }
            showsTransientNote = true
            return KeyResult(handled: true, actions: [.showNote(PanelBuilder.lastCommitForgottenNote)])
        }
    }

    // MARK: - ターミナル(R-07)

    /// ターミナルの行の判断に従う．ふつうの処理に回すときは nil
    private func applyTerminal(_ event: KeyEvent) -> KeyResult? {
        let composingKeys = phase == .composing && !composition.isEmpty ? composition.rawKeys : nil
        switch terminal.decide(event, isComposing: isComposing, composingKeys: composingKeys, holdsLetters: settings.current.inputStyle.typesLetters) {
        case .continue:
            return nil
        case .passThrough:
            return .passThrough
        case .commitCommand(let keys):
            // 打ったとおりの英字で確定する．確定した名前と空白は TerminalLine.didHandle で行の長さに数える
            return KeyResult(handled: true, actions: [.commit(keys + " ")] + reset())
        case .commitAndPass:
            return KeyResult(handled: false, actions: commitAll())
        }
    }

    // MARK: - 入力方式(R-05)

    /// 入力方式がメニューや設定の画面で変わっていたら，前の方式で組み立てていた文字を確定する
    private func adoptInputStyle() -> [ClientAction] {
        let current = settings.current.inputStyle
        defer { lastInputStyle = current }
        guard let last = lastInputStyle, last != current else { return [] }
        return commitAll()
    }

    /// 番号キーで選べる候補の数(分岐図なら注目している文節のページ，一覧ならそのページ)
    private var selectableCount: Int {
        switch phase {
        case .composing:
            return 0
        case .lattice(let lattice):
            return min(lattice.focused.candidates.count, settings.current.branchCandidatesPerPage)
        case .selecting(let selection):
            guard case .candidate(let index) = selection.focus else { return 0 }
            let perPage = settings.current.listCandidatesPerPage
            return min(selection.candidates.count - index / perPage * perPage, perPage)
        case .association(let list, _):
            return list.page(perPage: associationPerPage).words.count
        }
    }

    private func nextInputStyle() -> InputStyle {
        let styles = InputStyle.allCases
        let current = styles.firstIndex(of: settings.current.inputStyle) ?? 0
        return styles[(current + 1) % styles.count]
    }

    /// 入力方式ごとの解釈に従う．ふつうの処理に回すときは nil
    private func applyInputStyle(_ event: KeyEvent, context: InputContext) -> KeyResult? {
        let style = settings.current.inputStyle
        guard let handler = styleHandlers[style] else { return nil }
        // 英字入力の Tab で開いた分岐図などで英字を打ったら，選んでいる変換で確定してから英字を続ける
        if style.typesLetters, !composition.isEmpty, case .character(let character) = event.key, character.isASCII, character.isLetter {
            let committed = commitAll()
            if case .handled(let result)? = handler.interpret(event, state: InputStyleState(settings: settings.current, selectableCount: 0,
                                                                                         precedingText: context.precedingText)) {
                return KeyResult(handled: result.handled, actions: committed + result.actions)
            }
            return KeyResult(handled: true, actions: committed)
        }
        // 英字入力で日本語の読みを組み立てているあいだ(Tab で開いた分岐図)は，ほかのキーをふつうの処理に回す(Enter で確定など)
        if style.typesLetters, !composition.isEmpty { return nil }
        let state = InputStyleState(settings: settings.current, selectableCount: selectableCount, precedingText: context.precedingText)
        switch handler.interpret(event, state: state) {
        case nil:
            return nil
        case .handled(let result):
            return result
        case .convertRomaji(let keys):
            // 英字入力の語を日本語の読みにし，分岐図で変換を選べるようにする．Esc で英字に戻す
            var actions: [ClientAction] = commitAll()
            if !isComposing {
                setLeftContext(context.precedingText)
                converter.setApplication(context.applicationID)
            }
            composition = newComposition()
            let resolver = NasalReadingResolver(converter: converter)
            for key in keys {
                composition.insertRomaji(key)
                resolver.resolve(&composition)
            }
            convertedFromEnglish = keys
            enterConversion()
            actions += [.hideCandidates] + render(context: context)
            return KeyResult(handled: true, actions: actions)
        case .insertKana(let kana):
            var actions: [ClientAction] = []
            if phase != .composing { actions += commitAll() }
            if !isComposing {
                setLeftContext(context.precedingText)
                converter.setApplication(context.applicationID)
            }
            composition.insertKana(kana)
            if settings.current.punctuationCommits, SymbolTable.isPunctuation(kana, settings: settings.current) {
                return KeyResult(handled: true, actions: actions + commitAll())
            }
            return KeyResult(handled: true, actions: actions + render(context: context))
        }
    }

    /// 表に無い Control の組み合わせ
    private func handleControl(_ event: KeyEvent) -> KeyResult {
        // EN 入力の英字は，確定してからキーをアプリに渡す(Ctrl+A などで英字が残らないように)
        if !composingStyles.isEmpty { return KeyResult(handled: false, actions: commitAll()) }
        // 読みを組み立てている途中の Control+文字は，読みが入力先に混ざらないよう，アプリに渡さずに捨てる
        guard !composition.isEmpty, case .character = event.key else { return .passThrough }
        return KeyResult(handled: true)
    }

    /// 読み全体を字種に変えて選ぶ(既定では F6〜F10 と Ctrl+J/K/;/L/:．R-03)
    private func selectVariant(_ variant: ScriptVariant, context: InputContext) -> KeyResult {
        guard variant.apply(to: composition) != nil else { return KeyResult(handled: true) }
        phase = .selecting(makeSelection(focus: .variant(variant)))
        return KeyResult(handled: true, actions: render(context: context))
    }

    private func insertCharacter(_ character: Character, context: InputContext) -> KeyResult {
        var actions: [ClientAction] = []
        if case .selecting = phase, let number = numberKey(character), selectByNumber(number) {
            // 候補を選んでいるときの番号キーは，その候補を確定する
            return KeyResult(handled: true, actions: commitAll())
        }
        if case .association(var list, let origin) = phase, let number = numberKey(character), list.select(number: number, perPage: associationPerPage) {
            // 連想の一覧の番号キーも，その語を確定する
            phase = .association(list, origin: origin)
            return KeyResult(handled: true, actions: commitAll())
        }
        if phase != .composing {
            // 候補を選んでいる途中で打ち始めたら，選んでいる候補を確定して続ける
            actions += commitAll()
        }
        if !isComposing {
            composition = newComposition()
            // 打ち始めに，入力位置の前の文字列を変換の手がかりとして渡す(「AAA」+「まで」)
            setLeftContext(context.precedingText)
            converter.setApplication(context.applicationID)
        }
        let startsAlphabet = settings.current.shiftStartsAlphabet && character.isASCII && character.isLetter && character.isUppercase
        if startsAlphabet { alphabetRun = true }
        if alphabetRun, !(character.isASCII && character.isLetter) { alphabetRun = false }
        let isRomaji = !alphabetRun && (character.isASCII && character.isLetter && character.isLowercase)
            || character == "-"
            || (character == "'" && composition.pending == "n")
            // 「z.」→「…」，「z[」→「『」など，z と組み合わせる記号
            || (composition.pending == "z" && Self.zSymbolKeys.contains(character))
        if isRomaji {
            composition.insertRomaji(character)
            NasalReadingResolver(converter: converter).resolve(&composition)
            readingCorrector.didType(character)
            if corrector.active != nil, corrector.handleFollowingRomaji(in: &composition) == .waiting {
                return KeyResult(handled: true, actions: actions + render(context: context))
            }
        } else if character.isASCII && (character.isLetter || character.isNumber) {
            // 英単語に続けて打った大文字と数字は識別子の続き(「userName」「v2」)なので，綴りを直さず打ったとおりにする(R-06)
            corrector.commitAsTyped(into: &composition)
            readingCorrector.didInsertLiteral()
            let width = character.isNumber ? settings.current.numberWidth : settings.current.alphabetWidth
            let text = width == .fullwidth ? KanaWidth.fullwidthASCII(from: String(character)) : String(character)
            composition.insertLiteral(text, rawKey: character)
        } else {
            let text = SymbolTable.text(for: character, profile: context.profile, settings: settings.current)
            if !isComposing && text == String(character) {
                // 半角のままの記号は，組み立てを始めずにアプリへ渡す(プログラミング中に Enter を要求しない)
                return KeyResult(handled: false, actions: actions)
            }
            if character == "_" || (character == "." && context.profile.prefersHalfwidthSymbols) {
                // 「user_name」「a.b」の識別子は直さない(R-06)
                corrector.commitAsTyped(into: &composition)
            } else {
                corrector.commit(into: &composition)
            }
            readingCorrector.didInsertLiteral()
            composition.insertLiteral(text, rawKey: nil)
            if settings.current.punctuationCommits, SymbolTable.isPunctuation(text, settings: settings.current) {
                // 句読点を打ったら，その句読点まで確定する(設定)
                return KeyResult(handled: true, actions: actions + commitAll())
            }
        }
        updateCorrection()
        return KeyResult(handled: true, actions: actions + render(context: context))
    }

    private func insertLiteral(_ text: String, rawKey: Character?, context: InputContext) -> KeyResult {
        if !isComposing {
            return KeyResult(handled: true, actions: [.commit(text)])
        }
        if phase != .composing {
            return KeyResult(handled: true, actions: commitAll() + [.commit(text)])
        }
        corrector.commit(into: &composition)
        readingCorrector.didInsertLiteral()
        composition.insertLiteral(text, rawKey: rawKey)
        updateCorrection()
        return KeyResult(handled: true, actions: render(context: context))
    }

    /// 空白の幅の決め方
    private enum SpaceWidth {
        /// 設定(スペース幅)に従う
        case setting
        /// 設定と逆の幅
        case alternate
        case halfwidth
        case fullwidth
    }

    /// 空白を入れる．組み立て中の文字は確定してから入れる．
    /// 設定に従う空白は，プログラミング用のアプリでは常に半角にする
    private func insertSpace(_ width: SpaceWidth, event: KeyEvent, context: InputContext) -> KeyResult {
        // Space で英字のまま入れるところを終える
        alphabetRun = false
        let halfwidthOnly = context.profile.prefersHalfwidthSymbols
        let fullwidth = switch width {
        case .setting: settings.current.spaceWidth == .fullwidth && !halfwidthOnly
        case .alternate: settings.current.spaceWidth != .fullwidth && !halfwidthOnly
        case .halfwidth: false
        case .fullwidth: true
        }
        let actions = commitAll()
        if !fullwidth, event.key == .space, event.modifiers.subtracting(.shift).isEmpty {
            // 半角の空白は，Space そのものをアプリに渡す(アプリの補完などを妨げない)
            return KeyResult(handled: false, actions: actions)
        }
        return KeyResult(handled: true, actions: actions + [.commit(fullwidth ? Self.fullwidthSpace : " ")])
    }

    /// 変換する．英単語を直した直後は，直す前に戻す(R-02，Q-01)
    private func convert(withoutLearning: Bool, context: InputContext) -> KeyResult {
        // Space で英字のまま入れるところを終える
        alphabetRun = false
        if !withoutLearning, corrector.dismiss() {
            usage?.record(.englishCorrectionUndone)
            return KeyResult(handled: true, actions: render(context: context))
        }
        if withoutLearning { converter.suspendLearningUntilEnd() }
        // 打ち間違いの訂正を別のところで求めていて，まだ求め終わっていなければ，求め終わるまで変換を待つ．
        // 待たずに変換すると，Space を早く押したときに直すことも「もしかして」と示すこともできない
        if !waitsForCorrections, conversionCorrectionRequest != nil {
            waitsForCorrections = true
            pendingConversionLearns = !withoutLearning
            return KeyResult(handled: true, actions: [.awaitCorrections])
        }
        waitsForCorrections = false
        enterConversion()
        return KeyResult(handled: true, actions: render(context: context))
    }

    /// 変換の前に求めておく訂正のキーの並びと左の文脈．求めるものが無いか，訂正をこの中で求めるときは nil
    public var conversionCorrectionRequest: (keys: [String], leftContext: String?)? {
        guard phase == .composing, settings.current.typoCorrection == .standard,
            (composition.rawKeys?.count ?? 0) >= DefaultSettings.minimumKeysForLiveCorrection,
            let keys = readingCorrector.pendingKeys(for: composition) else { return nil }
        return (keys, compositionLeftContext)
    }

    /// 訂正を求め終わった(または待つのをやめた)あとで，待たせていた変換を続ける．待たせていなければ何もしない
    public func resumeConversion(context: InputContext) -> [ClientAction] {
        guard waitsForCorrections, phase == .composing else {
            waitsForCorrections = false
            return []
        }
        return convert(withoutLearning: !pendingConversionLearns, context: context).actions
    }

    /// ひらがな → 全角カタカナ → 半角カタカナ → ひらがな の順の次の字種．かなの字種を選んでいなければ全角カタカナ
    private func nextKanaType() -> ScriptVariant {
        guard case .selecting(let selection) = phase, case .variant(let current) = selection.focus else { return .katakana }
        switch current {
        case .hiragana: return .katakana
        case .katakana: return .halfwidthKatakana
        case .halfwidthKatakana: return .hiragana
        case .fullwidthRoman, .halfwidthRoman: return .katakana
        }
    }

    /// 変換を始める．設定が一覧でなければ分岐図にする．
    /// 英単語を補正しているときは，直した英単語を読みの中に確定させてから分岐図にする(打ったままに戻すのは補正の直後の Space)
    private func enterConversion() {
        usage?.record(.conversionOpened)
        freezeWordsReadAsRomaji()
        reviewReading()
        guard settings.current.candidatePresentation != .list else {
            phase = .selecting(makeSelection(focus: .candidate(0)))
            return
        }
        corrector.commit(into: &composition)
        let builder = LatticeBuilder(converter: converter)
        let focus = settings.current.initialFocus
        var lattice = builder.build(reading: composition.conversionReading, focus: focus)
        if !forcedBoundaries.isEmpty {
            // 打っている途中に入れた区切りで，必ず文節を分ける
            lattice = builder.splitting(lattice, at: forcedBoundaries, reading: composition.conversionReading)
            lattice.focusedIndex = lattice.initialFocus(focus)
        }
        if let suggested = readingCorrector.suggestion, readingCorrector.typedComposition(from: composition) == nil {
            // 「もしかして」と示しているときは，その文節だけ直せるよう，直した候補を該当の文節に入れる
            lattice = builder.addingCorrection(lattice, correctedReading: suggested.conversionReading, reading: composition.conversionReading)
            lattice.focusedIndex = lattice.initialFocus(focus)
        }
        if let typed = readingCorrector.typedComposition(from: composition) {
            // 打ち間違いを直した文節は，自動のときいちばん先に選ぶ(confidenceGap を最小にしてある)
            lattice = builder.addingTyped(lattice, typedReading: typed.conversionReading, reading: composition.conversionReading)
            lattice.focusedIndex = lattice.initialFocus(focus)
        }
        phase = .lattice(lattice)
    }

    /// ローマ字として読めてしまう英単語を英単語にする(「gitwotukau」→「gitを使う」)．打ち間違いを直して見せているときはしない
    private func freezeWordsReadAsRomaji() {
        guard phase == .composing, !readingCorrector.isApplied else { return }
        // 英語にも日本語にも読める語(「make」)は，前が英語のときや利用者が決めた語なら英語にする
        let context = WordLanguageContext.of(precedingText: compositionLeftContext)
        guard corrector.freezeEnglishWord(in: &composition, context: context) || corrector.freezeWordReadAsRomaji(in: &composition) else { return }
        readingCorrector.forgetReview()
        usage?.record(.englishCorrected)
    }

    /// 日本語の打ち間違いを見直す(「ようですね」→「よいですね」)．英単語を直しているときは見直さない
    private func reviewReading() {
        // 綴りを直した英単語のあとに日本語が続くときは，日本語の打ち間違いとしても見直し，直せる・示せるなら日本語に譲る
        // (tkitou → 英単語の bit ではなく 適当)．英単語の補正は取り消し，同じ位置では直し直さない
        let yields = corrector.yieldsToJapanese(in: composition)
        guard corrector.active == nil || yields else { return }
        let wasApplied = readingCorrector.isApplied
        readingCorrector.review(&composition, makeComposition: newComposition)
        if yields {
            // 日本語として確かに直せる(「もしかして」でなく直す)ときだけ譲る．示すだけの弱い訂正で英単語(jvascript → javascript)を消さない
            guard readingCorrector.isApplied else {
                readingCorrector.withdrawSuggestion()
                return
            }
            _ = corrector.dismiss()
        }
        if !wasApplied, readingCorrector.isApplied { usage?.record(.readingCorrected) }
    }

    /// 一覧の種類の行で字種を左右に移る．種類の行にいなければ何もしない
    private func handleHorizontal(forward: Bool, context: InputContext) -> KeyResult {
        guard case .selecting(var selection) = phase, case .variant(let current) = selection.focus else { return KeyResult(handled: true) }
        let available = ScriptVariant.allCases.filter { $0.apply(to: composition) != nil }
        guard let index = available.firstIndex(of: current) else { return KeyResult(handled: true) }
        let next = available[(index + (forward ? 1 : available.count - 1)) % available.count]
        selection.focus = .variant(next)
        phase = .selecting(selection)
        return KeyResult(handled: true, actions: render(context: context))
    }

    private func handleBackspace(context: InputContext) -> KeyResult {
        guard isComposing else { return .passThrough }
        if phase != .composing {
            // 候補を選んでいる途中の Backspace は，読みの組み立てに戻るだけ
            phase = .composing
            return KeyResult(handled: true, actions: render(context: context))
        }
        composition.deleteBackward()
        if composition.isEmpty {
            return KeyResult(handled: true, actions: reset())
        }
        NasalReadingResolver(converter: converter).resolve(&composition)
        forcedBoundaries.removeAll { $0 >= composition.kana.count }
        readingCorrector.didEdit(composition)
        updateCorrection()
        return KeyResult(handled: true, actions: render(context: context))
    }

    private func handleEscape(context: InputContext) -> KeyResult {
        guard isComposing else {
            // Vim のノーマルモードに戻る Escape で英数にする(設定)．Escape そのものはアプリに渡す
            guard settings.current.escapeSwitchesToDirect else { return .passThrough }
            return switchToDirectPassingEscape(actions: [])
        }
        let wasConverting = phase != .composing
        if wasConverting, let english = convertedFromEnglish, let handler = styleHandlers[settings.current.inputStyle] as? EnglishInput {
            // 英字入力の Tab で開いた分岐図は，Esc で英字に戻す
            _ = reset()
            handler.restore(english)
            return KeyResult(handled: true, actions: handler.render())
        }
        phase = .composing
        if readingCorrector.revert(&composition) {
            // 打ち間違いを直していたら，打ったままの読みに戻す
            usage?.record(.readingCorrectionUndone)
            return KeyResult(handled: true, actions: render(context: context))
        }
        if wasConverting || readingCorrector.dismissSuggestion(for: composition) {
            return KeyResult(handled: true, actions: render(context: context))
        }
        return KeyResult(handled: true, actions: reset())
    }

    /// 番号キーで候補を選ぶ．候補を選んでいるときだけ使う
    private func selectByNumber(_ number: Int) -> Bool {
        guard case .selecting(var selection) = phase, case .candidate(let index) = selection.focus else { return false }
        let perPage = settings.current.listCandidatesPerPage
        let target = index / perPage * perPage + number - 1
        guard target < selection.candidates.count else { return false }
        selection.focus = .candidate(target)
        phase = .selecting(selection)
        return true
    }

    // MARK: - 確定

    /// 組み立て中の文字を，今の表示のとおりに確定する
    private func commitAll() -> [ClientAction] {
        // EN 入力の英字と読みが両方あれば(入力方式を途中で変えたとき)，打った順に英字から確定する
        let styleActions = composingStyles.flatMap { $0.commit() }
        guard !composition.isEmpty else { return styleActions }
        return styleActions + commitComposition()
    }

    /// 組み立て中の読みを，今の表示のとおりに確定する
    private func commitComposition() -> [ClientAction] {
        // 連想の一覧で選んでいる語は，元の変換の文節に入れてから確定する
        resolveAssociation()
        if case .lattice(let lattice) = phase {
            for segment in lattice.segments where segment.selected.isFromEngine {
                converter.didCommit(segment.selected)
            }
            // 選び直した文節は，確定したときに第 1 候補でないもので数える(触って元に戻したものは数えない)
            let changed = lattice.segments.filter { $0.choice != .candidate(0) }.count
            usage?.record(.committed(changedSegments: changed, viaConversion: true))
            return [.commit(lattice.text)] + reset()
        }
        if case .selecting(let selection) = phase {
            let changed = selection.focus == .candidate(0) ? 0 : 1
            usage?.record(.committed(changedSegments: changed, viaConversion: true))
        } else {
            freezeWordsReadAsRomaji()
            usage?.record(.committed(changedSegments: 0, viaConversion: false))
        }
        var actions: [ClientAction] = []
        while !composition.isEmpty {
            let candidate = currentCandidate()
            if candidate.isFromEngine {
                converter.didCommit(candidate)
            }
            actions.append(.commit(candidate.text))
            if candidate.readingCount >= composition.conversionReading.count {
                break
            }
            // 読みの先頭だけの候補を確定したときは，残りを続けて確定する
            composition.dropReadingPrefix(candidate.readingCount)
            phase = .composing
            corrector.reset()
        }
        return actions + reset()
    }

    /// 空の読み．利用者が足したローマ字の綴りを使う
    private func newComposition() -> Composition {
        let rules = settings.current.customRomaji
        if rules != romajiTable.rules { romajiTable = (rules, RomajiTable.standard(adding: rules)) }
        let symbolRules = settings.current.symbolRules
        if symbolRules != symbolSequences.rules { symbolSequences = (symbolRules, SymbolSequenceSet(rules: symbolRules)) }
        return Composition(table: romajiTable.table, symbolSequences: symbolSequences.set)
    }

    private func reset() -> [ClientAction] {
        convertedFromEnglish = nil
        forcedBoundaries = []
        splitMode = false
        composition = newComposition()
        readingCorrector.reset()
        alphabetRun = false
        phase = .composing
        corrector.reset()
        converter.endComposition()
        return [.setMarkedText(.empty), .hideCandidates]
    }

    /// 今の表示で確定するとしたら何になるか
    private func currentCandidate() -> Candidate { candidate(in: phase) }

    /// phase の表示で確定するとしたら何になるか
    private func candidate(in phase: Phase) -> Candidate {
        let whole = composition.conversionReading.count
        switch phase {
        case .association(let list, let origin):
            return candidate(in: applying(list, to: origin))
        case .selecting(let selection):
            switch selection.focus {
            case .candidate(let index) where selection.candidates.indices.contains(index):
                return selection.candidates[index]
            case .candidate:
                break
            case .variant(let variant):
                if let text = variant.apply(to: composition) {
                    return Candidate(text: text, readingCount: whole, origin: .variant(variant))
                }
            }
        case .lattice(let lattice):
            return Candidate(text: lattice.text, readingCount: whole, origin: .combined)
        case .composing:
            if let correction = corrector.active {
                let following = corrector.followingReading(in: composition).conversionReading
                return Candidate(text: livePrefix(upTo: correction.kanaStart) + correction.word + following, readingCount: whole, origin: .correction)
            }
            // Enter は区切りなので，かなのまま見せていた語も変換して確定する．
            // ただしエディタとターミナルで英数字を打っている途中なら，見せているとおり読みのまま確定する(R-06)
            if settings.current.liveConversion, !(codeRestraintApplies && readingEndsWithAlphanumeric),
                composition.pending.isEmpty || composition.pending == "n",
                let live = liveCandidate() {
                return live
            }
        }
        return Candidate(text: composition.conversionReading, readingCount: whole, origin: .variant(.hiragana))
    }

    // MARK: - 候補

    private func liveCandidate() -> Candidate? {
        bestWholeCandidate(for: composition.conversionReading)
    }

    /// 読み全体に対応する候補のうち，いちばんよいもの．ライブ変換で見せる文字はすべてここから取る
    private func bestWholeCandidate(for reading: String) -> Candidate? {
        guard !reading.isEmpty else { return nil }
        return converter.candidates(for: reading).first { $0.readingCount == reading.count }
    }

    private func makeSelection(focus: CandidateSelection.Focus) -> CandidateSelection {
        var candidates: [Candidate] = []
        var annotations: [String?] = []
        let whole = composition.conversionReading.count
        if let correction = corrector.active {
            let prefix = livePrefix(upTo: correction.kanaStart)
            let typed = String(composition.displayReading.dropFirst(correction.kanaStart))
            let following = corrector.followingReading(in: composition).conversionReading
            candidates += [
                Candidate(text: prefix + correction.word + following, readingCount: whole, origin: .correction),
                Candidate(text: prefix + typed, readingCount: whole, origin: .asTyped),
            ]
            annotations += [nil, PanelBuilder.asTypedNote]
        }
        for candidate in converter.candidates(for: composition.conversionReading)
        where !candidates.contains(where: { $0.text == candidate.text }) {
            candidates.append(candidate)
            annotations.append(nil)
        }
        if candidates.isEmpty {
            candidates.append(Candidate(text: composition.conversionReading, readingCount: whole, origin: .variant(.hiragana)))
            annotations.append(nil)
        }
        return CandidateSelection(candidates: candidates, annotations: annotations, focus: focus)
    }

    /// 打っているあいだに出す候補(読み全体の変換と，続く語の予測)．出さない設定や，読みが短いときは空
    private func suggestionCandidates() -> [Candidate] {
        let display = settings.current.suggestionDisplay
        guard display == .always || (display == .whenLiveConversionOff && !settings.current.liveConversion),
            composition.pending.isEmpty || composition.pending == "n" else { return [] }
        let reading = composition.conversionReading
        guard reading.count >= DefaultSettings.minimumSuggestionReading else { return [] }
        var seen = Set<String>()
        let whole = converter.candidates(for: reading).filter { $0.readingCount == reading.count }
        return (whole.prefix(2) + converter.predictions(for: reading) + whole.dropFirst(2))
            .filter { seen.insert($0.text).inserted }
            .prefix(DefaultSettings.suggestionCount)
            .map { $0 }
    }

    /// 打っているあいだの候補の窓．どれも選んでいない状態で出し，↓ で選ぶ
    private func suggestionPanel() -> CandidatePanel? {
        let suggestions = suggestionCandidates()
        guard !suggestions.isEmpty else { return nil }
        return CandidatePanel(
            variants: [],
            selectedVariant: nil,
            entries: suggestions.map { CandidatePanel.Entry(text: $0.text, annotation: nil) },
            selectedEntry: nil,
            focus: .candidate,
            position: 0,
            total: suggestions.count,
            note: PanelBuilder.suggestionNote(key: keyLabel(.nextCandidate, in: .composing))
        )
    }

    private func updateCorrection() {
        let before = corrector.active
        // プログラミング用のアプリでは，日本語の文の中にある英単語だけを直す(R-06)
        let context = EnglishWordCorrector.Context(correctsOnlyInJapanese: profile.prefersHalfwidthSymbols,
                                                   precedingCharacter: compositionLeftContext?.last)
        corrector.update(for: composition, context: context)
        if before == nil, corrector.active != nil { usage?.record(.englishCorrected) }
    }

    /// 読みの先頭から kanaStart 文字目までを，ライブ変換の設定に従って表示する文字にする
    private func livePrefix(upTo kanaStart: Int) -> String {
        let prefix = String(composition.kana.prefix(kanaStart))
        guard settings.current.liveConversion else { return prefix }
        return bestWholeCandidate(for: prefix)?.text ?? prefix
    }

    // MARK: - 表示

    private func render(context: InputContext) -> [ClientAction] {
        if composition.isEmpty, let style = composingStyles.first { return style.render() }
        guard isComposing else { return reset() }
        // 学習から消したときの案内は，その操作のあとの 1 回だけ出す
        defer { pendingNote = nil }
        switch phase {
        case .composing:
            if let panel = suggestionPanel() {
                return [.setMarkedText(composingMarkedText()), .showCandidates(panel)] + correctionNote()
            }
            return [.setMarkedText(composingMarkedText()), .hideCandidates] + correctionNote()
        case .selecting(let selection):
            let candidate = currentCandidate()
            let remainder = String(composition.conversionReading.dropFirst(candidate.readingCount))
            let marked = MarkedText([.init(candidate.text, style: .focused), .init(remainder, style: .reading)])
            var panel = PanelBuilder.listPanel(for: selection, composition: composition, showsVariants: settings.current.showsVariantRow,
                                               perPage: settings.current.listCandidatesPerPage, nextKey: keyLabel(.nextCandidate, in: .converting),
                                               corrected: correctedRange(of: \.conversionReading))
            if readingCorrector.isApplied { panel.note = PanelBuilder.readingCorrectionNote(key: keyLabel(.cancel, in: .converting)) }
            if let pendingNote { panel.note = pendingNote }
            if case .candidate = selection.focus {
                panel.associationHint = associationHint(text: candidate.text, reading: String(composition.conversionReading.prefix(candidate.readingCount)))
            }
            return [.setMarkedText(marked), .showCandidates(panel)]
        case .association(let list, let origin):
            return renderAssociation(list, origin: origin)
        case .lattice(let lattice):
            // 打ち間違いを直した文節は，注目していなければ点線の下線にする
            let corrected = correctedRange(of: \.conversionReading)
            let marked = MarkedText(lattice.segments.enumerated().map { index, segment in
                let style: MarkedText.Style = index == lattice.focusedIndex ? .focused
                    : PanelBuilder.isCorrected(segment, changed: corrected) ? .correction : .converted
                return .init(segment.selected.text, style: style)
            })
            var panel = PanelBuilder.latticePanel(for: lattice, perPage: settings.current.branchCandidatesPerPage,
                                                  showsVariants: settings.current.showsVariantRow, corrected: corrected)
            let preview = LatticeBuilder(converter: converter).resizePreview(lattice, reading: composition.conversionReading)
            if let focused = panel.columns.firstIndex(where: \.isFocused) {
                panel.columns[focused].shorter = preview.shorter
                panel.columns[focused].longer = preview.longer
                panel.columns[focused].usageNote = usageNote(for: lattice)
                let segment = lattice.focused
                let segmentReading = String(composition.conversionReading.dropFirst(segment.readingStart).prefix(segment.readingLength))
                panel.columns[focused].sourceName = converter.sourceName(of: segment.selected.text, reading: segmentReading)
                panel.associationHint = associationHint(text: segment.selected.text, reading: segmentReading)
            }
            if readingCorrector.isApplied { panel.note = PanelBuilder.readingCorrectionNote(key: keyLabel(.cancel, in: .converting)) }
            if splitMode {
                panel = PanelBuilder.splitting(panel, pieces: focusedSplit(lattice).pieces)
            }
            if let pendingNote { panel.note = pendingNote }
            return [.setMarkedText(marked), .showLattice(panel)]
        }
    }

    /// キー設定の表で，その状態のそのコマンドに割り当てた最初のキーの名前(案内に出す)．無ければ nil
    private func keyLabel(_ command: KeymapCommand, in state: KeymapState) -> String? {
        settings.current.keymap.strokes(for: command, in: state).first?.label
    }

    /// 打ち間違いを直したこと，または「もしかして」を入力位置の近くに出す．
    /// 文はライブ変換の設定に従って見せる(直す前の文・直した文のどちらも)
    private func correctionNote() -> [ClientAction] {
        guard showsCorrectionNote else { return [] }
        let shown = { (reading: String) -> String in
            guard self.settings.current.liveConversion else { return reading }
            return self.bestWholeCandidate(for: reading)?.text ?? reading
        }
        if readingCorrector.isApplied, let typed = readingCorrector.typedComposition(from: composition) {
            return [.showNote(PanelBuilder.readingCorrectedNote(typed: shown(typed.conversionReading), key: keyLabel(.cancel, in: .composing)))]
        }
        if let suggestion = readingCorrector.suggestion {
            let phrase = correctedPhrase(reading: suggestion.conversionReading, other: composition.conversionReading) ?? shown(suggestion.conversionReading)
            return [.showNote(PanelBuilder.readingSuggestionNote(phrase, key: keyLabel(.acceptSuggestion, in: .composing)))]
        }
        return []
    }

    /// 直した読み(reading)を変換した文のうち，other と違う部分を含む文節(「もしかして」の案内に出す)．
    /// 文全体を出すと，長い文ではどこを直す案なのかが分からないため．文節に分けられなければ nil
    private func correctedPhrase(reading: String, other: String) -> String? {
        guard settings.current.liveConversion, let best = bestWholeCandidate(for: reading),
            let changed = CorrectedSpan.changedRange(from: other, to: reading) else { return nil }
        let units = ClauseSplitter.clauses(of: best.words).map { CorrectedSpan.Unit(text: $0.text, readingCount: $0.readingCount) }
        guard let pieces = CorrectedSpan.pieces(of: best.text, units: units, readingCount: reading.count, changed: changed),
            let range = CorrectedSpan.textRange(of: pieces) else { return nil }
        return String(Array(best.text)[range])
    }

    private func setLeftContext(_ text: String?) {
        compositionLeftContext = text
        converter.setLeftContext(text)
    }

    /// 注目している文節で選んでいる候補の使い分けと誤用の注釈(設定でオンのものだけ)
    private func usageNote(for lattice: SegmentLattice) -> String? {
        let segment = lattice.focused
        let text = segment.selected.text
        let reading = String(composition.conversionReading.dropFirst(segment.readingStart).prefix(segment.readingLength))
        let notes = [
            settings.current.misuseNotes ? UsageGuide.misuseNote(for: lattice.text) : nil,
            settings.current.proofreading ? Proofreading.note(for: lattice.text) : nil,
            settings.current.homophoneNotes ? UsageGuide.homophoneNote(for: text, reading: reading) : nil,
        ].compactMap { $0 }
        return notes.isEmpty ? nil : notes.joined(separator: "　")
    }

    // MARK: - 分岐図と一覧の操作(キー設定の表のコマンド)

    /// 候補の動かし方
    private enum CandidateMove {
        case next, previous, nextPage, previousPage, first, last
    }

    /// 候補を動かす．分岐図では注目している文節の候補，一覧では一覧の候補．
    /// 入力中の 次の候補・前の候補 は変換を始める(変換 と違い，英単語を直した直後でも戻さない)
    private func moveCandidate(_ move: CandidateMove, context: InputContext) -> KeyResult {
        switch phase {
        case .composing:
            alphabetRun = false
            // 打っているあいだの候補を出しているときは，↓ でその候補から選ぶ
            let suggestions = move == .next ? suggestionCandidates() : []
            if suggestions.isEmpty {
                enterConversion()
            } else {
                phase = .selecting(CandidateSelection(candidates: suggestions, annotations: suggestions.map { _ in nil }, focus: .candidate(0)))
            }
        case .lattice(var lattice):
            let perPage = settings.current.branchCandidatesPerPage
            switch move {
            case .next: lattice.moveSelection(by: 1)
            case .previous: lattice.moveSelection(by: -1, entersVariants: settings.current.showsVariantRow)
            case .nextPage: lattice.moveToPage(by: 1, perPage: perPage)
            case .previousPage: lattice.moveToPage(by: -1, perPage: perPage)
            case .first: lattice.selectCandidate(at: 0)
            case .last: lattice.selectCandidate(at: lattice.focused.candidates.count - 1)
            }
            phase = .lattice(lattice)
        case .selecting(var selection):
            let perPage = settings.current.listCandidatesPerPage
            switch move {
            case .next:
                // 種類の行からは候補の先頭に戻る
                selection.moveCandidate(by: 1)
            case .previous:
                switch selection.focus {
                case .variant:
                    break
                case .candidate(let index):
                    if index == 0 && settings.current.showsVariantRow {
                        // 候補一覧の先頭で前の候補に進むと種類の行に移る(R-03)
                        selection.focus = .variant(.hiragana)
                    } else {
                        selection.moveCandidate(by: -1)
                    }
                }
            case .nextPage: selection.movePage(by: 1, perPage: perPage)
            case .previousPage: selection.movePage(by: -1, perPage: perPage)
            case .first: selection.focus = .candidate(0)
            case .last: selection.focus = .candidate(max(selection.candidates.count - 1, 0))
            }
            phase = .selecting(selection)
        case .association:
            // 連想の一覧の中の動きは performInAssociation が受け持つ
            break
        }
        return KeyResult(handled: true, actions: render(context: context))
    }

    /// 文節の動かし方
    private enum SegmentMove {
        case next, previous, first, last, nextUncertain, previousUncertain, extend, shrink, extendToWord, shrinkToWord, split
    }

    /// 文節を移る・長さを変える・区切る．一覧は文節が 1 つなので，種類の行にいるときの左右だけ字種を移る
    private func moveSegment(_ move: SegmentMove, context: InputContext) -> KeyResult {
        switch phase {
        case .composing, .association:
            // 連想の一覧の中の動きは performInAssociation が受け持つ
            return KeyResult(handled: true)
        case .selecting:
            switch move {
            case .next: return handleHorizontal(forward: true, context: context)
            case .previous: return handleHorizontal(forward: false, context: context)
            case .first, .last, .nextUncertain, .previousUncertain, .extend, .shrink, .extendToWord, .shrinkToWord, .split: return KeyResult(handled: true)
            }
        case .lattice(var lattice):
            let builder = LatticeBuilder(converter: converter)
            switch move {
            case .next: lattice.moveFocus(by: 1)
            case .previous: lattice.moveFocus(by: -1)
            case .first: lattice.focusedIndex = 0
            case .last: lattice.focusedIndex = lattice.segments.count - 1
            case .nextUncertain: lattice.moveToUncertain(forward: true)
            case .previousUncertain: lattice.moveToUncertain(forward: false)
            case .extend, .shrink:
                let length = lattice.focused.readingLength + (move == .extend ? 1 : -1)
                lattice = builder.resize(lattice, segmentAt: lattice.focusedIndex, to: length, reading: composition.conversionReading)
            case .extendToWord, .shrinkToWord:
                // 文節の終わりを次・前の語の切れ目まで動かす(1 文字ずつより少ない打鍵で長さを変える)
                lattice = builder.resizeToWord(lattice, grow: move == .extendToWord, reading: composition.conversionReading)
            case .split:
                // 区切れる位置が 2 つ以上の文字のときだけ区切る状態にする
                splitMode = !splitMode && !focusedSplit(lattice).positions.isEmpty
            }
            phase = .lattice(lattice)
            return KeyResult(handled: true, actions: render(context: context))
        }
    }

    // MARK: - 連想変換(R-18)

    /// 連想の一覧の 1 ページの語の数．元の出し方(分岐図か一覧)の候補の数に合わせる
    private var associationPerPage: Int {
        if case .association(_, .selecting) = phase { return settings.current.listCandidatesPerPage }
        return settings.current.branchCandidatesPerPage
    }

    /// 連想変換のキー．入力中なら変換してから，変換中なら選んでいる文節を，連想の一覧に切り替える．
    /// 連想変換を使わない設定のときは，入力中ならふつうに変換する
    private func associate(context: InputContext) -> KeyResult {
        guard associationFinder.isEnabled else {
            return phase == .composing ? convert(withoutLearning: false, context: context) : KeyResult(handled: true)
        }
        if phase == .composing {
            alphabetRun = false
            waitsForCorrections = false
            enterConversion()
        }
        if !enterAssociation() {
            pendingNote = associationFinder.hasDictionaries ? PanelBuilder.noAssociationNote : PanelBuilder.noAssociationDictionaryNote
        }
        return KeyResult(handled: true, actions: render(context: context))
    }

    /// 選んでいる文節(一覧なら選んでいる候補)の連想の一覧に切り替える．連想が無ければ false
    private func enterAssociation() -> Bool {
        let base: (text: String, reading: String)
        switch phase {
        case .lattice(let lattice):
            base = (lattice.focused.selected.text, focusedReading(lattice))
        case .selecting:
            let candidate = currentCandidate()
            base = (candidate.text, String(composition.conversionReading.prefix(candidate.readingCount)))
        case .composing, .association:
            return false
        }
        guard let associations = associationFinder.find(text: base.text, reading: base.reading) else { return false }
        phase = .association(AssociationList(associations), origin: phase)
        return true
    }

    /// 連想の一覧を出しているときのコマンド．一覧の中で動く・元の変換に戻るものはここで行う．
    /// ほかのコマンドは，選んでいる語を元の変換の文節に入れてから，ふつうに行う(nil を返す)
    private func performInAssociation(_ command: KeymapCommand, list: AssociationList, origin: Phase, context: InputContext) -> KeyResult? {
        var list = list
        switch command {
        case .nextCandidate: list.move(by: 1)
        case .previousCandidate: list.move(by: -1)
        case .nextCandidatePage: list.movePage(by: 1, perPage: associationPerPage)
        case .previousCandidatePage: list.movePage(by: -1, perPage: associationPerPage)
        case .firstCandidate: list.selectFirst()
        case .lastCandidate: list.selectLast()
        // 左右(と迷う文節へ移るキー)で意味のまとまりを移る
        case .nextSegment, .nextUncertainSegment: list.moveGroup(by: 1)
        case .previousSegment, .previousUncertainSegment: list.moveGroup(by: -1)
        case .cancel, .backToReading, .associate:
            // 元の変換に戻る
            phase = origin
            return KeyResult(handled: true, actions: render(context: context))
        default:
            resolveAssociation()
            return nil
        }
        phase = .association(list, origin: origin)
        return KeyResult(handled: true, actions: render(context: context))
    }

    /// 連想の一覧で選んでいる語を元の変換の文節に入れ，連想の一覧を閉じる
    private func resolveAssociation() {
        guard case .association(let list, let origin) = phase else { return }
        phase = applying(list, to: origin)
    }

    /// origin(一覧か文節格子)の選んでいるところを，連想の一覧で選んでいる語にしたもの．
    /// 語は候補に足して選ぶ(元の候補にあればそれを選ぶ)．足した語は学習しない(CandidateOrigin.association)
    private func applying(_ list: AssociationList, to origin: Phase) -> Phase {
        let word = list.selectedWord
        switch origin {
        case .lattice(var lattice):
            var segment = lattice.focused
            if let index = segment.candidates.firstIndex(where: { $0.text == word }) {
                segment.choice = .candidate(index)
            } else {
                segment.candidates.append(Candidate(text: word, readingCount: segment.readingLength, origin: .association))
                segment.choice = .candidate(segment.candidates.count - 1)
            }
            segment.isDecided = true
            lattice.segments[lattice.focusedIndex] = segment
            return .lattice(lattice)
        case .selecting(var selection):
            let base = candidate(in: origin)
            if let index = selection.candidates.firstIndex(where: { $0.text == word && $0.readingCount == base.readingCount }) {
                selection.focus = .candidate(index)
            } else {
                selection.candidates.append(Candidate(text: word, readingCount: base.readingCount, origin: .association))
                selection.annotations.append(nil)
                selection.focus = .candidate(selection.candidates.count - 1)
            }
            return .selecting(selection)
        case .composing, .association:
            return origin
        }
    }

    /// 連想の一覧の表示．入力欄には選んでいる語を入れた文を見せる
    private func renderAssociation(_ list: AssociationList, origin: Phase) -> [ClientAction] {
        switch applying(list, to: origin) {
        case .lattice(let lattice):
            let marked = MarkedText(lattice.segments.enumerated().map { index, segment in
                .init(segment.selected.text, style: index == lattice.focusedIndex ? .focused : .converted)
            })
            let panel = PanelBuilder.associationLatticePanel(for: lattice, list: list, perPage: settings.current.branchCandidatesPerPage)
            return [.setMarkedText(marked), .showLattice(panel)]
        case .selecting(let selection):
            let candidate = candidate(in: .selecting(selection))
            let remainder = String(composition.conversionReading.dropFirst(candidate.readingCount))
            let marked = MarkedText([.init(candidate.text, style: .focused), .init(remainder, style: .reading)])
            let panel = PanelBuilder.associationListPanel(for: list, perPage: settings.current.listCandidatesPerPage)
            return [.setMarkedText(marked), .showCandidates(panel)]
        case .composing, .association:
            return []
        }
    }

    /// 選んでいる候補に連想があるときの知らせ．知らせない設定か，連想が無ければ nil
    private func associationHint(text: String, reading: String) -> String? {
        guard settings.current.showsAssociationHint, associationFinder.hasDictionaries,
            associationFinder.find(text: text, reading: reading) != nil else { return nil }
        return PanelBuilder.associationHint(key: keyLabel(.associate, in: .converting))
    }

    /// 分岐図の先頭の文節だけを確定し，残りの文節は選んだ候補のまま変換を続ける．文節が 1 つなら全体を確定する
    private func commitFirstSegment(context: InputContext) -> KeyResult {
        guard case .lattice(var lattice) = phase, lattice.segments.count > 1 else { return KeyResult(handled: true, actions: commitAll()) }
        let first = lattice.segments.removeFirst()
        if first.selected.isFromEngine { converter.didCommit(first.selected) }
        usage?.record(.committed(changedSegments: first.choice == .candidate(0) ? 0 : 1, viaConversion: true))
        composition.dropReadingPrefix(first.readingLength)
        for index in lattice.segments.indices { lattice.segments[index].readingStart -= first.readingLength }
        lattice.focusedIndex = max(lattice.focusedIndex - 1, 0)
        forcedBoundaries = forcedBoundaries.map { $0 - first.readingLength }.filter { $0 > 0 }
        // 確定した文節で読みの先頭が変わるので，打ち間違いの訂正と英字に戻す手がかりは捨てる
        readingCorrector.reset()
        corrector.reset()
        convertedFromEnglish = nil
        phase = .lattice(lattice)
        return KeyResult(handled: true, actions: [.commit(first.selected.text)] + render(context: context))
    }

    /// 文節を数字で区切っているときのキー．数字で区切り，Esc でやめる．ほかのキーは区切るのをやめてからふつうに処理する(nil)
    private func handleSplit(_ event: KeyEvent, lattice: inout SegmentLattice, context: InputContext) -> KeyResult? {
        splitMode = false
        switch event.key {
        case .character(let character) where character.wholeNumberValue != nil && event.modifiers.isEmpty:
            // 数字で選んだ位置で区切る．区切ったあとは前の文節に注目したまま
            let positions = focusedSplit(lattice).positions
            if let number = character.wholeNumberValue, positions.indices.contains(number - 1) {
                let builder = LatticeBuilder(converter: converter)
                lattice = builder.resize(lattice, segmentAt: lattice.focusedIndex, to: positions[number - 1], reading: composition.conversionReading)
            }
            phase = .lattice(lattice)
            return KeyResult(handled: true, actions: render(context: context))
        case .escape:
            phase = .lattice(lattice)
            return KeyResult(handled: true, actions: render(context: context))
        default:
            return nil
        }
    }

    /// 分岐図の番号キー．番号で選んだら，まだ選んでいない迷う文節へ進む．残っていなければ確定する(1 回の判断で済ませる)．
    /// 番号キーでなければ nil
    private func selectInLattice(_ character: Character, lattice: inout SegmentLattice, context: InputContext) -> KeyResult? {
        guard let number = numberKey(character), lattice.select(number: number, perPage: settings.current.branchCandidatesPerPage) else { return nil }
        return KeyResult(handled: true, actions: advance(after: lattice, context: context))
    }

    /// 分岐図で文節の候補を選んだあと，まだ選んでいない迷う文節へ進む．残っていなければ確定する
    private func advance(after chosen: SegmentLattice, context: InputContext) -> [ClientAction] {
        var lattice = chosen
        guard let next = lattice.segments.indices.first(where: { !lattice.segments[$0].isConfident && !lattice.segments[$0].isDecided }) else {
            phase = .lattice(lattice)
            return commitAll()
        }
        lattice.focusedIndex = next
        phase = .lattice(lattice)
        return render(context: context)
    }

    /// 候補の窓をマウスで押した．キーで同じことをしたときと同じに動く:
    /// 分岐図の幹は文節を選び(←→)，枝は番号キーで選んだのと同じ(迷う文節へ進むか確定)，一覧の行は選んで確定する(番号 → Enter)．
    /// 押した対象が今の状態に無ければ何もしない
    public func choose(_ target: PointerTarget, context: InputContext) -> [ClientAction] {
        switch (phase, target) {
        case (.lattice(var lattice), .segment(let index)):
            guard lattice.segments.indices.contains(index) else { return [] }
            lattice.focusedIndex = index
            phase = .lattice(lattice)
            return render(context: context)
        case (.lattice(var lattice), .alternative(let index)):
            guard lattice.select(number: index + 1, perPage: settings.current.branchCandidatesPerPage) else { return [] }
            return advance(after: lattice, context: context)
        case (.lattice(var lattice), .variant(let index)):
            guard lattice.selectVariant(at: index) else { return [] }
            return advance(after: lattice, context: context)
        case (.selecting, .entry(let index)):
            guard selectByNumber(index + 1) else { return [] }
            return commitAll()
        case (.selecting(var selection), .listVariant(let index)):
            guard ScriptVariant.allCases.indices.contains(index), ScriptVariant.allCases[index].apply(to: composition) != nil else { return [] }
            selection.focus = .variant(ScriptVariant.allCases[index])
            phase = .selecting(selection)
            return commitAll()
        default:
            return []
        }
    }

    /// 注目している文節の読み
    private func focusedReading(_ lattice: SegmentLattice) -> String {
        String(composition.conversionReading.dropFirst(lattice.focused.readingStart).prefix(lattice.focused.readingLength))
    }

    /// 注目している文節を区切れる位置で分けたもの．意味のある切れ目(「問題｜が｜ある」)だけにし，1 文字ずつは ⇧←→ に任せる．
    /// 切れ目が無い文節では positions が空(区切る状態に入らない)
    private func focusedSplit(_ lattice: SegmentLattice) -> SegmentSplitter.Split {
        let reading = focusedReading(lattice)
        let converter = converter
        return SegmentSplitter.split(
            shown: lattice.focused.selected.text, reading: reading,
            candidates: { part in converter.dictionaryCandidates(for: part).filter { $0.readingCount == part.count }.map(\.text) },
            words: converter.segmentationWords(for:))
    }

    /// エディタとターミナルでライブ変換を控えめにするか(R-06．設定)
    private var codeRestraintApplies: Bool {
        settings.current.restrainsLiveConversionInCode && (profile == .programming || profile == .terminal)
    }

    /// 読みの末尾が英数字か(識別子を打っている途中)
    private var readingEndsWithAlphanumeric: Bool {
        composition.pending.isEmpty && composition.kana.last.map(Composition.isAlphanumeric) == true
    }

    /// ライブ変換を控え，読みのまま見せるか(R-06)．打鍵が止まるまでと，英数字を打っているあいだ
    private var holdsLiveConversionForCode: Bool {
        codeRestraintApplies && (!isSettled || readingEndsWithAlphanumeric)
    }

    private func composingMarkedText() -> MarkedText {
        if let correction = corrector.active {
            return MarkedText([
                .init(livePrefix(upTo: correction.kanaStart), style: .converted),
                .init(correction.word, style: .correction),
                .init(corrector.followingReading(in: composition).displayReading, style: .reading),
            ])
        }
        guard settings.current.liveConversion, !holdsLiveConversionForCode else {
            // 打ち間違いを直した読みは，直したかなだけを点線の下線にする
            if let changed = correctedRange(of: \.kana) {
                let kana = Candidate(text: composition.kana, readingCount: composition.kana.count, origin: .variant(.hiragana))
                return MarkedText(Self.markedSegments(CorrectedSpan.pieces(of: kana, reading: composition.kana, changed: changed), otherwise: .reading)
                    + [.init(composition.pending, style: .reading)])
            }
            return MarkedText([.init(composition.displayReading, style: .reading)])
        }
        // ローマ字の途中(「ky」など)は変換せず，かなになった部分だけを変換して見せる
        let reading = composition.kana
        if !forcedBoundaries.isEmpty, !readingCorrector.isApplied {
            // 区切りを入れたところで分けて変換し，文節ごとに下線を分けて見せる
            var segments: [MarkedText.Segment] = []
            var start = 0
            for end in (forcedBoundaries.sorted() + [reading.count]) where end > start && end <= reading.count {
                let piece = String(reading.dropFirst(start).prefix(end - start))
                segments.append(.init(bestWholeCandidate(for: piece)?.text ?? piece, style: .converted))
                start = end
            }
            return MarkedText(segments + [.init(composition.pending, style: .reading)])
        }
        let best = bestWholeCandidate(for: reading)
        let shown = best.map { LiveConversionRule().display(of: $0, reading: reading, settled: isSettled) } ?? reading
        // 打ち間違いを直した読みは，直した語句だけを点線の下線にする．どこを直したかが分かるように
        if readingCorrector.isApplied {
            let candidate = best ?? Candidate(text: reading, readingCount: reading.count, origin: .variant(.hiragana))
            let pieces = correctedRange(of: \.kana).map {
                CorrectedSpan.aligning(CorrectedSpan.pieces(of: candidate, reading: reading, changed: $0), to: shown)
            } ?? [CorrectedSpan.Piece(shown, isCorrected: true)]
            return MarkedText(Self.markedSegments(pieces, otherwise: .converted) + [.init(composition.pending, style: .reading)])
        }
        return MarkedText([
            .init(shown, style: .converted),
            .init(composition.pending, style: .reading),
        ])
    }

    /// 打ち間違いを直して見せている読みのうち，直した部分(読みの先頭からの文字数)．直していなければ nil．
    /// reading は比べる読み(ライブ変換の表示は kana，変換は conversionReading)
    private func correctedRange(of reading: KeyPath<Composition, String>) -> Range<Int>? {
        guard readingCorrector.isApplied, let typed = readingCorrector.typedComposition(from: composition) else { return nil }
        return CorrectedSpan.changedRange(from: typed[keyPath: reading], to: composition[keyPath: reading])
    }

    /// 直した部分は補正の下線，そのほかは style にする
    private static func markedSegments(_ pieces: [CorrectedSpan.Piece], otherwise style: MarkedText.Style) -> [MarkedText.Segment] {
        pieces.map { .init($0.text, style: $0.isCorrected ? .correction : style) }
    }
}

extension InputSession {
    fileprivate static let fullwidthSpace = "\u{3000}"
    fileprivate static let zSymbolKeys: Set<Character> = [".", ",", "/", "[", "]"]

    fileprivate func numberKey(_ character: Character) -> Int? {
        guard settings.current.numberKeySelection, let value = character.wholeNumberValue, (1...9).contains(value) else { return nil }
        return value
    }
}

