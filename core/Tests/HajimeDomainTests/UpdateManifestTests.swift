import Foundation
import Testing
@testable import HajimeDomain

@Suite("R-19: 更新の確認で読む最新のバージョンの知らせ")
struct UpdateManifestTests {
    private static let digest = String(repeating: "ab", count: 32)
    private static let base = "https://haji.men/download/"

    private static func json(version: String = "0.2.7", macos: String = "v0.2.7/Hajime-0.2.7.pkg", sha256: String = digest,
                             releases: String = """
                             [{"version":"0.2.7","date":"2026-11-11","notes":"7"},{"version":"0.2.5","date":"2026-11-04","notes":"5"},
                              {"version":"0.2.6","date":"2026-11-07","notes":"6"},{"version":"x","date":"","notes":"?"}]
                             """) -> Data {
        Data("""
        {"version":"\(version)","files":{"macos":"\(macos)","windows":"v0.2.7/Hajime-0.2.7.msi"},
         "sha256":{"macos":"\(sha256)","windows":"\(digest)"},"releases":\(releases)}
        """.utf8)
    }

    @Test("バージョンを数として比べる")
    func comparesVersions() {
        #expect(ReleaseVersion("0.2.10")! > ReleaseVersion("0.2.9")!)
        #expect(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!)
        #expect(ReleaseVersion("0.2.7") == ReleaseVersion(major: 0, minor: 2, patch: 7))
        #expect(ReleaseVersion("0.2.7")?.description == "0.2.7")
    }

    @Test("X.Y.Z の形でないバージョンは読まない", arguments: ["v0.2.7", "0.2", "0.2.7.1", "0.2.7-beta", "0..7", "", "0.2.x", "٠.٢.٧"])
    func rejectsMalformedVersions(_ text: String) {
        #expect(ReleaseVersion(text) == nil)
    }

    @Test("配布物の URL と SHA-256 を読む")
    func readsPackage() throws {
        let manifest = try UpdateManifest.decode(Self.json())
        #expect(manifest.version == ReleaseVersion("0.2.7"))
        let package = try #require(manifest.package(for: .macos, baseURL: Self.base))
        #expect(package.url.absoluteString == "https://haji.men/download/v0.2.7/Hajime-0.2.7.pkg")
        #expect(package.fileName == "Hajime-0.2.7.pkg")
        #expect(package.sha256 == Self.digest)
        #expect(manifest.package(for: .windows, baseURL: Self.base)?.fileName == "Hajime-0.2.7.msi")
    }

    @Test("決めた形でない配布物の場所は使わない",
          arguments: ["../Hajime.pkg", "v0.2.7/../../x.pkg", "https://example.com/Hajime.pkg", "v0.2.7/.hidden", "v0.2.7/a/b.pkg",
                      "0.2.7/Hajime.pkg", "v0.2/Hajime.pkg", "v0.2.7/", "v0.2.7/Hajime 0.2.7.pkg", "v0.2.7/Hajime%2F.pkg"])
    func rejectsUnexpectedPaths(_ path: String) throws {
        let manifest = try UpdateManifest.decode(Self.json(macos: path))
        #expect(manifest.package(for: .macos, baseURL: Self.base) == nil)
    }

    @Test("16 進 64 桁でない SHA-256 は使わない", arguments: ["", "abc", String(repeating: "g", count: 64), String(repeating: "a", count: 65)])
    func rejectsMalformedDigests(_ digest: String) throws {
        let manifest = try UpdateManifest.decode(Self.json(sha256: digest))
        #expect(manifest.package(for: .macos, baseURL: Self.base) == nil)
    }

    @Test("https でない置き場所からは取らない")
    func requiresHTTPSBase() throws {
        let manifest = try UpdateManifest.decode(Self.json())
        #expect(manifest.package(for: .macos, baseURL: "http://haji.men/download/") == nil)
    }

    @Test("今のバージョンより新しい変更点だけを新しい順に出し，読めない節は飛ばす")
    func selectsNewerNotes() throws {
        let manifest = try UpdateManifest.decode(Self.json())
        #expect(manifest.notes(newerThan: ReleaseVersion("0.2.5")!).map(\.notes) == ["7", "6"])
        #expect(manifest.notes(newerThan: ReleaseVersion("0.2.7")!).isEmpty)
        #expect(manifest.releases.count == 3)
    }

    @Test("変更点が無くても読める")
    func readsWithoutReleases() throws {
        let data = Data(#"{"version":"0.2.7","files":{},"sha256":{}}"#.utf8)
        let manifest = try UpdateManifest.decode(data)
        #expect(manifest.releases.isEmpty)
        #expect(manifest.package(for: .macos, baseURL: Self.base) == nil)
    }

    @Test("形の違う知らせと大きすぎる知らせは読まない")
    func rejectsUnreadable() {
        #expect(throws: UpdateManifestError.unreadable) { try UpdateManifest.decode(Data("{}".utf8)) }
        #expect(throws: UpdateManifestError.unreadable) { try UpdateManifest.decode(Self.json(version: "latest")) }
        let large = Data(count: DefaultSettings.maximumUpdateManifestBytes + 1)
        #expect(throws: UpdateManifestError.tooLarge) { try UpdateManifest.decode(large) }
    }
}
