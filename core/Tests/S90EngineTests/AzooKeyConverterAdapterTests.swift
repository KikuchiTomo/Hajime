import Foundation
import S90Domain
import S90Engine
import Testing

/// 本物の辞書で変換できることを確かめる結合テスト．変換の質そのものは確かめない
@Suite("azooKey のエンジン")
@MainActor
struct AzooKeyConverterAdapterTests {
    private func makeEngine() throws -> AzooKeyConverterEngine {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-engine-\(UUID().uuidString)")
        return try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "s90.tokyo IME tests")
    }

    @Test("読み全体を変換した候補を返す")
    func converts() throws {
        let session = try makeEngine().makeSession()
        let candidates = session.candidates(for: "へんかん")
        #expect(candidates.contains { $0.text == "変換" && $0.readingCount == 4 })
    }

    @Test("文の先頭の文節だけの候補も返す")
    func firstClause() throws {
        let session = try makeEngine().makeSession()
        let candidates = session.candidates(for: "きょうはいいてんきです")
        #expect(candidates.contains { $0.readingCount < 11 })
        #expect(candidates.first?.readingCount == 11)
    }

    @Test("空の読みには何も返さない")
    func empty() throws {
        #expect(try makeEngine().makeSession().candidates(for: "").isEmpty)
    }

    @Test("学習のディレクトリは本人だけが使える権限で作る")
    func permissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-engine-\(UUID().uuidString)")
        _ = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "test")
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o700)
    }
}
