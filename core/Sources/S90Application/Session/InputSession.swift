import S90Domain

/// 入力欄ひとつぶんの入力の状態を進める．キーを受け取り，画面への操作(ClientAction)の列を返す．
///
/// 状態は 4 つある．
/// - 何も組み立てていない
/// - 読みを組み立てている(ライブ変換の結果か読みを表示する)
/// - 候補を一覧から選んでいる(候補ウィンドウを出す)
/// - 文節格子で文節ごとに候補を選んでいる(格子のウィンドウを出す)
@MainActor
public final class InputSession {
    private enum Phase: Equatable {
        case composing
        case selecting(CandidateSelection)
        case lattice(SegmentLattice)
    }


    private let converter: any KanaKanjiConverting
    private let lexicon: any EnglishLexicon
    private let settings: any SettingsReading

    public private(set) var mode: InputMode = .japanese
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
    /// 英字入力の Tab で日本語にした語の英字．分岐図で Esc を押したら英字に戻す
    private var convertedFromEnglish: String?
    /// 組み立てを始めたときの，入力位置の前の文字列(打ち間違いの訂正の手がかり)
    private var compositionLeftContext: String?
    /// 見直した直後の表示か．打ち間違いの案内は見直した直後だけ出し，次のキーで消す
    /// (打つたびに直す前の文も変換すると，1 キーの処理が重くなるため)
    private var showsCorrectionNote = false

    /// 使い方の記録(回数だけ)．記録しないときは nil
    private let usage: (any UsageRecording)?

    /// - Parameter typoService: 打ち間違いの訂正を別のところで求めるもの．nil なら変換器で求める(テストと Zenzai の無いとき)
    public init(converter: any KanaKanjiConverting, lexicon: any EnglishLexicon, settings: any SettingsReading, usage: (any UsageRecording)? = nil,
                typoService: (any TypoCorrecting)? = nil) {
        self.converter = converter
        self.lexicon = lexicon
        self.settings = settings
        self.usage = usage
        self.corrector = EnglishWordCorrector(lexicon: lexicon, settings: settings)
        self.readingCorrector = ReadingCorrector(converter: converter, settings: settings, usesProvidedCorrections: typoService != nil)
        self.styleHandlers = [.english: EnglishInput(converter: converter), .kana: KanaInput()]
    }

    public var isComposing: Bool { !composition.isEmpty || !composingStyles.isEmpty }

    // MARK: - 外からの操作

    public func handle(_ event: KeyEvent, context: InputContext) -> KeyResult {
        if context.isSecure {
            // パスワード欄では何もしない(docs/dev/SECURITY-MODEL.md)
            return .passThrough
        }
        showsCorrectionNote = false
        let result = route(event, context: context)
        // ターミナルの行には，どの経路で確定した文字もアプリに渡ったキーも，ここで 1 か所で数える
        if context.profile == .terminal { terminal.didHandle(event, result: result) }
        return result
    }

    private func route(_ event: KeyEvent, context: InputContext) -> KeyResult {
        if event.modifiers.contains(.command) {
            // ショートカットはアプリに任せる．組み立て中の文字は先に確定する
            return KeyResult(handled: false, actions: commitAll())
        }
        // 設定を開く・ライブ変換を切り替えるキー．入力メニューの操作を取り次がないアプリでも効くよう，キーで受ける
        if mode == .japanese, let command = settings.current.conversionKeys.command(for: event), command.isGlobal {
            let actions = commitAll()
            return KeyResult(handled: true, actions: actions + [command == .openSettings ? .openSettings : .toggleLiveConversion])
        }
        if context.profile == .direct {
            // IME を使わないアプリ(除外設定)では，日本語のモードでも英数のまま入れる
            return KeyResult(handled: false, actions: commitAll())
        }
        if event.modifiers.contains(.option), case .character = event.key {
            // Option との組み合わせで入る特殊な文字(å など)は，アプリの配列に任せる
            return KeyResult(handled: false, actions: commitAll())
        }
        if mode == .japanese, event.isKeypad, settings.current.keypadDirect, case .character(let character) = event.key {
            // テンキーの数字と記号は，組み立て中の文字を確定してから半角のまま確定する(設定)
            return KeyResult(handled: true, actions: commitAll() + [.commit(String(character))])
        }
        if !(event.key == .kana && event.modifiers.contains(.option)), let result = applyModeKey(event) {
            return result
        }
        switch mode {
        case .direct: return handleDirect(event, context: context)
        case .japanese: return handleJapanese(event, context: context)
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

    /// 読みを組み立てていて，打鍵が止まるのを待っているか．待っていれば，止まったときに settle を呼ぶ．
    /// EN 入力の英字は変換して見せないので待たない
    public var awaitsSettle: Bool {
        !composition.isEmpty && phase == .composing && !isSettled && settings.current.liveConversion
    }

    private func switchToDirectPassingEscape(actions: [ClientAction]) -> KeyResult {
        mode = .direct
        return KeyResult(handled: false, actions: actions + [.selectMode(.direct)] + modeIndicator(.direct))
    }

    /// 日本語と英数を切り替えるキー(英数・かな・半角/全角・変換・無変換)．割り当て(ModeKeyAssignments)に従う．
    /// 切り替えに使わないキーは nil を返し，ふつうの処理に回す
    private func applyModeKey(_ event: KeyEvent) -> KeyResult? {
        let keys = settings.current.modeKeys
        guard let action = keys.action(for: event.key), action != .none,
            let target = keys.mode(after: event.key, from: mode) else { return nil }
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
        return render(context: context)
    }

    /// 打鍵がさらに止まるのを待って，打ち間違いを見直すか．待っていれば，止まったときに review を呼ぶ
    public var awaitsReview: Bool {
        isSettled && phase == .composing && corrector.active == nil && !readingCorrector.isReviewed(composition)
            && (settings.current.typoCorrection == .standard || settings.current.misreadings)
            && (composition.rawKeys?.count ?? 0) >= DefaultSettings.minimumKeysForLiveCorrection
    }

    /// 見直すために，別のところで求める訂正のキーの並びと左の文脈．求めるものが無ければ nil
    public var correctionRequest: (keys: [String], leftContext: String?)? {
        guard awaitsReview, let keys = readingCorrector.pendingKeys(for: composition) else { return nil }
        return (keys, compositionLeftContext)
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

    private func handleDirect(_ event: KeyEvent, context: InputContext) -> KeyResult {
        switch event.key {
        case .kana where event.modifiers.contains(.option):
            // 英数のときも，Option+かな は日本語に戻して入力方式を切り替える
            mode = .japanese
            return KeyResult(handled: true, actions: [.selectMode(.japanese), .selectInputStyle(nextInputStyle())])
        case .yen:
            let text = settings.current.yenKey.character(profile: context.profile, optionPressed: event.modifiers.contains(.option))
            return KeyResult(handled: true, actions: [.commit(text)])
        default:
            // 切り替えに使わないと決めた英数・かな・半角/全角・変換・無変換は，アプリに渡す
            return .passThrough
        }
    }

    // MARK: - 日本語モード

    /// 日本語モードのキー．次の順に回し，前の段で扱ったキーは後ろに回さない．
    /// 1. 入力方式が前のキーから変わっていたら，組み立て中の文字を確定する
    /// 2. ターミナルの行(コマンドの行で英字をそのまま流す判断は，ほかの処理より先に要る．
    ///    行の長さと行の終わりは，処理の結果を見て TerminalLine.didHandle で数える)
    /// 3. Control の組み合わせ(R-03)
    /// 4. 分岐図の操作
    /// 5. 入力方式ごとの処理(EN 入力・かな入力)
    /// 6. ローマ字入力と共通の処理
    private func handleJapanese(_ event: KeyEvent, context: InputContext) -> KeyResult {
        isSettled = false
        let styleChange = adoptInputStyle()
        if !styleChange.isEmpty, !Self.continuesAfterStyleChange(event) {
            // メニューなどで入力方式が変わっていたら，前の方式の文字を確定する．Backspace・Escape・Enter・Space・矢印などは
            // 確定した文字に効いて意味が変わるので，確定だけにして飲み込む．文字・¥・英数・かなは新しい方式で続けて処理する
            return KeyResult(handled: true, actions: styleChange)
        }
        let routed = routeJapanese(event, context: context)
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

    private func routeJapanese(_ event: KeyEvent, context: InputContext) -> KeyResult {
        if context.profile == .terminal, settings.current.terminalCommands, let result = applyTerminal(event) {
            return result
        }
        // 分岐図では，利用者が割り当てたキー(Control 付きも)を Ctrl+J などより先に見る
        if case .lattice(var lattice) = phase, settings.current.conversionKeys.command(for: event) != nil,
            let result = handleLattice(event, lattice: &lattice, context: context) {
            return result
        }
        if event.modifiers.contains(.control) {
            return handleControl(event, context: context)
        }
        if case .lattice(var lattice) = phase, let result = handleLattice(event, lattice: &lattice, context: context) {
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
        case .kana where event.modifiers.contains(.option):
            // Option+かな で入力方式を順に切り替える(ローマ字 → かな → 英語 → ローマ字)
            return KeyResult(handled: true, actions: commitAll() + [.selectInputStyle(nextInputStyle())])
        case .kana, .eisu, .hankakuZenkaku:
            // 切り替えに使わないと決めたとき
            return isComposing ? KeyResult(handled: true) : .passThrough
        case .henkan:
            // 変換キーは，切り替えに使わないときは Space と同じに変換する
            return isComposing ? handleSpace(shift: false, context: context) : .passThrough
        case .muhenkan:
            // 無変換キーは，切り替えに使わないときはカタカナにする
            return isComposing ? selectVariant(.katakana, context: context) : .passThrough
        case .yen:
            let text = settings.current.yenKey.character(profile: context.profile, optionPressed: event.modifiers.contains(.option))
            return insertLiteral(text, rawKey: nil, context: context)
        case .character(let character):
            return insertCharacter(character, context: context)
        case .space:
            return handleSpace(shift: event.modifiers.contains(.shift), context: context)
        case .enter:
            guard isComposing else { return .passThrough }
            return KeyResult(handled: true, actions: commitAll())
        case .backspace:
            return handleBackspace(context: context)
        case .escape:
            return handleEscape(context: context)
        case .up:
            return handleVertical(forward: false, context: context)
        case .down:
            return handleVertical(forward: true, context: context)
        case .left, .right:
            return handleHorizontal(forward: event.key == .right)
        case .tab:
            guard isComposing else { return .passThrough }
            // 「もしかして」と示していた読みに直す
            if phase == .composing, readingCorrector.acceptSuggestion(&composition) {
                usage?.record(.readingCorrected)
                showsCorrectionNote = true
                return KeyResult(handled: true, actions: render(context: context))
            }
            return KeyResult(handled: true)
        case .function(let number):
            guard !composition.isEmpty, let variant = Self.functionKeyVariants[number] else { return .passThrough }
            return selectVariant(variant, context: context)
        }
    }

    // MARK: - ターミナル(R-07)

    /// ターミナルの行の判断に従う．ふつうの処理に回すときは nil
    private func applyTerminal(_ event: KeyEvent) -> KeyResult? {
        let composingKeys = phase == .composing && !composition.isEmpty ? composition.rawKeys : nil
        switch terminal.decide(event, isComposing: isComposing, composingKeys: composingKeys, holdsLetters: settings.current.inputStyle == .english) {
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
        if style == .english, !composition.isEmpty, case .character(let character) = event.key, character.isASCII, character.isLetter {
            let committed = commitAll()
            if case .handled(let result)? = handler.interpret(event, state: InputStyleState(settings: settings.current, selectableCount: 0)) {
                return KeyResult(handled: result.handled, actions: committed + result.actions)
            }
            return KeyResult(handled: true, actions: committed)
        }
        // 英字入力で日本語の読みを組み立てているあいだ(Tab で開いた分岐図)は，ほかのキーをふつうの処理に回す(Enter で確定など)
        if style == .english, !composition.isEmpty { return nil }
        let state = InputStyleState(settings: settings.current, selectableCount: selectableCount)
        switch handler.interpret(event, state: state) {
        case nil:
            return nil
        case .handled(let result):
            return result
        case .convertRomaji(let keys):
            // 英字入力の語を日本語の読みにし，分岐図で変換を選べるようにする．Esc で英字に戻す
            var actions: [ClientAction] = commitAll()
            if !isComposing { setLeftContext(context.precedingText) }
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
            if !isComposing { setLeftContext(context.precedingText) }
            composition.insertKana(kana)
            if settings.current.punctuationCommits, SymbolTable.isPunctuation(kana, settings: settings.current) {
                return KeyResult(handled: true, actions: actions + commitAll())
            }
            return KeyResult(handled: true, actions: actions + render(context: context))
        }
    }

    private func handleControl(_ event: KeyEvent, context: InputContext) -> KeyResult {
        // EN 入力の英字は，確定してからキーをアプリに渡す(Ctrl+A などで英字が残らないように)
        if !composingStyles.isEmpty { return KeyResult(handled: false, actions: commitAll()) }
        // 字種を選ぶ割り当て(R-03)
        guard !composition.isEmpty, case .character(let character) = event.key else { return .passThrough }
        let variant: ScriptVariant? = switch character.lowercased() {
        case "j": .hiragana
        case "k": .katakana
        case ";": .halfwidthKatakana
        case "l": .fullwidthRoman
        case ":", "'": .halfwidthRoman
        default: nil
        }
        guard let variant else { return KeyResult(handled: true) }
        return selectVariant(variant, context: context)
    }

    /// 読み全体を字種に変えて選ぶ(Ctrl+J/K/;/L/: と F6〜F10)
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
        if phase != .composing {
            // 候補を選んでいる途中で打ち始めたら，選んでいる候補を確定して続ける
            actions += commitAll()
        }
        if !isComposing {
            composition = newComposition()
            // 打ち始めに，入力位置の前の文字列を変換の手がかりとして渡す(「AAA」+「まで」)
            setLeftContext(context.precedingText)
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
            corrector.commit(into: &composition)
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
            corrector.commit(into: &composition)
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

    private func handleSpace(shift: Bool, context: InputContext) -> KeyResult {
        // Space で英字のまま入れるところを終える
        alphabetRun = false
        guard isComposing else {
            // 空白の幅は設定に従い，Shift+Space で逆の幅にする．プログラミング用のアプリでは常に半角
            let fullwidth = (settings.current.spaceWidth == .fullwidth) != shift
            guard fullwidth, !context.profile.prefersHalfwidthSymbols else { return .passThrough }
            return KeyResult(handled: true, actions: [.commit(Self.fullwidthSpace)])
        }
        switch phase {
        case .composing:
            if corrector.dismiss() {
                usage?.record(.englishCorrectionUndone)
                // 補正の直後の Space は，補正を取り消す(R-02，Q-01)
                return KeyResult(handled: true, actions: render(context: context))
            }
            enterConversion()
        case .selecting(var selection):
            selection.moveCandidate(by: 1)
            phase = .selecting(selection)
        case .lattice:
            break
        }
        return KeyResult(handled: true, actions: render(context: context))
    }

    /// 変換を始める．設定が一覧でなければ分岐図にする．
    /// 英単語を補正しているときは，直した英単語を読みの中に確定させてから分岐図にする(打ったままに戻すのは補正の直後の Space)
    private func enterConversion() {
        usage?.record(.conversionOpened)
        reviewReading()
        guard settings.current.candidatePresentation != .list else {
            phase = .selecting(makeSelection(focus: .candidate(0)))
            return
        }
        corrector.commit(into: &composition)
        let builder = LatticeBuilder(converter: converter)
        let focus = settings.current.initialFocus
        var lattice = builder.build(reading: composition.conversionReading, focus: focus)
        if let typed = readingCorrector.typedComposition(from: composition) {
            // 打ち間違いを直した文節は，自動のときいちばん先に選ぶ(confidenceGap を最小にしてある)
            lattice = builder.addingTyped(lattice, typedReading: typed.conversionReading, reading: composition.conversionReading)
            lattice.focusedIndex = lattice.initialFocus(focus)
        }
        phase = .lattice(lattice)
    }

    /// 日本語の打ち間違いを見直す(「ようですね」→「よいですね」)．英単語を直しているときは見直さない
    private func reviewReading() {
        guard corrector.active == nil else { return }
        let wasApplied = readingCorrector.isApplied
        readingCorrector.review(&composition, makeComposition: newComposition)
        if !wasApplied, readingCorrector.isApplied { usage?.record(.readingCorrected) }
    }

    private func handleVertical(forward: Bool, context: InputContext) -> KeyResult {
        guard isComposing else { return .passThrough }
        switch phase {
        case .composing:
            enterConversion()
        case .lattice:
            break
        case .selecting(var selection):
            switch selection.focus {
            case .variant:
                // 種類の行から下キーで候補一覧に戻る
                if forward { selection.focus = .candidate(0) }
            case .candidate(let index):
                if !forward && index == 0 && settings.current.showsVariantRow {
                    // 候補一覧の先頭で上キーを押すと種類の行に移る(R-03)
                    selection.focus = .variant(.hiragana)
                } else {
                    selection.moveCandidate(by: forward ? 1 : -1)
                }
            }
            phase = .selecting(selection)
        }
        return KeyResult(handled: true, actions: render(context: context))
    }

    private func handleHorizontal(forward: Bool) -> KeyResult {
        guard isComposing else { return .passThrough }
        guard case .selecting(var selection) = phase, case .variant(let current) = selection.focus else {
            // 文節の区切りを変える操作は，まだ用意していない
            return KeyResult(handled: true)
        }
        let available = ScriptVariant.allCases.filter { $0.apply(to: composition) != nil }
        guard let index = available.firstIndex(of: current) else { return KeyResult(handled: true) }
        let next = available[(index + (forward ? 1 : available.count - 1)) % available.count]
        selection.focus = .variant(next)
        phase = .selecting(selection)
        return KeyResult(handled: true, actions: render(context: .init()))
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
        if wasConverting, let english = convertedFromEnglish, let handler = styleHandlers[.english] as? EnglishInput {
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
        composition = newComposition()
        readingCorrector.reset()
        alphabetRun = false
        phase = .composing
        corrector.reset()
        converter.endComposition()
        return [.setMarkedText(.empty), .hideCandidates]
    }

    /// 今の表示で確定するとしたら何になるか
    private func currentCandidate() -> Candidate {
        let whole = composition.conversionReading.count
        switch phase {
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
            // Enter は区切りなので，かなのまま見せていた語も変換して確定する
            if settings.current.liveConversion, composition.pending.isEmpty || composition.pending == "n",
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

    private func updateCorrection() {
        let before = corrector.active
        corrector.update(for: composition)
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
        switch phase {
        case .composing:
            return [.setMarkedText(composingMarkedText()), .hideCandidates] + correctionNote()
        case .selecting(let selection):
            let candidate = currentCandidate()
            let remainder = String(composition.conversionReading.dropFirst(candidate.readingCount))
            let marked = MarkedText([.init(candidate.text, style: .focused), .init(remainder, style: .reading)])
            var panel = PanelBuilder.listPanel(for: selection, composition: composition, showsVariants: settings.current.showsVariantRow, perPage: settings.current.listCandidatesPerPage)
            if readingCorrector.isApplied { panel.note = PanelBuilder.readingCorrectionNote }
            return [.setMarkedText(marked), .showCandidates(panel)]
        case .lattice(let lattice):
            let marked = MarkedText(lattice.segments.enumerated().map { index, segment in
                .init(segment.selected.text, style: index == lattice.focusedIndex ? .focused : .converted)
            })
            var panel = PanelBuilder.latticePanel(for: lattice, perPage: settings.current.branchCandidatesPerPage)
            let preview = LatticeBuilder(converter: converter).resizePreview(lattice, reading: composition.conversionReading)
            if let focused = panel.columns.firstIndex(where: \.isFocused) {
                panel.columns[focused].shorter = preview.shorter
                panel.columns[focused].longer = preview.longer
            }
            if readingCorrector.isApplied { panel.note = PanelBuilder.readingCorrectionNote }
            return [.setMarkedText(marked), .showLattice(panel)]
        }
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
            return [.showNote(PanelBuilder.readingCorrectedNote(typed: shown(typed.conversionReading)))]
        }
        if let suggestion = readingCorrector.suggestion {
            return [.showNote(PanelBuilder.readingSuggestionNote(shown(suggestion.conversionReading)))]
        }
        return []
    }

    private func setLeftContext(_ text: String?) {
        compositionLeftContext = text
        converter.setLeftContext(text)
    }

    // MARK: - 分岐図

    /// 分岐図のときのキー．nil を返したキーは，ふつうの処理に回す．
    /// ↓ と Space は下の枝(変換の候補)へ，↑ は上の枝(字種)へ．Tab は迷う文節だけを渡り歩く(ADR 0007)
    private func handleLattice(_ event: KeyEvent, lattice: inout SegmentLattice, context: InputContext) -> KeyResult? {
        let builder = LatticeBuilder(converter: converter)
        // キーの割り当ては設定で変えられる(KeyBindings)
        if let command = settings.current.conversionKeys.command(for: event) {
            switch command {
            case .openSettings, .toggleLiveConversion:
                // route が先に受ける
                break
            case .nextCandidate: lattice.moveSelection(by: 1)
            case .previousCandidate: lattice.moveSelection(by: -1)
            case .nextSegment: lattice.moveFocus(by: 1)
            case .previousSegment: lattice.moveFocus(by: -1)
            case .nextUncertainSegment: lattice.moveToUncertain(forward: true)
            case .previousUncertainSegment: lattice.moveToUncertain(forward: false)
            case .extendSegment, .shrinkSegment:
                let length = lattice.focused.readingLength + (command == .extendSegment ? 1 : -1)
                lattice = builder.resize(lattice, segmentAt: lattice.focusedIndex, to: length, reading: composition.conversionReading)
            }
            phase = .lattice(lattice)
            return KeyResult(handled: true, actions: render(context: context))
        }
        switch event.key {
        case .character(let character):
            guard let number = numberKey(character), lattice.select(number: number, perPage: settings.current.branchCandidatesPerPage) else { return nil }
            // 番号で選んだら，まだ選んでいない迷う文節へ進む．残っていなければ確定する(1 回の判断で済ませる)
            guard let next = lattice.segments.indices.first(where: { !lattice.segments[$0].isConfident && !lattice.segments[$0].isDecided }) else {
                phase = .lattice(lattice)
                return KeyResult(handled: true, actions: commitAll())
            }
            lattice.focusedIndex = next
        default:
            return nil
        }
        phase = .lattice(lattice)
        return KeyResult(handled: true, actions: render(context: context))
    }

    private func composingMarkedText() -> MarkedText {
        if let correction = corrector.active {
            return MarkedText([
                .init(livePrefix(upTo: correction.kanaStart), style: .converted),
                .init(correction.word, style: .correction),
                .init(corrector.followingReading(in: composition).displayReading, style: .reading),
            ])
        }
        guard settings.current.liveConversion else {
            return MarkedText([.init(composition.displayReading, style: .reading)])
        }
        // ローマ字の途中(「ky」など)は変換せず，かなになった部分だけを変換して見せる
        let reading = composition.kana
        let shown = bestWholeCandidate(for: reading).map {
            LiveConversionRule().display(of: $0, reading: reading, settled: isSettled)
        }
        // 打ち間違いを直した読みは，点線の下線で直したことを見せる
        return MarkedText([
            .init(shown ?? reading, style: readingCorrector.isApplied ? .correction : .converted),
            .init(composition.pending, style: .reading),
        ])
    }
}

extension InputSession {
    fileprivate static let fullwidthSpace = "\u{3000}"
    /// F6〜F10 で選ぶ字種
    fileprivate static let functionKeyVariants: [Int: ScriptVariant] = [
        6: .hiragana, 7: .katakana, 8: .halfwidthKatakana, 9: .fullwidthRoman, 10: .halfwidthRoman,
    ]
    fileprivate static let zSymbolKeys: Set<Character> = [".", ",", "/", "[", "]"]

    fileprivate func numberKey(_ character: Character) -> Int? {
        guard settings.current.numberKeySelection, let value = character.wholeNumberValue, (1...9).contains(value) else { return nil }
        return value
    }
}

