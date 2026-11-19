import HajimeApplication
import HajimeDomain
import HajimeIPC
import HajimeTestSupport
import Testing

/// 打鍵が止まってから予測を出す設定(Windows)．DLL に予測を出す時機に来てもらい(wake)，来たときに出す．キーの応答では待たない
@MainActor
@Suite("予測を出す時機に来てもらう")
struct EnginePredictionTimingTests {
    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private let clock = Box<ContinuousClock.Instant>(ContinuousClock.now)
    private let sent = Box<[WireUiCommand]>([])
    private let settings: FakeSettings
    private let service: EngineService
    private static let plain = WireModifiers(shift: false, control: false, alt: false)
    private static let field = WireFieldContext(applicationId: "notepad.exe", isSecure: false, caret: WireRect(x: 10, y: 20, width: 1, height: 16))

    init() {
        var initial = DefaultSettings.settings
        initial.liveConversion = false
        initial.predictionDisplay = .afterPause
        initial.predictionDelay = 1.2
        // 予測より先に来てもらう用事(打ち間違いの見直し)を無くし，予測の時機だけを確かめる
        initial.typoCorrection = .off
        initial.misreadings = false
        // 候補の窓を出しているあいだは押した候補を取りに短い間隔で来てもらうので，出さない
        initial.suggestionDisplay = .off
        let settings = FakeSettings(initial)
        self.settings = settings
        let converter = FakeConverter(["えぴ": [("エピ", nil), ("えぴ", nil)]])
        converter.predictionTexts["えぴ"] = ["エピ", "エピソード"]
        let clock = clock
        let sent = sent
        service = EngineService(
            makeSession: { InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings, keyNames: .windows) },
            settings: settings, ui: { sent.value.append($0) }, openSettings: { _ in }, now: { clock.value })
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

    private func type(_ text: String, session: UInt32, from id: EngineService.ConnectionID) -> UInt32? {
        var last: UInt32?
        for character in text {
            last = wakeAfter(service.handle(WireRequest(id: 3, body: .key(session: session, input: WireKeyInput(key: .character(text: String(character)), modifiers: Self.plain,
                                                                                                             isKeypad: false), context: Self.field)), from: id).body)
        }
        return last
    }

    /// あとから求めて足す処理などの短い用事を済ませ，次に来てもらうまでの時間を返す
    private func drain(session: UInt32, from id: EngineService.ConnectionID) -> UInt32? {
        var wait: UInt32?
        for _ in 0..<50 {
            wait = wakeAfter(service.handle(WireRequest(id: 4, body: .wake(session: session, context: Self.field)), from: id).body)
            if (wait ?? .max) > 200 { break }
        }
        return wait
    }

    private var shownPredictions: [WirePrediction?] {
        sent.value.compactMap { command -> WirePrediction?? in
            if case .showPrediction(let prediction, _) = command { .some(prediction) } else { nil }
        }
    }

    @Test("打ったときは予測を出さず，設定の時間のあとに来てもらい，来たときに出す．打ち足すと待ち直す")
    func revealsOnWake() throws {
        let (id, session) = try open()
        let first = try #require(type("epi", session: session, from: id))
        #expect(first <= 1200)
        #expect(shownPredictions.allSatisfy { $0 == nil })
        // 設定の時間の前に来ても出さない
        clock.value += .milliseconds(500)
        let wait = try #require(drain(session: session, from: id))
        #expect(wait <= 700 && wait > 600)
        #expect(shownPredictions.allSatisfy { $0 == nil })
        // 設定の時間がたったら出す
        clock.value += .milliseconds(700)
        _ = drain(session: session, from: id)
        #expect(shownPredictions.last??.completion == "ソード")
        // 出したあとは，予測のためには来てもらわない
        sent.value = []
        _ = drain(session: session, from: id)
        #expect(shownPredictions.isEmpty)
    }

    @Test("セッションを閉じたら，出していた予測の窓を消す(予測の窓は候補の窓を消す指示では消えない)")
    func closingSessionHidesPrediction() throws {
        let (id, session) = try open()
        _ = type("epi", session: session, from: id)
        clock.value += .milliseconds(1300)
        _ = drain(session: session, from: id)
        #expect(shownPredictions.last??.completion == "ソード")
        sent.value = []
        _ = service.handle(WireRequest(id: 5, body: .closeSession(session: session)), from: id)
        #expect(sent.value.contains(.showPrediction(prediction: nil, anchor: nil)))
    }

    @Test("アプリが落ちて接続が切れたときも，出していた予測の窓を消す")
    func disconnectHidesPrediction() throws {
        let (id, session) = try open()
        _ = type("epi", session: session, from: id)
        clock.value += .milliseconds(1300)
        _ = drain(session: session, from: id)
        sent.value = []
        service.disconnect(id)
        #expect(sent.value.contains(.showPrediction(prediction: nil, anchor: nil)))
        #expect(sent.value.contains(.hide))
    }
}
