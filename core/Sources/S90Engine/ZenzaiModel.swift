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
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = (attributes[.size] as? NSNumber)?.intValue else {
            throw .fileNotFound
        }
        guard size == expectedSize else { throw .sizeMismatch(actual: size) }
        guard try sha256(of: url) == expectedSHA256 else { throw .hashMismatch }
        return ZenzaiModel(url: url)
    }

    private static func sha256(of url: URL) throws(VerificationError) -> String {
        #if canImport(CryptoKit)
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw .fileNotFound }
        defer { try? handle.close() }
        var hasher = SHA256()
        // 70MB ほどあるので，一度に読まずに区切って読む
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #else
        throw .unsupportedPlatform
        #endif
    }
}
