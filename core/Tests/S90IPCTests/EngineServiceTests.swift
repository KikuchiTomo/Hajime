import S90Application
import S90Domain
import S90IPC
import S90TestSupport
import Testing

@MainActor
@Suite("エンジンのプロセスの要求の扱い")
struct EngineServiceTests {
    private let settings: FakeSettings
    private let service: EngineService
    private let sent: Box<[WireUiCommand]>
    private let opened: Box<Int>

    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    init() {
        var initial = DefaultSettings.settings
        initial.liveConversion = false
        let settings = FakeSettings(initial)
        let sent = Box<[WireUiCommand]>([])
        let opened = Box(0)
        let converter = FakeConverter(["かな": [("仮名", nil)]])
        self.settings = settings
        self.sent = sent
        self.opened = opened
        self.service = EngineService(
            makeSession: { InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings) },
            settings: settings,
            ui: { sent.value.append($0) },
            openSettings: { opened.value += 1 }
        )
    }

    private static let plain = WireModifiers(shift: false, control: false, alt: false)
    private static let field = WireFieldContext(applicationId: "notepad.exe", isSecure: false, caret: WireRect(x: 10, y: 20, width: 1, height: 16))

    private func greeted() -> EngineService.ConnectionID {
        let id = service.connect()
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        return id
    }

    private func open(_ id: EngineService.ConnectionID) throws -> UInt32 {
        let response = service.handle(WireRequest(id: 2, body: .openSession), from: id)
        guard case .sessionOpened(let session, _) = response.body else {
            Issue.record("セッションを作れない: \(response.body)")
            throw CancellationError()
        }
        return session
    }

    private func type(_ text: String, session: UInt32, from id: EngineService.ConnectionID) -> [WireResponseBody] {
        text.map { character in
            service.handle(WireRequest(id: 3, body: .key(session: session, input: WireKeyInput(key: .character(text: String(character)), modifiers: Self.plain, isKeypad: false),
                                                         context: Self.field)), from: id).body
        }
    }

    private func press(_ key: WireKey, session: UInt32, from id: EngineService.ConnectionID) -> WireResponseBody {
        service.handle(WireRequest(id: 4, body: .key(session: session, input: WireKeyInput(key: key, modifiers: Self.plain, isKeypad: false), context: Self.field)), from: id).body
    }

    @Test("版を確かめる前の要求と，版の違う DLL は断る")
    func version() {
        let id = service.connect()
        #expect(service.handle(WireRequest(id: 1, body: .openSession), from: id).body == .error(code: .unsupportedVersion))
        #expect(service.handle(WireRequest(id: 2, body: .hello(protocolVersion: WireProtocol.version + 1)), from: id).body == .error(code: .unsupportedVersion))
        let response = service.handle(WireRequest(id: 3, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        #expect(response == WireResponse(id: 3, body: .hello(protocolVersion: WireProtocol.version)))
    }

    @Test("打った読みを組み立て中の文字にし，変換して確定する")
    func compose() throws {
        let id = greeted()
        let session = try open(id)
        let typed = type("kana", session: session, from: id)
        guard case .edit(let handled, let operations, let state) = typed.last else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(handled)
        #expect(operations == [.setComposition(segments: [WireTextSegment(text: "かな", style: .reading)])])
        #expect(state.isComposing)
        #expect(state.consumedKeys.isEmpty)

        guard case .edit(_, _, _) = press(.space, session: session, from: id) else {
            Issue.record("変換できない")
            return
        }
        #expect(sent.value.contains {
            switch $0 {
            case .showCandidates(_, let anchor), .showBranchMap(_, let anchor): anchor == Self.field.caret
            default: false
            }
        })

        guard case .edit(_, let committed, let after) = press(.enter, session: session, from: id) else {
            Issue.record("確定できない")
            return
        }
        #expect(committed.contains(.commit(text: "仮名")))
        #expect(!after.isComposing)
        #expect(sent.value.last == .hide)
    }

    @Test("ほかの接続のセッションは使えない")
    func otherConnection() throws {
        let first = greeted()
        let second = greeted()
        let session = try open(first)
        #expect(press(.space, session: session, from: second) == .error(code: .unknownSession))
        #expect(service.handle(WireRequest(id: 5, body: .closeSession(session: session)), from: second).body == .error(code: .unknownSession))
    }

    @Test("接続が切れたらその接続のセッションを捨てる")
    func disconnect() throws {
        let id = greeted()
        _ = try open(id)
        _ = try open(id)
        #expect(service.sessionCount == 2)
        service.disconnect(id)
        #expect(service.sessionCount == 0)
    }

    @Test("1 つの接続が作れるセッションには上限がある")
    func sessionLimit() throws {
        let id = greeted()
        for _ in 0..<EngineService.maximumSessionsPerConnection {
            _ = try open(id)
        }
        #expect(service.handle(WireRequest(id: 6, body: .openSession), from: id).body == .error(code: .tooManySessions))
    }

    @Test("パスワード欄では何もしない")
    func secure() throws {
        let id = greeted()
        let session = try open(id)
        let body = service.handle(WireRequest(id: 7, body: .key(session: session, input: WireKeyInput(key: .character(text: "k"), modifiers: Self.plain, isKeypad: false),
                                                               context: WireFieldContext(isSecure: true))), from: id).body
        guard case .edit(let handled, let operations, _) = body else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(!handled)
        #expect(operations.isEmpty)
    }

    @Test("ライブ変換を待つ時間を返し，wake で表示を変える")
    func wake() throws {
        try settings.update { $0.liveConversion = true }
        let id = greeted()
        let session = try open(id)
        guard case .edit(_, _, let state) = type("kana", session: session, from: id).last else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(state.wakeAfterMilliseconds == UInt32((settings.current.liveConversionDelay * 1000).rounded()))
        let woke = service.handle(WireRequest(id: 8, body: .wake(session: session, context: Self.field)), from: id).body
        guard case .edit(let handled, _, _) = woke else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(handled)
    }

    @Test("見た目の設定は設定の値を運ぶ")
    func presentation() {
        #expect(service.presentation.theme == settings.current.theme.rawValue)
        #expect(service.presentation.fontSize == settings.current.candidateFontSize)
    }
}
