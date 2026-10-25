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

    /// 大きさの上限を確かめながら読む．上限より 1 バイト多くまでだけを読み，超えていれば断る．
    /// ファイルの属性の大きさで確かめると，シンボリックリンクではリンク自体の大きさが返り，上限をすり抜けるため
    static func read(from url: URL, maximumBytes: Int) throws -> Data {
        // FIFO などを開いて止まらないよう，待たない開き方で開き，ふつうのファイルだけを読む(ZenzaiModel と同じ)
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOCTTY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { throw NotRegularFile() }
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw TooLarge(maximumBytes: maximumBytes) }
        return data
    }

    struct NotRegularFile: Error, Equatable {}

    struct TooLarge: Error, Equatable {
        var maximumBytes: Int
    }

    /// 読めなかったファイルを脇に置き，置いた場所を返す．既定値で始めたあとで上書きして，利用者の設定を消さないため
    static func setAside(_ url: URL) -> URL? {
        let aside = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).unreadable-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: url, to: aside)
            return aside
        } catch {
            return nil
        }
    }
}
