import Foundation
@testable import S90Domain
@testable import S90Persistence
import Testing

@Suite("取り込む辞書のファイル(R-14)")
struct DictionaryFileReaderTests {
    private let tsv = "!コメント\nでんあつ\t電圧\t名詞\tコメント\nやまだ\t山田\t人名\nとうきょう\t東京\t地名\n"

    @Test("タブ区切りを UTF-8・BOM 付き UTF-8・UTF-16(BOM あり/なし)・Shift_JIS・EUC-JP で読む", arguments: [
        String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .shiftJIS, .japaneseEUC,
    ])
    func encodings(encoding: String.Encoding) throws {
        let data = try #require(tsv.data(using: encoding))
        let words = try DictionaryFileReader.parse(data)
        #expect(words == [
            DictionaryWord(reading: "でんあつ", word: "電圧", wordClass: .noun),
            DictionaryWord(reading: "やまだ", word: "山田", wordClass: .personName),
            DictionaryWord(reading: "とうきょう", word: "東京", wordClass: .place),
        ])
    }

    @Test("BOM 付きの UTF-8")
    func utf8BOM() throws {
        let words = try DictionaryFileReader.parse(Data([0xEF, 0xBB, 0xBF]) + Data(tsv.utf8))
        #expect(words.first?.reading == "でんあつ")
    }

    @Test("SKK の形式: 1 行の複数の語と注釈を読み，送り仮名のある読みとコメントの行は読まない")
    func skk() throws {
        let text = ";; okuri-ari entries.\nかくr /書/描/\n;; okuri-nasi entries.\nかんじ /漢字/感じ;注釈/幹事/\nほうりつ /法律/\n"
        let words = try DictionaryFileReader.parse(Data(text.utf8))
        #expect(words.map(\.word) == ["漢字", "感じ", "幹事", "法律"])
        #expect(words.allSatisfy { $0.reading == "かんじ" || $0.reading == "ほうりつ" })
    }

    @Test("macOS のユーザ辞書の plist")
    func propertyList() throws {
        let list: [[String: String]] = [["phrase": "電磁誘導", "shortcut": "でんじゆうどう"], ["phrase": "壊れた", "shortcut": "abc"]]
        let data = try PropertyListSerialization.data(fromPropertyList: list, format: .xml, options: 0)
        #expect(try DictionaryFileReader.parse(data) == [DictionaryWord(reading: "でんじゆうどう", word: "電磁誘導")])
    }

    @Test("カタカナの読みはひらがなにそろえ，形の誤った行は読まない")
    func normalize() throws {
        let words = try DictionaryFileReader.parse(Data("デンアツ\t電圧\nabc\t壊れた\n\t空\n".utf8))
        #expect(words == [DictionaryWord(reading: "でんあつ", word: "電圧")])
    }

    @Test("品詞の名前を対応付け，分からなければ名詞", arguments: [
        ("名詞", WordClass.noun), ("固有名詞", .properNoun), ("人名", .personName), ("姓", .surname), ("名", .noun),
        ("地名その他", .place), ("組織", .organization), ("顔文字", .symbol), ("動詞ワ行五段", .noun),
    ])
    func partOfSpeech(name: String, expected: WordClass) {
        #expect(WordClass(partOfSpeech: name) == expected)
    }

    @Test("上限より大きなファイルは読まない")
    func tooLarge() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let handle = try #require({ () -> FileHandle? in
            FileManager.default.createFile(atPath: url.path, contents: nil)
            return FileHandle(forWritingAtPath: url.path)
        }())
        try handle.truncate(atOffset: UInt64(DefaultSettings.maximumImportedDictionaryBytes + 1))
        try handle.close()
        #expect(throws: DictionaryFileReader.FileError.fileTooLarge(maximumBytes: DefaultSettings.maximumImportedDictionaryBytes)) {
            try DictionaryFileReader.read(from: url)
        }
    }
}

@MainActor
@Suite("取り込んだ辞書の索引(R-14)")
struct ImportedDictionaryStoreTests {
    private func makeStore() -> (ImportedDictionaryStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ImportedDictionaryStore(directory: directory), directory)
    }

    @Test("読みがちょうど一致する語だけを引く")
    func lookup() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionary = ImportedDictionary(id: "a", name: "電気", wordCount: 3)
        try ImportedDictionaryStore.write([
            DictionaryWord(reading: "でんあつ", word: "電圧"),
            DictionaryWord(reading: "でんあつ", word: "電圧計"),
            DictionaryWord(reading: "でんあ", word: "電亜"),
            DictionaryWord(reading: "でんあつけい", word: "電圧計"),
        ], to: store.url(for: dictionary))
        #expect(Set(store.words(reading: "でんあつ", in: dictionary).map(\.word)) == ["電圧", "電圧計"])
        #expect(store.words(reading: "でん", in: dictionary).isEmpty)
        #expect(store.words(reading: "でんあつけい", in: dictionary).map(\.word) == ["電圧計"])
    }

    @Test("数十万語の辞書でも，1 つの読みを引くのは 1 ミリ秒もかからない")
    func largeDictionary() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let kana = Array("あいうえおかきくけこさしすせそたちつてとなにぬねの")
        var words: [DictionaryWord] = []
        for i in 0..<300_000 {
            var reading = ""
            var n = i
            repeat {
                reading.append(kana[n % kana.count])
                n /= kana.count
            } while n > 0
            words.append(DictionaryWord(reading: reading, word: "語\(i)"))
        }
        let dictionary = ImportedDictionary(id: "big", name: "大", wordCount: words.count)
        try ImportedDictionaryStore.write(words, to: store.url(for: dictionary))
        _ = store.words(reading: "あ", in: dictionary)
        let clock = ContinuousClock()
        var found = 0
        let elapsed = clock.measure {
            for word in words.prefix(1000) { found += store.words(reading: word.reading, in: dictionary).count }
        }
        #expect(found == 1000)
        #expect(elapsed < .milliseconds(1000))
    }

    @Test("消すと索引のファイルも消える")
    func remove() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let dictionary = ImportedDictionary(id: "a", name: "a", wordCount: 1)
        try ImportedDictionaryStore.write([DictionaryWord(reading: "あ", word: "亜")], to: store.url(for: dictionary))
        #expect(store.words(reading: "あ", in: dictionary).count == 1)
        store.remove(dictionary)
        #expect(!FileManager.default.fileExists(atPath: store.url(for: dictionary).path))
        #expect(store.words(reading: "あ", in: dictionary).isEmpty)
    }
}
