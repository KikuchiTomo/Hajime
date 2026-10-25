import Foundation
import S90Application
import S90Domain

/// 使い方の記録(回数だけ)を JSON のファイルに保存する．ファイルは本人だけが読み書きでき，端末の外には出さない
@MainActor
public final class FileUsageStore: UsageRecording {
    private let fileURL: URL
    private let isEnabled: () -> Bool
    public private(set) var counts: UsageCounts
    private var unsavedEvents = 0

    /// - Parameter isEnabled: 記録するか．設定の「使い方を記録する」を読む
    public init(fileURL: URL, isEnabled: @escaping () -> Bool) {
        self.fileURL = fileURL
        self.isEnabled = isEnabled
        self.counts = (try? Self.load(from: fileURL)) ?? UsageCounts()
    }

    public func record(_ event: UsageEvent) {
        guard isEnabled() else { return }
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
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(counts)
        let temporary = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: fileURL)
        }
    }

    private static func load(from url: URL) throws -> UsageCounts {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= DefaultSettings.maximumSettingsFileBytes else { throw CocoaError(.fileReadTooLarge) }
        return try JSONDecoder().decode(UsageCounts.self, from: Data(contentsOf: url))
    }
}
