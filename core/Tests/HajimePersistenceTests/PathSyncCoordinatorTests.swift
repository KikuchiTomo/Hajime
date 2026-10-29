import Foundation
import HajimeApplication
@testable import HajimeDomain
@testable import HajimePersistence
import Testing

@MainActor
@Suite("パスで選んだフォルダの同期(R-15．Windows)")
struct PathSyncCoordinatorTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-pathsync-\(UUID().uuidString)", isDirectory: true)

    /// 1 台の PC
    @MainActor
    private struct Machine {
        let settings: FileSettingsStore
        let dictionaries: ImportedDictionaryStore
        let files: SettingsFiles
        let sync: PathSyncCoordinator

        init(_ directory: URL) {
            settings = FileSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
            dictionaries = ImportedDictionaryStore(directory: directory.appendingPathComponent("dictionaries", isDirectory: true))
            files = SettingsFiles(settings: settings, dictionaries: dictionaries)
            let synchronizer = SettingsSynchronizer(settings: settings,
                                                    stateStore: FileSyncStateStore(fileURL: directory.appendingPathComponent("sync-state.json")))
            sync = PathSyncCoordinator(synchronizer: synchronizer,
                                       runner: FolderSyncRunner(synchronizer: synchronizer, settings: settings, dictionaries: dictionaries),
                                       settings: settings)
        }
    }

    @Test("フォルダを選ぶと同期を始め，ほかの PC に設定と取り込んだ辞書が届く")
    func twoMachines() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("OneDrive", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let a = Machine(root.appendingPathComponent("a"))
        let b = Machine(root.appendingPathComponent("b"))

        try a.settings.update { $0.liveConversion = false }
        let source = root.appendingPathComponent("電気.txt")
        try Data("でんあつ\t電圧\n".utf8).write(to: source)
        let dictionary = try await a.files.importDictionary(from: source.path, replacing: nil)
        try a.sync.chooseFolder(path: folder.path)
        await a.sync.waitForSync()
        #expect(a.sync.status.state.isEnabled)
        #expect(a.sync.status.state.folderName == "OneDrive")
        #expect(a.sync.status.problem == nil)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent(FolderSyncBackend.fileName).path))

        try b.sync.chooseFolder(path: folder.path)
        await b.sync.waitForSync()
        #expect(b.settings.current.liveConversion == false)
        #expect(b.dictionaries.words(reading: "でんあつ", in: dictionary).map(\.word) == ["電圧"])
        a.sync.stop()
        b.sync.stop()
    }

    @Test("無いフォルダは選べず，選んだフォルダが無くなれば folderUnavailable")
    func folderProblems() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let machine = Machine(root.appendingPathComponent("a"))
        #expect(throws: SettingsFileFailure.invalidPath) { try machine.sync.chooseFolder(path: root.appendingPathComponent("無い").path) }
        #expect(throws: SettingsFileFailure.invalidPath) { try machine.sync.chooseFolder(path: "relative") }
        #expect(!machine.sync.status.state.isEnabled)

        let folder = root.appendingPathComponent("USB", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try machine.sync.chooseFolder(path: folder.path)
        await machine.sync.waitForSync()
        try FileManager.default.removeItem(at: folder)
        machine.sync.syncNow()
        #expect(machine.sync.status.problem == .folderUnavailable)
        machine.sync.stop()
    }

    @Test("同期のファイルが壊れていれば上書きせずに unreadable．入力の設定はそのまま使える")
    func unreadable() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(FolderSyncBackend.fileName)
        try Data("not json".utf8).write(to: file)
        let machine = Machine(root.appendingPathComponent("a"))
        try machine.settings.update { $0.liveConversion = false }
        try machine.sync.chooseFolder(path: folder.path)
        await machine.sync.waitForSync()
        #expect(machine.sync.status.problem == .unreadable)
        #expect(machine.settings.current.liveConversion == false)
        #expect(try Data(contentsOf: file) == Data("not json".utf8))
        machine.sync.stop()
    }
}
