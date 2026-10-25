import AppKit
import InputMethodKit
import os

private let logger = Logger(subsystem: "tokyo.s90.inputmethod.S90IME", category: "app")

#if DEBUG
MainActor.assumeIsolated { SnapshotRenderer.runIfRequested() }
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

guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
    let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier) else {
    logger.fault("IMKServer を作れませんでした")
    exit(1)
}

// server はプロセスが終わるまで保持する
withExtendedLifetime(server) {
    NSApplication.shared.run()
}
