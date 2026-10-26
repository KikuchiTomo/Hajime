/// 日本語と英数を切り替えるキーで何をするか
public enum ModeKeyAction: String, Sendable, Equatable, Codable, CaseIterable {
    /// 日本語と英数を入れ替える
    case toggle
    /// 日本語にする
    case japanese
    /// 英数にする
    case direct
    /// 切り替えに使わない(変換・無変換はそのキーのふつうの働きにする)
    case none
}

/// 日本語と英数を切り替えるキーの割り当て．macOS と Windows で同じ設定を使う．
/// 既定は，Mac の英数・かなキーと，Windows の 半角/全角 キーの今の働きに合わせる．
/// Windows の変換・無変換は，ふつうの働き(変換・カタカナ)のままにし，上書きで切り替えにも使える
public struct ModeKeyAssignments: Sendable, Equatable, Codable {
    public var eisu: ModeKeyAction
    public var kana: ModeKeyAction
    public var hankakuZenkaku: ModeKeyAction
    public var henkan: ModeKeyAction
    public var muhenkan: ModeKeyAction

    public init(eisu: ModeKeyAction = .direct, kana: ModeKeyAction = .japanese, hankakuZenkaku: ModeKeyAction = .toggle,
                henkan: ModeKeyAction = .none, muhenkan: ModeKeyAction = .none) {
        self.eisu = eisu
        self.kana = kana
        self.hankakuZenkaku = hankakuZenkaku
        self.henkan = henkan
        self.muhenkan = muhenkan
    }

    public static let standard = ModeKeyAssignments()

    /// このキーの割り当て．切り替えのキーでなければ nil
    public func action(for key: KeyEvent.Key) -> ModeKeyAction? {
        switch key {
        case .eisu: eisu
        case .kana: kana
        case .hankakuZenkaku: hankakuZenkaku
        case .henkan: henkan
        case .muhenkan: muhenkan
        default: nil
        }
    }

    /// 切り替えたあとのモード．切り替えに使わないなら nil
    public func mode(after key: KeyEvent.Key, from current: InputMode) -> InputMode? {
        guard let action = action(for: key) else { return nil }
        switch action {
        case .toggle: return current == .japanese ? .direct : .japanese
        case .japanese: return .japanese
        case .direct: return .direct
        case ModeKeyAction.none: return nil
        }
    }

    private enum CodingKeys: String, CodingKey { case eisu, kana, hankakuZenkaku, henkan, muhenkan }

    /// 足したキーや読めない値は既定のままにする(古い設定のファイルと，ほかの版のファイルを読むため)
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var value = ModeKeyAssignments()
        func read(_ key: CodingKeys, _ keyPath: WritableKeyPath<ModeKeyAssignments, ModeKeyAction>) {
            if let action = try? container.decodeIfPresent(ModeKeyAction.self, forKey: key) { value[keyPath: keyPath] = action }
        }
        read(.eisu, \.eisu)
        read(.kana, \.kana)
        read(.hankakuZenkaku, \.hankakuZenkaku)
        read(.henkan, \.henkan)
        read(.muhenkan, \.muhenkan)
        self = value
    }
}
