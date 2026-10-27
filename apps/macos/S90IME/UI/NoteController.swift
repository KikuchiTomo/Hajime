import AppKit
import S90Application
import S90Domain

/// 入力位置の下に短い案内を出す(打ち間違いを直したこと・「もしかして」)．
/// 候補ウィンドウと同じ場所に出す．候補ウィンドウを出すとき(ClientActionPresenter)と hideCandidates で消す
@MainActor
final class NoteController {
    private let view = NoteView()
    private let backdrop = GlassBackdrop()
    private let window: NSPanel

    init() {
        window = FloatingPanel.make(contentView: view)
    }

    func show(_ note: Note, caret: NSRect, theme: ThemeChoice) {
        view.theme = ResolvedTheme.resolve(theme)
        view.note = note
        let size = view.fittingSize
        backdrop.cornerRadius = view.theme.cornerRadius
        _ = FloatingPanel.attach(view, to: window, backdrop: view.theme.isRounded ? backdrop : nil)
        window.setFrame(NSRect(origin: FloatingPanel.origin(for: size, caret: caret), size: size), display: true)
        if view.theme.isRounded { window.invalidateShadow() }
        window.orderFrontRegardless()
        // VoiceOver が動いているときは，案内を読み上げる
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
                .announcement: note.text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
        }
    }

    func hide() {
        window.orderOut(nil)
    }
}

final class NoteView: NSView {
    private typealias Glass = DesignTokens.Size.Glass
    private typealias Size = DesignTokens.Size.Candidate

    var note = Note.info("") { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }

    private var padding: CGFloat { theme.isRounded ? Glass.padding : Size.paddingX }
    private var inset: CGFloat { theme.isRounded ? 0 : Size.frameWidth + Size.bevelWidth }

    override var fittingSize: NSSize {
        let height = max(Glass.noteIconSize, Glass.keycapHeight, theme.labelFont(size: Glass.labelFontSize).boundingRectForFont.height)
        return NSSize(width: (NoteDrawing.width(note, theme: theme) + (padding + inset) * 2).rounded(.up),
                      height: max(Glass.footerHeight, height + (Size.sectionPaddingY + inset) * 2).rounded(.up))
    }

    override func draw(_ dirtyRect: NSRect) {
        if theme.isRounded {
            GlassDrawing.drawFrame(in: bounds, theme: theme, fillsSurface: false)
        } else {
            BevelDrawing.drawPanel(in: bounds, theme: theme)
        }
        NoteDrawing.draw(note, x: padding + inset, midY: bounds.midY, theme: theme)
    }
}
