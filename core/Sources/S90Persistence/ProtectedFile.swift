import Foundation

/// 本人だけが読み書きできるファイルの読み書き(docs/dev/SECURITY-MODEL.md)．設定と使い方の記録で共有する
enum ProtectedFile {
    /// 権限(0600)を付けた一時ファイルに書いてから置き換える．途中で落ちても前の中身が壊れず，
    /// 作ってから権限を変えるあいだにほかのユーザーに読まれることもない．置き換えに失敗したら一時ファイルを消す
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// 大きさの上限を確かめてから読む
    static func read(from url: URL, maximumBytes: Int) throws -> Data {
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        return try Data(contentsOf: url)
    }

    /// 読めなかったファイルを脇に置く．既定値で始めたあとで上書きして，利用者の設定を消さないため
    static func setAside(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let aside = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).unreadable-\(UUID().uuidString)")
        try? FileManager.default.moveItem(at: url, to: aside)
    }
}
