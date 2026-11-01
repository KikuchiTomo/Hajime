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
    /// 前に出した一覧と分岐図．あとから届いた候補で中身だけが変わったか(選んでいるものは同じか)を見分ける
    private var shownList: CandidatePanel?
    private var shownLattice: LatticePanel?
    /// 窓を入力位置の上と下のどちらに置いているか．出しているあいだは同じ側に保ち，隠したら決め直す
    private var side: PanelPlacement.Side?
    /// 窓の縁を動かしている途中か
    private var isAnimatingFrame = false

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
        view.maximumWidth = Self.maximumWidth(caret: caret)
        // 選んでいる候補が同じまま中身が変わったときは，あとから届いた候補なので重ねて変える(選び直しはすぐ見せる)
        let arrived = shownList.map { $0 != panel && $0.selectedEntry == panel.selectedEntry && $0.focus == panel.focus } ?? false
        shownList = panel
        shownLattice = nil
        view.panel = panel
        // 打っているあいだの候補(どれも選んでいない一覧)は打つたびに中身が変わるので，縁を動かさずにすぐ変える
        present(view, size: view.fittingSize(for: panel), caret: caret, theme: view.theme, crossfades: arrived, animatesFrame: panel.selectedEntry != nil)
        announceSelection(panel)
    }

    func showLattice(_ panel: LatticePanel, caret: NSRect, theme: ThemeChoice, fontSize: Double, keys: Keymap, showsHints: Bool) {
        branchView.keys = keys
        branchView.showsHints = showsHints
        branchView.theme = ResolvedTheme.resolve(theme)
        branchView.fontSize = CGFloat(fontSize)
        branchView.maximumWidth = Self.maximumWidth(caret: caret)
        let arrived = shownLattice.map { shown in
            shown != panel && shown.columns.map(\.text) == panel.columns.map(\.text)
                && shown.columns.firstIndex(where: \.isFocused) == panel.columns.firstIndex(where: \.isFocused)
                && shown.columns.map(\.selectedAlternative) == panel.columns.map(\.selectedAlternative)
        } ?? false
        shownLattice = panel
        shownList = nil
        branchView.panel = panel
        present(branchView, size: branchView.fittingSize(for: panel), caret: caret, theme: branchView.theme, crossfades: arrived)
        if let focused = panel.columns.first(where: \.isFocused) {
            // コマンドの候補を選んでいれば，その名前を「コマンド」と続けて読む(幹の文字には印が付いている)
            let command = focused.selectedAlternative.flatMap { index in
                focused.alternativeCommands.indices.contains(index) && focused.alternativeCommands[index] != nil ? focused.alternatives[index] : nil
            }
            let text = command.map(UIStrings.Candidate.commandAnnouncement) ?? focused.text
            announce(focused.homophone.map { "\(text)、\($0.text)" } ?? text)
        }
    }

    /// 窓の幅の上限．トークンの上限と，入力位置がある画面の幅(左右に余白を空ける)の狭い方
    private static func maximumWidth(caret: NSRect) -> CGFloat {
        let screen = FloatingPanel.visibleFrame(for: caret).width - DesignTokens.Size.Candidate.screenMargin * 2
        return min(DesignTokens.Size.Candidate.maxWidth, screen)
    }

    /// glass はすりガラスの地(GlassBackdrop)の上に中身を重ね，ウィンドウの影を付ける．
    /// 出ている窓の大きさが変わるときは縁を滑らかに動かし(候補が増えた・文節を移った)，crossfades ならあとから届いた中身を重ねて変える．
    /// 「視差効果を減らす」が有効なら，大きさはすぐ変え，重ね変わりだけにする(Apple のヒューマンインターフェイスガイドラインの動きの決まり)
    private func present(_ content: NSView, size: NSSize, caret: NSRect, theme: ResolvedTheme, crossfades: Bool = false, animatesFrame: Bool = true) {
        let glass = theme.isRounded
        backdrop.cornerRadius = theme.cornerRadius
        // 一覧と分岐図を切り替えたときも，窓が出たままなら同じ側に置く
        let wasOnScreen = window.isVisible
        let wasVisible = FloatingPanel.attach(content, to: window, backdrop: glass ? backdrop : nil)
        let placed = FloatingPanel.place(size, caret: caret, keeping: wasOnScreen ? side : nil)
        side = placed.side
        let frame = NSRect(origin: placed.origin, size: size)
        if wasVisible, crossfades, let root = window.contentView {
            root.wantsLayer = true
            let transition = CATransition()
            transition.type = .fade
            transition.duration = DesignTokens.Motion.CandidateWindow.update / 1000
            root.layer?.add(transition, forKey: "arrived")
        }
        // 動かすのは，左端と入力位置の側の辺(下に置くなら上の辺)がそのままで，大きさだけが変わるときに限る．
        // 窓ごと動くとき(入力位置が移った)は滑らせずにすぐ移す．動いている途中に次の大きさが届くと縁が揺れて見えるため，
        // 動いている途中なら今の動きを止めてすぐ移す
        let current = window.frame
        let anchoredEdgeStays = placed.side == .below ? abs(frame.maxY - current.maxY) < 1 : abs(frame.minY - current.minY) < 1
        let animates = wasVisible && animatesFrame && frame != current && anchoredEdgeStays && abs(frame.minX - current.minX) < 1 && !isAnimatingFrame
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animates {
            isAnimatingFrame = true
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DesignTokens.Motion.CandidateWindow.resize / 1000
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                window.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    self?.isAnimatingFrame = false
                    if glass { self?.window.invalidateShadow() }
                }
            }
        } else if isAnimatingFrame {
            // 動いている途中の動きを，長さ 0 の動きで置き換えて止める(そのままだと前の動きが新しい位置を上書きする)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                window.animator().setFrame(frame, display: true)
            }
            isAnimatingFrame = false
            if glass { window.invalidateShadow() }
        } else {
            window.setFrame(frame, display: true)
            if glass { window.invalidateShadow() }
        }
        if !wasVisible {
            startRestFadeIn()
            window.orderFrontRegardless()
        }
    }

    func hide() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        lastAnnounced = nil
        shownList = nil
        shownLattice = nil
        side = nil
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
        case .candidate: panel.selectedEntry.flatMap { index in
            guard panel.entries.indices.contains(index) else { return nil }
            let entry = panel.entries[index]
            return entry.command == nil ? entry.text : UIStrings.Candidate.commandAnnouncement(entry.text)
        }
        case .variants: panel.selectedVariant.flatMap { panel.variants.indices.contains($0) ? panel.variants[$0].label : nil }
        }
        // 使い分けがあれば続けて読む(語・意味・例・ほかの語)
        announce(text.map { text in panel.homophone.map { "\(text)、\($0.text)" } ?? text })
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
        place(size, caret: caret, keeping: nil).origin
    }

    /// 入力位置を教えないアプリでは，マウスの位置の近くに出す
    private static func anchor(for caret: NSRect) -> NSRect {
        caret == .zero ? NSRect(origin: NSEvent.mouseLocation, size: .zero) : caret
    }

    /// 入力位置がある画面の，使える範囲
    static func visibleFrame(for caret: NSRect) -> NSRect {
        let anchor = anchor(for: caret)
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// 前に置いた側(keeping)をなるべく保って置く(PanelPlacement.place)
    static func place(_ size: NSSize, caret: NSRect, keeping side: PanelPlacement.Side?) -> (origin: NSPoint, side: PanelPlacement.Side) {
        let anchor = anchor(for: caret)
        let visible = visibleFrame(for: caret)
        let placed = PanelPlacement.place(
            caret: Rect(x: anchor.minX, y: anchor.minY, width: anchor.width, height: anchor.height),
            size: Rect(x: 0, y: 0, width: size.width, height: size.height),
            screen: Rect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height),
            keeping: side
        )
        return (NSPoint(x: placed.x.rounded(), y: placed.y.rounded()), placed.side)
    }
}
