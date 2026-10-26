/// キーの押し方(修飾キーとキーの組み合わせ)．キー設定の表(Keymap)の 1 行のキー．
///
/// 設定のファイルには「Ctrl Shift Space」のような文字列で書く(`notation`)．人が読めて，手で直せるようにするため
public struct KeyStroke: Sendable, Hashable {
    public enum Key: Sendable, Hashable {
        /// 英字・数字・記号のキー．英字は小文字で持ち，Shift は shift で表す
        case character(String)
        case space
        case enter
        case tab
        case backspace
        /// 右の文字を消すキー(⌦)
        case delete
        case escape
        case up
        case down
        case left
        case right
        case home
        case end
        case pageUp
        case pageDown
        /// ファンクションキー(F1〜F20)
        case function(Int)
        case eisu
        case kana
        case hankakuZenkaku
        case henkan
        case muhenkan
    }

    public var key: Key
    public var shift: Bool
    public var control: Bool
    public var option: Bool
    public var command: Bool

    public init(_ key: Key, shift: Bool = false, control: Bool = false, option: Bool = false, command: Bool = false) {
        self.key = key
        self.shift = shift
        self.control = control
        self.option = option
        self.command = command
    }

    /// キー入力から作る．表に書けないキー(¥ キー)は nil．
    /// 英字でない文字(「!」「:」)は Shift を含めて文字になっているので，Shift は持たない(US 配列の ⌃: と JIS 配列の ⌃: を同じにする)
    public init?(_ event: KeyEvent) {
        let key: Key
        var shift = event.modifiers.contains(.shift)
        switch event.key {
        case .character(let character):
            guard !character.isWhitespace else { return nil }
            if !character.isLetter { shift = false }
            key = .character(String(character).lowercased())
        case .space: key = .space
        case .enter: key = .enter
        case .tab: key = .tab
        case .backspace: key = .backspace
        case .delete: key = .delete
        case .escape: key = .escape
        case .up: key = .up
        case .down: key = .down
        case .left: key = .left
        case .right: key = .right
        case .home: key = .home
        case .end: key = .end
        case .pageUp: key = .pageUp
        case .pageDown: key = .pageDown
        case .function(let number): key = .function(number)
        case .eisu: key = .eisu
        case .kana: key = .kana
        case .hankakuZenkaku: key = .hankakuZenkaku
        case .henkan: key = .henkan
        case .muhenkan: key = .muhenkan
        case .yen: return nil
        }
        self.init(key, shift: shift, control: event.modifiers.contains(.control), option: event.modifiers.contains(.option),
                  command: event.modifiers.contains(.command))
    }

    public func matches(_ event: KeyEvent) -> Bool {
        KeyStroke(event) == self
    }

    /// 修飾キーを押していない文字のキー．表に足すと，その文字を打てなくなる
    public var isPlainCharacter: Bool {
        if case .character = key { return !control && !option && !command }
        return false
    }
}

// MARK: - 画面に出す名前

extension KeyStroke {
    /// 画面に出す短い名前(「⌃⇧Space」「⌥F1」「⌃K」)．修飾キーは macOS のメニューと同じ記号で ⌃⌥⇧⌘ の順．
    /// 候補ウィンドウの案内(core が組み立てる)と設定の画面で同じ名前を使う
    public var label: String {
        var name = ""
        if control { name += "⌃" }
        if option { name += "⌥" }
        if shift { name += "⇧" }
        if command { name += "⌘" }
        return name + Self.label(of: key)
    }

    private static func label(of key: Key) -> String {
        switch key {
        case .character(let text): text.uppercased()
        case .space: "Space"
        case .enter: "Enter"
        case .tab: "Tab"
        case .backspace: "⌫"
        case .delete: "⌦"
        case .escape: "Esc"
        case .up: "↑"
        case .down: "↓"
        case .left: "←"
        case .right: "→"
        case .home: "Home"
        case .end: "End"
        case .pageUp: "PageUp"
        case .pageDown: "PageDown"
        case .function(let number): "F\(number)"
        case .eisu: "英数"
        case .kana: "かな"
        case .hankakuZenkaku: "半角/全角"
        case .henkan: "変換"
        case .muhenkan: "無変換"
        }
    }
}

// MARK: - 文字列の書き方

extension KeyStroke {
    /// 名前で書くキーと，その名前．読むときは大文字と小文字を区別しない
    private static let names: [(Key, String)] = [
        (.space, "Space"), (.enter, "Enter"), (.tab, "Tab"), (.backspace, "Backspace"), (.delete, "Delete"), (.escape, "Escape"),
        (.up, "Up"), (.down, "Down"), (.left, "Left"), (.right, "Right"), (.home, "Home"), (.end, "End"),
        (.pageUp, "PageUp"), (.pageDown, "PageDown"), (.eisu, "Eisu"), (.kana, "Kana"), (.hankakuZenkaku, "Hankaku/Zenkaku"),
        (.henkan, "Henkan"), (.muhenkan, "Muhenkan"),
    ]
    /// 読むときだけ受け付ける別名
    private static let aliases: [String: Key] = ["esc": .escape, "return": .enter, "kanji": .hankakuZenkaku, "del": .delete]
    /// ファンクションキーの番号の範囲
    public static let functionKeys = 1...20

    /// 「Ctrl Shift Space」の形．修飾キーは Ctrl・Option・Shift・Cmd の順
    public var notation: String {
        var parts: [String] = []
        if control { parts.append("Ctrl") }
        if option { parts.append("Option") }
        if shift { parts.append("Shift") }
        if command { parts.append("Cmd") }
        parts.append(Self.name(of: key))
        return parts.joined(separator: " ")
    }

    private static func name(of key: Key) -> String {
        switch key {
        case .character(let text): return text
        case .function(let number): return "F\(number)"
        default: return names.first { $0.0 == key }?.1 ?? ""
        }
    }

    /// notation の形から作る．読めなければ nil
    public init?(notation: String) {
        let parts = notation.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let last = parts.last else { return nil }
        var stroke = KeyStroke(.space)
        for modifier in parts.dropLast() {
            switch modifier.lowercased() {
            case "ctrl", "control": stroke.control = true
            case "option", "alt": stroke.option = true
            case "shift": stroke.shift = true
            case "cmd", "command": stroke.command = true
            default: return nil
            }
        }
        let lowered = last.lowercased()
        if let named = Self.names.first(where: { $0.1.lowercased() == lowered }) {
            stroke.key = named.0
        } else if let alias = Self.aliases[lowered] {
            stroke.key = alias
        } else if lowered.count > 1, lowered.hasPrefix("f"), let number = Int(lowered.dropFirst()), Self.functionKeys.contains(number) {
            stroke.key = .function(number)
        } else if last.count == 1, let character = last.first, !character.isWhitespace {
            stroke.key = .character(lowered)
            if !character.isLetter { stroke.shift = false }
        } else {
            return nil
        }
        self = stroke
    }
}

extension KeyStroke: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let stroke = KeyStroke(notation: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "読めないキー"))
        }
        self = stroke
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(notation)
    }
}
