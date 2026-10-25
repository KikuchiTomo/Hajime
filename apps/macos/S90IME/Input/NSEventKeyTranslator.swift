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
        return key.map { KeyEvent($0, modifiers: modifiers) }
    }

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
