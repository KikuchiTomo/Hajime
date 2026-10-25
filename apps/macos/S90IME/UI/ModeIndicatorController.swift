import AppKit
import S90Domain

/// 入力モードを切り替えたとき，入力位置の近くに小さな札を出す(docs/dev/DESIGN-SYSTEM.md の「モードの表示」)．
@MainActor
final class ModeIndicatorController {
    private let view = ModeIndicatorView()
    private let window: NSPanel
    private var hideTask: Task<Void, Never>?

    init() {
        window = FloatingPanel.make(contentView: view)
    }

    func show(_ mode: InputMode, caret: NSRect, theme: ThemePreference) {
        view.theme = ResolvedTheme.resolve(theme)
        view.label = UIStrings.ModeIndicator.label(for: mode)
        let size = view.fittingSize
        window.setFrame(NSRect(origin: FloatingPanel.origin(for: size, caret: caret), size: size), display: true)
        window.alphaValue = 1
        window.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(DesignTokens.Motion.ModeIndicator.visible))
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    private func fadeOut() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = DesignTokens.Motion.ModeIndicator.fade / 1000
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.window.orderOut(nil) }
        })
    }
}

private final class ModeIndicatorView: NSView {
    private typealias Size = DesignTokens.Size.ModeIndicator

    var label = "" { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }

    private var attributes: [NSAttributedString.Key: Any] {
        [.font: ResolvedTheme.labelFont(size: Size.fontSize), .foregroundColor: theme.text]
    }

    override var fittingSize: NSSize {
        let text = label.size(withAttributes: attributes)
        let inset = DesignTokens.Size.Candidate.frameWidth + DesignTokens.Size.Candidate.bevelWidth
        return NSSize(width: (text.width + Size.paddingX * 2 + inset * 2).rounded(.up), height: (text.height + Size.paddingY * 2 + inset * 2).rounded(.up))
    }

    override func draw(_ dirtyRect: NSRect) {
        BevelDrawing.drawPanel(in: bounds, theme: theme)
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()), withAttributes: attributes)
    }
}
