/// 入力のモード．日本語(ローマ字で読みを組み立てる)か，英数(そのまま入力)か．
public enum InputMode: String, Sendable, Equatable, Codable, CaseIterable {
    case japanese
    case direct
}

/// 入力先のアプリの種類．アプリごとの既定の振る舞いを決める(R-06，R-07)．
public enum AppProfile: String, Sendable, Equatable, Codable, CaseIterable {
    case standard
    /// エディタ・IDE．記号を半角にする
    case programming
    /// ターミナル．記号を半角にする
    case terminal

    public var prefersHalfwidthSymbols: Bool {
        switch self {
        case .standard: false
        case .programming, .terminal: true
        }
    }
}

/// キーを処理するときの入力先の情報．アダプタが毎回作って渡す．
public struct InputContext: Sendable, Equatable {
    public var profile: AppProfile
    /// パスワード欄などで，変換も学習もしないとき
    public var isSecure: Bool

    public init(profile: AppProfile = .standard, isSecure: Bool = false) {
        self.profile = profile
        self.isSecure = isSecure
    }
}
