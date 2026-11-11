import AppKit
import Carbon
import HajimeDomain
import os

/// NSEvent を OS に依存しない KeyEvent に変える．判断はしない．
enum NSEventKeyTranslator {
    /// 英字の配列で引き直したことの記録．打った文字は記録せず，起きたことと配列の ID だけを残す(docs/dev/SECURITY-MODEL.md)
    private static let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "input")
    /// 引き直したことを最後に記録した時刻．打つたびに記録しないよう，間を空ける
    private static var lastFallbackLog: ContinuousClock.Instant?

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
        let shifted = shiftedCharacters(of: event)
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
        // キー配列が ¥ を入れるときだけ，¥ キーの設定で決める．Shift+¥ の | など，ほかの文字はキー配列の文字のまま使う
        case _ where YenKeyPolicy.isChoosable(shifted ?? ""): .yen
        case let code where KeyCode.functionKeys[code] != nil: KeyCode.functionKeys[code].map(KeyEvent.Key.function)
        default: character(from: event, shifted: shifted, modifiers: modifiers).map(KeyEvent.Key.character)
        }
        // テンキーの Enter もテンキーのキーとして渡す(テンキーの Enter で計算する設定)
        let isKeypad = KeyCode.keypad.contains(event.keyCode) || event.keyCode == KeyCode.keypadEnter
        return key.map { KeyEvent($0, modifiers: modifiers, keyLabel: jisLabels[event.keyCode], isKeypad: isKeypad) }
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

    /// キー配列が Shift だけを効かせて入れる文字(Option・Control・Command で変わる前)．
    /// IME が受けるイベントの charactersIgnoringModifiers には Shift も効いていない(Shift+¥ が ¥ になる)ので，キー配列から引き直す
    private static func shiftedCharacters(of event: NSEvent) -> String? {
        event.characters(byApplyingModifiers: event.modifierFlags.intersection(.shift)) ?? event.charactersIgnoringModifiers
    }

    private static func character(from event: NSEvent, shifted: String?, modifiers: KeyEvent.Modifiers) -> Character? {
        // Control・Option・Command を押しているときは，それで変わる前の文字で判断する(Control+K，Option+Z など．キー設定の表で引く)．
        // Option で入る特殊な文字(å)は，表に無ければ InputSession がアプリに渡し，アプリが元のキーから入れる
        let changesCharacter = modifiers.contains(.control) || modifiers.contains(.option) || modifiers.contains(.command)
        let text = changesCharacter ? shifted : event.characters
        guard let text, text.count == 1, let character = text.first else { return nil }
        // 制御文字(矢印などの機能キーは私用領域の文字で来る)は扱わない
        guard let scalar = character.unicodeScalars.first,
            !CharacterSet.controlCharacters.contains(scalar),
            !(0xF700...0xF8FF).contains(scalar.value) else { return nil }
        // 英字・数字・記号のキーなのに英字でない文字で来たときは，OS の英字の配列で引き直す．
        // 入力先の配列を OS が見つけられないと，英字のキーが英字でない文字で届き，日本語のモードのまま英字しか入らなくなる
        if !changesCharacter, !character.isASCII, jisLabels[event.keyCode] != nil,
           let ascii = asciiCharacter(keyCode: event.keyCode, shift: modifiers.contains(.shift)) {
            logFallback()
            return ascii
        }
        return character
    }

    /// 同じキーを OS で最後に使った英字の配列で打ったときの文字．英字の配列が無いか，英字でなければ nil
    private static func asciiCharacter(keyCode: UInt16, shift: Bool) -> Character? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let modifierState = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifierState, UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters)
        guard status == noErr, length == 1, let scalar = Unicode.Scalar(characters[0]), scalar.isASCII,
              !CharacterSet.controlCharacters.contains(scalar) else { return nil }
        return Character(scalar)
    }

    /// 英字の配列で引き直したことを記録する．入力先の配列(TISInputSourceID)も残し，どの配列で英字でない文字が来たかを後で調べられるようにする
    private static func logFallback() {
        let now = ContinuousClock.now
        if let last = lastFallbackLog, now - last < .seconds(DefaultSettings.inputDiagnosticLogInterval) { return }
        lastFallbackLog = now
        var layout = "不明"
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            layout = Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
        }
        logger.notice("英字のキーが英字でない文字で届いたので，英字の配列で読み直しました(入力先の配列: \(layout, privacy: .public))")
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
