import Foundation
import HajimeApplication
import HajimeDomain

/// 使い方の記録(回数だけ)を JSON のファイルに保存する．ファイルは本人だけが読み書きでき，端末の外には出さない
@MainActor
public final class FileUsageStore: UsageRecording, UsageReading {
    private let fileURL: URL
    /// 記録するかは，記録するたびに設定の「使い方を記録する」(recordsUsage)で決める
    private let settings: any SettingsReading
    public private(set) var counts: UsageCounts
    private var unsavedEvents = 0

    public init(fileURL: URL, settings: any SettingsReading) {
        self.fileURL = fileURL
        self.settings = settings
        self.counts = (try? Self.load(from: fileURL)) ?? UsageCounts()
    }

    public func record(_ event: UsageEvent) {
        guard settings.current.recordsUsage else { return }
        counts.record(event)
        unsavedEvents += 1
        if unsavedEvents >= DefaultSettings.usageSaveInterval { flush() }
    }

    /// 数えた回数をファイルに書く．入力欄からフォーカスが外れたときなどに呼ぶ
    public func flush() {
        guard unsavedEvents > 0 else { return }
        unsavedEvents = 0
        try? save()
    }

    public func reset() {
        counts = UsageCounts()
        unsavedEvents = 0
        try? save()
    }

    private func save() throws {
        try ProtectedFile.write(JSONEncoder().encode(counts), to: fileURL)
    }

    private static func load(from url: URL) throws -> UsageCounts {
        try JSONDecoder().decode(UsageCounts.self, from: ProtectedFile.read(from: url, maximumBytes: DefaultSettings.maximumUsageFileBytes))
    }
}
