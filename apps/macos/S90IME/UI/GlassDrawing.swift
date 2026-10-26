import AppKit

/// すりガラスの見た目(glass)の部品を描く．地のぼかしは GlassBackdrop が受け持ち，ここでは縁と中身だけを描く
enum GlassDrawing {
    private typealias Glass = DesignTokens.Size.Glass

    /// 角丸の縁．fillsSurface が true なら面も塗る(ぼかしの無い画像に書き出すとき)
    static func drawFrame(in rect: NSRect, theme: ResolvedTheme, fillsSurface: Bool) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: Glass.cornerRadius, yRadius: Glass.cornerRadius)
        if fillsSurface {
            theme.surface.setFill()
            path.fill()
        }
        theme.frame.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// 選んでいるものの角丸の地
    static func fillCapsule(_ rect: NSRect, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: Glass.selectionRadius, yRadius: Glass.selectionRadius).fill()
    }

    /// 番号などを入れる小さな丸．selected は選んでいる行の上(アクセント色の地)に描くとき
    static func drawBadge(_ label: String, center: NSPoint, theme: ResolvedTheme, selected: Bool, opacity: CGFloat) {
        let size = Glass.badgeSize
        let rect = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        (selected ? theme.selectionText.withAlphaComponent(0.25) : theme.badge.withAlphaComponent(theme.badge.alphaComponent * opacity)).setFill()
        NSBezierPath(ovalIn: rect).fill()
        let color = (selected ? theme.selectionText : theme.textMuted).withAlphaComponent(selected ? 1 : opacity)
        drawCentered(label, attributes: [.font: theme.keyFont(size: Glass.keyFontSize), .foregroundColor: color], in: rect)
    }

    /// 枝の曲線．幹の下(上)の start から，候補の行の左の end へ，角を丸めて曲がる
    static func branchCurve(from start: NSPoint, to end: NSPoint) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: start)
        path.curve(to: end, controlPoint1: NSPoint(x: start.x, y: end.y), controlPoint2: NSPoint(x: start.x + (end.x - start.x) * 0.35, y: end.y))
        path.lineCapStyle = .round
        return path
    }

    // MARK: - 足元の案内

    /// 案内の幅．描くときと大きさを求めるときで同じものを使う
    static func hintsWidth(_ hints: [KeyHint], theme: ResolvedTheme) -> CGFloat {
        guard !hints.isEmpty else { return 0 }
        return hints.map { hintWidth($0, theme: theme) }.reduce(0, +) + Glass.hintGap * CGFloat(hints.count - 1)
    }

    /// キーキャップ風の札とその説明を左から並べる
    static func drawHints(_ hints: [KeyHint], x: CGFloat, midY: CGFloat, theme: ResolvedTheme) {
        var x = x
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: theme.labelFont(size: Glass.labelFontSize), .foregroundColor: theme.textMuted]
        for hint in hints {
            let cap = NSRect(x: x, y: (midY - Glass.keycapHeight / 2).rounded(), width: keycapWidth(hint.key, theme: theme), height: Glass.keycapHeight)
            let path = NSBezierPath(roundedRect: cap.insetBy(dx: 0.5, dy: 0.5), xRadius: Glass.keycapRadius, yRadius: Glass.keycapRadius)
            theme.badge.setFill()
            path.fill()
            theme.line.setStroke()
            path.lineWidth = 1
            path.stroke()
            drawCentered(hint.key, attributes: [.font: theme.keyFont(size: Glass.keyFontSize), .foregroundColor: theme.text], in: cap)
            let labelSize = hint.label.size(withAttributes: labelAttributes)
            hint.label.draw(at: NSPoint(x: cap.maxX + Glass.keycapPaddingX, y: (midY - labelSize.height / 2).rounded()), withAttributes: labelAttributes)
            x += hintWidth(hint, theme: theme) + Glass.hintGap
        }
    }

    private static func keycapWidth(_ key: String, theme: ResolvedTheme) -> CGFloat {
        let width = key.size(withAttributes: [.font: theme.keyFont(size: Glass.keyFontSize)]).width + Glass.keycapPaddingX * 2
        return max(Glass.keycapHeight, width.rounded(.up))
    }

    private static func hintWidth(_ hint: KeyHint, theme: ResolvedTheme) -> CGFloat {
        let label = hint.label.size(withAttributes: [.font: theme.labelFont(size: Glass.labelFontSize)]).width
        return keycapWidth(hint.key, theme: theme) + Glass.keycapPaddingX + label.rounded(.up)
    }

    // MARK: - 部品

    static func drawCentered(_ text: String, attributes: [NSAttributedString.Key: Any], in rect: NSRect) {
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
}

/// 足元に出す操作の案内．キーと，そのキーで何をするか
struct KeyHint: Equatable {
    var key: String
    var label: String

    /// platinum と desk は 1 行の文字で出す
    static func text(_ hints: [KeyHint]) -> String {
        hints.map { "\($0.key) \($0.label)" }.joined(separator: "　")
    }
}

/// glass の地．ウィンドウの後ろをぼかし，角を丸める．中身のビューを上に重ねる
final class GlassBackdrop: NSVisualEffectView {
    init() {
        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        maskImage = Self.mask(radius: DesignTokens.Size.Glass.cornerRadius)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 中身を入れ替える．中身はこのビューと同じ大きさに広げる
    func host(_ content: NSView) {
        guard content.superview !== self else { return }
        subviews.forEach { $0.removeFromSuperview() }
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)
    }

    /// 角丸の形．大きさが変わっても角の丸みが変わらないよう，角を残して伸ばす
    private static func mask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
