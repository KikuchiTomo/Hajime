import Foundation
import HajimeApplication
@testable import HajimeDomain
@testable import HajimePersistence
import Testing

@MainActor
@Suite("同期のフォルダで設定と辞書の索引を運ぶ(R-15・R-16)")
struct FolderSyncRunnerTests {
    @MainActor
    private final class MemoryStateStore: SyncStateStoring {
        var state = SyncState()
        func save(_ state: SyncState) throws { self.state = state }
    }

    /// 1 台の PC．設定のファイル・辞書の索引の置き場所・同期の手順
    @MainActor
    private struct Machine {
        let settings: FileSettingsStore
        let dictionaries: ImportedDictionaryStore
        let runner: FolderSyncRunner

        init(_ directory: URL, clock: @escaping () -> Date) {
            settings = FileSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
            dictionaries = ImportedDictionaryStore(directory: directory.appendingPathComponent("dictionaries", isDirectory: true))
            let synchronizer = SettingsSynchronizer(settings: settings, stateStore: MemoryStateStore(), clock: clock)
            runner = FolderSyncRunner(synchronizer: synchronizer, settings: settings, dictionaries: dictionaries)
        }

        func sync(_ folder: URL) async throws {
            #expect(await runner.syncSettings(in: folder) == nil)
            if let files = runner.dictionaryFiles() { runner.finish(try files.run(in: folder)) }
        }
    }

    @Test("A で取り込んだ辞書が B に届いて引け，A で消すと B の索引も消える")
    func dictionaryTravels() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-runner-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var time = Date(timeIntervalSince1970: 10_000)
        let clock = { time }
        let a = Machine(root.appendingPathComponent("a"), clock: clock)
        let b = Machine(root.appendingPathComponent("b"), clock: clock)

        let source = root.appendingPathComponent("電気.txt")
        try Data("でんあつ\t電圧\t名詞\n".utf8).write(to: source)
        let dictionary = ImportedDictionary(id: "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B", name: "電気", wordCount: 0)
        let imported = try a.dictionaries.importFile(from: source, as: dictionary)
        #expect(imported.wordCount == 1)
        #expect(imported.revision == (try DictionaryFileSync.sha256(of: a.dictionaries.url(for: dictionary))))
        try a.settings.update { _ = ImportedDictionary.record(imported, isNew: true, in: &$0.importedDictionaries) }

        try await a.sync(folder)
        time += 10
        try await b.sync(folder)
        #expect(b.settings.current.importedDictionaries.map(\.id) == [dictionary.id])
        #expect(b.dictionaries.words(reading: "でんあつ", in: imported).map(\.word) == ["電圧"])

        time += 10
        try a.settings.update { $0.importedDictionaries = [] }
        try await a.sync(folder)
        time += 10
        try await b.sync(folder)
        #expect(b.settings.current.importedDictionaries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: b.dictionaries.url(for: dictionary).path))
    }

    @Test("取り込んだ辞書のまとまりをこの PC だけにすると，索引は運ばない")
    func localScopeSkipsFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-runner-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        let state = MemoryStateStore()
        state.state.scopes[.importedDictionaries] = .local
        let synchronizer = SettingsSynchronizer(settings: store, stateStore: state)
        let runner = FolderSyncRunner(synchronizer: synchronizer, settings: store,
                                      dictionaries: ImportedDictionaryStore(directory: root.appendingPathComponent("dictionaries")))
        try store.update { $0.importedDictionaries = [ImportedDictionary(id: "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B", name: "電気", wordCount: 1)] }
        #expect(runner.dictionaryFiles() == nil)
        state.state.scopes[.importedDictionaries] = .synced
        #expect(runner.dictionaryFiles() != nil)
    }
}
