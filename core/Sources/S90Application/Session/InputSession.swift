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
    private var phase: Phase = .composing
    /// 英単語の補正(R-02)
    private let corrector: EnglishWordCorrector
    /// EN 入力(R-05)．入力方式が英語のときだけ使う
    private let english: EnglishInput
    /// ターミナルで打っている行の状態(R-07)
    private var commandLine = CommandLineState()
    /// 日本語の打ち間違いを直す前の読み．Esc で戻せるように覚えておく
    private var typedBeforeCorrection: Composition?
    /// 打鍵が止まったか．止まるまでは打っている途中の語をかなのまま見せる(LiveConversionRule)
    private var isSettled = false

    /// 使い方の記録(回数だけ)．記録しないときは nil
    private let usage: (any UsageRecording)?

    public init(converter: any KanaKanjiConverting, lexicon: any EnglishLexicon, settings: any SettingsReading, usage: (any UsageRecording)? = nil) {
        self.converter = converter
        self.lexicon = lexicon
        self.settings = settings
        self.usage = usage
        self.corrector = EnglishWordCorrector(lexicon: lexicon, settings: settings)
        self.english = EnglishInput(converter: converter)
    }

    public var isComposing: Bool { !composition.isEmpty || english.isComposing }

    // MARK: - 外からの操作

    public func handle(_ event: KeyEvent, context: InputContext) -> KeyResult {
        if context.isSecure {
            // パスワード欄では何もしない(docs/dev/SECURITY-MODEL.md)
            return .passThrough
        }
        if event.modifiers.contains(.command) {
            // ショートカットはアプリに任せる．組み立て中の文字は先に確定する
            return KeyResult(handled: false, actions: commitAll())
        }
        if event.modifiers.contains(.option), case .character = event.key {
            // Option との組み合わせで入る特殊な文字(å など)は，アプリの配列に任せる
            return KeyResult(handled: false, actions: commitAll())
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
        return actions
    }

    /// 入力欄からフォーカスが外れた．組み立て中の文字は確定する
    public func deactivate() -> [ClientAction] {
        commitAll()
    }

    /// 読みを組み立てていて，打鍵が止まるのを待っているか．待っていれば，止まったときに settle を呼ぶ
    public var awaitsSettle: Bool {
        isComposing && phase == .composing && !isSettled && settings.current.liveConversion
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

    // MARK: - 英数モード

    private func handleDirect(_ event: KeyEvent, context: InputContext) -> KeyResult {
        switch event.key {
        case .yen:
            let text = settings.current.yenKey.character(profile: context.profile, optionPressed: event.modifiers.contains(.option))
            return KeyResult(handled: true, actions: [.commit(text)])
        case .kana:
            mode = .japanese
            return KeyResult(handled: true, actions: [.selectMode(.japanese)] + modeIndicator(.japanese))
        case .eisu:
            return KeyResult(handled: true, actions: modeIndicator(.direct))
        default:
            return .passThrough
        }
    }

    // MARK: - 日本語モード

    private func handleJapanese(_ event: KeyEvent, context: InputContext) -> KeyResult {
        isSettled = false
        if event.modifiers.contains(.control) {
            return handleControl(event, context: context)
        }
        if case .lattice(var lattice) = phase, let result = handleLattice(event, lattice: &lattice, context: context) {
            return result
        }
        if context.profile == .terminal, let result = handleTerminal(event, context: context) {
            return result
        }
        if settings.current.inputStyle == .english, let result = handleEnglish(event) {
            return result
        }
        if settings.current.inputStyle == .kana, let result = handleKana(event, context: context) {
            return result
        }
        switch event.key {
        case .kana:
            return KeyResult(handled: true, actions: modeIndicator(.japanese))
        case .eisu:
            var actions = commitAll()
            mode = .direct
            actions += [.selectMode(.direct)] + modeIndicator(.direct)
            return KeyResult(handled: true, actions: actions)
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
            return isComposing ? KeyResult(handled: true) : .passThrough
        }
    }

    // MARK: - ターミナル(R-07)

    /// ターミナルのキー．nil を返したキーは，ふつうの処理に回す
    private func handleTerminal(_ event: KeyEvent, context: InputContext) -> KeyResult? {
        switch event.key {
        case .enter where !isComposing:
            commandLine.endLine()
            return nil
        case .space where phase == .composing && !composition.isEmpty:
            // 行の頭でコマンドの名前を打って Space を押したら，打ったとおりの英字で確定してコマンドの行に入る
            guard let keys = composition.rawKeys, commandLine.didTypeFirstWord(keys) else { return nil }
            reset()
            return KeyResult(handled: true, actions: [.commit(keys + " "), .setMarkedText(.empty), .hideCandidates])
        case .character(let character) where commandLine.passesThrough && !isComposing && !event.modifiers.contains(.control):
            // コマンドの行では英字も記号もそのまま流す
            commandLine.didPass(character)
            return .passThrough
        case .character(let character) where isComposing && commandLine.region == .quoted(character):
            // 引用符の中の日本語は，閉じる引用符で確定し，引用符はそのまま流す
            commandLine.didPass(character)
            return KeyResult(handled: false, actions: commitAll())
        case .character(let character) where !isComposing && (character == "\"" || character == "'"):
            // 引用符を閉じたらコマンドの行に戻る
            commandLine.didPass(character)
            return .passThrough
        case .character(let character) where event.modifiers.contains(.control) && (character == "c" || character == "u"):
            // Ctrl+C・Ctrl+U は行を捨てる
            commandLine.endLine()
            return nil
        default:
            return nil
        }
    }

    // MARK: - 入力方式(R-05)

    /// EN 入力のキー．nil を返したキー(モードの切り替えなど)は，ふつうの処理に回す
    private func handleEnglish(_ event: KeyEvent) -> KeyResult? {
        switch event.key {
        case .character(let character) where character.isASCII && character.isLetter:
            english.append(character)
            return KeyResult(handled: true, actions: english.render())
        case .tab:
            guard english.isComposing else { return .passThrough }
            return KeyResult(handled: true, actions: english.commitSuggestion())
        case .backspace:
            guard english.isComposing else { return .passThrough }
            english.deleteBackward()
            return KeyResult(handled: true, actions: english.render())
        case .escape:
            guard english.isComposing else { return .passThrough }
            return KeyResult(handled: true, actions: english.commitTyped())
        case .eisu, .kana, .yen:
            return nil
        default:
            // Space・Enter・数字・記号・矢印は，打った英字を確定してからアプリに渡す(英語の入力と同じ動き)
            return KeyResult(handled: false, actions: english.commitTyped())
        }
    }

    /// かな入力のキー．かなに当たらないキーは nil を返し，ふつうの処理に回す
    private func handleKana(_ event: KeyEvent, context: InputContext) -> KeyResult? {
        guard !event.modifiers.contains(.option) else { return nil }
        let kana: String? = switch event.key {
        case .character: event.keyLabel.flatMap { KanaLayout.kana(forKey: $0, shift: event.modifiers.contains(.shift)) }
        case .yen: KanaLayout.kana(forKey: "¥", shift: false)
        default: nil
        }
        guard let kana else { return nil }
        var actions: [ClientAction] = []
        if phase != .composing { actions += commitAll() }
        if !isComposing { converter.setLeftContext(context.precedingText) }
        composition.insertKana(kana)
        return KeyResult(handled: true, actions: actions + render(context: context))
    }

    private func handleControl(_ event: KeyEvent, context: InputContext) -> KeyResult {
        // macOS の日本語入力と同じ割り当て(R-03)
        guard !composition.isEmpty, case .character(let character) = event.key else { return .passThrough }
        let variant: ScriptVariant? = switch character.lowercased() {
        case "j": .hiragana
        case "k": .katakana
        case ";": .halfwidthKatakana
        case "l": .fullwidthRoman
        case ":", "'": .halfwidthRoman
        default: nil
        }
        guard let variant, variant.apply(to: composition) != nil else { return KeyResult(handled: true) }
        let selection = makeSelection(focus: .variant(variant))
        phase = .selecting(selection)
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
            // 打ち始めに，入力位置の前の文字列を変換の手がかりとして渡す(「AAA」+「まで」)
            converter.setLeftContext(context.precedingText)
        }
        let isRomaji = (character.isASCII && character.isLetter && character.isLowercase)
            || character == "-"
            || (character == "'" && composition.pending == "n")
            // 「z.」→「…」，「z[」→「『」など，z と組み合わせる記号
            || (composition.pending == "z" && Self.zSymbolKeys.contains(character))
        if isRomaji {
            composition.insertRomaji(character)
            NasalReadingResolver(converter: converter).resolve(&composition)
            if corrector.active != nil, corrector.handleFollowingRomaji(in: &composition) == .waiting {
                return KeyResult(handled: true, actions: actions + render(context: context))
            }
        } else if character.isASCII && (character.isLetter || character.isNumber) {
            corrector.commit(into: &composition)
            let text = character.isNumber && settings.current.numberWidth == .fullwidth
                ? KanaWidth.fullwidthASCII(from: String(character))
                : String(character)
            composition.insertLiteral(text, rawKey: character)
        } else {
            let text = SymbolTable.text(for: character, profile: context.profile, settings: settings.current)
            if !isComposing && text == String(character) {
                // 半角のままの記号は，組み立てを始めずにアプリへ渡す(プログラミング中に Enter を要求しない)
                return KeyResult(handled: false, actions: actions)
            }
            corrector.commit(into: &composition)
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
        composition.insertLiteral(text, rawKey: rawKey)
        updateCorrection()
        return KeyResult(handled: true, actions: render(context: context))
    }

    private func handleSpace(shift: Bool, context: InputContext) -> KeyResult {
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
    /// 英単語を補正しているときは，補正と入力のままを並べて比べられるよう一覧にする
    private func enterConversion() {
        usage?.record(.conversionOpened)
        correctReading()
        if settings.current.candidatePresentation != .list, corrector.active == nil {
            phase = .lattice(LatticeBuilder(converter: converter).build(reading: composition.conversionReading))
            return
        }
        phase = .selecting(makeSelection(focus: .candidate(0)))
    }

    /// 日本語の打ち間違いを直す(「ようですね」→「よいですね」)．変換を始めるときだけ行う．
    /// 打ち間違いを探すのは重いので打鍵ごとにはせず，直したことは画面に出して Esc で戻せるようにする
    private func correctReading() {
        typedBeforeCorrection = nil
        guard corrector.active == nil, let keys = composition.rawKeys, !keys.isEmpty,
            keys.allSatisfy({ ($0.isASCII && $0.isLetter && $0.isLowercase) || $0 == "-" }),
            composition.pending.isEmpty || composition.pending == "n" else { return }
        let rule = ReadingCorrectionRule(level: settings.current.typoCorrection)
        guard let correction = rule.correction(among: converter.typoCorrections(forKeys: keys), reading: composition.conversionReading)
        else { return }
        // 打ったときと同じ順にキーを入れ直し，「nn」のあとの母音の読みも打つときと同じ決まりで選ぶ
        var corrected = Composition()
        let resolver = NasalReadingResolver(converter: converter)
        for key in correction.keys {
            corrected.insertRomaji(key)
            resolver.resolve(&corrected)
        }
        guard !corrected.isEmpty, corrected.conversionReading != composition.conversionReading else { return }
        typedBeforeCorrection = composition
        composition = corrected
        usage?.record(.readingCorrected)
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
        updateCorrection()
        return KeyResult(handled: true, actions: render(context: context))
    }

    private func handleEscape(context: InputContext) -> KeyResult {
        guard isComposing else {
            // Vim のノーマルモードに戻る Escape で英数にする(設定)．Escape そのものはアプリに渡す
            guard settings.current.escapeSwitchesToDirect else { return .passThrough }
            mode = .direct
            return KeyResult(handled: false, actions: [.selectMode(.direct)] + modeIndicator(.direct))
        }
        if phase != .composing {
            phase = .composing
            if let typed = typedBeforeCorrection {
                // 打ち間違いを直していたら，打ったままの読みに戻す
                composition = typed
                typedBeforeCorrection = nil
                usage?.record(.readingCorrectionUndone)
            }
            return KeyResult(handled: true, actions: render(context: context))
        }
        return KeyResult(handled: true, actions: reset())
    }

    /// 番号キーで候補を選ぶ．候補を選んでいるときだけ使う
    private func selectByNumber(_ number: Int) -> Bool {
        guard case .selecting(var selection) = phase, case .candidate(let index) = selection.focus else { return false }
        let pageStart = index / DefaultSettings.candidatesPerPage * DefaultSettings.candidatesPerPage
        let target = pageStart + number - 1
        guard target < selection.candidates.count else { return false }
        selection.focus = .candidate(target)
        phase = .selecting(selection)
        return true
    }

    // MARK: - 確定

    /// 組み立て中の文字を，今の表示のとおりに確定する
    private func commitAll() -> [ClientAction] {
        if english.isComposing { return english.commitTyped() }
        guard isComposing else { return [] }
        if case .lattice(let lattice) = phase {
            for segment in lattice.segments where segment.selected.isFromEngine {
                converter.didCommit(segment.selected)
            }
            usage?.record(.committed(changedSegments: lattice.segments.filter(\.isDecided).count, viaConversion: true))
            return [.commit(lattice.text)] + reset()
        }
        if case .selecting(let selection) = phase {
            let changed = selection.focus == .candidate(0) ? 0 : 1
            usage?.record(.committed(changedSegments: changed, viaConversion: true))
        } else {
            usage?.record(.committed(changedSegments: 0, viaConversion: false))
        }
        var actions: [ClientAction] = []
        while isComposing {
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

    private func reset() -> [ClientAction] {
        if !composition.isEmpty { commandLine.didCommitText() }
        composition = Composition()
        typedBeforeCorrection = nil
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
        guard isComposing else { return reset() }
        switch phase {
        case .composing:
            return [.setMarkedText(composingMarkedText()), .hideCandidates]
        case .selecting(let selection):
            let candidate = currentCandidate()
            let remainder = String(composition.conversionReading.dropFirst(candidate.readingCount))
            let marked = MarkedText([.init(candidate.text, style: .focused), .init(remainder, style: .reading)])
            var panel = PanelBuilder.listPanel(for: selection, composition: composition, showsVariants: settings.current.showsVariantRow)
            if typedBeforeCorrection != nil { panel.note = PanelBuilder.readingCorrectionNote }
            return [.setMarkedText(marked), .showCandidates(panel)]
        case .lattice(let lattice):
            let marked = MarkedText(lattice.segments.enumerated().map { index, segment in
                .init(segment.selected.text, style: index == lattice.focusedIndex ? .focused : .converted)
            })
            var panel = PanelBuilder.latticePanel(for: lattice)
            if typedBeforeCorrection != nil { panel.note = PanelBuilder.readingCorrectionNote }
            return [.setMarkedText(marked), .showLattice(panel)]
        }
    }

    // MARK: - 分岐図

    /// 分岐図のときのキー．nil を返したキーは，ふつうの処理に回す．
    /// ↓ と Space は下の枝(変換の候補)へ，↑ は上の枝(字種)へ．Tab は迷う文節だけを渡り歩く(ADR 0007)
    private func handleLattice(_ event: KeyEvent, lattice: inout SegmentLattice, context: InputContext) -> KeyResult? {
        let builder = LatticeBuilder(converter: converter)
        switch event.key {
        case .left, .right:
            let forward = event.key == .right
            if event.modifiers.contains(.shift) {
                // Shift+←→ で注目している文節の区切りを動かす
                let length = lattice.focused.readingLength + (forward ? 1 : -1)
                lattice = builder.resize(lattice, segmentAt: lattice.focusedIndex, to: length, reading: composition.conversionReading)
            } else {
                lattice.moveFocus(by: forward ? 1 : -1)
            }
        case .tab:
            lattice.moveToUncertain(forward: !event.modifiers.contains(.shift))
        case .up:
            lattice.moveSelection(by: -1)
        case .down, .space:
            lattice.moveSelection(by: 1)
        case .character(let character):
            guard let number = numberKey(character), lattice.select(number: number) else { return nil }
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
        return MarkedText([
            .init(shown ?? reading, style: .converted),
            .init(composition.pending, style: .reading),
        ])
    }
}

extension InputSession {
    fileprivate static let fullwidthSpace = "\u{3000}"
    fileprivate static let zSymbolKeys: Set<Character> = [".", ",", "/", "[", "]"]

    fileprivate func numberKey(_ character: Character) -> Int? {
        guard settings.current.numberKeySelection, let value = character.wholeNumberValue, (1...DefaultSettings.candidatesPerPage).contains(value) else { return nil }
        return value
    }
}

