import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
import HajimeDomain

/// 外から取得して置いたファイル(Zenzai のモデル・同梱の辞書)を，ふつうのファイルとして開いてハッシュを求める．
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
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        var hasher = SHA256Digest()
        hasher.update(data)
        return hasher.finalizeHex()
        #endif
    }

    /// 決まった大きさを超えたら読むのをやめる．開いたあとでファイルが伸びても，読み続けて止まらないようにする
    static func sha256(of handle: FileHandle, maximumBytes: Int) throws(TooLarge) -> String {
        #if canImport(CryptoKit)
        var hasher = SHA256()
        #else
        // CryptoKit の無い OS(Windows)では自前の SHA-256 で求める．値が同じことは SHA256DigestTests で確かめる
        var hasher = SHA256Digest()
        #endif
        var total = 0
        // 大きなファイルもあるので，一度に読まずに区切って読む
        while let chunk = try? handle.read(upToCount: min(1 << 20, maximumBytes + 1 - total)), !chunk.isEmpty {
            total += chunk.count
            guard total <= maximumBytes else { throw TooLarge(readBytes: total) }
            #if canImport(CryptoKit)
            hasher.update(data: chunk)
            #else
            hasher.update(chunk)
            #endif
        }
        #if canImport(CryptoKit)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        return hasher.finalizeHex()
        #endif
    }
}
