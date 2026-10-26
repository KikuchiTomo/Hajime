import S90Application
import S90Domain
@testable import S90IPC
import S90TestSupport
import Testing

/// 打ち間違いの訂正を別に求めるとき(Zenzai があるとき)の，エンジンのプロセスの流れ(R-02)．
/// DLL からは要求と応答しか無いので，訂正を求めているあいだは短い wake を頼み，求め終わったあとの wake で結果を返す
@MainActor
@Suite("エンジンのプロセスで打ち間違いの訂正を裏で求める")
struct EngineServiceCorrectionTests {
    /// 「youdesu」を「yoidesu」に直す訂正を返す．finishes が false なら取り消されるまで返さない
    struct Service: TypoCorrecting {
        var finishes = true

        func corrections(forKeys keys: [String], leftContext: String?) async -> [String: [ReadingCorrection]] {
            if !finishes {
                while !Task.isCancelled { await Task.yield() }
                return [:]
            }
            return ["youdesu": [
                ReadingCorrection(keys: "yoidesu", reading: "ヨイデス", score: -1, cost: 1),
                ReadingCorrection(keys: "youdesu", reading: "ヨウデス", score: -9, cost: 0),
            ]]
        }
    }

    final class Clock {
        var now = ContinuousClock.now
    }

    private let settings: FakeSettings
    private let service: EngineService
    private let clock = Clock()

    init(service typo: Service = Service(), liveConversion: Bool = false) {
        var initial = DefaultSettings.settings
        initial.liveConversion = liveConversion
        let settings = FakeSettings(initial)
        let converter = FakeConverter(["ようです": [("様です", nil)], "よいです": [("良いです", nil)]])
        let clock = clock
        self.settings = settings
        self.service = EngineService(
            makeSession: { InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings, typoService: typo) },
            settings: settings, ui: { _ in }, openSettings: {}, typoService: typo, now: { clock.now }
        )
    }

    private static let plain = WireModifiers(shift: false, control: false, alt: false)
    private static let field = WireFieldContext(applicationId: "notepad.exe", isSecure: false)

    private func open() throws -> (EngineService.ConnectionID, UInt32) {
        let id = service.connect()
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        guard case .sessionOpened(let session, _) = service.handle(WireRequest(id: 2, body: .openSession), from: id).body else {
            Issue.record("セッションを作れない")
            throw CancellationError()
        }
        return (id, session)
    }

    private func press(_ key: WireKey, _ session: UInt32, _ id: EngineService.ConnectionID) -> WireResponseBody {
        service.handle(WireRequest(id: 3, body: .key(session: session, input: WireKeyInput(key: key, modifiers: Self.plain, isKeypad: false), context: Self.field)), from: id).body
    }

    private func type(_ text: String, _ session: UInt32, _ id: EngineService.ConnectionID) {
        for character in text { _ = press(.character(text: String(character)), session, id) }
    }

    private func wake(_ session: UInt32, _ id: EngineService.ConnectionID) -> WireResponseBody {
        service.handle(WireRequest(id: 4, body: .wake(session: session, context: Self.field)), from: id).body
    }

    private static func composition(_ body: WireResponseBody) -> String? {
        guard case .edit(_, let operations, _) = body else { return nil }
        return operations.compactMap { operation -> String? in
            if case .setComposition(let segments) = operation { return segments.map(\.text).joined() }
            return nil
        }.last
    }

    private static func wakeAfter(_ body: WireResponseBody) -> UInt32? {
        guard case .edit(_, _, let state) = body else { return nil }
        return state.wakeAfterMilliseconds
    }

    @Test("Space で訂正を待つあいだは短い wake を頼み，求め終わったら直して変換する")
    func conversionWaitsForCorrections() async throws {
        let (id, session) = try open()
        type("youdesu", session, id)
        let space = press(.space, session, id)
        #expect(Self.composition(space) == nil)
        #expect(Self.wakeAfter(space) == EngineService.correctionPollMilliseconds)
        await service.waitForCorrections()
        let woke = wake(session, id)
        #expect(Self.composition(woke) == "良いです")
        #expect(Self.wakeAfter(woke) != EngineService.correctionPollMilliseconds)
    }

    @Test("訂正が長くかかるときは，期限を過ぎたら直さずに変換する")
    func conversionGivesUpAfterDeadline() throws {
        let test = EngineServiceCorrectionTests(service: Service(finishes: false))
        let (id, session) = try test.open()
        test.type("youdesu", session, id)
        _ = test.press(.space, session, id)
        let early = test.wake(session, id)
        #expect(Self.composition(early) == nil)
        #expect(Self.wakeAfter(early) == EngineService.correctionPollMilliseconds)
        test.clock.now = test.clock.now + .seconds(DefaultSettings.correctionWaitBeforeConversion + 1)
        #expect(Self.composition(test.wake(session, id)) == "様です")
    }

    @Test("待っているあいだに次のキーを打ったら，待たせていた変換はしない")
    func keyCancelsWaitingConversion() async throws {
        let (id, session) = try open()
        type("youdesu", session, id)
        _ = press(.space, session, id)
        _ = press(.character(text: "n"), session, id)
        await service.waitForCorrections()
        let woke = wake(session, id)
        #expect(Self.composition(woke) != "良いです")
    }

    @Test("打鍵が止まったら訂正を裏で求め，求め終わったあとの wake で見直して直す")
    func reviewUsesProvidedCorrections() async throws {
        let (id, session) = try open()
        type("youdesu", session, id)
        var marked: String?
        for _ in 0..<6 {
            let woke = wake(session, id)
            if let text = Self.composition(woke) { marked = text }
            await service.waitForCorrections()
        }
        #expect(marked == "よいです")
    }
}
