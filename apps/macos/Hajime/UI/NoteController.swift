import AppKit
import HajimeApplication
import HajimeDomain

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

    /// 縁の線(角丸)，外枠と立体の縁(platinum と desk)の太さ．余白はこの内側から測る
    private var inset: CGFloat { theme.isRounded ? Size.frameWidth : Size.frameWidth + Size.bevelWidth }

    /// 1 行だけの小さな窓の余白(予測の窓・モード表示と同じ)．中身の高さは足元の行と同じ決め方
    override var fittingSize: NSSize {
        let font = theme.labelFont(size: Glass.labelFontSize)
        let height = max(Glass.noteIconSize, Glass.keycapHeight, (font.ascender - font.descender).rounded(.up))
        return NSSize(width: (NoteDrawing.width(note, theme: theme) + (Glass.compactPaddingX + inset) * 2).rounded(.up),
                      height: (height + (Glass.compactPaddingY + inset) * 2).rounded(.up))
    }

    override func draw(_ dirtyRect: NSRect) {
        if theme.isRounded {
            GlassDrawing.drawFrame(in: bounds, theme: theme, fillsSurface: false)
        } else {
            BevelDrawing.drawPanel(in: bounds, theme: theme)
        }
        NoteDrawing.draw(note, x: Glass.compactPaddingX + inset, midY: bounds.midY, theme: theme)
    }
}
