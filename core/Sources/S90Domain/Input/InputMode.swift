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
    /// IME を使わないアプリ．日本語のモードでも英数のまま入れる
    case direct

    public var prefersHalfwidthSymbols: Bool {
        switch self {
        case .standard: false
        case .programming, .terminal, .direct: true
        }
    }
}

/// キーを処理するときの入力先の情報．アダプタが毎回作って渡す．
public struct InputContext: Sendable, Equatable {
    public var profile: AppProfile
    /// パスワード欄などで，変換も学習もしないとき
    public var isSecure: Bool
    /// 入力位置の前にある文字列(左の文脈)．打ち始めのときだけアダプタが入れる．文脈を使う変換(Zenzai)の手がかり
    public var precedingText: String?

    public init(profile: AppProfile = .standard, isSecure: Bool = false, precedingText: String? = nil) {
        self.profile = profile
        self.isSecure = isSecure
        self.precedingText = precedingText
    }
}

extension InputContext: CustomStringConvertible, CustomDebugStringConvertible {
    // 入力位置の前の文字列は入力内容なので，ログには長さだけを出す
    public var description: String {
        "InputContext(profile: \(profile), isSecure: \(isSecure), precedingTextLength: \(precedingText?.count ?? 0))"
    }
    public var debugDescription: String { description }
}
