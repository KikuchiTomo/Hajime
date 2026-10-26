/// 変換しているとき(分岐図)の操作．キーの割り当てを設定で変えられる
public enum ConversionCommand: String, Sendable, Equatable, Codable, CaseIterable, CodingKeyRepresentable {
    case nextCandidate
    case previousCandidate
    case nextSegment
    case previousSegment
    case nextUncertainSegment
    case previousUncertainSegment
    case extendSegment
    case shrinkSegment
}

/// キーの押し方．設定に保存できる形にしたもの
public struct KeyStroke: Sendable, Hashable, Codable {
    public enum Key: Sendable, Hashable, Codable {
        case space
        case tab
        case up
        case down
        case left
        case right
        /// 英字・数字・記号のキー(小文字で持つ)
        case character(String)
    }

    public var key: Key
    public var shift: Bool
    public var control: Bool
    public var option: Bool

    public init(_ key: Key, shift: Bool = false, control: Bool = false, option: Bool = false) {
        self.key = key
        self.shift = shift
        self.control = control
        self.option = option
    }

    /// キー入力から作る．割り当てられないキー(Enter・Escape・Backspace・Command 付きなど)は nil
    public init?(_ event: KeyEvent) {
        guard !event.modifiers.contains(.command) else { return nil }
        let key: Key
        switch event.key {
        case .space: key = .space
        case .tab: key = .tab
        case .up: key = .up
        case .down: key = .down
        case .left: key = .left
        case .right: key = .right
        case .character(let character): key = .character(character.lowercased())
        default: return nil
        }
        self.init(key, shift: event.modifiers.contains(.shift), control: event.modifiers.contains(.control), option: event.modifiers.contains(.option))
    }

    public func matches(_ event: KeyEvent) -> Bool {
        KeyStroke(event) == self
    }
}

/// 変換しているときの操作ごとのキーの割り当て．1 つの操作に複数のキーを割り当てられる．
/// Enter(確定)・Escape(戻る)・Backspace・番号キーは変えられない(どの操作もできなくなるのを防ぐため)
public struct KeyBindings: Sendable, Equatable, Codable {
    public var commands: [ConversionCommand: [KeyStroke]]

    public init(_ commands: [ConversionCommand: [KeyStroke]]) {
        self.commands = commands
    }

    /// 既定の割り当て．macOS・ATOK・Microsoft IME と同じく，↓ と Space で次の候補，Shift+←→ で文節の長さ
    public static let standard = KeyBindings([
        .nextCandidate: [KeyStroke(.down), KeyStroke(.space)],
        .previousCandidate: [KeyStroke(.up), KeyStroke(.space, shift: true)],
        .nextSegment: [KeyStroke(.right)],
        .previousSegment: [KeyStroke(.left)],
        .nextUncertainSegment: [KeyStroke(.tab)],
        .previousUncertainSegment: [KeyStroke(.tab, shift: true)],
        .extendSegment: [KeyStroke(.right, shift: true)],
        .shrinkSegment: [KeyStroke(.left, shift: true)],
    ])

    /// このキーに割り当てた操作．無ければ nil
    public func command(for event: KeyEvent) -> ConversionCommand? {
        guard let stroke = KeyStroke(event) else { return nil }
        return ConversionCommand.allCases.first { commands[$0]?.contains(stroke) == true }
    }

    public func strokes(for command: ConversionCommand) -> [KeyStroke] {
        commands[command] ?? []
    }

    /// command にキーを割り当てる．ほかの操作に同じキーがあれば外す(1 つのキーは 1 つの操作だけ)
    public mutating func assign(_ stroke: KeyStroke, to command: ConversionCommand) {
        for other in ConversionCommand.allCases { commands[other]?.removeAll { $0 == stroke } }
        commands[command, default: []].append(stroke)
    }

    public mutating func remove(_ stroke: KeyStroke, from command: ConversionCommand) {
        commands[command]?.removeAll { $0 == stroke }
    }

    /// 読み込んだ割り当てに無い操作は既定の割り当てで埋める(操作を足したときに古い設定でも使えるように)
    public func filled() -> KeyBindings {
        var result = self
        for command in ConversionCommand.allCases where result.commands[command] == nil {
            result.commands[command] = Self.standard.commands[command]
        }
        return result
    }
}
