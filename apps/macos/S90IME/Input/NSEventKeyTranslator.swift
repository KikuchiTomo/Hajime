import AppKit
import S90Domain

/// NSEvent を OS に依存しない KeyEvent に変える．判断はしない．
enum NSEventKeyTranslator {
    // macOS の仮想キーコード(HIToolbox の kVK_*)
    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let jisEisu: UInt16 = 102
        static let jisKana: UInt16 = 104
        static let jisYen: UInt16 = 93
    }

    static func translate(_ event: NSEvent) -> KeyEvent? {
        guard event.type == .keyDown else { return nil }
        let modifiers = translateModifiers(event.modifierFlags)
        let key: KeyEvent.Key? = switch event.keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter: .enter
        case KeyCode.tab: .tab
        case KeyCode.space: .space
        case KeyCode.delete: .backspace
        case KeyCode.escape: .escape
        case KeyCode.left: .left
        case KeyCode.right: .right
        case KeyCode.down: .down
        case KeyCode.up: .up
        case KeyCode.jisEisu: .eisu
        case KeyCode.jisKana: .kana
        case KeyCode.jisYen: .yen
        default: character(from: event, modifiers: modifiers).map(KeyEvent.Key.character)
        }
        return key.map { KeyEvent($0, modifiers: modifiers, keyLabel: jisLabels[event.keyCode]) }
    }

    /// 仮想キーコードから，JIS キーボードのその位置の刻印を引く．かな入力でかなを引くのに使う(KanaLayout)．
    /// 仮想キーコードはキーの位置で決まり，配列の設定(US・JIS)によらない
    private static let jisLabels: [UInt16: String] = {
        var labels: [UInt16: String] = [:]
        let letters: [(UInt16, String)] = [
            (0x00, "a"), (0x01, "s"), (0x02, "d"), (0x03, "f"), (0x04, "h"), (0x05, "g"), (0x06, "z"), (0x07, "x"),
            (0x08, "c"), (0x09, "v"), (0x0B, "b"), (0x0C, "q"), (0x0D, "w"), (0x0E, "e"), (0x0F, "r"), (0x10, "y"),
            (0x11, "t"), (0x1F, "o"), (0x20, "u"), (0x22, "i"), (0x23, "p"), (0x25, "l"), (0x26, "j"), (0x28, "k"),
            (0x2D, "n"), (0x2E, "m"),
        ]
        let digits: [(UInt16, String)] = [
            (0x12, "1"), (0x13, "2"), (0x14, "3"), (0x15, "4"), (0x17, "5"), (0x16, "6"), (0x1A, "7"), (0x1C, "8"),
            (0x19, "9"), (0x1D, "0"),
        ]
        // 記号のキーは，US 配列の名前のキーコードが JIS キーボードでは別の刻印の位置に当たる
        let symbols: [(UInt16, String)] = [
            (0x1B, "-"), (0x18, "^"), (0x21, "@"), (0x1E, "["), (0x29, ";"), (0x27, ":"), (0x2A, "]"),
            (0x2B, ","), (0x2F, "."), (0x2C, "/"), (0x5E, "_"),
        ]
        for (code, label) in letters + digits + symbols { labels[code] = label }
        return labels
    }()

    private static func character(from event: NSEvent, modifiers: KeyEvent.Modifiers) -> Character? {
        // Control を押しているときは，Control で変わる前の文字で判断する(Control+K など)
        let text = modifiers.contains(.control) ? event.charactersIgnoringModifiers : event.characters
        guard let text, text.count == 1, let character = text.first else { return nil }
        // 制御文字(矢印などの機能キーは私用領域の文字で来る)は扱わない
        guard let scalar = character.unicodeScalars.first,
            !CharacterSet.controlCharacters.contains(scalar),
            !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
        return character
    }

    private static func translateModifiers(_ flags: NSEvent.ModifierFlags) -> KeyEvent.Modifiers {
        var modifiers: KeyEvent.Modifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}
