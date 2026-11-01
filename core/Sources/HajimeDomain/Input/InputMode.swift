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
    /// 入力先をこのアプリに移すたびに英数のモードにする．あとから日本語のモードにもできる
    case imeOff
    /// 入力先をこのアプリに移すたびに日本語のモードにする
    case imeOn
    /// このアプリで最後に使ったモードを覚えておき，入力先を戻したときにそのモードにする
    case remembersMode

    public var prefersHalfwidthSymbols: Bool {
        switch self {
        case .standard, .imeOff, .imeOn, .remembersMode: false
        case .programming, .terminal, .direct: true
        }
    }

    /// 入力先をアプリに移したときのモードを決める扱いか．入力の扱い(記号を半角など)とは別に，同じアプリに 1 つずつ付けられる
    public var setsModeOnFocus: Bool { modeOnFocus != .unchanged }

    /// 入力先をこのアプリに移したときのモード
    public var modeOnFocus: ModeOnFocus {
        switch self {
        case .imeOff: .fixed(.direct)
        case .imeOn: .fixed(.japanese)
        case .remembersMode: .remembered
        case .standard, .programming, .terminal, .direct: .unchanged
        }
    }
}

/// 入力先のアプリを移したときにモードをどうするか
public enum ModeOnFocus: Sendable, Equatable {
    /// それまでのモードのまま
    case unchanged
    /// 決まったモードにする
    case fixed(InputMode)
    /// そのアプリで最後に使ったモードにする
    case remembered
}

/// キーを処理するときの入力先の情報．アダプタが毎回作って渡す．
public struct InputContext: Sendable, Equatable {
    public var profile: AppProfile
    /// パスワード欄などで，変換も学習もしないとき
    public var isSecure: Bool
    /// 入力位置の前にある文字列(左の文脈)．打ち始めのときだけアダプタが入れる．文脈を使う変換(Zenzai)の手がかり
    public var precedingText: String?
    /// 入力先のアプリの識別子(macOS はバンドル ID)．アプリの条件の辞書を選ぶのに使う(R-16)
    public var applicationID: String?

    public init(profile: AppProfile = .standard, isSecure: Bool = false, precedingText: String? = nil, applicationID: String? = nil) {
        self.profile = profile
        self.isSecure = isSecure
        self.precedingText = precedingText
        self.applicationID = applicationID
    }
}

extension InputContext: CustomStringConvertible, CustomDebugStringConvertible {
    // 入力位置の前の文字列は入力内容なので，ログには長さだけを出す
    public var description: String {
        "InputContext(profile: \(profile), isSecure: \(isSecure), precedingTextLength: \(precedingText?.count ?? 0))"
    }
    public var debugDescription: String { description }
}
