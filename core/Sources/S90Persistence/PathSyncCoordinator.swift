import Foundation
import S90Application
import S90Domain

/// パスで選んだフォルダで同期する時機を決める(R-15．Windows)．macOS の SyncCoordinator と同じ時機で動く．
///
/// - 起動したときに一度同期し，そのあとは DefaultSettings.syncPollInterval ごとにほかの PC の変更を取り込む
/// - 設定を変えたら DefaultSettings.syncWriteDelay だけ待って同期する(続けて変えたときに何度も書かないため)
/// - 取り込んだ辞書の索引は数百 MB になりうるので，メインスレッドの外で運ぶ
///
/// Windows にはセキュリティスコープ付きのブックマークが無いので，選んだフォルダはパスで覚える(SyncState.folderPath)
@MainActor
public final class PathSyncCoordinator: SyncControlling {
    private let synchronizer: SettingsSynchronizer
    private let runner: FolderSyncRunner
    private var problem: SyncProblem?
    private var isSyncingSettings = false
    private var dictionaryTask: Task<Void, Never>?
    private var writeTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    public init(synchronizer: SettingsSynchronizer, runner: FolderSyncRunner, settings: any SettingsObserving) {
        self.synchronizer = synchronizer
        self.runner = runner
        settings.observe { [weak self] _ in self?.scheduleSync() }
    }

    /// 起動したときに一度同期し，そのあとは一定の間隔で同期のファイルを見る
    public func start() {
        syncNow()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DefaultSettings.syncPollInterval))
                self?.syncNow()
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        writeTask?.cancel()
    }

    public var status: SyncStatus {
        SyncStatus(state: synchronizer.state, problem: problem, isSyncing: isSyncingSettings || dictionaryTask != nil)
    }

    public func chooseFolder(path: String) throws {
        guard let folder = LocalFilePath.existingDirectory(path) else { throw SettingsFileFailure.invalidPath }
        try synchronizer.setFolder(path: folder.path, name: folder.lastPathComponent)
        problem = nil
        syncNow()
    }

    public func setEnabled(_ enabled: Bool) throws {
        try synchronizer.setEnabled(enabled)
        if enabled { syncNow() }
    }

    public func setScope(_ scope: SyncScope, for group: SyncGroup) throws {
        try synchronizer.setScope(scope, for: group)
        syncNow()
    }

    public func setLocal(_ isLocal: Bool, field: String) throws {
        try synchronizer.setLocal(isLocal, field: field)
    }

    /// 今すぐ同期する．同期しない設定か，フォルダを選んでいなければ何もしない
    public func syncNow() {
        let state = synchronizer.state
        guard state.isEnabled, let path = state.folderPath, !isSyncingSettings else { return }
        guard let folder = LocalFilePath.existingDirectory(path) else {
            // 外付けのドライブを外した，クラウドのアプリを止めたなど．フォルダが戻れば次の同期で続ける
            problem = .folderUnavailable
            return
        }
        isSyncingSettings = true
        defer { isSyncingSettings = false }
        do {
            try runner.syncSettings(in: folder)
            problem = nil
            syncDictionaryFiles(in: folder)
        } catch {
            problem = error as? SettingsSynchronizer.SyncError == .unreadableDocument ? .unreadable : .failed
        }
    }

    /// 取り込んだ辞書の索引を運ぶ．前の分が終わっていなければ何もしない(次の同期でまた見る)
    private func syncDictionaryFiles(in folder: URL) {
        guard dictionaryTask == nil, let files = runner.dictionaryFiles() else { return }
        dictionaryTask = Task { [weak self] in
            let result = await Self.run(files, in: folder)
            self?.finishDictionaryFiles(result)
        }
    }

    @concurrent
    private static func run(_ files: FolderSyncRunner.DictionaryFiles, in folder: URL) async -> Result<DictionaryFileSync.Outcome, any Error> {
        Result { try files.run(in: folder) }
    }

    private func finishDictionaryFiles(_ result: Result<DictionaryFileSync.Outcome, any Error>) {
        dictionaryTask = nil
        switch result {
        case .success(let outcome):
            runner.finish(outcome)
        case .failure:
            problem = .failed
        }
    }

    private func scheduleSync() {
        writeTask?.cancel()
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(DefaultSettings.syncWriteDelay))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
    }

    /// 索引を運び終えるまで待つ(テスト用)
    func waitForDictionaryFiles() async {
        await dictionaryTask?.value
    }
}
