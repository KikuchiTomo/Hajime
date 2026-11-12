import AppKit
import HajimeApplication
import HajimeDomain

/// 分岐図を描く(ADR 0007)．文を 1 本の幹として文節を横に並べ，注目している文節から枝を伸ばす．
///
/// - 下の枝: 変換の候補．↓ と Space で下へたどる．番号キーで選べる
/// - 上の枝: 文字種(ひらがな・カタカナ・半角カタカナ)．↑ で上へたどる
/// - 確信の低い文節は幹の文字に点線を引き，注目していなければ次の候補を 1 つだけ薄く添える
/// - 選び直した文節は実線を引く．変換器が書き換えない文節であることを見せる
/// - 文節を区切っているとき(⇧↓)は，注目している文節の幹を意味のある切れ目(「問題｜が｜ある」)で分け，切れ目に小さな番号の丸を挟む．
///   番号キーは区切る位置を選ぶので，枝は出さない(core の PanelBuilder.splitting)
///
/// - 連想の一覧(R-18)では，いちばん上に見出し(元の語と意味の説明)の行を出し，下の枝に連想の単語を並べる
///
/// 幹の文節の位置は幹の文字の幅だけで決め，注目を移しても動かさない(空間の安定性)．
/// 枝は幹の文節から 1 本の幹を伸ばし，候補ごとに同じ形の曲がり角と水平の線を出す(BranchLines)．
/// 曲線の枝のテーマは 4 分の 1 の円で，直線の枝のテーマは直角に曲がる．platinum と desk は 1 ドットの線で描く
final class BranchView: NSView {
    private typealias Size = DesignTokens.Size.Candidate
    private typealias Branch = DesignTokens.Size.Branch
    private typealias Glass = DesignTokens.Size.Glass

    var panel: LatticePanel? {
        didSet {
            updateReservedCard()
            updateTrunkOffset()
            needsDisplay = true
        }
    }
    /// 窓の幅の上限(CandidatePanelController が画面の幅から決める)．幹がこれより長い文では，幹を横にずらして注目している文節を見せる
    var maximumWidth = DesignTokens.Size.Candidate.maxWidth {
        didSet {
            updateTrunkOffset()
            needsDisplay = true
        }
    }
    /// 幹が窓に収まらないときに，幹を左へずらす量．注目している文節が窓から出るときだけ，出ない分だけずらす
    /// (文節を移るたびに幹が動かないよう，入る限り前の量を保つ)
    private var trunkOffset: CGFloat = 0
    /// 足元の案内に出すキーの割り当て
    var keys = KeymapPreset.standard.keymap { didSet { needsDisplay = true } }
    /// 足元にキーの案内を出すか(設定の「キーの案内を表示」)
    var showsHints = true { didSet { needsDisplay = true } }

    /// 足元の案内．区切っているときは区切る操作だけを出す
    private var hints: [KeyHint] {
        let focused = panel?.columns.first(where: \.isFocused)
        if let split = focused?.split { return UIStrings.Branch.splitHints(count: split.pieces.count - 1) }
        if panel?.association != nil { return UIStrings.Association.hints(for: keys) }
        return UIStrings.Branch.hints(for: keys)
    }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }
    var fontSize: CGFloat = Size.fontSize { didSet { needsDisplay = true } }
    var restOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    /// glass の面を自分で塗るか．ぼかしの地(GlassBackdrop)の無いところ(画像への書き出し)で使う
    var fillsSurface = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    // MARK: - 寸法

    /// テーマごとの寸法．glass は余白と行を広く取る
    private struct Metrics {
        var inset: CGFloat
        var rowHeight: CGFloat
        var trunkGap: CGFloat
        var branchIndent: CGFloat
        var stemX: CGFloat
        /// 候補の文字の前に置く番号の幅
        var lead: CGFloat
        var footerHeight: CGFloat
        var lineWidth: CGFloat
        var lineWidthSelected: CGFloat
        /// 幹の根元を文節の枠の端からずらす量(角丸のテーマは文節の地が上下に細いので，その端から伸ばす)
        var rootInset: CGFloat
        /// 枝の水平の線の終わりから候補の行までの空き
        var tipGap: CGFloat
    }

    private var metrics: Metrics {
        let scale = fontSize / Size.fontSize
        if theme.isRounded {
            return Metrics(inset: Glass.padding, rowHeight: (Glass.rowHeight * scale).rounded(), trunkGap: Glass.trunkGap,
                           branchIndent: Glass.branchIndent, stemX: Glass.branchStemX, lead: Glass.badgeSize + Size.paddingX,
                           footerHeight: Glass.footerHeight, lineWidth: Glass.lineWidth, lineWidthSelected: Glass.lineWidthSelected,
                           rootInset: Glass.selectionInsetY, tipGap: Glass.branchTipGap)
        }
        let labelHeight = (labelFont.ascender - labelFont.descender).rounded(.up) + Size.sectionPaddingY * 2
        return Metrics(inset: Size.frameWidth + Size.bevelWidth + Size.paddingX, rowHeight: (Size.rowHeight * scale).rounded(),
                       trunkGap: Branch.trunkGap, branchIndent: Branch.branchIndent, stemX: Branch.branchStemX, lead: Size.indexWidth,
                       footerHeight: max(labelHeight, Glass.keycapHeight + Size.sectionPaddingY * 2),
                       lineWidth: Branch.lineWidth, lineWidthSelected: Branch.lineWidthSelected, rootInset: 0, tipGap: Size.frameWidth)
    }

    private var candidateFont: NSFont { theme.candidateFont(size: fontSize) }
    private var trunkFont: NSFont { theme.trunkFont(size: fontSize) }
    private var labelFont: NSFont { theme.labelFont(size: theme.isRounded ? Glass.labelFontSize : Size.labelFontSize) }
    private var dropShadowOffset: CGFloat { theme.hasDropShadow ? Size.shadowOffset : 0 }

    // MARK: - 語の意味のカード

    /// 語の意味のカード(R-08)．layout が nil なら，意味の無い候補を選んでいるあいだ空けておくカード
    private struct MeaningSlot {
        var placement: MeaningPlacement
        var layout: MeaningCardDrawing.Layout?
        /// カードの大きさ(内側の余白を含む)
        var size: NSSize
    }

    /// 候補の右に出したカードの場所．同じ文節の同じ候補の並びのあいだは，意味の無い候補を選んでも場所を空けたままにする
    private var reservedCard: (key: [String], height: CGFloat)?

    /// 予約の見分け: 注目している文節の位置と，下の枝の候補
    private func reservationKey(_ panel: LatticePanel) -> [String]? {
        guard let focused = panel.columns.firstIndex(where: \.isFocused) else { return nil }
        return ["\(focused)"] + panel.columns[focused].alternatives
    }

    /// 同音語の札には，下の枝に出ていない語だけを出す(枝に出ている語は見れば分かる)
    private func cardLayout(_ note: HomophoneNote, column: LatticePanel.Column, width: CGFloat) -> MeaningCardDrawing.Layout {
        let shown = Set(column.alternatives)
        return MeaningCardDrawing.layout(note, others: note.others.filter { !shown.contains($0) }, width: width, theme: theme)
    }

    private func updateReservedCard() {
        guard let panel, panel.meaningPlacement == .side, let key = reservationKey(panel),
              let column = panel.columns.first(where: \.isFocused), column.split == nil else {
            reservedCard = nil
            return
        }
        let height = column.homophone.map { cardLayout($0, column: column, width: Glass.meaningBranchWidth).size.height }
        if let reserved = reservedCard, reserved.key == key {
            reservedCard = (key, max(reserved.height, height ?? 0))
        } else {
            reservedCard = height.map { (key, $0) }
        }
    }

    /// contentWidth は窓の中身の幅．下に出すカードはこの幅に合わせて折り返す
    private func meaningSlot(for panel: LatticePanel, contentWidth: CGFloat) -> MeaningSlot? {
        guard let column = panel.columns.first(where: \.isFocused), column.split == nil else { return nil }
        switch panel.meaningPlacement {
        case .below:
            guard let note = column.homophone else { return nil }
            let layout = cardLayout(note, column: column, width: max(contentWidth - Glass.meaningPadding * 2, Glass.meaningCardWidth))
            return MeaningSlot(placement: .below, layout: layout, size: layout.size)
        case .side:
            let layout = column.homophone.map { cardLayout($0, column: column, width: Glass.meaningBranchWidth) }
            let reserved = reservedCard?.key == reservationKey(panel) ? reservedCard?.height : nil
            guard layout != nil || reserved != nil else { return nil }
            let height = max(layout?.size.height ?? 0, reserved ?? 0)
            return MeaningSlot(placement: .side, layout: layout, size: NSSize(width: Glass.meaningBranchWidth + Glass.meaningPadding * 2, height: height))
        }
    }

    /// 下に出すカードの上下の空き
    private var belowCardMargin: CGFloat { Size.paddingX / 2 }

    /// 幹・枝・足元の位置．描くときと大きさを求めるときで同じものを使う
    private struct Layout {
        var trunkX: [CGFloat]
        var trunkWidths: [CGFloat]
        var lowerRows: Int
        var trunkY: CGFloat
        var branchWidth: CGFloat
        var size: NSSize
        /// 幹をずらしたとき，文字を描いてよい左右の範囲(窓の内側)．ずらしていなければ nil
        var clip: ClosedRange<CGFloat>? = nil
        /// 幹の右端(ずらす前)と，注目している文節の左右の端(ずらす前．枝を含む)
        var trunkRight: CGFloat = 0
        var focusSpan: ClosedRange<CGFloat>? = nil
        /// 語の意味のカードと，その枠(ずらしたあとの位置)．カードを出さなければ nil
        var slot: MeaningSlot? = nil
        var card: NSRect? = nil
        /// 下の枝の高さ(候補の枝と，候補の右に出すカードの高い方)
        var lowerHeight: CGFloat = 0
    }

    /// 下の枝の候補の行の幅(コマンドのアイコンと，文字のあとに添える説明を含む)
    private func lowerRowWidth(_ row: Row) -> CGFloat {
        let icon: CGFloat = row.command == nil ? 0 : CommandDrawing.width
        return textWidth(row.text, font: candidateFont) + icon + CandidateDetailDrawing.width(row.detail, font: labelFont)
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        text.size(withAttributes: [.font: font]).width.rounded(.up)
    }

    /// 打ち間違いを直した文節の幹で，文字のあとに添える「修正」の札の幅(前の空きを含む)
    private var correctedLabelWidth: CGFloat {
        NoteDrawing.tagWidth(UIStrings.Branch.corrected, theme: theme) + Size.paddingX / 2
    }

    /// offset を渡さなければ，今の幹のずれ(trunkOffset)を使う
    private func layout(for panel: LatticePanel, offset: CGFloat? = nil) -> Layout {
        let metrics = metrics
        var x = metrics.inset
        var trunkX: [CGFloat] = []
        var trunkWidths: [CGFloat] = []
        for column in panel.columns {
            let text = trunkCommand(column).map { CommandDrawing.width + textWidth($0.title, font: trunkFont) } ?? textWidth(column.text, font: trunkFont)
            let width = (column.split.map { splitPieces($0).width } ?? text) + Size.paddingX * 2
                + (column.isCorrected ? correctedLabelWidth : 0)
            trunkX.append(x)
            trunkWidths.append(width)
            x += width + metrics.trunkGap
        }
        let trunkRight = x - metrics.trunkGap
        let focused = panel.columns.firstIndex(where: \.isFocused)
        let column = focused.map { panel.columns[$0] }
        // コマンドの候補は文字の前に種類のアイコンを置くので，その幅も足す
        let labelWidths = (column.map(lowerRows) ?? []).map(lowerRowWidth) + (column?.variants ?? []).map { textWidth($0, font: candidateFont) }
        // 打ったまま・修正・コマンドの添え書きの幅も足す
        let noteWidth = (column?.alternativeNotes.compactMap { $0 }.map { textWidth($0, font: labelFont) }.max()).map { $0 + Size.paddingX * 2 } ?? 0
        let branchWidth = metrics.stemX + metrics.branchIndent + metrics.lead
            + (labelWidths.max() ?? 0) + noteWidth + Size.paddingX * 2
        // 候補の右に出すカードは，候補の枝の先に続けて置く(枝の一部として幅に数え，長い文でも注目している文節と一緒に見せる)
        let sideSlot = meaningSlot(for: panel, contentWidth: 0).flatMap { $0.placement == .side ? $0 : nil }
        let cardExtent = sideSlot.map { Glass.meaningGap + $0.size.width } ?? 0
        let branchRight = (focused.map { trunkX[$0] } ?? metrics.inset) + branchWidth + cardExtent
        let previewRows = panel.columns.contains { $0.preview != nil } ? 1 : 0
        let upperRows = column?.variants.count ?? 0
        let lowerRows = max(column?.alternatives.count ?? 0, previewRows)
        let lowerHeight = max(metrics.rowHeight * CGFloat(lowerRows), sideSlot.map { $0.size.height + Size.paddingX / 2 } ?? 0)
        let footer = footerWidth(panel) + (showsPosition(panel) ? textWidth(position(of: panel), font: labelFont) : 0) + Size.paddingX * 3
        // 使い分けや誤用の注釈と，IME からの知らせ(直したことなど)は，枝と足元のあいだに 1 行ずつ出す．キーの案内は消さない
        let note = [column?.usageNote.map { textWidth($0, font: labelFont) }, panel.note.map { NoteDrawing.width($0, theme: theme) },
                    panel.meaningPlacement == .below && column?.homophone != nil ? Glass.meaningCardWidth + Glass.meaningPadding * 2 : nil]
            .compactMap { $0.map { $0 + Size.paddingX * 2 } }.max() ?? 0
        let heading = panel.association.map { AssociationHeadingDrawing.width($0, font: labelFont, emphasis: labelFont) + metrics.inset * 2 } ?? 0
        var width = max(Size.minWidth, trunkRight + metrics.inset, branchRight + metrics.inset, footer + metrics.inset * 2, note + metrics.inset * 2, heading)
        let focusSpan = focused.map { trunkX[$0]...max(trunkX[$0] + trunkWidths[$0], branchRight) }
        var shiftedX = trunkX
        var shownBranchWidth = branchWidth
        var clip: ClosedRange<CGFloat>?
        let limit = max(maximumWidth, Size.minWidth)
        if width > limit {
            // 長い文は窓を画面に収め，幹をずらして注目している文節と枝を見せる
            let offset = min(max(offset ?? trunkOffset, 0), max(max(trunkRight, branchRight) + metrics.inset - limit, 0))
            shiftedX = trunkX.map { $0 - offset }
            width = limit
            let right = limit - metrics.inset
            if let focused { shownBranchWidth = max(min(branchWidth, right - shiftedX[focused]), 0) }
            clip = metrics.inset...right
        }
        let trunkY = metrics.inset + headingHeight(panel) + CGFloat(upperRows) * metrics.rowHeight
        // 下に出すカードは窓の中身の幅で折り返す
        let slot = sideSlot ?? meaningSlot(for: panel, contentWidth: width.rounded(.up) - metrics.inset * 2)
        let belowHeight = slot.map { $0.placement == .below ? $0.size.height + belowCardMargin * 2 : 0 } ?? 0
        let height = trunkY + metrics.rowHeight + lowerHeight + Size.frameWidth + metrics.footerHeight
            + belowHeight
            + (column?.usageNote == nil ? 0 : metrics.footerHeight)
            + (panel.note == nil ? 0 : metrics.footerHeight)
            + (theme.isRounded ? 0 : metrics.inset)
        var card: NSRect?
        if let slot, let focused {
            switch slot.placement {
            case .side:
                card = NSRect(x: shiftedX[focused] + branchWidth + Glass.meaningGap, y: trunkY + metrics.rowHeight + Size.paddingX / 4,
                              width: slot.size.width, height: slot.size.height)
            case .below:
                card = NSRect(x: metrics.inset, y: trunkY + metrics.rowHeight + lowerHeight + belowCardMargin,
                              width: width.rounded(.up) - metrics.inset * 2, height: slot.size.height)
            }
        }
        return Layout(trunkX: shiftedX, trunkWidths: trunkWidths, lowerRows: lowerRows, trunkY: trunkY,
                      branchWidth: shownBranchWidth, size: NSSize(width: width.rounded(.up), height: height.rounded(.up)),
                      clip: clip, trunkRight: trunkRight, focusSpan: focusSpan, slot: slot, card: card, lowerHeight: lowerHeight)
    }

    /// 注目している文節(枝を含む)が窓の内側に入るよう，幹をずらす量を決め直す．入っていれば前の量のまま
    private func updateTrunkOffset() {
        guard let panel else {
            trunkOffset = 0
            return
        }
        let natural = layout(for: panel, offset: 0)
        guard natural.clip != nil, let span = natural.focusSpan else {
            trunkOffset = 0
            return
        }
        let inset = metrics.inset
        let visible = max(maximumWidth, Size.minWidth) - inset * 2
        var offset = trunkOffset
        // 左に出たら左端に，右に出たら右端にそろえる．枝が窓より広いときは文節の左端を優先する
        if span.upperBound - offset > inset + visible { offset = span.upperBound - inset - visible }
        if span.lowerBound - offset < inset { offset = span.lowerBound - inset }
        trunkOffset = max(offset, 0)
    }

    /// 連想の一覧の見出しの行の高さ(区切りの線を含む)．連想でなければ 0
    private func headingHeight(_ panel: LatticePanel) -> CGFloat {
        panel.association == nil ? 0 : metrics.footerHeight + Size.frameWidth
    }

    func fittingSize(for panel: LatticePanel) -> NSSize {
        let size = layout(for: panel).size
        return NSSize(width: size.width + dropShadowOffset, height: size.height + dropShadowOffset)
    }

    // MARK: - 押した位置

    /// 押した対象を知らせる先(候補の窓をマウスで押したとき)
    var onChoose: ((PointerTarget) -> Void)?

    /// point(この view の座標)にある押せる対象．幹の文節と，注目している文節の上下の枝．無ければ nil
    func target(at point: NSPoint) -> PointerTarget? {
        guard let panel else { return nil }
        let layout = layout(for: panel)
        let metrics = metrics
        for index in panel.columns.indices {
            let node = NSRect(x: layout.trunkX[index], y: layout.trunkY, width: layout.trunkWidths[index], height: metrics.rowHeight)
            if node.contains(point) { return .segment(index) }
        }
        // 区切っているあいだ(⇧↓)は番号キーで区切る位置を選ぶので，枝は押せない
        guard let focused = panel.columns.firstIndex(where: \.isFocused), panel.columns[focused].split == nil else { return nil }
        let left = layout.trunkX[focused]
        func row(_ index: Int, downward: Bool) -> NSRect {
            let y = downward ? layout.trunkY + metrics.rowHeight + CGFloat(index) * metrics.rowHeight
                : layout.trunkY - CGFloat(index + 1) * metrics.rowHeight
            return NSRect(x: left, y: y, width: layout.branchWidth, height: metrics.rowHeight)
        }
        let column = panel.columns[focused]
        if let index = column.alternatives.indices.first(where: { row($0, downward: true).contains(point) }) {
            // コメントの札は枝の行の中にあるので，行より先に調べる(札を押すと候補の代わりにコメントを入れる)
            if let comment = column.comment(at: index) {
                let node = NSRect(x: left, y: layout.trunkY, width: layout.trunkWidths[focused], height: metrics.rowHeight)
                let rect = branchRowRect(index, from: node, width: layout.branchWidth, downward: true, metrics: metrics)
                if NoteDrawing.tagHitRect(comment, maxX: tagMaxX(in: rect), row: rect, theme: theme).contains(point) { return .comment(index) }
            }
            return .alternative(index)
        }
        if let index = column.variants.indices.first(where: { row($0, downward: false).contains(point) }) { return .variant(index) }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let target = target(at: convert(event.locationInWindow, from: nil)) else { return }
        onChoose?(target)
    }

    // 窓が前に出ていなくても 1 回目の押下で選ぶ(入力先のアプリからフォーカスを移さない)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        guard let panel else { return }
        let layout = layout(for: panel)
        let metrics = metrics
        let body = NSRect(origin: .zero, size: layout.size)
        if theme.isRounded {
            GlassDrawing.drawFrame(in: body, theme: theme, fillsSurface: fillsSurface)
        } else {
            BevelDrawing.drawDropShadow(for: body, theme: theme)
            BevelDrawing.drawPanel(in: body, theme: theme)
        }
        if let heading = panel.association {
            let row = NSRect(x: metrics.inset, y: metrics.inset, width: body.width - metrics.inset * 2, height: metrics.footerHeight)
            AssociationHeadingDrawing.draw(heading, in: row, theme: theme, font: labelFont, emphasis: labelFont)
            let lineInset = theme.isRounded ? metrics.inset : metrics.inset - Size.paddingX
            if theme.isRounded {
                theme.line.setFill()
                NSRect(x: lineInset, y: row.maxY, width: body.width - lineInset * 2, height: Size.frameWidth).fill()
            } else {
                BevelDrawing.drawSeparator(y: row.maxY, from: lineInset, to: body.width - lineInset, theme: theme)
            }
        }
        let focusedIndex = panel.columns.firstIndex(where: \.isFocused)
        // 注目している文節の枝が重なる範囲には，ほかの文節の添え書きを描かない
        let branchRange = focusedIndex.map { layout.trunkX[$0]...(layout.trunkX[$0] + layout.branchWidth) }
        // 幹をずらしたときは，窓の内側の外に出た文節を描かない(窓の縁に重ねない)
        NSGraphicsContext.saveGraphicsState()
        if let clip = layout.clip { NSRect(x: clip.lowerBound, y: 0, width: clip.upperBound - clip.lowerBound, height: body.height).clip() }
        for (index, column) in panel.columns.enumerated() {
            let node = NSRect(x: layout.trunkX[index], y: layout.trunkY, width: layout.trunkWidths[index], height: metrics.rowHeight)
            if let clip = layout.clip, node.maxX < clip.lowerBound || node.minX > clip.upperBound { continue }
            drawTrunkNode(column, in: node)
            if !theme.isRounded, index < panel.columns.count - 1 {
                // glass は文節の間を空けるだけにし，文として読めるようにする
                theme.line.setFill()
                NSRect(x: node.maxX, y: node.midY.rounded(), width: layout.trunkX[index + 1] - node.maxX, height: Branch.lineWidth).fill()
            }
            if column.isFocused {
                drawBranches(lowerRows(column), from: node, width: layout.branchWidth, downward: true)
                drawBranches(upperRows(column), from: node, width: layout.branchWidth, downward: false)
                if let slot = layout.slot, slot.placement == .side, let card = layout.card {
                    // 選んでいる候補から，枝の先へ意味のカードをつなぐ(分岐図の 3 段目)
                    if let selected = column.selectedAlternative, let layoutOfCard = slot.layout {
                        let row = NSRect(x: node.minX, y: node.maxY + CGFloat(selected) * metrics.rowHeight, width: layout.branchWidth, height: metrics.rowHeight)
                        let start = NSPoint(x: row.maxX.rounded(), y: row.midY.rounded())
                        let end = NSPoint(x: card.minX, y: MeaningCardDrawing.headerMidY(layoutOfCard, in: card))
                        MeaningCardDrawing.drawConnector(from: start, to: end, theme: theme)
                    }
                    drawCard(slot.layout, in: card)
                }
            } else if let preview = column.preview, !(branchRange?.overlaps(node.minX...node.maxX) ?? false) {
                // 添える候補は次の文節の手前までに収め，はみ出す分は省く(次の文節の添え書きと重ねない)
                let limit = index + 1 < layout.trunkX.count ? layout.trunkX[index + 1] : body.maxX - metrics.inset
                drawPreview(preview, under: node, maxX: limit)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        var footerY = layout.trunkY + metrics.rowHeight + layout.lowerHeight
        if let slot = layout.slot, slot.placement == .below, let card = layout.card {
            // 候補の下: 枝と足元のあいだに，窓の幅いっぱいのカードを出す
            drawCard(slot.layout, in: card)
            footerY = card.maxY + belowCardMargin
        }
        if let note = panel.columns.first(where: \.isFocused)?.usageNote {
            let row = NSRect(x: metrics.inset, y: footerY, width: body.width - metrics.inset * 2, height: metrics.footerHeight)
            drawText(note, attributes: [.font: labelFont, .foregroundColor: theme.textMuted], x: row.minX, in: row)
            footerY += metrics.footerHeight
        }
        if let note = panel.note {
            // 打ち間違いを直したことなど，IME が変えたことを知らせる
            let row = NSRect(x: metrics.inset, y: footerY, width: body.width - metrics.inset * 2, height: metrics.footerHeight)
            NoteDrawing.draw(note, x: row.minX, midY: row.midY, theme: theme)
            footerY += metrics.footerHeight
        }
        drawFooter(panel, y: footerY, width: body.width)
    }

    // MARK: - 幹

    private func drawTrunkNode(_ column: LatticePanel.Column, in node: NSRect) {
        let color: NSColor
        if theme.isRounded {
            if column.isFocused { GlassDrawing.fillCapsule(node.insetBy(dx: 0, dy: 2), color: theme.focusTint) }
            color = theme.text
        } else {
            if column.isFocused {
                theme.selection.setFill()
                node.fill()
            }
            color = column.isFocused ? theme.selectionText : theme.text
        }
        if let split = column.split {
            drawSplit(split, in: node, color: color)
        } else if let command = trunkCommand(column) {
            // コマンドを選んでいれば，幹も枝と同じく種類のアイコンと名前で見せる(入力中の文字には印を付けた名前が出る)
            CommandDrawing.drawIcon(command.kind, x: node.minX + Size.paddingX, midY: node.midY, theme: theme, selected: !theme.isRounded && column.isFocused)
            drawText(command.title, attributes: [.font: trunkFont, .foregroundColor: color], x: node.minX + Size.paddingX + CommandDrawing.width, in: node)
        } else {
            drawText(column.text, attributes: [.font: trunkFont, .foregroundColor: color], x: node.minX + Size.paddingX, in: node)
        }
        // 下線: 選び直した文節は実線，確信の低い文節は点線．線の種類でも区別し，色だけに頼らない
        let offset = theme.isRounded ? Glass.underlineOffset : Branch.underlineOffset
        let y = node.maxY - offset
        let from = node.minX + Size.paddingX
        let to = node.maxX - Size.paddingX - (column.isCorrected ? correctedLabelWidth : 0)
        if column.isCorrected {
            // 打ち間違いを直した文節には，文字のあとに補正の色で「修正」と添える．確信の低い文節の点線と見分けるため
            NoteDrawing.drawTag(UIStrings.Branch.corrected, maxX: node.maxX - Size.paddingX / 2, midY: node.midY, theme: theme,
                                selected: !theme.isRounded && column.isFocused)
        }
        if column.isDecided {
            GlassDrawing.drawUnderline(from: from, to: to, y: y, color: theme.isRounded ? theme.textMuted : color, dotted: false, theme: theme)
        } else if column.isUncertain {
            let dotColor = !theme.isRounded && column.isFocused ? theme.selectionText : theme.correction
            GlassDrawing.drawUnderline(from: from, to: to, y: y, color: dotColor, dotted: true, theme: theme)
        }
    }

    /// 幹の文節で選んでいるコマンドの種類と名前．コマンドを選んでいなければ nil
    private func trunkCommand(_ column: LatticePanel.Column) -> (kind: LauncherCommand.Kind, title: String)? {
        guard let index = column.selectedAlternative, column.alternativeCommands.indices.contains(index), column.alternatives.indices.contains(index),
              let kind = column.alternativeCommands[index] else { return nil }
        return (kind, column.alternatives[index])
    }

    // MARK: - 区切る位置

    /// 区切る位置の番号を挟んだ文節の並び．runs は番号のあいだの字と左端，badges は番号と丸の中心(幹の文字の左端から)
    private struct SplitPieces {
        var runs: [(text: String, x: CGFloat)] = []
        var badges: [(label: String, centerX: CGFloat)] = []
        var width: CGFloat = 0
    }

    private func splitPieces(_ split: LatticePanel.Column.Split) -> SplitPieces {
        let slot = Branch.splitBadgeSize + Branch.splitBadgeGap * 2
        var pieces = SplitPieces()
        var x: CGFloat = 0
        for (index, text) in split.pieces.enumerated() {
            if index > 0 {
                pieces.badges.append(("\(index)", x + slot / 2))
                x += slot
            }
            pieces.runs.append((text, x))
            x += textWidth(text, font: trunkFont)
        }
        pieces.width = x
        return pieces
    }

    /// 区切っている文節の幹．切れ目(「問題｜が｜ある」)に，候補の番号と同じ形の小さな丸で番号を描く
    private func drawSplit(_ split: LatticePanel.Column.Split, in node: NSRect, color: NSColor) {
        let pieces = splitPieces(split)
        let left = node.minX + Size.paddingX
        for run in pieces.runs {
            drawText(run.text, attributes: [.font: trunkFont, .foregroundColor: color], x: left + run.x, in: node)
        }
        // platinum と desk は注目している文節を選択の色で塗るので，丸も選んでいる行の上の描き方にする
        for badge in pieces.badges {
            GlassDrawing.drawBadge(badge.label, center: NSPoint(x: (left + badge.centerX).rounded(), y: node.midY.rounded()), theme: theme,
                                   selected: !theme.isRounded, opacity: 1, size: Branch.splitBadgeSize, fontSize: Branch.splitBadgeFontSize)
        }
    }

    // MARK: - 枝

    private struct Row {
        var text: String
        var badge: String
        var isSelected: Bool
        var opacity: CGFloat
        /// 打ったまま・修正・コマンドの添え書きか，ユーザー辞書の語のコメント
        var note: String? = nil
        /// コマンドの候補なら，その種類(文字の前にアイコンを置き，添え書きをアクセントの色の札にする)
        var command: LauncherCommand.Kind? = nil
        /// 文字のすぐあとに控えめに添える説明(絵文字の名前)
        var detail: String? = nil
    }

    /// 下の枝(変換の候補)．第 1 候補はすぐに濃く出す
    private func lowerRows(_ column: LatticePanel.Column) -> [Row] {
        column.alternatives.enumerated().map { index, text in
            Row(text: text, badge: "\(index + 1)", isSelected: index == column.selectedAlternative, opacity: index == 0 ? 1 : restOpacity,
                note: column.alternativeNotes.indices.contains(index) ? column.alternativeNotes[index] : nil,
                command: column.alternativeCommands.indices.contains(index) ? column.alternativeCommands[index] : nil,
                detail: column.alternativeDetails.indices.contains(index) ? column.alternativeDetails[index] : nil)
        }
    }

    /// 上の枝(文字種)．幹に近いものから上へ積む
    private func upperRows(_ column: LatticePanel.Column) -> [Row] {
        column.variants.enumerated().map { index, text in
            Row(text: text, badge: UIStrings.Branch.variantBadge, isSelected: index == column.selectedVariant, opacity: restOpacity)
        }
    }

    /// 枝の index 番目の行(番号・文字・札を描く枠)．描くときと押した位置を調べるときで同じものを使う
    private func branchRowRect(_ index: Int, from node: NSRect, width: CGFloat, downward: Bool, metrics: Metrics) -> NSRect {
        let stemX = (node.minX + metrics.stemX).rounded()
        let y = downward ? node.maxY + CGFloat(index) * metrics.rowHeight : node.minY - CGFloat(index + 1) * metrics.rowHeight
        return NSRect(x: stemX + metrics.branchIndent, y: y, width: width - metrics.stemX - metrics.branchIndent, height: metrics.rowHeight)
    }

    /// 枝の行の札の右端
    private func tagMaxX(in row: NSRect) -> CGFloat { row.maxX - Size.paddingX / 2 }

    private func drawBranches(_ rows: [Row], from node: NSRect, width: CGFloat, downward: Bool) {
        guard !rows.isEmpty else { return }
        let metrics = metrics
        let rowRect = { (index: Int) -> NSRect in
            self.branchRowRect(index, from: node, width: width, downward: downward, metrics: metrics)
        }
        BranchLineDrawing.draw(stemX: node.minX + metrics.stemX, rootY: rootY(of: node, downward: downward),
                               rowMidYs: rows.indices.map { rowRect($0).midY }, tipX: rowRect(0).minX - metrics.tipGap,
                               selected: rows.firstIndex(where: \.isSelected), style: lineStyle(color: theme.line))
        for (index, row) in rows.enumerated() {
            drawRow(row, in: rowRect(index))
        }
    }

    /// 幹の根元: 下の枝は文節の札の下の端，上の枝は上の端
    private func rootY(of node: NSRect, downward: Bool) -> CGFloat {
        downward ? node.maxY - metrics.rootInset : node.minY + metrics.rootInset
    }

    /// 枝の線の太さと曲がり角．曲線の枝のテーマだけ角を丸める
    private func lineStyle(color: NSColor) -> BranchLineDrawing.Style {
        let metrics = metrics
        let curved = theme.isRounded && !theme.straightBranches
        return BranchLineDrawing.Style(lineWidth: metrics.lineWidth, selectedWidth: metrics.lineWidthSelected,
                                       radius: curved ? Glass.branchTurnRadius : 0, color: color, selection: theme.selection)
    }

    private func drawRow(_ row: Row, in rect: NSRect) {
        let textColor = (row.isSelected ? theme.selectionText : theme.text).withAlphaComponent(row.isSelected ? 1 : row.opacity)
        if theme.isRounded {
            if row.isSelected { GlassDrawing.fillCapsule(rect.insetBy(dx: 0, dy: 2), color: theme.selection) }
            let badgeCenter = NSPoint(x: rect.minX + Size.paddingX / 2 + Glass.badgeSize / 2, y: rect.midY)
            GlassDrawing.drawBadge(row.badge, center: badgeCenter, theme: theme, selected: row.isSelected, opacity: row.opacity)
        } else {
            if row.isSelected {
                theme.selection.setFill()
                rect.fill()
            }
            let badgeColor = (row.isSelected ? theme.selectionText : theme.textMuted).withAlphaComponent(row.isSelected ? 1 : row.opacity)
            GlassDrawing.drawLabel(row.badge, color: badgeColor, in: NSRect(x: rect.minX + Size.paddingX / 2, y: rect.minY, width: metrics.lead - Size.paddingX / 2, height: rect.height), theme: theme)
        }
        var textX = rect.minX + Size.paddingX / 2 + metrics.lead
        if let kind = row.command {
            // コマンドの候補は，文字の前に種類のアイコンを置く
            CommandDrawing.drawIcon(kind, x: textX, midY: rect.midY, theme: theme, selected: row.isSelected, opacity: row.isSelected ? 1 : row.opacity)
            textX += CommandDrawing.width
        }
        // 絵文字の名前は候補の文字のすぐあとに薄く小さく添える(番号と同じ色)
        let detailColor = (row.isSelected ? theme.selectionText : theme.textMuted).withAlphaComponent(row.isSelected ? 1 : row.opacity)
        CandidateDetailDrawing.draw(CandidateDetailDrawing.line(row.text, attributes: [.font: candidateFont, .foregroundColor: textColor], detail: row.detail,
                                                                detailAttributes: [.font: labelFont, .foregroundColor: detailColor]),
                                    x: textX, in: rect)
        if let note = row.note {
            NoteDrawing.drawTag(note, maxX: tagMaxX(in: rect), midY: rect.midY, theme: theme, selected: row.isSelected, command: row.command != nil)
        }
    }

    /// 注目していない確信の低い文節の下に，次の候補を 1 つだけ薄く添える
    private func drawPreview(_ text: String, under node: NSRect, maxX: CGFloat) {
        let metrics = metrics
        let stemX = node.minX + metrics.stemX
        let row = NSRect(x: stemX, y: node.maxY, width: node.width, height: metrics.rowHeight)
        let color = theme.textMuted.withAlphaComponent(restOpacity)
        // 枝と同じ形で，幹から短く曲がる
        let tipX = (stemX + metrics.branchIndent / 2).rounded()
        BranchLineDrawing.draw(stemX: stemX, rootY: rootY(of: node, downward: true), rowMidYs: [row.midY], tipX: tipX, selected: nil,
                               style: lineStyle(color: theme.line.withAlphaComponent(theme.line.alphaComponent * restOpacity)))
        let textX = tipX + Size.paddingX / 2
        let attributes: [NSAttributedString.Key: Any] = [.font: candidateFont, .foregroundColor: color]
        drawText(TextFitting.truncated(text, attributes: attributes, width: maxX - textX), attributes: attributes, x: textX, in: row)
    }

    // MARK: - 足元

    /// 足元の右に何番目の候補かを出すか．区切っているときは候補を出さないので出さない
    private func showsPosition(_ panel: LatticePanel) -> Bool {
        panel.columns.first(where: \.isFocused)?.split == nil
    }

    private func position(of panel: LatticePanel) -> String {
        let count = panel.columns.first(where: \.isFocused)?.alternatives.count ?? 0
        return UIStrings.Branch.position(first: panel.position, last: panel.position + max(count, 1) - 1, total: panel.total)
    }

    private func footerWidth(_ panel: LatticePanel) -> CGFloat {
        let source = panel.columns.first(where: \.isFocused)?.sourceName
            .map { textWidth(UIStrings.Branch.dictionarySource($0), font: labelFont) + Size.paddingX } ?? 0
        return (showsHints ? GlassDrawing.hintsWidth(hints, theme: theme) : 0) + source + associationWidth(panel)
    }

    /// 連想の知らせ(R-18)．キーが割り当てられていればキーキャップの札，無ければ語だけ
    private func associationKeyHint(_ panel: LatticePanel) -> KeyHint? {
        panel.associationHint.flatMap { hint in hint.key.map { KeyHint(key: $0, label: hint.label) } }
    }

    private func associationWidth(_ panel: LatticePanel) -> CGFloat {
        guard let hint = panel.associationHint else { return 0 }
        let width = associationKeyHint(panel).map { GlassDrawing.hintsWidth([$0], theme: theme) } ?? textWidth(hint.label, font: labelFont)
        return width + Size.paddingX
    }

    private func drawFooter(_ panel: LatticePanel, y: CGFloat, width: CGFloat) {
        let metrics = metrics
        let lineInset = theme.isRounded ? metrics.inset : metrics.inset - Size.paddingX
        if theme.isRounded {
            theme.line.setFill()
            NSRect(x: lineInset, y: y, width: width - lineInset * 2, height: Size.frameWidth).fill()
        } else {
            BevelDrawing.drawSeparator(y: y, from: lineInset, to: width - lineInset, theme: theme)
        }
        let footer = NSRect(x: metrics.inset, y: y + Size.frameWidth, width: width - metrics.inset * 2, height: metrics.footerHeight)
        let muted: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.textMuted]
        let position = showsPosition(panel) ? position(of: panel) : ""
        // 右の位置と辞書の名前，連想の知らせを先に取り，残りの幅に入るキーの案内だけを出す
        let reserved = footerWidth(panel) - (showsHints ? GlassDrawing.hintsWidth(hints, theme: theme) : 0)
            + (position.isEmpty ? 0 : textWidth(position, font: labelFont) + Size.paddingX)
        var hintsEnd = footer.minX
        if showsHints {
            let shown = GlassDrawing.hints(hints, fitting: footer.width - reserved, theme: theme)
            GlassDrawing.drawHints(shown, x: footer.minX, midY: footer.midY, theme: theme)
            if !shown.isEmpty { hintsEnd += GlassDrawing.hintsWidth(shown, theme: theme) + Size.paddingX }
        }
        if let hint = panel.associationHint {
            // 選んでいる候補に連想があることを，キーの案内のあとに小さく出す(R-18)．キーは文字ではなくキーキャップで描く
            if let keyHint = associationKeyHint(panel) {
                GlassDrawing.drawHints([keyHint], x: hintsEnd, midY: footer.midY, theme: theme)
            } else {
                drawText(hint.label, attributes: muted, x: hintsEnd, in: footer)
            }
        }
        drawText(position, attributes: muted, x: footer.maxX - textWidth(position, font: labelFont), in: footer)
        if let source = panel.columns.first(where: \.isFocused)?.sourceName {
            // 選んでいる候補が取り込んだ辞書の語なら，その辞書の名前を位置の左に小さく出す(R-16)
            let label = UIStrings.Branch.dictionarySource(source)
            let x = footer.maxX - textWidth(position, font: labelFont) - Size.paddingX - textWidth(label, font: labelFont)
            drawText(label, attributes: [.font: labelFont, .foregroundColor: theme.correction], x: x, in: footer)
        }
    }

    // MARK: - 部品

    /// 語の意味のカード．layout が nil なら空けておくカード(意味の無い候補を選んでいるとき)
    private func drawCard(_ layout: MeaningCardDrawing.Layout?, in rect: NSRect) {
        guard let layout else {
            MeaningCardDrawing.drawEmpty(in: rect, theme: theme)
            return
        }
        MeaningCardDrawing.drawBackground(in: rect, theme: theme)
        MeaningCardDrawing.drawContent(layout, in: rect, theme: theme)
    }

    private func drawText(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, in rect: NSRect) {
        let size = text.size(withAttributes: attributes)
        let y = rect.minY + ((rect.height - size.height) / 2).rounded()
        text.draw(at: NSPoint(x: x.rounded(), y: y), withAttributes: attributes)
    }
}

extension LatticePanel.Column {
    /// 下の枝の index 番目の候補に添えたユーザー辞書の語のコメント(札に出す文字．長ければ先頭だけ)．コメントでなければ nil
    func comment(at index: Int) -> String? {
        guard alternativeComments.indices.contains(index), alternativeComments[index], alternativeNotes.indices.contains(index) else { return nil }
        return alternativeNotes[index]
    }
}
