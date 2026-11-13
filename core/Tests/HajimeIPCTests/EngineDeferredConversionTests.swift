import HajimeApplication
import HajimeDomain
import HajimeIPC
import HajimeTestSupport
import Testing

/// 打鍵の合間の Zenzai の変換(performDeferredConversion)が打鍵の間隔より長くかかる入力では，合間に求めず打鍵が止まってから求める(Windows)
@MainActor
@Suite("打鍵の合間の変換を次の打鍵に待たせない")
struct EngineDeferredConversionTests {
    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private let converter = FakeConverter()
    private let clock = Box<ContinuousClock.Instant>(ContinuousClock.now)
    private let service: EngineService
    private static let plain = WireModifiers(shift: false, control: false, alt: false)
    private static let field = WireFieldContext(applicationId: "notepad.exe", isSecure: false, caret: WireRect(x: 10, y: 20, width: 1, height: 16))

    init() {
        var initial = DefaultSettings.settings
        initial.liveConversion = true
        let settings = FakeSettings(initial)
        let converter = converter
        let clock = clock
        converter.defersWhileTyping = true
        service = EngineService(
            makeSession: { InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings, keyNames: .windows) },
            settings: settings, ui: { _ in }, openSettings: { _ in }, now: { clock.value })
    }

    private func open() throws -> (EngineService.ConnectionID, UInt32) {
        let id = service.connect()
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        guard case .sessionOpened(let session, _) = service.handle(WireRequest(id: 2, body: .openSession), from: id).body else {
            Issue.record("セッションを作れない")
            throw CancellationError()
        }
        return (id, session)
    }

    private func wakeAfter(_ body: WireResponseBody) -> UInt32? {
        guard case .edit(_, _, let state) = body else { return nil }
        return state.wakeAfterMilliseconds
    }

    private func press(_ key: WireKey, session: UInt32, from id: EngineService.ConnectionID) -> UInt32? {
        wakeAfter(service.handle(WireRequest(id: 3, body: .key(session: session, input: WireKeyInput(key: key, modifiers: Self.plain, isKeypad: false),
                                                                context: Self.field)), from: id).body)
    }

    private func wake(session: UInt32, from id: EngineService.ConnectionID) -> UInt32? {
        wakeAfter(service.handle(WireRequest(id: 4, body: .wake(session: session, context: Self.field)), from: id).body)
    }

    @Test("合間の変換が長くかかったら，その入力のあいだは打鍵が止まってから求め，入力を終えたらまた合間に求める")
    func waitsForPause() throws {
        let (id, session) = try open()
        // 速いうちは，打鍵のすぐあとに来てもらって合間に求める
        #expect(press(.character(text: "a"), session: session, from: id) == EngineService.deferredConversionPollMilliseconds)
        // 合間の変換が打鍵の間隔より長くかかった
        converter.onDeferredConversion = { [clock] in clock.value += .milliseconds(Int(DefaultSettings.deferredConversionBudget * 1000) + 50) }
        _ = wake(session: session, from: id)
        #expect(converter.deferredConversionCount == 1)

        // 次の打鍵からは，打鍵が止まったときに来てもらう(打鍵のすぐあとには求めない)
        let delay = try #require(press(.character(text: "i"), session: session, from: id))
        #expect(delay > EngineService.deferredConversionPollMilliseconds)
        _ = wake(session: session, from: id)
        #expect(converter.deferredConversionCount == 1)

        // 打鍵が止まったら求める(打ち切らない)
        clock.value += .seconds(DefaultSettings.liveConversionSettleDelay)
        _ = wake(session: session, from: id)
        #expect(converter.deferredConversionCount == 2)

        // 入力を終えたら，次の入力はまた合間に求める
        converter.onDeferredConversion = nil
        _ = press(.enter, session: session, from: id)
        #expect(press(.character(text: "u"), session: session, from: id) == EngineService.deferredConversionPollMilliseconds)
    }
}
