import Foundation
import HajimeDomain
import HajimePersistence
import Testing

@Suite("同梱の同音異義語の使い分けの辞書")
@MainActor
struct UsageDictionaryFileTests {
    @Test("同梱する辞書を読み，活用した形と名詞の語に使い分けを示す")
    func bundledDictionary() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/usage/usage_dict.txt")
        let dictionary = try #require(UsageDictionaryFile(url: url).usageDictionary)
        #expect(dictionary.note(for: "撮った", reading: "とった")?.hasPrefix("撮る: ") == true)
        #expect(dictionary.note(for: "会う", reading: "あう")?.contains("ほかに") == true)
        #expect(dictionary.note(for: "精算", reading: "せいさん")?.hasPrefix("精算: ") == true)
    }

    @Test("Mozc の辞書から作った辞書も続けて読み，元の辞書に無い読みの語に使い分けを示す")
    func bundledExtraDictionary() throws {
        let usage = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/usage")
        let base = usage.appendingPathComponent("usage_dict.txt")
        let extra = usage.appendingPathComponent("usage_dict_extra.tsv")
        let dictionary = try #require(UsageDictionaryFile(urls: [base, extra]).usageDictionary)
        #expect(dictionary.note(for: "撮った", reading: "とった")?.hasPrefix("撮る: ") == true)
        #expect(dictionary.note(for: "機械", reading: "きかい")?.contains("機会") == true)
        #expect(UsageDictionaryFile(url: base).usageDictionary?.note(for: "機械", reading: "きかい") == nil)
    }

    @Test("読めないファイルは飛ばし，残りのファイルを読む")
    func skipsMissingFile() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/usage/usage_dict.txt")
        let dictionary = try #require(UsageDictionaryFile(urls: [URL(fileURLWithPath: "/nonexistent/usage_dict_extra.tsv"), url]).usageDictionary)
        #expect(dictionary.note(for: "撮った", reading: "とった")?.hasPrefix("撮る: ") == true)
    }

    @Test("無いファイルは nil")
    func missingFile() {
        #expect(UsageDictionaryFile(url: URL(fileURLWithPath: "/nonexistent/usage_dict.txt")).usageDictionary == nil)
    }
}
