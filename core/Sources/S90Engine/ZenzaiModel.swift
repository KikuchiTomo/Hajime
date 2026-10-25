import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Zenzai(文脈を見るニューラルかな漢字変換)のモデルのファイル．
///
/// 外から取得するファイルなので，SHA-256 がリポジトリに書いた値と一致したものだけを使う(docs/dev/SECURITY-MODEL.md)．
/// 値を変えるときは docs/dev/adr/0006-zenzai.md の手順で，取得元と版を確かめてから書き換える．
public struct ZenzaiModel: Sendable, Equatable {
    public enum VerificationError: Error, Equatable {
        case fileNotFound
        case sizeMismatch(actual: Int)
        case hashMismatch
        case unsupportedPlatform
    }

    /// Miwa-Keita/zenz-v3.2-small-gguf(Apache-2.0)の ggml-model-Q5_K_M.gguf．
    /// Hugging Face のコミット c67e03e07d215c869f591b274c1631170d3e11fe
    public static let expectedSHA256 = "29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673"
    public static let expectedSize = 73_871_936
    public static let fileName = "zenz-v3.2-small-Q5_K_M.gguf"

    public let url: URL

    /// ファイルを確かめてから作る．大きさとハッシュのどちらかが違えば使わない
    public static func verified(at url: URL) throws(VerificationError) -> ZenzaiModel {
        try verified(at: url, expectedSize: expectedSize, expectedSHA256: expectedSHA256)
    }

    /// 確かめる値を渡せる形．テストで小さなファイルを使って確かめるため
    static func verified(at url: URL, expectedSize: Int, expectedSHA256: String) throws(VerificationError) -> ZenzaiModel {
        // 先に開いてから，開いたものがふつうのファイルかと大きさを確かめる．確かめてから開くまでのあいだに
        // FIFO や /dev/zero への差し替えが起きても止まらないようにするため．O_NONBLOCK で開くので，FIFO でも開く時点で止まらない
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else { throw .fileNotFound }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { throw .fileNotFound }
        let size = Int(status.st_size)
        guard size == expectedSize else { throw .sizeMismatch(actual: size) }
        guard try sha256(of: handle, maximumBytes: expectedSize) == expectedSHA256 else { throw .hashMismatch }
        return ZenzaiModel(url: url)
    }

    /// 決まった大きさを超えたら読むのをやめる．開いたあとでファイルが伸びても，読み続けて止まらないようにする
    static func sha256(of handle: FileHandle, maximumBytes: Int) throws(VerificationError) -> String {
        #if canImport(CryptoKit)
        var hasher = SHA256()
        var total = 0
        // 70MB ほどあるので，一度に読まずに区切って読む
        while let chunk = try? handle.read(upToCount: min(1 << 20, maximumBytes + 1 - total)), !chunk.isEmpty {
            total += chunk.count
            // 上限を超えたことだけが分かる．ファイルの本当の大きさは分からないので，読んだ量を入れる
            guard total <= maximumBytes else { throw .sizeMismatch(actual: total) }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        throw .unsupportedPlatform
        #endif
    }
}
