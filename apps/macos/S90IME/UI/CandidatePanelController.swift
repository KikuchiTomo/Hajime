import AppKit
import S90Application
import S90Domain

/// 候補ウィンドウを出し入れする．ウィンドウはアプリ全体で 1 つだけ使い回す．
@MainActor
final class CandidatePanelController {
    private let window: NSPanel
    private let view = CandidateView()
    private var fadeTimer: Timer?
    private var lastAnnounced: String?

    init() {
        window = FloatingPanel.make(contentView: view)
    }

    func show(_ panel: CandidatePanel, caret: NSRect, theme: ThemePreference, fontSize: Double) {
        let wasVisible = window.isVisible
        view.theme = ResolvedTheme.resolve(theme)
        view.fontSize = CGFloat(fontSize)
        view.panel = panel
        let size = view.fittingSize(for: panel)
        let origin = FloatingPanel.origin(for: size, caret: caret)
        window.setFrame(NSRect(origin: origin, size: size), display: true)
        if !wasVisible {
            startRestFadeIn()
            window.orderFrontRegardless()
        }
        announceSelection(panel)
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
            view.restOpacity = 1
            return
        }
        view.restOpacity = 0
        let duration = DesignTokens.Motion.CandidateRest.fadeIn / 1000
        let start = Date()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: Self.frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.stepFade(start: start, duration: duration) }
        }
    }

    private static let frameInterval: TimeInterval = 1.0 / 60

    private func stepFade(start: Date, duration: TimeInterval) {
        let progress = min(Date().timeIntervalSince(start) / duration, 1)
        view.restOpacity = CGFloat(progress)
        if progress >= 1 {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
    }

    /// VoiceOver が動いているときだけ，選んでいる候補を読み上げる
    private func announceSelection(_ panel: CandidatePanel) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let text: String? = switch panel.focus {
        case .candidate: panel.selectedEntry.flatMap { panel.entries.indices.contains($0) ? panel.entries[$0].text : nil }
        case .variants: panel.selectedVariant.flatMap { panel.variants.indices.contains($0) ? panel.variants[$0].label : nil }
        }
        guard let text, text != lastAnnounced else { return }
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
