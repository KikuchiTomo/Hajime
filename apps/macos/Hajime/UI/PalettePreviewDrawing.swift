import AppKit
import HajimeApplication
import HajimeDomain

/// パレットの説明の欄(R-26)の名前・項目名・値・タグを描く．配置は core の PalettePreviewLayout が決め，ここでは書体と色を決めて
/// 決まったベースラインに文字を置くだけにする(文字はベースラインの位置で描くので，書体が違っても縦がそろう)
@MainActor
enum PalettePreviewDrawing {
    private typealias Size = DesignTokens.Size.Palette

    static let metrics = PalettePreviewLayout.Metrics.tokens

    static let labels = PalettePreviewLayout.Labels(
        unicode: UIStrings.Palette.unicodeNameLabel, english: UIStrings.Palette.englishNameLabel, readings: UIStrings.Palette.readingsLabel,
        shortcodes: UIStrings.Palette.shortcodesLabel, codePoints: UIStrings.Palette.codePointsLabel, more: { UIStrings.Candidate.more($0) })

    /// 欄の高さ．その種類で出る行の分だけで決め，選んでいる文字では変えない
    nonisolated static func height(for fields: PalettePanel.PreviewFields, kind: PaletteItem.Kind) -> Double {
        PalettePreviewLayout.height(fields: fields, kind: kind, tileHeight: Size.tileSize, metrics: .tokens)
    }

    /// ピン留めのボタン．欄の右の端で，見出しの行の縦の中心に置く(押せる範囲は探す欄と同じ高さの正方形)
    static func pinRect(in rect: NSRect) -> NSRect {
        let midY = PalettePreviewLayout.headingMidY(top: rect.minY, metrics: metrics)
        let side = Size.controlHeight
        return NSRect(x: rect.maxX - side, y: (midY - side / 2).rounded(), width: side, height: side)
    }

    /// 名前・項目名・値・タグを描く．kind は今の種類(顔文字は項目名の列を読みだけで決める)
    static func draw(_ preview: PalettePanel.Preview, fields: PalettePanel.PreviewFields, kind: PaletteItem.Kind, area: NSRect, tile: NSRect,
                     theme: ResolvedTheme) {
        let measuring = Measuring(theme)
        let layout = PalettePreviewLayout(preview: preview, fields: fields, kind: kind, area: box(area), tile: box(tile), pinWidth: Size.controlHeight,
                                          labels: labels, measuring: measuring, metrics: metrics)
        for chip in layout.chips {
            drawChip(chip, measuring: measuring, theme: theme)
        }
        for text in layout.texts {
            draw(text.text, font: measuring.font(text.role), color: color(of: text.role, theme: theme), x: text.x, baseline: text.baseline)
        }
    }

    // MARK: - 描画

    /// ベースラインの位置で描くときの枠の幅．1 行で描くので，折り返さない広さにする
    private static let drawingWidth: CGFloat = 10_000

    /// 文字のベースラインを baseline に置いて描く(用紙の左上ではなくベースラインの位置で描く)
    private static func draw(_ text: String, font: NSFont, color: NSColor, x: Double, baseline: Double) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(with: NSRect(x: x, y: baseline, width: drawingWidth, height: 0), options: [], attributes: attributes)
    }

    /// 等幅の文字のタグ．角丸のテーマは控えめな地，platinum と desk は光の縁の色の地に 1 ドットの枠(入力欄の形)
    private static func drawChip(_ chip: PalettePreviewLayout.Chip, measuring: Measuring, theme: ResolvedTheme) {
        let rect = NSRect(x: chip.frame.x, y: chip.frame.y, width: chip.frame.width, height: chip.frame.height)
        if theme.isRounded {
            theme.badge.setFill()
            NSBezierPath(roundedRect: rect, xRadius: Size.chipRadius, yRadius: Size.chipRadius).fill()
        } else {
            let line = DesignTokens.Size.Candidate.frameWidth
            theme.line.setFill()
            rect.fill()
            theme.bevelLight.setFill()
            rect.insetBy(dx: line, dy: line).fill()
        }
        for (line, baseline) in zip(chip.lines, chip.baselines) {
            draw(line, font: measuring.font(chip.role), color: theme.text, x: chip.textX, baseline: baseline)
        }
    }

    /// 名前と値は文字の色，名前の出どころと項目名と「+n」は控えめな色
    private static func color(of role: PalettePreviewLayout.Role, theme: ResolvedTheme) -> NSColor {
        switch role {
        case .heading, .value, .code, .smallCode: theme.text
        case .source, .label, .more: theme.textMuted
        }
    }

    private static func box(_ rect: NSRect) -> PalettePreviewLayout.Box {
        PalettePreviewLayout.Box(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    /// 役割ごとの書体で幅と高さを測る
    struct Measuring: PalettePreviewMeasuring {
        private let fonts: [PalettePreviewLayout.Role: NSFont]

        init(_ theme: ResolvedTheme) {
            fonts = [
                .heading: theme.emphasisFont(size: Size.nameFontSize),
                .source: theme.labelFont(size: Size.previewLabelFontSize),
                .label: theme.labelFont(size: Size.previewLabelFontSize),
                .value: theme.labelFont(size: Size.detailFontSize),
                .more: theme.labelFont(size: Size.detailFontSize),
                .code: .monospacedSystemFont(ofSize: Size.codeFontSize, weight: .regular),
                .smallCode: .monospacedSystemFont(ofSize: Size.previewChipSmallFontSize, weight: .regular),
            ]
        }

        func font(_ role: PalettePreviewLayout.Role) -> NSFont {
            fonts[role] ?? .systemFont(ofSize: Size.detailFontSize)
        }

        func width(_ text: String, _ role: PalettePreviewLayout.Role) -> Double {
            text.isEmpty ? 0 : (text as NSString).size(withAttributes: [.font: font(role)]).width.rounded(.up)
        }

        func ascent(_ role: PalettePreviewLayout.Role) -> Double { font(role).ascender }
        // 行送りの余り(leading)は字面ではないので含めない(ヒラギノは leading が大きく，含めると行の高さを超える)
        func descent(_ role: PalettePreviewLayout.Role) -> Double { -font(role).descender }
    }
}
