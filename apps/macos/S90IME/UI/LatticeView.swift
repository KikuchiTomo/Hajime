import AppKit
import S90Application

/// 文節格子を描く．1 段目に文節ごとの今の候補を横に並べ，その下に文節ごとの候補の列を置く．
///
/// 注目している文節だけ番号を付けて選べるようにし，ほかの列は確信度が低いときだけ薄く見せる．
/// 候補の位置は列の中で固定し，注目を移しても並びは変えない(空間の安定性．docs/dev/research/candidate-presentation.md)．
final class LatticeView: NSView {
    private typealias Size = DesignTokens.Size.Candidate

    var panel: LatticePanel? { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }
    var fontSize: CGFloat = Size.fontSize { didSet { needsDisplay = true } }
    var restOpacity: CGFloat = 1 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private var candidateFont: NSFont { ResolvedTheme.candidateFont(size: fontSize) }
    private var labelFont: NSFont { ResolvedTheme.labelFont(size: Size.labelFontSize) }
    private var rowHeight: CGFloat { (Size.rowHeight * fontSize / Size.fontSize).rounded() }
    private var labelRowHeight: CGFloat { (labelFont.ascender - labelFont.descender).rounded(.up) + Size.sectionPaddingY * 2 }
    private var inset: CGFloat { Size.frameWidth + (theme.hasBevel ? Size.bevelWidth : 0) }
    private var dropShadowOffset: CGFloat { theme.hasDropShadow ? Size.shadowOffset : 0 }

    private func columnWidths(for panel: LatticePanel) -> [CGFloat] {
        let attributes: [NSAttributedString.Key: Any] = [.font: candidateFont]
        return panel.columns.map { column in
            let widest = ([column.text] + column.alternatives).map { $0.size(withAttributes: attributes).width }.max() ?? 0
            return (widest + Size.indexWidth + Size.paddingX * 2).rounded(.up)
        }
    }

    private func visibleRows(for panel: LatticePanel) -> Int {
        panel.columns.filter(\.showsAlternatives).map(\.alternatives.count).max() ?? 0
    }

    func fittingSize(for panel: LatticePanel) -> NSSize {
        let columns = columnWidths(for: panel).reduce(0, +) + CGFloat(max(panel.columns.count - 1, 0)) * Size.frameWidth
        let footer = UIStrings.Lattice.hint.size(withAttributes: [.font: labelFont]).width + Size.paddingX * 2
        let width = max(Size.minWidth, columns, footer)
        let height = rowHeight + Size.frameWidth + CGFloat(visibleRows(for: panel)) * rowHeight + Size.frameWidth + labelRowHeight
        return NSSize(width: (width + inset * 2 + dropShadowOffset).rounded(.up), height: (height + inset * 2 + dropShadowOffset).rounded(.up))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let panel else { return }
        let body = NSRect(x: 0, y: 0, width: bounds.width - dropShadowOffset, height: bounds.height - dropShadowOffset)
        BevelDrawing.drawDropShadow(for: body, theme: theme)
        BevelDrawing.drawPanel(in: body, theme: theme)
        let content = body.insetBy(dx: inset, dy: inset)
        let widths = columnWidths(for: panel)
        let rows = visibleRows(for: panel)
        let gridBottom = content.minY + rowHeight + Size.frameWidth + CGFloat(rows) * rowHeight
        var x = content.minX
        for (index, column) in panel.columns.enumerated() {
            let width = widths[index]
            drawColumn(column, in: NSRect(x: x, y: content.minY, width: width, height: gridBottom - content.minY))
            x += width
            if index < panel.columns.count - 1 {
                // 文節の境目の縦線
                theme.separator.setFill()
                NSRect(x: x, y: content.minY, width: Size.frameWidth, height: gridBottom - content.minY).fill()
                x += Size.frameWidth
            }
        }
        BevelDrawing.drawSeparator(y: content.minY + rowHeight, from: content.minX, to: content.maxX, theme: theme)
        BevelDrawing.drawSeparator(y: gridBottom, from: content.minX, to: content.maxX, theme: theme)
        let footer = NSRect(x: content.minX, y: gridBottom + Size.frameWidth, width: content.width, height: labelRowHeight)
        drawText(UIStrings.Lattice.hint, attributes: [.font: labelFont, .foregroundColor: theme.textMuted], x: footer.minX + Size.paddingX, in: footer)
    }

    private func drawColumn(_ column: LatticePanel.Column, in rect: NSRect) {
        // 1 段目: 今の候補．注目している文節は選択の色で塗る
        let head = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rowHeight)
        if column.isFocused {
            theme.selection.setFill()
            head.fill()
        }
        let headColor = column.isFocused ? theme.selectionText : theme.text
        drawText(column.text, attributes: [.font: candidateFont, .foregroundColor: headColor], x: head.minX + Size.paddingX, in: head)
        guard column.showsAlternatives else { return }
        var y = head.maxY + Size.frameWidth
        for (index, alternative) in column.alternatives.enumerated() {
            let row = NSRect(x: rect.minX, y: y, width: rect.width, height: rowHeight)
            let isSelected = column.isFocused && index == column.selectedAlternative
            let opacity: CGFloat = (isSelected || index == 0) ? 1 : restOpacity
            if isSelected {
                theme.selection.withAlphaComponent(0.25).setFill()
                row.fill()
            }
            // 注目していない列は薄く見せ，番号を付けない(選べるのは注目している列だけ)
            let textColor = (column.isFocused ? theme.text : theme.textMuted).withAlphaComponent(opacity)
            if column.isFocused {
                drawText("\(index + 1)", attributes: [.font: labelFont, .foregroundColor: theme.textMuted.withAlphaComponent(opacity)], x: row.minX + Size.paddingX, in: row)
            }
            drawText(alternative, attributes: [.font: candidateFont, .foregroundColor: textColor], x: row.minX + Size.paddingX + Size.indexWidth, in: row)
            y += rowHeight
        }
    }

    private func drawText(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, in rect: NSRect) {
        let size = text.size(withAttributes: attributes)
        let y = rect.minY + ((rect.height - size.height) / 2).rounded()
        text.draw(at: NSPoint(x: x.rounded(), y: y), withAttributes: attributes)
    }
}
