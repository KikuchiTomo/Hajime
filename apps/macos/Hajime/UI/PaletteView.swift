import AppKit
import HajimeApplication
import HajimeDomain

/// 絵文字と記号のパレットの中身を描く(R-26)．上から，探す欄と種類の切り替え・まとまりのタブ・見出し・マス目・文字の説明・キーの案内．
///
/// 何を出すかは core(PaletteSession)が決めた PalettePanel のとおりにし，ここでは描くことと，押した位置を PaletteTarget にすることだけをする．
/// 部品の位置と余白は core の PaletteWindowLayout が決める(余白は間隔の段階 size.space だけを使う)．
/// 窓の大きさは列数・行数・マスの大きさ・説明の項目と種類で決め，中身(探した結果の数や選んでいる文字)では変えない．
/// 顔文字はマス目の幅を 1 行のマスの数(cellsPerRow)で割った広いマスに，テーマの文字の書体で描く．
///
/// core が添えた動き(PalettePanel.Motion)があれば，選択の枠・種類の切り替えとタブの印を滑らせ，マス目の中身を送り，
/// 肌の色の帯とピンを弾ませる(PaletteMotionState)．動いているあいだは画面のリフレッシュ(CADisplayLink)ごとに，
/// 動いている部品の範囲だけを描き直す．「視差効果を減らす」が有効なら動かさない
final class PaletteView: NSView {
    private typealias Size = DesignTokens.Size.Palette
    private typealias Glass = DesignTokens.Size.Glass

    var panel: PalettePanel? {
        didSet {
            startMotion(from: oldValue)
            needsDisplay = true
        }
    }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }
    /// マスの一辺(設定のパレットのマスの大きさ)
    var cellSize = CGFloat(DefaultSettings.paletteCellSize) { didSet { needsDisplay = true } }
    /// glass の面を自分で塗るか．ぼかしの地(GlassBackdrop)の無いところ(画像への書き出し)で使う
    var fillsSurface = false { didSet { needsDisplay = true } }
    /// 押した対象を知らせる先
    var onTarget: ((PaletteTarget) -> Void)?
    /// 動きの時刻(秒)．画像への書き出しで動きの途中のコマを描くときに差し替える
    var clock: () -> CFTimeInterval = CACurrentMediaTime
    /// 窓に出ていなくても動きを付けるか(画像への書き出しで動きの途中のコマを描くとき)
    var forcesMotion = false

    private var motion = PaletteMotionState()
    private var displayLink: CADisplayLink?
    /// 中身を送るあいだの，前と今のマス目の画像．送り始めに一度だけ描き，コマごとにはこの画像をずらして重ねる(文字を描き直さない)
    private var swapImages: (previous: NSImage, current: NSImage)?
    /// マス目を画像に描いているところか．画像には描き直す範囲に関わらずすべてのマスを描く
    private var rendersOffscreen = false

    override var isFlipped: Bool { true }

    private var dropShadowOffset: CGFloat { theme.hasDropShadow ? DesignTokens.Size.Candidate.shadowOffset : 0 }
    /// 窓の縁の太さ(角丸のテーマは縁の線，platinum と desk は外枠と立体の縁)．内側の余白はこの内側から測る
    private var border: CGFloat {
        DesignTokens.Size.Candidate.frameWidth + (theme.isRounded ? 0 : DesignTokens.Size.Candidate.bevelWidth)
    }
    private var labelFont: NSFont { theme.labelFont(size: Size.headingFontSize) }
    /// 絵文字を実際の外形で箱の真ん中に置くための測り
    private let glyphs = GlyphFitting()

    // MARK: - 大きさと位置

    /// 窓の大きさ．列数・行数・マスの大きさ・説明の項目と種類で決まり，選んでいる文字では変えない
    func fittingSize(for panel: PalettePanel) -> NSSize {
        let layout = windowLayout(for: panel)
        return NSSize(width: CGFloat(layout.width).rounded(.up), height: CGFloat(layout.height).rounded(.up))
    }

    private func windowLayout(for panel: PalettePanel) -> PaletteWindowLayout {
        let modeFont = theme.labelFont(size: Size.modeFontSize)
        let modeWidths = panel.modes.map { Double(($0.title.size(withAttributes: [.font: modeFont]).width + Size.controlPaddingX * 2).rounded(.up)) }
        let previewHeight = panel.showsPreview ? PalettePreviewDrawing.height(for: panel.previewFields, kind: Self.kind(of: panel)) : nil
        return PaletteWindowLayout(columns: panel.columns, visibleRows: panel.visibleRows, cellSize: cellSize, tabCount: panel.tabs.count,
                                   modeWidths: modeWidths, previewHeight: previewHeight, metrics: .tokens(border: border, shadow: dropShadowOffset))
    }

    private struct Layout {
        var body: NSRect
        var content: NSRect
        var search: NSRect
        var modes: [NSRect]
        var tabs: [NSRect]
        var heading: NSRect
        var grid: NSRect
        var scrollbar: NSRect
        var separators: [CGFloat]
        var preview: NSRect?
        var footer: NSRect
        var skinToneButton: NSRect
    }

    private func layout(for panel: PalettePanel) -> Layout {
        let window = windowLayout(for: panel)
        func rect(_ box: PaletteWindowLayout.Box) -> NSRect { NSRect(x: box.x, y: box.y, width: box.width, height: box.height) }
        return Layout(body: rect(window.body), content: rect(window.content), search: rect(window.search), modes: window.modes.map(rect),
                      tabs: window.tabs.map(rect), heading: rect(window.heading), grid: rect(window.grid), scrollbar: rect(window.scrollbar),
                      separators: window.separators.map { CGFloat($0) }, preview: window.preview.map(rect), footer: rect(window.footer),
                      skinToneButton: rect(window.skinToneButton))
    }

    /// 今の種類
    private static func kind(of panel: PalettePanel) -> PaletteItem.Kind {
        panel.modes.first { $0.isSelected }?.kind ?? .emoji
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
        if let preview = layout.preview, panel.preview != nil, PalettePreviewDrawing.pinRect(in: preview).contains(point) { return .pin }
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
        // 動いているあいだは動いている部品の範囲だけを描き直すので，その範囲に掛からない部品は描かない
        if needsToDraw(layout.search) { drawSearch(panel, in: layout.search) }
        if needsToDraw(Self.union(layout.modes)) { drawModes(panel, in: layout.modes) }
        if needsToDraw(Self.union(layout.tabs)) { drawTabs(panel, in: layout.tabs) }
        if needsToDraw(layout.heading) { drawHeading(panel.heading, in: layout.heading) }
        if needsToDraw(layout.grid.union(layout.scrollbar).insetBy(dx: -Size.selectionStroke, dy: -Size.selectionStroke)) { drawGrid(panel, layout: layout) }
        // 区切りの線は中身の左の端から右の端まで
        for y in layout.separators where needsToDraw(NSRect(x: layout.content.minX, y: y.rounded(), width: layout.content.width,
                                                             height: DesignTokens.Size.Candidate.frameWidth)) {
            separator(y: y, from: layout.content.minX, to: layout.content.maxX)
        }
        if let preview = layout.preview, let shown = panel.preview, needsToDraw(preview) { drawPreview(shown, panel: panel, in: preview) }
        if needsToDraw(layout.footer) { drawFooter(panel, layout: layout) }
        if let picker = panel.skinTonePicker { drawPicker(picker, layout: layout) }
    }

    private static func union(_ rects: [NSRect]) -> NSRect {
        rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) }
    }

    // MARK: - 動き

    /// core が添えた動き(PalettePanel.Motion)から，滑る印・送る中身・弾む部品の動きを始める．
    /// 窓に出ていないとき・前の内容が無いとき・「視差効果を減らす」が有効なときは動かさない
    private func startMotion(from old: PalettePanel?) {
        // 大きさが決まる前(窓に入れる前)は，部品の位置が求められないので動かさない
        guard let panel, let old, !bounds.isEmpty, forcesMotion || (window != nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else {
            stopMotion()
            return
        }
        typealias Duration = DesignTokens.Motion.Palette
        let layout = layout(for: panel)
        let oldLayout = self.layout(for: old)
        let time = clock()
        let changes = panel.motion
        // 選択の枠．滑っている途中で次へ動いたら，今の位置から滑らせ直す
        if let from = changes.selectionFrom, panel.selection != nil {
            let previous = old.selection.map { cellRect(row: $0.row, column: $0.column, in: oldLayout, panel: old) }
            let current = motion.selection.flatMap { slide in previous.map { PaletteMotionState.rect(slide, to: $0, at: time, easing: PaletteEasing.easeOut) } }
            motion.selection = .init(from: current ?? cellRect(row: from.row, column: from.column, in: layout, panel: panel), start: time,
                                     duration: Duration.selection / 1000)
        } else if old.selection != panel.selection || changes.content != nil {
            motion.selection = nil
        }
        // 種類の切り替えの印
        if let from = changes.modeFrom, let index = panel.modes.firstIndex(where: { $0.kind == from }), layout.modes.indices.contains(index) {
            let previous = old.modes.firstIndex(where: \.isSelected).flatMap { oldLayout.modes.indices.contains($0) ? oldLayout.modes[$0] : nil }
            let current = motion.mode.flatMap { slide in previous.map { PaletteMotionState.rect(slide, to: $0, at: time, easing: PaletteEasing.easeInOut) } }
            motion.mode = .init(from: current ?? layout.modes[index], start: time, duration: Duration.indicator / 1000)
        }
        // まとまりのタブの印
        if let from = changes.tabFrom, let index = panel.tabs.firstIndex(where: { $0.section == from }), layout.tabs.indices.contains(index) {
            let previous = old.tabs.firstIndex(where: \.isSelected).flatMap { oldLayout.tabs.indices.contains($0) ? oldLayout.tabs[$0] : nil }
            let current = motion.tab.flatMap { slide in previous.map { PaletteMotionState.rect(slide, to: $0, at: time, easing: PaletteEasing.easeInOut) } }
            motion.tab = .init(from: current ?? layout.tabs[index], start: time, duration: Duration.indicator / 1000)
        } else if old.tabs.map(\.section) != panel.tabs.map(\.section) {
            motion.tab = nil
        }
        if let direction = changes.content {
            motion.content = .init(previous: old, direction: direction, start: time, duration: Duration.content / 1000)
            swapImages = nil
        }
        if changes.opensPicker {
            motion.picker = .init(start: time, duration: Duration.pop / 1000)
        } else if panel.skinTonePicker == nil {
            motion.picker = nil
        }
        if changes.togglesPin {
            motion.pin = .init(start: time, duration: Duration.pop / 1000)
        }
        if motion.isActive, displayLink == nil, window != nil {
            let link = displayLink(target: self, selector: #selector(stepMotion(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    private func stopMotion() {
        motion = PaletteMotionState()
        swapImages = nil
        displayLink?.invalidate()
        displayLink = nil
    }

    /// 画面のリフレッシュごとに，動いている部品の範囲だけを描き直す．動きが終わったら止める
    @objc private func stepMotion(_ link: CADisplayLink) {
        guard let panel else {
            stopMotion()
            return
        }
        let layout = layout(for: panel)
        let margin = Size.selectionStroke + 2
        if let slide = motion.selection, let to = panel.selection {
            setNeedsDisplay(slide.from.union(cellRect(row: to.row, column: to.column, in: layout, panel: panel)).insetBy(dx: -margin, dy: -margin))
        }
        if motion.mode != nil { setNeedsDisplay(Self.union(layout.modes)) }
        if motion.tab != nil { setNeedsDisplay(Self.union(layout.tabs)) }
        if motion.content != nil { setNeedsDisplay(layout.grid.insetBy(dx: -margin, dy: -margin)) }
        if motion.picker != nil, let picker = panel.skinTonePicker {
            setNeedsDisplay((layout.preview ?? .zero).union(Self.union(pickerCells(picker, in: layout))).insetBy(dx: -margin * 2, dy: -margin * 2))
        }
        if motion.pin != nil, let preview = layout.preview {
            setNeedsDisplay(PalettePreviewDrawing.pinRect(in: preview).insetBy(dx: -margin * 2, dy: -margin * 2))
        }
        motion.prune(at: clock())
        if motion.content == nil { swapImages = nil }
        if !motion.isActive {
            link.invalidate()
            displayLink = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopMotion() }
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
            icon.draw(in: NSRect(x: rect.minX + Size.controlPaddingX, y: (rect.midY - icon.size.height / 2).rounded(), width: icon.size.width, height: icon.size.height))
        }
        let caretWidth = Size.selectionStroke
        let textX = rect.minX + Size.controlPaddingX * 2 + iconSize + caretWidth
        let font = theme.candidateFont(size: Size.searchFontSize)
        let isEmpty = panel.query.isEmpty
        let text = isEmpty ? panel.placeholder : panel.query
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: isEmpty ? theme.textMuted : theme.text]
        let available = rect.maxX - textX - Size.controlPaddingX
        let shown = TextFitting.truncated(text, attributes: attributes, width: available)
        let size = shown.size(withAttributes: attributes)
        let y = (rect.midY - size.height / 2).rounded()
        shown.draw(at: NSPoint(x: textX, y: y), withAttributes: attributes)
        // 打った文字が探す欄に入ることを示す縦の線(入力位置)．空なら案内の文の前に置く
        let caretX = isEmpty ? textX - caretWidth * 2 : min(textX + size.width + 1, rect.maxX - Size.controlPaddingX)
        theme.selection.setFill()
        NSRect(x: caretX.rounded(), y: rect.midY - Size.searchFontSize / 2 - 1, width: caretWidth, height: Size.searchFontSize + 2).fill()
    }

    private func drawModes(_ panel: PalettePanel, in rects: [NSRect]) {
        guard let first = rects.first, let last = rects.last else { return }
        let whole = NSRect(x: first.minX, y: first.minY, width: last.maxX - first.minX, height: first.height)
        fill(whole, color: theme.badge, radius: Size.searchRadius)
        let font = theme.labelFont(size: Size.modeFontSize)
        for (mode, rect) in zip(panel.modes, rects) {
            GlassDrawing.drawCentered(mode.title, attributes: [.font: font, .foregroundColor: theme.textMuted], in: rect)
        }
        guard let selected = panel.modes.firstIndex(where: \.isSelected), rects.indices.contains(selected) else { return }
        // 選んでいる種類の印．切り替えたら前の種類から滑らせ，印に重なった文字だけを選択の文字の色で描き直す
        // (印が滑るあいだ，文字の色も印の端で切り替わる)
        let pill = PaletteMotionState.rect(motion.mode, to: rects[selected], at: clock(), easing: PaletteEasing.easeInOut).insetBy(dx: Size.inset, dy: Size.inset)
        fill(pill, color: theme.selection, radius: Size.searchRadius - Size.inset)
        NSGraphicsContext.saveGraphicsState()
        (theme.isRounded ? NSBezierPath(roundedRect: pill, xRadius: Size.searchRadius - Size.inset, yRadius: Size.searchRadius - Size.inset)
            : NSBezierPath(rect: pill)).addClip()
        for (mode, rect) in zip(panel.modes, rects) where rect.intersects(pill) {
            GlassDrawing.drawCentered(mode.title, attributes: [.font: font, .foregroundColor: theme.selectionText], in: rect)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawTabs(_ panel: PalettePanel, in rects: [NSRect]) {
        // 選んでいるまとまりの印．まとまりが変わったら前のタブから滑らせる
        if let selected = panel.tabs.firstIndex(where: \.isSelected), rects.indices.contains(selected) {
            let rect = PaletteMotionState.rect(motion.tab, to: rects[selected], at: clock(), easing: PaletteEasing.easeInOut)
            if theme.isRounded {
                // 角丸のテーマは薄い地と下の線で示す
                fill(rect.insetBy(dx: Size.inset, dy: Size.inset), color: theme.focusTint, radius: Glass.selectionRadius)
                theme.selection.setFill()
                NSRect(x: rect.minX + Size.itemGap, y: rect.maxY - Size.selectionStroke, width: rect.width - Size.itemGap * 2, height: Size.selectionStroke).fill()
            } else {
                // platinum と desk は選択の色の枠と下の線で示す．塗ってアイコンを選択の文字の色にすると，
                // 選択の文字の色が暗いテーマ(desk)では SF Symbols の顔の中まで塗られて見分けられない
                stroke(rect.insetBy(dx: Size.inset, dy: Size.inset), color: theme.selection, radius: 0, width: DesignTokens.Size.Candidate.frameWidth)
                theme.selection.setFill()
                NSRect(x: rect.minX + Size.itemGap, y: rect.maxY - Size.selectionStroke - Size.inset, width: rect.width - Size.itemGap * 2,
                       height: Size.selectionStroke).fill()
            }
        }
        for (tab, rect) in zip(panel.tabs, rects) {
            let color = tab.isSelected ? theme.text : theme.textMuted
            if let name = PaletteIcons.symbolName(for: tab.section),
               let image = SymbolImageCache.image(name, pointSize: Size.tabIconSize, weight: tab.isSelected ? .semibold : .regular, color: color) {
                image.draw(in: NSRect(x: (rect.midX - image.size.width / 2).rounded(), y: (rect.midY - image.size.height / 2).rounded(),
                                      width: image.size.width, height: image.size.height))
            } else {
                // 顔文字のまとまりの短い顔はタブの幅に収まるよう縮める
                drawFitted(tab.symbol, size: Size.tabIconSize + DesignTokens.Size.Candidate.frameWidth, color: color, in: rect.insetBy(dx: Size.inset, dy: 0))
            }
        }
    }

    private func drawHeading(_ text: String, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.textMuted]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: rect.minX, y: (rect.midY - size.height / 2).rounded()), withAttributes: attributes)
    }

    private func drawGrid(_ panel: PalettePanel, layout: Layout) {
        let time = clock()
        if let swap = motion.content {
            // 中身を送る．前の中身を送る向きへ出ていかせながら薄くし，今の中身を手前から入れながら濃くする
            let t = PaletteEasing.easeOut(PaletteMotionState.progress(swap.start, swap.duration, at: time))
            let (dx, dy): (CGFloat, CGFloat) = switch swap.direction {
            case .next: (1, 0)
            case .previous: (-1, 0)
            case .down: (0, 1)
            case .up: (0, -1)
            }
            let shift = Size.contentShift
            let area = layout.grid.insetBy(dx: -Size.selectionStroke, dy: -Size.selectionStroke)
            if swapImages == nil, let previous = cellsImage(swap.previous, layout: layout, area: area), let current = cellsImage(panel, layout: layout, area: area) {
                swapImages = (previous, current)
            }
            NSGraphicsContext.saveGraphicsState()
            area.clip()
            if let images = swapImages {
                images.previous.draw(in: area.offsetBy(dx: -dx * shift * t, dy: -dy * shift * t), from: .zero, operation: .sourceOver, fraction: 1 - t,
                                     respectFlipped: true, hints: nil)
                images.current.draw(in: area.offsetBy(dx: dx * shift * (1 - t), dy: dy * shift * (1 - t)), from: .zero, operation: .sourceOver, fraction: t,
                                    respectFlipped: true, hints: nil)
            } else {
                drawCells(swap.previous, layout: layout, offset: CGPoint(x: -dx * shift * t, y: -dy * shift * t), alpha: 1 - t, time: time)
                drawCells(panel, layout: layout, offset: CGPoint(x: dx * shift * (1 - t), y: dy * shift * (1 - t)), alpha: t, time: time)
            }
            NSGraphicsContext.restoreGraphicsState()
        } else {
            drawCells(panel, layout: layout, offset: .zero, alpha: 1, time: time)
        }
        if let message = panel.message {
            let attributes: [NSAttributedString.Key: Any] = [.font: theme.labelFont(size: Size.detailFontSize), .foregroundColor: theme.textMuted]
            GlassDrawing.drawCentered(message, attributes: attributes, in: layout.grid)
        }
        drawScrollbar(panel, in: layout.scrollbar)
    }

    /// panel のマス目(線・選択の枠・文字)を，area の大きさの透明な画像に描く．画面と同じ細かさ(Retina なら 2 倍)で描く
    private func cellsImage(_ panel: PalettePanel, layout: Layout, area: NSRect) -> NSImage? {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard area.width > 0, area.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((area.width * scale).rounded(.up)), pixelsHigh: Int((area.height * scale).rounded(.up)),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let bitmap = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = area.size
        let context = bitmap.cgContext
        // view と同じ，上が 0 の座標で描く
        context.translateBy(x: 0, y: area.height * scale)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -area.minX, y: -area.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        rendersOffscreen = true
        drawCells(panel, layout: layout, offset: .zero, alpha: 1, time: clock(), slidesSelection: false)
        rendersOffscreen = false
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: area.size)
        image.addRepresentation(rep)
        return image
    }

    /// 描き直す範囲に掛かるか．マス目を画像に描いているときは，すべてを描く
    private func shouldDraw(_ rect: NSRect) -> Bool {
        rendersOffscreen || needsToDraw(rect)
    }

    /// マス目の線・選択の枠・文字を描く．offset だけずらし，alpha の濃さで描く(中身を送るとき)．
    /// 一部だけを描き直すときは，描き直す範囲に掛からないマスを描かない
    private func drawCells(_ panel: PalettePanel, layout: Layout, offset: CGPoint, alpha: CGFloat, time: CFTimeInterval, slidesSelection: Bool = true) {
        guard alpha > 0 else { return }
        let symbolFont = theme.candidateFont(size: (cellSize * Size.symbolScale).rounded())
        let isWide = Self.isWide(panel)
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.setAlpha(alpha)
        context?.translateBy(x: offset.x, y: offset.y)
        defer { context?.restoreGState() }
        if let selection = panel.selection {
            // 色だけに頼らないよう，地を塗ったうえで枠も描く．選択が動いたら前のマスから滑らせる
            let target = cellRect(row: selection.row, column: selection.column, in: layout, panel: panel)
            let rect = slidesSelection && offset == .zero ? PaletteMotionState.rect(motion.selection, to: target, at: time, easing: PaletteEasing.easeOut) : target
            let inner = rect.insetBy(dx: 1, dy: 1)
            if shouldDraw(inner.offsetBy(dx: offset.x, dy: offset.y).insetBy(dx: -Size.selectionStroke, dy: -Size.selectionStroke)) {
                fill(inner, color: theme.focusTint, radius: Size.cellRadius)
                stroke(inner, color: theme.selection, radius: Size.cellRadius, width: Size.selectionStroke)
            }
        }
        for row in panel.rows {
            if row.startsSection, row.index != panel.firstRow {
                // まとまりの境目に細い線を引く
                let y = layout.grid.minY + CGFloat(row.index - panel.firstRow) * cellSize
                let line = NSRect(x: layout.grid.minX + Size.cellRadius, y: y.rounded(), width: layout.grid.width - Size.cellRadius * 2, height: DesignTokens.Size.Candidate.frameWidth)
                if shouldDraw(line.offsetBy(dx: offset.x, dy: offset.y)) {
                    theme.line.setFill()
                    line.fill()
                }
            }
            for (column, cell) in row.cells.enumerated() {
                let rect = cellRect(row: row.index, column: column, in: layout, panel: panel)
                guard shouldDraw(rect.offsetBy(dx: offset.x, dy: offset.y)) else { continue }
                if isWide {
                    // 顔文字は絵文字を含んでいても文字の書体で描く(顔の形を崩さない)
                    drawFitted(cell.text, size: (cellSize * Size.kaomojiScale).rounded(), color: theme.text, in: rect.insetBy(dx: Size.kaomojiPaddingX, dy: 0))
                    continue
                }
                if Self.isEmoji(cell.text) {
                    // 絵文字は外形がマスの余白の内側に収まる大きさにし，外形の中心をマスの中心に合わせる(横に広い絵文字も欠けない)
                    drawEmoji(cell.text, in: rect, padding: Size.cellPadding)
                } else {
                    GlassDrawing.drawCentered(cell.text, attributes: [.font: symbolFont, .foregroundColor: theme.text], in: rect)
                }
            }
        }
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

    /// 説明の欄．左に選んでいる文字の大きな見本，右に名前と「項目名 → 値」の表(PalettePreviewDrawing)．
    /// ピン留めのボタンは見出しの行の縦の中心に置く
    private func drawPreview(_ preview: PalettePanel.Preview, panel: PalettePanel, in rect: NSRect) {
        let side = Size.tileSize
        var tile = NSRect(x: rect.minX, y: rect.minY, width: side, height: side)
        let kind = Self.kind(of: panel)
        if kind.cellShape == .wide {
            // 顔文字は横に長いので，文字の幅に合わせて四角を広げる(説明の欄の幅の一定の割合まで)
            let width = preview.text.size(withAttributes: [.font: theme.candidateFont(size: Size.previewKaomojiFontSize)]).width + Size.tilePadding * 2
            tile.size.width = min(max(tile.width, width.rounded(.up)), (rect.width * Size.previewKaomojiWidth).rounded())
            fill(tile, color: theme.badge, radius: Size.cellRadius)
            drawFitted(preview.text, size: Size.previewKaomojiFontSize, color: theme.text, in: tile.insetBy(dx: Size.kaomojiPaddingX, dy: 0))
        } else {
            fill(tile, color: theme.badge, radius: Size.cellRadius)
            if Self.isEmoji(preview.text) {
                // 絵文字は外形が四角の余白の内側に収まる大きさにし，外形の中心を四角の中心に合わせる
                drawEmoji(preview.text, in: tile, padding: Size.tilePadding)
            } else {
                let font = theme.candidateFont(size: Size.previewGlyphSize * Size.symbolScale * Size.previewSymbolBoost)
                preview.text.draw(at: glyphs.origin(preview.text, font: font, centeredIn: tile), withAttributes: [.font: font, .foregroundColor: theme.text])
            }
        }
        PalettePreviewDrawing.draw(preview, fields: panel.previewFields, kind: kind, area: rect, tile: tile, theme: theme)
        let pin = PalettePreviewDrawing.pinRect(in: rect)
        if let image = SymbolImageCache.image(preview.isPinned ? "pin.fill" : "pin", pointSize: Size.tabIconSize, weight: .regular,
                                              color: preview.isPinned ? theme.selection : theme.textMuted) {
            // ピン留めを切り替えたら，ピンを一度大きくして弾ませる
            let scale = motion.pin.map { 1 + (Size.pinBounce - 1) * PaletteEasing.bounce(PaletteMotionState.progress($0.start, $0.duration, at: clock())) } ?? 1
            let width = image.size.width * scale
            let height = image.size.height * scale
            image.draw(in: NSRect(x: pin.midX - width / 2, y: pin.midY - height / 2, width: width, height: height))
        }
    }

    /// 絵文字を，外形が box から上下左右に padding を除いた中に収まる大きさで，外形の中心を box の中心に合わせて描く
    private func drawEmoji(_ text: String, in box: NSRect, padding: CGFloat) {
        let font = glyphs.font(text, named: PaletteIcons.emojiFontName, fitting: box, padding: padding)
        text.draw(at: glyphs.origin(text, font: font, centeredIn: box), withAttributes: [.font: font])
    }

    /// 足元．キーの案内と，右の端に既定の肌の色のボタン(キーの札と同じ高さ・縦の中心)
    private func drawFooter(_ panel: PalettePanel, layout: Layout) {
        let footer = layout.footer
        let hints = panel.hints.map { KeyHint(key: $0.key, label: $0.action) }
        let fitting = GlassDrawing.hints(hints, fitting: footer.width - layout.skinToneButton.width - Size.groupGap, theme: theme)
        GlassDrawing.drawHints(fitting, x: footer.minX, midY: footer.midY, theme: theme)
        let button = layout.skinToneButton
        GlassDrawing.drawKeycap(button, theme: theme)
        // 余白は札の縁(platinum と desk は立体の縁)の内側から測る．キーの札の中の記号と同じ余白
        let border = GlassDrawing.keycapBorder(theme: theme)
        drawEmoji(PaletteStrings.skinToneSample.text(skinTone: panel.skinTone), in: button.insetBy(dx: border, dy: border), padding: Size.skinButtonPadding)
    }

    private func drawPicker(_ picker: PalettePanel.SkinTonePicker, layout: Layout) {
        let cells = pickerCells(picker, in: layout)
        guard let first = cells.first, let last = cells.last else { return }
        let margin = Size.itemGap
        let strip = NSRect(x: first.minX, y: first.minY, width: last.maxX - first.minX, height: first.height).insetBy(dx: -margin, dy: -margin)
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        defer { context?.restoreGState() }
        // 開いたら，覆いと帯を薄い形から濃くし，帯は少し小さい形から少し行き過ぎて元の大きさへ浮かび上がらせる
        let pop = motion.picker.map { PaletteMotionState.progress($0.start, $0.duration, at: clock()) }
        if let t = pop { context?.setAlpha(PaletteEasing.easeOut(min(t * 2, 1))) }
        // 下の説明の文字が帯のまわりに見えないよう，説明の欄ごと(上の区切りの線の下から)面の色で覆う
        if let preview = layout.preview, let line = layout.separators.first {
            theme.surface.withAlphaComponent(1).setFill()
            let top = line.rounded() + DesignTokens.Size.Candidate.frameWidth
            NSRect(x: preview.minX, y: top, width: preview.width, height: preview.maxY - top).fill()
        }
        if let t = pop {
            let scale = Size.popScale + (1 - Size.popScale) * PaletteEasing.overshoot(t)
            context?.translateBy(x: strip.midX, y: strip.midY)
            context?.scaleBy(x: scale, y: scale)
            context?.translateBy(x: -strip.midX, y: -strip.midY)
        }
        fill(strip, color: theme.surface.withAlphaComponent(1), radius: Size.searchRadius)
        stroke(strip, color: theme.frame, radius: Size.searchRadius, width: DesignTokens.Size.Candidate.frameWidth)
        for (index, (option, rect)) in zip(picker.options, cells).enumerated() {
            if index == picker.selected {
                let inner = rect.insetBy(dx: DesignTokens.Size.Candidate.frameWidth, dy: DesignTokens.Size.Candidate.frameWidth)
                fill(inner, color: theme.focusTint, radius: Size.cellRadius)
                stroke(inner, color: theme.selection, radius: Size.cellRadius, width: Size.selectionStroke)
            }
            drawEmoji(option, in: rect, padding: Size.cellPadding)
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
