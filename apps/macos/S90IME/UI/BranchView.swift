import AppKit
import S90Application
import S90Domain

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
/// glass は曲線の枝と角丸の選択，platinum と desk は 1 ドットの直線の枝で描く
final class BranchView: NSView {
    private typealias Size = DesignTokens.Size.Candidate
    private typealias Branch = DesignTokens.Size.Branch
    private typealias Glass = DesignTokens.Size.Glass

    var panel: LatticePanel? { didSet { needsDisplay = true } }
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
    }

    private var metrics: Metrics {
        let scale = fontSize / Size.fontSize
        if theme.isRounded {
            return Metrics(inset: Glass.padding, rowHeight: (Glass.rowHeight * scale).rounded(), trunkGap: Glass.trunkGap,
                           branchIndent: Glass.branchIndent, stemX: Glass.branchStemX, lead: Glass.badgeSize + Size.paddingX,
                           footerHeight: Glass.footerHeight)
        }
        let labelHeight = (labelFont.ascender - labelFont.descender).rounded(.up) + Size.sectionPaddingY * 2
        return Metrics(inset: Size.frameWidth + Size.bevelWidth + Size.paddingX, rowHeight: (Size.rowHeight * scale).rounded(),
                       trunkGap: Branch.trunkGap, branchIndent: Branch.branchIndent, stemX: Branch.branchStemX, lead: Size.indexWidth,
                       footerHeight: max(labelHeight, Glass.keycapHeight + Size.sectionPaddingY * 2))
    }

    private var candidateFont: NSFont { theme.candidateFont(size: fontSize) }
    private var trunkFont: NSFont { theme.trunkFont(size: fontSize) }
    private var labelFont: NSFont { theme.labelFont(size: theme.isRounded ? Glass.labelFontSize : Size.labelFontSize) }
    private var dropShadowOffset: CGFloat { theme.hasDropShadow ? Size.shadowOffset : 0 }

    /// 幹・枝・足元の位置．描くときと大きさを求めるときで同じものを使う
    private struct Layout {
        var trunkX: [CGFloat]
        var trunkWidths: [CGFloat]
        var lowerRows: Int
        var trunkY: CGFloat
        var branchWidth: CGFloat
        var size: NSSize
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        text.size(withAttributes: [.font: font]).width.rounded(.up)
    }

    /// 打ち間違いを直した文節の幹で，文字のあとに添える「修正」の札の幅(前の空きを含む)
    private var correctedLabelWidth: CGFloat {
        NoteDrawing.tagWidth(UIStrings.Branch.corrected, theme: theme) + Size.paddingX / 2
    }

    private func layout(for panel: LatticePanel) -> Layout {
        let metrics = metrics
        var x = metrics.inset
        var trunkX: [CGFloat] = []
        var trunkWidths: [CGFloat] = []
        for column in panel.columns {
            let width = (column.split.map { splitPieces($0).width } ?? textWidth(column.text, font: trunkFont)) + Size.paddingX * 2
                + (column.isCorrected ? correctedLabelWidth : 0)
            trunkX.append(x)
            trunkWidths.append(width)
            x += width + metrics.trunkGap
        }
        let trunkRight = x - metrics.trunkGap
        let focused = panel.columns.firstIndex(where: \.isFocused)
        let column = focused.map { panel.columns[$0] }
        let labels = (column?.alternatives ?? []) + (column?.variants ?? [])
        // 打ったまま・修正の添え書きの幅も足す
        let noteWidth = (column?.alternativeNotes.compactMap { $0 }.map { textWidth($0, font: labelFont) }.max()).map { $0 + Size.paddingX * 2 } ?? 0
        let branchWidth = metrics.stemX + metrics.branchIndent + metrics.lead
            + (labels.map { textWidth($0, font: candidateFont) }.max() ?? 0) + noteWidth + Size.paddingX * 2
        let branchRight = (focused.map { trunkX[$0] } ?? metrics.inset) + branchWidth
        let previewRows = panel.columns.contains { $0.preview != nil } ? 1 : 0
        let upperRows = column?.variants.count ?? 0
        let lowerRows = max(column?.alternatives.count ?? 0, previewRows)
        let footer = footerWidth(panel) + (showsPosition(panel) ? textWidth(position(of: panel), font: labelFont) : 0) + Size.paddingX * 3
        // 使い分けや誤用の注釈と，IME からの知らせ(直したことなど)は，枝と足元のあいだに 1 行ずつ出す．キーの案内は消さない
        let note = [column?.usageNote.map { textWidth($0, font: labelFont) }, panel.note.map { NoteDrawing.width($0, theme: theme) }]
            .compactMap { $0.map { $0 + Size.paddingX * 2 } }.max() ?? 0
        let heading = panel.association.map { AssociationHeadingDrawing.width($0, font: labelFont, emphasis: labelFont) + metrics.inset * 2 } ?? 0
        let width = max(Size.minWidth, trunkRight + metrics.inset, branchRight + metrics.inset, footer + metrics.inset * 2, note + metrics.inset * 2, heading)
        let trunkY = metrics.inset + headingHeight(panel) + CGFloat(upperRows) * metrics.rowHeight
        let height = trunkY + metrics.rowHeight * CGFloat(1 + lowerRows) + Size.frameWidth + metrics.footerHeight
            + (column?.usageNote == nil ? 0 : metrics.footerHeight)
            + (panel.note == nil ? 0 : metrics.footerHeight)
            + (theme.isRounded ? 0 : metrics.inset)
        return Layout(trunkX: trunkX, trunkWidths: trunkWidths, lowerRows: lowerRows, trunkY: trunkY,
                      branchWidth: branchWidth, size: NSSize(width: width.rounded(.up), height: height.rounded(.up)))
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
        if let index = column.alternatives.indices.first(where: { row($0, downward: true).contains(point) }) { return .alternative(index) }
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
        for (index, column) in panel.columns.enumerated() {
            let node = NSRect(x: layout.trunkX[index], y: layout.trunkY, width: layout.trunkWidths[index], height: metrics.rowHeight)
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
        var footerY = layout.trunkY + metrics.rowHeight * CGFloat(1 + layout.lowerRows)
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
        /// 打ったまま・修正の添え書き
        var note: String? = nil
    }

    /// 下の枝(変換の候補)．第 1 候補はすぐに濃く出す
    private func lowerRows(_ column: LatticePanel.Column) -> [Row] {
        column.alternatives.enumerated().map { index, text in
            Row(text: text, badge: "\(index + 1)", isSelected: index == column.selectedAlternative, opacity: index == 0 ? 1 : restOpacity,
                note: column.alternativeNotes.indices.contains(index) ? column.alternativeNotes[index] : nil)
        }
    }

    /// 上の枝(文字種)．幹に近いものから上へ積む
    private func upperRows(_ column: LatticePanel.Column) -> [Row] {
        column.variants.enumerated().map { index, text in
            Row(text: text, badge: UIStrings.Branch.variantBadge, isSelected: index == column.selectedVariant, opacity: restOpacity)
        }
    }

    private func drawBranches(_ rows: [Row], from node: NSRect, width: CGFloat, downward: Bool) {
        guard !rows.isEmpty else { return }
        let metrics = metrics
        let stemX = (node.minX + metrics.stemX).rounded()
        let rowRect = { (index: Int) -> NSRect in
            let y = downward ? node.maxY + CGFloat(index) * metrics.rowHeight : node.minY - CGFloat(index + 1) * metrics.rowHeight
            return NSRect(x: stemX + metrics.branchIndent, y: y, width: width - metrics.stemX - metrics.branchIndent, height: metrics.rowHeight)
        }
        if theme.isRounded, !theme.straightBranches {
            drawCurves(rows, stemX: stemX, stemY: downward ? node.maxY - 2 : node.minY + 2, rowRect: rowRect)
        } else {
            drawStraightLines(rows, stemX: stemX, node: node, downward: downward, rowRect: rowRect)
        }
        for (index, row) in rows.enumerated() {
            drawRow(row, in: rowRect(index))
        }
    }

    /// glass: 幹の下(上)の 1 点から，候補ごとに曲線を出す．選んでいる枝は最後にアクセント色で重ねる
    private func drawCurves(_ rows: [Row], stemX: CGFloat, stemY: CGFloat, rowRect: (Int) -> NSRect) {
        let start = NSPoint(x: stemX, y: stemY)
        let curves = rows.indices.map { index in
            let rect = rowRect(index)
            return GlassDrawing.branchCurve(from: start, to: NSPoint(x: rect.minX - 3, y: rect.midY))
        }
        for (index, curve) in curves.enumerated() where !rows[index].isSelected {
            theme.line.withAlphaComponent(theme.line.alphaComponent * rows[index].opacity).setStroke()
            curve.lineWidth = Glass.lineWidth
            curve.stroke()
        }
        for (index, curve) in curves.enumerated() where rows[index].isSelected {
            theme.selection.setStroke()
            curve.lineWidth = Glass.lineWidthSelected
            curve.stroke()
        }
    }

    /// platinum と desk: 縦の線を下ろし，候補ごとに横の線を出す
    private func drawStraightLines(_ rows: [Row], stemX: CGFloat, node: NSRect, downward: Bool, rowRect: (Int) -> NSRect) {
        let last = rowRect(rows.count - 1)
        let stemTop = downward ? node.maxY : last.midY
        let stemBottom = downward ? last.midY : node.minY
        theme.line.setFill()
        NSRect(x: stemX, y: stemTop, width: Branch.lineWidth, height: stemBottom - stemTop).fill()
        for (index, row) in rows.enumerated() {
            let rect = rowRect(index)
            let tickWidth = row.isSelected ? Branch.lineWidthSelected : Branch.lineWidth
            (row.isSelected ? theme.selection : theme.line).setFill()
            NSRect(x: stemX, y: (rect.midY - tickWidth / 2).rounded(), width: rect.minX - stemX - Size.frameWidth, height: tickWidth).fill()
        }
    }

    private func drawRow(_ row: Row, in rect: NSRect) {
        let textColor = (row.isSelected ? theme.selectionText : theme.text).withAlphaComponent(row.isSelected ? 1 : row.opacity)
        defer {
            if let note = row.note {
                NoteDrawing.drawTag(note, maxX: rect.maxX - Size.paddingX / 2, midY: rect.midY, theme: theme, selected: row.isSelected)
            }
        }
        if theme.isRounded {
            if row.isSelected { GlassDrawing.fillCapsule(rect.insetBy(dx: 0, dy: 2), color: theme.selection) }
            let badgeCenter = NSPoint(x: rect.minX + Size.paddingX / 2 + Glass.badgeSize / 2, y: rect.midY)
            GlassDrawing.drawBadge(row.badge, center: badgeCenter, theme: theme, selected: row.isSelected, opacity: row.opacity)
            drawText(row.text, attributes: [.font: candidateFont, .foregroundColor: textColor], x: rect.minX + Size.paddingX / 2 + metrics.lead, in: rect)
            return
        }
        if row.isSelected {
            theme.selection.setFill()
            rect.fill()
        }
        let badgeColor = (row.isSelected ? theme.selectionText : theme.textMuted).withAlphaComponent(row.isSelected ? 1 : row.opacity)
        GlassDrawing.drawLabel(row.badge, color: badgeColor, in: NSRect(x: rect.minX + Size.paddingX / 2, y: rect.minY, width: metrics.lead - Size.paddingX / 2, height: rect.height), theme: theme)
        drawText(row.text, attributes: [.font: candidateFont, .foregroundColor: textColor], x: rect.minX + Size.paddingX / 2 + metrics.lead, in: rect)
    }

    /// 注目していない確信の低い文節の下に，次の候補を 1 つだけ薄く添える
    private func drawPreview(_ text: String, under node: NSRect, maxX: CGFloat) {
        let metrics = metrics
        let stemX = (node.minX + metrics.stemX).rounded()
        let row = NSRect(x: stemX, y: node.maxY, width: node.width, height: metrics.rowHeight)
        let color = theme.textMuted.withAlphaComponent(restOpacity)
        let textX: CGFloat
        if theme.isRounded {
            let end = NSPoint(x: stemX + metrics.branchIndent / 2, y: row.midY)
            let curve = GlassDrawing.branchCurve(from: NSPoint(x: stemX, y: node.maxY - 2), to: end)
            theme.line.withAlphaComponent(theme.line.alphaComponent * restOpacity).setStroke()
            curve.lineWidth = Glass.lineWidth
            curve.stroke()
            textX = end.x + Size.paddingX / 2
        } else {
            color.setFill()
            NSRect(x: stemX, y: node.maxY, width: Branch.lineWidth, height: row.height / 2).fill()
            NSRect(x: stemX, y: row.midY.rounded(), width: metrics.branchIndent / 2, height: Branch.lineWidth).fill()
            textX = stemX + metrics.branchIndent / 2 + Size.paddingX / 2
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: candidateFont, .foregroundColor: color]
        drawText(Self.truncated(text, attributes: attributes, width: maxX - textX), attributes: attributes, x: textX, in: row)
    }

    /// 幅に収まるよう末尾を「…」で省く
    private static func truncated(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> String {
        guard text.size(withAttributes: attributes).width > width else { return text }
        var characters = Array(text)
        while !characters.isEmpty, (String(characters) + "…").size(withAttributes: attributes).width > width {
            characters.removeLast()
        }
        return characters.isEmpty ? "" : String(characters) + "…"
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
        let association = panel.associationHint.map { textWidth($0, font: labelFont) + Size.paddingX } ?? 0
        return (showsHints ? GlassDrawing.hintsWidth(hints, theme: theme) : 0) + source + association
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
        var hintsEnd = footer.minX
        if showsHints {
            GlassDrawing.drawHints(hints, x: footer.minX, midY: footer.midY, theme: theme)
            hintsEnd += GlassDrawing.hintsWidth(hints, theme: theme) + Size.paddingX
        }
        if let hint = panel.associationHint {
            // 選んでいる候補に連想があることを，キーの案内のあとに小さく出す(R-18)
            drawText(hint, attributes: muted, x: hintsEnd, in: footer)
        }
        let position = showsPosition(panel) ? position(of: panel) : ""
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
        let size = text.size(withAttributes: attributes)
        let y = rect.minY + ((rect.height - size.height) / 2).rounded()
        text.draw(at: NSPoint(x: x.rounded(), y: y), withAttributes: attributes)
    }
}
