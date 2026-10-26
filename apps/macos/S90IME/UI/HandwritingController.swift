import AppKit
import S90Application
import S90Domain
import SwiftUI

/// 手書きで文字を探す窓(R-14)．書いた線を少し待ってから認識し，候補を選ぶと入力先に入れて閉じる．
///
/// 窓はキーボードの入力を受けず，入力先のアプリを前面のまま残す(候補の窓と同じくフォーカスを奪わない)．
/// 以前は窓を前に出すために入力メソッドを前面のアプリにしていたが，macOS 14 からはほかのアプリが前面を譲らない限り前に出られず，
/// 前に出られたときは入力先のアプリが入力メソッドから外れるので，選んだ文字を入れる先が無くなっていた．
/// 書くのも候補を選ぶのもマウスなので，キーボードの入力を受ける必要は無い
@MainActor
final class HandwritingController {
    private let model: HandwritingModel
    private let settings: any SettingsStoring
    private var window: NSPanel?
    /// 窓を開いた入力先(の presenter)．入力先は入力欄ごとにあるので，開いた入力先から外れたときだけ閉じる
    private weak var owner: AnyObject?

    init(recognizer: any HandwritingRecognizing, settings: any SettingsStoring) {
        self.model = HandwritingModel(recognizer: recognizer)
        self.settings = settings
    }

    /// 入力位置の近くに開く．owner は開いた入力先，commit は選んだ文字をその入力先に入れる
    func show(caret: NSRect, owner: AnyObject, commit: @escaping (String) -> Void) {
        self.owner = owner
        model.theme = ResolvedTheme.resolve(ThemeChoice(settings.current))
        model.clear()
        model.onSelect = { [weak self] text in
            self?.close()
            commit(text)
        }
        let window = window ?? makeWindow()
        self.window = window
        let size = NSSize(width: DesignTokens.Size.Handwriting.width, height: DesignTokens.Size.Handwriting.height)
        // 中身の大きさを窓の大きさにする(枠の見出しの分だけ窓を高くする)
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        window.setFrame(NSRect(origin: FloatingPanel.origin(for: frame.size, caret: caret), size: frame.size), display: true)
        window.orderFrontRegardless()
    }

    /// 閉じる．書いた線は捨てる
    func close() {
        window?.close()
    }

    /// owner が開いた窓なら閉じる
    func close(openedBy owner: AnyObject) {
        if self.owner === owner { close() }
    }

    private func makeWindow() -> NSPanel {
        let panel = HandwritingPanel(contentRect: .zero, styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = UIStrings.Features.handwritingTitle
        panel.isReleasedWhenClosed = false
        // 入力先のアプリより上に浮かせる．前面のアプリが入れ替わっても隠さず，フルスクリーンのアプリの上にも出す
        panel.level = .floating
        panel.hidesOnDeactivate = false
        // 広げると書く欄も大きくなる．書く欄より小さくはしない
        panel.contentMinSize = NSSize(width: DesignTokens.Size.Handwriting.width, height: DesignTokens.Size.Handwriting.height)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = FirstClickHostingView(rootView: HandwritingView(model: model))
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.clear() }
        }
        return panel
    }
}

/// キーボードの入力を受けない窓．押しても入力先のアプリからフォーカスを移さない
private final class HandwritingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 前面でないアプリの窓でも，最初のクリックから書ける・押せるようにする
/// (ふつうの窓では最初のクリックは窓を前に出すだけで，中身に届かない)
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 手書きの窓の状態．線を足すたびに少し待ってから認識する
@MainActor
final class HandwritingModel: ObservableObject {
    @Published private(set) var strokes: [[CGPoint]] = []
    @Published private(set) var candidates: [String] = []
    @Published var theme = ResolvedTheme.resolveStatic
    var onSelect: (String) -> Void = { _ in }
    private let recognizer: any HandwritingRecognizing
    private var recognition: Task<Void, Never>?
    /// 書く場所の大きさ(認識に渡す)
    var canvasSize = CGSize(width: DesignTokens.Size.Handwriting.canvasSize, height: DesignTokens.Size.Handwriting.canvasSize)

    init(recognizer: any HandwritingRecognizing) {
        self.recognizer = recognizer
    }

    /// 線を書いている途中か．書き始めの点の移動量で判断すると，速く書き始めた線が前の線とつながるので，書き終えるまでを数える
    private var isStroking = false

    /// 線を point まで伸ばす．書いている途中でなければ，新しい線を始める
    func draw(to point: CGPoint) {
        if isStroking, !strokes.isEmpty {
            strokes[strokes.count - 1].append(point)
        } else {
            strokes.append([point])
            isStroking = true
        }
    }

    /// 線を書き終えた．止まってから認識する(書いている途中の画は認識しない)
    func end() {
        isStroking = false
        recognition?.cancel()
        let strokes = strokes.map { $0.map { Point(x: $0.x, y: $0.y) } }
        let size = Size(width: canvasSize.width, height: canvasSize.height)
        recognition = Task { [weak self, recognizer] in
            try? await Task.sleep(for: .seconds(DefaultSettings.handwritingRecognitionDelay))
            guard !Task.isCancelled else { return }
            let texts = await recognizer.recognize(strokes: strokes, canvasSize: size)
            guard !Task.isCancelled else { return }
            self?.candidates = texts
        }
    }

    func clear() {
        recognition?.cancel()
        isStroking = false
        strokes = []
        candidates = []
    }
}

/// 書く場所と候補．色はテーマに合わせる
struct HandwritingView: View {
    @ObservedObject var model: HandwritingModel

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                // 窓の大きさが変わっても，書く欄は正方形のまま真ん中に置く
                let side = max(min(geometry.size.width, geometry.size.height) - DesignTokens.Size.Handwriting.canvasPadding * 2, 0)
                HandwritingCanvas(model: model, side: side)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .frame(minWidth: DesignTokens.Size.Handwriting.canvasSize + DesignTokens.Size.Handwriting.canvasPadding * 2,
                   minHeight: DesignTokens.Size.Handwriting.canvasSize + DesignTokens.Size.Handwriting.canvasPadding * 2)
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.candidates, id: \.self) { text in
                            Button(text) { model.onSelect(text) }
                                .buttonStyle(.bordered)
                                .font(.system(size: 18))
                        }
                    }
                }
                Button(UIStrings.Features.handwritingClear) { model.clear() }
            }
            .padding([.horizontal, .bottom], DesignTokens.Size.Handwriting.canvasPadding)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// 正方形の書く欄．漢字の練習帳のように，実線の枠と，縦と横の中心を通る破線の十字を薄く描く
private struct HandwritingCanvas: View {
    @ObservedObject var model: HandwritingModel
    let side: CGFloat

    var body: some View {
        let theme = model.theme
        ZStack {
            Color(nsColor: theme.surface.alphaComponent < 0.5 ? .textBackgroundColor : theme.surface)
            Canvas { context, size in
                let guide = Color(nsColor: theme.line)
                let lineWidth = DesignTokens.Size.Handwriting.frameWidth
                var cross = Path()
                cross.move(to: CGPoint(x: size.width / 2, y: 0))
                cross.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                cross.move(to: CGPoint(x: 0, y: size.height / 2))
                cross.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                let dash = DesignTokens.Size.Handwriting.guideDash
                context.stroke(cross, with: .color(guide), style: StrokeStyle(lineWidth: lineWidth, dash: [dash, dash]))
                context.stroke(Path(CGRect(origin: .zero, size: size).insetBy(dx: lineWidth / 2, dy: lineWidth / 2)), with: .color(guide), lineWidth: lineWidth)
                // 線をまとめて 1 回で描く(1 画ずつ描くと，半透明の文字色で線の重なりが濃くなる)
                var path = Path()
                for stroke in model.strokes {
                    path.addLines(stroke.count == 1 ? [stroke[0], stroke[0]] : stroke)
                }
                context.stroke(path, with: .color(Color(nsColor: theme.text)),
                               style: StrokeStyle(lineWidth: DesignTokens.Size.Handwriting.strokeWidth, lineCap: .round, lineJoin: .round))
            }
            if model.strokes.isEmpty {
                Text(UIStrings.Features.handwritingPrompt)
                    .foregroundStyle(Color(nsColor: theme.textMuted))
                    .padding(.horizontal, DesignTokens.Size.Handwriting.canvasPadding)
                    .background(Color(nsColor: theme.surface.alphaComponent < 0.5 ? .textBackgroundColor : theme.surface))
            }
        }
        .frame(width: side, height: side)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in model.draw(to: value.location) }
            .onEnded { _ in model.end() })
        // 認識には書く欄の大きさを渡す．大きさが変わったら，書いた線と欄の位置が合わなくなるので書き直してもらう
        .onAppear { model.canvasSize = CGSize(width: side, height: side) }
        .onChange(of: side) { _, newSide in
            model.clear()
            model.canvasSize = CGSize(width: newSide, height: newSide)
        }
    }
}
