import S90Domain

/// 英語のまま入力する(EN 入力．R-05)．打った英字をそのまま見せ，ローマ字として読める並びには日本語の候補を添える．
///
/// Space・Enter・記号は英語の入力と同じに動く(打った英字を確定し，キーはアプリに渡す)．
/// 日本語にするのは Tab を押したときだけ(Q-02)．英語を打つ人の手の流れを変えないため
@MainActor
final class EnglishInput {
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

    func deleteBackward() {
        if !typed.isEmpty { typed.removeLast() }
    }

    /// 打った英字をローマ字として読んだ日本語の候補．ローマ字として読めなければ nil
    var suggestion: Candidate? {
        guard typed.count >= DefaultSettings.minimumEnglishInputSuggestionLength,
            typed.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        var composition = Composition()
        for key in typed.lowercased() { composition.insertRomaji(key) }
        guard !composition.containsInvalidRomaji, composition.pending.isEmpty || composition.pending == "n" else { return nil }
        let reading = composition.conversionReading
        return converter.candidates(for: reading).first { $0.readingCount == reading.count }
            ?? Candidate(text: reading, readingCount: reading.count, origin: .variant(.hiragana))
    }

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
}
