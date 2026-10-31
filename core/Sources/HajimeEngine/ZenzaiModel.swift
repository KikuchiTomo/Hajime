import Foundation
import HajimeDomain

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
        guard let (handle, size) = FileDigest.openRegularFile(at: url) else { throw .fileNotFound }
        guard size == expectedSize else { throw .sizeMismatch(actual: size) }
        guard try sha256(of: handle, maximumBytes: expectedSize) == expectedSHA256 else { throw .hashMismatch }
        return ZenzaiModel(url: url)
    }

    /// 決まった大きさを超えたら読むのをやめる(FileDigest.sha256)．超えたときは読んだ量を大きさとして返す
    static func sha256(of handle: FileHandle, maximumBytes: Int) throws(VerificationError) -> String {
        do {
            return try FileDigest.sha256(of: handle, maximumBytes: maximumBytes)
        } catch {
            throw .sizeMismatch(actual: error.readBytes)
        }
    }
}
