import Foundation
import HajimeDomain
import HajimePersistence
import Testing

@Suite("同梱の語の意味と同音異義語の使い分けの辞書")
@MainActor
struct UsageDictionaryFileTests {
    @Test("同梱する辞書を読み，活用した形と名詞の語に使い分けを示す")
    func bundledDictionary() async throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/usage/usage_dict.txt")
        let dictionary = try #require(await UsageDictionaryFile(url: url).waitForLoad())
        #expect(dictionary.note(for: "撮った", reading: "とった")?.word == "撮る")
        // 説明の頭の注記(〈「取る」とも〉)は意味にしない
        #expect(dictionary.note(for: "採る", reading: "とる")?.senses.first?.meaning == "(人を)採用する")
        #expect(dictionary.note(for: "採る", reading: "とる")?.senses.first?.example == "新人を採る")
        // 同じ読みの語が無い語(並ぶ)には，意味だけを辞書の順に示す
        let line = try #require(dictionary.note(for: "並んだ", reading: "ならんだ"))
        #expect(line.others.isEmpty)
        #expect(line.senses.map(\.meaning) == ["列をつくる", "同等になる"])
        #expect(dictionary.note(for: "会う", reading: "あう")?.others.isEmpty == false)
        #expect(dictionary.note(for: "精算", reading: "せいさん")?.word == "精算")
    }

    @Test("Mozc の辞書から作った辞書も続けて読み，元の辞書に無い読みの語に使い分けを示す")
    func bundledExtraDictionary() async throws {
        let usage = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/usage")
        let base = usage.appendingPathComponent("usage_dict.txt")
        let extra = usage.appendingPathComponent("usage_dict_extra.tsv")
        let dictionary = try #require(await UsageDictionaryFile(urls: [base, extra]).waitForLoad())
        #expect(dictionary.note(for: "撮った", reading: "とった")?.word == "撮る")
        #expect(dictionary.note(for: "機械", reading: "きかい")?.others.contains("機会") == true)
        #expect(await UsageDictionaryFile(url: base).waitForLoad()?.note(for: "機械", reading: "きかい") == nil)
    }

    @Test("同音異義語の無い語の辞書も続けて裏で読み，「動く」の活用した形に意味だけを示す")
    func bundledWordsDictionary() async throws {
        let usage = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/usage")
        let urls = ["usage_dict.txt", "usage_dict_extra.tsv", "usage_dict_words.tsv"].map { usage.appendingPathComponent($0) }
        let file = UsageDictionaryFile(urls: urls)
        // 読み終わる前は待たずに nil を返す(変換を止めない)
        #expect(file.usageDictionary == nil)
        let dictionary = try #require(await file.waitForLoad())
        #expect(file.usageDictionary != nil)
        let moved = try #require(dictionary.note(for: "動いた", reading: "うごいた"))
        #expect(moved.word == "動く")
        #expect(moved.others.isEmpty)
        #expect(moved.senses.count >= 1)
        // 3 つのファイルとも 5 列目の品詞を読む
        #expect(moved.partOfSpeech == .verb)
        #expect(dictionary.note(for: "撮った", reading: "とった")?.partOfSpeech == .verb)
        #expect(dictionary.note(for: "機械", reading: "きかい")?.partOfSpeech == .noun)
        // 元の辞書と同音異義語の辞書の語はそのまま
        #expect(dictionary.note(for: "撮った", reading: "とった")?.word == "撮る")
        #expect(dictionary.note(for: "機械", reading: "きかい")?.others.contains("機会") == true)
    }

    @Test("読めないファイルは飛ばし，残りのファイルを読む")
    func skipsMissingFile() async throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/usage/usage_dict.txt")
        let dictionary = try #require(await UsageDictionaryFile(urls: [URL(fileURLWithPath: "/nonexistent/usage_dict_extra.tsv"), url]).waitForLoad())
        #expect(dictionary.note(for: "撮った", reading: "とった")?.word == "撮る")
    }

    @Test("無いファイルは nil")
    func missingFile() async {
        #expect(await UsageDictionaryFile(url: URL(fileURLWithPath: "/nonexistent/usage_dict.txt")).waitForLoad() == nil)
    }
}
