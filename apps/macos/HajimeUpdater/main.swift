import AppKit
import HajimeDomain

/// 更新用のアプリ(Hajime IME Updater)．IME の本体(Hajime.app)の Contents/Helpers に入れ，入力メニューと設定の画面の「更新を確認」から起動する．
///
/// IME の本体はサンドボックスの中で通信の権限を持たず，すべてのキー入力を受け取る．
/// 通信と管理者の権限でのインストールは，キー入力を受け取らないこの別のアプリだけが行う(SECURITY-MODEL.md の通信)．
/// 起動されたら 1 回だけ更新を確かめて終わる．ここがこのアプリの composition root
enum UpdaterIdentity {
    static let subsystem = Bundle.main.bundleIdentifier ?? "men.haji.inputmethod.Hajime.Updater"
    static let displayName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "Hajime IME Updater"
    /// 本体と同じバージョン(apps/macos/project.yml の MARKETING_VERSION を共有する)
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
}

@MainActor
final class UpdaterDelegate: NSObject, NSApplicationDelegate {
    private let updater: Updater

    init(updater: Updater) {
        self.updater = updater
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await updater.run()
            NSApp.terminate(nil)
        }
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    // Dock に出さない．窓と警告だけを出す
    application.setActivationPolicy(.accessory)
    let updater = Updater(installedVersion: ReleaseVersion(UpdaterIdentity.version), client: UpdateClient(version: UpdaterIdentity.version),
                          verifier: PackageVerifier(), installer: PackageInstaller())
    let delegate = UpdaterDelegate(updater: updater)
    application.delegate = delegate
    withExtendedLifetime(delegate) {
        application.run()
    }
}
