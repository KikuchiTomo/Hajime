import os
import S90Application
import S90Domain
import SwiftUI

/// 初期設定で選んでいる値．開いたときは今の設定に推奨の値を重ねたもの．「はじめる」で，初期設定が受け持つ項目だけを保存する
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var draft: S90Domain.Settings
    @Published var page = OnboardingPage.allCases[0]

    private let store: any SettingsStoring
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "onboarding")
    /// 終えたとき(「はじめる」か「あとで設定する」)に呼ぶ
    var onEnd: () -> Void = {}

    init(store: any SettingsStoring) {
        self.store = store
        draft = OnboardingPage.recommended(from: store.current)
    }

    func binding<Value>(_ keyPath: WritableKeyPath<S90Domain.Settings, Value>) -> Binding<Value> {
        Binding(get: { self.draft[keyPath: keyPath] }, set: { self.draft[keyPath: keyPath] = $0 })
    }

    var modeSwitchStyle: ModeSwitchStyle? {
        get { ModeSwitchStyle.current(in: draft.keymap) }
        set { if let newValue { draft.keymap = newValue.applied(to: draft.keymap) } }
    }

    var isFirst: Bool { page == OnboardingPage.allCases.first }
    var isLast: Bool { page == OnboardingPage.allCases.last }

    func next() {
        guard let index = OnboardingPage.allCases.firstIndex(of: page), index + 1 < OnboardingPage.allCases.count else { return }
        page = OnboardingPage.allCases[index + 1]
    }

    func back() {
        guard let index = OnboardingPage.allCases.firstIndex(of: page), index > 0 else { return }
        page = OnboardingPage.allCases[index - 1]
    }

    /// 選んだ値を保存して終える
    func finish() {
        do {
            try store.update { Self.apply(self.draft, to: &$0) }
        } catch {
            logger.error("初期設定を保存できませんでした: \(String(describing: error), privacy: .public)")
        }
        onEnd()
    }

    /// 保存せずに終える(設定の画面であとから変えられる)
    func skip() {
        onEnd()
    }

    /// 初期設定が受け持つ項目だけを写す．開いているあいだに設定の画面で変えたほかの項目は上書きしない
    static func apply(_ draft: S90Domain.Settings, to settings: inout S90Domain.Settings) {
        if let style = ModeSwitchStyle.current(in: draft.keymap) { settings.keymap = style.applied(to: settings.keymap) }
        settings.typoCorrection = draft.typoCorrection
        settings.correctionSensitivity = draft.correctionSensitivity
        settings.theme = draft.theme
        settings.customThemeID = draft.customThemeID
        settings.liveConversion = draft.liveConversion
        settings.liveConversionDelay = draft.liveConversionDelay
        settings.candidatePresentation = draft.candidatePresentation
        settings.initialFocus = draft.initialFocus
        settings.punctuation = draft.punctuation
        settings.brackets = draft.brackets
        settings.slash = draft.slash
        settings.yenKey = draft.yenKey
        settings.spaceWidth = draft.spaceWidth
        settings.numberWidth = draft.numberWidth
        settings.alphabetWidth = draft.alphabetWidth
        settings.association = draft.association
        settings.calculation = draft.calculation
        settings.postalCodeConversion = draft.postalCodeConversion
        settings.dateConversion = draft.dateConversion
    }
}
