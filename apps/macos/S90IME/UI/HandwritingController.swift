import AppKit
import S90Application
import S90Domain
import SwiftUI

/// 手書きで文字を探す窓(R-14)．書いた線を少し待ってから認識し，候補を選ぶと入力先に入れて閉じる．
///
/// 入力メソッドは前面に出られないアプリなので，開いているあいだだけ補助アプリ(.accessory)にして前に出す(設定の画面と同じ)．
/// 閉じたら前面に出ないアプリに戻し，開く前に使っていたアプリを前に戻してから文字を入れる
@MainActor
final class HandwritingController {
    private let model: HandwritingModel
    private let settings: any SettingsStoring
    private var window: NSPanel?
    /// 開く前に前面にあったアプリ．閉じたらこれを前に戻す
    private var previousApp: NSRunningApplication?

    init(recognizer: any HandwritingRecognizing, settings: any SettingsStoring) {
        self.model = HandwritingModel(recognizer: recognizer)
        self.settings = settings
    }

    /// 入力位置の近くに開く．commit は選んだ文字を入力先に入れる
    func show(caret: NSRect, commit: @escaping (String) -> Void) {
        previousApp = NSWorkspace.shared.frontmostApplication
        model.theme = ResolvedTheme.resolve(ThemeChoice(settings.current))
        model.clear()
        model.onSelect = { [weak self] text in self?.select(text, commit: commit) }
        let window = window ?? makeWindow()
        self.window = window
        let size = NSSize(width: DesignTokens.Size.Handwriting.width, height: DesignTokens.Size.Handwriting.height)
        window.setFrame(NSRect(origin: FloatingPanel.origin(for: size, caret: caret), size: size), display: true)
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func select(_ text: String, commit: @escaping (String) -> Void) {
        window?.close()
        // 前のアプリが前に戻ってから入れる(入力先がキーを受ける状態になってから)
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { commit(text) }
    }

    private func makeWindow() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = UIStrings.Features.handwritingTitle
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: HandwritingView(model: model))
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = NSApp.setActivationPolicy(.prohibited)
                self?.model.clear()
            }
        }
        return panel
    }
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
    var canvasSize = CGSize(width: DesignTokens.Size.Handwriting.width, height: DesignTokens.Size.Handwriting.canvasHeight)

    init(recognizer: any HandwritingRecognizing) {
        self.recognizer = recognizer
    }

    func begin(at point: CGPoint) {
        strokes.append([point])
    }

    func extend(to point: CGPoint) {
        guard !strokes.isEmpty else { return begin(at: point) }
        strokes[strokes.count - 1].append(point)
    }

    /// 線を書き終えた．止まってから認識する(書いている途中の画は認識しない)
    func end() {
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
        strokes = []
        candidates = []
    }
}

/// 書く場所と候補．色はテーマに合わせる
private struct HandwritingView: View {
    @ObservedObject var model: HandwritingModel

    var body: some View {
        let theme = model.theme
        VStack(spacing: 0) {
            ZStack {
                Color(nsColor: theme.surface.alphaComponent < 0.5 ? .textBackgroundColor : theme.surface)
                if model.strokes.isEmpty {
                    Text(UIStrings.Features.handwritingPrompt).foregroundStyle(Color(nsColor: theme.textMuted))
                }
                Canvas { context, _ in
                    for stroke in model.strokes {
                        var path = Path()
                        path.addLines(stroke.count == 1 ? [stroke[0], stroke[0]] : stroke)
                        context.stroke(path, with: .color(Color(nsColor: theme.text)), style: StrokeStyle(lineWidth: DesignTokens.Size.Handwriting.strokeWidth, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .frame(height: DesignTokens.Size.Handwriting.canvasHeight)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if value.translation == .zero { model.begin(at: value.location) } else { model.extend(to: value.location) }
                }
                .onEnded { _ in model.end() })
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
                    .keyboardShortcut(.delete, modifiers: [])
            }
            .padding(8)
        }
    }
}
