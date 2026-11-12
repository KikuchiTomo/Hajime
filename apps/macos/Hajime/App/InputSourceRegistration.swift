import AppKit
import HajimeDomain
import os

/// 入れた Hajime IME が OS の入力ソースから外れていたら，Contents/Helpers の補助のアプリに登録し直してもらう．
///
/// OS は入れた入力メソッドを入力ソースの一覧から外すことがある(同じバンドル ID のアプリが別の場所に登録されたときなど)．
/// 外れると OS は英字の配列(ABC)で入力させ，キーがこの IME に届かず，英数・かなのキーでも戻せない．
/// 入力ソースの一覧はサンドボックスの外のプロセスが共有していて，この IME(サンドボックスの中)は自分用の写しを読むので
/// 外れたことが見えず，ここから登録し直しても共有の一覧には届かない(2026-11-12 に確かめた)．
/// そのため確かめるのも登録し直すのも，サンドボックスの外で動く補助のアプリ(HajimeInputSourceHelper)に任せる．
/// 外れているあいだも，OS はほかの入力先でこの IME を有効にするので，起動したときと入力先が変わったときに，間を空けて起動する
@MainActor
final class InputSourceRegistration {
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "app")
    private let bundle: Bundle
    private var lastRequested: ContinuousClock.Instant?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// 補助のアプリを起動して，外れていれば登録し直してもらう．間を空けずに呼ばれたときは起動しない
    func repairIfNeeded() {
        let now = ContinuousClock.now
        if let lastRequested, now - lastRequested < .seconds(DefaultSettings.inputSourceCheckInterval) { return }
        lastRequested = now
        // 入力メソッドの置き場所(Input Methods)から動いているときだけ．ビルドしたフォルダから動かしたものは登録しない
        guard bundle.bundleURL.deletingLastPathComponent().lastPathComponent == "Input Methods" else { return }
        let helper = bundle.bundleURL.appendingPathComponent("Contents/Helpers/\(AppIdentity.inputSourceHelperName).app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: helper.path) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        NSWorkspace.shared.openApplication(at: helper, configuration: configuration) { [logger] _, error in
            guard let error else { return }
            logger.error("入力ソースを確かめる補助のアプリを起動できませんでした: \(String(describing: error), privacy: .public)")
        }
    }
}
