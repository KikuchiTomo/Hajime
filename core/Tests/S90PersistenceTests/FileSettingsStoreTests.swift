import Foundation
import S90Domain
import S90Persistence
import Testing

@Suite("設定の保存")
@MainActor
struct FileSettingsStoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("s90-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    @Test("ファイルが無ければ既定値")
    func defaults() {
        #expect(FileSettingsStore(fileURL: temporaryFile()).current == DefaultSettings.settings)
    }

    @Test("保存した設定を読み直せ，本人だけが読み書きできる")
    func roundTrip() throws {
        let url = temporaryFile()
        let store = FileSettingsStore(fileURL: url)
        try store.update { $0.liveConversion = false }
        try store.update { $0.yenKey = .alwaysYen }
        #expect(FileSettingsStore(fileURL: url).current.liveConversion == false)
        #expect(FileSettingsStore(fileURL: url).current.yenKey == .alwaysYen)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test("壊れたファイルなら既定値で始める")
    func broken() throws {
        let url = temporaryFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: url)
        #expect(FileSettingsStore(fileURL: url).current == DefaultSettings.settings)
    }

    @Test("大きすぎるファイルは読まない")
    func tooLarge() throws {
        let url = temporaryFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: DefaultSettings.maximumSettingsFileBytes + 1).write(to: url)
        #expect(FileSettingsStore(fileURL: url).current == DefaultSettings.settings)
    }
}
