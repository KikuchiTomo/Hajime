import S90Domain

/// 候補ウィンドウ(一覧と文節格子)に出す内容を，入力の状態から組み立てる．
/// 状態を持たない計算だけなので，InputSession から分けておく
enum PanelBuilder {
    static let asTypedNote = "入力のまま"
    static let correctionNote = "Space 入力のままに戻す"

    static func listPanel(for selection: CandidateSelection, composition: Composition, showsVariants: Bool) -> CandidatePanel {
        let variants = showsVariants
            ? ScriptVariant.allCases.map { CandidatePanel.Variant(label: $0.label, isAvailable: $0.apply(to: composition) != nil) }
            : []
        let perPage = DefaultSettings.candidatesPerPage
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

    static func latticePanel(for lattice: SegmentLattice) -> LatticePanel {
        let perSegment = DefaultSettings.latticeCandidatesPerSegment
        let columns = lattice.segments.enumerated().map { index, segment in
            // 選んでいる候補が見えるよう，候補の列は選んでいる位置を含む範囲を切り出す
            let pageStart = segment.selectedIndex / perSegment * perSegment
            let page = segment.candidates[pageStart..<min(pageStart + perSegment, segment.candidates.count)]
            let isFocused = index == lattice.focusedIndex
            return LatticePanel.Column(
                text: segment.selected.text,
                alternatives: page.map(\.text),
                selectedAlternative: segment.selectedIndex - pageStart,
                isFocused: isFocused,
                // 確信度の高い文節は候補の列を畳み，見るだけの手間を減らす
                showsAlternatives: isFocused || !segment.isConfident
            )
        }
        return LatticePanel(columns: columns)
    }
}
