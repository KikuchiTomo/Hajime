import AppKit

/// すりガラスの見た目(glass)の部品を描く．地のぼかしは GlassBackdrop が受け持ち，ここでは縁と中身だけを描く
enum GlassDrawing {
    private typealias Glass = DesignTokens.Size.Glass

    /// 角丸の縁．fillsSurface が true なら面も塗る(ぼかしの無い画像に書き出すとき)．
    /// glass のほかの角丸のテーマは，ぼかしの地(GlassBackdrop)の上を色で塗りつぶす(角丸の形と窓の影は地の側が受け持つ)
    static func drawFrame(in rect: NSRect, theme: ResolvedTheme, fillsSurface: Bool) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: theme.cornerRadius, yRadius: theme.cornerRadius)
        if fillsSurface || !theme.usesBackdrop {
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
        drawLabel(label, color: color, in: rect, theme: theme)
    }

    /// 番号は文字で，矢印などの記号は SF Symbols のアイコンで描く
    static func drawLabel(_ label: String, color: NSColor, in rect: NSRect, theme: ResolvedTheme) {
        if case .symbol(let name)? = KeyHint.parts(of: label).first, label.count == 1,
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: Glass.keyFontSize - 1, weight: .bold).applying(NSImage.SymbolConfiguration(paletteColors: [color]))) {
            let size = image.size
            image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            return
        }
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

    /// キーキャップの札とその説明を左から並べる．キーは文字ではなく SF Symbols のアイコンで描く(KeyHint.Part)．
    /// 札の形はテーマに合わせる: 角丸のテーマは角丸，platinum は立体の縁，desk は文字の色の縁取り
    static func drawHints(_ hints: [KeyHint], x: CGFloat, midY: CGFloat, theme: ResolvedTheme) {
        var x = x
        let labelAttributes: [NSAttributedString.Key: Any] = [.font: theme.labelFont(size: Glass.labelFontSize), .foregroundColor: theme.textMuted]
        for hint in hints {
            let cap = NSRect(x: x, y: (midY - Glass.keycapHeight / 2).rounded(), width: keycapWidth(hint, theme: theme), height: Glass.keycapHeight)
            drawKeycap(cap, theme: theme)
            var partX = cap.minX + Glass.keycapPaddingX
            for part in hint.parts {
                let width = partWidth(part, theme: theme)
                drawPart(part, in: NSRect(x: partX, y: cap.minY, width: width, height: cap.height), theme: theme)
                partX += width + partGap
            }
            let labelSize = hint.label.size(withAttributes: labelAttributes)
            hint.label.draw(at: NSPoint(x: cap.maxX + Glass.keycapPaddingX, y: (midY - labelSize.height / 2).rounded()), withAttributes: labelAttributes)
            x += hintWidth(hint, theme: theme) + Glass.hintGap
        }
    }

    /// キーの部品のあいだの空き
    private static let partGap: CGFloat = 1

    private static func drawKeycap(_ cap: NSRect, theme: ResolvedTheme) {
        switch theme.kind {
        case .platinum:
            // 角の立った立体の札．外枠の内側に光の縁(左と上)と影の縁(右と下)
            theme.frame.setFill()
            cap.fill()
            let inner = cap.insetBy(dx: 1, dy: 1)
            theme.surface.setFill()
            inner.fill()
            theme.bevelLight.setFill()
            NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: 1).fill()
            NSRect(x: inner.minX, y: inner.minY, width: 1, height: inner.height).fill()
            theme.bevelShadow.setFill()
            NSRect(x: inner.minX, y: inner.maxY - 1, width: inner.width, height: 1).fill()
            NSRect(x: inner.maxX - 1, y: inner.minY, width: 1, height: inner.height).fill()
        case .desk:
            // 蛍光表示管の琥珀色で縁取った札
            theme.text.withAlphaComponent(0.12).setFill()
            cap.fill()
            theme.text.withAlphaComponent(0.6).setStroke()
            let path = NSBezierPath(rect: cap.insetBy(dx: 0.5, dy: 0.5))
            path.lineWidth = 1
            path.stroke()
        default:
            let path = NSBezierPath(roundedRect: cap.insetBy(dx: 0.5, dy: 0.5), xRadius: Glass.keycapRadius, yRadius: Glass.keycapRadius)
            theme.badge.setFill()
            path.fill()
            theme.line.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    private static func symbolImage(_ name: String, theme: ResolvedTheme) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: Glass.keyFontSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [theme.text]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    private static func partWidth(_ part: KeyHint.Part, theme: ResolvedTheme) -> CGFloat {
        switch part {
        case .symbol(let name): (symbolImage(name, theme: theme)?.size.width ?? Glass.keyFontSize).rounded(.up)
        case .text(let text): text.size(withAttributes: [.font: theme.keyFont(size: Glass.keyFontSize)]).width.rounded(.up)
        }
    }

    private static func drawPart(_ part: KeyHint.Part, in rect: NSRect, theme: ResolvedTheme) {
        switch part {
        case .symbol(let name):
            guard let image = symbolImage(name, theme: theme) else { return }
            let size = image.size
            image.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        case .text(let text):
            drawCentered(text, attributes: [.font: theme.keyFont(size: Glass.keyFontSize), .foregroundColor: theme.text], in: rect)
        }
    }

    private static func keycapWidth(_ hint: KeyHint, theme: ResolvedTheme) -> CGFloat {
        let parts = hint.parts.map { partWidth($0, theme: theme) }.reduce(0, +) + partGap * CGFloat(max(hint.parts.count - 1, 0))
        return max(Glass.keycapHeight, (parts + Glass.keycapPaddingX * 2).rounded(.up))
    }

    private static func hintWidth(_ hint: KeyHint, theme: ResolvedTheme) -> CGFloat {
        let label = hint.label.size(withAttributes: [.font: theme.labelFont(size: Glass.labelFontSize)]).width
        return keycapWidth(hint, theme: theme) + Glass.keycapPaddingX + label.rounded(.up)
    }

    // MARK: - 部品

    static func drawCentered(_ text: String, attributes: [NSAttributedString.Key: Any], in rect: NSRect) {
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attributes)
    }
}

/// 足元に出す操作の案内．キーと，そのキーで何をするか．
/// key は macOS のメニューと同じ記号で書いた名前(「⇧←」「←→」「Tab」「⌃⌥L」)．描くときはアイコンの部品に分ける
struct KeyHint: Equatable {
    var key: String
    var label: String

    /// キーキャップの中に並べる部品．記号は SF Symbols のアイコン，ほかは文字
    enum Part: Equatable {
        case symbol(String)
        case text(String)
    }

    var parts: [Part] { Self.parts(of: key) }

    /// 記号と SF Symbols の名前
    private static let symbols: [Character: String] = [
        "⌃": "control", "⌥": "option", "⇧": "shift", "⌘": "command",
        "↑": "arrow.up", "↓": "arrow.down", "←": "arrow.left", "→": "arrow.right",
        "⌫": "delete.left", "⌦": "delete.right",
    ]

    /// 名前で書くキー(KeyStroke.label)のうち，アイコンで描くもの
    private static let namedSymbols: [(String, String)] = [
        ("←→", "arrow.left.and.right"), ("Tab", "arrow.right.to.line"), ("Space", "space"), ("Enter", "return"), ("Esc", "escape"),
    ]

    static func parts(of key: String) -> [Part] {
        var parts: [Part] = []
        var rest = Substring(key)
        var text = ""
        func flushText() {
            // 1 文字の英字はキーの刻印と同じ大文字にする．名前(「Home」)はそのまま
            if !text.isEmpty { parts.append(.text(text.count == 1 ? text.uppercased() : text)) }
            text = ""
        }
        while let first = rest.first {
            if let (name, symbol) = namedSymbols.first(where: { rest.hasPrefix($0.0) }) {
                flushText()
                parts.append(.symbol(symbol))
                rest = rest.dropFirst(name.count)
            } else if let name = symbols[first] {
                flushText()
                parts.append(.symbol(name))
                rest = rest.dropFirst()
            } else {
                // 記号でない文字は続けて 1 つの文字の部品にする(「L」「F7」「変換」)
                text.append(first)
                rest = rest.dropFirst()
            }
        }
        flushText()
        return parts
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

    /// 角の丸さ(カスタムテーマで変わる)．変わったときだけ形を作り直す
    var cornerRadius: CGFloat = DesignTokens.Size.Glass.cornerRadius {
        didSet {
            guard cornerRadius != oldValue else { return }
            maskImage = Self.mask(radius: max(cornerRadius, 0.5))
        }
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
