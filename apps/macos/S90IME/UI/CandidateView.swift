import AppKit
import S90Application

/// 候補ウィンドウの中身を描く．上から，種類の行・候補・足元の 3 つの区画．
final class CandidateView: NSView {
    private typealias Size = DesignTokens.Size.Candidate

    var panel: CandidatePanel? { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }
    var fontSize: CGFloat = Size.fontSize { didSet { needsDisplay = true } }
    /// 第 1 候補と選んでいる候補以外の濃さ．出した直後は薄くし，すぐに濃くする(ephemeral adaptation)．
    /// 位置は動かさない．reports/IME候補提示の木構造と認知科学.md の提案による
    var restOpacity: CGFloat = 1 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private var candidateFont: NSFont { ResolvedTheme.candidateFont(size: fontSize) }
    private var labelFont: NSFont { ResolvedTheme.labelFont(size: Size.labelFontSize) }
    private var rowHeight: CGFloat { (Size.rowHeight * fontSize / Size.fontSize).rounded() }
    private var labelRowHeight: CGFloat { (labelFont.ascender - labelFont.descender).rounded(.up) + Size.sectionPaddingY * 2 }
    /// 外枠と立体の縁の太さ
    private var inset: CGFloat { Size.frameWidth + (theme.hasBevel ? Size.bevelWidth : 0) }
    private var dropShadowOffset: CGFloat { theme.hasDropShadow ? Size.shadowOffset : 0 }

    // MARK: - 大きさ

    func fittingSize(for panel: CandidatePanel) -> NSSize {
        let textAttributes: [NSAttributedString.Key: Any] = [.font: candidateFont]
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont]
        let entryWidth = panel.entries.map { entry in
            let annotation = entry.annotation.map { $0.size(withAttributes: labelAttributes).width + Size.paddingX } ?? 0
            return entry.text.size(withAttributes: textAttributes).width + annotation
        }.max() ?? 0
        let variantsWidth = panel.variants.reduce(CGFloat(0)) { width, variant in
            width + variant.label.size(withAttributes: labelAttributes).width + Size.variantPaddingX * 2
        }
        let footerWidth = footerText(for: panel).left.size(withAttributes: labelAttributes).width
            + footerText(for: panel).right.size(withAttributes: labelAttributes).width + Size.paddingX * 3
        let contentWidth = max(Size.minWidth, Size.indexWidth + entryWidth + Size.paddingX * 2, variantsWidth + Size.paddingX, footerWidth)
        var height = CGFloat(panel.entries.count) * rowHeight + labelRowHeight + Size.frameWidth
        if !panel.variants.isEmpty { height += labelRowHeight + Size.frameWidth }
        return NSSize(width: (contentWidth + inset * 2 + dropShadowOffset).rounded(.up), height: (height + inset * 2 + dropShadowOffset).rounded(.up))
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        guard let panel else { return }
        let body = NSRect(x: 0, y: 0, width: bounds.width - dropShadowOffset, height: bounds.height - dropShadowOffset)
        // isFlipped なので，影は右と下(y が大きい側)に出す
        if theme.hasDropShadow {
            theme.frame.setFill()
            body.offsetBy(dx: dropShadowOffset, dy: dropShadowOffset).fill()
        }
        BevelDrawing.drawPanel(in: body, theme: theme)
        let content = body.insetBy(dx: inset, dy: inset)
        var y = content.minY
        if !panel.variants.isEmpty {
            drawVariants(panel, in: NSRect(x: content.minX, y: y, width: content.width, height: labelRowHeight))
            y += labelRowHeight
            BevelDrawing.drawSeparator(y: y, from: content.minX, to: content.maxX, theme: theme)
            y += Size.frameWidth
        }
        for (index, entry) in panel.entries.enumerated() {
            drawEntry(entry, index: index, panel: panel, in: NSRect(x: content.minX, y: y, width: content.width, height: rowHeight))
            y += rowHeight
        }
        BevelDrawing.drawSeparator(y: y, from: content.minX, to: content.maxX, theme: theme)
        y += Size.frameWidth
        drawFooter(panel, in: NSRect(x: content.minX, y: y, width: content.width, height: labelRowHeight))
    }

    private func drawVariants(_ panel: CandidatePanel, in rect: NSRect) {
        var x = rect.minX + Size.paddingX / 2
        for (index, variant) in panel.variants.enumerated() {
            let isSelected = panel.focus == .variants && panel.selectedVariant == index
            // ふだんは弱い文字で見せ，上キーで移ったときだけ強調する(R-03)
            let color: NSColor = isSelected ? theme.selectionText : (variant.isAvailable ? theme.textMuted : theme.textMuted.withAlphaComponent(0.4))
            let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: color]
            let width = variant.label.size(withAttributes: attributes).width + Size.variantPaddingX * 2
            let cell = NSRect(x: x, y: rect.minY + 1, width: width, height: rect.height - 2)
            if isSelected {
                theme.selection.setFill()
                cell.fill()
            }
            drawText(variant.label, attributes: attributes, x: cell.minX + Size.variantPaddingX, in: cell)
            x += width
        }
    }

    private func drawEntry(_ entry: CandidatePanel.Entry, index: Int, panel: CandidatePanel, in rect: NSRect) {
        let isSelected = panel.focus == .candidate && panel.selectedEntry == index
        if isSelected {
            theme.selection.setFill()
            rect.fill()
        }
        let opacity: CGFloat = (isSelected || index == 0) ? 1 : restOpacity
        let textColor = (isSelected ? theme.selectionText : theme.text).withAlphaComponent(opacity)
        let mutedColor = (isSelected ? theme.selectionText : theme.textMuted).withAlphaComponent(opacity)
        let number = "\(index + 1)"
        drawText(number, attributes: [.font: labelFont, .foregroundColor: mutedColor], x: rect.minX + Size.paddingX, in: rect)
        drawText(entry.text, attributes: [.font: candidateFont, .foregroundColor: textColor], x: rect.minX + Size.paddingX + Size.indexWidth, in: rect)
        if let annotation = entry.annotation {
            let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: mutedColor]
            let width = annotation.size(withAttributes: attributes).width
            drawText(annotation, attributes: attributes, x: rect.maxX - Size.paddingX - width, in: rect)
        }
    }

    private func drawFooter(_ panel: CandidatePanel, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.textMuted]
        let text = footerText(for: panel)
        drawText(text.left, attributes: attributes, x: rect.minX + Size.paddingX, in: rect)
        let width = text.right.size(withAttributes: attributes).width
        drawText(text.right, attributes: attributes, x: rect.maxX - Size.paddingX - width, in: rect)
    }

    private func footerText(for panel: CandidatePanel) -> (left: String, right: String) {
        let left = panel.focus == .variants ? UIStrings.Candidate.variantsPosition(panel.selectedVariant.map { $0 + 1 } ?? 1, panel.variants.count)
            : "\(panel.position) / \(panel.total)"
        let right = panel.note ?? (panel.focus == .variants ? UIStrings.Candidate.variantsHint : UIStrings.Candidate.candidatesHint)
        return (left, right)
    }

    /// 行の高さの中で縦に中央にそろえて描く．座標は整数に丸め，文字の輪郭をぼかさない
    private func drawText(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, in rect: NSRect) {
        let size = text.size(withAttributes: attributes)
        let y = rect.minY + ((rect.height - size.height) / 2).rounded()
        text.draw(at: NSPoint(x: x.rounded(), y: y), withAttributes: attributes)
    }
}

extension ResolvedTheme {
    /// ビューを作った直後に使う仮の値．表示する前に必ず resolve した値で置き換える
    static var resolveStatic: ResolvedTheme {
        ResolvedTheme(
            kind: .platinum,
            surface: DesignTokens.Palette.platinum.surface.color,
            bevelLight: DesignTokens.Palette.platinum.bevelLight.color,
            bevelShadow: DesignTokens.Palette.platinum.bevelShadow.color,
            frame: DesignTokens.Palette.platinum.frame.color,
            text: DesignTokens.Palette.platinum.text.color,
            textMuted: DesignTokens.Palette.platinum.textMuted.color,
            selection: DesignTokens.Palette.platinum.selection.color,
            selectionText: DesignTokens.Palette.platinum.selectionText.color,
            correction: DesignTokens.Palette.platinum.correction.color
        )
    }
}
