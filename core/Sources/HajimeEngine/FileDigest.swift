import Foundation
#if canImport(CryptoKit)
import CryptoKit
#elseif os(Windows)
import CWindowsHash
#endif
import HajimeDomain

/// 外から取得して置いたファイル(Zenzai モデル・同梱の辞書)を，ふつうのファイルとして開いてハッシュを求める．
///
/// 開いた時点で止まるファイル(FIFO)や終わらないファイル(/dev/zero)に差し替えられても止まらないよう，
/// 開き方と読む量の上限をここにまとめる(docs/dev/SECURITY-MODEL.md)
enum FileDigest {
    /// 決めた大きさの上限を超えて読めた．読んだ量だけが分かる(ファイルの本当の大きさは分からない)
    struct TooLarge: Error, Equatable {
        let readBytes: Int
    }

    /// ふつうのファイルとして開き，開いたものの大きさを返す．ふつうのファイルでなければ nil
    static func openRegularFile(at url: URL) -> (handle: FileHandle, size: Int)? {
        #if os(Windows)
        // Windows には FIFO や /dev/zero のような，開くと止まる・終わらないファイルが無い．
        // ふつうのファイルかと大きさを確かめてから開き，読む量は大きさの上限で止める
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        return (handle, (attributes[.size] as? NSNumber)?.intValue ?? -1)
        #else
        // 先に開いてから，開いたものがふつうのファイルかと大きさを確かめる．確かめてから開くまでのあいだに
        // FIFO や /dev/zero への差し替えが起きても止まらないようにするため．O_NONBLOCK で開くので，FIFO でも開く時点で止まらない
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOCTTY)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { return nil }
        return (handle, Int(status.st_size))
        #endif
    }

    /// 中身を読まずに，ふつうのファイルの大きさ・更新日時・ファイル ID を得る．前回確かめたファイルと同じかを見分けるため(ADR 0017)．
    /// 無いか，ふつうのファイルでなければ nil
    static func stamp(at url: URL) -> FileStamp? {
        #if os(Windows)
        guard let path = url.withUnsafeFileSystemRepresentation({ $0.map { String(cString: $0) } }) else { return nil }
        var stamp = hajime_file_stamp()
        guard path.withCString(encodedAs: UTF16.self, { hajime_file_stamp_of($0, &stamp) }) == 0 else { return nil }
        return FileStamp(size: Int64(bitPattern: stamp.size), modified: stamp.modified, volume: stamp.volume, file: stamp.file)
        #else
        var status = stat()
        guard stat(url.path, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { return nil }
        #if canImport(Darwin)
        let modified = Int64(status.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(status.st_mtimespec.tv_nsec)
        #else
        let modified = Int64(status.st_mtim.tv_sec) * 1_000_000_000 + Int64(status.st_mtim.tv_nsec)
        #endif
        return FileStamp(size: Int64(status.st_size), modified: modified, volume: UInt64(truncatingIfNeeded: status.st_dev),
                         file: UInt64(truncatingIfNeeded: status.st_ino))
        #endif
    }

    /// directory の中の paths(区切りは /)のファイルの属性を，渡した順に返す．無いかふつうのファイルでなければ nil．
    /// Windows はファイルごとに開くと数千のファイル(同梱の辞書)で数百ミリ秒かかるので，ディレクトリごとに一度だけ読む
    static func stamps(of paths: [String], in directory: URL) -> [FileStamp?] {
        #if os(Windows)
        var listed: [String: [String: FileStamp]] = [:]
        return paths.map { path in
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            let parent = parts.dropLast().joined(separator: "/")
            if listed[parent] == nil {
                let url = parts.dropLast().reduce(directory) { $0.appendingPathComponent(String($1), isDirectory: true) }
                listed[parent] = stamps(inDirectory: url) ?? [:]
            }
            return parts.last.flatMap { listed[parent]?[String($0)] }
        }
        #else
        return ConcurrentWork.map(paths) { path in stamp(at: path.split(separator: "/").reduce(directory) { $0.appendingPathComponent(String($1)) }) }
        #endif
    }

    #if os(Windows)
    /// ディレクトリのすぐ下のふつうのファイルの属性を名前ごとに返す．読めなければ nil
    private static func stamps(inDirectory url: URL) -> [String: FileStamp]? {
        guard let path = url.withUnsafeFileSystemRepresentation({ $0.map { String(cString: $0) } }) else { return nil }
        let found = DirectoryStamps()
        let context = Unmanaged.passUnretained(found).toOpaque()
        let result = withExtendedLifetime(found) {
            path.withCString(encodedAs: UTF16.self) { directory in
                hajime_directory_stamps(directory, context) { context, name, length, stamp in
                    guard let context, let name, let stamp else { return }
                    let found = Unmanaged<DirectoryStamps>.fromOpaque(context).takeUnretainedValue()
                    let text = String(decoding: UnsafeBufferPointer(start: name, count: Int(length)), as: UTF16.self)
                    found.values[text] = FileStamp(size: Int64(bitPattern: stamp.pointee.size), modified: stamp.pointee.modified,
                                                   volume: stamp.pointee.volume, file: stamp.pointee.file)
                }
            }
        }
        return result == 0 ? found.values : nil
    }

    /// C の口から呼ばれる visitor が見つけたファイルをためる入れ物(呼ぶスレッドの中だけで使う)
    private final class DirectoryStamps {
        var values: [String: FileStamp] = [:]
    }
    #endif

    /// 中身をすべて読む．決まった大きさを超えたら読むのをやめる
    static func read(_ handle: FileHandle, maximumBytes: Int) throws(TooLarge) -> Data {
        var data = Data()
        while let chunk = try? handle.read(upToCount: min(1 << 20, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            data.append(chunk)
            guard data.count <= maximumBytes else { throw TooLarge(readBytes: data.count) }
        }
        return data
    }

    /// 読み終えた中身の SHA-256(小文字の 16 進)
    static func sha256(of data: Data) -> String {
        var hasher = Hasher()
        hasher.update(data)
        return hasher.finalizeHex()
    }

    /// 決まった大きさを超えたら読むのをやめる．開いたあとでファイルが伸びても，読み続けて止まらないようにする
    static func sha256(of handle: FileHandle, maximumBytes: Int) throws(TooLarge) -> String {
        var hasher = Hasher()
        var total = 0
        // 大きなファイルもあるので，一度に読まずに区切って読む
        while let chunk = try? handle.read(upToCount: min(1 << 20, maximumBytes + 1 - total)), !chunk.isEmpty {
            total += chunk.count
            guard total <= maximumBytes else { throw TooLarge(readBytes: total) }
            hasher.update(chunk)
        }
        return hasher.finalizeHex()
    }

    /// その OS で速い SHA-256．macOS は CryptoKit，Windows は OS の CNG(開けなければ自前の SHA256Digest)，ほかは自前の SHA256Digest．
    /// 同梱の辞書とモデル(合わせて 480MB ほど)を確かめる(初めての起動と，ファイルかアプリが変わったあと．ADR 0017)ので，CPU の SHA の命令を使える OS の実装を使う
    private struct Hasher {
        #if canImport(CryptoKit)
        private var digest = SHA256()

        mutating func update(_ data: Data) {
            digest.update(data: data)
        }

        func finalizeHex() -> String {
            HajimeDomain.SHA256Digest.lowercaseHex(digest.finalize())
        }
        #elseif os(Windows)
        private let system = WindowsSHA256()
        private var portable = SHA256Digest()

        mutating func update(_ data: Data) {
            if let system {
                system.update(data)
            } else {
                portable.update(data)
            }
        }

        mutating func finalizeHex() -> String {
            system?.finalizeHex() ?? portable.finalizeHex()
        }
        #else
        private var digest = SHA256Digest()

        mutating func update(_ data: Data) {
            digest.update(data)
        }

        mutating func finalizeHex() -> String {
            digest.finalizeHex()
        }
        #endif
    }

    #if os(Windows)
    /// Windows の CNG(BCrypt)で求める SHA-256．CNG を開けなければ作れない(nil)ので，呼ぶ側は自前の SHA256Digest で求める．
    /// 途中で CNG が失敗したら空の文字列を返す．どのハッシュとも一致しないので，確かめていないファイルを使わない側に倒れる
    private final class WindowsSHA256 {
        private var state: OpaquePointer?
        private var failed = false

        init?() {
            guard let state = hajime_sha256_begin() else { return nil }
            self.state = state
        }

        deinit {
            if let state { hajime_sha256_discard(state) }
        }

        func update(_ data: Data) {
            guard let state, !failed else { return }
            let result = data.withUnsafeBytes { bytes in
                hajime_sha256_update(state, bytes.baseAddress?.assumingMemoryBound(to: UInt8.self), bytes.count)
            }
            if result != 0 { failed = true }
        }

        func finalizeHex() -> String {
            guard let state else { return "" }
            self.state = nil
            var digest = [UInt8](repeating: 0, count: 32)
            let result = digest.withUnsafeMutableBufferPointer { hajime_sha256_finish(state, $0.baseAddress) }
            return result == 0 && !failed ? HajimeDomain.SHA256Digest.lowercaseHex(digest) : ""
        }
    }
    #endif
}
