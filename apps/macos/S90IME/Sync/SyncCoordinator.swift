import AppKit
import os
import S90Application
import S90Domain
import S90Persistence

/// 同期の時機とフォルダの扱い(TODO 43・49)．設定を変えたら少し待って同期し，ほかの Mac の変更を一定の間隔で取り込む．
///
/// フォルダはサンドボックスの外にあるので，利用者が選んだときにセキュリティスコープ付きのブックマークを作って覚え，
/// 同期のたびにブックマークから開いて，終わったら閉じる
@MainActor
final class SyncCoordinator: ObservableObject {
    @Published private(set) var state: SyncState
    @Published private(set) var lastError: String?
    private let synchronizer: SettingsSynchronizer
    private var writeTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var isSyncing = false
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "sync")

    init(synchronizer: SettingsSynchronizer, settings: any SettingsObserving) {
        self.synchronizer = synchronizer
        self.state = synchronizer.state
        settings.observe { [weak self] _ in self?.scheduleSync() }
    }

    /// 起動したときに一度同期し，そのあとは一定の間隔で同期のファイルを見る
    func start() {
        syncNow()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DefaultSettings.syncPollInterval))
                self?.syncNow()
            }
        }
    }

    /// 同期のフォルダを選ぶ．選んだら同期を始める
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            try synchronizer.setEnabled(true, folderBookmark: bookmark, folderName: url.lastPathComponent)
            refresh()
            syncNow()
        } catch {
            fail(error)
        }
    }

    func setEnabled(_ enabled: Bool) {
        do {
            try synchronizer.setEnabled(enabled, folderBookmark: state.folderBookmark, folderName: state.folderName)
            refresh()
            if enabled { syncNow() }
        } catch {
            fail(error)
        }
    }

    func setScope(_ scope: SyncScope, for group: SyncGroup) {
        do {
            try synchronizer.setScope(scope, for: group)
            refresh()
            syncNow()
        } catch {
            fail(error)
        }
    }

    /// 今すぐ同期する．同期しない設定か，フォルダを選んでいなければ何もしない
    func syncNow() {
        guard state.isEnabled, let bookmark = state.folderBookmark, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            var isStale = false
            let folder = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            guard folder.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
            defer { folder.stopAccessingSecurityScopedResource() }
            if isStale {
                // フォルダを動かしたなどでブックマークが古くなったら作り直す
                let renewed = try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                try synchronizer.setEnabled(true, folderBookmark: renewed, folderName: folder.lastPathComponent)
            }
            try synchronizer.sync(with: FolderSyncBackend(folder: folder))
            lastError = nil
        } catch {
            fail(error)
        }
        refresh()
    }

    private func scheduleSync() {
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(DefaultSettings.syncWriteDelay))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    private func refresh() {
        state = synchronizer.state
    }

    private func fail(_ error: any Error) {
        // 理由の種類だけを記録する．同期のファイルの中身(設定やユーザー辞書の語)は出さない
        logger.error("同期できませんでした: \(String(describing: type(of: error)), privacy: .public)")
        lastError = error as? SettingsSynchronizer.SyncError == .unreadableDocument ? UIStrings.Sync.unreadable : UIStrings.Sync.failed
    }
}
