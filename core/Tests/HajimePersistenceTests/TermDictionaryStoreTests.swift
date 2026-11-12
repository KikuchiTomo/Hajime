import Foundation
import HajimeDomain
@testable import HajimePersistence
import Testing

@MainActor
@Suite("専門用語の辞書のファイル(R-29)")
struct TermDictionaryStoreTests {
    /// 本物のファイルと同じく，行を UTF-8 のバイト順に並べて書く
    private func write(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("terms-\(UUID().uuidString).tsv")
        let sorted = lines.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        try Data(sorted.map { $0 + "\n" }.joined().utf8).write(to: url)
        return url
    }

    @Test("読みがちょうど一致する語を，分野と品詞を付けて引く")
    func lookup() throws {
        let url = try write([
            "かでんあつ\t過電圧\tnoun\tengineering\t0",
            "ふーりえへんかん\tフーリエ変換\tnoun\tmathematics\t0",
            "ふーりえへんかん\tフーリエ変換\tnoun\tphysics\t0",
            "ぱいそん\tPython\tproperNoun\tcomputing\t0",
            "しかん\t篩管\tnoun\tbiology\t1",
            "たたいた\t多対多\tnoun\tcomputing\t2",
            "かんくう\t管腔\tnoun\tmedicine",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TermDictionaryStore(url: url)
        #expect(store.words(reading: "ふーりえへんかん").map(\.field) == [.mathematics, .physics])
        #expect(store.words(reading: "ぱいそん") == [TermWord(word: DictionaryWord(reading: "ぱいそん", word: "Python", wordClass: .properNoun), field: .computing)])
        #expect(store.words(reading: "かでん").isEmpty)
        // 読みが通常の辞書の語とどう重なるか．列が無ければ同じ読みの語があるとみなす(点数を下げる方)
        #expect(store.words(reading: "しかん").map(\.overlap) == [.sameReading])
        #expect(store.words(reading: "たたいた").map(\.overlap) == [.splittable])
        #expect(store.words(reading: "かんくう").map(\.overlap) == [.sameReading])
        #expect(store.words(reading: "かでんあつ").map(\.overlap) == [TermWord.Overlap.none])
    }

    @Test("知らない分野の行と，読みの形が正しくない行は使わない")
    func skipsUnknownRows() throws {
        let url = try write([
            "あいうえ\t愛\tnoun\tastrology\t0",
            "かきくけ\t書き\tnoun",
            "カキクケ\t柿\tnoun\tfood\t0",
            "さしすせ\t寿司\tnoun\tfood\t0",
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let store = TermDictionaryStore(url: url)
        #expect(store.words(reading: "あいうえ").isEmpty)
        #expect(store.words(reading: "かきくけ").isEmpty)
        #expect(store.words(reading: "カキクケ").isEmpty)
        #expect(store.words(reading: "さしすせ").map(\.word.word) == ["寿司"])
    }

    @Test("ファイルが無ければ語を返さない(専門用語の辞書の無い古い辞書)")
    func missingFile() {
        let store = TermDictionaryStore(url: FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).tsv"))
        #expect(store.words(reading: "かでんあつ").isEmpty)
    }
}
