import AppKit
import HajimeApplication

/// 連想の一覧(R-18)の見出しの行を描く．一覧(CandidateView)と分岐図(BranchView)で同じ形にする．
/// 左に「連想」と元の語と今の意味の説明，右に意味のまとまりの位置(「1 / 3」)を置く
@MainActor
enum AssociationHeadingDrawing {
    private typealias Size = DesignTokens.Size.Candidate

    /// 行に要る幅(左右の余白を除く)
    static func width(_ heading: AssociationHeading, font: NSFont, emphasis: NSFont) -> CGFloat {
        let parts = leftParts(heading)
        let muted = parts.prefix.size(withAttributes: [.font: font]).width + parts.label.size(withAttributes: [.font: font]).width
        let headword = heading.headword.size(withAttributes: [.font: emphasis]).width
        let position = position(heading).size(withAttributes: [.font: font]).width
        return (muted + headword + position + Size.paddingX * 3).rounded(.up)
    }

    static func draw(_ heading: AssociationHeading, in rect: NSRect, theme: ResolvedTheme, font: NSFont, emphasis: NSFont) {
        let muted: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: theme.textMuted]
        let strong: [NSAttributedString.Key: Any] = [.font: emphasis, .foregroundColor: theme.text]
        let parts = leftParts(heading)
        var x = rect.minX
        x += drawText(parts.prefix, attributes: muted, x: x, in: rect)
        x += drawText(heading.headword, attributes: strong, x: x, in: rect)
        let position = position(heading)
        let positionWidth = position.size(withAttributes: muted).width
        _ = drawText(position, attributes: muted, x: rect.maxX - positionWidth, in: rect)
        if !parts.label.isEmpty {
            // 意味の説明は位置の手前までに収める
            let available = rect.maxX - positionWidth - Size.paddingX - x
            _ = drawText(truncated(parts.label, attributes: muted, width: available), attributes: muted, x: x, in: rect)
        }
    }

    private static func leftParts(_ heading: AssociationHeading) -> (prefix: String, label: String) {
        (UIStrings.Association.headingPrefix + "　", heading.label.isEmpty ? "" : "　" + heading.label)
    }

    private static func position(_ heading: AssociationHeading) -> String {
        heading.groupCount > 1 ? UIStrings.Association.groupPosition(heading.group, heading.groupCount) : ""
    }

    /// 縦に中央にそろえて描き，描いた幅を返す．座標は整数に丸め，文字の輪郭をぼかさない
    private static func drawText(_ text: String, attributes: [NSAttributedString.Key: Any], x: CGFloat, in rect: NSRect) -> CGFloat {
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: x.rounded(), y: rect.minY + ((rect.height - size.height) / 2).rounded()), withAttributes: attributes)
        return size.width
    }

    private static func truncated(_ text: String, attributes: [NSAttributedString.Key: Any], width: CGFloat) -> String {
        guard text.size(withAttributes: attributes).width > width else { return text }
        var characters = Array(text)
        while !characters.isEmpty, (String(characters) + "…").size(withAttributes: attributes).width > width { characters.removeLast() }
        return characters.isEmpty ? "" : String(characters) + "…"
    }
}
