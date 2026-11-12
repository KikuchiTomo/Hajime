import Foundation
import HajimeDomain
@testable import HajimeEngine
import Testing

/// 同梱の辞書と Zenzai のモデルを確かめる SHA-256(macOS は CryptoKit，Windows は OS の CNG)が，自前の SHA256Digest と同じ値になること
@Suite("ファイルの SHA-256")
struct FileDigestTests {
    private func bytes(_ count: Int) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: $0 &* 131 &+ count) }
    }

    @Test("中身から求めた値が自前の SHA-256 と同じになる", arguments: [0, 1, 55, 56, 63, 64, 65, 1000, (1 << 20) + 13])
    func data(count: Int) {
        let bytes = bytes(count)
        #expect(FileDigest.sha256(of: Data(bytes)) == SHA256Digest.hex(of: bytes))
    }

    @Test("ファイルを区切って読んで求めた値が自前の SHA-256 と同じになる", arguments: [0, 3, (1 << 20) - 1, 1 << 20, (3 << 20) + 7])
    func file(count: Int) throws {
        let bytes = bytes(count)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-digest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(bytes).write(to: url)
        let (handle, size) = try #require(FileDigest.openRegularFile(at: url))
        #expect(size == count)
        #expect(try FileDigest.sha256(of: handle, maximumBytes: count) == SHA256Digest.hex(of: bytes))
    }

    /// Windows の CI のログで CNG の速さを見るため．機械によって変わるので判定はしない
    @Test("速さを書き出す")
    func speed() {
        let data = Data(repeating: 0x5a, count: 64 << 20)
        let elapsed = ContinuousClock().measure { _ = FileDigest.sha256(of: data) }
        print("FileDigest の SHA-256: 64MB に \(elapsed)")
    }

    @Test("大きさの上限を超えたら読むのをやめる")
    func tooLarge() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-digest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(bytes(1000)).write(to: url)
        let (handle, _) = try #require(FileDigest.openRegularFile(at: url))
        #expect(throws: FileDigest.TooLarge.self) { try FileDigest.sha256(of: handle, maximumBytes: 999) }
    }
}

@Suite("並べた仕事")
struct ConcurrentWorkTests {
    @Test("渡した順に結果を返す")
    func keepsOrder() {
        let values = Array(0..<5000)
        #expect(ConcurrentWork.map(values) { $0 * 3 } == values.map { $0 * 3 })
        #expect(ConcurrentWork.map([Int]()) { $0 }.isEmpty)
    }
}

@Suite("起動のときに確かめるもの")
struct StartupResourcesTests {
    @Test("場所を渡さなかったものは確かめず，無いものは使わない")
    func missing() {
        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-none-\(UUID().uuidString)")
        let resources = StartupResources.verified(zenzai: nil, fastZenzai: nowhere.appendingPathComponent("model.gguf"), dictionary: nowhere)
        #expect(resources.zenzai == nil)
        #expect(resources.fastZenzai == .failure(.fileNotFound))
        #expect(resources.dictionary == .failure(.manifestNotFound))
    }
}
