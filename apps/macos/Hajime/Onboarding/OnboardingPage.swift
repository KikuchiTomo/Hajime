import HajimeDomain

/// 初期設定のページ．並びは Windows 版と同じ
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case modeSwitch
    case correction
    case theme
    case liveConversion
    case presentation
    case characters
    case features

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .modeSwitch: UIStrings.Onboarding.modeTitle
        case .correction: UIStrings.Onboarding.correctionTitle
        case .theme: UIStrings.Onboarding.themeTitle
        case .liveConversion: UIStrings.Onboarding.liveTitle
        case .presentation: UIStrings.Onboarding.presentationTitle
        case .characters: UIStrings.Onboarding.charactersTitle
        case .features: UIStrings.Onboarding.featuresTitle
        }
    }

    var detail: String {
        switch self {
        case .modeSwitch: UIStrings.Onboarding.modeDetail
        case .correction: UIStrings.Onboarding.correctionDetail
        case .theme: UIStrings.Onboarding.themeDetail
        case .liveConversion: UIStrings.Onboarding.liveDetail
        case .presentation: UIStrings.Onboarding.presentationDetail
        case .characters: UIStrings.Onboarding.charactersDetail
        case .features: UIStrings.Onboarding.featuresDetail
        }
    }

    /// 推奨の値を選んだ設定．初期設定を開いたときに，今の設定にこれを重ねて見せる
    static func recommended(from settings: Settings) -> Settings {
        var result = settings
        result.keymap = ModeSwitchStyle.recommended.applied(to: settings.keymap)
        result.typoCorrection = .standard
        result.correctionSensitivity = .standard
        result.liveConversion = true
        result.liveConversionDelay = DefaultSettings.onboardingLiveConversionDelay
        result.candidatePresentation = .automatic
        result.initialFocus = .start
        return result
    }
}
