import Foundation
@testable import HajimeEngine
import Testing

/// 同梱の辞書は外から取得するので，ファイルごとの SHA-256 の一覧と中身が合わない辞書を使わないことを確かめる
@Suite("同梱の辞書の確認")
struct BundledDictionaryTests {
    /// 「abc」の SHA-256
    private let abcSHA256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    /// louds/charID.chid(中身は abc)と，それを書いた一覧を持つ小さな辞書を作る．一覧の中身と，一覧の SHA-256 を返す
    private func makeDictionary(manifest: String? = nil) throws -> (directory: URL, manifestSHA256: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-dictionary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("louds"), withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: directory.appendingPathComponent("louds/charID.chid"))
        let text = manifest ?? "\(abcSHA256)  louds/charID.chid\n"
        let data = Data(text.utf8)
        try data.write(to: directory.appendingPathComponent(BundledDictionary.manifestName))
        return (directory, FileDigest.sha256(of: data))
    }

    @Test("一覧とファイルのハッシュが合えば使う")
    func accepts() throws {
        let (directory, manifestSHA256) = try makeDictionary()
        #expect(try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256).url == directory)
    }

    @Test("一覧が無ければ使わない")
    func missingManifest() throws {
        let (directory, manifestSHA256) = try makeDictionary()
        try FileManager.default.removeItem(at: directory.appendingPathComponent(BundledDictionary.manifestName))
        #expect(throws: BundledDictionary.VerificationError.manifestNotFound) {
            try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256)
        }
    }

    @Test("一覧の SHA-256 が合わなければ使わない")
    func manifestMismatch() throws {
        let (directory, _) = try makeDictionary()
        #expect(throws: BundledDictionary.VerificationError.manifestMismatch) {
            try BundledDictionary.verified(at: directory, expectedManifestSHA256: abcSHA256)
        }
    }

    @Test("一覧にあるファイルの中身が変わっていれば使わない")
    func fileMismatch() throws {
        let (directory, manifestSHA256) = try makeDictionary()
        try Data("abd".utf8).write(to: directory.appendingPathComponent("louds/charID.chid"))
        #expect(throws: BundledDictionary.VerificationError.hashMismatch) {
            try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256)
        }
    }

    @Test("一覧にあるファイルが無ければ使わない")
    func fileMissing() throws {
        let (directory, manifestSHA256) = try makeDictionary(manifest: "\(abcSHA256)  louds/charID.chid\n\(abcSHA256)  louds/none.louds\n")
        #expect(throws: BundledDictionary.VerificationError.fileNotFound) {
            try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256)
        }
    }

    @Test("エンジンが読むのに要るファイルが一覧に無ければ使わない")
    func requiredFileMissing() throws {
        let (directory, manifestSHA256) = try makeDictionary(manifest: "")
        #expect(throws: BundledDictionary.VerificationError.malformedManifest) {
            try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256)
        }
    }

    /// 本物の辞書(make test-zenzai が HAJIME_BUNDLED_DICTIONARY に場所を入れる)が確かめられ，起動を遅らせすぎないこと
    @Test("取得した本物の辞書を確かめられる", .enabled(if: ProcessInfo.processInfo.environment["HAJIME_BUNDLED_DICTIONARY"] != nil))
    func acceptsRealDictionary() throws {
        let path = try #require(ProcessInfo.processInfo.environment["HAJIME_BUNDLED_DICTIONARY"])
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var dictionary: BundledDictionary?
        let elapsed = try ContinuousClock().measure { dictionary = try BundledDictionary.verified(at: url) }
        #expect(dictionary?.url == url)
        print("同梱の辞書の確認にかかった時間: \(elapsed)")
        #expect(elapsed < .seconds(2))
    }

    @Test("ディレクトリの外を指すパスや形の正しくない行を受け付けない", arguments: [
        "/etc/passwd", "../outside", "louds/../../outside", "louds//charID.chid", "./louds/charID.chid", "louds\\charID.chid", "C:/outside",
    ])
    func rejectsUnsafePaths(path: String) {
        #expect(throws: BundledDictionary.VerificationError.malformedManifest) {
            try BundledDictionary.parse("\(abcSHA256)  \(path)\n")
        }
    }

    @Test("ハッシュの形が正しくない行を受け付けない", arguments: ["ABC", String(repeating: "g", count: 64), String(repeating: "A", count: 64)])
    func rejectsMalformedHashes(hash: String) {
        #expect(throws: BundledDictionary.VerificationError.malformedManifest) {
            try BundledDictionary.parse("\(hash)  louds/charID.chid\n")
        }
    }
}
