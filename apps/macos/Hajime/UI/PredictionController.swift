import AppKit
import HajimeApplication

/// 打っているあいだの続く語句の予測を，組み立て中の文字のすぐ右に出す小さな窓．
/// 予測は読みの変換とは体験が違うので，変換の候補の窓には混ぜずに別の窓にする．
/// 候補の窓を出す・消すときには触らず，ClientAction.showPrediction だけで出し入れする(打ち終わったら InputSession が nil を送る)
@MainActor
final class PredictionController {
    private let view = PredictionView()
    private let backdrop = GlassBackdrop()
    private let window: NSPanel
    private(set) var isVisible = false

    init() {
        window = FloatingPanel.make(contentView: view)
    }

    /// end は組み立て中の文字の最後の字の行の長方形
    func show(_ prediction: Prediction, end: NSRect, theme: ThemeChoice, fontSize: Double) {
        view.theme = ResolvedTheme.resolve(theme)
        view.fontSize = CGFloat(fontSize)
        view.prediction = prediction
        backdrop.cornerRadius = view.theme.cornerRadius
        _ = FloatingPanel.attach(view, to: window, backdrop: view.theme.isRounded ? backdrop : nil)
        isVisible = true
        move(end: end)
        if view.theme.isRounded { window.invalidateShadow() }
        window.orderFrontRegardless()
        // VoiceOver が動いているときは，予測した語句を読み上げる(予測が変わったときだけ呼ばれる)
        if NSWorkspace.shared.isVoiceOverEnabled {
            NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
                .announcement: UIStrings.Prediction.announcement(prediction.text),
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ])
        }
    }

    /// 組み立て中の文字が変わったときに，右端に合わせて置き直す
    func move(end: NSRect) {
        guard isVisible else { return }
        let size = view.fittingSize
        window.setFrame(NSRect(origin: Self.origin(for: size, end: end), size: size), display: true)
    }

    func hide() {
        isVisible = false
        window.orderOut(nil)
    }

    /// 組み立て中の文字の右端のすぐ右に，行の高さの中央をそろえて置く．アプリが位置を教えなければマウスの位置．
    /// 画面の右に入らなければ，入るところまで左へ寄せる
    static func origin(for size: NSSize, end: NSRect) -> NSPoint {
        let anchor = end == .zero ? NSRect(origin: NSEvent.mouseLocation, size: .zero) : end
        var x = anchor.maxX + DesignTokens.Size.Prediction.gap
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            x = max(visible.minX, min(x, visible.maxX - size.width))
        }
        return NSPoint(x: x.rounded(), y: (anchor.midY - size.height / 2).rounded())
    }
}

/// 予測の窓の中身．打った部分はふつうの文字の色，補う部分は薄い色で描き，確定のキーをキーキャップで添える
final class PredictionView: NSView {
    private typealias Glass = DesignTokens.Size.Glass
    private typealias Size = DesignTokens.Size.Candidate
    private typealias Spacing = DesignTokens.Size.Prediction

    var prediction = Prediction(typed: "", completion: "", key: nil) { didSet { needsDisplay = true } }
    var theme = ResolvedTheme.resolveStatic { didSet { needsDisplay = true } }
    var fontSize: CGFloat = Size.fontSize { didSet { needsDisplay = true } }
    /// glass の面を自分で塗るか．ぼかしの地(GlassBackdrop)の無いところ(画像への書き出し)で使う
    var fillsSurface = false { didSet { needsDisplay = true } }

    private var font: NSFont { theme.candidateFont(size: fontSize) }
    /// platinum と desk は外枠と立体の縁の内側に描く
    private var inset: CGFloat { theme.isRounded ? 0 : Size.frameWidth + Size.bevelWidth }

    private func attributes(_ color: NSColor) -> [NSAttributedString.Key: Any] { [.font: font, .foregroundColor: color] }

    private var textWidth: CGFloat {
        (prediction.typed.size(withAttributes: attributes(theme.text)).width
            + prediction.completion.size(withAttributes: attributes(theme.textMuted)).width).rounded(.up)
    }

    override var fittingSize: NSSize {
        let key = prediction.key.map { Spacing.keyGap + GlassDrawing.keysWidth($0, theme: theme) } ?? 0
        let content = max((font.ascender - font.descender).rounded(.up), Glass.keycapHeight)
        return NSSize(width: (textWidth + key + (Spacing.paddingX + inset) * 2).rounded(.up),
                      height: (content + (Spacing.paddingY + inset) * 2).rounded(.up))
    }

    override func draw(_ dirtyRect: NSRect) {
        if theme.isRounded {
            GlassDrawing.drawFrame(in: bounds, theme: theme, fillsSurface: fillsSurface)
        } else {
            BevelDrawing.drawPanel(in: bounds, theme: theme)
        }
        var x = Spacing.paddingX + inset
        for (text, color) in [(prediction.typed, theme.text), (prediction.completion, theme.textMuted)] where !text.isEmpty {
            let size = text.size(withAttributes: attributes(color))
            text.draw(at: NSPoint(x: x, y: (bounds.midY - size.height / 2).rounded()), withAttributes: attributes(color))
            x += size.width
        }
        if let key = prediction.key {
            GlassDrawing.drawKeys(key, x: (x + Spacing.keyGap).rounded(), midY: bounds.midY, theme: theme)
        }
    }
}
