import Foundation
import HajimeDomain
@testable import HajimePersistence
import Testing

@Suite("パレットの使い方のファイル", .serialized)
@MainActor
struct FilePaletteUsageStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hajime-palette-\(UUID().uuidString)/\(DefaultSettings.paletteUsageFileName)")
    }

    @Test("変えるたびに本人だけが読み書きできるファイルに書き，読み直せる")
    func savesWithPermission() throws {
        let url = temporaryURL()
        let store = FilePaletteUsageStore(fileURL: url)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        store.update { $0.record("🙇", at: date) }
        #if !os(Windows)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        #endif
        #expect(FilePaletteUsageStore(fileURL: url).usage.score(of: "🙇", at: date) == 1)
    }

    @Test("何も変えなければ書かない")
    func noChange() {
        let url = temporaryURL()
        FilePaletteUsageStore(fileURL: url).update { _ in }
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("壊れたファイルと大きすぎるファイルは読まずに空の使い方で始める")
    func brokenFile() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: url)
        #expect(FilePaletteUsageStore(fileURL: url).usage == PaletteUsage())
        try Data(count: DefaultSettings.maximumPaletteUsageFileBytes + 1).write(to: url)
        #expect(FilePaletteUsageStore(fileURL: url).usage == PaletteUsage())
    }
}
