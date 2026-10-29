import AppKit
import HajimeApplication
import HajimeDomain

/// 候補ウィンドウ(一覧と分岐図)を出し入れする．ウィンドウはアプリ全体で 1 つだけ使い回す．
@MainActor
final class CandidatePanelController {
    private let window: NSPanel
    private let view = CandidateView()
    private let branchView = BranchView()
    private let backdrop = GlassBackdrop()
    private var fadeTimer: Timer?
    private var lastAnnounced: String?

    /// 候補をマウスで押したときに知らせる先．押した対象(PointerTarget)を渡す
    var onChoose: ((PointerTarget) -> Void)? {
        didSet {
            view.onChoose = onChoose
            branchView.onChoose = onChoose
        }
    }

    init() {
        window = FloatingPanel.make(contentView: view)
        // 候補を押して選べるようにする．窓は前に出ない(フォーカスを入力先のアプリから移さない)
        window.ignoresMouseEvents = false
    }

    func show(_ panel: CandidatePanel, caret: NSRect, theme: ThemeChoice, fontSize: Double, keys: Keymap) {
        view.keys = keys
        view.theme = ResolvedTheme.resolve(theme)
        view.fontSize = CGFloat(fontSize)
        view.panel = panel
        present(view, size: view.fittingSize(for: panel), caret: caret, theme: view.theme)
        announceSelection(panel)
    }

    func showLattice(_ panel: LatticePanel, caret: NSRect, theme: ThemeChoice, fontSize: Double, keys: Keymap, showsHints: Bool) {
        branchView.keys = keys
        branchView.showsHints = showsHints
        branchView.theme = ResolvedTheme.resolve(theme)
        branchView.fontSize = CGFloat(fontSize)
        branchView.panel = panel
        present(branchView, size: branchView.fittingSize(for: panel), caret: caret, theme: branchView.theme)
        if let focused = panel.columns.first(where: \.isFocused) {
            announce(focused.text)
        }
    }

    /// glass はすりガラスの地(GlassBackdrop)の上に中身を重ね，ウィンドウの影を付ける
    private func present(_ content: NSView, size: NSSize, caret: NSRect, theme: ResolvedTheme) {
        let glass = theme.isRounded
        backdrop.cornerRadius = theme.cornerRadius
        let wasVisible = FloatingPanel.attach(content, to: window, backdrop: glass ? backdrop : nil)
        window.setFrame(NSRect(origin: FloatingPanel.origin(for: size, caret: caret), size: size), display: true)
        if glass { window.invalidateShadow() }
        if !wasVisible {
            startRestFadeIn()
            window.orderFrontRegardless()
        }
    }

    func hide() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        lastAnnounced = nil
        window.orderOut(nil)
    }

    /// 第 1 候補はすぐに出し，残りを位置を変えずに濃くしていく．
    /// 「視差効果を減らす」が有効なら，最初から濃く出す
    private func startRestFadeIn() {
        fadeTimer?.invalidate()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setRestOpacity(1)
            return
        }
        setRestOpacity(0)
        let duration = DesignTokens.Motion.CandidateRest.fadeIn / 1000
        let start = Date()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepFade(start: start, duration: duration) }
        }
    }

    private static let frameInterval: TimeInterval = 1.0 / 60

    private func stepFade(start: Date, duration: TimeInterval) {
        let progress = min(Date().timeIntervalSince(start) / duration, 1)
        setRestOpacity(CGFloat(progress))
        if progress >= 1 {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
    }

    private func setRestOpacity(_ value: CGFloat) {
        view.restOpacity = value
        branchView.restOpacity = value
    }

    /// VoiceOver が動いているときだけ，選んでいる候補を読み上げる
    private func announceSelection(_ panel: CandidatePanel) {
        let text: String? = switch panel.focus {
        case .candidate: panel.selectedEntry.flatMap { panel.entries.indices.contains($0) ? panel.entries[$0].text : nil }
        case .variants: panel.selectedVariant.flatMap { panel.variants.indices.contains($0) ? panel.variants[$0].label : nil }
        }
        announce(text)
    }

    private func announce(_ text: String?) {
        guard NSWorkspace.shared.isVoiceOverEnabled, let text, text != lastAnnounced else { return }
        lastAnnounced = text
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}

/// フォーカスを奪わず，入力先のアプリの上に浮かぶウィンドウ
@MainActor
enum FloatingPanel {
    static func make(contentView: NSView) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = contentView
        return panel
    }

    /// 中身をウィンドウに付ける．backdrop を渡したら，その上に重ねて影を付ける．
    /// 付ける前から同じ中身が見えていたら true を返す
    static func attach(_ content: NSView, to window: NSWindow, backdrop: GlassBackdrop?) -> Bool {
        let root: NSView = backdrop ?? content
        let wasVisible = window.isVisible && window.contentView === root && (backdrop == nil || content.superview === backdrop)
        if let backdrop { backdrop.host(content) }
        if window.contentView !== root { window.contentView = root }
        window.hasShadow = backdrop != nil
        return wasVisible
    }

    /// 入力位置の行の長方形から，ウィンドウの左下の座標を決める．規則は core の PanelPlacement
    static func origin(for size: NSSize, caret: NSRect) -> NSPoint {
        // 入力位置を教えないアプリでは，マウスの位置の近くに出す
        let anchor = caret == .zero ? NSRect(origin: NSEvent.mouseLocation, size: .zero) : caret
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = PanelPlacement.origin(
            caret: Rect(x: anchor.minX, y: anchor.minY, width: anchor.width, height: anchor.height),
            size: Rect(x: 0, y: 0, width: size.width, height: size.height),
            screen: Rect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height)
        )
        return NSPoint(x: origin.x.rounded(), y: origin.y.rounded())
    }
}
