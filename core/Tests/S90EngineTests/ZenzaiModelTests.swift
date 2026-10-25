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

    @Test("シンボリックリンクはたどった先がふつうのファイルなら使う")
    func symlinkToFile() throws {
        let target = try write("abc")
        let link = FileManager.default.temporaryDirectory.appendingPathComponent("s90-zenzai-link-\(UUID().uuidString).gguf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        defer { try? FileManager.default.removeItem(at: link) }
        #expect(try ZenzaiModel.verified(at: link, expectedSize: 3, expectedSHA256: abcSHA256).url == link)
    }

    @Test("リンクの先が /dev/zero やディレクトリなら使わない(読み続けて止まらない)")
    func symlinkToSpecialFile() throws {
        for destination in [URL(fileURLWithPath: "/dev/zero"), FileManager.default.temporaryDirectory] {
            let link = FileManager.default.temporaryDirectory.appendingPathComponent("s90-zenzai-link-\(UUID().uuidString).gguf")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
            defer { try? FileManager.default.removeItem(at: link) }
            #expect(throws: ZenzaiModel.VerificationError.fileNotFound) {
                try ZenzaiModel.verified(at: link, expectedSize: 3, expectedSHA256: abcSHA256)
            }
        }
    }

    @Test("ハッシュは決まった大きさを超えたら読むのをやめる")
    func stopsReadingAtLimit() throws {
        let url = try write("abcdef")
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        #expect(throws: ZenzaiModel.VerificationError.sizeMismatch(actual: 4)) {
            try ZenzaiModel.sha256(of: handle, maximumBytes: 3)
        }
    }

    @Test("FIFO は開く時点で止まらずに使わない")
    func fifo() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("s90-zenzai-fifo-\(UUID().uuidString)")
        #expect(mkfifo(url.path, 0o600) == 0)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: ZenzaiModel.VerificationError.fileNotFound) {
            try ZenzaiModel.verified(at: url, expectedSize: 3, expectedSHA256: abcSHA256)
        }
    }
}
