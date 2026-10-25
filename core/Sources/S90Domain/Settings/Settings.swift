/// 利用者が変えられる設定．既定値は DefaultSettings にまとめる．
public struct Settings: Sendable, Equatable, Codable {
    public var liveConversion: Bool
    public var yenKey: YenKeyPolicy
    public var typoCorrection: TypoCorrectionLevel
    public var showsVariantRow: Bool
    public var theme: ThemePreference
    public var candidateFontSize: Double
    public var candidatePresentation: CandidatePresentation
    /// アプリの識別子(macOS はバンドル ID)の前方一致からプロファイルを決める規則．先にあるものを優先する
    public var profileRules: [ProfileRule]

    public init(
        liveConversion: Bool,
        yenKey: YenKeyPolicy,
        typoCorrection: TypoCorrectionLevel,
        showsVariantRow: Bool,
        theme: ThemePreference,
        candidateFontSize: Double,
        candidatePresentation: CandidatePresentation,
        profileRules: [ProfileRule]
    ) {
        self.liveConversion = liveConversion
        self.yenKey = yenKey
        self.typoCorrection = typoCorrection
        self.showsVariantRow = showsVariantRow
        self.theme = theme
        self.candidateFontSize = candidateFontSize
        self.candidatePresentation = candidatePresentation
        self.profileRules = profileRules
    }

    // 項目を足しても古い設定ファイルを読めるよう，無い項目は既定値で埋める
    private enum CodingKeys: String, CodingKey {
        case liveConversion, yenKey, typoCorrection, showsVariantRow, theme, candidateFontSize, candidatePresentation, profileRules
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DefaultSettings.settings
        liveConversion = try container.decodeIfPresent(Bool.self, forKey: .liveConversion) ?? defaults.liveConversion
        yenKey = try container.decodeIfPresent(YenKeyPolicy.self, forKey: .yenKey) ?? defaults.yenKey
        typoCorrection = try container.decodeIfPresent(TypoCorrectionLevel.self, forKey: .typoCorrection) ?? defaults.typoCorrection
        showsVariantRow = try container.decodeIfPresent(Bool.self, forKey: .showsVariantRow) ?? defaults.showsVariantRow
        theme = try container.decodeIfPresent(ThemePreference.self, forKey: .theme) ?? defaults.theme
        candidateFontSize = try container.decodeIfPresent(Double.self, forKey: .candidateFontSize) ?? defaults.candidateFontSize
        candidatePresentation = try container.decodeIfPresent(CandidatePresentation.self, forKey: .candidatePresentation) ?? defaults.candidatePresentation
        profileRules = try container.decodeIfPresent([ProfileRule].self, forKey: .profileRules) ?? defaults.profileRules
    }

    public func profile(forApplication identifier: String?) -> AppProfile {
        guard let identifier else { return .standard }
        return profileRules.first { identifier.hasPrefix($0.applicationPrefix) }?.profile ?? .standard
    }
}

public struct ProfileRule: Sendable, Equatable, Codable {
    public var applicationPrefix: String
    public var profile: AppProfile

    public init(applicationPrefix: String, profile: AppProfile) {
        self.applicationPrefix = applicationPrefix
        self.profile = profile
    }
}

public enum ThemePreference: String, Sendable, Equatable, Codable, CaseIterable {
    /// ライトモードで platinum，ダークモードで desk
    case automatic
    case platinum
    case desk
    case native
}

/// タイプミスの補正の強さ(R-02)
public enum TypoCorrectionLevel: String, Sendable, Equatable, Codable, CaseIterable {
    case off
    /// ローマ字として読めない並びが英単語そのものだったときだけ直す(「pyてょn」→「python」)
    case conservative
    /// 綴りの誤りも直す(「pthon」→「python」)
    case standard
}

/// JIS キーボードの ¥ キーで入れる文字(R-04)
public enum YenKeyPolicy: String, Sendable, Equatable, Codable, CaseIterable {
    case alwaysBackslash
    case alwaysYen
    /// プログラミング用・ターミナルのプロファイルでだけ \
    case backslashInProgramming

    public static let backslash = "\\"
    public static let yen = "¥"

    /// Option を押しているときは逆の文字にする
    public func character(profile: AppProfile, optionPressed: Bool) -> String {
        let prefersBackslash: Bool = switch self {
        case .alwaysBackslash: true
        case .alwaysYen: false
        case .backslashInProgramming: profile.prefersHalfwidthSymbols
        }
        return prefersBackslash != optionPressed ? Self.backslash : Self.yen
    }
}
