import AppKit
import CoreText
import HajimeDomain

/// 語の意味のカード(R-08)を描く．一覧(CandidateView)と分岐図(BranchView)で同じものを使う．
///
/// 上から順に，見出し(辞書のアイコン・語・品詞の札)，意味，使い方の例，同音語を並べる．
/// - 意味が 2 つ以上なら，頭に角丸の四角の番号を付ける(候補の番号の丸と形を変え，番号キーで選ぶものと見分ける)
/// - 意味と例はカードの幅で折り返す(CoreText の行分けで，句読点や小さいかなを行の頭に置かない)．行数の上限を超える分は「…」で省く
/// - 使い方の例は左に縦の線を引いて控えめな色で出し，例の中の見出しの語だけを強める
/// - 同音語は区切りの線の下に，耳のアイコンと札で並べる
///
/// 候補の右に出すときは，一覧では選んでいる候補を指す三角を左の辺に付け(drawBackground の pointerY)，
/// 分岐図では選んでいる候補からカードへ線を引く(drawConnector)．
/// 折り返しは重いので，同じ注釈と幅の配置は覚えておいて使い回す(ふわっと出すあいだ 1 秒に 60 回描き直すため)
@MainActor
enum MeaningCardDrawing {
    private typealias Glass = DesignTokens.Size.Glass
    private typealias Opacity = DesignTokens.Opacity.Glass

    /// 折り返した 1 行
    struct Line {
        var text: NSAttributedString
        var height: CGFloat
    }

    /// 1 つの意味の行
    struct Sense {
        var number: String?
        var meaning: [Line]
        var example: [Line]
        var height: CGFloat
    }

    /// 描く位置を決めたカード．size は内側の余白を含む
    struct Layout {
        var note: HomophoneNote
        var others: [String]
        var headerHeight: CGFloat
        var senses: [Sense]
        /// 同音語の行(上の区切りと空きを含む)．同音語が無ければ 0
        var othersHeight: CGFloat
        var size: NSSize
    }

    private struct CacheKey: Hashable {
        var note: String
        var others: [String]
        var width: CGFloat
        var theme: String
    }

    private static var cache: [CacheKey: Layout] = [:]
    /// 覚えておく数の上限(超えたら捨てて作り直す)
    private static let cacheLimit = 64

    /// 配置を見分けるテーマの値．文字の色は折り返した行に入るので，書体のほかに色も含める(外観やテーマを変えたら作り直す)
    private static func themeKey(_ theme: ResolvedTheme) -> String {
        "\(theme.kind)|\(theme.typeface)|\(theme.customFontName ?? "")|\(theme.text)|\(theme.textMuted)|\(increasesContrast)"
    }

    /// 文字を並べる幅(余白を除く)が width のカードの配置．others は同音語の札に出す語(分岐図では枝に出ている語を除いたもの)
    static func layout(_ note: HomophoneNote, others: [String]? = nil, width: CGFloat, theme: ResolvedTheme) -> Layout {
        let others = others ?? note.others
        let key = CacheKey(note: "\(note.word)\u{1F}\(note.partOfSpeech?.rawValue ?? "")\u{1F}\(note.senses.map { "\($0.meaning)\u{1E}\($0.example ?? "")" })",
                           others: others, width: width, theme: themeKey(theme))
        if let cached = cache[key] { return cached }
        let numbered = note.senses.count > 1
        let textWidth = width - (numbered ? Glass.meaningBadgeSize + Glass.noteGap : 0)
        let exampleWidth = textWidth - Glass.meaningExampleBarWidth - Glass.meaningExampleIndent
        let senses = note.senses.enumerated().map { index, sense -> Sense in
            let meaning = wrap(NSAttributedString(string: sense.meaning, attributes: [.font: bodyFont(theme), .foregroundColor: theme.text]),
                               width: textWidth, maxLines: Int(Glass.meaningMeaningLines))
            let example = sense.example.map { wrap(exampleText($0, word: note.word, theme: theme), width: exampleWidth, maxLines: Int(Glass.meaningExampleLines)) } ?? []
            let height = linesHeight(meaning) + (example.isEmpty ? 0 : Glass.meaningExampleGap + linesHeight(example))
            return Sense(number: numbered ? UIStrings.Candidate.senseNumber(index + 1) : nil, meaning: meaning, example: example, height: height)
        }
        let headerHeight = max(lineHeight(headwordFont(theme)), Glass.meaningPosHeight)
        let othersHeight = others.isEmpty ? 0 : Glass.meaningOthersGap * 2 + DesignTokens.Size.Candidate.frameWidth + Glass.tagHeight
        let sensesHeight = senses.reduce(0) { $0 + $1.height } + Glass.meaningSenseGap * CGFloat(max(senses.count - 1, 0))
        let height = Glass.meaningPadding * 2 + headerHeight + Glass.meaningHeaderGap + sensesHeight + othersHeight
        let layout = Layout(note: note, others: others, headerHeight: headerHeight, senses: senses, othersHeight: othersHeight,
                            size: NSSize(width: width + Glass.meaningPadding * 2, height: height.rounded(.up)))
        if cache.count >= cacheLimit { cache.removeAll() }
        cache[key] = layout
        return layout
    }

    // MARK: - 地

    /// カードの地．pointerY があれば，左の辺からその高さを指す三角を出す(一覧で選んでいる候補を指す)
    static func drawBackground(in rect: NSRect, theme: ResolvedTheme, pointerY: CGFloat? = nil) {
        let notch = Glass.meaningNotch
        guard theme.isRounded else {
            // platinum と desk: 1 ドットの枠と，枠の色の三角
            theme.line.setFill()
            rect.frame(withWidth: DesignTokens.Size.Candidate.frameWidth)
            if let pointerY {
                let y = min(max(pointerY, rect.minY + notch * 2), rect.maxY - notch * 2).rounded()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: rect.minX, y: y - notch))
                path.line(to: NSPoint(x: rect.minX - notch, y: y))
                path.line(to: NSPoint(x: rect.minX, y: y + notch))
                path.close()
                path.fill()
            }
            return
        }
        let radius = min(Glass.meaningRadius, theme.cornerRadius, rect.height / 2, rect.width / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
        path.appendArc(from: NSPoint(x: rect.maxX, y: rect.minY), to: NSPoint(x: rect.maxX, y: rect.maxY), radius: radius)
        path.appendArc(from: NSPoint(x: rect.maxX, y: rect.maxY), to: NSPoint(x: rect.minX, y: rect.maxY), radius: radius)
        path.appendArc(from: NSPoint(x: rect.minX, y: rect.maxY), to: NSPoint(x: rect.minX, y: rect.minY), radius: radius)
        if let pointerY, rect.height > (radius + notch) * 2 {
            // 三角は角の丸みにかからない範囲に収める．地と同じ 1 つの形にし，重ねて濃くならないようにする
            let y = min(max(pointerY, rect.minY + radius + notch), rect.maxY - radius - notch)
            path.line(to: NSPoint(x: rect.minX, y: y + notch))
            path.line(to: NSPoint(x: rect.minX - notch, y: y))
            path.line(to: NSPoint(x: rect.minX, y: y - notch))
        }
        path.appendArc(from: NSPoint(x: rect.minX, y: rect.minY), to: NSPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
        path.close()
        cardFill(theme).setFill()
        path.fill()
    }

    /// 意味の無い候補を選んでいるときの空いたカード．地の真ん中に辞書のアイコンを薄く出す(カードの場所は動かさない)
    static func drawEmpty(in rect: NSRect, theme: ResolvedTheme, pointerY: CGFloat? = nil) {
        drawBackground(in: rect, theme: theme, pointerY: pointerY)
        let color = theme.textMuted.withAlphaComponent(DesignTokens.Opacity.Glass.meaningEmptyIcon)
        guard let image = symbol(bookSymbols, pointSize: Glass.meaningEmptyIconSize, color: color) else { return }
        image.draw(in: NSRect(x: (rect.midX - image.size.width / 2).rounded(), y: (rect.midY - image.size.height / 2).rounded(),
                              width: image.size.width, height: image.size.height))
    }

    /// 分岐図で，選んでいる候補の行の右の端(from)からカードの左の辺(to)へ引く線．端に丸を付ける．
    /// 曲線の枝のテーマはなめらかな S 字，直線の枝のテーマは折れ線にする
    static func drawConnector(from start: NSPoint, to end: NSPoint, theme: ResolvedTheme) {
        let path = NSBezierPath()
        path.move(to: start)
        let middle = ((start.x + end.x) / 2).rounded()
        if theme.isRounded, !theme.straightBranches {
            path.curve(to: end, controlPoint1: NSPoint(x: middle, y: start.y), controlPoint2: NSPoint(x: middle, y: end.y))
        } else {
            path.line(to: NSPoint(x: middle, y: start.y))
            path.line(to: NSPoint(x: middle, y: end.y))
            path.line(to: end)
        }
        path.lineWidth = theme.isRounded ? Glass.lineWidthSelected : DesignTokens.Size.Branch.lineWidthSelected
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        theme.selection.setStroke()
        path.stroke()
        let dot = Glass.meaningDotSize
        theme.selection.setFill()
        NSBezierPath(ovalIn: NSRect(x: end.x - dot / 2, y: end.y - dot / 2, width: dot, height: dot)).fill()
    }

    /// カードの見出しの行の縦の中心(rect はカードの枠)．分岐図のつなぐ線はここへ引く
    static func headerMidY(_ layout: Layout, in rect: NSRect) -> CGFloat {
        (rect.minY + Glass.meaningPadding + layout.headerHeight / 2).rounded()
    }

    // MARK: - 中身

    /// rect(カードの枠．地は描かない)の中に，見出し・意味・例・同音語を描く
    static func drawContent(_ layout: Layout, in rect: NSRect, theme: ResolvedTheme) {
        let left = rect.minX + Glass.meaningPadding
        let right = rect.maxX - Glass.meaningPadding
        var y = rect.minY + Glass.meaningPadding
        drawHeader(layout, x: left, maxX: right, y: y, theme: theme)
        y += layout.headerHeight + Glass.meaningHeaderGap
        for sense in layout.senses {
            var textX = left
            if let number = sense.number, let first = sense.meaning.first {
                let size = Glass.meaningBadgeSize
                let badge = NSRect(x: left, y: (y + (first.height - size) / 2).rounded(), width: size, height: size)
                let radius = theme.isRounded ? Glass.meaningBadgeRadius : 0
                tint(theme).setFill()
                NSBezierPath(roundedRect: badge, xRadius: radius, yRadius: radius).fill()
                GlassDrawing.drawCentered(number, attributes: [.font: theme.keyFont(size: Glass.meaningBadgeFontSize), .foregroundColor: theme.selection], in: badge)
                textX = badge.maxX + Glass.noteGap
            }
            var lineY = y
            for line in sense.meaning {
                line.text.draw(at: NSPoint(x: textX.rounded(), y: lineY.rounded()))
                lineY += line.height + Glass.meaningLineSpacing
            }
            if !sense.example.isEmpty {
                lineY += Glass.meaningExampleGap - Glass.meaningLineSpacing
                let barHeight = linesHeight(sense.example)
                let bar = NSRect(x: textX, y: lineY, width: Glass.meaningExampleBarWidth, height: barHeight)
                theme.selection.withAlphaComponent(Opacity.meaningExampleBar).setFill()
                NSBezierPath(roundedRect: bar, xRadius: bar.width / 2, yRadius: bar.width / 2).fill()
                for line in sense.example {
                    line.text.draw(at: NSPoint(x: (bar.maxX + Glass.meaningExampleIndent).rounded(), y: lineY.rounded()))
                    lineY += line.height + Glass.meaningLineSpacing
                }
            }
            y += sense.height + Glass.meaningSenseGap
        }
        guard !layout.others.isEmpty else { return }
        y += Glass.meaningOthersGap - Glass.meaningSenseGap
        theme.line.setFill()
        NSRect(x: left, y: y.rounded(), width: right - left, height: DesignTokens.Size.Candidate.frameWidth).fill()
        y += DesignTokens.Size.Candidate.frameWidth + Glass.meaningOthersGap
        drawOthers(layout.others, x: left, maxX: right, midY: y + Glass.tagHeight / 2, theme: theme)
    }

    /// 見出し: 辞書のアイコン・語・品詞の札
    private static func drawHeader(_ layout: Layout, x: CGFloat, maxX: CGFloat, y: CGFloat, theme: ResolvedTheme) {
        let midY = y + layout.headerHeight / 2
        var x = x
        if let icon = symbol(bookSymbols, pointSize: Glass.meaningIconSize, color: theme.selection) {
            icon.draw(in: NSRect(x: x, y: (midY - icon.size.height / 2).rounded(), width: icon.size.width, height: icon.size.height))
            x += icon.size.width + Glass.noteGap
        }
        let word: [NSAttributedString.Key: Any] = [.font: headwordFont(theme), .foregroundColor: theme.text]
        let posWidth = layout.note.partOfSpeech.map { posTagWidth($0.name, theme: theme) + Glass.noteGap } ?? 0
        let shown = TextFitting.truncated(layout.note.word, attributes: word, width: maxX - x - posWidth)
        let size = shown.size(withAttributes: word)
        shown.draw(at: NSPoint(x: x.rounded(), y: (midY - size.height / 2).rounded()), withAttributes: word)
        x += size.width + Glass.noteGap
        if let partOfSpeech = layout.note.partOfSpeech { drawPosTag(partOfSpeech.name, x: x, midY: midY, theme: theme) }
    }

    /// 品詞の札．アクセントの色を薄く敷いた角丸の地にアクセントの色の字
    private static func drawPosTag(_ text: String, x: CGFloat, midY: CGFloat, theme: ResolvedTheme) {
        let rect = NSRect(x: x.rounded(), y: (midY - Glass.meaningPosHeight / 2).rounded(), width: posTagWidth(text, theme: theme), height: Glass.meaningPosHeight)
        let radius = theme.isRounded ? rect.height / 2 : 0
        tint(theme).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        GlassDrawing.drawCentered(text, attributes: [.font: theme.labelFont(size: Glass.meaningPosFontSize), .foregroundColor: theme.selection], in: rect)
    }

    private static func posTagWidth(_ text: String, theme: ResolvedTheme) -> CGFloat {
        (text.size(withAttributes: [.font: theme.labelFont(size: Glass.meaningPosFontSize)]).width + Glass.meaningPosPaddingX * 2).rounded(.up)
    }

    /// 同音語の行: 耳のアイコン・「同音」・札．入らない札は「+n」にまとめる
    private static func drawOthers(_ others: [String], x: CGFloat, maxX: CGFloat, midY: CGFloat, theme: ResolvedTheme) {
        let muted: [NSAttributedString.Key: Any] = [.font: theme.labelFont(size: Glass.labelFontSize), .foregroundColor: theme.textMuted]
        var x = x
        if let icon = symbol(["ear"], pointSize: Glass.meaningIconSize, color: theme.textMuted) {
            icon.draw(in: NSRect(x: x, y: (midY - icon.size.height / 2).rounded(), width: icon.size.width, height: icon.size.height))
            x += icon.size.width + Glass.noteGap / 2
        }
        let label = UIStrings.Candidate.homophoneOthers
        let labelSize = label.size(withAttributes: muted)
        label.draw(at: NSPoint(x: x.rounded(), y: (midY - labelSize.height / 2).rounded()), withAttributes: muted)
        x += labelSize.width
        for (index, word) in others.enumerated() {
            let tag = NoteDrawing.tagWidth(word, theme: theme)
            let rest = others.count - index - 1
            let reserve = rest > 0 ? Glass.usageTagGap + UIStrings.Candidate.more(rest).size(withAttributes: muted).width : 0
            if x + Glass.usageTagGap + tag + reserve > maxX {
                let more = UIStrings.Candidate.more(others.count - index)
                let size = more.size(withAttributes: muted)
                more.draw(at: NSPoint(x: (x + Glass.usageTagGap).rounded(), y: (midY - size.height / 2).rounded()), withAttributes: muted)
                return
            }
            x += Glass.usageTagGap + tag
            NoteDrawing.drawTag(word, maxX: x, midY: midY, theme: theme, selected: false)
        }
    }

    // MARK: - 文字

    private static func bodyFont(_ theme: ResolvedTheme) -> NSFont { theme.bodyFont(size: Glass.meaningBodyFontSize) }
    private static func headwordFont(_ theme: ResolvedTheme) -> NSFont { theme.emphasisFont(size: Glass.meaningHeadwordFontSize) }

    /// 使い方の例．控えめな色で書き，例の中の見出しの語(活用した形は漢字の部分と送り仮名の長さまで)を文字の色の太字にする
    private static func exampleText(_ example: String, word: String, theme: ResolvedTheme) -> NSAttributedString {
        let font = theme.bodyFont(size: Glass.meaningExampleFontSize)
        let text = NSMutableAttributedString(string: example, attributes: [.font: font, .foregroundColor: theme.textMuted])
        if let range = highlightRange(of: word, in: example) {
            text.addAttributes([.font: theme.emphasisFont(size: Glass.meaningExampleFontSize), .foregroundColor: theme.text], range: range)
        }
        return text
    }

    /// 例の中で見出しの語に当たる範囲(UTF-16)．語がそのまま無ければ，漢字の部分と続くひらがなを送り仮名の長さまで．見つからなければ nil
    static func highlightRange(of word: String, in example: String) -> NSRange? {
        if let range = example.range(of: word) { return NSRange(range, in: example) }
        let stem = String(word.prefix { !isHiragana($0) })
        guard !stem.isEmpty, stem != word, let range = example.range(of: stem) else { return nil }
        let okurigana = word.count - stem.count
        let tail = example[range.upperBound...].prefix(while: isHiragana).prefix(okurigana)
        return NSRange(range.lowerBound..<tail.endIndex, in: example)
    }

    private static func isHiragana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) }
    }

    /// 幅で折り返した行．CoreText の行分けを使う．maxLines を超える分は最後の行の末尾を「…」にして省く
    static func wrap(_ text: NSAttributedString, width: CGFloat, maxLines: Int) -> [Line] {
        guard text.length > 0, width > 0, maxLines > 0 else { return [] }
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        var lines: [Line] = []
        var start = 0
        while start < text.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            guard count > 0 else { break }
            let rest = NSRange(location: start, length: text.length - start)
            if lines.count == maxLines - 1, start + count < text.length {
                let last = truncated(text.attributedSubstring(from: rest), width: width)
                lines.append(Line(text: last, height: lineHeight(of: last)))
                break
            }
            let piece = text.attributedSubstring(from: NSRange(location: start, length: count))
            lines.append(Line(text: piece, height: lineHeight(of: piece)))
            start += count
        }
        return lines
    }

    /// 末尾を「…」にして width に収めたもの
    private static func truncated(_ text: NSAttributedString, width: CGFloat) -> NSAttributedString {
        guard text.size().width > width, text.length > 0 else { return text }
        let ellipsis = NSAttributedString(string: "…", attributes: text.attributes(at: text.length - 1, effectiveRange: nil))
        var length = text.length
        while length > 0 {
            length -= 1
            let candidate = NSMutableAttributedString(attributedString: text.attributedSubstring(from: NSRange(location: 0, length: length)))
            candidate.append(ellipsis)
            if candidate.size().width <= width { return candidate }
        }
        return ellipsis
    }

    private static func lineHeight(of text: NSAttributedString) -> CGFloat {
        guard text.length > 0, let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont else { return 0 }
        return lineHeight(font)
    }

    private static func lineHeight(_ font: NSFont) -> CGFloat { (font.ascender - font.descender + font.leading).rounded(.up) }

    private static func linesHeight(_ lines: [Line]) -> CGFloat {
        lines.reduce(0) { $0 + $1.height } + Glass.meaningLineSpacing * CGFloat(max(lines.count - 1, 0))
    }

    // MARK: - 色とアイコン

    /// 見出しの辞書のアイコン．日本語の辞書のアイコンが無い OS では本のアイコン
    private static let bookSymbols = ["character.book.closed.ja", "book.closed"]

    private static func symbol(_ names: [String], pointSize: CGFloat, color: NSColor) -> NSImage? {
        names.lazy.compactMap { SymbolImageCache.image($0, pointSize: pointSize, weight: .medium, color: color) }.first
    }

    private static var increasesContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

    /// カードの地(文字の色を薄く敷く)
    private static func cardFill(_ theme: ResolvedTheme) -> NSColor {
        theme.text.withAlphaComponent(increasesContrast || theme.kind == .contrast ? Opacity.meaningCardContrast : Opacity.meaningCard)
    }

    /// 番号と品詞の札の地(アクセントの色を薄く敷く)
    private static func tint(_ theme: ResolvedTheme) -> NSColor {
        theme.selection.withAlphaComponent(increasesContrast || theme.kind == .contrast ? Opacity.meaningBadgeContrast : Opacity.meaningBadge)
    }
}
