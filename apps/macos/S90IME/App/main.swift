import AppKit
import InputMethodKit
import os

private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "app")

#if DEBUG
MainActor.assumeIsolated {
    SnapshotRenderer.runIfRequested()
    SettingsBenchmark.runIfRequested()
}
#endif

MainActor.assumeIsolated {
    do {
        try CompositionRoot.install()
    } catch {
        // 組み立てに失敗すると入力できないので，理由を残して終わる．入力内容はここに含まれない
        logger.fault("起動に失敗しました: \(String(describing: error), privacy: .public)")
        exit(1)
    }
}

#if DEBUG
// 開発版だけ: 起動してすぐ設定の画面を開く(入力メニューを使わずに，画面が出るかを確かめる)
if CommandLine.arguments.contains("--open-settings") {
    MainActor.assumeIsolated { CompositionRoot.installed?.settingsWindow.show() }
}
#endif

guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
    let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier) else {
    logger.fault("IMKServer を作れませんでした")
    exit(1)
}

// server はプロセスが終わるまで保持する
withExtendedLifetime(server) {
    NSApplication.shared.run()
}
