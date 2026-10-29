/// 日本語と英数を切り替えるキーの使い方(初期設定で選ぶ)．キー設定の表の，修飾キーなしの英数キーとかなキーの行を書き換える
public enum ModeSwitchStyle: String, Sendable, Equatable, CaseIterable {
    /// 英数キーで英数，かなキーで日本語にする(macOS の決まり．推奨)
    case separate
    /// 英数キーとかなキーのどちらでも，押すたびに日本語と英数を切り替える
    case single

    /// 推奨の使い方
    public static let recommended = ModeSwitchStyle.separate

    /// 英数キーとかなキーの行(状態は「いつでも」)
    private var entries: [KeymapEntry] {
        switch self {
        case .separate:
            [KeymapEntry(.anywhere, KeyStroke(.eisu), .directMode), KeymapEntry(.anywhere, KeyStroke(.kana), .japaneseMode)]
        case .single:
            [KeymapEntry(.anywhere, KeyStroke(.eisu), .toggleMode), KeymapEntry(.anywhere, KeyStroke(.kana), .toggleMode)]
        }
    }

    private static let keys: Set<KeyStroke> = [KeyStroke(.eisu), KeyStroke(.kana)]

    /// 表の英数キーとかなキーの行(「いつでも」の状態)をこの使い方にする．ほかの行は変えない
    public func applied(to keymap: Keymap) -> Keymap {
        var result = keymap
        result.entries.removeAll { $0.state == .anywhere && Self.keys.contains($0.stroke) }
        result.entries.append(contentsOf: entries)
        return result
    }

    /// 表の英数キーとかなキーの行がどちらの使い方か．どちらにも当たらなければ nil
    public static func current(in keymap: Keymap) -> ModeSwitchStyle? {
        let rows = Set(keymap.entries.filter { $0.state == .anywhere && keys.contains($0.stroke) })
        return allCases.first { Set($0.entries) == rows }
    }
}
