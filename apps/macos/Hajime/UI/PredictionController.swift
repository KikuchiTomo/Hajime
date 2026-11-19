import AppKit
import HajimeApplication
import HajimeDomain

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

    /// 最後に置いたときの，最後の字の長方形と候補の窓の側
    private var placed: (tail: NSRect, candidates: PanelPlacement.Side?)?

    /// tail は組み立て中の文字の最後の字の長方形(横は字の幅，縦は行の高さ)，candidates は候補の窓を置いている側(出していなければ nil)
    func show(_ prediction: Prediction, tail: NSRect, candidates: PanelPlacement.Side?, theme: ThemeChoice, fontSize: Double) {
        view.theme = ResolvedTheme.resolve(theme)
        view.fontSize = CGFloat(fontSize)
        view.prediction = prediction
        backdrop.cornerRadius = view.theme.cornerRadius
        _ = FloatingPanel.attach(view, to: window, backdrop: view.theme.isRounded ? backdrop : nil)
        isVisible = true
        placed = nil
        move(tail: tail, candidates: candidates)
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

    /// 組み立て中の文字か候補の窓の側が変わったときに，最後の字の右に合わせて置き直す
    func move(tail: NSRect, candidates: PanelPlacement.Side?) {
        guard isVisible else { return }
        if let placed, placed.tail == tail, placed.candidates == candidates { return }
        placed = (tail, candidates)
        let size = view.fittingSize
        window.setFrame(NSRect(origin: Self.origin(for: size, tail: tail, candidates: candidates), size: size), display: true)
    }

    func hide() {
        isVisible = false
        placed = nil
        window.orderOut(nil)
    }

    /// 最後の字のすぐ右に，行の高さの中央をそろえて置く(規則は core の PredictionPlacement)．アプリが位置を教えなければマウスの位置．
    /// 候補の窓を出していなければ，下に出るものとして置く(候補の窓があとから出ても，予測の窓を動かさない)
    static func origin(for size: NSSize, tail: NSRect, candidates: PanelPlacement.Side?) -> NSPoint {
        let anchor = tail == .zero ? NSRect(origin: NSEvent.mouseLocation, size: .zero) : tail
        let visible = FloatingPanel.visibleFrame(for: tail)
        let origin = PredictionPlacement.origin(
            tail: Rect(x: anchor.minX, y: anchor.minY, width: anchor.width, height: anchor.height),
            size: Rect(x: 0, y: 0, width: size.width, height: size.height),
            screen: Rect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height),
            gap: DesignTokens.Size.Prediction.gap,
            candidates: candidates ?? .below
        )
        return NSPoint(x: origin.x.rounded(), y: origin.y.rounded())
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
    /// glass の面を自分で塗るか．ぼかしの背景(GlassBackdrop)の無いところ(画像への書き出し)で使う
    var fillsSurface = false { didSet { needsDisplay = true } }

    private var font: NSFont { theme.candidateFont(size: fontSize) }
    /// 枠線(角丸)，外枠とベベル(platinum と desk)の太さ．余白はこの内側から測る
    private var inset: CGFloat { theme.isRounded ? Size.frameWidth : Size.frameWidth + Size.bevelWidth }

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
            // 文字の行の箱を窓の縦の真ん中に置く(キーキャップと同じ真ん中)
            TextFitting.draw(text, attributes: attributes(color), x: x, midY: bounds.midY)
            x += text.size(withAttributes: attributes(color)).width
        }
        if let key = prediction.key {
            GlassDrawing.drawKeys(key, x: (x + Spacing.keyGap).rounded(), midY: bounds.midY, theme: theme)
        }
    }
}
