import AppKit
import HajimeApplication
import HajimeDomain

/// 候補ウィンドウの中身を描く．上から，文字種の行・候補・足元の 3 つの区画．
/// 連想の一覧(R-18)では，文字種の行の代わりに見出し(元の語と意味の説明)の行を出す
final class CandidateView: NSView {
    private typealias Size = DesignTokens.Size.Candidate
    private typealias Glass = DesignTokens.Size.Glass

    var panel: CandidatePanel? { didSet { needsDisplay = true } }
    /// 足元の案内に出すキーの割り当て(連想の一覧のとき)
    var keys = KeymapPreset.standard.keymap { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }
    var fontSize: CGFloat = Size.fontSize { didSet { needsDisplay = true } }
    /// 第 1 候補と選んでいる候補以外の濃さ．出した直後は薄くし，すぐに濃くする(ephemeral adaptation)．
    /// 位置は動かさない．docs/dev/research/candidate-presentation.md の提案による
    var restOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    /// glass の面を自分で塗るか．ぼかしの地(GlassBackdrop)の無いところ(画像への書き出し)で使う
    var fillsSurface = false { didSet { needsDisplay = true } }
    /// 窓の幅の上限．長い文の候補は末尾を「…」で省いてこの幅に収める(CandidatePanelController が画面の幅から決める)
    var maximumWidth = DesignTokens.Size.Candidate.maxWidth { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    private var candidateFont: NSFont { theme.candidateFont(size: fontSize) }
    private var labelFont: NSFont { theme.labelFont(size: theme.isRounded ? Glass.labelFontSize : Size.labelFontSize) }
    private var rowHeight: CGFloat { ((theme.isRounded ? Glass.rowHeight : Size.rowHeight) * fontSize / Size.fontSize).rounded() }
    private var sectionHeight: CGFloat {
        theme.isRounded ? Glass.footerHeight
            : max((labelFont.ascender - labelFont.descender).rounded(.up), Glass.keycapHeight) + Size.sectionPaddingY * 2
    }
    /// 外枠と立体の縁の太さ．glass は余白
    private var inset: CGFloat { theme.isRounded ? Glass.padding / 2 : Size.frameWidth + Size.bevelWidth }
    /// 番号の幅
    private var lead: CGFloat { theme.isRounded ? Glass.badgeSize + Size.paddingX : Size.indexWidth }
    private var dropShadowOffset: CGFloat { theme.hasDropShadow ? Size.shadowOffset : 0 }

    // MARK: - 大きさ

    func fittingSize(for panel: CandidatePanel) -> NSSize {
        let textAttributes: [NSAttributedString.Key: Any] = [.font: candidateFont]
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont]
        let entryWidth = panel.entries.map { entry in
            let annotation = entry.annotation.map { NoteDrawing.tagWidth($0, theme: theme) + Size.paddingX } ?? 0
            return entry.text.size(withAttributes: textAttributes).width + annotation
        }.max() ?? 0
        let variantsWidth = panel.variants.reduce(CGFloat(0)) { width, variant in
            width + variant.label.size(withAttributes: labelAttributes).width + Size.variantPaddingX * 2
        }
        let footer = footerContent(for: panel)
        let footerWidth = hintsWidth(footer) + footer.position.size(withAttributes: labelAttributes).width + Size.paddingX * 3
        let headingWidth = panel.association.map { AssociationHeadingDrawing.width($0, font: labelFont, emphasis: labelFont) + Size.paddingX * 2 } ?? 0
        let contentWidth = max(Size.minWidth, lead + entryWidth + Size.paddingX * 2, variantsWidth + Size.paddingX * 2, footerWidth, headingWidth)
        var height = CGFloat(panel.entries.count) * rowHeight + sectionHeight + Size.frameWidth
        if !panel.variants.isEmpty || panel.association != nil { height += sectionHeight + Size.frameWidth }
        let width = min(contentWidth + inset * 2 + dropShadowOffset, max(maximumWidth, Size.minWidth))
        return NSSize(width: width.rounded(.up), height: (height + inset * 2 + dropShadowOffset).rounded(.up))
    }

    // MARK: - 押した位置

    /// 押した対象を知らせる先(候補の窓をマウスで押したとき)
    var onChoose: ((PointerTarget) -> Void)?

    /// 字種の行と候補の行の位置．描くときと押した位置を調べるときで同じものを使う
    private struct Geometry {
        var variantsRow: NSRect?
        var entryRows: [NSRect]
    }

    private func geometry(for panel: CandidatePanel) -> Geometry {
        let body = NSRect(x: 0, y: 0, width: bounds.width - dropShadowOffset, height: bounds.height - dropShadowOffset)
        let content = body.insetBy(dx: inset, dy: inset)
        var y = content.minY
        var variantsRow: NSRect?
        if panel.association != nil || !panel.variants.isEmpty {
            if panel.association == nil { variantsRow = NSRect(x: content.minX, y: y, width: content.width, height: sectionHeight) }
            y += sectionHeight + Size.frameWidth
        }
        let entryRows = panel.entries.indices.map { index in
            NSRect(x: content.minX, y: y + CGFloat(index) * rowHeight, width: content.width, height: rowHeight)
        }
        return Geometry(variantsRow: variantsRow, entryRows: entryRows)
    }

    /// 字種の行の 1 つずつの枠
    private func variantCells(_ panel: CandidatePanel, in rect: NSRect) -> [NSRect] {
        var x = rect.minX + Size.paddingX / 2
        return panel.variants.map { variant in
            let width = variant.label.size(withAttributes: [.font: labelFont]).width + Size.variantPaddingX * 2
            defer { x += width }
            return NSRect(x: x, y: rect.minY + (theme.isRounded ? 4 : 1), width: width, height: rect.height - (theme.isRounded ? 8 : 2))
        }
    }

    /// point(この view の座標)にある押せる対象．無ければ nil
    func target(at point: NSPoint) -> PointerTarget? {
        guard let panel else { return nil }
        let geometry = geometry(for: panel)
        if let row = geometry.entryRows.firstIndex(where: { $0.contains(point) }) { return .entry(row) }
        if let row = geometry.variantsRow, let cell = variantCells(panel, in: row).firstIndex(where: { $0.contains(point) }),
           panel.variants[cell].isAvailable {
            return .listVariant(cell)
        }
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
        let body = NSRect(x: 0, y: 0, width: bounds.width - dropShadowOffset, height: bounds.height - dropShadowOffset)
        if theme.isRounded {
            GlassDrawing.drawFrame(in: body, theme: theme, fillsSurface: fillsSurface)
        } else {
            BevelDrawing.drawDropShadow(for: body, theme: theme)
            BevelDrawing.drawPanel(in: body, theme: theme)
        }
        let content = body.insetBy(dx: inset, dy: inset)
        var y = content.minY
        if let heading = panel.association {
            let row = NSRect(x: content.minX + Size.paddingX, y: y, width: content.width - Size.paddingX * 2, height: sectionHeight)
            AssociationHeadingDrawing.draw(heading, in: row, theme: theme, font: labelFont, emphasis: labelFont)
            y += sectionHeight
            drawSeparator(y: y, from: content.minX, to: content.maxX)
            y += Size.frameWidth
        } else if !panel.variants.isEmpty {
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
        if theme.isRounded {
            theme.line.setFill()
            NSRect(x: minX + Size.paddingX / 2, y: y, width: maxX - minX - Size.paddingX, height: Size.frameWidth).fill()
        } else {
            BevelDrawing.drawSeparator(y: y, from: minX, to: maxX, theme: theme)
        }
    }

    private func drawVariants(_ panel: CandidatePanel, in rect: NSRect) {
        for (index, (variant, cell)) in zip(panel.variants, variantCells(panel, in: rect)).enumerated() {
            let isSelected = panel.focus == .variants && panel.selectedVariant == index
            // ふだんは弱い文字で見せ，上キーで移ったときだけ強調する(R-03)
            let color: NSColor = isSelected ? theme.selectionText : (variant.isAvailable ? theme.textMuted : theme.textMuted.withAlphaComponent(DesignTokens.Opacity.Variant.unavailable))
            let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: color]
            if isSelected {
                if theme.isRounded {
                    GlassDrawing.fillCapsule(cell, color: theme.selection)
                } else {
                    theme.selection.setFill()
                    cell.fill()
                }
            }
            drawText(variant.label, attributes: attributes, x: cell.minX + Size.variantPaddingX, in: cell)
        }
    }

    private func drawEntry(_ entry: CandidatePanel.Entry, index: Int, panel: CandidatePanel, in rect: NSRect) {
        let isSelected = panel.focus == .candidate && panel.selectedEntry == index
        if isSelected {
            if theme.isRounded {
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
        let textX: CGFloat
        if theme.isRounded {
            let center = NSPoint(x: rect.minX + Size.paddingX / 2 + Glass.badgeSize / 2, y: rect.midY)
            GlassDrawing.drawBadge(number, center: center, theme: theme, selected: isSelected, opacity: opacity)
            textX = rect.minX + Size.paddingX / 2 + lead
        } else {
            drawText(number, attributes: [.font: labelFont, .foregroundColor: mutedColor], x: rect.minX + Size.paddingX, in: rect)
            textX = rect.minX + Size.paddingX + lead
        }
        let annotationWidth = entry.annotation.map { NoteDrawing.tagWidth($0, theme: theme) + Size.paddingX } ?? 0
        let textAttributes: [NSAttributedString.Key: Any] = [.font: candidateFont, .foregroundColor: textColor]
        let available = rect.maxX - Size.paddingX - annotationWidth - textX
        // 長い文の候補は，ほかの候補と違うところの少し手前から見せる(頭が同じ文が並ぶので，末尾を省くと見分けられない)
        let shared = entry.text.count > Int(available / max(candidateFont.pointSize, 1))
            ? max(TextFitting.sharedPrefixLength(of: entry.text, among: panel.entries.map(\.text)) - Int(DesignTokens.Size.Candidate.truncationContext), 0) : 0
        let shown = TextFitting.truncated(entry.text, attributes: textAttributes, width: available, keeping: shared)
        drawText(shown, attributes: textAttributes, x: textX, in: rect)
        // 省いたときは下線を引く範囲を，見えている文字(「…」を除く)までにする
        if let corrected = entry.corrected, shown == entry.text {
            // 打ち間違いを直した語句に，入力中の文字と同じ補正の点線の下線を引く．選んでいる行は選択の文字の色にする
            let characters = Array(entry.text)
            let start = min(corrected.lowerBound, characters.count), end = min(corrected.upperBound, characters.count)
            let width = { (text: ArraySlice<Character>) in String(text).size(withAttributes: [.font: self.candidateFont]).width }
            let from = (textX + width(characters[..<start])).rounded()
            let to = (from + width(characters[start..<end])).rounded()
            let offset = theme.isRounded ? Glass.underlineOffset : DesignTokens.Size.Branch.underlineOffset
            let color = (isSelected ? theme.selectionText : theme.correction).withAlphaComponent(opacity)
            GlassDrawing.drawUnderline(from: from, to: to, y: rect.maxY - offset, color: color, dotted: true, theme: theme)
        }
        if let annotation = entry.annotation {
            NoteDrawing.drawTag(annotation, maxX: rect.maxX - Size.paddingX / 2, midY: rect.midY, theme: theme, selected: isSelected)
        }
    }

    // MARK: - 足元

    private struct Footer {
        var hints: [KeyHint]
        var note: Note?
        var position: String
        /// 選んでいる候補に連想があるときの知らせ(R-18)．キーの案内のあとに小さく出す
        var associationHint: String?
    }

    private func footerContent(for panel: CandidatePanel) -> Footer {
        if panel.association != nil {
            return Footer(hints: UIStrings.Association.hints(for: keys), note: panel.note, position: UIStrings.Candidate.position(panel.position, panel.total))
        }
        if panel.focus == .variants {
            let position = UIStrings.Candidate.variantsPosition(panel.selectedVariant.map { $0 + 1 } ?? 1, panel.variants.count)
            return Footer(hints: UIStrings.Candidate.variantsHints, note: panel.note, position: position)
        }
        return Footer(hints: UIStrings.Candidate.candidatesHints, note: panel.note, position: UIStrings.Candidate.position(panel.position, panel.total),
                      associationHint: panel.associationHint)
    }

    private func hintsWidth(_ footer: Footer) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont]
        if let note = footer.note { return NoteDrawing.width(note, theme: theme) }
        let extra = footer.associationHint.map { $0.size(withAttributes: attributes).width + Size.paddingX } ?? 0
        return GlassDrawing.hintsWidth(footer.hints, theme: theme) + extra
    }

    /// glass は案内を左，位置を右．platinum と desk は位置を左，案内を右(漢字Talk 7 の候補ウィンドウにならう)
    private func drawFooter(_ panel: CandidatePanel, in rect: NSRect) {
        let footer = footerContent(for: panel)
        let muted: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.textMuted]
        let left = rect.minX + Size.paddingX
        let right = { (text: String, attributes: [NSAttributedString.Key: Any]) in
            self.drawText(text, attributes: attributes, x: rect.maxX - Size.paddingX - text.size(withAttributes: attributes).width, in: rect)
        }
        let hintsWidth = GlassDrawing.hintsWidth(footer.hints, theme: theme)
        if theme.isRounded {
            if let note = footer.note {
                NoteDrawing.draw(note, x: left, midY: rect.midY, theme: theme)
            } else {
                GlassDrawing.drawHints(footer.hints, x: left, midY: rect.midY, theme: theme)
                if let hint = footer.associationHint { drawText(hint, attributes: muted, x: left + hintsWidth + Size.paddingX, in: rect) }
            }
            right(footer.position, muted)
            return
        }
        drawText(footer.position, attributes: muted, x: left, in: rect)
        if let note = footer.note {
            NoteDrawing.draw(note, x: rect.maxX - Size.paddingX - NoteDrawing.width(note, theme: theme), midY: rect.midY, theme: theme)
        } else {
            GlassDrawing.drawHints(footer.hints, x: rect.maxX - Size.paddingX - hintsWidth, midY: rect.midY, theme: theme)
            if let hint = footer.associationHint {
                let width = hint.size(withAttributes: muted).width
                drawText(hint, attributes: muted, x: rect.maxX - Size.paddingX - hintsWidth - Size.paddingX - width, in: rect)
            }
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
