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
    /// 設定とユーザー辞書を突き合わせている仕事．終わるまで次の同期を始めない
    private var settingsTask: Task<Void, Never>?
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
        SyncStatus(state: synchronizer.state, problem: problem, isSyncing: settingsTask != nil || dictionaryTask != nil)
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

    /// 今すぐ同期する．同期しない設定か，フォルダを選んでいなければ何もしない．
    /// 同期のファイルの読み書きはメインスレッドの外で行い，時間の上限(DefaultSettings.syncFileTimeout)を過ぎたら待つのをやめる．
    /// どこで失敗しても problem に記録するだけで，入力は止めない
    public func syncNow() {
        let state = synchronizer.state
        guard state.isEnabled, let path = state.folderPath, settingsTask == nil else { return }
        guard let folder = LocalFilePath.existingDirectory(path) else {
            // 外付けのドライブを外した，クラウドのアプリを止めたなど．フォルダが戻れば次の同期で続ける
            problem = .folderUnavailable
            return
        }
        settingsTask = Task { [weak self] in
            await self?.syncSettings(in: folder)
            self?.settingsTask = nil
        }
    }

    private func syncSettings(in folder: URL) async {
        let backend = FolderSyncBackend(folder: folder)
        guard let read = await Deadline.run(seconds: DefaultSettings.syncFileTimeout, { await Self.perform { try backend.read() } }) else {
            problem = .folderUnavailable
            return
        }
        do {
            let merged = try runner.merge(remote: try read.get())
            if let written = merged.written {
                let wrote = await Deadline.run(seconds: DefaultSettings.syncFileTimeout, { await Self.perform { try backend.write(written) } })
                guard let wrote else {
                    problem = .folderUnavailable
                    return
                }
                try wrote.get()
            }
            try runner.commit(merged)
            problem = nil
            syncDictionaryFiles(in: folder)
        } catch {
            problem = error as? SettingsSynchronizer.SyncError == .unreadableDocument ? .unreadable : .failed
        }
    }

    @concurrent
    private static func perform<Value: Sendable>(_ body: @Sendable () throws -> Value) async -> Result<Value, any Error> {
        Result { try body() }
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

    /// 同期と索引の運びが終わるまで待つ(テスト用)
    func waitForSync() async {
        await settingsTask?.value
        await dictionaryTask?.value
    }
}
