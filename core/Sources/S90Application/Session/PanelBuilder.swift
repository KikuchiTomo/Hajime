import S90Domain

/// 候補ウィンドウ(一覧と文節格子)に出す内容を，入力の状態から組み立てる．
/// 状態を持たない計算だけなので，InputSession から分けておく
enum PanelBuilder {
    static let asTypedNote = "入力のまま"
    static let correctedNote = "修正"
    static let englishInputNote = "Tab 日本語にする"
    /// 選んでいる候補を学習から消したときの案内
    static let candidateForgottenNote = "学習から消しました"
    /// 最後に確定した語の学習を取り消したときの案内
    static let lastCommitForgottenNote = "最後の学習を取り消しました"

    // 案内に出すキーは，キー設定の表でそのコマンドに割り当てた最初のキー(R-17)．キーが無ければキーの部分を出さない

    /// 英単語を直した候補が先頭の一覧の案内．key は次の候補のキー
    static func correctionNote(key: String?) -> String { key.map { "\($0) 入力のままに戻す" } ?? correctedNote }

    /// 打っているあいだの候補の窓の案内．key は候補に入るキー
    static func suggestionNote(key: String?) -> String? { key.map { "\($0) で選ぶ" } }

    /// 分岐図か一覧で，打ち間違いを直したときの案内．key は取り消しのキー
    static func readingCorrectionNote(key: String?) -> String { key.map { "直しました　\($0) で打ったままに戻す" } ?? "直しました" }

    /// ライブ変換で打ち間違いを直したときの案内．typed は直す前の文，key は取り消しのキー
    static func readingCorrectedNote(typed: String, key: String?) -> String {
        key.map { "直しました　\($0) で「\(typed)」に戻す" } ?? "直しました"
    }

    /// 直さずに示すときの案内．corrected は直した文，key は「もしかして」に直すキー
    static func readingSuggestionNote(_ corrected: String, key: String?) -> String {
        "もしかして「\(corrected)」" + (key.map { "　\($0) で直す" } ?? "")
    }

    /// - Parameter nextKey: 次の候補のキーの名前(英単語を直した候補の案内に出す)
    static func listPanel(for selection: CandidateSelection, composition: Composition, showsVariants: Bool,
                          perPage: Int = DefaultSettings.candidatesPerPage, nextKey: String? = nil) -> CandidatePanel {
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
            note: isCorrected ? correctionNote(key: nextKey) : nil
        )
    }

    /// showsVariants が false なら上の枝(字種)を出さない(設定の「候補の上に文字種の行を表示」)
    static func latticePanel(for lattice: SegmentLattice, perPage perSegment: Int = DefaultSettings.latticeCandidatesPerSegment,
                             showsVariants: Bool = true) -> LatticePanel {
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
            var column = LatticePanel.Column(
                text: segment.selected.text,
                alternatives: page.map(\.text),
                selectedAlternative: selectedCandidate.map { $0 - pageStart },
                variants: showsVariants ? segment.variants.map(\.text) : [],
                selectedVariant: selectedVariant,
                isFocused: true,
                isUncertain: !segment.isConfident,
                isDecided: segment.isDecided
            )
            column.alternativeNotes = page.map { candidate in
                switch candidate.origin {
                case .asTyped: asTypedNote
                case .correction: correctedNote
                default: nil
                }
            }
            return column
        }
        return LatticePanel(columns: columns, position: position, total: total)
    }

    /// 文節を区切っているとき(⇧↓)の分岐図．注目している文節を区切れる位置で分けて幹に出し，切れ目に番号を振る(SegmentSplitter)．
    /// 番号キーは区切る位置を選ぶので，候補と字種の枝は出さない(枝の番号と取り違えないように)
    static func splitting(_ panel: LatticePanel, pieces: [String]) -> LatticePanel {
        guard let focused = panel.columns.firstIndex(where: \.isFocused) else { return panel }
        var panel = panel
        let column = panel.columns[focused]
        var splitting = LatticePanel.Column(text: column.text, isFocused: true, isUncertain: column.isUncertain, isDecided: column.isDecided)
        splitting.split = .init(pieces: pieces)
        panel.columns[focused] = splitting
        return panel
    }
}
