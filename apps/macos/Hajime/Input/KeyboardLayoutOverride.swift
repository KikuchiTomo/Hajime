import Carbon
import InputMethodKit
import HajimeDomain

/// 設定の英字の配列(KeyboardLayout)を，入力先のアプリに対して OS の配列に切り替える．
///
/// 「システムの設定に従う」のときも，OS で最後に使った英字の配列を指定する．指定しないと，Hajime IME のモードで
/// キーをどの配列で文字にするかを OS が決める．英字の配列を入力ソースに入れていないと OS が配列を見つけられず，
/// 英字のキーが英字でない文字で届いて，日本語のモードのまま英字しか入らなくなることがある(Mozc なども同じく常に指定する)
enum KeyboardLayoutOverride {
    static func apply(_ layout: KeyboardLayout, to client: any IMKTextInput) {
        guard let identifier = identifier(for: layout) else { return }
        client.overrideKeyboard(withKeyboardNamed: identifier)
    }

    /// macOS の配列の ID(TISInputSourceID)
    private static func identifier(for layout: KeyboardLayout) -> String? {
        switch layout {
        case .system: currentASCIICapableLayout()
        case .abc: "com.apple.keylayout.ABC"
        case .us: "com.apple.keylayout.US"
        case .dvorak: "com.apple.keylayout.Dvorak"
        case .dvorakQwertyCommand: "com.apple.keylayout.DVORAK-QWERTYCMD"
        case .colemak: "com.apple.keylayout.Colemak"
        }
    }

    /// OS で最後に使った英字の配列の ID．入力ソースに英字の配列が無くても，OS は最後に使った配列(既定は ABC)を返す
    private static func currentASCIICapableLayout() -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    }
}
