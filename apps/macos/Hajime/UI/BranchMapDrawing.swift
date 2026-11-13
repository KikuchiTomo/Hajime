import AppKit
import HajimeApplication

/// 分岐図の部品を描く．線の上の丸，丸を避けて引く線，背景と反転した色のキーの案内，文節の境目のつまみ．
///
/// 角丸のテーマは丸と丸い角の線，platinum と desk は四角と 1 ドットの線(デバイスのピクセルにそろえる)で描く．
/// 上下が反転した(isFlipped の)ビューで使う
@MainActor
enum BranchMapDrawing {
    private typealias Map = DesignTokens.Size.BranchMap
    private typealias Glass = DesignTokens.Size.Glass
    private typealias Part = DesignTokens.Size.Part
    private typealias Space = DesignTokens.Size.Space

    /// 線の上の丸．文節・候補・文字種・意味のどれも同じ形にする
    struct Stop {
        enum State {
            /// 選んでいない
            case plain
            /// 選んだ道すじの途中にある
            case passed
            /// 選んでいる
            case selected
        }

        var center: NSPoint
        var state = State.plain
        var opacity: CGFloat = 1

        var size: CGFloat { state == .selected ? Map.stopSizeSelected : Map.stopSize }

        var rect: NSRect {
            NSRect(x: (center.x - size / 2).rounded(), y: (center.y - size / 2).rounded(), width: size, height: size)
        }
    }

    /// 折れ線．points を順につなぎ，角は radius で丸める(0 なら直角)
    struct Line {
        var points: [NSPoint]
        var radius: CGFloat = 0
        /// 点線にする(確信の低い文節の下の幹)
        var dotted = false
    }

    // MARK: - 線

    /// 線を描く．丸(stops)の内側には線を通さず，丸を輪で描けるようにする
    static func stroke(_ lines: [Line], color: NSColor, width: CGFloat, avoiding stops: [Stop], in bounds: NSRect, theme: ResolvedTheme) {
        guard !lines.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let clip = NSBezierPath(rect: bounds)
        for stop in stops { clip.append(outline(of: stop, theme: theme)) }
        clip.windingRule = .evenOdd
        clip.addClip()
        color.setStroke()
        color.setFill()
        for line in lines where line.points.count > 1 {
            if theme.isRounded {
                strokeRounded(line, width: width)
            } else {
                fillCrisp(line, width: width)
            }
        }
    }

    private static func strokeRounded(_ line: Line, width: CGFloat) {
        let path = NSBezierPath()
        path.move(to: line.points[0])
        for index in 1..<line.points.count {
            if index < line.points.count - 1, line.radius > 0 {
                path.appendArc(from: line.points[index], to: line.points[index + 1], radius: line.radius)
            } else {
                path.line(to: line.points[index])
            }
        }
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if line.dotted { path.setLineDash([0, Glass.dotPitch], count: 2, phase: 0) }
        path.stroke()
    }

    /// platinum と desk: 縦か横の線を，1 ドットの幅の四角で塗る(線をぼかさない)
    private static func fillCrisp(_ line: Line, width: CGFloat) {
        for index in 1..<line.points.count {
            let from = line.points[index - 1], to = line.points[index]
            let minX = min(from.x, to.x).rounded(), minY = min(from.y, to.y).rounded()
            let horizontal = abs(from.y - to.y) < abs(from.x - to.x)
            let length = (horizontal ? abs(from.x - to.x) : abs(from.y - to.y)).rounded() + width
            let rect = horizontal ? NSRect(x: minX, y: minY, width: length, height: width) : NSRect(x: minX, y: minY, width: width, height: length)
            guard line.dotted else {
                rect.fill()
                continue
            }
            var x = rect.minX
            while x < rect.maxX {
                NSRect(x: x, y: rect.minY, width: width, height: width).fill()
                x += width * 2
            }
        }
    }

    /// 続きがある印．from から to へ，端へ向けて透かした線を引く(畳んでいる枝)．縦か横の線
    static func drawFadingLine(from: NSPoint, to: NSPoint, color: NSColor, width: CGFloat) {
        let rect = NSRect(x: min(from.x, to.x) - width / 2, y: min(from.y, to.y) - width / 2, width: abs(from.x - to.x) + width,
                          height: abs(from.y - to.y) + width)
        guard let gradient = NSGradient(starting: color, ending: color.withAlphaComponent(0)) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        gradient.draw(from: from, to: to, options: [])
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: - 丸

    private static func outline(of stop: Stop, theme: ResolvedTheme) -> NSBezierPath {
        theme.isRounded ? NSBezierPath(ovalIn: stop.rect) : NSBezierPath(rect: stop.rect)
    }

    /// 丸を描く．選んでいる丸は選択の色で塗り，道すじの途中の丸は選択の色の輪，ほかは線の色の輪
    static func draw(_ stops: [Stop], lineWidth: CGFloat, theme: ResolvedTheme) {
        for stop in stops {
            switch stop.state {
            case .selected:
                theme.selection.withAlphaComponent(stop.opacity).setFill()
                outline(of: stop, theme: theme).fill()
            case .passed, .plain:
                let color = stop.state == .passed ? theme.selection : theme.line
                color.withAlphaComponent(color.alphaComponent * stop.opacity).setStroke()
                let inset = lineWidth / 2
                let ring = stop.rect.insetBy(dx: inset, dy: inset)
                let path = theme.isRounded ? NSBezierPath(ovalIn: ring) : NSBezierPath(rect: ring)
                path.lineWidth = lineWidth
                path.stroke()
            }
        }
    }

    // MARK: - キーの案内

    /// 案内の部品．キーごとの部品の並びと，そのあとの言葉
    private static func keyWidth(_ hint: KeyHint, theme: ResolvedTheme) -> CGFloat {
        let caps = hint.keycaps
        let parts = caps.map { parts in
            parts.map { GlassDrawing.partWidth($0, theme: theme) }.reduce(0, +) + Glass.keycapPartGap * CGFloat(max(parts.count - 1, 0))
        }
        return parts.reduce(0, +) + Glass.keycapGap * CGFloat(max(caps.count - 1, 0))
    }

    private static func labelAttributes(_ theme: ResolvedTheme, color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: theme.labelFont(size: Glass.keyFontSize), .foregroundColor: color]
    }

    /// 案内の幅．キーと言葉を 1 つの面で囲む
    static func hintWidth(_ hint: KeyHint, theme: ResolvedTheme) -> CGFloat {
        let label = hint.label.isEmpty ? 0 : hint.label.size(withAttributes: labelAttributes(theme, color: theme.hintInk)).width.rounded(.up) + Space.inline
        return max(Glass.tagHeight, Part.tagPaddingX * 2 + keyWidth(hint, theme: theme) + label)
    }

    /// 案内を並べた幅
    static func hintsWidth(_ hints: [KeyHint], theme: ResolvedTheme) -> CGFloat {
        guard !hints.isEmpty else { return 0 }
        return hints.map { hintWidth($0, theme: theme) }.reduce(0, +) + Glass.hintGap * CGFloat(hints.count - 1)
    }

    /// 案内を x から描く．文字の色の面に，背景の色の文字(候補の中身と見分ける)．selected なら選択の色の面
    static func drawHint(_ hint: KeyHint, x: CGFloat, midY: CGFloat, theme: ResolvedTheme, selected: Bool = false) {
        let width = hintWidth(hint, theme: theme)
        let rect = NSRect(x: x.rounded(), y: (midY - Glass.tagHeight / 2).rounded(), width: width, height: Glass.tagHeight)
        (selected ? theme.selection : theme.hintFill).setFill()
        if theme.isRounded {
            NSBezierPath(roundedRect: rect, xRadius: Glass.tagRadius, yRadius: Glass.tagRadius).fill()
        } else {
            rect.fill()
        }
        let ink = selected ? theme.selectionText : theme.hintInk
        var partX = rect.minX + Part.tagPaddingX
        // 言葉の無い案内(キーだけ)は，面の真ん中に置く
        if hint.label.isEmpty { partX = rect.midX - keyWidth(hint, theme: theme) / 2 }
        for (index, parts) in hint.keycaps.enumerated() {
            if index > 0 { partX += Glass.keycapGap - Glass.keycapPartGap }
            for part in parts {
                let partWidth = GlassDrawing.partWidth(part, theme: theme)
                GlassDrawing.drawPart(part, in: NSRect(x: partX, y: rect.minY, width: partWidth, height: rect.height), theme: theme, color: ink)
                partX += partWidth + Glass.keycapPartGap
            }
        }
        guard !hint.label.isEmpty else { return }
        TextFitting.draw(hint.label, attributes: labelAttributes(theme, color: ink), x: partX - Glass.keycapPartGap + Space.inline, midY: rect.midY)
    }

    /// 案内を左から並べて描く
    static func drawHints(_ hints: [KeyHint], x: CGFloat, midY: CGFloat, theme: ResolvedTheme) {
        var x = x
        for hint in hints {
            drawHint(hint, x: x, midY: midY, theme: theme)
            x += hintWidth(hint, theme: theme) + Glass.hintGap
        }
    }

    // MARK: - キーだけの印

    /// 文字種の前に置く，キーだけの印の幅．候補の番号と同じキーキャップの形
    static func keyWidth(_ key: String, theme: ResolvedTheme) -> CGFloat {
        max(Glass.tagHeight, Part.tagPaddingX * 2 + keyWidth(KeyHint(key: key, label: ""), theme: theme))
    }

    /// キーだけの印を x から描く．selected なら選択の背景の上の描き方
    static func drawKey(_ key: String, x: CGFloat, midY: CGFloat, theme: ResolvedTheme, selected: Bool) {
        let hint = KeyHint(key: key, label: "")
        let rect = NSRect(x: x.rounded(), y: (midY - Glass.tagHeight / 2).rounded(), width: keyWidth(key, theme: theme), height: Glass.tagHeight)
        if selected {
            theme.selectionText.withAlphaComponent(DesignTokens.Opacity.Badge.selected).setFill()
            if theme.isRounded {
                NSBezierPath(roundedRect: rect, xRadius: Glass.keycapRadius, yRadius: Glass.keycapRadius).fill()
            } else {
                rect.fill()
            }
        } else {
            GlassDrawing.drawKeycap(rect, theme: theme)
        }
        let ink = selected ? theme.selectionText : theme.textMuted
        var partX = rect.midX - keyWidth(hint, theme: theme) / 2
        for (index, parts) in hint.keycaps.enumerated() {
            if index > 0 { partX += Glass.keycapGap - Glass.keycapPartGap }
            for part in parts {
                let partWidth = GlassDrawing.partWidth(part, theme: theme)
                GlassDrawing.drawPart(part, in: NSRect(x: partX, y: rect.minY, width: partWidth, height: rect.height), theme: theme, color: ink)
                partX += partWidth + Glass.keycapPartGap
            }
        }
    }

    // MARK: - 境目のつまみ

    /// 文節の境目のつまみ．縦の線と，左右の山形(境目を左右へ動かせる印)
    static func drawGrip(x: CGFloat, midY: CGFloat, height: CGFloat, theme: ResolvedTheme) {
        let bar = Glass.editingCaretWidth
        theme.selection.setFill()
        NSRect(x: (x - bar / 2).rounded(), y: (midY - height / 2).rounded(), width: bar, height: height.rounded()).fill()
        let size = Map.gripSize
        let path = NSBezierPath()
        for side in [CGFloat(-1), 1] {
            let tip = x + side * (bar / 2 + Space.fine + size)
            path.move(to: NSPoint(x: tip - side * size, y: midY - size))
            path.line(to: NSPoint(x: tip, y: midY))
            path.line(to: NSPoint(x: tip - side * size, y: midY + size))
        }
        path.lineWidth = Glass.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        theme.selection.setStroke()
        path.stroke()
    }

    // MARK: - はみ出した幹

    /// body を描き，left・right の側を端へ向けて透かす．幹が窓からはみ出していることを見せる
    static func fading(left: Bool, right: Bool, in bounds: NSRect, body: () -> Void) {
        guard left || right, let context = NSGraphicsContext.current?.cgContext else {
            body()
            return
        }
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        context.setBlendMode(.destinationIn)
        let fade = min(Map.fadeWidth / max(bounds.width, 1), 0.5)
        let colors = [NSColor.black.withAlphaComponent(left ? 0 : 1), .black, .black, NSColor.black.withAlphaComponent(right ? 0 : 1)].map(\.cgColor)
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, fade, 1 - fade, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: bounds.minX, y: 0), end: CGPoint(x: bounds.maxX, y: 0),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
