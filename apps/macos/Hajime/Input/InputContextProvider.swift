import Carbon
import InputMethodKit
import HajimeApplication
import HajimeDomain

/// 入力先のアプリと入力欄の情報を集める．
@MainActor
final class InputContextProvider {
    private let settings: any SettingsReading

    init(settings: any SettingsReading) {
        self.settings = settings
    }

    /// - Parameter includePrecedingText: 入力位置の前の文字列を読むか．打ち始めのときだけ読む(毎キー問い合わせないため)
    func context(for client: any IMKTextInput, includePrecedingText: Bool) -> InputContext {
        // パスワード欄などで Secure Input が有効なら，変換も学習もしない．前の文字列も読まない
        let isSecure = IsSecureEventInputEnabled()
        let application = client.bundleIdentifier()
        return InputContext(
            profile: settings.current.profile(forApplication: application),
            isSecure: isSecure,
            precedingText: includePrecedingText && !isSecure ? precedingText(of: client) : nil,
            applicationID: application
        )
    }

    /// 入力位置の前にある文字列．アプリが教えないときは nil．中身はログに出さない
    private func precedingText(of client: any IMKTextInput) -> String? {
        let selection = client.selectedRange()
        guard selection.location != NSNotFound, selection.location > 0 else { return nil }
        let length = min(selection.location, DefaultSettings.maximumLeftContextLength)
        return client.attributedSubstring(from: NSRange(location: selection.location - length, length: length))?.string
    }
}
