import Foundation
import S90Application
import S90Domain

/// 設定を JSON のファイルに保存する．ファイルは本人だけが読み書きできる権限で作る(docs/dev/SECURITY-MODEL.md)．
@MainActor
public final class FileSettingsStore: SettingsStoring {
    public enum StoreError: Error, Equatable {
        case fileTooLarge(bytes: Int)
    }

    private let fileURL: URL
    public private(set) var current: Settings

    /// 読めないファイル・壊れたファイルのときは既定値で始める．入力を止めないため
    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.current = (try? Self.load(from: fileURL)) ?? DefaultSettings.settings
    }

    public func update(_ change: (inout Settings) -> Void) throws {
        var next = current
        change(&next)
        try save(next)
        current = next
    }

    private func save(_ settings: Settings) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        // 権限を付けた一時ファイルに書いてから置き換える．途中で落ちても設定が壊れず，
        // 作ってから権限を変えるあいだにほかのユーザーに読まれることもない
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

    private static func load(from url: URL) throws -> Settings {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size <= DefaultSettings.maximumSettingsFileBytes else {
            throw StoreError.fileTooLarge(bytes: size)
        }
        return try JSONDecoder().decode(Settings.self, from: Data(contentsOf: url))
    }
}
