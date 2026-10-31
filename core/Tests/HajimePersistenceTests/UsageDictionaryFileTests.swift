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

    @Test("無いファイルは nil")
    func missingFile() {
        #expect(UsageDictionaryFile(url: URL(fileURLWithPath: "/nonexistent/usage_dict.txt")).usageDictionary == nil)
    }
}
