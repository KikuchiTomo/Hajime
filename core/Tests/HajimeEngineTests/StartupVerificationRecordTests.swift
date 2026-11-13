import Foundation
import HajimeApplication
import HajimeDomain
@testable import HajimeEngine
import Testing

/// 前回確かめて合ったファイルが変わっていなければハッシュを求め直さず，どれかが変わっていれば確かめ直すこと(ADR 0017)．
///
/// ハッシュを求めたかどうかは，中身だけを書き換えて大きさ・更新日時・ファイル ID を元のままにしたファイルで見分ける．
/// 確かめ直せばハッシュが合わずに断り，記録を使えば断らない
@Suite("起動のときに確かめた結果の記録")
struct StartupVerificationRecordTests {
    /// 「abc」の SHA-256
    private let abcSHA256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    /// 比べるときに揺れないよう，秒の切りのよい更新日時にそろえる
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-record-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func setModified(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    /// 同じファイルのまま(ファイル ID を変えずに)中身を書き換え，更新日時を戻す
    private func overwriteInPlace(_ url: URL, with text: String) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
        try setModified(url, fixedDate)
    }

    private func model(_ text: String = "abc") throws -> URL {
        let url = try temporaryDirectory().appendingPathComponent("model.gguf")
        try Data(text.utf8).write(to: url)
        try setModified(url, fixedDate)
        return url
    }

    private func check(_ url: URL, previous: VerificationRecord.Entry?, expectedSHA256: String? = nil) throws -> VerificationRecord.Entry? {
        try ZenzaiModel.check(url, expectedSize: 3, expectedSHA256: expectedSHA256 ?? abcSHA256, previous: previous)
    }

    @Test("属性が前回と同じなら，ハッシュを求めずに使う")
    func reusesWhenUnchanged() throws {
        let url = try model()
        let record = try #require(try check(url, previous: nil))
        try overwriteInPlace(url, with: "abd")
        #expect(FileDigest.stamp(at: url) != nil)
        #expect(try check(url, previous: record) == record)
        // 記録を使わなければ，書き換えた中身に気付いて断る
        #expect(throws: ZenzaiModel.VerificationError.hashMismatch) { try check(url, previous: nil) }
    }

    @Test("更新日時が違えば確かめ直す")
    func reverifiesWhenModified() throws {
        let url = try model()
        let record = try check(url, previous: nil)
        try overwriteInPlace(url, with: "abd")
        try setModified(url, fixedDate.addingTimeInterval(1))
        #expect(throws: ZenzaiModel.VerificationError.hashMismatch) { try check(url, previous: record) }
    }

    @Test("大きさが違えば確かめ直す")
    func reverifiesWhenResized() throws {
        let url = try model()
        let record = try check(url, previous: nil)
        try Data("abcd".utf8).write(to: url)
        try setModified(url, fixedDate)
        #expect(throws: ZenzaiModel.VerificationError.sizeMismatch(actual: 4)) { try check(url, previous: record) }
    }

    @Test("ファイル ID が違えば(別のファイルに置き換えられたら)確かめ直す")
    func reverifiesWhenReplaced() throws {
        let url = try model()
        let record = try check(url, previous: nil)
        let replacement = url.deletingLastPathComponent().appendingPathComponent("replacement.gguf")
        try Data("abd".utf8).write(to: replacement)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)
        try setModified(url, fixedDate)
        #expect(FileDigest.stamp(at: url)?.size == 3)
        #expect(throws: ZenzaiModel.VerificationError.hashMismatch) { try check(url, previous: record) }
    }

    @Test("照らし合わせる SHA-256 か場所が前回と違えば確かめ直す")
    func reverifiesWhenExpectationChanges() throws {
        let url = try model()
        let record = try #require(try check(url, previous: nil))
        try overwriteInPlace(url, with: "abd")
        var moved = record
        moved.location += "-moved"
        #expect(throws: ZenzaiModel.VerificationError.hashMismatch) { try check(url, previous: moved) }
        let other = String(repeating: "0", count: 64)
        #expect(throws: ZenzaiModel.VerificationError.hashMismatch) {
            try check(url, previous: VerificationRecord.Entry(location: record.location, expectedSHA256: other, files: record.files))
        }
    }

    @Test("記録の中身が合わなければ(壊れた記録)確かめ直す")
    func reverifiesWhenRecordIsGarbage() throws {
        let url = try model()
        let record = try #require(try check(url, previous: nil))
        try overwriteInPlace(url, with: "abd")
        let garbage = VerificationRecord.Entry(location: record.location, expectedSHA256: record.expectedSHA256, files: "not a digest")
        #expect(throws: ZenzaiModel.VerificationError.hashMismatch) { try check(url, previous: garbage) }
    }

    /// louds/charID.chid(中身は abc)と一覧を持つ小さな辞書
    private func dictionary() throws -> (directory: URL, manifestSHA256: String, file: URL) {
        let directory = try temporaryDirectory()
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("louds"), withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("louds/charID.chid")
        try Data("abc".utf8).write(to: file)
        try setModified(file, fixedDate)
        let manifest = Data("\(abcSHA256)  louds/charID.chid\n".utf8)
        try manifest.write(to: directory.appendingPathComponent(BundledDictionary.manifestName))
        return (directory, FileDigest.sha256(of: manifest), file)
    }

    @Test("辞書: 一覧にあるファイルの属性が前回と同じなら，ファイルのハッシュを求めずに使う．違えば確かめ直す")
    func dictionaryReuse() throws {
        let (directory, manifestSHA256, file) = try dictionary()
        let record = try #require(try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256, previous: nil, recording: true).record)
        try overwriteInPlace(file, with: "abd")
        let reused = try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256, previous: record, recording: true)
        #expect(reused.dictionary.url == directory)
        #expect(reused.record == record)
        try setModified(file, fixedDate.addingTimeInterval(1))
        #expect(throws: BundledDictionary.VerificationError.hashMismatch) {
            try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256, previous: record, recording: true)
        }
    }

    @Test("辞書: 記録があっても一覧は毎回確かめる")
    func dictionaryManifestAlwaysChecked() throws {
        let (directory, manifestSHA256, _) = try dictionary()
        let record = try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256, previous: nil, recording: true).record
        try Data("\(abcSHA256)  louds/charID.chid\n\n".utf8).write(to: directory.appendingPathComponent(BundledDictionary.manifestName))
        #expect(throws: BundledDictionary.VerificationError.manifestMismatch) {
            try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256, previous: record, recording: true)
        }
    }

    @Test("記録を書かないときは記録を返さない")
    func noRecordWithoutRecording() throws {
        let (directory, manifestSHA256, _) = try dictionary()
        #expect(try BundledDictionary.verified(at: directory, expectedManifestSHA256: manifestSHA256, previous: nil, recording: false).record == nil)
    }

    @Test("無いファイルとディレクトリは属性を返さない")
    func stampOfMissing() throws {
        let directory = try temporaryDirectory()
        #expect(FileDigest.stamp(at: directory) == nil)
        #expect(FileDigest.stamp(at: directory.appendingPathComponent("none")) == nil)
    }

    @Test("読めない記録(ストアが nil を返す)なら，すべて確かめて記録し直す．合わなかったものは記録しない")
    func storeIgnoresUnreadableRecord() {
        let store = MemoryRecordStore(record: nil)
        let nowhere = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-none-\(UUID().uuidString)")
        let resources = StartupResources.verified(zenzai: nowhere.appendingPathComponent("model.gguf"), fastZenzai: nil, dictionary: nowhere,
                                                  records: store, appVersion: "1")
        #expect(resources.zenzai == .failure(.fileNotFound))
        #expect(resources.dictionary == .failure(.manifestNotFound))
        #expect(store.saved == [VerificationRecord(appVersion: "1")])
    }
}

/// 記録を覚えておくだけのストア
private final class MemoryRecordStore: VerificationRecordStoring, @unchecked Sendable {
    private let lock = NSLock()
    private let record: VerificationRecord?
    private var savedRecords: [VerificationRecord] = []

    init(record: VerificationRecord?) {
        self.record = record
    }

    var saved: [VerificationRecord] {
        lock.lock()
        defer { lock.unlock() }
        return savedRecords
    }

    func load() -> VerificationRecord? { record }

    func save(_ record: VerificationRecord) {
        lock.lock()
        defer { lock.unlock() }
        savedRecords.append(record)
    }
}
