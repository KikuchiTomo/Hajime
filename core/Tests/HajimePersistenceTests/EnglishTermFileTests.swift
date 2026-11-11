import Foundation
import HajimeDomain
import HajimePersistence
import Testing

@Suite("同梱の英語の語の辞書のファイル")
@MainActor
struct EnglishTermFileTests {
    private func temporaryFile(_ contents: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-english-terms-\(UUID().uuidString).txt")
        try contents.write(to: url)
        return url
    }

    @Test("R-24: 1 行に 1 語のファイルを読む")
    func readsFile() throws {
        let url = try temporaryFile(Data("# 略語\nAPI\nOpenAI\n".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let dictionary = try #require(EnglishTermFile(url: url).englishTerms)
        #expect(dictionary.terms(forReading: "あぴ") == ["API"])
        #expect(dictionary.count == 2)
    }

    @Test("R-24: 無いファイル，語の無いファイル，大きすぎるファイルは読まない")
    func rejectsFiles() throws {
        #expect(EnglishTermFile(url: FileManager.default.temporaryDirectory.appendingPathComponent("hajime-missing-\(UUID().uuidString)")).englishTerms == nil)
        let empty = try temporaryFile(Data("# 語なし\nC++\n".utf8))
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(EnglishTermFile(url: empty).englishTerms == nil)
        let large = try temporaryFile(Data(repeating: UInt8(ascii: "a"), count: DefaultSettings.maximumEnglishTermFileBytes + 1))
        defer { try? FileManager.default.removeItem(at: large) }
        #expect(EnglishTermFile(url: large).englishTerms == nil)
    }
}
