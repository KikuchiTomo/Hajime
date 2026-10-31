import AppKit
import os
import HajimeDomain

/// 読みで呼び出すコマンド(LauncherCommand)を macOS で動かす(R-22)．
///
/// アプリはサンドボックスの中で動くので，どれも Launch Services(NSWorkspace)に頼んで開く．プロセスを直に起こさず，シェルも通さない
/// - アプリ: アプリのパスかバンドル ID
/// - URL: http・https だけ(LauncherCommand.isValidTarget)
/// - ファイル: 設定の画面で選んだときに作ったセキュリティスコープ付きのブックマーク(CommandBookmarks)で開く
/// - ショートカット: ショートカット App の URL(shortcuts://run-shortcut)で名前を渡す
@MainActor
final class CommandLauncher {
    private let bookmarks: CommandBookmarks
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "commands")

    init(bookmarks: CommandBookmarks) {
        self.bookmarks = bookmarks
    }

    func run(_ command: LauncherCommand) {
        guard command.isValid else { return }
        switch command.kind {
        case .openApplication:
            guard let url = applicationURL(command.target) else { return failed(command) }
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [logger] _, error in
                if error != nil { logger.error("コマンドのアプリを開けませんでした") }
            }
        case .openURL:
            guard let url = URL(string: command.target) else { return failed(command) }
            NSWorkspace.shared.open(url)
        case .openFile:
            guard let url = bookmarks.resolve(id: command.id) else { return failed(command) }
            let accessing = url.startAccessingSecurityScopedResource()
            NSWorkspace.shared.open(url)
            if accessing { url.stopAccessingSecurityScopedResource() }
        case .runShortcut:
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: command.target)]
            guard let url = components.url else { return failed(command) }
            NSWorkspace.shared.open(url)
        }
    }

    /// アプリのパス(「/Applications/Claude.app」)か，バンドル ID(「com.anthropic.claudefordesktop」)
    private func applicationURL(_ target: String) -> URL? {
        if target.hasPrefix("/") {
            let url = URL(fileURLWithPath: target)
            return url.pathExtension == "app" ? url : nil
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: target)
    }

    private func failed(_ command: LauncherCommand) {
        // 行き先は利用者の書いたものなので，ログには種類だけを出す
        logger.error("コマンドを動かせませんでした: \(command.kind.rawValue, privacy: .public)")
        NSSound.beep()
    }
}

/// 「ファイルを開く」コマンドのファイルのブックマーク．サンドボックスの外のファイルは，利用者がファイルを選んだときにしか
/// 開けないので，設定の画面で選んだときにブックマークを作ってこの Mac の UserDefaults に覚える(同期しない)
@MainActor
final class CommandBookmarks {
    private let defaults: UserDefaults
    private static let key = "commandFileBookmarks"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func store(_ url: URL, id: String) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
        var all = defaults.dictionary(forKey: Self.key) as? [String: Data] ?? [:]
        all[id] = data
        defaults.set(all, forKey: Self.key)
    }

    func resolve(id: String) -> URL? {
        guard let data = (defaults.dictionary(forKey: Self.key) as? [String: Data])?[id] else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// 一覧に無いコマンドのブックマークを捨てる
    func prune(keeping ids: Set<String>) {
        guard let all = defaults.dictionary(forKey: Self.key) as? [String: Data] else { return }
        defaults.set(all.filter { ids.contains($0.key) }, forKey: Self.key)
    }
}
