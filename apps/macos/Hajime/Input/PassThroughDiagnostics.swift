import HajimeDomain
import os

/// 日本語のモードなのに英字のキーをアプリに渡したときに，その理由を記録する．
/// 「日本語のモードのまま英字しか入らない」状態になったとき，どの理由で渡したかを `log show` で調べられるようにする．
/// 打った文字・アプリの識別子は記録せず，理由だけを残す(docs/dev/SECURITY-MODEL.md)．同じ理由は間を空けて記録する
@MainActor
final class PassThroughDiagnostics {
    private enum Reason: String {
        case secureInput = "保護された入力(Secure Input)が有効"
        case excludedApplication = "IME を使わないアプリ(除外設定)"
        case option = "Option キーが押されている"
        case other = "そのほか"
    }

    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "input")
    private var lastLogged: [Reason: ContinuousClock.Instant] = [:]

    /// キーをアプリに渡した(handled が false)ときに呼ぶ．日本語のモードで，⌘・⌃ の付かない英字のキーのときだけ理由を記録する．
    /// ターミナルの行の頭で英字をそのまま流す(R-07)のは決まった動きなので記録しない
    func recordPassThrough(_ event: KeyEvent, mode: InputMode, context: InputContext) {
        guard mode == .japanese, case .character(let character) = event.key, character.isASCII, character.isLetter,
              !event.modifiers.contains(.command), !event.modifiers.contains(.control), context.profile != .terminal else { return }
        let reason: Reason = if context.isSecure {
            .secureInput
        } else if context.profile == .direct {
            .excludedApplication
        } else if event.modifiers.contains(.option) {
            .option
        } else {
            .other
        }
        let now = ContinuousClock.now
        if let last = lastLogged[reason], now - last < .seconds(DefaultSettings.inputDiagnosticLogInterval) { return }
        lastLogged[reason] = now
        logger.notice("日本語のモードで英字のキーをアプリに渡しました(理由: \(reason.rawValue, privacy: .public))")
    }
}
