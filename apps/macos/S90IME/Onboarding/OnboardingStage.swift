import AppKit
import S90Application
import S90Domain
import SwiftUI

/// 初期設定の左の実演．入力欄の模型と，その下に候補ウィンドウと同じ部品(分岐図・一覧・案内・モードの札)を置き，台本のコマを時間で切り替える
struct OnboardingStage: NSViewRepresentable {
    let page: OnboardingPage
    let settings: S90Domain.Settings

    func makeNSView(context: Context) -> DemoStageView {
        DemoStageView()
    }

    func updateNSView(_ view: DemoStageView, context: Context) {
        view.play(DemoScripts.frames(for: page, settings: settings), settings: settings)
    }
}

@MainActor
final class DemoStageView: NSView {
    /// 見本の画像を書き出すとき(デバッグビルド)は，動かさずに最後のコマを写す
    static var showsLastFrameOnly = false

    private typealias Size = DesignTokens.Size.Onboarding

    private let branch = BranchView()
    private let list = CandidateView()
    private let note = NoteView()
    private let mode = ModeIndicatorView()
    private let panelHost = ScaledHost()

    private var frames: [DemoFrame] = []
    private var index = 0
    private var timer: Timer?
    private var settings = S90Domain.Settings()
    private var current: DemoFrame?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        branch.fillsSurface = true
        list.fillsSurface = true
        mode.fillsSurface = true
        branch.showsHints = false
        addSubview(panelHost)
        addSubview(mode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    /// 台本を始める．同じ台本と設定なら，続きから流す
    func play(_ frames: [DemoFrame], settings: S90Domain.Settings) {
        guard frames != self.frames || settings != self.settings else { return }
        self.frames = frames
        self.settings = settings
        timer?.invalidate()
        // 「視差効果を減らす」が有効なら動かさず，最後のコマだけを見せる
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || Self.showsLastFrameOnly {
            index = max(frames.count - 1, 0)
            show(frames.last)
            return
        }
        index = 0
        step()
    }

    private func step() {
        guard !frames.isEmpty else { return }
        let frame = frames[index]
        show(frame)
        timer = Timer.scheduledTimer(withTimeInterval: frame.duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.index = (self.index + 1) % self.frames.count
                self.step()
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { timer?.invalidate() }
    }

    private func show(_ frame: DemoFrame?) {
        current = frame
        let theme = ResolvedTheme.resolve(ThemeChoice(settings), appearance: effectiveAppearance)
        let fontSize = CGFloat(settings.candidateFontSize)
        var content: NSView?
        var natural = NSSize.zero
        switch frame?.panel {
        case .lattice(let panel)?:
            branch.theme = theme
            branch.fontSize = fontSize
            branch.keys = settings.keymap
            branch.panel = panel
            natural = branch.fittingSize(for: panel)
            content = branch
        case .list(let panel)?:
            list.theme = theme
            list.fontSize = fontSize
            list.keys = settings.keymap
            list.panel = panel
            natural = list.fittingSize(for: panel)
            content = list
        case .note(let value)?:
            note.theme = theme
            note.note = value
            natural = note.fittingSize
            content = note
        case nil:
            content = nil
        }
        panelHost.set(content, natural: natural)
        mode.isHidden = frame?.mode == nil
        if let label = frame?.mode {
            mode.theme = theme
            mode.label = label
        }
        needsLayout = true
        needsDisplay = true
    }

    // MARK: - 配置

    private var fieldRect: NSRect {
        // タイトルバーの下から，舞台の上 1/4 ほどに置く(下に候補の窓を広げる場所を空ける)
        NSRect(x: Size.stagePadding, y: Size.stagePadding * 4, width: bounds.width - Size.stagePadding * 2, height: Size.fieldHeight)
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: Size.fieldFontSize), .foregroundColor: NSColor.labelColor]
    }

    /// 確定した文字の後ろ(組み立て中の文字の始まり)と，文字の終わりの x
    private var textPositions: (markedStart: CGFloat, end: CGFloat) {
        let start = fieldRect.minX + Size.cardPadding
        let committed = (current?.committed ?? "").size(withAttributes: textAttributes).width
        let marked = (current?.marked.text ?? "").size(withAttributes: textAttributes).width
        return (start + committed, start + committed + marked)
    }

    override func layout() {
        super.layout()
        let field = fieldRect
        let positions = textPositions
        let top = field.maxY + Size.demoGap
        let available = NSSize(width: bounds.width - Size.stagePadding * 2, height: bounds.height - top - Size.stagePadding)
        let size = panelHost.fittingSize(in: available)
        let x = min(max(positions.markedStart - Size.cardPadding, Size.stagePadding), bounds.width - Size.stagePadding - size.width)
        panelHost.frame = NSRect(x: x.rounded(), y: top, width: size.width, height: size.height)
        let modeSize = mode.fittingSize
        mode.frame = NSRect(x: min(positions.end + Size.demoGap / 2, bounds.width - Size.stagePadding - modeSize.width).rounded(),
                            y: top, width: modeSize.width, height: modeSize.height)
    }

    // MARK: - 入力欄の模型

    override func draw(_ dirtyRect: NSRect) {
        let field = fieldRect
        let path = NSBezierPath(roundedRect: field, xRadius: Size.fieldRadius, yRadius: Size.fieldRadius)
        NSColor.textBackgroundColor.withAlphaComponent(DesignTokens.Opacity.Onboarding.field).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()

        let attributes = textAttributes
        let font = NSFont.systemFont(ofSize: Size.fieldFontSize)
        // 座標は上から下へ(isFlipped)．文字の行の高さを入力欄の真ん中にそろえる
        let lineHeight = font.ascender - font.descender
        let lineTop = (field.midY - lineHeight / 2).rounded()
        let baselineY = lineTop + font.ascender
        var x = field.minX + Size.cardPadding
        let theme = ResolvedTheme.resolve(ThemeChoice(settings), appearance: effectiveAppearance)
        func drawText(_ text: String) -> CGFloat {
            let width = text.size(withAttributes: attributes).width
            text.draw(at: NSPoint(x: x, y: baselineY - font.ascender), withAttributes: attributes)
            return width
        }
        x += drawText(current?.committed ?? "")
        let underlineY = baselineY + font.descender.magnitude / 2 + 2
        for segment in current?.marked.segments ?? [] {
            let from = x
            x += drawText(segment.text)
            switch segment.style {
            case .reading, .converted:
                NSColor.secondaryLabelColor.setFill()
                NSRect(x: from, y: underlineY, width: x - from, height: 1).fill()
            case .focused:
                NSColor.labelColor.setFill()
                NSRect(x: from, y: underlineY - 0.5, width: x - from, height: 2).fill()
            case .correction:
                GlassDrawing.drawUnderline(from: from, to: x, y: underlineY, color: theme.correction, dotted: true, theme: theme)
            }
            x += 2
        }
        // 入力位置
        NSColor.controlAccentColor.setFill()
        NSRect(x: x.rounded(), y: lineTop, width: 2, height: lineHeight).fill()
    }
}

/// 中の部品を描いた大きさ(natural)のまま持ち，枠が狭ければ座標の比(bounds)で縮めて描く
@MainActor
final class ScaledHost: NSView {
    private var content: NSView?
    private var natural = NSSize.zero

    override var isFlipped: Bool { true }

    func set(_ view: NSView?, natural: NSSize) {
        if content !== view {
            content?.removeFromSuperview()
            if let view { addSubview(view) }
            content = view
        }
        self.natural = natural
        view?.frame = NSRect(origin: .zero, size: natural)
        isHidden = view == nil
        needsLayout = true
    }

    func fittingSize(in available: NSSize) -> NSSize {
        guard natural.width > 0, natural.height > 0 else { return .zero }
        let scale = min(1, available.width / natural.width, available.height / natural.height)
        return NSSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded())
    }

    override func layout() {
        super.layout()
        bounds = NSRect(origin: .zero, size: natural)
    }
}
