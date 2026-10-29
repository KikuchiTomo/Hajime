import Foundation
import HajimeDomain
@testable import HajimePersistence
import Testing

@Suite("使い方の記録のファイル", .serialized)
@MainActor
struct FileUsageStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hajime-usage-\(UUID().uuidString)/usage.json")
    }

    @Test("決まった回数ごとに，本人だけが読み書きできるファイルに書く")
    func savesWithPermission() throws {
        let url = temporaryURL()
        let store = FileUsageStore(fileURL: url, isEnabled: { true })
        for _ in 0..<(DefaultSettings.usageSaveInterval - 1) { store.record(.conversionOpened) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        store.record(.conversionOpened)
        #if !os(Windows)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        #endif
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
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = SystemCalendar.localTimeZone(at: Date())
        let date = try #require(gregorian.date(from: components))
        let calendar = SystemCalendar(clock: { date })
        #expect(calendar.now() == CalendarDate(year: 2026, month: 10, day: 31, weekday: 7, hour: 23, minute: 59))
        let tomorrow = calendar.day(offsetFromToday: 1)
        #expect((tomorrow.month, tomorrow.day, tomorrow.weekday) == (11, 1, 1))
    }

    @Test("渡した時間帯で日時を読む(UTC の 16:30 は日本時間では翌日の 1:30)")
    func timeZone() throws {
        let date = Date(timeIntervalSince1970: 1_793_118_600)  // 2026-10-27 16:30 UTC
        let tokyo = try #require(TimeZone(secondsFromGMT: 9 * 3600))
        let calendar = SystemCalendar(clock: { date }, timeZone: { _ in tokyo })
        #expect(calendar.now() == CalendarDate(year: 2026, month: 10, day: 28, weekday: 4, hour: 1, minute: 30))
        #expect(calendar.day(offsetFromToday: 0).day == 28)
    }

    @Test("端末の時間帯は，OS の時計の UTC との差に合う(Windows の Foundation のように GMT に落ちない)")
    func localTimeZone() {
        let now = Date()
        let zone = SystemCalendar.localTimeZone(at: now)
        #if os(Windows)
        var time = time_t(now.timeIntervalSince1970)
        var parts = tm()
        localtime_s(&parts, &time)
        #expect(zone.secondsFromGMT(for: now) == Int(_mkgmtime(&parts) - time))
        #else
        #expect(zone.secondsFromGMT(for: now) == TimeZone.current.secondsFromGMT(for: now))
        #endif
    }
}
