import S90Domain

/// 候補ウィンドウ(一覧と文節格子)に出す内容を，入力の状態から組み立てる．
/// 状態を持たない計算だけなので，InputSession から分けておく
enum PanelBuilder {
    static let asTypedNote = "入力のまま"
    static let splitNote = "数字で区切る位置を選ぶ　Esc でやめる"
    static let correctionNote = "Space 入力のままに戻す"
    static let englishInputNote = "Tab 日本語にする"
    static let readingCorrectionNote = "直しました　Esc で打ったままに戻す"

    /// ライブ変換で打ち間違いを直したときの案内．typed は直す前の文
    static func readingCorrectedNote(typed: String) -> String { "直しました　Esc で「\(typed)」に戻す" }

    /// 直さずに示すときの案内．corrected は直した文
    static func readingSuggestionNote(_ corrected: String) -> String { "もしかして「\(corrected)」　Tab で直す" }

    static func listPanel(for selection: CandidateSelection, composition: Composition, showsVariants: Bool,
                          perPage: Int = DefaultSettings.candidatesPerPage) -> CandidatePanel {
        let variants = showsVariants
            ? ScriptVariant.allCases.map { CandidatePanel.Variant(label: $0.label, isAvailable: $0.apply(to: composition) != nil) }
            : []
        let focusedIndex: Int
        let selectedVariant: Int?
        switch selection.focus {
        case .candidate(let index):
            focusedIndex = index
            selectedVariant = nil
        case .variant(let variant):
            focusedIndex = 0
            selectedVariant = ScriptVariant.allCases.firstIndex(of: variant)
        }
        let pageStart = focusedIndex / perPage * perPage
        let pageEnd = min(pageStart + perPage, selection.candidates.count)
        let entries = (pageStart..<pageEnd).map {
            CandidatePanel.Entry(text: selection.candidates[$0].text, annotation: selection.annotations[$0])
        }
        let isCorrected = selection.candidates.first?.origin == .correction
        return CandidatePanel(
            variants: variants,
            selectedVariant: selectedVariant,
            entries: entries,
            selectedEntry: selectedVariant == nil ? focusedIndex - pageStart : nil,
            focus: selectedVariant == nil ? .candidate : .variants,
            position: focusedIndex + 1,
            total: selection.candidates.count,
            note: isCorrected ? correctionNote : nil
        )
    }

    static func latticePanel(for lattice: SegmentLattice, perPage perSegment: Int = DefaultSettings.latticeCandidatesPerSegment) -> LatticePanel {
        var position = 1
        var total = 0
        let columns = lattice.segments.enumerated().map { index, segment -> LatticePanel.Column in
            let selectedCandidate: Int? = if case .candidate(let value) = segment.choice { value } else { nil }
            let selectedVariant: Int? = if case .variant(let value) = segment.choice { value } else { nil }
            guard index == lattice.focusedIndex else {
                // 注目していない文節は幹だけ．迷う文節には次の候補を 1 つ添え，見るだけで気づけるようにする
                let preview = segment.isConfident || segment.isDecided
                    ? nil
                    : segment.candidates.first { $0.text != segment.selected.text }?.text
                return LatticePanel.Column(text: segment.selected.text, isFocused: false, isUncertain: !segment.isConfident,
                                           isDecided: segment.isDecided, preview: preview)
            }
            // 選んでいる候補が見えるよう，下の枝は選んでいる位置を含むページを切り出す
            let pageStart = (selectedCandidate ?? 0) / perSegment * perSegment
            let page = segment.candidates[pageStart..<min(pageStart + perSegment, segment.candidates.count)]
            position = pageStart + 1
            total = segment.candidates.count
            return LatticePanel.Column(
                text: segment.selected.text,
                alternatives: page.map(\.text),
                selectedAlternative: selectedCandidate.map { $0 - pageStart },
                variants: segment.variants.map(\.text),
                selectedVariant: selectedVariant,
                isFocused: true,
                isUncertain: !segment.isConfident,
                isDecided: segment.isDecided
            )
        }
        return LatticePanel(columns: columns, position: position, total: total)
    }
}
