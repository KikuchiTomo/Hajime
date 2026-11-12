import AppKit
import HajimeApplication
import HajimeDomain

/// 絵文字と記号のパレットの中身を描く(R-26)．上から，探す欄と種類の切り替え・まとまりのタブ・見出し・マス目・文字の説明・キーの案内．
///
/// 何を出すかは core(PaletteSession)が決めた PalettePanel のとおりにし，ここでは描くことと，押した位置を PaletteTarget にすることだけをする．
/// 窓の大きさは列数・行数・マスの大きさだけで決め，中身(探した結果の数や種類)では変えない．
/// 顔文字はマス目の幅を 1 行のマスの数(cellsPerRow)で割った広いマスに，テーマの文字の書体で描く
final class PaletteView: NSView {
    private typealias Size = DesignTokens.Size.Palette
    private typealias Glass = DesignTokens.Size.Glass

    var panel: PalettePanel? { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }
    /// マスの一辺(設定のパレットのマスの大きさ)
    var cellSize = CGFloat(DefaultSettings.paletteCellSize) { didSet { needsDisplay = true } }
    /// glass の面を自分で塗るか．ぼかしの地(GlassBackdrop)の無いところ(画像への書き出し)で使う
    var fillsSurface = false { didSet { needsDisplay = true } }
    /// 押した対象を知らせる先
    var onTarget: ((PaletteTarget) -> Void)?

    override var isFlipped: Bool { true }

    private var dropShadowOffset: CGFloat { theme.hasDropShadow ? DesignTokens.Size.Candidate.shadowOffset : 0 }
    private var inset: CGFloat { theme.isRounded ? Size.padding : DesignTokens.Size.Candidate.frameWidth + DesignTokens.Size.Candidate.bevelWidth + Size.padding / 2 }
    private var labelFont: NSFont { theme.labelFont(size: Size.headingFontSize) }

    // MARK: - 大きさと位置

    /// 窓の大きさ．列数・行数・マスの大きさ・説明を出すかだけで決まる
    func fittingSize(for panel: PalettePanel) -> NSSize {
        let width = inset * 2 + CGFloat(panel.columns) * cellSize + Size.scrollbarGutter + dropShadowOffset
        var height = inset * 2 + Size.searchHeight + Size.gap + Size.tabHeight + Size.headingHeight + CGFloat(panel.visibleRows) * cellSize + Size.gap
        if panel.showsPreview { height += PalettePreviewDrawing.height(for: panel.previewFields, theme: theme) }
        height += Size.footerHeight + dropShadowOffset
        return NSSize(width: width.rounded(.up), height: height.rounded(.up))
    }

    private struct Layout {
        var body: NSRect
        var search: NSRect
        var modes: [NSRect]
        var tabs: [NSRect]
        var heading: NSRect
        var grid: NSRect
        var scrollbar: NSRect
        var preview: NSRect?
        var footer: NSRect
        var skinToneButton: NSRect
    }

    private func layout(for panel: PalettePanel) -> Layout {
        let body = NSRect(x: 0, y: 0, width: bounds.width - dropShadowOffset, height: bounds.height - dropShadowOffset)
        let content = body.insetBy(dx: inset, dy: inset)
        var y = content.minY
        // 探す欄の右に種類の切り替えを置く
        let modeFont = theme.labelFont(size: Size.modeFontSize)
        let modeWidths = panel.modes.map { ($0.title.size(withAttributes: [.font: modeFont]).width + Size.modePaddingX * 2).rounded(.up) }
        let modesWidth = modeWidths.reduce(0, +)
        var x = content.maxX - modesWidth
        let modes = modeWidths.map { width in
            defer { x += width }
            return NSRect(x: x, y: y, width: width, height: Size.searchHeight)
        }
        let search = NSRect(x: content.minX, y: y, width: content.width - modesWidth - Size.gap, height: Size.searchHeight)
        y += Size.searchHeight + Size.gap
        let tabWidth = panel.tabs.isEmpty ? 0 : min(Size.tabHeight + Size.gap, content.width / CGFloat(panel.tabs.count)).rounded(.down)
        let tabs = panel.tabs.indices.map { NSRect(x: content.minX + CGFloat($0) * tabWidth, y: y, width: tabWidth, height: Size.tabHeight) }
        y += Size.tabHeight
        let heading = NSRect(x: content.minX, y: y, width: content.width, height: Size.headingHeight)
        y += Size.headingHeight
        let grid = NSRect(x: content.minX, y: y, width: CGFloat(panel.columns) * cellSize, height: CGFloat(panel.visibleRows) * cellSize)
        let scrollbar = NSRect(x: grid.maxX + (Size.scrollbarGutter - Size.scrollbarWidth) / 2, y: grid.minY, width: Size.scrollbarWidth, height: grid.height)
        y = grid.maxY + Size.gap
        var preview: NSRect?
        if panel.showsPreview {
            let height = PalettePreviewDrawing.height(for: panel.previewFields, theme: theme)
            preview = NSRect(x: content.minX, y: y, width: content.width, height: height)
            y += height
        }
        let footer = NSRect(x: content.minX, y: y, width: content.width, height: Size.footerHeight)
        let button = NSRect(x: footer.maxX - Size.footerHeight, y: footer.minY, width: Size.footerHeight, height: Size.footerHeight)
        return Layout(body: body, search: search, modes: modes, tabs: tabs, heading: heading, grid: grid, scrollbar: scrollbar, preview: preview,
                      footer: footer, skinToneButton: button)
    }

    /// マスの幅．四角いマスは一辺．顔文字の広いマスは，マス目の幅を 1 行のマスの数で割ったもの
    private func cellWidth(for panel: PalettePanel) -> CGFloat {
        CGFloat(panel.columns) * cellSize / CGFloat(max(panel.cellsPerRow, 1))
    }

    /// 今の種類のマスが広いマス(顔文字)か
    private static func isWide(_ panel: PalettePanel) -> Bool {
        panel.modes.first { $0.isSelected }?.kind.cellShape == .wide
    }

    private func cellRect(row: Int, column: Int, in layout: Layout, panel: PalettePanel) -> NSRect {
        let width = cellWidth(for: panel)
        return NSRect(x: layout.grid.minX + CGFloat(column) * width, y: layout.grid.minY + CGFloat(row - panel.firstRow) * cellSize, width: width, height: cellSize)
    }

    /// 肌の色の帯のマス．説明の欄(無ければマス目の下の端)に重ねて出す
    private func pickerCells(_ picker: PalettePanel.SkinTonePicker, in layout: Layout) -> [NSRect] {
        let size = Size.pickerCellSize
        let width = size * CGFloat(picker.options.count)
        let area = layout.preview ?? NSRect(x: layout.grid.minX, y: layout.grid.maxY - size, width: layout.grid.width, height: size)
        let x = (area.midX - width / 2).rounded()
        let y = (area.midY - size / 2).rounded()
        return picker.options.indices.map { NSRect(x: x + CGFloat($0) * size, y: y, width: size, height: size) }
    }

    // MARK: - 押した位置

    func target(at point: NSPoint, hovering: Bool = false) -> PaletteTarget? {
        guard let panel else { return nil }
        let layout = layout(for: panel)
        if let picker = panel.skinTonePicker, let index = pickerCells(picker, in: layout).firstIndex(where: { $0.contains(point) }) {
            return hovering ? nil : .skinTone(SkinTone.allCases[index])
        }
        if layout.grid.contains(point) {
            let column = Int((point.x - layout.grid.minX) / cellWidth(for: panel))
            let row = panel.firstRow + Int((point.y - layout.grid.minY) / cellSize)
            guard panel.rows.first(where: { $0.index == row }).map({ column < $0.cells.count }) ?? false else { return nil }
            let position = PalettePanel.Position(row: row, column: column)
            return hovering ? .hover(position) : .cell(position)
        }
        guard !hovering else { return nil }
        if let index = layout.tabs.firstIndex(where: { $0.contains(point) }) { return .tab(panel.tabs[index].section) }
        if let index = layout.modes.firstIndex(where: { $0.contains(point) }) { return .mode(panel.modes[index].kind) }
        if layout.skinToneButton.contains(point) { return .skinToneButton }
        if let preview = layout.preview, preview.contains(point), panel.preview != nil, pinRect(in: preview).contains(point) { return .pin }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let target = target(at: convert(event.locationInWindow, from: nil)) else { return }
        onTarget?(target)
    }

    override func mouseMoved(with event: NSEvent) {
        guard let target = target(at: convert(event.locationInWindow, from: nil), hovering: true) else { return }
        onTarget?(target)
    }

    /// ホイールの量をためて，マス 1 つ分ごとに 1 行スクロールする
    private var scrollRemainder: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * cellSize
        scrollRemainder -= delta
        let rows = Int(scrollRemainder / cellSize)
        guard rows != 0 else { return }
        scrollRemainder -= CGFloat(rows) * cellSize
        onTarget?(.scroll(rows))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // 窓が前に出ていなくても 1 回目の押下で選ぶ(入力先のアプリからフォーカスを移さない)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        guard let panel else { return }
        let layout = layout(for: panel)
        if theme.isRounded {
            GlassDrawing.drawFrame(in: layout.body, theme: theme, fillsSurface: fillsSurface)
        } else {
            BevelDrawing.drawDropShadow(for: layout.body, theme: theme)
            BevelDrawing.drawPanel(in: layout.body, theme: theme)
        }
        drawSearch(panel, in: layout.search)
        drawModes(panel, in: layout.modes)
        drawTabs(panel, in: layout.tabs)
        drawHeading(panel.heading, in: layout.heading)
        drawGrid(panel, layout: layout)
        if let preview = layout.preview {
            separator(y: preview.minY - Size.gap / 2, from: layout.grid.minX, to: layout.footer.maxX)
            if let shown = panel.preview { drawPreview(shown, in: preview, isWide: Self.isWide(panel)) }
        }
        separator(y: layout.footer.minY, from: layout.footer.minX, to: layout.footer.maxX)
        drawFooter(panel, layout: layout)
        if let picker = panel.skinTonePicker { drawPicker(picker, layout: layout) }
    }

    private func separator(y: CGFloat, from minX: CGFloat, to maxX: CGFloat) {
        if theme.isRounded {
            theme.line.setFill()
            NSRect(x: minX, y: y.rounded(), width: maxX - minX, height: DesignTokens.Size.Candidate.frameWidth).fill()
        } else {
            BevelDrawing.drawSeparator(y: y.rounded(), from: minX, to: maxX, theme: theme)
        }
    }

    /// 角丸のテーマは角丸で，platinum と desk は角の立った形で塗る
    private func fill(_ rect: NSRect, color: NSColor, radius: CGFloat) {
        color.setFill()
        if theme.isRounded {
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        } else {
            rect.fill()
        }
    }

    private func stroke(_ rect: NSRect, color: NSColor, radius: CGFloat, width: CGFloat) {
        color.setStroke()
        let inset = rect.insetBy(dx: width / 2, dy: width / 2)
        let path = theme.isRounded ? NSBezierPath(roundedRect: inset, xRadius: radius, yRadius: radius) : NSBezierPath(rect: inset)
        path.lineWidth = width
        path.stroke()
    }

    private func drawSearch(_ panel: PalettePanel, in rect: NSRect) {
        fill(rect, color: theme.badge, radius: Size.searchRadius)
        let iconSize = Size.searchIconSize
        if let icon = SymbolImageCache.image("magnifyingglass", pointSize: iconSize, weight: .medium, color: theme.textMuted) {
            icon.draw(in: NSRect(x: rect.minX + Size.modePaddingX, y: (rect.midY - icon.size.height / 2).rounded(), width: icon.size.width, height: icon.size.height))
        }
        let caretWidth = Size.selectionStroke
        let textX = rect.minX + Size.modePaddingX * 2 + iconSize + caretWidth
        let font = theme.candidateFont(size: Size.searchFontSize)
        let isEmpty = panel.query.isEmpty
        let text = isEmpty ? panel.placeholder : panel.query
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: isEmpty ? theme.textMuted : theme.text]
        let available = rect.maxX - textX - Size.modePaddingX
        let shown = TextFitting.truncated(text, attributes: attributes, width: available)
        let size = shown.size(withAttributes: attributes)
        let y = (rect.midY - size.height / 2).rounded()
        shown.draw(at: NSPoint(x: textX, y: y), withAttributes: attributes)
        // 打った文字が探す欄に入ることを示す縦の線(入力位置)．空なら案内の文の前に置く
        let caretX = isEmpty ? textX - caretWidth * 2 : min(textX + size.width + 1, rect.maxX - Size.modePaddingX)
        theme.selection.setFill()
        NSRect(x: caretX.rounded(), y: rect.midY - Size.searchFontSize / 2 - 1, width: caretWidth, height: Size.searchFontSize + 2).fill()
    }

    private func drawModes(_ panel: PalettePanel, in rects: [NSRect]) {
        guard let first = rects.first, let last = rects.last else { return }
        let whole = NSRect(x: first.minX, y: first.minY, width: last.maxX - first.minX, height: first.height)
        fill(whole, color: theme.badge, radius: Size.searchRadius)
        let font = theme.labelFont(size: Size.modeFontSize)
        for (mode, rect) in zip(panel.modes, rects) {
            if mode.isSelected { fill(rect.insetBy(dx: 2, dy: 2), color: theme.selection, radius: Size.searchRadius - 2) }
            GlassDrawing.drawCentered(mode.title, attributes: [.font: font, .foregroundColor: mode.isSelected ? theme.selectionText : theme.textMuted], in: rect)
        }
    }

    private func drawTabs(_ panel: PalettePanel, in rects: [NSRect]) {
        for (tab, rect) in zip(panel.tabs, rects) {
            let color = tab.isSelected ? theme.text : theme.textMuted
            if tab.isSelected, theme.isRounded {
                // 角丸のテーマは薄い地と下の線で示す
                fill(rect.insetBy(dx: 2, dy: 2), color: theme.focusTint, radius: Glass.selectionRadius)
                theme.selection.setFill()
                NSRect(x: rect.minX + 4, y: rect.maxY - Size.selectionStroke, width: rect.width - 8, height: Size.selectionStroke).fill()
            } else if tab.isSelected {
                // platinum と desk は選択の色の枠と下の線で示す．塗ってアイコンを選択の文字の色にすると，
                // 選択の文字の色が暗いテーマ(desk)では SF Symbols の顔の中まで塗られて見分けられない
                stroke(rect.insetBy(dx: 2, dy: 2), color: theme.selection, radius: 0, width: 1)
                theme.selection.setFill()
                NSRect(x: rect.minX + 4, y: rect.maxY - Size.selectionStroke - 2, width: rect.width - 8, height: Size.selectionStroke).fill()
            }
            if let name = PaletteIcons.symbolName(for: tab.section),
               let image = SymbolImageCache.image(name, pointSize: Size.tabIconSize, weight: tab.isSelected ? .semibold : .regular, color: color) {
                image.draw(in: NSRect(x: (rect.midX - image.size.width / 2).rounded(), y: (rect.midY - image.size.height / 2).rounded(),
                                      width: image.size.width, height: image.size.height))
            } else {
                // 顔文字のまとまりの短い顔はタブの幅に収まるよう縮める
                drawFitted(tab.symbol, size: Size.tabIconSize + 1, color: color, in: rect.insetBy(dx: 2, dy: 0))
            }
        }
    }

    private func drawHeading(_ text: String, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.textMuted]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: rect.minX + Size.cellRadius, y: (rect.midY - size.height / 2).rounded()), withAttributes: attributes)
    }

    private func drawGrid(_ panel: PalettePanel, layout: Layout) {
        let emojiFont = NSFont(name: PaletteIcons.emojiFontName, size: (cellSize * Size.emojiScale).rounded()) ?? .systemFont(ofSize: cellSize * Size.emojiScale)
        let symbolFont = theme.candidateFont(size: (cellSize * Size.symbolScale).rounded())
        let isWide = Self.isWide(panel)
        for row in panel.rows {
            if row.startsSection, row.index != panel.firstRow {
                // まとまりの境目に細い線を引く
                let y = layout.grid.minY + CGFloat(row.index - panel.firstRow) * cellSize
                theme.line.setFill()
                NSRect(x: layout.grid.minX + Size.cellRadius, y: y.rounded(), width: layout.grid.width - Size.cellRadius * 2, height: DesignTokens.Size.Candidate.frameWidth).fill()
            }
            for (column, cell) in row.cells.enumerated() {
                let rect = cellRect(row: row.index, column: column, in: layout, panel: panel)
                let isSelected = panel.selection == PalettePanel.Position(row: row.index, column: column)
                if isSelected {
                    // 色だけに頼らないよう，地を塗ったうえで枠も描く
                    let inner = rect.insetBy(dx: 1, dy: 1)
                    fill(inner, color: theme.focusTint, radius: Size.cellRadius)
                    stroke(inner, color: theme.selection, radius: Size.cellRadius, width: Size.selectionStroke)
                }
                if isWide {
                    // 顔文字は絵文字を含んでいても文字の書体で描く(顔の形を崩さない)
                    drawFitted(cell.text, size: (cellSize * Size.kaomojiScale).rounded(), color: theme.text, in: rect.insetBy(dx: Size.kaomojiPaddingX, dy: 0))
                    continue
                }
                let font = Self.isEmoji(cell.text) ? emojiFont : symbolFont
                GlassDrawing.drawCentered(cell.text, attributes: [.font: font, .foregroundColor: theme.text], in: rect)
            }
        }
        if let message = panel.message {
            let attributes: [NSAttributedString.Key: Any] = [.font: theme.labelFont(size: Size.detailFontSize), .foregroundColor: theme.textMuted]
            GlassDrawing.drawCentered(message, attributes: attributes, in: layout.grid)
        }
        drawScrollbar(panel, in: layout.scrollbar)
    }

    private func drawScrollbar(_ panel: PalettePanel, in rect: NSRect) {
        guard panel.rowCount > panel.visibleRows else { return }
        let length = max(rect.height * CGFloat(panel.visibleRows) / CGFloat(panel.rowCount), Size.scrollbarMinLength)
        let travel = rect.height - length
        let maximumFirst = CGFloat(panel.rowCount - panel.visibleRows)
        let y = rect.minY + travel * CGFloat(panel.firstRow) / maximumFirst
        fill(NSRect(x: rect.minX, y: y.rounded(), width: rect.width, height: length.rounded()), color: theme.textMuted.withAlphaComponent(DesignTokens.Opacity.Palette.scrollbar),
             radius: rect.width / 2)
    }

    private func pinRect(in preview: NSRect) -> NSRect {
        NSRect(x: preview.maxX - Size.footerHeight, y: preview.minY, width: Size.footerHeight, height: Size.footerHeight)
    }

    /// 説明の欄．左上に選んでいる文字の大きな見本，右上にピン留めのボタン，見本の右と下に名前・読み・札(PalettePreviewDrawing)
    private func drawPreview(_ preview: PalettePanel.Preview, in rect: NSRect, isWide: Bool) {
        let area = PalettePreviewDrawing.contentArea(of: rect)
        let side = PalettePreviewDrawing.tileSide
        var tile = NSRect(x: area.minX, y: area.minY, width: side, height: side)
        if isWide {
            // 顔文字は横に長いので，文字の幅に合わせて枠を広げる(説明の欄の幅の一定の割合まで)
            let width = preview.text.size(withAttributes: [.font: theme.candidateFont(size: Size.previewKaomojiFontSize)]).width + Size.kaomojiPaddingX * 4
            tile.size.width = min(max(tile.width, width.rounded(.up)), (rect.width * Size.previewKaomojiWidth).rounded())
            fill(tile, color: theme.badge, radius: Size.cellRadius)
            drawFitted(preview.text, size: Size.previewKaomojiFontSize, color: theme.text, in: tile.insetBy(dx: Size.kaomojiPaddingX, dy: 0))
        } else {
            fill(tile, color: theme.badge, radius: Size.cellRadius)
            let glyphFont = Self.isEmoji(preview.text) ? (NSFont(name: PaletteIcons.emojiFontName, size: Size.previewGlyphSize * Size.emojiScale) ?? .systemFont(ofSize: Size.previewGlyphSize))
                : theme.candidateFont(size: Size.previewGlyphSize * Size.symbolScale * Size.previewSymbolBoost)
            GlassDrawing.drawCentered(preview.text, attributes: [.font: glyphFont, .foregroundColor: theme.text], in: tile)
        }
        let pin = pinRect(in: rect)
        PalettePreviewDrawing.draw(preview, in: .init(area: area, tile: tile, pin: pin), theme: theme)
        if let image = SymbolImageCache.image(preview.isPinned ? "pin.fill" : "pin", pointSize: Size.tabIconSize, weight: .regular,
                                              color: preview.isPinned ? theme.selection : theme.textMuted) {
            image.draw(in: NSRect(x: (pin.midX - image.size.width / 2).rounded(), y: (pin.midY - image.size.height / 2).rounded(), width: image.size.width, height: image.size.height))
        }
    }

    private func drawFooter(_ panel: PalettePanel, layout: Layout) {
        let footer = layout.footer
        let hints = panel.hints.map { KeyHint(key: $0.key, label: $0.action) }
        let fitting = GlassDrawing.hints(hints, fitting: footer.width - Size.footerHeight - Size.gap, theme: theme)
        GlassDrawing.drawHints(fitting, x: footer.minX, midY: footer.midY, theme: theme)
        // 既定の肌の色のボタン
        let button = layout.skinToneButton.insetBy(dx: 3, dy: 3)
        fill(button, color: theme.badge, radius: Size.cellRadius)
        let sample = PaletteStrings.skinToneSample.text(skinTone: panel.skinTone)
        let font = NSFont(name: PaletteIcons.emojiFontName, size: (button.height * Size.emojiScale).rounded()) ?? .systemFont(ofSize: button.height * Size.emojiScale)
        GlassDrawing.drawCentered(sample, attributes: [.font: font], in: button)
    }

    private func drawPicker(_ picker: PalettePanel.SkinTonePicker, layout: Layout) {
        let cells = pickerCells(picker, in: layout)
        guard let first = cells.first, let last = cells.last else { return }
        let margin = Size.selectionStroke * 2
        let strip = NSRect(x: first.minX, y: first.minY, width: last.maxX - first.minX, height: first.height).insetBy(dx: -margin, dy: -margin)
        // 下の説明の文字が帯のまわりに見えないよう，説明の欄ごと(上の区切りの線の下から)面の色で覆う
        if let preview = layout.preview {
            theme.surface.withAlphaComponent(1).setFill()
            let top = (preview.minY - Size.gap / 2).rounded() + DesignTokens.Size.Candidate.frameWidth
            NSRect(x: preview.minX, y: top, width: preview.width, height: preview.maxY - top).fill()
        }
        fill(strip, color: theme.surface.withAlphaComponent(1), radius: Size.searchRadius)
        stroke(strip, color: theme.frame, radius: Size.searchRadius, width: 1)
        let font = NSFont(name: PaletteIcons.emojiFontName, size: (Size.pickerCellSize * Size.emojiScale).rounded()) ?? .systemFont(ofSize: Size.pickerCellSize * Size.emojiScale)
        for (index, (option, rect)) in zip(picker.options, cells).enumerated() {
            if index == picker.selected {
                let inner = rect.insetBy(dx: 1, dy: 1)
                fill(inner, color: theme.focusTint, radius: Size.cellRadius)
                stroke(inner, color: theme.selection, radius: Size.cellRadius, width: Size.selectionStroke)
            }
            GlassDrawing.drawCentered(option, attributes: [.font: font], in: rect)
        }
    }

    /// テーマの文字の書体で，rect の幅に収まるよう縮めて真ん中に描く．縮めても下限(kaomojiMinFontSize)で収まらなければ末尾を省く
    private func drawFitted(_ text: String, size: CGFloat, color: NSColor, in rect: NSRect) {
        var font = theme.candidateFont(size: size)
        let width = text.size(withAttributes: [.font: font]).width
        if width > rect.width, width > 0 {
            font = theme.candidateFont(size: max(Size.kaomojiMinFontSize, (size * rect.width / width).rounded(.down)))
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        GlassDrawing.drawCentered(TextFitting.truncated(text, attributes: attributes, width: rect.width), attributes: attributes, in: rect)
    }

    /// 絵文字の書体で描く文字か．絵文字の表示を持つ文字(U+FE0F を含むものを含む)と，組み合わせの絵文字
    static func isEmoji(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation || text.unicodeScalars.contains("\u{FE0F}") || text.unicodeScalars.count > 1 && first.properties.isEmoji
    }
}

/// パレットのタブのアイコンと絵文字の書体．絵文字のまとまりは SF Symbols のアイコンで描き(テーマの文字の色に合わせる)，
/// 記号のまとまりは代表の文字で描く
enum PaletteIcons {
    static let emojiFontName = "AppleColorEmoji"

    static func symbolName(for section: PaletteSection.Kind) -> String? {
        switch section {
        case .pinned: "pin"
        case .frequent: "clock"
        case .results: "magnifyingglass"
        case .category(let category):
            switch category {
            case .smileys: "theatermasks"
            case .people: "hand.raised"
            case .nature: "pawprint"
            case .food: "fork.knife"
            case .travel: "car"
            case .activities: "soccerball"
            case .objects: "lightbulb"
            case .symbols: "heart"
            case .flags: "flag"
            case .punctuation, .brackets, .arrows, .math, .letters, .units, .enclosed, .shapes, .lines, .misc: nil
            case .joy, .sorrow, .sweat, .anger, .surprise, .greeting, .animals, .otherFaces: nil
            }
        }
    }
}
