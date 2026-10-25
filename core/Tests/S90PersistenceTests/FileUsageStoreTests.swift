import Foundation
import S90Domain
@testable import S90Persistence
import Testing

@Suite("使い方の記録のファイル", .serialized)
@MainActor
struct FileUsageStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("s90-usage-\(UUID().uuidString)/usage.json")
    }

    @Test("決まった回数ごとに，本人だけが読み書きできるファイルに書く")
    func savesWithPermission() throws {
        let url = temporaryURL()
        let store = FileUsageStore(fileURL: url, isEnabled: { true })
        for _ in 0..<(DefaultSettings.usageSaveInterval - 1) { store.record(.conversionOpened) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        store.record(.conversionOpened)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        #expect(FileUsageStore(fileURL: url, isEnabled: { true }).counts.conversionsOpened == DefaultSettings.usageSaveInterval)
    }

    @Test("記録を止めているあいだは数えない")
    func disabled() {
        let store = FileUsageStore(fileURL: temporaryURL(), isEnabled: { false })
        store.record(.conversionOpened)
        #expect(store.counts.conversionsOpened == 0)
    }

    @Test("壊れたファイルと大きすぎるファイルは読まずに 0 から数える")
    func brokenFile() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: url)
        #expect(FileUsageStore(fileURL: url, isEnabled: { true }).counts == UsageCounts())
        try Data(count: DefaultSettings.maximumUsageFileBytes + 1).write(to: url)
        #expect(FileUsageStore(fileURL: url, isEnabled: { true }).counts == UsageCounts())
    }
}

@Suite("暦")
@MainActor
struct SystemCalendarTests {
    @Test("決まった日時から，今日とずらした日を読む")
    func days() throws {
        var components = DateComponents()
        (components.year, components.month, components.day, components.hour, components.minute) = (2026, 10, 31, 23, 59)
        let date = try #require(Calendar(identifier: .gregorian).date(from: components))
        let calendar = SystemCalendar(clock: { date })
        #expect(calendar.now() == CalendarDate(year: 2026, month: 10, day: 31, weekday: 7, hour: 23, minute: 59))
        let tomorrow = calendar.day(offsetFromToday: 1)
        #expect((tomorrow.month, tomorrow.day, tomorrow.weekday) == (11, 1, 1))
    }
}
