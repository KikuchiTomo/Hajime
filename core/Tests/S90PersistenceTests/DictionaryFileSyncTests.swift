import Foundation
@testable import S90Domain
@testable import S90Persistence
import Testing

@Suite("取り込んだ辞書の索引の同期(R-15・R-16)")
struct DictionaryFileSyncTests {
    private let id = "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B"

    /// 2 台の Mac の索引の置き場所と，共有する同期のフォルダ
    private struct Folders {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("s90-dictsync-\(UUID().uuidString)")
        var macA: URL { root.appendingPathComponent("a") }
        var macB: URL { root.appendingPathComponent("b") }
        var shared: URL { root.appendingPathComponent("shared") }

        init() throws {
            for url in [macA, macB, shared] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        }
    }

    private func writeIndex(_ words: [DictionaryWord], in directory: URL) throws -> ImportedDictionary {
        var dictionary = ImportedDictionary(id: id, name: "電気", wordCount: words.count)
        let url = directory.appendingPathComponent(dictionary.indexFileName)
        try ImportedDictionaryStore.write(words, to: url)
        dictionary.revision = try DictionaryFileSync.sha256(of: url)
        return dictionary
    }

    @Test("片方の Mac で取り込んだ索引が，同期のフォルダを通ってもう片方に届き，引ける")
    @MainActor
    func roundTrip() throws {
        let folders = try Folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let dictionary = try writeIndex([DictionaryWord(reading: "でんあつ", word: "電圧")], in: folders.macA)

        let upload = try DictionaryFileSync(localDirectory: folders.macA, syncFolder: folders.shared).sync([dictionary])
        #expect(upload.uploaded == 1)
        let download = try DictionaryFileSync(localDirectory: folders.macB, syncFolder: folders.shared).sync([dictionary])
        #expect(download.installed == [id])
        #expect(ImportedDictionaryStore(directory: folders.macB).words(reading: "でんあつ", in: dictionary).map(\.word) == ["電圧"])
        // もう一度同期しても，運び直さない
        let again = try DictionaryFileSync(localDirectory: folders.macB, syncFolder: folders.shared).sync([dictionary])
        #expect(again == DictionaryFileSync.Outcome())
    }

    @Test("同期のフォルダの索引が書き換えられていれば入れ替えず，ほかの辞書は続けて運ぶ")
    func rejectsTamperedFile() throws {
        let folders = try Folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let dictionary = try writeIndex([DictionaryWord(reading: "でんあつ", word: "電圧")], in: folders.macA)
        _ = try DictionaryFileSync(localDirectory: folders.macA, syncFolder: folders.shared).sync([dictionary])
        let remote = folders.shared.appendingPathComponent(DictionaryFileSync.folderName)
            .appendingPathComponent(DictionaryFileSync.remoteFileName(id: id, revision: try #require(dictionary.revision)))
        try Data("でんあつ\t偽物\tnoun\n".utf8).write(to: remote)

        let outcome = try DictionaryFileSync(localDirectory: folders.macB, syncFolder: folders.shared).sync([dictionary])
        #expect(outcome.failed == [id])
        #expect(outcome.installed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folders.macB.appendingPathComponent(dictionary.indexFileName).path))
    }

    @Test("取り込み直す前のバージョンと消した辞書の索引をフォルダから消し，利用者が置いたほかのファイルには触れない")
    func removesStaleFiles() throws {
        let folders = try Folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let old = try writeIndex([DictionaryWord(reading: "でんあつ", word: "電圧")], in: folders.macA)
        _ = try DictionaryFileSync(localDirectory: folders.macA, syncFolder: folders.shared).sync([old])
        let remoteFolder = folders.shared.appendingPathComponent(DictionaryFileSync.folderName)
        try Data("memo".utf8).write(to: remoteFolder.appendingPathComponent("memo.tsv"))

        let new = try writeIndex([DictionaryWord(reading: "でんりゅう", word: "電流")], in: folders.macA)
        let outcome = try DictionaryFileSync(localDirectory: folders.macA, syncFolder: folders.shared).sync([new])
        #expect(outcome.uploaded == 1)
        #expect(outcome.removed == 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: remoteFolder.path).sorted()
        #expect(names == [DictionaryFileSync.remoteFileName(id: id, revision: try #require(new.revision)), "memo.tsv"].sorted())
    }

    @Test("バージョンの無い辞書(同期を入れる前に取り込んだもの)は，この Mac の索引からバージョンを求めて返す")
    func computesMissingRevision() throws {
        let folders = try Folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        var dictionary = try writeIndex([DictionaryWord(reading: "でんあつ", word: "電圧")], in: folders.macA)
        let revision = dictionary.revision
        dictionary.revision = nil
        let outcome = try DictionaryFileSync(localDirectory: folders.macA, syncFolder: folders.shared).sync([dictionary])
        #expect(outcome.computedRevisions == [id: try #require(revision)])
        #expect(outcome.uploaded == 0)
    }

    @Test("索引の名前の形を見分ける")
    func indexFileName() {
        #expect(DictionaryFileSync.isIndexFileName(DictionaryFileSync.remoteFileName(id: id, revision: String(repeating: "0", count: 64))))
        #expect(!DictionaryFileSync.isIndexFileName("memo.tsv"))
        #expect(!DictionaryFileSync.isIndexFileName("\(id)-\(String(repeating: "G", count: 64)).tsv"))
    }
}
