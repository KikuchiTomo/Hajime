/// OS に依存しないキー入力．macOS の NSEvent や Windows の WPARAM はアダプタがこれに変換する．
public struct KeyEvent: Sendable, Equatable {
    public enum Key: Sendable, Equatable {
        /// 配列に従って入力された文字(Shift を含む)．英字・数字・記号
        case character(Character)
        case space
        case enter
        case backspace
        case escape
        case tab
        case up
        case down
        case left
        case right
        /// JIS キーボードの英数キー
        case eisu
        /// JIS キーボードのかなキー
        case kana
        /// JIS キーボードの ¥ キー(R-04)．何を入れるかは YenKeyPolicy が決める
        case yen
    }

    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }

        public static let shift = Modifiers(rawValue: 1 << 0)
        public static let control = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    public var key: Key
    public var modifiers: Modifiers
    /// 押したキーの JIS キーボードでの刻印(「q」「1」「@」など)．かな入力でかなを引くのに使う(KanaLayout)．
    /// 配列によらず位置で決まるので，アダプタが分かるときだけ入れる
    public var keyLabel: String?

    public init(_ key: Key, modifiers: Modifiers = [], keyLabel: String? = nil) {
        self.key = key
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }
}

extension KeyEvent: CustomStringConvertible, CustomDebugStringConvertible {
    // 入力した文字がログに出ないよう，文字そのものは伏せる(docs/dev/SECURITY-MODEL.md)
    public var description: String {
        switch key {
        case .character: "KeyEvent(character, modifiers: \(modifiers.rawValue))"
        default: "KeyEvent(\(key), modifiers: \(modifiers.rawValue))"
        }
    }

    public var debugDescription: String { description }
}
