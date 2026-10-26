import AppKit
import S90Application

/// 分岐図を描く(ADR 0007)．文を 1 本の幹として文節を横に並べ，注目している文節から枝を伸ばす．
///
/// - 下の枝: 変換の候補．↓ と Space で下へたどる．番号キーで選べる
/// - 上の枝: 文字種(ひらがな・カタカナ・半角カタカナ)．↑ で上へたどる
/// - 確信の低い文節は幹の文字に点線を引き，注目していなければ次の候補を 1 つだけ薄く添える
/// - 選び直した文節は実線を引く．変換器が書き換えない文節であることを見せる
///
/// 幹の文節の位置は幹の文字の幅だけで決め，注目を移しても動かさない(空間の安定性)．
/// glass は曲線の枝と角丸の選択，platinum と desk は 1 ドットの直線の枝で描く
final class BranchView: NSView {
    private typealias Size = DesignTokens.Size.Candidate
    private typealias Branch = DesignTokens.Size.Branch
    private typealias Glass = DesignTokens.Size.Glass

    var panel: LatticePanel? { didSet { needsDisplay = true } }
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
        if theme.isGlass {
            return Metrics(inset: Glass.padding, rowHeight: (Glass.rowHeight * scale).rounded(), trunkGap: Glass.trunkGap,
                           branchIndent: Glass.branchIndent, stemX: Glass.branchStemX, lead: Glass.badgeSize + Size.paddingX,
                           footerHeight: Glass.footerHeight)
        }
        let labelHeight = (labelFont.ascender - labelFont.descender).rounded(.up) + Size.sectionPaddingY * 2
        return Metrics(inset: Size.frameWidth + Size.bevelWidth + Size.paddingX, rowHeight: (Size.rowHeight * scale).rounded(),
                       trunkGap: Branch.trunkGap, branchIndent: Branch.branchIndent, stemX: Branch.branchStemX, lead: Size.indexWidth,
                       footerHeight: labelHeight)
    }

    private var candidateFont: NSFont { theme.candidateFont(size: fontSize) }
    private var trunkFont: NSFont { theme.trunkFont(size: fontSize) }
    private var labelFont: NSFont { theme.labelFont(size: theme.isGlass ? Glass.labelFontSize : Size.labelFontSize) }
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

    private func layout(for panel: LatticePanel) -> Layout {
        let metrics = metrics
        var x = metrics.inset
        var trunkX: [CGFloat] = []
        var trunkWidths: [CGFloat] = []
        for column in panel.columns {
            let width = textWidth(column.text, font: trunkFont) + Size.paddingX * 2
            trunkX.append(x)
            trunkWidths.append(width)
            x += width + metrics.trunkGap
        }
        let trunkRight = x - metrics.trunkGap
        let focused = panel.columns.firstIndex(where: \.isFocused)
        let column = focused.map { panel.columns[$0] }
        let labels = (column?.alternatives ?? []) + (column?.variants ?? [])
        let branchWidth = metrics.stemX + metrics.branchIndent + metrics.lead
            + (labels.map { textWidth($0, font: candidateFont) }.max() ?? 0) + Size.paddingX * 2
        let branchRight = (focused.map { trunkX[$0] } ?? metrics.inset) + branchWidth
        let previewRows = panel.columns.contains { $0.preview != nil } ? 1 : 0
        let upperRows = column?.variants.count ?? 0
        let lowerRows = max(column?.alternatives.count ?? 0, previewRows)
        let footer = footerWidth(panel) + textWidth(position(of: panel), font: labelFont) + Size.paddingX * 3
        let width = max(Size.minWidth, trunkRight + metrics.inset, branchRight + metrics.inset, footer + metrics.inset * 2)
        let trunkY = metrics.inset + CGFloat(upperRows) * metrics.rowHeight
        let height = trunkY + metrics.rowHeight * CGFloat(1 + lowerRows) + Size.frameWidth + metrics.footerHeight
            + (theme.isGlass ? 0 : metrics.inset)
        return Layout(trunkX: trunkX, trunkWidths: trunkWidths, lowerRows: lowerRows, trunkY: trunkY,
                      branchWidth: branchWidth, size: NSSize(width: width.rounded(.up), height: height.rounded(.up)))
    }

    func fittingSize(for panel: LatticePanel) -> NSSize {
        let size = layout(for: panel).size
        return NSSize(width: size.width + dropShadowOffset, height: size.height + dropShadowOffset)
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        guard let panel else { return }
        let layout = layout(for: panel)
        let metrics = metrics
        let body = NSRect(origin: .zero, size: layout.size)
        if theme.isGlass {
            GlassDrawing.drawFrame(in: body, theme: theme, fillsSurface: fillsSurface)
        } else {
            BevelDrawing.drawDropShadow(for: body, theme: theme)
            BevelDrawing.drawPanel(in: body, theme: theme)
        }
        let focusedIndex = panel.columns.firstIndex(where: \.isFocused)
        // 注目している文節の枝が重なる範囲には，ほかの文節の添え書きを描かない
        let branchRange = focusedIndex.map { layout.trunkX[$0]...(layout.trunkX[$0] + layout.branchWidth) }
        for (index, column) in panel.columns.enumerated() {
            let node = NSRect(x: layout.trunkX[index], y: layout.trunkY, width: layout.trunkWidths[index], height: metrics.rowHeight)
            drawTrunkNode(column, in: node)
            if !theme.isGlass, index < panel.columns.count - 1 {
                // glass は文節の間を空けるだけにし，文として読めるようにする
                theme.line.setFill()
                NSRect(x: node.maxX, y: node.midY.rounded(), width: layout.trunkX[index + 1] - node.maxX, height: Branch.lineWidth).fill()
            }
            if column.isFocused {
                drawBranches(lowerRows(column), from: node, width: layout.branchWidth, downward: true)
                drawBranches(upperRows(column), from: node, width: layout.branchWidth, downward: false)
            } else if let preview = column.preview, !(branchRange?.overlaps(node.minX...node.maxX) ?? false) {
                drawPreview(preview, under: node)
            }
        }
        let footerY = layout.trunkY + metrics.rowHeight * CGFloat(1 + layout.lowerRows)
        drawFooter(panel, y: footerY, width: body.width)
    }

    // MARK: - 幹

    private func drawTrunkNode(_ column: LatticePanel.Column, in node: NSRect) {
        let color: NSColor
        if theme.isGlass {
            if column.isFocused { GlassDrawing.fillCapsule(node.insetBy(dx: 0, dy: 2), color: theme.focusTint) }
            color = theme.text
        } else {
            if column.isFocused {
                theme.selection.setFill()
                node.fill()
            }
            color = column.isFocused ? theme.selectionText : theme.text
        }
        drawText(column.text, attributes: [.font: trunkFont, .foregroundColor: color], x: node.minX + Size.paddingX, in: node)
        // 下線: 選び直した文節は実線，確信の低い文節は点線．線の種類でも区別し，色だけに頼らない
        let offset = theme.isGlass ? Glass.underlineOffset : Branch.underlineOffset
        let y = node.maxY - offset
        let from = node.minX + Size.paddingX
        let to = node.maxX - Size.paddingX
        if column.isDecided {
            drawUnderline(from: from, to: to, y: y, color: theme.isGlass ? theme.textMuted : color, dotted: false)
        } else if column.isUncertain {
            let dotColor = !theme.isGlass && column.isFocused ? theme.selectionText : theme.correction
            drawUnderline(from: from, to: to, y: y, color: dotColor, dotted: true)
        }
    }

    // MARK: - 枝

    private struct Row {
        var text: String
        var badge: String
        var isSelected: Bool
        var opacity: CGFloat
    }

    /// 下の枝(変換の候補)．第 1 候補はすぐに濃く出す
    private func lowerRows(_ column: LatticePanel.Column) -> [Row] {
        column.alternatives.enumerated().map { index, text in
            Row(text: text, badge: "\(index + 1)", isSelected: index == column.selectedAlternative, opacity: index == 0 ? 1 : restOpacity)
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
        if theme.isGlass {
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
        if theme.isGlass {
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
        drawText(row.badge, attributes: [.font: labelFont, .foregroundColor: badgeColor], x: rect.minX + Size.paddingX / 2, in: rect)
        drawText(row.text, attributes: [.font: candidateFont, .foregroundColor: textColor], x: rect.minX + Size.paddingX / 2 + metrics.lead, in: rect)
    }

    /// 注目していない確信の低い文節の下に，次の候補を 1 つだけ薄く添える
    private func drawPreview(_ text: String, under node: NSRect) {
        let metrics = metrics
        let stemX = (node.minX + metrics.stemX).rounded()
        let row = NSRect(x: stemX, y: node.maxY, width: node.width, height: metrics.rowHeight)
        let color = theme.textMuted.withAlphaComponent(restOpacity)
        let textX: CGFloat
        if theme.isGlass {
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
        drawText(text, attributes: [.font: candidateFont, .foregroundColor: color], x: textX, in: row)
    }

    // MARK: - 足元

    private func position(of panel: LatticePanel) -> String {
        let count = panel.columns.first(where: \.isFocused)?.alternatives.count ?? 0
        return UIStrings.Branch.position(first: panel.position, last: panel.position + max(count, 1) - 1, total: panel.total)
    }

    private func footerWidth(_ panel: LatticePanel) -> CGFloat {
        if let note = panel.note { return textWidth(note, font: labelFont) }
        return theme.isGlass ? GlassDrawing.hintsWidth(UIStrings.Branch.hints, theme: theme)
            : textWidth(KeyHint.text(UIStrings.Branch.hints), font: labelFont)
    }

    private func drawFooter(_ panel: LatticePanel, y: CGFloat, width: CGFloat) {
        let metrics = metrics
        let lineInset = theme.isGlass ? metrics.inset : metrics.inset - Size.paddingX
        if theme.isGlass {
            theme.line.setFill()
            NSRect(x: lineInset, y: y, width: width - lineInset * 2, height: Size.frameWidth).fill()
        } else {
            BevelDrawing.drawSeparator(y: y, from: lineInset, to: width - lineInset, theme: theme)
        }
        let footer = NSRect(x: metrics.inset, y: y + Size.frameWidth, width: width - metrics.inset * 2, height: metrics.footerHeight)
        let muted: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.textMuted]
        if let note = panel.note {
            // 打ち間違いを直したことなど，IME が変えたことを知らせる
            drawText(note, attributes: [.font: labelFont, .foregroundColor: theme.correction], x: footer.minX, in: footer)
        } else if theme.isGlass {
            GlassDrawing.drawHints(UIStrings.Branch.hints, x: footer.minX, midY: footer.midY, theme: theme)
        } else {
            drawText(KeyHint.text(UIStrings.Branch.hints), attributes: muted, x: footer.minX, in: footer)
        }
        let position = position(of: panel)
        drawText(position, attributes: muted, x: footer.maxX - textWidth(position, font: labelFont), in: footer)
    }

    // MARK: - 部品

    private func drawUnderline(from minX: CGFloat, to maxX: CGFloat, y: CGFloat, color: NSColor, dotted: Bool) {
        if theme.isGlass {
            // glass は丸い点と丸い端の線
            let path = NSBezierPath()
            path.move(to: NSPoint(x: minX, y: y))
            path.line(to: NSPoint(x: maxX, y: y))
            path.lineWidth = Glass.lineWidthSelected
            path.lineCapStyle = .round
            if dotted { path.setLineDash([0, Glass.lineWidthSelected * 2.5], count: 2, phase: 0) }
            color.setStroke()
            path.stroke()
            return
        }
        color.setFill()
        let rect = NSRect(x: minX, y: y, width: maxX - minX, height: Branch.lineWidth)
        guard dotted else {
            rect.fill()
            return
        }
        let step = Branch.lineWidthSelected * 2
        var x = rect.minX
        while x < rect.maxX {
            NSRect(x: x, y: rect.minY, width: min(Branch.lineWidthSelected, rect.maxX - x), height: rect.height).fill()
            x += step
        }
    }

    private func drawText(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, in rect: NSRect) {
        let size = text.size(withAttributes: attributes)
        let y = rect.minY + ((rect.height - size.height) / 2).rounded()
        text.draw(at: NSPoint(x: x.rounded(), y: y), withAttributes: attributes)
    }
}
