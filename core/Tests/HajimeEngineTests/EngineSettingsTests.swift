import Foundation
import HajimeDomain
import HajimeEngine
import Testing

@Suite("変換に効く設定")
@MainActor
struct EngineSettingsTests {
    private func makeEngine() throws -> AzooKeyConverterEngine {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-settings-\(UUID().uuidString)")
        return try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "settings")
    }

    @Test("ユーザー辞書に登録した語を，文の中でも候補に出す")
    func userDictionary() throws {
        let engine = try makeEngine()
        var settings = Settings()
        // エンジンは辞書の語の続きになる読みしかたどらないので，辞書にある読みの語で確かめる(読みの一致は SupplementedConverter が受け持つ)
        settings.userDictionary = [UserDictionaryEntry(reading: "かいしゃ", word: "hajime株式会社")]
        engine.apply(settings)
        let texts = engine.makeSession().candidates(for: "かいしゃにいく").map(\.text)
        #expect(texts.contains { $0.hasPrefix("hajime株式会社") })
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

    @Test("学習を使わない求め(点数・語の区切り)のあとに確定しても，次の変換で上に来る")
    func learnsAfterScoringRequest() throws {
        let engine = try makeEngine()
        let session = engine.makeSession()
        let third = try #require(session.candidates(for: "きしゃ").dropFirst(2).first)
        // 分岐図を作るときは，確定の直前に学習を使わない求めが入る
        _ = session.plausibility(of: "きしゃ")
        _ = session.segmentationWords(for: "きしゃ")
        session.didCommit(third)
        session.endComposition()
        #expect(engine.makeSession().candidates(for: "きしゃ").first?.text == third.text)
    }

    @Test("先頭の語を選び直してつないだ候補を確定すると，元の語を学ぶ")
    func learnsHeadWordOfCombinedCandidate() throws {
        let engine = try makeEngine()
        let session = engine.makeSession()
        let word = try #require(session.dictionaryCandidates(for: "きしゃ").dropFirst(2).first)
        var combined = Candidate(text: word.text + "に", readingCount: 4, origin: .combined)
        combined.learnedParts = [word]
        #expect(combined.isLearnable)
        session.didCommit(combined)
        session.endComposition()
        #expect(engine.makeSession().candidates(for: "きしゃ").first?.text == word.text)
    }
}
