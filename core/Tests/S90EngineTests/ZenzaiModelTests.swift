import Foundation
@testable import S90Engine
import Testing

/// Zenzai のモデルは外から取得するので，大きさとハッシュが合わないファイルを使わないことを確かめる
@Suite("Zenzai のモデルの確認")
struct ZenzaiModelTests {
    /// 「abc」の SHA-256
    private let abcSHA256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

    private func write(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("s90-zenzai-\(UUID().uuidString).gguf")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test("大きさとハッシュが合えば使う")
    func accepts() throws {
        let url = try write("abc")
        #expect(try ZenzaiModel.verified(at: url, expectedSize: 3, expectedSHA256: abcSHA256).url == url)
    }

    @Test("ファイルが無ければ使わない")
    func missing() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("s90-none-\(UUID().uuidString)")
        #expect(throws: ZenzaiModel.VerificationError.fileNotFound) {
            try ZenzaiModel.verified(at: url, expectedSize: 3, expectedSHA256: abcSHA256)
        }
    }

    @Test("大きさが違えば，ハッシュを計算する前に使わない")
    func wrongSize() throws {
        let url = try write("abcd")
        #expect(throws: ZenzaiModel.VerificationError.sizeMismatch(actual: 4)) {
            try ZenzaiModel.verified(at: url, expectedSize: 3, expectedSHA256: abcSHA256)
        }
    }

    @Test("大きさが同じでも中身が違えば使わない")
    func wrongHash() throws {
        let url = try write("abd")
        #expect(throws: ZenzaiModel.VerificationError.hashMismatch) {
            try ZenzaiModel.verified(at: url, expectedSize: 3, expectedSHA256: abcSHA256)
        }
    }
}
