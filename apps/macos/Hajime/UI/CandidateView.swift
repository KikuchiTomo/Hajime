import AppKit
import HajimeApplication
import HajimeDomain

/// 候補ウィンドウの中身を描く．上から，文字種の行・候補・足元の 3 つの区画．
/// 連想の一覧(R-18)では，文字種の行の代わりに見出し(元の語と意味の説明)の行を出す
final class CandidateView: NSView {
    private typealias Size = DesignTokens.Size.Candidate
    private typealias Glass = DesignTokens.Size.Glass
    private typealias Meaning = DesignTokens.Size.Meaning

    var panel: CandidatePanel? {
        didSet {
            updateReservedCard()
            needsDisplay = true
        }
    }
    /// 足元の案内に出すキーの割り当て
    var keys = KeymapPreset.standard.keymap { didSet { needsDisplay = true } }
    /// 足元にキーの案内を出すか(設定の「キーの案内を表示」)
    var showsHints = true { didSet { needsDisplay = true } }
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

    /// 区画の寸法．行の間隔は文字の大きさに合わせて変える
    private var metrics: CandidateListLayout.Metrics {
        let scale = fontSize / Size.fontSize
        if theme.isRounded {
            let footer = max(Glass.keycapHeight, Glass.noteIconSize, (labelFont.ascender - labelFont.descender).rounded(.up))
            return .rounded(rowPitch: (Glass.rowHeight * scale).rounded(), headerHeight: Glass.headerHeight, footerHeight: footer)
        }
        let section = max((labelFont.ascender - labelFont.descender).rounded(.up), Glass.keycapHeight) + Size.sectionPaddingY * 2
        return .bevel(rowPitch: (Size.rowHeight * scale).rounded(), sectionHeight: section, hasShadow: theme.hasDropShadow)
    }

    /// 行の地の内側の左右の余白．番号の丸(番号)の左と注釈の札の右，足元の案内と位置の左右の端をここにそろえる
    private var rowPaddingX: CGFloat { theme.isRounded ? Glass.rowPaddingX : Size.paddingX }
    /// 番号の幅(番号から候補の文字まで)
    private var lead: CGFloat { theme.isRounded ? Glass.badgeSize + Size.paddingX : Size.indexWidth }

    // MARK: - 語の意味

    /// 語の意味(R-08)の置き方と中身．layout が nil なら，意味の無い候補を選んでいるあいだ空けておく場所
    private struct MeaningSlot {
        var placement: MeaningPlacement
        var layout: MeaningCardDrawing.Layout?
        /// 目印の列の左の端と見出しの行の縦の真ん中
        var position: MeaningCardLayout.Placement
        /// 場所の大きさ(platinum と desk は下の余白を含む)
        var size: NSSize
    }

    /// 候補の右に出した語の意味の場所．同じ候補の並びのあいだは，意味の無い候補(ひらがなの候補など)を選んでも場所を空けたままにし，
    /// 窓の幅と高さを変えない(候補を移るたびに窓の縁が動かないように)
    private var reservedCard: (entries: [String], height: CGFloat)?

    /// 候補の右: 目印の列は場所の左の端，見出しの行は候補の 1 行目の地の真ん中
    private var sidePosition: MeaningCardLayout.Placement {
        .init(left: 0, headerMidY: (metrics.rowPitch - metrics.rowInset * 2) / 2)
    }

    /// 候補の下: 目印の列を候補の番号に，文の列を候補の文字にそろえる．見出しの行は場所の上の端から
    private var belowPosition: MeaningCardLayout.Placement {
        .init(left: rowPaddingX + lead - Meaning.markerWidth - Meaning.markerGap,
              headerMidY: sectionPadding + MeaningCardDrawing.headerHeight(theme: theme) / 2)
    }

    /// platinum と desk は区画どうしを線で区切って空きを取らないので，語の意味の上と下に文字の行と同じ余白を足す
    private var sectionPadding: CGFloat { theme.isRounded ? 0 : Size.sectionPaddingY }

    private func updateReservedCard() {
        guard let panel, panel.meaningPlacement == .side else {
            reservedCard = nil
            return
        }
        let entries = panel.entries.map(\.text)
        let height = panel.homophone.map {
            MeaningCardDrawing.layout($0, width: Meaning.listWidth, placement: sidePosition, theme: theme).size.height + sectionPadding
        }
        if let reserved = reservedCard, reserved.entries == entries {
            reservedCard = (entries, max(reserved.height, height ?? 0))
        } else {
            reservedCard = height.map { (entries, $0) }
        }
    }

    /// 候補の右の語の意味．下の語の意味は窓の中身の幅で折り返すので，幅が決まってから作る(belowSlot)
    private func sideSlot(for panel: CandidatePanel) -> MeaningSlot? {
        guard panel.meaningPlacement == .side else { return nil }
        let position = sidePosition
        let layout = panel.homophone.map { MeaningCardDrawing.layout($0, width: Meaning.listWidth, placement: position, theme: theme) }
        let reserved = reservedCard?.entries == panel.entries.map(\.text) ? reservedCard?.height : nil
        guard layout != nil || reserved != nil else { return nil }
        let height = max((layout?.size.height).map { $0 + sectionPadding } ?? 0, reserved ?? 0)
        return MeaningSlot(placement: .side, layout: layout, position: position, size: NSSize(width: Meaning.listWidth, height: height))
    }

    private func belowSlot(for panel: CandidatePanel, width: CGFloat) -> MeaningSlot? {
        guard panel.meaningPlacement == .below, let note = panel.homophone else { return nil }
        let position = belowPosition
        let layout = MeaningCardDrawing.layout(note, width: width, placement: position, theme: theme)
        return MeaningSlot(placement: .below, layout: layout, position: position,
                           size: NSSize(width: layout.size.width, height: layout.size.height + sectionPadding))
    }

    // MARK: - 大きさと区画

    /// 候補の列(行の地)の幅．足元とカードを除く．表に広げていれば，すべての列と列のあいだの線を合わせた幅
    private func listWidth(for panel: CandidatePanel) -> CGFloat {
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: labelFont]
        let variantsWidth = panel.variants.reduce(CGFloat(0)) { width, variant in
            width + variant.label.size(withAttributes: labelAttributes).width + Size.variantPaddingX * 2
        } + (rowPaddingX - Size.variantPaddingX) * 2
        let headingWidth = panel.association.map { AssociationHeadingDrawing.width($0, font: labelFont, emphasis: labelFont) + rowPaddingX * 2 } ?? 0
        let columns = CGFloat(panel.columnCount)
        let entriesWidth = cellWidth(for: panel) * columns + Size.frameWidth * (columns - 1)
        return max(Size.minWidth, entriesWidth, variantsWidth, headingWidth).rounded(.up)
    }

    /// 候補 1 つの行の地の幅．左の余白・番号・文字・添え書き・右の余白(文字の右は番号の左より広く空ける)．
    /// 表ではすべての列を同じ幅にそろえ，窓が幅の上限に収まらなければ列を狭めて，収まらない候補は末尾を省く
    private func cellWidth(for panel: CandidatePanel) -> CGFloat {
        let textAttributes: [NSAttributedString.Key: Any] = [.font: candidateFont]
        let entryWidth = panel.entries.map { entry in
            let annotation = entry.annotation.map { NoteDrawing.tagWidth($0, theme: theme) + Size.paddingX } ?? 0
            let icon = entry.command == nil ? 0 : CommandDrawing.width
            return icon + entry.text.size(withAttributes: textAttributes).width + annotation
        }.max() ?? 0
        let natural = (rowPaddingX + lead + entryWidth + Size.paddingX).rounded(.up)
        guard panel.columnLength != nil else { return natural }
        // 列の位置を整数にそろえる．文字が収まる幅は切り上げ，上限から割った幅は切り捨てる(文字を 1 ドット足りずに省かないように)
        let columns = CGFloat(panel.columnCount)
        let outer = (metrics.edge + metrics.padding) * 2 + metrics.shadow
        let available = (max(maximumWidth, Size.minWidth) - outer - Size.frameWidth * (columns - 1)) / columns
        return min(natural, available.rounded(.down))
    }

    /// 候補を縦に並べる行の数．表なら 1 列の候補の数(最後のページで候補が少なければその数)
    private func rowCount(for panel: CandidatePanel) -> Int {
        guard let length = panel.columnLength, length > 0 else { return panel.entries.count }
        return min(panel.entries.count, length)
    }

    private func footerWidth(for panel: CandidatePanel) -> CGFloat {
        let footer = footerContent(for: panel)
        return (hintsWidth(footer) + footer.position.size(withAttributes: [.font: labelFont]).width + rowPaddingX * 2 + Glass.hintGap).rounded(.up)
    }

    /// 区画の配置と，そこに出すカード．size は窓の大きさを外から決めるとき(描くときと押した位置を調べるときは今の大きさ)
    private func placement(for panel: CandidatePanel, size: NSSize? = nil) -> (layout: CandidateListLayout, slot: MeaningSlot?) {
        let list = listWidth(for: panel)
        let footer = footerWidth(for: panel)
        let metrics = metrics
        let style: CandidateListLayout.Style = theme.isRounded ? .rounded : .bevel
        let hasHeader = panel.association != nil || !panel.variants.isEmpty
        let limit = max(maximumWidth, Size.minWidth)
        var slot = sideSlot(for: panel)
        var card = slot.map { CandidateListLayout.Card.side(width: $0.size.width, height: $0.size.height) }
        if slot == nil, panel.meaningPlacement == .below, panel.homophone != nil {
            // 下のカードは窓の中身の幅いっぱい．窓の幅の上限を超えるなら上限に収める
            let outer = (metrics.edge + metrics.padding) * 2 + metrics.shadow
            let width = min(CandidateListLayout.belowCardWidth(listWidth: list, footerWidth: footer, minimum: Meaning.listWidth), limit - outer).rounded(.down)
            slot = belowSlot(for: panel, width: width)
            card = slot.map { .below(width: $0.size.width, height: $0.size.height) }
        }
        let layout = CandidateListLayout(style: style, listWidth: list, footerWidth: footer, hasHeader: hasHeader, rowCount: rowCount(for: panel),
                                         card: card, maximumWidth: limit, metrics: metrics, size: size.map { (Double($0.width), Double($0.height)) })
        return (layout, slot)
    }

    func fittingSize(for panel: CandidatePanel) -> NSSize {
        let layout = placement(for: panel).layout
        return NSSize(width: layout.width, height: layout.height)
    }

    // MARK: - 押した位置

    /// 押した対象を知らせる先(候補の窓をマウスで押したとき)
    var onChoose: ((PointerTarget) -> Void)?

    /// 候補ごとの行の地と押せる範囲，表の列のあいだの縦の線
    private struct Cells {
        var rows: [NSRect]
        var hitRows: [NSRect]
        var separators: [NSRect]
    }

    /// 候補ごとの枠．表では上から下へ詰め，列を左から右へ並べる．列のあいだは 1 ドットの縦の線で区切る．
    /// 表でなければ，配置の候補の行をそのまま使う
    private func cells(for panel: CandidatePanel, layout: CandidateListLayout) -> Cells {
        let rows = layout.rows.map(NSRect.init), hits = layout.hitRows.map(NSRect.init)
        guard let length = panel.columnLength, length > 0, let first = rows.first, let last = rows.last else {
            return Cells(rows: rows, hitRows: hits, separators: [])
        }
        let columns = panel.columnCount
        let gaps = Size.frameWidth * CGFloat(columns - 1)
        let cell = min(cellWidth(for: panel), ((first.width - gaps) / CGFloat(columns)).rounded(.down))
        let x = { (column: Int) in first.minX + CGFloat(column) * (cell + Size.frameWidth) }
        let place = { (row: NSRect, index: Int) in NSRect(x: x(index / length), y: row.minY, width: cell, height: row.height) }
        // 縦の線は行の地の上の端から下の端まで(glass は行と行のあいだの空きの分だけ短くなる)
        let separators = (1..<max(columns, 1)).map { NSRect(x: x($0) - Size.frameWidth, y: first.minY, width: Size.frameWidth, height: last.maxY - first.minY) }
        return Cells(rows: panel.entries.indices.map { place(rows[$0 % length], $0) },
                     hitRows: panel.entries.indices.map { place(hits[$0 % length], $0) }, separators: separators)
    }

    /// 字種の行の 1 つずつの枠(行の高さいっぱい)．最初の字種の文字を候補の番号の左にそろえる
    private func variantCells(_ panel: CandidatePanel, in rect: NSRect) -> [NSRect] {
        var x = rect.minX + rowPaddingX - Size.variantPaddingX
        return panel.variants.map { variant in
            let width = variant.label.size(withAttributes: [.font: labelFont]).width + Size.variantPaddingX * 2
            defer { x += width }
            return NSRect(x: x, y: rect.minY, width: width, height: rect.height)
        }
    }

    /// 候補の行の札の右端(行の地の内側の余白の内側．足元の位置の右の端と同じ x)
    private func tagMaxX(in row: NSRect) -> CGFloat { row.maxX - rowPaddingX }

    /// ユーザー辞書の語のコメントの札を押せる範囲．コメントの札の無い行は nil
    private func commentRect(_ entry: CandidatePanel.Entry, in row: NSRect) -> NSRect? {
        entry.comment.map { NoteDrawing.tagHitRect($0, maxX: tagMaxX(in: row), row: row, theme: theme) }
    }

    /// point(この view の座標)にある押せる対象．無ければ nil．
    /// コメントの札は行の中にあるので，行より先に調べる(札を押すと候補の代わりにコメントを入れる)
    func target(at point: NSPoint) -> PointerTarget? {
        guard let panel else { return nil }
        let layout = placement(for: panel, size: bounds.size).layout
        let hitRows = cells(for: panel, layout: layout).hitRows
        if let row = hitRows.firstIndex(where: { $0.contains(point) }) {
            // 札を押せる範囲は，候補の行と同じく行と行のあいだまで(札の右の端は行の地の内側)
            if let comment = commentRect(panel.entries[row], in: hitRows[row]), comment.contains(point) { return .comment(row) }
            return .entry(row)
        }
        if panel.association == nil, let header = layout.header,
           let cell = variantCells(panel, in: NSRect(header)).firstIndex(where: { $0.contains(point) }), panel.variants[cell].isAvailable {
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
        let (layout, slot) = placement(for: panel, size: bounds.size)
        let body = NSRect(layout.body)
        if theme.isRounded {
            GlassDrawing.drawFrame(in: body, theme: theme, fillsSurface: fillsSurface)
        } else {
            BevelDrawing.drawDropShadow(for: body, theme: theme)
            BevelDrawing.drawPanel(in: body, theme: theme)
        }
        if let header = layout.header.map(NSRect.init) {
            if let heading = panel.association {
                let row = header.insetBy(dx: rowPaddingX, dy: 0)
                AssociationHeadingDrawing.draw(heading, in: row, theme: theme, font: labelFont, emphasis: labelFont)
            } else {
                drawVariants(panel, in: header)
            }
        }
        if let line = layout.headerSeparator { drawLine(NSRect(line)) }
        let cells = cells(for: panel, layout: layout)
        cells.separators.forEach(drawLine)
        for (index, (entry, row)) in zip(panel.entries, cells.rows).enumerated() {
            drawEntry(entry, index: index, panel: panel, in: row)
        }
        if let slot, let card = layout.card.map(NSRect.init) {
            if let line = layout.cardSeparator { drawLine(NSRect(line)) }
            if let meaning = slot.layout {
                MeaningCardDrawing.drawContent(meaning, in: card, theme: theme)
                // 候補の右に出すときは，選んでいる候補の行の右の端から語の意味の見出しへ線でつなぐ
                // 表では，選んでいる候補の行の高さで候補の列の右の端から引く(ほかの列の候補にかからないように)
                if slot.placement == .side, let selected = panel.selectedEntry, panel.focus == .candidate, cells.rows.indices.contains(selected),
                   let listMaxX = layout.rows.first.map({ NSRect($0).maxX }) {
                    let row = cells.rows[selected]
                    MeaningCardDrawing.drawConnector(from: NSPoint(x: listMaxX, y: row.midY.rounded()),
                                                     to: NSPoint(x: MeaningCardDrawing.connectorEndX(in: card, placement: slot.position),
                                                                 y: (card.minY + slot.position.headerMidY).rounded()),
                                                     theme: theme)
                }
            } else {
                MeaningCardDrawing.drawEmpty(in: card, placement: slot.position, theme: theme)
            }
        }
        drawLine(NSRect(layout.footerSeparator))
        drawFooter(panel, in: NSRect(layout.footer))
    }

    /// 区切りの線(1 ドット)
    private func drawLine(_ rect: NSRect) {
        theme.line.setFill()
        rect.fill()
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
                GlassDrawing.fillCapsule(rect, color: theme.selection)
            } else {
                theme.selection.setFill()
                rect.fill()
            }
        }
        let opacity: CGFloat = (isSelected || index == 0) ? 1 : restOpacity
        let textColor = (isSelected ? theme.selectionText : theme.text).withAlphaComponent(opacity)
        let mutedColor = (isSelected ? theme.selectionText : theme.textMuted).withAlphaComponent(opacity)
        // 表では選んでいる列にだけ番号を振る(番号キーはその列の中で選ぶ)．ほかの列は番号の場所を空けたままにし，列を移っても文字を動かさない．
        // 番号キーで選べない窓(選び始める前の入力中の候補など)では番号を振らない．
        // 文字の位置は変えない(選び始めて番号が出たときに候補が横に動かないように)
        let number = panel.number(ofEntry: index).map(String.init)
        let numberX = rect.minX + rowPaddingX
        var textX = numberX + lead
        if let number {
            if theme.isRounded {
                let center = NSPoint(x: numberX + Glass.badgeSize / 2, y: rect.midY)
                GlassDrawing.drawBadge(number, center: center, theme: theme, selected: isSelected, opacity: opacity)
            } else {
                drawText(number, attributes: [.font: labelFont, .foregroundColor: mutedColor], x: numberX, in: rect)
            }
        }
        if let kind = entry.command {
            // コマンドの候補は，文字の前に種類のアイコンを置く
            CommandDrawing.drawIcon(kind, x: textX, midY: rect.midY, theme: theme, selected: isSelected, opacity: opacity)
            textX += CommandDrawing.width
        }
        let annotationWidth = entry.annotation.map { NoteDrawing.tagWidth($0, theme: theme) + Size.paddingX } ?? 0
        let textAttributes: [NSAttributedString.Key: Any] = [.font: candidateFont, .foregroundColor: textColor]
        let available = rect.maxX - rowPaddingX - annotationWidth - textX
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
            let offset = theme.isRounded ? Glass.underlineOffset - Glass.selectionInsetY : DesignTokens.Size.Branch.underlineOffset
            let color = (isSelected ? theme.selectionText : theme.correction).withAlphaComponent(opacity)
            GlassDrawing.drawUnderline(from: from, to: to, y: rect.maxY - offset, color: color, dotted: true, theme: theme)
        }
        if let annotation = entry.annotation {
            NoteDrawing.drawTag(annotation, maxX: tagMaxX(in: rect), midY: rect.midY, theme: theme, selected: isSelected,
                                command: entry.command != nil)
        }
    }

    // MARK: - 足元

    private struct Footer {
        var hints: [KeyHint]
        var note: Note?
        var position: String
        /// 選んでいる候補に連想があるときの知らせ(R-18)のうち，キーの割り当てが無いときの語．キーがあればキーキャップの札として hints に入れる
        var associationHint: String?
    }

    /// 何番目の候補か．まだ選んでいない(入力中の候補の窓で選び始める前の)ときは出さない
    private func position(of panel: CandidatePanel) -> String {
        panel.position == 0 ? "" : UIStrings.Candidate.position(panel.position, panel.total)
    }

    private func footerContent(for panel: CandidatePanel) -> Footer {
        // キーはキー設定の表で，変換中にそのコマンドに割り当てた最初のキー(R-17)．どの案内を出すかは core の表(IndicatorLabels)
        var hints = showsHints ? KeyHint.make(IndicatorLabels.listHints(for: panel), keymap: keys) : []
        if panel.association != nil {
            return Footer(hints: hints, note: panel.note, position: position(of: panel))
        }
        if panel.focus == .variants {
            let position = UIStrings.Candidate.variantsPosition(panel.selectedVariant.map { $0 + 1 } ?? 1, panel.variants.count)
            return Footer(hints: hints, note: panel.note, position: position)
        }
        var associationText: String?
        if let hint = panel.associationHint {
            if let key = hint.key { hints.append(KeyHint(key: key, label: hint.label)) } else { associationText = hint.label }
        }
        return Footer(hints: hints, note: panel.note, position: position(of: panel), associationHint: associationText)
    }

    private func hintsWidth(_ footer: Footer) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont]
        if let note = footer.note { return NoteDrawing.width(note, theme: theme) }
        let extra = footer.associationHint.map { $0.size(withAttributes: attributes).width + Glass.hintGap } ?? 0
        return GlassDrawing.hintsWidth(footer.hints, theme: theme) + extra
    }

    /// glass は案内を左，位置を右．platinum と desk は位置を左，案内を右(漢字Talk 7 の候補ウィンドウにならう)．
    /// 左右の端は候補の行の番号の左と注釈の札の右にそろえる
    private func drawFooter(_ panel: CandidatePanel, in rect: NSRect) {
        let footer = footerContent(for: panel)
        let muted: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: theme.textMuted]
        let left = rect.minX + rowPaddingX
        let rightEdge = rect.maxX - rowPaddingX
        let right = { (text: String, attributes: [NSAttributedString.Key: Any]) in
            self.drawText(text, attributes: attributes, x: rightEdge - text.size(withAttributes: attributes).width, in: rect)
        }
        let hintsWidth = GlassDrawing.hintsWidth(footer.hints, theme: theme)
        if theme.isRounded {
            if let note = footer.note {
                NoteDrawing.draw(note, x: left, midY: rect.midY, theme: theme)
            } else {
                GlassDrawing.drawHints(footer.hints, x: left, midY: rect.midY, theme: theme)
                if let hint = footer.associationHint { drawText(hint, attributes: muted, x: left + hintsWidth + Glass.hintGap, in: rect) }
            }
            right(footer.position, muted)
            return
        }
        drawText(footer.position, attributes: muted, x: left, in: rect)
        if let note = footer.note {
            NoteDrawing.draw(note, x: rightEdge - NoteDrawing.width(note, theme: theme), midY: rect.midY, theme: theme)
        } else {
            GlassDrawing.drawHints(footer.hints, x: rightEdge - hintsWidth, midY: rect.midY, theme: theme)
            if let hint = footer.associationHint {
                let width = hint.size(withAttributes: muted).width
                drawText(hint, attributes: muted, x: rightEdge - hintsWidth - Glass.hintGap - width, in: rect)
            }
        }
    }

    /// 行の縦の真ん中に，文字の行の箱(書体の ascender から descender まで)の真ん中を合わせて描く．
    /// ベースラインと x は整数に丸め，文字の輪郭をぼかさない
    private func drawText(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, in rect: NSRect) {
        TextFitting.draw(text, attributes: attributes, x: x, midY: rect.midY)
    }
}

extension CandidatePanel.Entry {
    /// 札に出したユーザー辞書の語のコメント(長ければ先頭だけ)．札がコメントでなければ nil
    var comment: String? { hasComment ? annotation : nil }
}

extension ResolvedTheme {
    /// ビューを作った直後に使う仮の値．表示する前に必ず resolve した値で置き換える
    @MainActor
    static var resolveStatic: ResolvedTheme { resolve(.automatic, appearance: NSAppearance(named: .aqua)) }
}
