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
    private typealias Meaning = DesignTokens.Size.Meaning
    private typealias Space = DesignTokens.Size.Space

    var panel: LatticePanel? {
        didSet {
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
        /// 候補の行の地の上下を縮める量(角丸のテーマ)．行の地の見える上の端は行の上の端からこの分だけ下
        var rowInset: CGFloat
        var lineWidth: CGFloat
        var lineWidthSelected: CGFloat
        /// 幹の根元を文節の枠の端からずらす量(角丸のテーマは文節の地が上下に細いので，その端から伸ばす)
        var rootInset: CGFloat
    }

    /// 区切りの線の上と下，カードと枝・区切りの線のあいだの空き
    private var gap: CGFloat { Glass.separatorGap }

    /// 見出し・注釈・知らせ・足元の文字の左右の端．幹の文節の文字の左の端(文節の地の左から paddingX)にそろえる
    private var textInset: CGFloat { metrics.inset + Size.paddingX }

    private var metrics: Metrics {
        let scale = fontSize / Size.fontSize
        // 足元の行(と注釈・知らせの行)は，キーキャップ・案内のアイコン・文字の行の箱のいちばん高いもの
        let footer = max(Glass.keycapHeight, Glass.noteIconSize, (labelFont.ascender - labelFont.descender).rounded(.up))
        if theme.isRounded {
            return Metrics(inset: Size.frameWidth + Glass.windowPadding, rowHeight: (Glass.rowHeight * scale).rounded(), trunkGap: Glass.trunkGap,
                           branchIndent: Glass.branchIndent, stemX: Glass.branchStemX, lead: Glass.badgeSize + Size.paddingX,
                           footerHeight: footer, rowInset: Glass.selectionInsetY, lineWidth: Glass.lineWidth,
                           lineWidthSelected: Glass.lineWidthSelected, rootInset: Glass.selectionInsetY)
        }
        return Metrics(inset: Size.frameWidth + Size.bevelWidth + Glass.windowPadding, rowHeight: (Size.rowHeight * scale).rounded(),
                       trunkGap: Branch.trunkGap, branchIndent: Branch.branchIndent, stemX: Branch.branchStemX, lead: Size.indexWidth,
                       footerHeight: footer, rowInset: 0, lineWidth: Branch.lineWidth, lineWidthSelected: Branch.lineWidthSelected,
                       rootInset: 0)
    }

    private var candidateFont: NSFont { theme.candidateFont(size: fontSize) }
    private var trunkFont: NSFont { theme.trunkFont(size: fontSize) }
    private var labelFont: NSFont { theme.labelFont(size: theme.isRounded ? Glass.labelFontSize : Size.labelFontSize) }
    private var dropShadowOffset: CGFloat { theme.hasDropShadow ? Size.shadowOffset : 0 }

    // MARK: - 語の意味

    /// 候補の下に出す語の意味(R-08)．候補の右に出す設定では，窓の外の吹き出し(MeaningBubbleController)に出す
    private struct MeaningSlot {
        var layout: MeaningCardDrawing.Layout
        /// 目印の列の左の端と見出しの行の縦の真ん中
        var position: MeaningCardLayout.Placement
        var size: NSSize
    }

    /// 候補の下: 目印の列を幹の文字と足元の左の端にそろえる．見出しの行は場所の上の端から
    private var belowPosition: MeaningCardLayout.Placement {
        .init(left: Size.paddingX, headerMidY: MeaningCardDrawing.headerHeight(theme: theme) / 2)
    }

    /// 同音語のタグに出す語．下の枝に出ていない語だけにする(枝に出ている語は見れば分かる)
    static func others(of note: HomophoneNote, in column: LatticePanel.Column) -> [String] {
        let shown = Set(column.alternatives)
        return note.others.filter { !shown.contains($0) }
    }

    /// 幅 width(窓の中身の幅)の，候補の下に出す語の意味．区切っているあいだと，候補の右(吹き出し)に出す設定では nil
    private func meaningSlot(for panel: LatticePanel, width: CGFloat) -> MeaningSlot? {
        guard panel.meaningPlacement == .below, let column = panel.columns.first(where: \.isFocused), column.split == nil,
              let note = column.homophone else { return nil }
        let position = belowPosition
        let layout = MeaningCardDrawing.layout(note, others: Self.others(of: note, in: column), width: width, placement: position, theme: theme)
        return MeaningSlot(layout: layout, position: position, size: layout.size)
    }

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

    /// 打ち間違いを直した文節の幹で，文字のあとに添える「修正」のタグの幅(前の空きを含む)
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
        let branchRight = (focused.map { trunkX[$0] } ?? metrics.inset) + branchWidth
        let previewRows = panel.columns.contains { $0.preview != nil } ? 1 : 0
        let upperRows = column?.variants.count ?? 0
        let lowerRows = max(column?.alternatives.count ?? 0, previewRows)
        // 足元: 左右の余白と，案内と位置のあいだ(案内と案内のあいだと同じ)
        let footer = footerWidth(panel) + (showsPosition(panel) ? textWidth(position(of: panel), font: labelFont) : 0) + Size.paddingX * 2 + Glass.hintGap
        // 使い分けや誤用の注釈と，IME からの知らせ(直したことなど)は，枝と足元のあいだに 1 行ずつ出す．キーの案内は消さない
        let note = [column?.usageNote.map { textWidth($0, font: labelFont) }, panel.note.map { NoteDrawing.width($0, theme: theme) },
                    panel.meaningPlacement == .below && column?.homophone != nil ? Meaning.listWidth : nil]
            .compactMap { $0.map { $0 + Size.paddingX * 2 } }.max() ?? 0
        let heading = panel.association.map { AssociationHeadingDrawing.width($0, font: labelFont, emphasis: labelFont) + (metrics.inset + Size.paddingX) * 2 } ?? 0
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
        width = width.rounded(.up)
        let contentRight = width - metrics.inset
        // いちばん上の行の地(角丸のテーマは行の上下を縮めて描く)の上の端を，縁の内側の余白の端にそろえる
        let trunkY = metrics.inset - metrics.rowInset + headingHeight(panel) + CGFloat(upperRows) * metrics.rowHeight
        // 下の枝の見える下の端(候補の行の地の下の端)
        let lowerTop = trunkY + metrics.rowHeight
        var bottom = lowerTop + metrics.rowHeight * CGFloat(lowerRows) - (lowerRows > 0 ? metrics.rowInset : 0)
        var slot: MeaningSlot?
        var card: NSRect?
        // 候補の下: 窓の中身の幅いっぱい．枝とのあいだは区切りの線の上と同じ空き
        if focused != nil, let below = meaningSlot(for: panel, width: contentRight - metrics.inset) {
            let frame = NSRect(x: metrics.inset, y: bottom + gap, width: below.size.width, height: below.size.height)
            slot = below
            card = frame
            bottom = frame.maxY
        }
        let notes = (column?.usageNote == nil ? 0 : 1) + (panel.note == nil ? 0 : 1)
        let height = bottom + (gap + metrics.footerHeight) * CGFloat(notes) + gap + Size.frameWidth + gap + metrics.footerHeight + metrics.inset
        let lowerHeight = bottom - lowerTop
        return Layout(trunkX: shiftedX, trunkWidths: trunkWidths, lowerRows: lowerRows, trunkY: trunkY,
                      branchWidth: shownBranchWidth, size: NSSize(width: width, height: height.rounded(.up)),
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

    /// 連想の一覧の見出しの行の高さ(区切りの線とその上下の空きを含む)．連想でなければ 0
    private func headingHeight(_ panel: LatticePanel) -> CGFloat {
        panel.association == nil ? 0 : metrics.footerHeight + gap * 2 + Size.frameWidth
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
            // コメントのタグは枝の行の中にあるので，行より先に調べる(タグを押すと候補の代わりにコメントを入れる)
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

    /// 注目している文節で選んでいる候補の枝の行(この view の座標)．語の意味の吹き出しの三角はこの行の縦の真ん中を指す．
    /// 候補を選んでいないとき・区切っているときは nil
    func selectedRowRect() -> NSRect? {
        guard let panel, let focused = panel.columns.firstIndex(where: \.isFocused) else { return nil }
        let column = panel.columns[focused]
        guard column.split == nil, let selected = column.selectedAlternative, column.alternatives.indices.contains(selected) else { return nil }
        let layout = layout(for: panel)
        let node = NSRect(x: layout.trunkX[focused], y: layout.trunkY, width: layout.trunkWidths[focused], height: metrics.rowHeight)
        return branchRowRect(selected, from: node, width: layout.branchWidth, downward: true, metrics: metrics)
    }

    /// 語の意味の吹き出しが覆わない物(この view の座標)．幹の文節・選んでいない枝の行・枝の下の注釈と足元
    func bubbleObstacles() -> [NSRect] {
        guard let panel, let focused = panel.columns.firstIndex(where: \.isFocused) else { return [] }
        let layout = layout(for: panel)
        let metrics = metrics
        let nodes = panel.columns.indices.map { NSRect(x: layout.trunkX[$0], y: layout.trunkY, width: layout.trunkWidths[$0], height: metrics.rowHeight) }
        let column = panel.columns[focused]
        let node = nodes[focused]
        let lower = lowerRows(column).indices.filter { $0 != column.selectedAlternative }
            .map { branchRowRect($0, from: node, width: layout.branchWidth, downward: true, metrics: metrics) }
        let upper = upperRows(column).indices.map { branchRowRect($0, from: node, width: layout.branchWidth, downward: false, metrics: metrics) }
        let footerTop = layout.trunkY + metrics.rowHeight + layout.lowerHeight
        let footer = NSRect(x: 0, y: footerTop, width: layout.size.width, height: layout.size.height - footerTop)
        return nodes + lower + upper + [footer]
    }

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
            let row = NSRect(x: textInset, y: metrics.inset, width: body.width - textInset * 2, height: metrics.footerHeight)
            AssociationHeadingDrawing.draw(heading, in: row, theme: theme, font: labelFont, emphasis: labelFont)
            drawSeparator(y: row.maxY + gap, width: body.width)
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
            } else if let preview = column.preview, !(branchRange?.overlaps(node.minX...node.maxX) ?? false) {
                // 添える候補は次の文節の手前までに収め，はみ出す分は省く(次の文節の添え書きと重ねない)
                let limit = index + 1 < layout.trunkX.count ? layout.trunkX[index + 1] : body.maxX - metrics.inset
                drawPreview(preview, under: node, maxX: limit)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        var footerY = layout.trunkY + metrics.rowHeight + layout.lowerHeight
        if let slot = layout.slot, let card = layout.card {
            // 候補の下: 枝と足元のあいだに，窓の幅いっぱいに出す
            MeaningCardDrawing.drawContent(slot.layout, in: card, theme: theme)
        }
        if let note = panel.columns.first(where: \.isFocused)?.usageNote {
            let row = NSRect(x: textInset, y: footerY + gap, width: body.width - textInset * 2, height: metrics.footerHeight)
            drawText(note, attributes: [.font: labelFont, .foregroundColor: theme.textMuted], x: row.minX, in: row)
            footerY = row.maxY
        }
        if let note = panel.note {
            // 打ち間違いを直したことなど，IME が変えたことを知らせる
            let row = NSRect(x: textInset, y: footerY + gap, width: body.width - textInset * 2, height: metrics.footerHeight)
            NoteDrawing.draw(note, x: row.minX, midY: row.midY, theme: theme)
            footerY = row.maxY
        }
        drawFooter(panel, y: footerY + gap, width: body.width)
    }

    // MARK: - 幹

    private func drawTrunkNode(_ column: LatticePanel.Column, in node: NSRect) {
        let color: NSColor
        if theme.isRounded {
            if column.isFocused { GlassDrawing.fillCapsule(node.insetBy(dx: 0, dy: Glass.selectionInsetY), color: theme.focusTint) }
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
        /// コマンドの候補なら，その種類(文字の前にアイコンを置き，添え書きをアクセントの色のタグにする)
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

    /// 枝の index 番目の行(番号・文字・タグを描く枠)．描くときと押した位置を調べるときで同じものを使う
    private func branchRowRect(_ index: Int, from node: NSRect, width: CGFloat, downward: Bool, metrics: Metrics) -> NSRect {
        let stemX = (node.minX + metrics.stemX).rounded()
        let y = downward ? node.maxY + CGFloat(index) * metrics.rowHeight : node.minY - CGFloat(index + 1) * metrics.rowHeight
        return NSRect(x: stemX + metrics.branchIndent, y: y, width: width - metrics.stemX - metrics.branchIndent, height: metrics.rowHeight)
    }

    /// 枝の行のタグの右端
    private func tagMaxX(in row: NSRect) -> CGFloat { row.maxX - Size.paddingX / 2 }

    private func drawBranches(_ rows: [Row], from node: NSRect, width: CGFloat, downward: Bool) {
        guard !rows.isEmpty else { return }
        let metrics = metrics
        let rowRect = { (index: Int) -> NSRect in
            self.branchRowRect(index, from: node, width: width, downward: downward, metrics: metrics)
        }
        BranchLineDrawing.draw(stemX: node.minX + metrics.stemX, rootY: rootY(of: node, downward: downward),
                               rowMidYs: rows.indices.map { rowRect($0).midY }, tipX: leadMinX(in: rowRect(0)) - Space.inline,
                               selected: rows.firstIndex(where: \.isSelected), style: lineStyle(color: theme.line))
        for (index, row) in rows.enumerated() {
            drawRow(row, in: rowRect(index))
        }
    }

    /// 枝の行の番号(丸)の左の端．枝の水平の線は，ここから inline の空きを残して終える
    private func leadMinX(in row: NSRect) -> CGFloat { row.minX + Size.paddingX / 2 }

    /// 幹の根元: 下の枝は文節のタグの下の端，上の枝は上の端
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
            if row.isSelected { GlassDrawing.fillCapsule(rect.insetBy(dx: 0, dy: Glass.selectionInsetY), color: theme.selection) }
            let badgeCenter = NSPoint(x: leadMinX(in: rect) + Glass.badgeSize / 2, y: rect.midY)
            GlassDrawing.drawBadge(row.badge, center: badgeCenter, theme: theme, selected: row.isSelected, opacity: row.opacity)
        } else {
            if row.isSelected {
                theme.selection.setFill()
                rect.fill()
            }
            let badgeColor = (row.isSelected ? theme.selectionText : theme.textMuted).withAlphaComponent(row.isSelected ? 1 : row.opacity)
            GlassDrawing.drawLabel(row.badge, color: badgeColor, in: NSRect(x: leadMinX(in: rect), y: rect.minY, width: metrics.lead - Size.paddingX / 2, height: rect.height), theme: theme)
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
        let textX = tipX + Space.inline
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

    /// 連想の知らせ(R-18)．キーが割り当てられていればキーキャップ，無ければ語だけ
    private func associationKeyHint(_ panel: LatticePanel) -> KeyHint? {
        panel.associationHint.flatMap { hint in hint.key.map { KeyHint(key: $0, label: hint.label) } }
    }

    private func associationWidth(_ panel: LatticePanel) -> CGFloat {
        guard let hint = panel.associationHint else { return 0 }
        let width = associationKeyHint(panel).map { GlassDrawing.hintsWidth([$0], theme: theme) } ?? textWidth(hint.label, font: labelFont)
        return width + Glass.hintGap
    }

    /// 区切りの線．窓の中身の左右の端から端まで(語の意味のカードの端と同じ)
    private func drawSeparator(y: CGFloat, width: CGFloat) {
        theme.line.setFill()
        NSRect(x: metrics.inset, y: y, width: width - metrics.inset * 2, height: Size.frameWidth).fill()
    }

    /// 足元．y は区切りの線の上の端．線の下に区切りの線の上と同じ空きを空けて案内を出す
    private func drawFooter(_ panel: LatticePanel, y: CGFloat, width: CGFloat) {
        let metrics = metrics
        drawSeparator(y: y, width: width)
        let footer = NSRect(x: textInset, y: y + Size.frameWidth + gap, width: width - textInset * 2, height: metrics.footerHeight)
        let muted: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.textMuted]
        let position = showsPosition(panel) ? position(of: panel) : ""
        // 右の位置と辞書の名前，連想の知らせを先に取り，残りの幅に入るキーの案内だけを出す
        let reserved = footerWidth(panel) - (showsHints ? GlassDrawing.hintsWidth(hints, theme: theme) : 0)
            + (position.isEmpty ? 0 : textWidth(position, font: labelFont) + Glass.hintGap)
        var hintsEnd = footer.minX
        if showsHints {
            let shown = GlassDrawing.hints(hints, fitting: footer.width - reserved, theme: theme)
            GlassDrawing.drawHints(shown, x: footer.minX, midY: footer.midY, theme: theme)
            if !shown.isEmpty { hintsEnd += GlassDrawing.hintsWidth(shown, theme: theme) + Glass.hintGap }
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

    private func drawText(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, in rect: NSRect) {
        TextFitting.draw(text, attributes: attributes, x: x, midY: rect.midY)
    }
}

extension LatticePanel.Column {
    /// 下の枝の index 番目の候補に添えたユーザー辞書の語のコメント(タグに出す文字．長ければ先頭だけ)．コメントでなければ nil
    func comment(at index: Int) -> String? {
        guard alternativeComments.indices.contains(index), alternativeComments[index], alternativeNotes.indices.contains(index) else { return nil }
        return alternativeNotes[index]
    }
}
