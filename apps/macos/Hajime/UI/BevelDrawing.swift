import AppKit

/// プラチナ外観(platinum と desk)の縁取りを線で描く．glass は GlassDrawing が描く．画像は貼らない(docs/dev/DESIGN-SYSTEM.md の「レトロな表現は描画で出す」)．
enum BevelDrawing {
    /// rect の外側に 1 ドットの外枠，その内側に光の縁(左と上)と影の縁(右と下)を描き，面を塗る
    static func drawPanel(in rect: NSRect, theme: ResolvedTheme) {
        let line = DesignTokens.Size.Candidate.frameWidth
        theme.frame.setFill()
        rect.fill()
        let inner = rect.insetBy(dx: line, dy: line)
        theme.surface.setFill()
        inner.fill()
        let bevel = DesignTokens.Size.Candidate.bevelWidth
        theme.bevelLight.setFill()
        // AppKit の座標は下が原点なので，上の縁は maxY の側
        NSRect(x: inner.minX, y: inner.maxY - bevel, width: inner.width, height: bevel).fill()
        NSRect(x: inner.minX, y: inner.minY, width: bevel, height: inner.height).fill()
        theme.bevelShadow.setFill()
        NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: bevel).fill()
        NSRect(x: inner.maxX - bevel, y: inner.minY, width: bevel, height: inner.height).fill()
    }

    /// ぼかしの無い影(desk だけ)．上下が反転した(isFlipped の)ビューで，右と下に出す
    static func drawDropShadow(for rect: NSRect, theme: ResolvedTheme) {
        guard theme.hasDropShadow else { return }
        let offset = DesignTokens.Size.Candidate.shadowOffset
        theme.frame.setFill()
        rect.offsetBy(dx: offset, dy: offset).fill()
    }

    static func drawSeparator(y: CGFloat, from minX: CGFloat, to maxX: CGFloat, theme: ResolvedTheme) {
        theme.line.setFill()
        NSRect(x: minX, y: y, width: maxX - minX, height: DesignTokens.Size.Candidate.frameWidth).fill()
    }
}
