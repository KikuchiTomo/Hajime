#if canImport(CryptoKit)
import CryptoKit
import Foundation
import S90Domain

/// 取り込んだ辞書の索引のファイルを，同期のフォルダの s90-dictionaries/ と突き合わせる(R-15・R-16)．
///
/// 設定の同期で辞書の一覧(id と revision)がそろったあとに呼ぶ．同期のフォルダには「<id>-<revision>.tsv」の名前で置く．
/// - この Mac の索引が一覧の revision と同じで，フォルダに無ければ書き出す
/// - この Mac に無いか古く，フォルダにあれば読み込み，SHA-256 が revision と合うときだけ入れ替える
/// - フォルダにある，一覧のどれにも当たらない索引は消す(取り込み直す前のバージョンと，消した辞書)
///
/// 索引は数百 MB になりうるので，メモリに読み込まずに少しずつ写し，ハッシュも少しずつ求める．メインスレッドの外で呼ぶ
public struct DictionaryFileSync: Sendable {
    public static let folderName = "s90-dictionaries"

    public struct Outcome: Sendable, Equatable {
        /// 同期のフォルダから読み込んで入れ替えた辞書の id．索引を開き直す
        public var installed: [String] = []
        /// 書き出した数
        public var uploaded = 0
        /// フォルダから消した数
        public var removed = 0
        /// revision の無い辞書(同期を入れる前に取り込んだもの)の，この Mac の索引から求めた revision．設定に書き戻す
        public var computedRevisions: [String: String] = [:]
        /// 運べなかった辞書の id(フォルダの索引が壊れている，大きすぎるなど)．ほかの辞書は続けて運ぶ
        public var failed: [String] = []
    }

    private let localDirectory: URL
    private let remoteDirectory: URL

    /// localDirectory はこの Mac の索引の置き場所(Application Support の dictionaries/)，syncFolder は利用者が選んだ同期のフォルダ
    public init(localDirectory: URL, syncFolder: URL) {
        self.localDirectory = localDirectory
        self.remoteDirectory = syncFolder.appendingPathComponent(Self.folderName, isDirectory: true)
    }

    public func sync(_ dictionaries: [ImportedDictionary]) throws -> Outcome {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: remoteDirectory, withIntermediateDirectories: true)
        var outcome = Outcome()
        var expected = Set<String>()
        for dictionary in dictionaries where dictionary.hasValidIdentity {
            let local = localDirectory.appendingPathComponent(dictionary.indexFileName)
            guard let revision = dictionary.revision else {
                // バージョンの無い辞書は，この Mac に索引があればバージョンを求めて設定に書き戻す．書き出すのは次の同期で
                if let computed = try? Self.sha256(of: local) { outcome.computedRevisions[dictionary.id] = computed }
                continue
            }
            let name = Self.remoteFileName(id: dictionary.id, revision: revision)
            expected.insert(name)
            let remote = remoteDirectory.appendingPathComponent(name)
            let localRevision = try? Self.sha256(of: local)
            do {
                if localRevision == revision {
                    if !fileManager.fileExists(atPath: remote.path) {
                        try Self.copy(from: local, to: remote, expectedRevision: revision)
                        outcome.uploaded += 1
                    }
                } else if fileManager.fileExists(atPath: remote.path) {
                    try fileManager.createDirectory(at: localDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    try Self.copy(from: remote, to: local, expectedRevision: revision)
                    outcome.installed.append(dictionary.id)
                }
            } catch {
                outcome.failed.append(dictionary.id)
            }
        }
        // 一覧に無い索引を消す．この形の名前のファイルだけを消し，利用者が置いたほかのファイルには触れない
        for name in (try? fileManager.contentsOfDirectory(atPath: remoteDirectory.path)) ?? [] where Self.isIndexFileName(name) && !expected.contains(name) {
            try? fileManager.removeItem(at: remoteDirectory.appendingPathComponent(name))
            outcome.removed += 1
        }
        return outcome
    }

    static func remoteFileName(id: String, revision: String) -> String { "\(id)-\(revision).tsv" }

    /// 「<UUID>-<64 桁の 16 進>.tsv」か
    static func isIndexFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".tsv") else { return false }
        let stem = name.dropLast(4)
        guard stem.count == 36 + 1 + 64 else { return false }
        let id = String(stem.prefix(36))
        let revision = String(stem.suffix(64))
        return stem[stem.index(stem.startIndex, offsetBy: 36)] == "-"
            && ImportedDictionary(id: id, name: "", wordCount: 0, revision: revision).hasValidIdentity
    }

    /// 索引のファイルの SHA-256(16 進の小文字)．上限より大きいファイルとふつうのファイルでないものは断る
    public static func sha256(of url: URL) throws -> String {
        let handle = try openRegularFile(url)
        var hasher = SHA256()
        var total = 0
        while let chunk = try handle.read(upToCount: DefaultSettings.syncCopyChunkBytes), !chunk.isEmpty {
            total += chunk.count
            guard total <= DefaultSettings.maximumSyncedDictionaryBytes else {
                throw ProtectedFile.TooLarge(maximumBytes: DefaultSettings.maximumSyncedDictionaryBytes)
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// 少しずつ一時ファイルに写し，写した中身の SHA-256 が expectedRevision と合えば置き換える．
    /// 合わなければ(運ぶ途中で壊れた，書き換えられた)一時ファイルを消して断る
    private static func copy(from source: URL, to destination: URL, expectedRevision: String) throws {
        let input = try openRegularFile(source)
        let directory = destination.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? output.close() }
            var hasher = SHA256()
            var total = 0
            while let chunk = try input.read(upToCount: DefaultSettings.syncCopyChunkBytes), !chunk.isEmpty {
                total += chunk.count
                guard total <= DefaultSettings.maximumSyncedDictionaryBytes else {
                    throw ProtectedFile.TooLarge(maximumBytes: DefaultSettings.maximumSyncedDictionaryBytes)
                }
                hasher.update(data: chunk)
                try output.write(contentsOf: chunk)
            }
            guard hasher.finalize().map({ String(format: "%02x", $0) }).joined() == expectedRevision else { throw RevisionMismatch() }
            try output.close()
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// FIFO などを開いて止まらないよう，待たない開き方で開き，ふつうのファイルだけを読む(ProtectedFile と同じ)
    private static func openRegularFile(_ url: URL) throws -> FileHandle {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOCTTY)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { throw ProtectedFile.NotRegularFile() }
        return handle
    }

    /// 写した中身の SHA-256 が一覧の revision と合わない
    public struct RevisionMismatch: Error, Equatable {}
}
#endif
