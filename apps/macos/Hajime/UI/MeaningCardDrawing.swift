import AppKit
import CoreText
import HajimeApplication
import HajimeDomain

/// 語の意味(R-08)を描く．一覧(CandidateView)と分岐図(BranchView)で同じものを使う．
///
/// 箱は描かず，候補の列(分岐図では候補の枝)の続きとして置く．配置は core の MeaningCardLayout が決める．
/// ここでは意味と例を幅で折り返し(CoreText の行分けで，句読点や小さいかなを行の頭に置かない)，配置のとおりに描く．
/// 文字は配置のベースラインに書く(行の箱の中で上下にずれないように)．
/// - 意味が 2 つ以上なら，目印の列に角丸の四角の番号を付ける(候補の番号の丸と形を変え，番号キーで選ぶものと見分ける)
/// - 使い方の例は左に縦の線を引いて控えめな色で出し，例の中の見出しの語だけを強める
/// - 同音語は区切りの線の下に，耳のアイコンと札だけで並べる
/// - アクセントの色は，選んでいる候補とつなぐ線(drawConnector)だけに使う．アイコンは控えめな色，札は文字の色を薄く敷いた地に文字の色の字
///
/// 折り返しは重いので，同じ注釈と幅の配置は覚えておいて使い回す(ふわっと出すあいだ 1 秒に 60 回描き直すため)
@MainActor
enum MeaningCardDrawing {
    private typealias Meaning = DesignTokens.Size.Meaning

    /// 配置と，折り返した意味と例の行
    struct Layout {
        var placed: MeaningCardLayout
        /// 意味ごとの，折り返した意味の行と例の行
        var meaning: [[NSAttributedString]]
        var example: [[NSAttributedString]]
        var size: NSSize { NSSize(width: placed.width, height: placed.height) }
    }

    private struct CacheKey: Hashable {
        var note: String
        var others: [String]
        var width: CGFloat
        var left: Double
        var headerMidY: Double
        var theme: String
    }

    private static var cache: [CacheKey: Layout] = [:]
    /// 覚えておく数の上限(超えたら捨てて作り直す)
    private static let cacheLimit = 64

    /// 配置を見分けるテーマの値．文字の色は折り返した行に入るので，書体のほかに色も含める(外観やテーマを変えたら作り直す)
    private static func themeKey(_ theme: ResolvedTheme) -> String {
        "\(theme.kind)|\(theme.typeface)|\(theme.customFontName ?? "")|\(theme.text)|\(theme.textMuted)|\(increasesContrast)"
    }

    /// 幅 width の語の意味の配置．others は同音語の札に出す語(分岐図では枝に出ている語を除いたもの)．
    /// placement は目印の列の左の端と見出しの行の縦の真ん中(まわりの候補の行に合わせて描く側が決める)
    static func layout(_ note: HomophoneNote, others: [String]? = nil, width: CGFloat, placement: MeaningCardLayout.Placement,
                       theme: ResolvedTheme) -> Layout {
        let others = others ?? note.others
        let key = CacheKey(note: "\(note.word)\u{1F}\(note.partOfSpeech?.rawValue ?? "")\u{1F}\(note.senses.map { "\($0.meaning)\u{1E}\($0.example ?? "")" })",
                           others: others, width: width, left: placement.left, headerMidY: placement.headerMidY, theme: themeKey(theme))
        if let cached = cache[key] { return cached }
        let metrics = MeaningCardLayout.Metrics.tokens
        let columns = MeaningCardLayout.Columns(width: width, left: placement.left, metrics: metrics)
        let numbered = note.senses.count > 1
        let meaning = note.senses.map { sense in
            wrap(NSAttributedString(string: sense.meaning, attributes: [.font: font(.meaning, theme), .foregroundColor: theme.text]),
                 width: columns.textWidth, maxLines: Int(Meaning.meaningLines))
        }
        let example = note.senses.map { sense in
            sense.example.map { wrap(exampleText($0, word: note.word, theme: theme), width: columns.exampleWidth, maxLines: Int(Meaning.exampleLines)) } ?? []
        }
        let senses = note.senses.indices.map { index in
            MeaningCardLayout.Content.Sense(number: numbered ? UIStrings.Candidate.senseNumber(index + 1) : nil,
                                            meaningLines: meaning[index].count, exampleLines: example[index].count)
        }
        let content = MeaningCardLayout.Content(word: note.word, partOfSpeech: note.partOfSpeech?.name, senses: senses, others: others)
        let placed = MeaningCardLayout(content: content, width: width, placement: placement, moreLabel: { UIStrings.Candidate.more($0) },
                                       measuring: Measuring(theme: theme), metrics: metrics)
        let layout = Layout(placed: placed, meaning: meaning, example: example)
        if cache.count >= cacheLimit { cache.removeAll() }
        cache[key] = layout
        return layout
    }

    /// 見出しの行の高さ．描く側が見出しの行を候補の行の真ん中にそろえるのに使う
    static func headerHeight(theme: ResolvedTheme) -> CGFloat {
        MeaningCardLayout.headerHeight(measuring: Measuring(theme: theme), metrics: .tokens)
    }

    // MARK: - 空いた場所

    /// 意味の無い候補を選んでいるとき．場所は空けたまま(窓の大きさを変えない)，見出しの辞書のアイコンだけを薄く出す
    static func drawEmpty(in rect: NSRect, placement: MeaningCardLayout.Placement, theme: ResolvedTheme) {
        let color = theme.textMuted.withAlphaComponent(DesignTokens.Opacity.Glass.meaningEmptyIcon)
        guard let image = symbol(bookSymbols, pointSize: Meaning.iconSize, color: color) else { return }
        drawCentered(image, at: NSPoint(x: rect.minX + placement.left + Meaning.markerWidth / 2, y: rect.minY + placement.headerMidY))
    }

    /// つなぐ線の終わりの x．見出しのアイコンの手前で止める(rect は語の意味の場所)
    static func connectorEndX(in rect: NSRect, placement: MeaningCardLayout.Placement) -> CGFloat {
        rect.minX + placement.left - DesignTokens.Size.Space.xs
    }

    /// 選んでいる候補の行の右の端(from)から語の意味の見出し(to)へ引く線．端に丸を付ける．
    /// 枝(BranchLineDrawing)と同じ半径の曲がり角でつなぐ．直線の枝のテーマは直角に曲がる
    static func drawConnector(from start: NSPoint, to end: NSPoint, theme: ResolvedTheme) {
        // 枝と同じ形: 水平に出て，真ん中で枝と同じ半径の 4 分の 1 の円で曲がり，縦に進んでまた曲がり，水平に見出しへ入る．
        // 直線の枝のテーマは直角に曲がる．高さの差が小さければ半径を縮める
        let middle = ((start.x + end.x) / 2).rounded()
        let curved = theme.isRounded && !theme.straightBranches
        let rise = end.y - start.y
        let radius = min(curved ? DesignTokens.Size.Glass.branchTurnRadius : 0, abs(rise) / 2, middle - start.x, end.x - middle)
        let direction: CGFloat = rise < 0 ? -1 : 1
        let path = NSBezierPath()
        path.move(to: start)
        if rise == 0 {
            path.line(to: end)
        } else if radius > 0 {
            path.line(to: NSPoint(x: middle - radius, y: start.y))
            path.appendArc(from: NSPoint(x: middle, y: start.y), to: NSPoint(x: middle, y: end.y), radius: radius)
            path.line(to: NSPoint(x: middle, y: end.y - direction * radius))
            path.appendArc(from: NSPoint(x: middle, y: end.y), to: end, radius: radius)
            path.line(to: end)
        } else {
            path.line(to: NSPoint(x: middle, y: start.y))
            path.line(to: NSPoint(x: middle, y: end.y))
            path.line(to: end)
        }
        path.lineWidth = theme.isRounded ? DesignTokens.Size.Glass.lineWidthSelected : DesignTokens.Size.Branch.lineWidthSelected
        // 枝の線(BranchLineDrawing)と同じく，端は平らにし直角の角は尖らせる
        path.lineCapStyle = .butt
        path.lineJoinStyle = .miter
        theme.selection.setStroke()
        path.stroke()
        let dot = Meaning.dotSize
        theme.selection.setFill()
        NSBezierPath(ovalIn: NSRect(x: end.x - dot / 2, y: end.y - dot / 2, width: dot, height: dot)).fill()
    }

    // MARK: - 中身

    /// rect(語の意味の場所．箱は描かない)の中に，配置のとおりに見出し・意味・例・同音語を描く
    static func drawContent(_ layout: Layout, in rect: NSRect, theme: ResolvedTheme) {
        let placed = layout.placed
        let origin = rect.origin
        func box(_ box: MeaningCardLayout.Box) -> NSRect {
            NSRect(x: origin.x + box.x, y: origin.y + box.y, width: box.width, height: box.height)
        }
        func draw(_ text: NSAttributedString, x: Double, baseline: Double) {
            text.draw(with: NSRect(x: (origin.x + x).rounded(), y: origin.y + baseline, width: CGFloat.greatestFiniteMagnitude, height: 0),
                      options: [], context: nil)
        }

        // 見出し
        if let icon = symbol(bookSymbols, pointSize: Meaning.iconSize, color: theme.textMuted) {
            drawCentered(icon, at: NSPoint(x: box(placed.bookIcon).midX, y: box(placed.bookIcon).midY))
        }
        let headword = placed.headword
        draw(NSAttributedString(string: headword.text, attributes: [.font: font(.headword, theme), .foregroundColor: theme.text]),
             x: headword.line.x, baseline: headword.line.baseline)
        // 札(品詞・番号・同音語)は，パレットの説明の札と同じく文字の色を薄く敷いた地に文字の色の字
        // (控えめな色の字では地との差が足りないテーマがある)．アクセントの色は選んでいる候補とつなぐ線だけに使う
        if let chip = placed.partOfSpeech {
            let frame = box(chip.frame)
            let radius = theme.isRounded ? frame.height / 2 : 0
            theme.badge.setFill()
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
            draw(NSAttributedString(string: chip.text, attributes: [.font: font(.partOfSpeech, theme), .foregroundColor: theme.text]),
                 x: chip.textX, baseline: chip.baseline)
        }

        // 意味と例
        for (index, sense) in placed.senses.enumerated() {
            if let badge = sense.badge, let number = sense.number {
                let frame = box(badge)
                let radius = theme.isRounded ? Meaning.numberRadius : 0
                theme.badge.setFill()
                NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
                draw(NSAttributedString(string: number.text, attributes: [.font: font(.number, theme), .foregroundColor: theme.text]),
                     x: number.line.x, baseline: number.line.baseline)
            }
            for (line, text) in zip(sense.meaning, layout.meaning[index]) {
                draw(text, x: line.x, baseline: line.baseline)
            }
            if let bar = sense.exampleBar {
                let frame = box(bar)
                theme.line.setFill()
                NSBezierPath(roundedRect: frame, xRadius: frame.width / 2, yRadius: frame.width / 2).fill()
            }
            for (line, text) in zip(sense.example, layout.example[index]) {
                draw(text, x: line.x, baseline: line.baseline)
            }
        }

        // 同音語
        guard let separator = placed.separator else { return }
        theme.line.setFill()
        box(separator).fill()
        if let ear = placed.earIcon, let icon = symbol(["ear"], pointSize: Meaning.iconSize, color: theme.textMuted) {
            drawCentered(icon, at: NSPoint(x: box(ear).midX, y: box(ear).midY))
        }
        let muted: [NSAttributedString.Key: Any] = [.font: font(.label, theme), .foregroundColor: theme.textMuted]
        let tagText: [NSAttributedString.Key: Any] = [.font: font(.label, theme), .foregroundColor: theme.text]
        for tag in placed.tags {
            let frame = box(tag.frame)
            theme.badge.setFill()
            let radius = theme.isRounded ? DesignTokens.Size.Glass.tagRadius : 0
            NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius).fill()
            draw(NSAttributedString(string: tag.text, attributes: tagText), x: tag.textX, baseline: tag.baseline)
        }
        if let more = placed.more {
            draw(NSAttributedString(string: more.text, attributes: muted), x: more.line.x, baseline: more.line.baseline)
        }
    }

    /// 画像を center を中心に，デバイスのピクセルにそろえて描く
    private static func drawCentered(_ image: NSImage, at center: NSPoint) {
        image.draw(in: NSRect(x: (center.x - image.size.width / 2).rounded(), y: (center.y - image.size.height / 2).rounded(),
                              width: image.size.width, height: image.size.height))
    }

    // MARK: - 文字

    /// 役割ごとの書体
    private static func font(_ role: MeaningCardLayout.Role, _ theme: ResolvedTheme) -> NSFont {
        switch role {
        case .headword: theme.emphasisFont(size: Meaning.headwordFontSize)
        case .partOfSpeech: theme.labelFont(size: Meaning.partOfSpeechFontSize)
        case .number: theme.keyFont(size: Meaning.numberFontSize)
        case .meaning: theme.bodyFont(size: Meaning.bodyFontSize)
        case .example: theme.bodyFont(size: Meaning.exampleFontSize)
        case .label, .tag: theme.labelFont(size: DesignTokens.Size.Glass.labelFontSize)
        }
    }

    /// 配置に渡す測り方．行の箱は書体の ascender と descender，文字の箱は書体の大きさ(日本語の字の外形はほぼこの箱に収まる)
    private struct Measuring: MeaningCardMeasuring {
        var fonts: [MeaningCardLayout.Role: NSFont]

        @MainActor
        init(theme: ResolvedTheme) {
            fonts = Dictionary(uniqueKeysWithValues: MeaningCardLayout.Role.allCases.map { ($0, MeaningCardDrawing.font($0, theme)) })
        }

        private func font(_ role: MeaningCardLayout.Role) -> NSFont { fonts[role] ?? .systemFont(ofSize: NSFont.systemFontSize) }

        func width(_ text: String, _ role: MeaningCardLayout.Role) -> Double { text.size(withAttributes: [.font: font(role)]).width }
        func ascent(_ role: MeaningCardLayout.Role) -> Double { font(role).ascender }
        func descent(_ role: MeaningCardLayout.Role) -> Double { -font(role).descender }
        func size(_ role: MeaningCardLayout.Role) -> Double { font(role).pointSize }
    }

    /// 使い方の例．控えめな色で書き，例の中の見出しの語(活用した形は漢字の部分と送り仮名の長さまで)を文字の色の太字にする
    private static func exampleText(_ example: String, word: String, theme: ResolvedTheme) -> NSAttributedString {
        let text = NSMutableAttributedString(string: example, attributes: [.font: font(.example, theme), .foregroundColor: theme.textMuted])
        if let range = highlightRange(of: word, in: example) {
            text.addAttributes([.font: theme.emphasisFont(size: Meaning.exampleFontSize), .foregroundColor: theme.text], range: range)
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
    static func wrap(_ text: NSAttributedString, width: CGFloat, maxLines: Int) -> [NSAttributedString] {
        guard text.length > 0, width > 0, maxLines > 0 else { return [] }
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        var lines: [NSAttributedString] = []
        var start = 0
        while start < text.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            guard count > 0 else { break }
            let rest = NSRange(location: start, length: text.length - start)
            if lines.count == maxLines - 1, start + count < text.length {
                lines.append(truncated(text.attributedSubstring(from: rest), width: width))
                break
            }
            lines.append(text.attributedSubstring(from: NSRange(location: start, length: count)))
            start += count
        }
        return avoidingSingleCharacterLastLine(lines)
    }

    /// 最後の行が 1 字だけになるときは，前の行の最後の字も送る(1 字だけの行を作らない)．
    /// 送る字を行の頭に置けないときと，前の行が短いときは送らない(Windows の scene::meaning::wrap と同じ決め方)
    private static func avoidingSingleCharacterLastLine(_ lines: [NSAttributedString]) -> [NSAttributedString] {
        guard lines.count >= 2, let last = lines.last, last.string.count == 1 else { return lines }
        let previous = lines[lines.count - 2]
        guard previous.string.count >= 3, let moved = previous.string.last, !lineStartForbidden.contains(moved) else { return lines }
        let split = previous.length - String(moved).utf16.count
        let head = previous.attributedSubstring(from: NSRange(location: 0, length: split))
        let tail = NSMutableAttributedString(attributedString: previous.attributedSubstring(from: NSRange(location: split, length: previous.length - split)))
        tail.append(last)
        return Array(lines.dropLast(2)) + [head, tail]
    }

    /// 行の頭に置かない字(Windows の scene::meaning の LINE_START_FORBIDDEN と同じ)
    private static let lineStartForbidden = Set("、。，．,.:;!?)]}）］｝」』】〕〉》・：；？！ー…‥々ゝゞヽヾぁぃぅぇぉっゃゅょゎゕゖァィゥェォッャュョヮヵヶ")

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

    // MARK: - 色とアイコン

    /// 見出しの辞書のアイコン．日本語の辞書のアイコンが無い OS では本のアイコン
    private static let bookSymbols = ["character.book.closed.ja", "book.closed"]

    private static func symbol(_ names: [String], pointSize: CGFloat, color: NSColor) -> NSImage? {
        names.lazy.compactMap { SymbolImageCache.image($0, pointSize: pointSize, weight: .medium, color: color) }.first
    }

    private static var increasesContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }

}
