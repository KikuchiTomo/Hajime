import HajimeDomain

/// 候補ウィンドウ(一覧と文節格子)に出す内容を，入力の状態から組み立てる．
/// 状態を持たない計算だけなので，InputSession から分けておく
enum PanelBuilder {
    static let asTypedNote = "入力のまま"
    static let correctedNote = CandidatePanel.correctedAnnotation
    static let englishInputNote = Note.info("Tab 日本語に変換")
    /// 英字入力で日本語にして見せているときの案内
    static let englishInputJapaneseNote = Note.info("Esc 英字に戻す　Tab 変換")
    /// 選んでいる候補を学習から消したときの案内
    static let candidateForgottenNote = Note.info("学習から削除しました")
    /// 最後に確定した語の学習を取り消したときの案内
    static let lastCommitForgottenNote = Note.info("最後の学習を取り消しました")
    /// 戻した補正を覚えたときの案内．phrase は覚えた語句(打ったままの読み)
    static func correctionRememberedNote(_ phrase: String) -> Note { .info("「\(phrase)」は次から直しません") }

    /// 連想変換で，選んでいる語の連想が見つからなかったときの案内(R-18)
    static let noAssociationNote = Note.info("連想はありません")
    /// 連想変換を使う設定で，引ける連想の辞書が無いときの案内
    static let noAssociationDictionaryNote = Note.info("連想の辞書がありません")

    /// 打ち間違いの案内の主な語と，キーでできること
    private static let correctedTitle = "修正"
    private static let suggestionTitle = "もしかして"
    private static let revertAction = "戻す"
    private static let applyAction = "修正"

    // 案内に出すキーは，キー設定の表でそのコマンドに割り当てた最初のキー(R-17)．キーが無ければキーの部分を出さない

    /// 英単語を直した候補が先頭の一覧の案内．key は次の候補のキー
    static func correctionNote(key: String?) -> Note {
        Note(tone: .correction, title: correctedTitle, key: key, keyAction: key.map { _ in "入力のままに戻す" })
    }

    /// 打っているあいだの候補の窓の案内．key は候補に入るキー
    static func suggestionNote(key: String?) -> Note? { key.map { .info("\($0) で選ぶ") } }

    /// 分岐図か一覧で，打ち間違いを直したときの案内．key は取り消しのキー
    /// 文節をその場で打ち直しているときの案内．subject は打ち直す前の文節，key は打ち直した読みを変換するキー
    static func inlineEditNote(replacing subject: String, key: String?) -> Note {
        Note(tone: .info, title: "打ち直し", subject: subject, key: key, keyAction: key.map { _ in "変換" })
    }

    static func readingCorrectionNote(key: String?) -> Note {
        Note(tone: .correction, title: correctedTitle, key: key, keyAction: key.map { _ in "入力のままに戻す" })
    }

    /// ライブ変換で打ち間違いを直したときの案内．typed は直す前の文，key は取り消しのキー
    static func readingCorrectedNote(typed: String, key: String?) -> Note {
        Note(tone: .correction, title: correctedTitle, subject: typed, key: key, keyAction: key.map { _ in revertAction })
    }

    /// 直さずに示すときの案内．corrected は直した文，key は「もしかして」に直すキー
    static func readingSuggestionNote(_ corrected: String, key: String?) -> Note {
        Note(tone: .suggestion, title: suggestionTitle, subject: corrected, key: key, keyAction: key.map { _ in applyAction })
    }

    /// 打ち間違いを直した部分を含む文節か．直した読みの部分(changed．読みの先頭からの文字数)にかかる文節で，
    /// 打ったままの候補を選んでいないもの．「もしかして」の直した候補を選んだ文節も含む
    static func isCorrected(_ segment: SegmentLattice.Segment, changed: Range<Int>?) -> Bool {
        switch segment.selected.origin {
        case .correction: return true
        // 打ったままと，連想で選び直した単語は，打ち間違いを直したものではない
        case .asTyped, .association, .command: return false
        case .engine, .variant, .sentencePart, .combined, .symbol, .userDictionary:
            guard let changed else { return false }
            return (segment.readingStart..<(segment.readingStart + segment.readingLength)).overlaps(changed)
        }
    }

    /// - Parameters:
    ///   - nextKey: 次の候補のキーの名前(英単語を直した候補の案内に出す)
    ///   - corrected: 打ち間違いを直した読みの部分(読みの先頭からの文字数)．候補の中の当たる語句に補正の下線を引く
    static func listPanel(for selection: CandidateSelection, composition: Composition, showsVariants: Bool,
                          perPage: Int = DefaultSettings.candidatesPerPage, nextKey: String? = nil, corrected: Range<Int>? = nil) -> CandidatePanel {
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
        let reading = composition.conversionReading
        let entries = (pageStart..<pageEnd).map { index in
            let candidate = selection.candidates[index]
            let range = corrected.flatMap { CorrectedSpan.textRange(of: CorrectedSpan.pieces(of: candidate, reading: reading, changed: $0)) }
            // 前の文節(shownPrefix)は一覧に出さない
            let text = !selection.shownPrefix.isEmpty && candidate.text.hasPrefix(selection.shownPrefix)
                ? String(candidate.text.dropFirst(selection.shownPrefix.count)) : candidate.text
            return CandidatePanel.Entry(text: text, annotation: selection.annotations[index], corrected: selection.shownPrefix.isEmpty ? range : nil)
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

    /// 選んでいる候補に連想があるときの知らせ．key は連想変換のキー
    static func associationHint(key: String?) -> String { key.map { "\($0) 連想" } ?? "連想" }

    // MARK: 連想(R-18)

    /// 連想の見出し
    static func associationHeading(_ list: AssociationList) -> AssociationHeading {
        AssociationHeading(headword: list.associations.headword, label: list.group.label, group: list.groupIndex + 1,
                           groupCount: list.associations.groups.count)
    }

    /// 一覧で出す連想．1 ページにはひとつの意味のまとまりの語だけを並べ，位置はまとまりの中で数える
    static func associationListPanel(for list: AssociationList, perPage: Int) -> CandidatePanel {
        let page = list.page(perPage: perPage)
        var panel = CandidatePanel(
            variants: [],
            selectedVariant: nil,
            entries: page.words.map { CandidatePanel.Entry(text: $0, annotation: nil) },
            selectedEntry: page.selected,
            focus: .candidate,
            position: list.indexInGroup + 1,
            total: list.group.words.count,
            note: nil
        )
        panel.association = associationHeading(list)
        return panel
    }

    /// 分岐図で出す連想．lattice は選んでいる連想の語を注目している文節に入れたもの．
    /// 注目している文節の下の枝に今のまとまりの語を並べ，上の枝(字種)は出さない
    static func associationLatticePanel(for lattice: SegmentLattice, list: AssociationList, perPage: Int) -> LatticePanel {
        var panel = latticePanel(for: lattice, perPage: perPage, showsVariants: false)
        let page = list.page(perPage: perPage)
        if let focused = panel.columns.firstIndex(where: \.isFocused) {
            panel.columns[focused].alternatives = page.words
            panel.columns[focused].selectedAlternative = page.selected
            panel.columns[focused].alternativeNotes = []
            panel.columns[focused].isUncertain = false
        }
        panel.position = list.indexInGroup - page.selected + 1
        panel.total = list.group.words.count
        panel.association = associationHeading(list)
        return panel
    }

    /// showsVariants が false なら上の枝(字種)を出さない(設定の「候補の上に文字種の行を表示」)
    /// corrected は打ち間違いを直した読みの部分．かかる文節に補正の印を付ける(isCorrected)
    static func latticePanel(for lattice: SegmentLattice, perPage perSegment: Int = DefaultSettings.latticeCandidatesPerSegment,
                             showsVariants: Bool = true, corrected: Range<Int>? = nil) -> LatticePanel {
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
                var column = LatticePanel.Column(text: segment.selected.text, isFocused: false, isUncertain: !segment.isConfident,
                                                 isDecided: segment.isDecided, preview: preview)
                column.isCorrected = isCorrected(segment, changed: corrected)
                return column
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
            column.isCorrected = isCorrected(segment, changed: corrected)
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

    /// 文節ごとの一覧．注目している文節の候補を縦に並べ，字種は上の種類の行に出す(分岐図の下の枝と上の枝にあたる)
    static func segmentListPanel(for lattice: SegmentLattice, perPage: Int, showsVariants: Bool, corrected: Range<Int>? = nil,
                                 reading: String) -> CandidatePanel {
        let segment = lattice.focused
        let selectedCandidate: Int? = if case .candidate(let value) = segment.choice { value } else { nil }
        let selectedVariant: Int? = if case .variant(let value) = segment.choice { value } else { nil }
        let variants = showsVariants
            ? ScriptVariant.allCases.map { variant in
                CandidatePanel.Variant(label: variant.label, isAvailable: segment.variants.contains { $0.origin == .variant(variant) })
            }
            : []
        let pageStart = (selectedCandidate ?? 0) / perPage * perPage
        let page = pageStart..<min(pageStart + perPage, segment.candidates.count)
        // 打ち間違いを直した部分は，候補の中の当たる語句に補正の下線を引く(読みの位置は文節の中で数え直す)
        let start = segment.readingStart
        let changed = corrected.map { max($0.lowerBound - start, 0)..<max($0.upperBound - start, 0) }.flatMap { $0.isEmpty ? nil : $0 }
        let segmentReading = String(reading.dropFirst(start).prefix(segment.readingLength))
        let entries = page.map { index in
            let candidate = segment.candidates[index]
            let range = changed.flatMap { CorrectedSpan.textRange(of: CorrectedSpan.pieces(of: candidate, reading: segmentReading, changed: $0)) }
            let annotation: String? = switch candidate.origin {
            case .asTyped: asTypedNote
            case .correction: correctedNote
            default: nil
            }
            return CandidatePanel.Entry(text: candidate.text, annotation: annotation, corrected: range)
        }
        let variantIndex = selectedVariant.flatMap { index -> Int? in
            guard case .variant(let variant) = segment.variants[index].origin else { return nil }
            return ScriptVariant.allCases.firstIndex(of: variant)
        }
        return CandidatePanel(
            variants: variants,
            selectedVariant: variantIndex,
            entries: entries,
            selectedEntry: selectedCandidate.map { $0 - pageStart },
            focus: selectedVariant == nil ? .candidate : .variants,
            position: (selectedCandidate ?? 0) + 1,
            total: segment.candidates.count,
            note: nil
        )
    }

    /// 文節ごとの一覧で文節を区切っているとき(⇧↓)．区切れる位置ごとに，そこで区切った文節を番号順に並べる(番号キーで選ぶ)
    static func splittingList(pieces: [String]) -> CandidatePanel {
        let entries = (1..<max(pieces.count, 1)).map { position in
            CandidatePanel.Entry(text: pieces[..<position].joined() + splitMark + pieces[position...].joined(), annotation: nil)
        }
        return CandidatePanel(variants: [], selectedVariant: nil, entries: entries, selectedEntry: nil, focus: .candidate,
                              position: 0, total: entries.count, note: nil)
    }

    /// 区切る位置を見せる印
    static let splitMark = "｜"

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
