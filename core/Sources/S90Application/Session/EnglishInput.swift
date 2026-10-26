import S90Domain

/// 英語のまま入力する(EN 入力．R-05)．打った英字をそのまま見せ，ローマ字として読める並びには日本語の候補を添える．
///
/// Space・Enter・記号は英語の入力と同じに動く(打った英字を確定し，キーはアプリに渡す)．
/// 日本語にするのは Tab を押したときだけ(Q-02)．英語を打つ人の手の流れを変えないため．
/// Tab では確定せず，分岐図を開いて変換を選べるようにする．Esc で英字に戻せる
@MainActor
final class EnglishInput: InputStyleHandling {
    private let converter: any KanaKanjiConverting
    private(set) var typed = ""

    init(converter: any KanaKanjiConverting) {
        self.converter = converter
    }

    var isComposing: Bool { !typed.isEmpty }

    /// 英字を足す
    func append(_ character: Character) {
        typed.append(character)
    }

    /// 分岐図から英字に戻す(Esc)
    func restore(_ text: String) {
        typed = text
    }

    func deleteBackward() {
        if !typed.isEmpty { typed.removeLast() }
    }

    /// 打った英字をローマ字として読んだ日本語の候補．ローマ字として読めなければ nil．
    /// 大文字を含むなら英語として打っているので出さない(「Documents」などの補完を妨げない)
    var suggestion: Candidate? {
        guard typed.count >= DefaultSettings.minimumEnglishInputSuggestionLength,
            typed.allSatisfy({ ($0.isASCII && $0.isLetter && $0.isLowercase) || $0 == "-" }) else { return nil }
        var composition = Composition()
        for key in typed.lowercased() { composition.insertRomaji(key) }
        guard !composition.containsInvalidRomaji, composition.pending.isEmpty || composition.pending == "n" else { return nil }
        let reading = composition.conversionReading
        return converter.candidates(for: reading).first { $0.readingCount == reading.count }
            ?? Candidate(text: reading, readingCount: reading.count, origin: .variant(.hiragana))
    }

    func commit() -> [ClientAction] { commitTyped() }

    /// 打った英字のまま確定する
    func commitTyped() -> [ClientAction] {
        guard isComposing else { return [] }
        let text = typed
        typed = ""
        return [.commit(text), .setMarkedText(.empty), .hideCandidates]
    }

    /// 日本語の候補で確定する．候補が無ければ英字のまま
    func commitSuggestion() -> [ClientAction] {
        guard let suggestion else { return commitTyped() }
        if suggestion.isFromEngine { converter.didCommit(suggestion) }
        typed = ""
        converter.endComposition()
        return [.commit(suggestion.text), .setMarkedText(.empty), .hideCandidates]
    }

    func render() -> [ClientAction] {
        guard isComposing else { return [.setMarkedText(.empty), .hideCandidates] }
        let marked = MarkedText([.init(typed, style: .reading)])
        guard let suggestion, suggestion.text != typed else { return [.setMarkedText(marked), .hideCandidates] }
        let panel = CandidatePanel(variants: [], selectedVariant: nil, entries: [.init(text: suggestion.text, annotation: nil)],
                                   selectedEntry: nil, focus: .candidate, position: 1, total: 1, note: PanelBuilder.englishInputNote)
        return [.setMarkedText(marked), .showCandidates(panel)]
    }

    func interpret(_ event: KeyEvent, state: InputStyleState) -> InputStyleInterpretation? {
        switch event.key {
        case .character(let character) where character.isASCII && character.isLetter:
            append(character)
            return .handled(KeyResult(handled: true, actions: render()))
        case .character("-") where isComposing:
            // 語の途中の「-」は伸ばし棒として読む(「ra-men」→ ラーメン)．英字のまま確定すれば「ra-men」
            append("-")
            return .handled(KeyResult(handled: true, actions: render()))
        case .tab:
            guard isComposing else { return .handled(.passThrough) }
            // 日本語の候補が無ければ，英字を確定して Tab をアプリに渡す(ターミナルの補完を妨げない)
            guard let suggestion, suggestion.text != typed else { return .handled(KeyResult(handled: false, actions: commitTyped())) }
            let keys = typed
            typed = ""
            return .convertRomaji(keys)
        case .backspace:
            guard isComposing else { return .handled(.passThrough) }
            deleteBackward()
            return .handled(KeyResult(handled: true, actions: render()))
        case .escape:
            // 組み立てていなければふつうの処理(Escape で英数にする設定)に回す．
            // 打っている途中なら英字を確定し，Escape もアプリに渡す(Vim のノーマルモードに 1 回で戻れる)
            guard isComposing else { return nil }
            return .handled(KeyResult(handled: false, actions: commitTyped()))
        case .eisu, .kana, .yen:
            return nil
        default:
            // Space・Enter・数字・記号・矢印は，打った英字を確定してからアプリに渡す(英語の入力と同じ動き)
            return .handled(KeyResult(handled: false, actions: commitTyped()))
        }
    }
}
