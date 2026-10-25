import Carbon
import InputMethodKit
import S90Application
import S90Domain

/// 入力先のアプリと入力欄の情報を集める．
@MainActor
final class InputContextProvider {
    private let settings: any SettingsReading

    init(settings: any SettingsReading) {
        self.settings = settings
    }

    func context(for client: any IMKTextInput) -> InputContext {
        InputContext(
            profile: settings.current.profile(forApplication: client.bundleIdentifier()),
            // パスワード欄などで Secure Input が有効なら，変換も学習もしない
            isSecure: IsSecureEventInputEnabled()
        )
    }
}
