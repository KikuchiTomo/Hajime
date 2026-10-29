import AppKit
import HajimeApplication
import SwiftUI

/// 初期設定の窓．まだ済んでいなければ起動したときに 1 回だけ開き，設定の画面の「情報」からも開き直せる
@MainActor
final class OnboardingWindowController {
    /// 済んだかどうかを記録するキー(利用者ごとの UserDefaults)
    static let completedKey = "onboardingCompleted"

    private let settings: any SettingsStoring
    private let defaults: UserDefaults
    private var window: NSWindow?

    init(settings: any SettingsStoring, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
    }

    var isCompleted: Bool { defaults.bool(forKey: Self.completedKey) }

    /// まだ済んでいなければ開く
    func showIfNeeded() {
        guard !isCompleted else { return }
        show()
    }

    /// 開く．開くたびに今の設定から作り直す(前に開いたときの選択は残さない)
    func show() {
        let model = OnboardingModel(store: settings)
        model.onEnd = { [weak self] in self?.end() }
        let window = window ?? Self.makeWindow()
        window.contentView = Self.makeContent(model: model)
        self.window = window
        ForegroundWindow.present(window)
    }

    /// 「はじめる」か「あとで設定する」を押した．どちらでも済んだことにし，次からは自動では開かない
    private func end() {
        defaults.set(true, forKey: Self.completedKey)
        window?.close()
    }

    /// 窓の中身．窓の大きさは変えない(画面の中身の大きさに合わせて窓が伸びないようにする)
    static func makeContent(model: OnboardingModel) -> NSView {
        let hosting = NSHostingView(rootView: OnboardingView(model: model))
        hosting.sizingOptions = []
        return hosting
    }

    /// 初期設定の窓を作る．書き出し(デバッグビルド)でも同じ窓を使う
    static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingView.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = UIStrings.Onboarding.windowTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        ForegroundWindow.configure(window)
        window.center()
        return window
    }
}
