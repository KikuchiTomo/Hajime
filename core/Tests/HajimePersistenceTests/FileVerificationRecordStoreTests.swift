import Foundation
import HajimeDomain
@testable import HajimePersistence
import Testing

/// 起動のときに確かめた結果の記録(ADR 0017)のファイル．読めない記録は無かったものとし，呼ぶ側にすべて確かめ直させる
@Suite("確かめた結果の記録のファイル")
struct FileVerificationRecordStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("hajime-record-\(UUID().uuidString)/\(DefaultSettings.verificationRecordFileName)")
    }

    private let record = VerificationRecord(appVersion: "1.0 (1)", entries: [
        "zenzai.small": .init(location: "/Applications/Hajime.app/Contents/Resources/Zenzai/model.gguf",
                              expectedSHA256: String(repeating: "a", count: 64), files: String(repeating: "b", count: 64)),
    ])

    @Test("本人だけが読み書きできるファイルに書き，読み直せる")
    func roundTrip() throws {
        let url = temporaryURL()
        let store = FileVerificationRecordStore(fileURL: url)
        #expect(store.load() == nil)
        store.save(record)
        #if !os(Windows)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        #endif
        #expect(FileVerificationRecordStore(fileURL: url).load() == record)
    }

    @Test("壊れた記録・形の違う記録・大きすぎる記録は読まない", arguments: [
        Data("{".utf8), Data("not json".utf8), Data(#"{"format":1,"appVersion":"1"}"#.utf8), Data(#"{"format":"1","appVersion":1,"entries":{}}"#.utf8),
        Data(count: DefaultSettings.maximumVerificationRecordBytes + 1),
    ])
    func unreadable(data: Data) throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        #expect(FileVerificationRecordStore(fileURL: url).load() == nil)
    }

    @Test("ディレクトリは記録として読まない")
    func directory() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(FileVerificationRecordStore(fileURL: url).load() == nil)
    }
}
