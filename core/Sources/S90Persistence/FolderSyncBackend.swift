import Foundation
import S90Application
import S90Domain

/// 利用者が選んだフォルダに同期のファイル(s90-sync.json)を置く(TODO 43)．
/// Dropbox・Google Drive・iCloud Drive のフォルダを選べば，それぞれのアプリが Mac のあいだで運ぶ．このアプリは通信しない
public struct FolderSyncBackend: SyncBackend {
    public static let fileName = "s90-sync.json"
    private let fileURL: URL

    public init(folder: URL) {
        self.fileURL = folder.appendingPathComponent(Self.fileName)
    }

    public func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try ProtectedFile.read(from: fileURL, maximumBytes: DefaultSettings.maximumSyncFileBytes)
    }

    public func write(_ data: Data) throws {
        guard data.count <= DefaultSettings.maximumSyncFileBytes else { throw ProtectedFile.TooLarge(maximumBytes: DefaultSettings.maximumSyncFileBytes) }
        try ProtectedFile.write(data, to: fileURL)
    }
}

/// この Mac の同期の設定(フォルダ・範囲・記録)を sync-state.json に保存する．同期のファイルには入れない
@MainActor
public final class FileSyncStateStore: SyncStateStoring {
    private let fileURL: URL
    public private(set) var state: SyncState

    /// 読めないときは同期しない状態で始める(記録を失っても，次の同期で同期のファイルから取り込み直せる)
    public init(fileURL: URL) {
        self.fileURL = fileURL
        let data = try? ProtectedFile.read(from: fileURL, maximumBytes: DefaultSettings.maximumSyncFileBytes)
        self.state = data.flatMap { try? SyncCoding.decoder.decode(SyncState.self, from: $0) } ?? SyncState()
    }

    public func save(_ state: SyncState) throws {
        try ProtectedFile.write(SyncCoding.encoder.encode(state), to: fileURL)
        self.state = state
    }
}
