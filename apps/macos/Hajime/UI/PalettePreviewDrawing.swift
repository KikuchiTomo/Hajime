import AppKit
import HajimeApplication

/// パレットの説明の欄(R-26)のうち，大きな見本の右と下に並べる名前・読み・札を描く．
///
/// 上から順に次を並べる．
/// - 見出しの名前．どこで定めた名前か(CLDR)を枠の札で後ろに添える．入らなければ折り返し，札は最後の行の後ろに置く
/// - Unicode の名前．どこで定めた名前か(Unicode・CLDR)の札を前に置き，入らなければ折り返す(続く行は札の後ろにそろえる)
/// - 読み．「読み」の札のあとに「、」で並べ，入らない読みは「+n」にまとめる
/// - ショートコードとコードポイント．等幅の字の札にし，札の途中では切らずに次の行へ送る．行より広い札は字を縮め，それでも入らなければ札の中で折り返す
///
/// 項目は，見本の高さまでに始まるものは見本の右に，その下で始まるものは欄の幅いっぱいに置く(折り返した行は項目の 1 行目にそろえる)．
/// ピン留めのボタンの高さまでの行はボタンの手前で止める．
/// 欄の高さは出す項目の設定だけで決める(height(for:theme:))．選んでいる文字の中身が入りきらなければ，
/// Unicode の名前の行を減らし，見出しの名前を 1 行にし，読みを省き，Unicode の名前を省く順に詰める．それでも入らない札は「+n」にまとめる．
/// 決め方は Windows の候補ウィンドウ(palette::preview)と同じにする
@MainActor
enum PalettePreviewDrawing {
    private typealias Size = DesignTokens.Size.Palette

    /// 欄の中で，名前・読み・札を置く場所(上下の余白を除いた欄)と，見本とピン留めのボタンが占める場所
    struct Frame {
        var area: NSRect
        var tile: NSRect
        var pin: NSRect
    }

    /// 欄(rect)から上下の余白を除いた，見本と名前を置く場所
    static func contentArea(of rect: NSRect) -> NSRect {
        rect.insetBy(dx: 0, dy: Size.previewPaddingY)
    }

    /// 見本の枠の一辺(顔文字は横に広げる)
    static var tileSide: CGFloat { Size.previewGlyphSize + Size.previewTilePadding * 2 }

    /// 欄の高さ．見本の高さと，見込んだ行(見出し・Unicode の名前・読み・札)を積んだ高さの大きいほうに，上下の余白を足したもの
    static func height(for fields: PalettePanel.PreviewFields, theme: ResolvedTheme) -> CGFloat {
        let fonts = Fonts(theme)
        var height = fonts.nameRow
        if fields.unicodeName { height += Size.previewLineGap + fonts.detailRow + fonts.detailLine * (Size.previewNameLines - 1) }
        if fields.readings { height += Size.previewLineGap + fonts.detailRow }
        if fields.chips {
            let lines = Size.previewChipLines
            height += Size.previewLineGap + fonts.chipHeight(lines: 1) * lines + Size.previewChipGap * (lines - 1)
        }
        return (max(tileSide, height) + Size.previewPaddingY * 2).rounded(.up)
    }

    static func draw(_ preview: PalettePanel.Preview, in frame: Frame, theme: ResolvedTheme) {
        let fonts = Fonts(theme)
        var options = Options()
        var parts = plan(preview, options: options, frame: frame, fonts: fonts)
        // 入りきらなければ，Unicode の名前の行を見込んだ数まで減らし，見出しの名前を 1 行にし，読みを省き，Unicode の名前を 1 行にし，省く
        let steps: [(inout Options) -> Void] = [
            { $0.unicodeLines = min($0.unicodeLines, Int(Size.previewNameLines)) },
            { $0.headingLines = 1 },
            { $0.readings = false },
            { $0.unicodeLines = 1 },
            { $0.unicodeName = false },
        ]
        for step in steps where bottom(of: parts) > frame.area.maxY {
            step(&options)
            parts = plan(preview, options: options, frame: frame, fonts: fonts)
        }
        for part in limitingChips(parts, in: frame, fonts: fonts) { draw(part, fonts: fonts, theme: theme) }
    }

    // MARK: - 配置

    /// 詰めるときに変えるもの
    private struct Options {
        var headingLines = Int(Size.previewHeadingMaxLines)
        var unicodeLines = Int(Size.previewNameMaxLines)
        var readings = true
        var unicodeName = true
    }

    /// 描く部品．rect は部品の枠(文字は枠の左上から描く)
    private enum Part {
        case text(String, NSFont, NSRect)
        /// 名前を定めたところと「読み」の枠の札
        case tag(String, NSRect)
        /// ショートコードとコードポイントの札．行より広ければ字を縮め(small)，それでも入らなければ札の中で折り返す
        case chip([String], small: Bool, NSRect)
        /// 入らなかった読みや札の数(「+n」)
        case more(Int, NSRect)

        var rect: NSRect {
            switch self {
            case .text(_, _, let rect), .tag(_, let rect), .chip(_, _, let rect), .more(_, let rect): rect
            }
        }

        var isChip: Bool {
            if case .chip = self { true } else { false }
        }
    }

    /// 書体と行の高さ
    private struct Fonts {
        let name: NSFont
        let detail: NSFont
        let tag: NSFont
        let code: NSFont
        let smallCode: NSFont

        init(_ theme: ResolvedTheme) {
            name = theme.emphasisFont(size: Size.nameFontSize)
            detail = theme.labelFont(size: Size.detailFontSize)
            tag = theme.labelFont(size: Size.previewTagFontSize)
            code = .monospacedSystemFont(ofSize: Size.codeFontSize, weight: .regular)
            smallCode = .monospacedSystemFont(ofSize: Size.previewChipSmallFontSize, weight: .regular)
        }

        var nameLine: CGFloat { PalettePreviewDrawing.lineHeight(name) }
        var detailLine: CGFloat { PalettePreviewDrawing.lineHeight(detail) }
        var tagHeight: CGFloat { PalettePreviewDrawing.lineHeight(tag) + Size.previewChipPaddingY }
        /// 札を添える行の高さ
        var nameRow: CGFloat { max(nameLine, tagHeight) }
        var detailRow: CGFloat { max(detailLine, tagHeight) }

        func chipHeight(lines: CGFloat, small: Bool = false) -> CGFloat {
            PalettePreviewDrawing.lineHeight(small ? smallCode : code) * lines + Size.previewChipPaddingY * 2
        }

        func width(_ text: String, _ font: NSFont) -> CGFloat { text.size(withAttributes: [.font: font]).width.rounded(.up) }
        func tagWidth(_ text: String) -> CGFloat { width(text, tag) + Size.previewTagPaddingX * 2 }
        func moreWidth(_ count: Int) -> CGFloat { width(UIStrings.Candidate.more(count), detail) }
    }

    /// y から始まる行の左右の端．見本の高さまでは見本の右，ピン留めのボタンの高さまではボタンの手前まで
    private static func span(at y: CGFloat, in frame: Frame) -> (minX: CGFloat, maxX: CGFloat) {
        (y < frame.tile.maxY ? frame.tile.maxX + Size.previewGap : frame.area.minX, y < frame.pin.maxY ? frame.pin.minX : frame.area.maxX)
    }

    /// 折り返した 1 行．row は行の高さ
    private struct Line {
        var text: String
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var row: CGFloat
    }

    /// top から text を折り返して置いた行．左の端は 1 行目の位置(span(at:in:))にそろえ，右の端は行ごとに決める．maxLines を超える分は最後の行の末尾を「…」で省く．
    /// indent は行の左の端からずらす幅(札の後ろにそろえる)，reserve は行の右に空けておく幅(後ろに置く札の分)．
    /// 1 行目の高さは rows.first(札を置く行)，続く行は rows.next
    private static func flow(_ text: String, font: NSFont, maxLines: Int, top: CGFloat, indent: CGFloat, reserve: CGFloat,
                             rows: (first: CGFloat, next: CGFloat), frame: Frame) -> [Line] {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var lines: [Line] = []
        var rest = Substring(text)
        var y = top
        // 続く行も 1 行目と同じ左の端から書く(見本の下に回り込ませると，札の後ろにそろわない)
        let x = Self.span(at: top, in: frame).minX + indent
        while !rest.isEmpty, lines.count < maxLines {
            let width = Self.span(at: y, in: frame).maxX - x - reserve
            let count = TextFitting.lineBreak(rest, attributes: attributes, width: width)
            let isLast = lines.count == maxLines - 1 && count < rest.count
            let shown = isLast ? TextFitting.truncated(String(rest), attributes: attributes, width: width)
                : String(rest.prefix(count)).trimmingCharacters(in: .whitespaces)
            let row = lines.isEmpty ? rows.first : rows.next
            lines.append(Line(text: shown, x: x, y: y, width: shown.size(withAttributes: attributes).width.rounded(.up), row: row))
            y += row
            rest = isLast ? "" : rest.dropFirst(count).drop { $0 == " " }
        }
        return lines
    }

    /// 行(高さ rowHeight)の中で縦に中央にそろえた枠
    private static func centered(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, in rowHeight: CGFloat) -> NSRect {
        NSRect(x: x.rounded(), y: (y + (rowHeight - height) / 2).rounded(), width: width, height: height)
    }

    private static func plan(_ preview: PalettePanel.Preview, options: Options, frame: Frame, fonts: Fonts) -> [Part] {
        var parts: [Part] = []
        var y = frame.area.minY
        // 見出しの名前と，どこで定めた名前かの札．札は最後の行の後ろに置く
        let nameTag = preview.nameSource.map { fonts.tagWidth($0) + Size.previewTagGap } ?? 0
        let heading = flow(preview.name, font: fonts.name, maxLines: options.headingLines, top: y, indent: 0, reserve: nameTag,
                           rows: (fonts.nameRow, fonts.nameLine), frame: frame)
        for line in heading {
            parts.append(.text(line.text, fonts.name, centered(x: line.x, y: line.y, width: line.width, height: fonts.nameLine, in: line.row)))
        }
        if let source = preview.nameSource, let last = heading.last {
            parts.append(.tag(source, centered(x: last.x + last.width + Size.previewTagGap, y: last.y, width: fonts.tagWidth(source),
                                               height: fonts.tagHeight, in: last.row)))
        }
        y = heading.last.map { $0.y + $0.row } ?? y + fonts.nameRow
        // Unicode の名前．札の後ろから書き，折り返した行も札の後ろにそろえる
        if options.unicodeName, !preview.unicodeName.isEmpty {
            y += Size.previewLineGap
            var indent: CGFloat = 0
            if let source = preview.unicodeNameSource {
                let width = fonts.tagWidth(source)
                parts.append(.tag(source, centered(x: Self.span(at: y, in: frame).minX, y: y, width: width, height: fonts.tagHeight, in: fonts.detailRow)))
                indent = width + Size.previewTagGap
            }
            let lines = flow(preview.unicodeName, font: fonts.detail, maxLines: options.unicodeLines, top: y, indent: indent, reserve: 0,
                             rows: (fonts.detailRow, fonts.detailLine), frame: frame)
            for line in lines {
                parts.append(.text(line.text, fonts.detail, centered(x: line.x, y: line.y, width: line.width, height: fonts.detailLine, in: line.row)))
            }
            y = lines.last.map { $0.y + $0.row } ?? y
        }
        var span = Self.span(at: y, in: frame)
        // 読み．入る数だけ並べ，残りの数を添える
        if options.readings, !preview.readings.isEmpty {
            y += Size.previewLineGap
            span = Self.span(at: y, in: frame)
            let label = PaletteStrings.readings
            let labelWidth = fonts.tagWidth(label)
            parts.append(.tag(label, centered(x: span.minX, y: y, width: labelWidth, height: fonts.tagHeight, in: fonts.detailRow)))
            let x = span.minX + labelWidth + Size.previewTagGap
            let (text, rest) = fittingReadings(preview.readings, width: span.maxX - x, fonts: fonts)
            let width = fonts.width(text, fonts.detail)
            parts.append(.text(text, fonts.detail, centered(x: x, y: y, width: width, height: fonts.detailLine, in: fonts.detailRow)))
            if rest > 0 {
                parts.append(.more(rest, centered(x: x + width + Size.previewTagGap, y: y, width: fonts.moreWidth(rest), height: fonts.detailLine,
                                                  in: fonts.detailRow)))
            }
            y += fonts.detailRow
        }
        // ショートコードとコードポイントの札．入らない札は次の行へ送り，行より広い札は字を縮め，それでも入らなければ札の中で折り返す
        let chips = preview.shortcodes + preview.codePoints
        guard !chips.isEmpty else { return parts }
        y += Size.previewLineGap
        span = Self.span(at: y, in: frame)
        var x = span.minX
        var rowHeight: CGFloat = 0
        for chip in chips {
            var lines = [chip]
            var width = fonts.width(chip, fonts.code) + Size.previewChipPaddingX * 2
            if x > span.minX, x + width > span.maxX {
                y += rowHeight + Size.previewChipGap
                span = Self.span(at: y, in: frame)
                x = span.minX
                rowHeight = 0
            }
            let rowWidth = span.maxX - span.minX
            let small = width > rowWidth
            if small {
                width = fonts.width(chip, fonts.smallCode) + Size.previewChipPaddingX * 2
                if width > rowWidth {
                    width = rowWidth
                    lines = TextFitting.wrapped(chip, attributes: [.font: fonts.smallCode], width: width - Size.previewChipPaddingX * 2)
                }
            }
            let height = fonts.chipHeight(lines: CGFloat(lines.count), small: small)
            parts.append(.chip(lines, small: small, NSRect(x: x.rounded(), y: y.rounded(), width: width, height: height)))
            x += width + Size.previewChipGap
            rowHeight = max(rowHeight, height)
        }
        return parts
    }

    private static func bottom(of parts: [Part]) -> CGFloat {
        parts.map(\.rect.maxY).max() ?? 0
    }

    /// 欄の下の端を越える札を除き，除いた数を最後に残した札の後ろに「+n」で示す．「+n」が入らなければその札も除く
    private static func limitingChips(_ parts: [Part], in frame: Frame, fonts: Fonts) -> [Part] {
        guard bottom(of: parts) > frame.area.maxY else { return parts }
        let total = parts.filter(\.isChip).count
        var kept = parts.filter { !$0.isChip || $0.rect.maxY <= frame.area.maxY }
        while let index = kept.lastIndex(where: \.isChip) {
            let last = kept[index].rect
            let dropped = total - kept.filter(\.isChip).count
            let more = NSRect(x: last.maxX + Size.previewChipGap, y: last.minY, width: fonts.moreWidth(dropped), height: last.height)
            if more.maxX <= span(at: last.minY, in: frame).maxX {
                kept.append(.more(dropped, more))
                return kept
            }
            kept.remove(at: index)
        }
        return kept
    }

    /// 幅に入る数の読み(「、」でつなぐ)と，入らなかった読みの数．1 つ目も入らなければ末尾を省く
    private static func fittingReadings(_ readings: [String], width: CGFloat, fonts: Fonts) -> (String, Int) {
        func moreWidth(_ rest: Int) -> CGFloat { rest > 0 ? Size.previewTagGap + fonts.moreWidth(rest) : 0 }
        for count in stride(from: readings.count, through: 1, by: -1) {
            let text = readings.prefix(count).joined(separator: PaletteStrings.readingSeparator)
            if fonts.width(text, fonts.detail) + moreWidth(readings.count - count) <= width { return (text, readings.count - count) }
        }
        let rest = readings.count - 1
        return (TextFitting.truncated(readings[0], attributes: [.font: fonts.detail], width: width - moreWidth(rest)), rest)
    }

    // MARK: - 描画

    private static func draw(_ part: Part, fonts: Fonts, theme: ResolvedTheme) {
        let line = DesignTokens.Size.Candidate.frameWidth
        switch part {
        case .text(let text, let font, let rect):
            text.draw(at: rect.origin, withAttributes: [.font: font, .foregroundColor: theme.text])
        case .tag(let text, let rect):
            // 名前を定めたところと「読み」は，値と見分けるよう枠だけの札にする
            let radius = theme.isRounded ? Size.previewTagRadius : 0
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: line / 2, dy: line / 2), xRadius: radius, yRadius: radius)
            path.lineWidth = line
            theme.line.setStroke()
            path.stroke()
            GlassDrawing.drawCentered(text, attributes: [.font: fonts.tag, .foregroundColor: theme.textMuted], in: rect)
        case .chip(let lines, let small, let rect):
            // 角丸のテーマは控えめな地．platinum と desk は光の縁の色の地に 1 ドットの枠(入力欄の形)
            if theme.isRounded {
                theme.badge.setFill()
                NSBezierPath(roundedRect: rect, xRadius: Size.previewChipRadius, yRadius: Size.previewChipRadius).fill()
            } else {
                theme.line.setFill()
                rect.fill()
                theme.bevelLight.setFill()
                rect.insetBy(dx: line, dy: line).fill()
            }
            let font = small ? fonts.smallCode : fonts.code
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.text]
            for (index, text) in lines.enumerated() {
                let y = rect.minY + Size.previewChipPaddingY + lineHeight(font) * CGFloat(index)
                text.draw(at: NSPoint(x: rect.minX + Size.previewChipPaddingX, y: y.rounded()), withAttributes: attributes)
            }
        case .more(let count, let rect):
            UIStrings.Candidate.more(count).draw(at: rect.origin, withAttributes: [.font: fonts.detail, .foregroundColor: theme.textMuted])
        }
    }

    nonisolated static func lineHeight(_ font: NSFont) -> CGFloat { (font.ascender - font.descender + font.leading).rounded(.up) }
}
