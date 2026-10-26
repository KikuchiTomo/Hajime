import AppKit
import S90Application

/// 候補ウィンドウの中身を描く．上から，文字種の行・候補・足元の 3 つの区画．
final class CandidateView: NSView {
    private typealias Size = DesignTokens.Size.Candidate
    private typealias Glass = DesignTokens.Size.Glass

    var panel: CandidatePanel? { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }
    var fontSize: CGFloat = Size.fontSize { didSet { needsDisplay = true } }
    /// 第 1 候補と選んでいる候補以外の濃さ．出した直後は薄くし，すぐに濃くする(ephemeral adaptation)．
    /// 位置は動かさない．docs/dev/research/candidate-presentation.md の提案による
    var restOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    /// glass の面を自分で塗るか．ぼかしの地(GlassBackdrop)の無いところ(画像への書き出し)で使う
    var fillsSurface = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private var candidateFont: NSFont { theme.candidateFont(size: fontSize) }
    private var labelFont: NSFont { theme.labelFont(size: theme.isGlass ? Glass.labelFontSize : Size.labelFontSize) }
    private var rowHeight: CGFloat { ((theme.isGlass ? Glass.rowHeight : Size.rowHeight) * fontSize / Size.fontSize).rounded() }
    private var sectionHeight: CGFloat {
        theme.isGlass ? Glass.footerHeight : (labelFont.ascender - labelFont.descender).rounded(.up) + Size.sectionPaddingY * 2
    }
    /// 外枠と立体の縁の太さ．glass は余白
    private var inset: CGFloat { theme.isGlass ? Glass.padding / 2 : Size.frameWidth + Size.bevelWidth }
    /// 番号の幅
    private var lead: CGFloat { theme.isGlass ? Glass.badgeSize + Size.paddingX : Size.indexWidth }
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
        let footer = footerContent(for: panel)
        let footerWidth = hintsWidth(footer.hints, note: footer.note) + footer.position.size(withAttributes: labelAttributes).width + Size.paddingX * 3
        let contentWidth = max(Size.minWidth, lead + entryWidth + Size.paddingX * 2, variantsWidth + Size.paddingX * 2, footerWidth)
        var height = CGFloat(panel.entries.count) * rowHeight + sectionHeight + Size.frameWidth
        if !panel.variants.isEmpty { height += sectionHeight + Size.frameWidth }
        return NSSize(width: (contentWidth + inset * 2 + dropShadowOffset).rounded(.up), height: (height + inset * 2 + dropShadowOffset).rounded(.up))
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        guard let panel else { return }
        let body = NSRect(x: 0, y: 0, width: bounds.width - dropShadowOffset, height: bounds.height - dropShadowOffset)
        if theme.isGlass {
            GlassDrawing.drawFrame(in: body, theme: theme, fillsSurface: fillsSurface)
        } else {
            BevelDrawing.drawDropShadow(for: body, theme: theme)
            BevelDrawing.drawPanel(in: body, theme: theme)
        }
        let content = body.insetBy(dx: inset, dy: inset)
        var y = content.minY
        if !panel.variants.isEmpty {
            drawVariants(panel, in: NSRect(x: content.minX, y: y, width: content.width, height: sectionHeight))
            y += sectionHeight
            drawSeparator(y: y, from: content.minX, to: content.maxX)
            y += Size.frameWidth
        }
        for (index, entry) in panel.entries.enumerated() {
            drawEntry(entry, index: index, panel: panel, in: NSRect(x: content.minX, y: y, width: content.width, height: rowHeight))
            y += rowHeight
        }
        drawSeparator(y: y, from: content.minX, to: content.maxX)
        y += Size.frameWidth
        drawFooter(panel, in: NSRect(x: content.minX, y: y, width: content.width, height: sectionHeight))
    }

    private func drawSeparator(y: CGFloat, from minX: CGFloat, to maxX: CGFloat) {
        if theme.isGlass {
            theme.line.setFill()
            NSRect(x: minX + Size.paddingX / 2, y: y, width: maxX - minX - Size.paddingX, height: Size.frameWidth).fill()
        } else {
            BevelDrawing.drawSeparator(y: y, from: minX, to: maxX, theme: theme)
        }
    }

    private func drawVariants(_ panel: CandidatePanel, in rect: NSRect) {
        var x = rect.minX + Size.paddingX / 2
        for (index, variant) in panel.variants.enumerated() {
            let isSelected = panel.focus == .variants && panel.selectedVariant == index
            // ふだんは弱い文字で見せ，上キーで移ったときだけ強調する(R-03)
            let color: NSColor = isSelected ? theme.selectionText : (variant.isAvailable ? theme.textMuted : theme.textMuted.withAlphaComponent(0.4))
            let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: color]
            let width = variant.label.size(withAttributes: attributes).width + Size.variantPaddingX * 2
            let cell = NSRect(x: x, y: rect.minY + (theme.isGlass ? 4 : 1), width: width, height: rect.height - (theme.isGlass ? 8 : 2))
            if isSelected {
                if theme.isGlass {
                    GlassDrawing.fillCapsule(cell, color: theme.selection)
                } else {
                    theme.selection.setFill()
                    cell.fill()
                }
            }
            drawText(variant.label, attributes: attributes, x: cell.minX + Size.variantPaddingX, in: cell)
            x += width
        }
    }

    private func drawEntry(_ entry: CandidatePanel.Entry, index: Int, panel: CandidatePanel, in rect: NSRect) {
        let isSelected = panel.focus == .candidate && panel.selectedEntry == index
        if isSelected {
            if theme.isGlass {
                GlassDrawing.fillCapsule(rect.insetBy(dx: 0, dy: 2), color: theme.selection)
            } else {
                theme.selection.setFill()
                rect.fill()
            }
        }
        let opacity: CGFloat = (isSelected || index == 0) ? 1 : restOpacity
        let textColor = (isSelected ? theme.selectionText : theme.text).withAlphaComponent(opacity)
        let mutedColor = (isSelected ? theme.selectionText : theme.textMuted).withAlphaComponent(opacity)
        let number = "\(index + 1)"
        if theme.isGlass {
            let center = NSPoint(x: rect.minX + Size.paddingX / 2 + Glass.badgeSize / 2, y: rect.midY)
            GlassDrawing.drawBadge(number, center: center, theme: theme, selected: isSelected, opacity: opacity)
            drawText(entry.text, attributes: [.font: candidateFont, .foregroundColor: textColor], x: rect.minX + Size.paddingX / 2 + lead, in: rect)
        } else {
            drawText(number, attributes: [.font: labelFont, .foregroundColor: mutedColor], x: rect.minX + Size.paddingX, in: rect)
            drawText(entry.text, attributes: [.font: candidateFont, .foregroundColor: textColor], x: rect.minX + Size.paddingX + lead, in: rect)
        }
        if let annotation = entry.annotation {
            let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: mutedColor]
            let width = annotation.size(withAttributes: attributes).width
            drawText(annotation, attributes: attributes, x: rect.maxX - Size.paddingX - width, in: rect)
        }
    }

    // MARK: - 足元

    private struct Footer {
        var hints: [KeyHint]
        var note: String?
        var position: String
    }

    private func footerContent(for panel: CandidatePanel) -> Footer {
        if panel.focus == .variants {
            let position = UIStrings.Candidate.variantsPosition(panel.selectedVariant.map { $0 + 1 } ?? 1, panel.variants.count)
            return Footer(hints: UIStrings.Candidate.variantsHints, note: panel.note, position: position)
        }
        return Footer(hints: UIStrings.Candidate.candidatesHints, note: panel.note, position: UIStrings.Candidate.position(panel.position, panel.total))
    }

    private func hintsWidth(_ hints: [KeyHint], note: String?) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont]
        if let note { return note.size(withAttributes: attributes).width }
        return theme.isGlass ? GlassDrawing.hintsWidth(hints, theme: theme) : KeyHint.text(hints).size(withAttributes: attributes).width
    }

    /// glass は案内を左，位置を右．platinum と desk は位置を左，案内を右(漢字Talk 7 の候補ウィンドウにならう)
    private func drawFooter(_ panel: CandidatePanel, in rect: NSRect) {
        let footer = footerContent(for: panel)
        let muted: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.textMuted]
        let noteAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.correction]
        let left = rect.minX + Size.paddingX
        let right = { (text: String, attributes: [NSAttributedString.Key: Any]) in
            self.drawText(text, attributes: attributes, x: rect.maxX - Size.paddingX - text.size(withAttributes: attributes).width, in: rect)
        }
        if theme.isGlass {
            if let note = footer.note {
                drawText(note, attributes: noteAttributes, x: left, in: rect)
            } else {
                GlassDrawing.drawHints(footer.hints, x: left, midY: rect.midY, theme: theme)
            }
            right(footer.position, muted)
            return
        }
        drawText(footer.position, attributes: muted, x: left, in: rect)
        if let note = footer.note {
            right(note, noteAttributes)
        } else {
            right(KeyHint.text(footer.hints), muted)
        }
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
    @MainActor
    static var resolveStatic: ResolvedTheme { resolve(.automatic, appearance: NSAppearance(named: .aqua)) }
}
