import AppKit
import S90Application

/// 案内(Note)と候補の横の札を描く．分岐図・一覧の足元と，入力位置の下の案内の窓で同じものを使う．
///
/// 案内は部品ごとに描き分ける: 頭のアイコン(補正の色の地の丸)，主な語(「修正」「もしかして」)，
/// 対象の字(直す前の字は取り消し線，直した字は文字の色)，キーキャップの札とそのキーでできること
@MainActor
enum NoteDrawing {
    private typealias Glass = DesignTokens.Size.Glass

    /// 頭のアイコン(SF Symbols)．ほかの知らせにはアイコンを付けない
    private static func symbol(for tone: Note.Tone) -> String? {
        switch tone {
        case .correction: "wand.and.stars"
        case .suggestion: "lightbulb"
        case .info: nil
        }
    }

    private static func titleAttributes(_ note: Note, theme: ResolvedTheme) -> [NSAttributedString.Key: Any] {
        let color = note.tone == .info ? theme.textMuted : theme.correction
        return [.font: theme.emphasisFont(size: Glass.labelFontSize), .foregroundColor: color]
    }

    private static func subjectAttributes(_ note: Note, theme: ResolvedTheme) -> [NSAttributedString.Key: Any] {
        let font = theme.labelFont(size: Glass.labelFontSize)
        guard note.tone == .correction else { return [.font: font, .foregroundColor: theme.text] }
        // 直す前の字は，消したことが分かるよう取り消し線で薄く
        return [.font: font, .foregroundColor: theme.textMuted, .strikethroughStyle: NSUnderlineStyle.single.rawValue, .strikethroughColor: theme.textMuted]
    }

    private static func hints(_ note: Note) -> [KeyHint] {
        guard let key = note.key, let action = note.keyAction else { return [] }
        return [KeyHint(key: key, label: action)]
    }

    /// 案内の幅．描くときと大きさを求めるときで同じものを使う
    static func width(_ note: Note, theme: ResolvedTheme) -> CGFloat {
        var parts: [CGFloat] = []
        if symbol(for: note.tone) != nil { parts.append(Glass.noteIconSize) }
        if !note.title.isEmpty { parts.append(note.title.size(withAttributes: titleAttributes(note, theme: theme)).width.rounded(.up)) }
        if let subject = note.subject { parts.append(subject.size(withAttributes: subjectAttributes(note, theme: theme)).width.rounded(.up)) }
        let hints = hints(note)
        if !hints.isEmpty { parts.append(GlassDrawing.hintsWidth(hints, theme: theme)) }
        return parts.reduce(0, +) + Glass.noteGap * CGFloat(max(parts.count - 1, 0))
    }

    /// 案内を x から左寄せで描く．midY は行の中心(上下が反転した isFlipped のビュー)
    static func draw(_ note: Note, x: CGFloat, midY: CGFloat, theme: ResolvedTheme) {
        var x = x
        if let name = symbol(for: note.tone) {
            let rect = NSRect(x: x, y: (midY - Glass.noteIconSize / 2).rounded(), width: Glass.noteIconSize, height: Glass.noteIconSize)
            theme.correctionTint.setFill()
            (theme.isRounded ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)).fill()
            if let image = SymbolImageCache.image(name, pointSize: Glass.keyFontSize, weight: .semibold, color: theme.correction) {
                image.draw(in: NSRect(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2, width: image.size.width, height: image.size.height))
            }
            x = rect.maxX + Glass.noteGap
        }
        x = drawText(note.title, attributes: titleAttributes(note, theme: theme), x: x, midY: midY)
        if let subject = note.subject {
            x = drawText(subject, attributes: subjectAttributes(note, theme: theme), x: x, midY: midY)
        }
        let hints = hints(note)
        if !hints.isEmpty { GlassDrawing.drawHints(hints, x: x, midY: midY, theme: theme) }
    }

    /// 文字を描き，次の部品の左端を返す
    private static func drawText(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, midY: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return x }
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: x, y: (midY - size.height / 2).rounded()), withAttributes: attributes)
        return x + size.width.rounded(.up) + Glass.noteGap
    }

    // MARK: - 候補の横の札

    /// 札の幅
    static func tagWidth(_ text: String, theme: ResolvedTheme) -> CGFloat {
        (text.size(withAttributes: [.font: theme.labelFont(size: Glass.labelFontSize)]).width + Glass.tagPaddingX * 2).rounded(.up)
    }

    /// 候補の横の札(「修正」「入力のまま」，取り込んだ辞書の名前)．「修正」は補正の色の地，ほかは控えめな地．
    /// selected は選んでいる行の上(アクセント色の地)に描くとき
    static func drawTag(_ text: String, maxX: CGFloat, midY: CGFloat, theme: ResolvedTheme, selected: Bool) {
        let width = tagWidth(text, theme: theme)
        let rect = NSRect(x: (maxX - width).rounded(), y: (midY - Glass.tagHeight / 2).rounded(), width: width, height: Glass.tagHeight)
        let corrected = text == CandidatePanel.correctedAnnotation
        let fill: NSColor = selected ? theme.selectionText.withAlphaComponent(DesignTokens.Opacity.Badge.selected)
            : corrected ? theme.correctionTint : theme.badge
        let color: NSColor = selected ? theme.selectionText : corrected ? theme.correction : theme.textMuted
        fill.setFill()
        let radius = theme.isRounded ? Glass.tagRadius : 0
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        GlassDrawing.drawCentered(text, attributes: [.font: theme.labelFont(size: Glass.labelFontSize), .foregroundColor: color], in: rect)
    }
}
