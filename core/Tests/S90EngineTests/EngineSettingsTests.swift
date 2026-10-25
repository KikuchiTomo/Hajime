import Foundation
import S90Domain
import S90Engine
import Testing

@Suite("変換に効く設定")
@MainActor
struct EngineSettingsTests {
    private func makeEngine() throws -> AzooKeyConverterEngine {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-settings-\(UUID().uuidString)")
        return try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "settings")
    }

    @Test("ユーザー辞書に登録した語を，文の中でも候補に出す")
    func userDictionary() throws {
        let engine = try makeEngine()
        var settings = Settings()
        // エンジンは辞書の語の続きになる読みしかたどらないので，辞書にある読みの語で確かめる(読みの一致は SupplementedConverter が受け持つ)
        settings.userDictionary = [UserDictionaryEntry(reading: "かいしゃ", word: "s90株式会社")]
        engine.apply(settings)
        let texts = engine.makeSession().candidates(for: "かいしゃにいく").map(\.text)
        #expect(texts.contains { $0.hasPrefix("s90株式会社") })
    }

    @Test("学習を切ると，確定しても順位が変わらない")
    func learningDisabled() throws {
        let engine = try makeEngine()
        var settings = Settings()
        settings.learning = .disabled
        engine.apply(settings)
        let session = engine.makeSession()
        let before = session.candidates(for: "きしゃ").map(\.text)
        let third = try #require(session.candidates(for: "きしゃ").dropFirst(2).first)
        session.didCommit(third)
        session.endComposition()
        #expect(engine.makeSession().candidates(for: "きしゃ").map(\.text).first == before.first)
    }
}
