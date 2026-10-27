import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
import S90Domain

/// Zenzai(文脈を見るニューラルかな漢字変換)のモデルのファイル．
///
/// 外から取得するファイルなので，SHA-256 がリポジトリに書いた値と一致したものだけを使う(docs/dev/SECURITY-MODEL.md)．
/// 値を変えるときは docs/dev/adr/0006-zenzai.md の手順で，取得元とバージョンを確かめてから書き換える．
public struct ZenzaiModel: Sendable, Equatable {
    public enum VerificationError: Error, Equatable {
        case fileNotFound
        case sizeMismatch(actual: Int)
        case hashMismatch
    }

    /// Miwa-Keita/zenz-v3.2-small-gguf(Apache-2.0)の ggml-model-Q5_K_M.gguf．
    /// Hugging Face のコミット c67e03e07d215c869f591b274c1631170d3e11fe
    public static let expectedSHA256 = "29c223d4c23327b80fd13ebb5ab2555057a46317997d5da391584ffbef0db673"
    public static let expectedSize = 73_871_936
    public static let fileName = "zenz-v3.2-small-Q5_K_M.gguf"

    public let url: URL

    /// 表示の変換とは別の推論の文脈で Zenzai を使うための場所(打ち間違いの訂正 ZenzaiTypoService が使う)．
    ///
    /// azooKey は Zenzai を場所(URL の文字列)ごとに 1 つ共有し，推論を 1 本ずつ流す．訂正が表示の変換と同じ文脈を使うと，
    /// 訂正を求めているあいだ打鍵の変換が待たされる(CPU で推論する Windows では 1〜2 秒止まる)．
    /// フラグメントを付けた URL は別の文脈になる．読むファイル(path)は同じなので，モデルの重みは共有したまま
    public var separateContextURL: URL {
        URL(string: url.absoluteString + "#" + Self.separateContextFragment) ?? url
    }

    static let separateContextFragment = "typo"

    /// ファイルを確かめてから作る．大きさとハッシュのどちらかが違えば使わない
    public static func verified(at url: URL) throws(VerificationError) -> ZenzaiModel {
        try verified(at: url, expectedSize: expectedSize, expectedSHA256: expectedSHA256)
    }

    /// 確かめる値を渡せる形．テストで小さなファイルを使って確かめるため
    static func verified(at url: URL, expectedSize: Int, expectedSHA256: String) throws(VerificationError) -> ZenzaiModel {
        #if os(Windows)
        // Windows には FIFO や /dev/zero のような，開くと止まる・終わらないファイルが無い．
        // ふつうのファイルかと大きさを確かめてから開き，読む量は大きさの上限で止める
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeRegular,
            let handle = try? FileHandle(forReadingFrom: url) else { throw .fileNotFound }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? -1
        guard size == expectedSize else { throw .sizeMismatch(actual: size) }
        guard try sha256(of: handle, maximumBytes: expectedSize) == expectedSHA256 else { throw .hashMismatch }
        return ZenzaiModel(url: url)
        #else
        // 先に開いてから，開いたものがふつうのファイルかと大きさを確かめる．確かめてから開くまでのあいだに
        // FIFO や /dev/zero への差し替えが起きても止まらないようにするため．O_NONBLOCK で開くので，FIFO でも開く時点で止まらない
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOCTTY)
        guard descriptor >= 0 else { throw .fileNotFound }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { throw .fileNotFound }
        let size = Int(status.st_size)
        guard size == expectedSize else { throw .sizeMismatch(actual: size) }
        guard try sha256(of: handle, maximumBytes: expectedSize) == expectedSHA256 else { throw .hashMismatch }
        return ZenzaiModel(url: url)
        #endif
    }

    /// 決まった大きさを超えたら読むのをやめる．開いたあとでファイルが伸びても，読み続けて止まらないようにする
    static func sha256(of handle: FileHandle, maximumBytes: Int) throws(VerificationError) -> String {
        #if canImport(CryptoKit)
        var hasher = SHA256()
        #else
        // CryptoKit の無い OS(Windows)では自前の SHA-256 で求める．値が同じことは SHA256DigestTests で確かめる
        var hasher = SHA256Digest()
        #endif
        var total = 0
        // 70MB ほどあるので，一度に読まずに区切って読む
        while let chunk = try? handle.read(upToCount: min(1 << 20, maximumBytes + 1 - total)), !chunk.isEmpty {
            total += chunk.count
            // 上限を超えたことだけが分かる．ファイルの本当の大きさは分からないので，読んだ量を入れる
            guard total <= maximumBytes else { throw .sizeMismatch(actual: total) }
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
