import AppKit
import HajimeDomain

/// NSEvent を OS に依存しない KeyEvent に変える．判断はしない．
enum NSEventKeyTranslator {
    // macOS の仮想キーコード(HIToolbox の kVK_*)
    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let delete: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let home: UInt16 = 115
        static let end: UInt16 = 119
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
        static let escape: UInt16 = 53
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
        static let jisEisu: UInt16 = 102
        static let jisKana: UInt16 = 104
        static let jisYen: UInt16 = 93
        /// F1〜F20(キー設定の表で割り当てられる．R-17)
        static let functionKeys: [UInt16: Int] = [
            122: 1, 120: 2, 99: 3, 118: 4, 96: 5, 97: 6, 98: 7, 100: 8, 101: 9, 109: 10,
            103: 11, 111: 12, 105: 13, 107: 14, 113: 15, 106: 16, 64: 17, 79: 18, 80: 19, 90: 20,
        ]
        /// テンキーの数字と記号(. * + / - =)．Enter(76)と Clear(71)は含めない
        static let keypad: Set<UInt16> = [65, 67, 69, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]
    }

    static func translate(_ event: NSEvent) -> KeyEvent? {
        guard event.type == .keyDown else { return nil }
        let modifiers = translateModifiers(event.modifierFlags)
        let key: KeyEvent.Key? = switch event.keyCode {
        case KeyCode.returnKey, KeyCode.keypadEnter: .enter
        case KeyCode.tab: .tab
        case KeyCode.space: .space
        case KeyCode.delete: .backspace
        case KeyCode.forwardDelete: .delete
        case KeyCode.home: .home
        case KeyCode.end: .end
        case KeyCode.pageUp: .pageUp
        case KeyCode.pageDown: .pageDown
        case KeyCode.escape: .escape
        case KeyCode.left: .left
        case KeyCode.right: .right
        case KeyCode.down: .down
        case KeyCode.up: .up
        case KeyCode.jisEisu: .eisu
        case KeyCode.jisKana: .kana
        case KeyCode.jisYen: .yen
        case let code where KeyCode.functionKeys[code] != nil: KeyCode.functionKeys[code].map(KeyEvent.Key.function)
        default: character(from: event, modifiers: modifiers).map(KeyEvent.Key.character)
        }
        return key.map { KeyEvent($0, modifiers: modifiers, keyLabel: jisLabels[event.keyCode], isKeypad: KeyCode.keypad.contains(event.keyCode)) }
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
        // Control・Option・Command を押しているときは，それで変わる前の文字で判断する(Control+K，Option+Z など．キー設定の表で引く)．
        // Option で入る特殊な文字(å)は，表に無ければ InputSession がアプリに渡し，アプリが元のキーから入れる
        let changesCharacter = modifiers.contains(.control) || modifiers.contains(.option) || modifiers.contains(.command)
        let text = changesCharacter ? event.charactersIgnoringModifiers : event.characters
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
