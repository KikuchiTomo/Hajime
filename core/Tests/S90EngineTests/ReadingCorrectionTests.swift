import Foundation
import S90Application
import S90Domain
import S90Engine
import S90TestSupport
import Testing

/// 本物の Zenzai で日本語の打ち間違いを直す．モデルが要るので，環境変数 S90_ZENZAI_MODEL にモデルの場所があるときだけ動かす
@Suite("日本語の打ち間違い(Zenzai)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["S90_ZENZAI_MODEL"] != nil))
@MainActor
struct ReadingCorrectionTests {
    @Test("Space で変換すると打ち間違いを直す", arguments: [
        ("kyounotenkihayoudesune", "良いですね"),
        ("watashuhagakuseidesu", "学生"),
        ("arigatpugozaimasu", "ありがとう"),
    ])
    func corrects(keys: String, expected: String) throws {
        let marked = try convert(keys)
        #expect(marked.contains(expected))
    }

    @Test("正しく打った語は直さない", arguments: ["konnichiha", "henkann", "nihongonyuuryoku"])
    func keeps(keys: String) throws {
        let session = try makeSession()
        let before = live(session, keys)
        let after = marked(session.handle(KeyEvent(.space), context: InputContext()).actions)
        #expect(after == before || after == nil, "\(keys)")
    }

    @Test("別の変換器で求めた訂正で，報告された打ち間違いを直す(打ち忘れ・余分な母音・入れ替わり)", arguments: [
        ("kyouhaitenkidesune", "kyouhaiitenkidesune"),
        ("kyouhaiteknidesune", "kyouhaiitenkidesune"),
        ("tututasakanagaookikatta", "tuttasakanagaookikatta"),
    ])
    func service(typed: String, expected: String) async throws {
        let path = try #require(ProcessInfo.processInfo.environment["S90_ZENZAI_MODEL"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-typo-\(UUID().uuidString)")
        let service = ZenzaiTypoService(zenzai: try ZenzaiModel.verified(at: URL(fileURLWithPath: path)), memoryDirectory: directory, versionString: "typo")
        let corrections = await service.corrections(forKeys: [typed], leftContext: nil)
        #expect(corrections[typed]?.first?.keys == expected)
    }

    private func makeSession() throws -> InputSession {
        let path = try #require(ProcessInfo.processInfo.environment["S90_ZENZAI_MODEL"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-typo-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "typo", zenzai: try ZenzaiModel.verified(at: URL(fileURLWithPath: path)))
        return InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(), settings: FakeSettings())
    }

    private func convert(_ keys: String) throws -> String {
        let session = try makeSession()
        _ = live(session, keys)
        return marked(session.handle(KeyEvent(.space), context: InputContext()).actions) ?? ""
    }

    private func live(_ session: InputSession, _ keys: String) -> String? {
        var result: String?
        for key in keys { result = marked(session.handle(KeyEvent(.character(key)), context: InputContext()).actions) ?? result }
        return result
    }

    private func marked(_ actions: [ClientAction]) -> String? {
        actions.compactMap { if case .setMarkedText(let text) = $0 { text.text } else { nil } }.last
    }
}
