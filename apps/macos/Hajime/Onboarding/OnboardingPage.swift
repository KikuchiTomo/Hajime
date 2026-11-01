import HajimeDomain

/// 初期設定のページ．並びは Windows 版と同じ
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case modeSwitch
    /// アプリごとの入力モード(除外設定の IME をオフ・オン・オンオフを記憶)の紹介
    case appModes
    case correction
    case theme
    case liveConversion
    case presentation
    case characters
    case features
    /// 既定ではオフの試験的な機能(手のずれ・うろ覚えの語・動的な辞書・変換マクロ・コマンド)
    case extras

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .modeSwitch: UIStrings.Onboarding.modeTitle
        case .appModes: UIStrings.Onboarding.appModesTitle
        case .correction: UIStrings.Onboarding.correctionTitle
        case .theme: UIStrings.Onboarding.themeTitle
        case .liveConversion: UIStrings.Onboarding.liveTitle
        case .presentation: UIStrings.Onboarding.presentationTitle
        case .characters: UIStrings.Onboarding.charactersTitle
        case .features: UIStrings.Onboarding.featuresTitle
        case .extras: UIStrings.Onboarding.extrasTitle
        }
    }

    var detail: String {
        switch self {
        case .modeSwitch: UIStrings.Onboarding.modeDetail
        case .appModes: UIStrings.Onboarding.appModesDetail
        case .correction: UIStrings.Onboarding.correctionDetail
        case .theme: UIStrings.Onboarding.themeDetail
        case .liveConversion: UIStrings.Onboarding.liveDetail
        case .presentation: UIStrings.Onboarding.presentationDetail
        case .characters: UIStrings.Onboarding.charactersDetail
        case .features: UIStrings.Onboarding.featuresDetail
        case .extras: UIStrings.Onboarding.extrasDetail
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

/// 機能を紹介するページ(便利な機能・試験的な機能)の項目．項目の上にポインタを置くと，左に実演と説明を出す
enum OnboardingSpotlight: Int, CaseIterable, Identifiable {
    case association
    case calculation
    case postalCode
    case date
    case looseReadings
    case phoneticSpelling
    case handShift
    case macros
    case dynamicDictionary
    case commands

    var id: Int { rawValue }

    var page: OnboardingPage {
        switch self {
        case .association, .calculation, .postalCode, .date: .features
        case .looseReadings, .phoneticSpelling, .handShift, .macros, .dynamicDictionary, .commands: .extras
        }
    }

    /// page に並べる項目(並びは Windows 版の初期設定と同じ)
    static func items(on page: OnboardingPage) -> [Self] {
        allCases.filter { $0.page == page }
    }

    /// オンとオフを切り替える設定の項目
    var setting: WritableKeyPath<Settings, Bool> {
        switch self {
        case .association: \.association
        case .calculation: \.calculation
        case .postalCode: \.postalCodeConversion
        case .date: \.dateConversion
        case .looseReadings: \.looseReadings
        case .phoneticSpelling: \.phoneticSpelling
        case .handShift: \.handShiftCorrection
        case .macros: \.conversionMacros
        case .dynamicDictionary: \.dynamicDictionary
        case .commands: \.launcherCommands
        }
    }

    var title: String {
        switch self {
        case .association: UIStrings.Onboarding.association
        case .calculation: UIStrings.Onboarding.calculation
        case .postalCode: UIStrings.Onboarding.postalCode
        case .date: UIStrings.Onboarding.date
        case .looseReadings: UIStrings.Extras.looseReadings
        case .phoneticSpelling: UIStrings.Extras.phoneticSpelling
        case .handShift: UIStrings.Extras.handShift
        case .macros: UIStrings.Onboarding.macros
        case .dynamicDictionary: UIStrings.Onboarding.dynamicDictionary
        case .commands: UIStrings.Onboarding.commands
        }
    }

    var detail: String {
        switch self {
        case .association: UIStrings.Onboarding.associationDetail
        case .calculation: UIStrings.Onboarding.calculationDetail
        case .postalCode: UIStrings.Onboarding.postalCodeDetail
        case .date: UIStrings.Onboarding.dateDetail
        case .looseReadings: UIStrings.Extras.looseReadingsNote
        case .phoneticSpelling: UIStrings.Extras.phoneticSpellingNote
        case .handShift: UIStrings.Extras.handShiftNote
        case .macros: UIStrings.Onboarding.macrosDetail
        case .dynamicDictionary: UIStrings.Onboarding.dynamicDictionaryDetail
        case .commands: UIStrings.Onboarding.commandsDetail
        }
    }

    /// 説明の札に出す SF Symbols のアイコン
    var symbol: String {
        switch self {
        case .association: "point.3.connected.trianglepath.dotted"
        case .calculation: "plus.forwardslash.minus"
        case .postalCode: "envelope"
        case .date: "calendar"
        case .looseReadings: "questionmark.bubble"
        case .phoneticSpelling: "waveform"
        case .handShift: "hand.raised"
        case .macros: "wand.and.stars"
        case .dynamicDictionary: "clock.arrow.circlepath"
        case .commands: "play.rectangle"
        }
    }
}
