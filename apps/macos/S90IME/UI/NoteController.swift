import AppKit
import S90Domain

/// 入力位置の下に短い案内を出す(打ち間違いを直したこと・「もしかして」)．
/// 候補ウィンドウと同じ場所に出すが，案内を出すのは読みを組み立てているあいだだけなので重ならない．
/// 消すのは候補ウィンドウと同じ時機(ClientAction.hideCandidates)
@MainActor
final class NoteController {
    private let view = NoteView()
    private let backdrop = GlassBackdrop()
    private let window: NSPanel

    init() {
        window = FloatingPanel.make(contentView: view)
    }

    func show(_ text: String, caret: NSRect, theme: ThemePreference) {
        view.theme = ResolvedTheme.resolve(theme)
        view.text = text
        let size = view.fittingSize
        _ = FloatingPanel.attach(view, to: window, backdrop: view.theme.isGlass ? backdrop : nil)
        window.setFrame(NSRect(origin: FloatingPanel.origin(for: size, caret: caret), size: size), display: true)
        if view.theme.isGlass { window.invalidateShadow() }
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }
}

final class NoteView: NSView {
    private typealias Glass = DesignTokens.Size.Glass
    private typealias Size = DesignTokens.Size.Candidate

    var text = "" { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: theme.labelFont(size: Glass.labelFontSize + 1), .foregroundColor: theme.correction]
    }

    private var padding: CGFloat { theme.isGlass ? Glass.padding : Size.paddingX }

    override var fittingSize: NSSize {
        let size = text.size(withAttributes: attributes)
        let inset = theme.isGlass ? 0 : Size.frameWidth + Size.bevelWidth
        return NSSize(width: (size.width + (padding + inset) * 2).rounded(.up), height: (size.height + (Size.sectionPaddingY + inset) * 2 + 4).rounded(.up))
    }

    override func draw(_ dirtyRect: NSRect) {
        if theme.isGlass {
            GlassDrawing.drawFrame(in: bounds, theme: theme, fillsSurface: false)
        } else {
            BevelDrawing.drawPanel(in: bounds, theme: theme)
        }
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()), withAttributes: attributes)
    }
}
