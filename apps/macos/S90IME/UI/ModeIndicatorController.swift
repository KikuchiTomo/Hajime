import AppKit
import S90Domain

/// 入力モードを切り替えたとき，入力位置の近くに小さな札を出す(docs/dev/DESIGN-SYSTEM.md の「モードの表示」)．
@MainActor
final class ModeIndicatorController {
    private let view = ModeIndicatorView()
    private let backdrop = GlassBackdrop()
    private let window: NSPanel
    private var hideTask: Task<Void, Never>?

    init() {
        window = FloatingPanel.make(contentView: view)
    }

    func show(_ mode: InputMode, caret: NSRect, theme: ThemePreference) {
        show(label: UIStrings.ModeIndicator.label(for: mode), caret: caret, theme: theme)
    }

    func show(_ style: InputStyle, caret: NSRect, theme: ThemePreference) {
        show(label: UIStrings.ModeIndicator.label(for: style), caret: caret, theme: theme)
    }

    private func show(label: String, caret: NSRect, theme: ThemePreference) {
        view.theme = ResolvedTheme.resolve(theme)
        view.label = label
        let size = view.fittingSize
        _ = FloatingPanel.attach(view, to: window, backdrop: view.theme.isGlass ? backdrop : nil)
        window.setFrame(NSRect(origin: FloatingPanel.origin(for: size, caret: caret), size: size), display: true)
        if view.theme.isGlass { window.invalidateShadow() }
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

final class ModeIndicatorView: NSView {
    private typealias Size = DesignTokens.Size.ModeIndicator
    private typealias Glass = DesignTokens.Size.Glass

    var label = "" { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }
    /// glass の面を自分で塗るか．ぼかしの地の無いところ(画像への書き出し)で使う
    var fillsSurface = false { didSet { needsDisplay = true } }

    private var attributes: [NSAttributedString.Key: Any] {
        let font = theme.isGlass ? NSFont.systemFont(ofSize: Glass.modeIndicatorFontSize, weight: .semibold) : theme.labelFont(size: Size.fontSize)
        return [.font: font, .foregroundColor: theme.text]
    }

    /// glass は角丸の正方形(文字が長いときは横に伸ばす)，platinum と desk は文字に合わせた札
    override var fittingSize: NSSize {
        let text = label.size(withAttributes: attributes)
        if theme.isGlass {
            let width = max(Glass.modeIndicatorSize, text.width + Size.paddingX * 2)
            return NSSize(width: width.rounded(.up), height: Glass.modeIndicatorSize)
        }
        let inset = DesignTokens.Size.Candidate.frameWidth + DesignTokens.Size.Candidate.bevelWidth
        return NSSize(width: (text.width + Size.paddingX * 2 + inset * 2).rounded(.up), height: (text.height + Size.paddingY * 2 + inset * 2).rounded(.up))
    }

    override func draw(_ dirtyRect: NSRect) {
        if theme.isGlass {
            GlassDrawing.drawFrame(in: bounds, theme: theme, fillsSurface: fillsSurface)
        } else {
            BevelDrawing.drawPanel(in: bounds, theme: theme)
        }
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded()), withAttributes: attributes)
    }
}
