import Carbon
import HajimeDomain
import os

/// 入れた Hajime IME が OS の入力ソースから外れていたら，登録し直す．
/// 同じバンドル ID のアプリが別の場所に登録される(開発でビルドしたものなど)と，OS が入れたほうを入力ソースから外すことがある．
/// 外れると入力メニューで切り替えられず，入力ソースを消して足し直すまで使えない．外れても OS はこのプロセスに入力先を渡し続けるので，
/// 起動したときと入力先が変わったときに確かめる．有効にしていたかどうかは OS が覚えているので，登録し直すだけでよい
@MainActor
final class InputSourceRegistration {
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "app")
    private let bundle: Bundle
    private var lastChecked: ContinuousClock.Instant?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// 入力ソースから外れていれば登録し直す．間を空けずに呼ばれたときは確かめない
    func repairIfNeeded() {
        let now = ContinuousClock.now
        if let lastChecked, now - lastChecked < .seconds(DefaultSettings.inputSourceCheckInterval) { return }
        lastChecked = now
        // 入力メソッドの置き場所(Input Methods)から動いているときだけ登録する．ビルドしたフォルダから動かしたものは登録しない
        guard bundle.bundleURL.deletingLastPathComponent().lastPathComponent == "Input Methods",
              let identifier = bundle.bundleIdentifier, !isRegistered(identifier) else { return }
        let status = TISRegisterInputSource(bundle.bundleURL as CFURL)
        if status == noErr {
            logger.notice("入力ソースから外れていたので，登録し直しました")
        } else {
            logger.error("入力ソースから外れていたので登録し直そうとしましたが，失敗しました(\(status, privacy: .public))")
        }
    }

    private func isRegistered(_ identifier: String) -> Bool {
        let filter = [kTISPropertyBundleID as String: identifier] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() else { return false }
        return CFArrayGetCount(sources) > 0
    }
}
