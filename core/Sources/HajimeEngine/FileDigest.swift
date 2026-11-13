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
    /// 起動のたびに同梱の辞書と Zenzai モデル(合わせて 280MB ほど)を確かめるので，CPU の SHA の命令を使える OS の実装を使う
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
