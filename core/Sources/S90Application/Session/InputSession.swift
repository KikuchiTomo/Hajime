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
    /// 補正した結果．補正が無いか，取り消したときは nil
    private var correction: String?
    /// 利用者が補正を取り消した．同じ読みを打ち続けるあいだは補正し直さない(Q-01)
    private var correctionDismissed = false

    public init(converter: any KanaKanjiConverting, lexicon: any EnglishLexicon, settings: any SettingsReading) {
        self.converter = converter
        self.lexicon = lexicon
        self.settings = settings
    }

    public var isComposing: Bool { !composition.isEmpty }

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

    // MARK: - 英数モード

    private func handleDirect(_ event: KeyEvent, context: InputContext) -> KeyResult {
        switch event.key {
        case .yen:
            let text = settings.current.yenKey.character(profile: context.profile, optionPressed: event.modifiers.contains(.option))
            return KeyResult(handled: true, actions: [.commit(text)])
        case .kana:
            mode = .japanese
            return KeyResult(handled: true, actions: [.selectMode(.japanese), .showModeIndicator(.japanese)])
        case .eisu:
            return KeyResult(handled: true, actions: [.showModeIndicator(.direct)])
        default:
            return .passThrough
        }
    }

    // MARK: - 日本語モード

    private func handleJapanese(_ event: KeyEvent, context: InputContext) -> KeyResult {
        if event.modifiers.contains(.control) {
            return handleControl(event, context: context)
        }
        if case .lattice(var lattice) = phase, let result = handleLattice(event, lattice: &lattice, context: context) {
            return result
        }
        switch event.key {
        case .kana:
            return KeyResult(handled: true, actions: [.showModeIndicator(.japanese)])
        case .eisu:
            var actions = commitAll()
            mode = .direct
            actions += [.selectMode(.direct), .showModeIndicator(.direct)]
            return KeyResult(handled: true, actions: actions)
        case .yen:
            let text = settings.current.yenKey.character(profile: context.profile, optionPressed: event.modifiers.contains(.option))
            return insertLiteral(text, rawKey: nil, context: context)
        case .character(let character):
            return insertCharacter(character, context: context)
        case .space:
            return handleSpace(context: context)
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

    private func handleControl(_ event: KeyEvent, context: InputContext) -> KeyResult {
        // macOS の日本語入力と同じ割り当て(R-03)
        guard isComposing, case .character(let character) = event.key else { return .passThrough }
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
        let isRomaji = (character.isASCII && character.isLetter && character.isLowercase)
            || character == "-"
            || (character == "'" && composition.pending == "n")
        if isRomaji {
            composition.insertRomaji(character)
        } else if character.isASCII && (character.isLetter || character.isNumber) {
            composition.insertLiteral(String(character), rawKey: character)
        } else {
            let text = SymbolTable.text(for: character, profile: context.profile)
            if !isComposing && text == String(character) {
                // 半角のままの記号は，組み立てを始めずにアプリへ渡す(プログラミング中に Enter を要求しない)
                return KeyResult(handled: false, actions: actions)
            }
            composition.insertLiteral(text, rawKey: nil)
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
        composition.insertLiteral(text, rawKey: rawKey)
        updateCorrection()
        return KeyResult(handled: true, actions: render(context: context))
    }

    private func handleSpace(context: InputContext) -> KeyResult {
        guard isComposing else { return .passThrough }
        switch phase {
        case .composing:
            if correction != nil {
                // 補正の直後の Space は，補正を取り消す(R-02，Q-01)
                correction = nil
                correctionDismissed = true
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

    /// 変換を始める．設定と文節の数から，一覧か文節格子かを決める
    private func enterConversion() {
        let presentation = settings.current.candidatePresentation
        if presentation != .list, correction == nil {
            let lattice = LatticeBuilder(converter: converter).build(reading: composition.conversionReading)
            if presentation == .lattice || lattice.segments.count >= 2 {
                phase = .lattice(lattice)
                return
            }
        }
        phase = .selecting(makeSelection(focus: .candidate(0)))
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
        updateCorrection()
        return KeyResult(handled: true, actions: render(context: context))
    }

    private func handleEscape(context: InputContext) -> KeyResult {
        guard isComposing else { return .passThrough }
        if phase != .composing {
            phase = .composing
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
        guard isComposing else { return [] }
        if case .lattice(let lattice) = phase {
            for segment in lattice.segments where isEngine(segment.selected) {
                converter.didCommit(segment.selected)
            }
            return [.commit(lattice.text)] + reset()
        }
        var actions: [ClientAction] = []
        while isComposing {
            let candidate = currentCandidate()
            if case .engine = candidate.origin {
                converter.didCommit(candidate)
            }
            actions.append(.commit(candidate.text))
            if candidate.readingCount >= composition.conversionReading.count {
                break
            }
            // 読みの先頭だけの候補を確定したときは，残りを続けて確定する
            composition.dropReadingPrefix(candidate.readingCount)
            phase = .composing
            correction = nil
        }
        return actions + reset()
    }

    private func reset() -> [ClientAction] {
        composition = Composition()
        phase = .composing
        correction = nil
        correctionDismissed = false
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
            return Candidate(text: lattice.text, readingCount: whole, origin: .variant(.hiragana))
        case .composing:
            if let correction {
                return Candidate(text: correction, readingCount: whole, origin: .correction)
            }
            if settings.current.liveConversion, composition.pending.isEmpty || composition.pending == "n",
                let live = liveCandidate() {
                return live
            }
        }
        return Candidate(text: composition.conversionReading, readingCount: whole, origin: .variant(.hiragana))
    }

    // MARK: - 候補

    private func liveCandidate() -> Candidate? {
        let reading = composition.conversionReading
        return converter.candidates(for: reading).first { $0.readingCount == reading.count }
    }

    private func makeSelection(focus: CandidateSelection.Focus) -> CandidateSelection {
        var candidates: [Candidate] = []
        var annotations: [String?] = []
        let whole = composition.conversionReading.count
        if let correction {
            candidates += [
                Candidate(text: correction, readingCount: whole, origin: .correction),
                Candidate(text: composition.displayReading, readingCount: whole, origin: .asTyped),
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
        let rule = TypoCorrectionRule(level: settings.current.typoCorrection)
        guard !correctionDismissed, let keys = rule.candidateKeys(in: composition) else {
            correction = nil
            return
        }
        let isWord = lexicon.isWord(keys)
        correction = rule.correction(for: keys, isWord: isWord, suggestions: isWord ? [] : lexicon.suggestions(for: keys))
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
            return [.setMarkedText(marked), .showCandidates(PanelBuilder.listPanel(for: selection, composition: composition, showsVariants: settings.current.showsVariantRow))]
        case .lattice(let lattice):
            let marked = MarkedText(lattice.segments.enumerated().map { index, segment in
                .init(segment.selected.text, style: index == lattice.focusedIndex ? .focused : .converted)
            })
            return [.setMarkedText(marked), .showLattice(PanelBuilder.latticePanel(for: lattice))]
        }
    }


    private func isEngine(_ candidate: Candidate) -> Bool {
        if case .engine = candidate.origin { true } else { false }
    }

    // MARK: - 文節格子

    /// 文節格子のときのキー．nil を返したキーは，ふつうの処理に回す
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
            lattice.moveFocus(by: event.modifiers.contains(.shift) ? -1 : 1)
        case .up:
            lattice.moveSelection(by: -1)
        case .down, .space:
            lattice.moveSelection(by: 1)
        case .character(let character):
            guard let number = numberKey(character), lattice.select(number: number) else { return nil }
            // 番号で選んだら次の文節に進む．最後の文節なら確定する
            if lattice.focusedIndex == lattice.segments.count - 1 {
                phase = .lattice(lattice)
                return KeyResult(handled: true, actions: commitAll())
            }
            lattice.moveFocus(by: 1)
        default:
            return nil
        }
        phase = .lattice(lattice)
        return KeyResult(handled: true, actions: render(context: context))
    }

    private func composingMarkedText() -> MarkedText {
        if let correction {
            return MarkedText([.init(correction, style: .correction)])
        }
        guard settings.current.liveConversion else {
            return MarkedText([.init(composition.displayReading, style: .reading)])
        }
        // ローマ字の途中(「ky」など)は変換せず，かなになった部分だけを変換して見せる
        let reading = composition.kana
        let live = reading.isEmpty ? nil : converter.candidates(for: reading).first { $0.readingCount == reading.count }
        return MarkedText([
            .init(live?.text ?? reading, style: .converted),
            .init(composition.pending, style: .reading),
        ])
    }

}

extension InputSession {
    fileprivate func numberKey(_ character: Character) -> Int? {
        guard let value = character.wholeNumberValue, (1...DefaultSettings.candidatesPerPage).contains(value) else { return nil }
        return value
    }
}

