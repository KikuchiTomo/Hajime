import Foundation
@testable import S90Domain
@testable import S90Persistence
import Testing

@Suite("連想の辞書のファイル(R-18)")
struct AssociationFileReaderTests {
    @Test("タブ区切りは先頭の列を意味の説明にし，タブの無い行は「,」「、」で区切る．コメントと 1 語だけの行は読まない")
    func parse() throws {
        let text = "# コメント\n見た目が快い\t綺麗\t麗しい\t華麗\n清らか,清い、潔い\n一語だけ\n\t端麗\t端麗\t秀麗\n"
        let groups = try AssociationFileReader.parse(Data(text.utf8))
        #expect(groups == [
            AssociationGroup(label: "見た目が快い", words: ["綺麗", "麗しい", "華麗"]),
            AssociationGroup(label: "", words: ["清らか", "清い", "潔い"]),
            AssociationGroup(label: "", words: ["端麗", "秀麗"]),
        ])
    }

    @Test("Shift_JIS のファイルも読む")
    func shiftJIS() throws {
        let data = try #require("意味\t綺麗\t麗しい\n".data(using: .shiftJIS))
        #expect(try AssociationFileReader.parse(data).first?.words == ["綺麗", "麗しい"])
    }

    @Test("まとまりの語は上限の数までにする")
    func groupWordLimit() throws {
        let words = (0..<(DefaultSettings.maximumAssociationGroupWords + 10)).map { "語\($0)" }
        let groups = try AssociationFileReader.parse(Data(("\t" + words.joined(separator: "\t")).utf8))
        #expect(groups.first?.words.count == DefaultSettings.maximumAssociationGroupWords)
    }

    @Test("大きすぎるファイルと，まとまりの無いファイルは読まない")
    func rejects() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let large = directory.appendingPathComponent("large.tsv")
        try Data(count: DefaultSettings.maximumAssociationFileBytes + 1).write(to: large)
        #expect(throws: DictionaryFileReader.FileError.fileTooLarge(maximumBytes: DefaultSettings.maximumAssociationFileBytes)) {
            try AssociationFileReader.read(from: large)
        }
        let empty = directory.appendingPathComponent("empty.tsv")
        try Data("# なし\n一語\n".utf8).write(to: empty)
        #expect(throws: DictionaryFileReader.FileError.empty) { try AssociationFileReader.read(from: empty) }
    }
}

@MainActor
@Suite("連想の辞書の索引(R-18)")
struct AssociationDictionaryStoreTests {
    private func makeStore() throws -> (AssociationDictionaryStore, AssociationDictionary, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = AssociationDictionaryStore(directory: directory)
        let dictionary = AssociationDictionary(id: UUID().uuidString, name: "類語", groupCount: 2)
        try AssociationDictionaryStore.write([
            AssociationGroup(label: "見た目が快い", words: ["綺麗", "美しい", "麗しい"]),
            AssociationGroup(label: "汚れがない", words: ["綺麗", "清潔"]),
            AssociationGroup(label: "", words: ["美", "美しさ"]),
        ], to: store.url(for: dictionary))
        return (store, dictionary, directory)
    }

    @Test("語ごとに，その語を含むまとまりを取り込んだ順に引く．まとまりの語は引いた語を除いたもの")
    func lookup() throws {
        let (store, dictionary, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(store.groups(for: "綺麗", in: dictionary) == [
            AssociationGroup(label: "見た目が快い", words: ["美しい", "麗しい"]),
            AssociationGroup(label: "汚れがない", words: ["清潔"]),
        ])
        #expect(store.groups(for: "美しい", in: dictionary).map(\.words) == [["綺麗", "麗しい"]])
        // 前方が同じだけの語(「美」と「美しい」)は取り違えない
        #expect(store.groups(for: "美", in: dictionary).map(\.words) == [["美しさ"]])
        #expect(store.groups(for: "汚い", in: dictionary).isEmpty)
    }

    @Test("索引のファイルは本人だけが読み書きでき，消すと引けなくなる")
    func permissionsAndRemove() throws {
        let (store, dictionary, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        #if !os(Windows)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.url(for: dictionary).path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        #endif
        store.remove(dictionary)
        #expect(store.groups(for: "綺麗", in: dictionary).isEmpty)
    }

    @Test("書き換えられた索引の形の誤った行と，UUID の形でない id の辞書は使わない")
    func rejectsTamperedIndex() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AssociationDictionaryStore(directory: directory)
        let dictionary = AssociationDictionary(id: UUID().uuidString, name: "x", groupCount: 1)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let long = String(repeating: "あ", count: DefaultSettings.maximumAssociationWordLength + 1)
        try Data("綺麗\t説明\n綺麗\t説明\t\(long)\n綺麗\t説明\t美しい\n".utf8).write(to: store.url(for: dictionary))
        #expect(store.groups(for: "綺麗", in: dictionary).map(\.words) == [["美しい"]])
        let invalid = AssociationDictionary(id: "../x", name: "x", groupCount: 1)
        #expect(store.groups(for: "綺麗", in: invalid).isEmpty)
    }
}
