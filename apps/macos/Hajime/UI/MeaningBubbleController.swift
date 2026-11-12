import AppKit
import HajimeApplication
import HajimeDomain

/// 語の意味の吹き出し(R-08)を出し入れする．候補の窓の子の窓にし，候補の窓の外に出す．
///
/// - 候補の窓の右に出し，画面の右の端に入らなければ左に出す．先(三角)は選んでいる候補の行の縦の真ん中を指す(core の MeaningBubbleLayout)
/// - 背景・枠線・角の丸み・影は候補の窓と同じ(角丸のテーマはすりガラスの背景を吹き出しの形に切り抜き，窓の影を付ける)
/// - 選んでいる候補が変わったら付いて動く．「視差効果を減らす」が有効ならすぐ移す
/// - フォーカスを取らず，マウスは通す(押しても受けない)
@MainActor
final class MeaningBubbleController {
    private let window: NSPanel
    private let view = MeaningBubbleView()
    private let backdrop = GlassBackdrop()
    private var isAnimating = false

    init() {
        window = FloatingPanel.make(contentView: view)
    }

    /// note を，選んでいる候補の行 row のすぐ横(行の右の端から inline)に出し，先で行の縦の真ん中を指す．
    /// 候補の窓 anchor の空いている所に重ねてよいが，obstacles(ほかの候補・幹の文節・足元の案内・入力中の文字)は覆わない．
    /// 座標はどれも画面の座標．others は同音語のタグに出す語，screen は画面の使える範囲
    func show(_ note: HomophoneNote, others: [String], theme: ResolvedTheme, row: NSRect, anchor: NSRect, obstacles: [NSRect], screen: NSRect,
              parent: NSWindow) {
        let metrics = MeaningBubbleLayout.Metrics.tokens(rounded: theme.isRounded)
        let header = MeaningCardDrawing.headerHeight(theme: theme)
        let content = MeaningCardDrawing.layout(note, others: others, width: metrics.width - metrics.padding * 2,
                                                placement: .init(left: 0, headerMidY: header / 2), theme: theme)
        // core の配置は上が y の小さい座標なので，画面の上の端から測り直す
        let top = screen.maxY
        let box = { (rect: NSRect) in MeaningBubbleLayout.Box(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height) }
        let placement = MeaningBubbleLayout(
            row: box(row), window: box(anchor),
            size: (metrics.width, content.size.height + metrics.padding * 2),
            preferredPointer: metrics.padding + header / 2,
            screen: .init(x: screen.minX, y: 0, width: screen.width, height: screen.height),
            obstacles: obstacles.map(box),
            metrics: metrics
        )
        let frame = NSRect(x: placement.window.x, y: top - placement.window.maxY, width: placement.window.width, height: placement.window.height)
        view.configure(content: content, placement: placement, metrics: metrics, theme: theme)
        let rounded = theme.isRounded
        if rounded {
            backdrop.host(view)
            backdrop.maskImage = view.mask(size: frame.size)
            if window.contentView !== backdrop { window.contentView = backdrop }
        } else if window.contentView !== view {
            window.contentView = view
        }
        window.hasShadow = rounded
        let wasVisible = window.isVisible && window.parent === parent
        if window.parent !== parent {
            window.parent?.removeChildWindow(window)
            parent.addChildWindow(window, ordered: .above)
        }
        move(to: frame, animated: wasVisible && frame != window.frame && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        view.needsDisplay = true
        if !wasVisible { window.orderFront(nil) }
    }

    func hide() {
        window.parent?.removeChildWindow(window)
        window.orderOut(nil)
    }

    /// 選んでいる候補が変わったときは滑らせて付いて動く．動いている途中に次が届いたら，今の動きを止めてすぐ移す
    private func move(to frame: NSRect, animated: Bool) {
        if animated, !isAnimating {
            isAnimating = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DesignTokens.Motion.CandidateWindow.resize / 1000
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.isAnimating = false
                    self?.window.invalidateShadow()
                }
            }
            return
        }
        if isAnimating {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                window.animator().setFrame(frame, display: true)
            }
            isAnimating = false
        } else {
            window.setFrame(frame, display: true)
        }
        window.invalidateShadow()
    }
}

/// 吹き出しの形(本体と先を 1 本の枠線でなぞる)と，中の語の意味を描く
final class MeaningBubbleView: NSView {
    private var content: MeaningCardDrawing.Layout?
    private var placement: MeaningBubbleLayout?
    private var metrics = MeaningBubbleLayout.Metrics.tokens(rounded: true)
    private var theme = ResolvedTheme.resolveStatic
    /// glass の面を自分で塗るか．ぼかしの背景の無いところ(画像への書き出し)で使う
    var fillsSurface = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    func configure(content: MeaningCardDrawing.Layout, placement: MeaningBubbleLayout, metrics: MeaningBubbleLayout.Metrics, theme: ResolvedTheme) {
        self.content = content
        self.placement = placement
        self.metrics = metrics
        self.theme = theme
        needsDisplay = true
    }

    /// 吹き出しの形の枠線．線の太さの半分だけ内側を通す
    private func outline() -> NSBezierPath? {
        guard let placement else { return nil }
        let outline = placement.outline(metrics: metrics, stroke: DesignTokens.Size.Part.stroke)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: outline.startX, y: outline.startY))
        for segment in outline.segments {
            switch segment {
            case let .line(x, y):
                path.line(to: NSPoint(x: x, y: y))
            case let .corner(cornerX, cornerY, toX, toY, radius):
                if radius > 0 {
                    path.appendArc(from: NSPoint(x: cornerX, y: cornerY), to: NSPoint(x: toX, y: toY), radius: radius)
                } else {
                    path.line(to: NSPoint(x: cornerX, y: cornerY))
                }
            }
        }
        path.close()
        return path
    }

    /// すりガラスの背景を吹き出しの形に切り抜く形(大きさ size の窓)
    func mask(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: true) { [weak self] _ in
            NSColor.black.setFill()
            self?.outline()?.fill()
            return true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let placement, let content, let path = outline() else { return }
        if fillsSurface || !theme.usesBackdrop || !theme.isRounded {
            theme.surface.setFill()
            path.fill()
        }
        theme.frame.setStroke()
        path.lineWidth = DesignTokens.Size.Part.stroke
        path.stroke()
        let inner = NSRect(x: placement.body.x + metrics.padding, y: placement.body.y + metrics.padding,
                           width: content.size.width, height: content.size.height)
        MeaningCardDrawing.drawContent(content, in: inner, theme: theme)
    }
}
