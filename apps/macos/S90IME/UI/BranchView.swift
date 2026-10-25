import AppKit
import S90Application

/// 分岐図を描く(ADR 0007)．文を 1 本の幹として文節を横に並べ，注目している文節から枝を伸ばす．
///
/// - 下の枝: 変換の候補．↓ と Space で下へたどる．番号キーで選べる
/// - 上の枝: 字種(そのまま・カタカナ・半角カタカナ)．↑ で上へたどる
/// - 迷う文節は幹の文字に点線を引き，注目していなければ次の候補を 1 つだけ薄く添える
/// - 選び直した文節は実線を引く．変換器が書き換えない文節であることを見せる
///
/// 幹の文節の位置は幹の文字の幅だけで決め，注目を移しても動かさない(空間の安定性)．
final class BranchView: NSView {
    private typealias Size = DesignTokens.Size.Candidate
    private typealias Branch = DesignTokens.Size.Branch

    var panel: LatticePanel? { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }
    var fontSize: CGFloat = Size.fontSize { didSet { needsDisplay = true } }
    var restOpacity: CGFloat = 1 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private var candidateFont: NSFont { ResolvedTheme.candidateFont(size: fontSize) }
    private var labelFont: NSFont { ResolvedTheme.labelFont(size: Size.labelFontSize) }
    private var rowHeight: CGFloat { (Size.rowHeight * fontSize / Size.fontSize).rounded() }
    private var labelRowHeight: CGFloat { (labelFont.ascender - labelFont.descender).rounded(.up) + Size.sectionPaddingY * 2 }
    private var inset: CGFloat { Size.frameWidth + (theme.hasBevel ? Size.bevelWidth : 0) + Size.paddingX }
    private var dropShadowOffset: CGFloat { theme.hasDropShadow ? Size.shadowOffset : 0 }

    /// 幹・枝・説明の行の位置．描くときと大きさを求めるときで同じものを使う
    private struct Layout {
        var trunkX: [CGFloat]
        var trunkWidths: [CGFloat]
        var upperRows: Int
        var lowerRows: Int
        var trunkY: CGFloat
        var branchWidth: CGFloat
        var size: NSSize
    }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        text.size(withAttributes: [.font: font]).width.rounded(.up)
    }

    private func layout(for panel: LatticePanel) -> Layout {
        var x = inset
        var trunkX: [CGFloat] = []
        var trunkWidths: [CGFloat] = []
        for column in panel.columns {
            let width = textWidth(column.text, font: candidateFont) + Size.paddingX * 2
            trunkX.append(x)
            trunkWidths.append(width)
            x += width + Branch.trunkGap
        }
        let trunkRight = x - Branch.trunkGap
        let focused = panel.columns.firstIndex(where: \.isFocused)
        let column = focused.map { panel.columns[$0] }
        let labels = (column?.alternatives ?? []) + (column?.variants ?? [])
        let branchWidth = Branch.branchIndent + Size.indexWidth + (labels.map { textWidth($0, font: candidateFont) }.max() ?? 0) + Size.paddingX * 2
        let branchRight = (focused.map { trunkX[$0] } ?? inset) + branchWidth
        let previewRows = panel.columns.contains { $0.preview != nil } ? 1 : 0
        let upperRows = column?.variants.count ?? 0
        let lowerRows = max(column?.alternatives.count ?? 0, previewRows)
        let footer = textWidth(panel.note ?? UIStrings.Branch.hint, font: labelFont) + textWidth(UIStrings.Branch.position(panel.position, panel.total), font: labelFont) + Size.paddingX * 3
        let width = max(Size.minWidth, trunkRight + inset, branchRight + inset, footer + inset * 2)
        let trunkY = inset + CGFloat(upperRows) * rowHeight
        let height = trunkY + rowHeight + CGFloat(lowerRows) * rowHeight + Size.frameWidth + labelRowHeight + inset
        return Layout(trunkX: trunkX, trunkWidths: trunkWidths, upperRows: upperRows, lowerRows: lowerRows, trunkY: trunkY,
                      branchWidth: branchWidth, size: NSSize(width: width.rounded(.up), height: height.rounded(.up)))
    }

    func fittingSize(for panel: LatticePanel) -> NSSize {
        let size = layout(for: panel).size
        return NSSize(width: size.width + dropShadowOffset, height: size.height + dropShadowOffset)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let panel else { return }
        let layout = layout(for: panel)
        let body = NSRect(origin: .zero, size: layout.size)
        BevelDrawing.drawDropShadow(for: body, theme: theme)
        BevelDrawing.drawPanel(in: body, theme: theme)
        let focusedIndex = panel.columns.firstIndex(where: \.isFocused)
        // 注目している文節の枝が重なる範囲には，ほかの文節の添え書きを描かない
        let branchRange = focusedIndex.map { layout.trunkX[$0]...(layout.trunkX[$0] + layout.branchWidth) }
        for (index, column) in panel.columns.enumerated() {
            let node = NSRect(x: layout.trunkX[index], y: layout.trunkY, width: layout.trunkWidths[index], height: rowHeight)
            drawTrunkNode(column, in: node)
            if index < panel.columns.count - 1 {
                drawTrunkLink(from: node.maxX, to: layout.trunkX[index + 1], y: node.midY)
            }
            if column.isFocused {
                drawLowerBranches(column, from: node, width: layout.branchWidth)
                drawUpperBranches(column, from: node, width: layout.branchWidth)
            } else if let preview = column.preview, !(branchRange?.overlaps(node.minX...node.maxX) ?? false) {
                drawPreview(preview, under: node)
            }
        }
        let footerY = layout.trunkY + rowHeight + CGFloat(layout.lowerRows) * rowHeight
        BevelDrawing.drawSeparator(y: footerY, from: inset - Size.paddingX, to: body.maxX - inset + Size.paddingX, theme: theme)
        let footer = NSRect(x: inset, y: footerY + Size.frameWidth, width: body.width - inset * 2, height: labelRowHeight)
        let muted: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.textMuted]
        if let note = panel.note {
            // 打ち間違いを直したことなど，IME が変えたことを知らせる
            drawText(note, attributes: [.font: labelFont, .foregroundColor: theme.correction], x: footer.minX, in: footer)
        } else {
            drawText(UIStrings.Branch.hint, attributes: muted, x: footer.minX, in: footer)
        }
        let position = UIStrings.Branch.position(panel.position, panel.total)
        drawText(position, attributes: muted, x: footer.maxX - textWidth(position, font: labelFont), in: footer)
    }

    // MARK: - 幹

    private func drawTrunkNode(_ column: LatticePanel.Column, in node: NSRect) {
        if column.isFocused {
            theme.selection.setFill()
            node.fill()
        }
        let color = column.isFocused ? theme.selectionText : theme.text
        drawText(column.text, attributes: [.font: candidateFont, .foregroundColor: color], x: node.minX + Size.paddingX, in: node)
        // 下線: 選び直した文節は実線，迷う文節は点線．線の種類でも区別し，色だけに頼らない
        let underline = NSRect(x: node.minX + Size.paddingX, y: node.maxY - Branch.underlineOffset, width: node.width - Size.paddingX * 2, height: Branch.lineWidth)
        if column.isDecided {
            color.setFill()
            underline.fill()
        } else if column.isUncertain {
            drawDotted(underline, color: column.isFocused ? theme.selectionText : theme.correction)
        }
    }

    private func drawTrunkLink(from minX: CGFloat, to maxX: CGFloat, y: CGFloat) {
        theme.separator.setFill()
        NSRect(x: minX, y: y.rounded(), width: maxX - minX, height: Branch.lineWidth).fill()
    }

    // MARK: - 枝

    /// 下の枝(変換の候補)．幹の左寄りから縦の線を下ろし，候補ごとに横の線を出す
    private func drawLowerBranches(_ column: LatticePanel.Column, from node: NSRect, width: CGFloat) {
        let rows = column.alternatives.enumerated().map { index, text in
            (text: text, label: "\(index + 1)", isSelected: index == column.selectedAlternative, opacity: index == 0 ? 1 : restOpacity)
        }
        drawBranches(rows, from: node, width: width, downward: true)
    }

    /// 上の枝(字種)．幹に近いものから上へ積む
    private func drawUpperBranches(_ column: LatticePanel.Column, from node: NSRect, width: CGFloat) {
        let rows = column.variants.enumerated().map { index, text in
            (text: text, label: "↑", isSelected: index == column.selectedVariant, opacity: restOpacity)
        }
        drawBranches(rows, from: node, width: width, downward: false)
    }

    private func drawBranches(_ rows: [(text: String, label: String, isSelected: Bool, opacity: CGFloat)], from node: NSRect, width: CGFloat, downward: Bool) {
        guard !rows.isEmpty else { return }
        let stemX = (node.minX + Branch.branchStemX).rounded()
        let rowRect = { (index: Int) -> NSRect in
            let y = downward ? node.maxY + CGFloat(index) * self.rowHeight : node.minY - CGFloat(index + 1) * self.rowHeight
            return NSRect(x: stemX, y: y, width: width - Branch.branchStemX, height: self.rowHeight)
        }
        // 縦の線は，幹から最後の枝の中ほどまで
        let last = rowRect(rows.count - 1)
        let stemTop = downward ? node.maxY : last.midY
        let stemBottom = downward ? last.midY : node.minY
        theme.separator.setFill()
        NSRect(x: stemX, y: stemTop, width: Branch.lineWidth, height: stemBottom - stemTop).fill()
        for (index, row) in rows.enumerated() {
            let rect = rowRect(index)
            let tickWidth = row.isSelected ? Branch.lineWidthSelected : Branch.lineWidth
            (row.isSelected ? theme.selection : theme.separator).setFill()
            NSRect(x: stemX, y: (rect.midY - tickWidth / 2).rounded(), width: Branch.branchIndent - Size.frameWidth, height: tickWidth).fill()
            let label = NSRect(x: stemX + Branch.branchIndent, y: rect.minY, width: rect.maxX - stemX - Branch.branchIndent, height: rect.height)
            if row.isSelected {
                theme.selection.setFill()
                label.fill()
            }
            let textColor = (row.isSelected ? theme.selectionText : theme.text).withAlphaComponent(row.isSelected ? 1 : row.opacity)
            let labelColor = (row.isSelected ? theme.selectionText : theme.textMuted).withAlphaComponent(row.isSelected ? 1 : row.opacity)
            drawText(row.label, attributes: [.font: labelFont, .foregroundColor: labelColor], x: label.minX + Size.paddingX / 2, in: label)
            drawText(row.text, attributes: [.font: candidateFont, .foregroundColor: textColor], x: label.minX + Size.paddingX / 2 + Size.indexWidth, in: label)
        }
    }

    /// 注目していない迷う文節の下に，次の候補を 1 つだけ薄く添える
    private func drawPreview(_ text: String, under node: NSRect) {
        let stemX = (node.minX + Branch.branchStemX).rounded()
        let row = NSRect(x: stemX, y: node.maxY, width: node.width, height: rowHeight)
        let color = theme.textMuted.withAlphaComponent(restOpacity)
        color.setFill()
        NSRect(x: stemX, y: node.maxY, width: Branch.lineWidth, height: row.height / 2).fill()
        NSRect(x: stemX, y: row.midY.rounded(), width: Branch.branchIndent / 2, height: Branch.lineWidth).fill()
        drawText(text, attributes: [.font: candidateFont, .foregroundColor: color], x: stemX + Branch.branchIndent / 2 + Size.paddingX / 2, in: row)
    }

    // MARK: - 部品

    private func drawDotted(_ rect: NSRect, color: NSColor) {
        color.setFill()
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
