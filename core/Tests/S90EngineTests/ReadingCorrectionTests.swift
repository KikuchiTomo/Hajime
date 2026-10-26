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

    @Test("英語の混ざる文は，打鍵が止まって見直しても，Space で変換しても英単語を日本語に直さない", arguments: [
        ("pythongasugoi", "pythonがすごい"),
        ("gitwotukau", "gitを使う"),
        ("konoIMEha", "このIMEは"),
        ("AAAmade", "AAAまで"),
    ])
    func keepsEnglish(keys: String, expected: String) throws {
        let lexicon = FakeLexicon(words: ["python", "git"])
        let reviewed = try makeSession(lexicon: lexicon)
        _ = live(reviewed, keys)
        let settled = marked(reviewed.settle(context: InputContext()) + reviewed.review(context: InputContext()))
        #expect(settled == nil || settled == expected, "\(keys)")
        var committed = ""
        for action in reviewed.handle(KeyEvent(.enter), context: InputContext()).actions {
            if case .commit(let text) = action { committed += text }
        }
        #expect(committed == expected)

        let converted = try makeSession(lexicon: lexicon)
        _ = live(converted, keys)
        _ = converted.handle(KeyEvent(.space), context: InputContext())
        committed = ""
        for action in converted.handle(KeyEvent(.enter), context: InputContext()).actions {
            if case .commit(let text) = action { committed += text }
        }
        #expect(committed == expected)
    }

    @Test("アプリと同じ道筋(打つ → 止まる → 別の変換器で訂正を求める → 見直す)で直すか示す", arguments: [
        "kyounotenkihayoudesune", "kyouhaitenkidesune", "kyouhaiteknidesune", "tututasakanagaookikatta", "mizurai",
        "arigatpugozaimasu", "yorosikuonagaisimasu", "konnnitiwa", "tkitou", "nankatkitou", "wakeranai", "sorehawakeranaidesu",
    ])
    func appFlow(keys: String) async throws {
        let path = try #require(ProcessInfo.processInfo.environment["S90_ZENZAI_MODEL"])
        let model = try ZenzaiModel.verified(at: URL(fileURLWithPath: path))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-typo-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "typo", zenzai: model)
        let service = ZenzaiTypoService(zenzai: model, memoryDirectory: directory, versionString: "typo")
        let session = InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(), settings: FakeSettings(), typoService: service)
        _ = live(session, keys)
        var actions = session.settle(context: InputContext())
        let request = session.correctionRequest
        #expect(request != nil, "\(keys): 訂正を求めない")
        if let request {
            let corrections = await service.corrections(forKeys: request.keys, leftContext: request.leftContext)
            session.provideCorrections(corrections)
        }
        actions += session.review(context: InputContext())
        let note = actions.compactMap { if case .showNote(let text) = $0 { text } else { nil } }.last
        let corrected = actions.contains { if case .setMarkedText(let text) = $0 { text.segments.contains { $0.style == .correction } } else { false } }
        print("通し \(keys): 直した=\(corrected) 案内=\(note ?? "-") 文=\(marked(actions) ?? "-")")
        #expect(corrected || note?.hasPrefix("もしかして") == true, "\(keys)")
    }

    @Test("綴りを直した英単語は，打鍵が止まって日本語の見直しをしても英単語のまま(日本語として直せないとき)", arguments: [
        ("pthon", "pthon", "python"), ("pthonga", "pthon", "pythonが"), ("pyhtonwotukau", "pyhton", "pythonを使う"),
    ])
    func englishMisspellingKept(keys: String, typo: String, expected: String) async throws {
        let path = try #require(ProcessInfo.processInfo.environment["S90_ZENZAI_MODEL"])
        let model = try ZenzaiModel.verified(at: URL(fileURLWithPath: path))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-typo-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "typo", zenzai: model)
        let service = ZenzaiTypoService(zenzai: model, memoryDirectory: directory, versionString: "typo")
        let session = InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(suggestions: [typo: [String(expected.prefix { $0.isASCII })]]), settings: FakeSettings(), typoService: service)
        let typed = live(session, keys)
        var actions = session.settle(context: InputContext())
        if let request = session.correctionRequest {
            session.provideCorrections(await service.corrections(forKeys: request.keys, leftContext: request.leftContext))
        }
        actions += session.review(context: InputContext())
        let text = marked(actions) ?? typed ?? ""
        #expect(text.hasPrefix(String(expected.prefix { $0.isASCII })) && !text.contains { $0.isASCII && $0.isUppercase }, "\(keys) → \(text)")
    }

    private func makeSession(lexicon: FakeLexicon = FakeLexicon()) throws -> InputSession {
        let path = try #require(ProcessInfo.processInfo.environment["S90_ZENZAI_MODEL"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-typo-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "typo", zenzai: try ZenzaiModel.verified(at: URL(fileURLWithPath: path)))
        return InputSession(converter: engine.makeSession(), lexicon: lexicon, settings: FakeSettings())
    }

    private func convert(_ keys: String) throws -> String {
        let session = try makeSession()
        _ = live(session, keys)
        return marked(session.handle(KeyEvent(.space), context: InputContext()).actions) ?? ""
    }

    @Test("英単語の綴りの候補があっても，日本語の打ち間違いとして直せるなら日本語にする", arguments: [
        ("tkitou", "適当"), ("arigatpugozaimasu", "ありがとうございます"), ("yorpsikuonegaisimasu", "よろしくお願いします"),
    ])
    func japaneseWinsOverEnglishSpelling(keys: String, expected: String) async throws {
        let path = try #require(ProcessInfo.processInfo.environment["S90_ZENZAI_MODEL"])
        let model = try ZenzaiModel.verified(at: URL(fileURLWithPath: path))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-typo-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "typo", zenzai: model)
        let service = ZenzaiTypoService(zenzai: model, memoryDirectory: directory, versionString: "typo")
        // macOS の綴りの候補のように，読めない並びのどの部分にも近い英単語を返す
        let tails = (1...keys.count).map { String(keys.suffix($0)) } + (1...keys.count).map { String(keys.prefix($0)) }
        let lexicon = FakeLexicon(suggestions: Dictionary(uniqueKeysWithValues: Set(tails).map { ($0, ["bit", "kit", "epulo", "absi"]) }))
        let session = InputSession(converter: engine.makeSession(), lexicon: lexicon, settings: FakeSettings(), typoService: service)
        let typed = live(session, keys)
        var actions = session.settle(context: InputContext())
        if let request = session.correctionRequest {
            session.provideCorrections(await service.corrections(forKeys: request.keys, leftContext: request.leftContext))
        }
        actions += session.review(context: InputContext())
        let text = marked(actions) ?? typed ?? ""
        #expect(text == expected, "\(keys) → \(text)")
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
