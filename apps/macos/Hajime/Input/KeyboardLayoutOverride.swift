import InputMethodKit
import HajimeDomain

/// 設定の英字の配列(KeyboardLayout)を，入力先のアプリに対して OS の配列に切り替える．
/// 「OS のまま」のときは切り替えない
enum KeyboardLayoutOverride {
    static func apply(_ layout: KeyboardLayout, to client: any IMKTextInput) {
        guard let identifier = identifier(for: layout) else { return }
        client.overrideKeyboard(withKeyboardNamed: identifier)
    }

    /// macOS の配列の ID(TISInputSourceID)
    private static func identifier(for layout: KeyboardLayout) -> String? {
        switch layout {
        case .system: nil
        case .abc: "com.apple.keylayout.ABC"
        case .us: "com.apple.keylayout.US"
        case .dvorak: "com.apple.keylayout.Dvorak"
        case .dvorakQwertyCommand: "com.apple.keylayout.DVORAK-QWERTYCMD"
        case .colemak: "com.apple.keylayout.Colemak"
        }
    }
}
