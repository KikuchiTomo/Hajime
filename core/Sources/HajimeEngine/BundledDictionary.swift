import Foundation
import HajimeDomain

/// アプリに入れるかな漢字変換の辞書(hajime-dictionary．azooKey の辞書に Mozc の語を足したもの)のディレクトリ．
///
/// 外から取得するファイルなので，辞書に入っているファイルごとの SHA-256 の一覧(SHA256SUMS)の SHA-256 をここに書き，
/// 一覧と，一覧にあるすべてのファイルが一致したものだけを使う(docs/dev/SECURITY-MODEL.md)．
/// 版を変えるときは tools/dictionary/fetch_dictionary.sh・fetch_dictionary.ps1 と一緒に書き換える．
/// 辞書の形は AzooKeyKanaKanjiConverter の版に合わせて作ってあるので，core/Package.swift の fork の revision を上げるときは作り直した版に上げる
public struct BundledDictionary: Sendable, Equatable {
    public enum VerificationError: Error, Equatable {
        /// 一覧が無いか，ふつうのファイルでない
        case manifestNotFound
        /// 一覧の SHA-256 が合わない
        case manifestMismatch
        /// 一覧の行の形が正しくない(ディレクトリの外を指すパスを含む)
        case malformedManifest
        /// 一覧にあるファイルが無いか，ふつうのファイルでない
        case fileNotFound
        /// 一覧にあるファイルが大きさの上限を超えた
        case fileTooLarge
        /// 一覧にあるファイルの SHA-256 が合わない
        case hashMismatch
    }

    /// https://github.com/KikuchiTomo/hajime-dictionary の v0.1.1
    public static let version = "0.1.1"
    public static let expectedManifestSHA256 = "8b73e404747c801017c9ca37219bb9ba97702939ef29822e704f741d2c827779"
    /// アプリの中で辞書を置くディレクトリの名前
    public static let directoryName = "Dictionary"
    static let manifestName = "SHA256SUMS"
    /// azooKey のエンジンが辞書として読むのに要るファイル．一覧にこれが無ければ辞書として使わない
    static let requiredFile = "louds/charID.chid"

    public let url: URL

    /// ディレクトリを確かめてから作る．一覧かファイルのどれかが合わなければ使わない
    public static func verified(at directory: URL) throws(VerificationError) -> BundledDictionary {
        try verified(at: directory, expectedManifestSHA256: expectedManifestSHA256)
    }

    /// 確かめる値を渡せる形．テストで小さな辞書を使って確かめるため
    static func verified(at directory: URL, expectedManifestSHA256: String) throws(VerificationError) -> BundledDictionary {
        let manifestURL = directory.appendingPathComponent(manifestName, isDirectory: false)
        guard let (handle, _) = FileDigest.openRegularFile(at: manifestURL) else { throw .manifestNotFound }
        // 一度だけ開いて読み，読んだ中身でハッシュを確かめてから解釈する(確かめてから読み直すあいだに差し替えられないように)
        guard let data = try? FileDigest.read(handle, maximumBytes: DefaultSettings.maximumBundledDictionaryManifestBytes),
            FileDigest.sha256(of: data) == expectedManifestSHA256 else { throw .manifestMismatch }
        guard let text = String(data: data, encoding: .utf8) else { throw .malformedManifest }
        let entries = try parse(text)
        guard entries.contains(where: { $0.path == requiredFile }) else { throw .malformedManifest }
        for entry in entries {
            let url = entry.path.split(separator: "/").reduce(directory) { $0.appendingPathComponent(String($1)) }
            guard let (file, _) = FileDigest.openRegularFile(at: url) else { throw .fileNotFound }
            let digest: String
            do {
                digest = try FileDigest.sha256(of: file, maximumBytes: DefaultSettings.maximumBundledDictionaryFileBytes)
            } catch {
                throw .fileTooLarge
            }
            guard digest == entry.sha256 else { throw .hashMismatch }
        }
        return BundledDictionary(url: directory)
    }

    /// 一覧の 1 行は「SHA-256(小文字の 16 進 64 桁)<空白 2 つ>ディレクトリからの相対パス(区切りは /)」
    static func parse(_ text: String) throws(VerificationError) -> [(sha256: String, path: String)] {
        var entries: [(sha256: String, path: String)] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[1].hasPrefix(" ") else { throw .malformedManifest }
            let hash = String(parts[0])
            let path = String(parts[1].dropFirst())
            guard hash.count == 64, hash.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else {
                throw .malformedManifest
            }
            // ディレクトリの外を指すパス(絶対パス・..・\ を含むもの)は受け付けない
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.isEmpty, !path.contains("\\"), !path.contains(":"),
                components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw .malformedManifest }
            entries.append((hash, path))
        }
        return entries
    }
}
