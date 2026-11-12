import Foundation
import HajimeApplication
import HajimeDomain
import HajimeIPC
import HajimeTestSupport
import Testing

/// 絵文字と記号のパレット(R-26)を，Windows のエンジンのプロセスで出し入れする
@MainActor
@Suite("エンジンのプロセスのパレット")
struct EnginePaletteTests {
    private let settings: FakeSettings
    private let service: EngineService
    private let sent: Box<[WireUiCommand]>

    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private static let table = [
        ["emoji", "people", "🙇", "0.6", "おじぎする人", "おじぎするひと", "person bowing", "おじぎ", "bow", "bow", ""],
        ["emoji", "people", "👍", "0.6", "サムズアップ", "さむずあっぷ", "thumbs up", "いいね", "good", "+1|thumbsup", ""],
        ["symbol", "arrows", "→", "", "右向矢印", "みぎむきやじるし", "rightwards arrow", "やじるし", "arrow", "", ""],
        ["kaomoji", "greeting", "m(_ _)m", "", "ぺこり", "ぺこり", "", "ぺこり|おじぎ", "", "", ""],
    ].map { $0.joined(separator: "\t") }.joined(separator: "\n")

    init() {
        var initial = DefaultSettings.settings
        initial.liveConversion = false
        initial.paletteCellSize = 40
        let settings = FakeSettings(initial)
        let sent = Box<[WireUiCommand]>([])
        let catalog = FakePaletteCatalog(Self.table)
        let usage = FakePaletteUsageStore()
        let palette = PaletteServices(catalog: catalog, usage: usage, now: { Date(timeIntervalSince1970: 1_800_000_000) })
        self.settings = settings
        self.sent = sent
        self.service = EngineService(
            makeSession: { InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: settings, keyNames: .windows, palette: palette) },
            settings: settings,
            ui: { sent.value.append($0) },
            openSettings: {}
        )
    }

    private static let plain = WireModifiers(shift: false, control: false, alt: false)
    private static let field = WireFieldContext(applicationId: "notepad.exe", isSecure: false, caret: WireRect(x: 10, y: 20, width: 1, height: 16))

    private func connect(isCandidateWindow: Bool = false) -> EngineService.ConnectionID {
        let id = service.connect(isCandidateWindow: isCandidateWindow)
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        return id
    }

    private func open(_ id: EngineService.ConnectionID) throws -> UInt32 {
        guard case .sessionOpened(let session, _) = service.handle(WireRequest(id: 2, body: .openSession), from: id).body else {
            Issue.record("セッションを作れない")
            throw CancellationError()
        }
        return session
    }

    private func press(_ key: WireKey, _ modifiers: WireModifiers = plain, session: UInt32, from id: EngineService.ConnectionID) -> WireResponseBody {
        service.handle(WireRequest(id: 3, body: .key(session: session, input: WireKeyInput(key: key, modifiers: modifiers, isKeypad: false), context: Self.field)),
                       from: id).body
    }

    private func type(_ text: String, session: UInt32, from id: EngineService.ConnectionID) {
        for character in text { _ = press(.character(text: String(character)), session: session, from: id) }
    }

    private var shownPanel: WirePalettePanel? {
        for command in sent.value.reversed() {
            if case .showPalette(let panel, _) = command { return panel }
            if case .hidePalette = command { return nil }
        }
        return nil
    }

    /// ⌃⌥E(Windows は Ctrl+Alt+E)でパレットを開く
    private func openPalette(session: UInt32, from id: EngineService.ConnectionID) -> WireResponseBody {
        press(.character(text: "e"), WireModifiers(shift: false, control: true, alt: true), session: session, from: id)
    }

    @Test("R-26: Ctrl+Alt+E でパレットを候補ウィンドウに出し，開いているあいだは DLL にすべてのキーを送ってもらう")
    func opens() throws {
        let id = connect()
        let session = try open(id)
        guard case .edit(true, _, let state) = openPalette(session: session, from: id) else {
            Issue.record("パレットのキーを受けない")
            return
        }
        #expect(state.isComposing)
        #expect(state.wakeAfterMilliseconds.map { $0 <= EngineService.candidateClickPollMilliseconds } == true)
        let panel = try #require(shownPanel)
        #expect(panel.cellSize == 40)
        #expect(panel.rows.first?.cells.map(\.text) == ["🙇", "👍"])
        #expect(panel.hints.first?.keys == "Enter")
    }

    @Test("R-26: 探して Enter で選んだ文字を確定し，パレットを閉じる")
    func searchAndInsert() throws {
        let id = connect()
        let session = try open(id)
        _ = openPalette(session: session, from: id)
        type("ojigi", session: session, from: id)
        #expect(shownPanel?.query == "おじぎ")
        guard case .edit(true, let operations, let state) = press(.enter, session: session, from: id) else {
            Issue.record("Enter を受けない")
            return
        }
        #expect(operations.contains(.commit(text: "🙇")))
        #expect(sent.value.last == .hidePalette)
        #expect(!state.isComposing)
    }

    @Test("R-26: 候補ウィンドウでパレットを押した対象は，出しているセッションの次の wake で処理する．ほかの接続からは受けない")
    func pointer() throws {
        let id = connect()
        let session = try open(id)
        let window = connect(isCandidateWindow: true)
        let click = WireRequestBody.choosePalette(target: .cell(row: 0, column: 1))
        // 出していないときは受けない
        #expect(service.handle(WireRequest(id: 10, body: click), from: window).body == .error(code: .malformed))
        _ = openPalette(session: session, from: id)
        #expect(service.handle(WireRequest(id: 11, body: click), from: id).body == .error(code: .malformed))
        #expect(service.handle(WireRequest(id: 12, body: .choosePalette(target: .hover(row: 0, column: 1))), from: window).body == .done)
        #expect(service.handle(WireRequest(id: 13, body: click), from: window).body == .done)
        // 知らないまとまりは無視する
        #expect(service.handle(WireRequest(id: 14, body: .choosePalette(target: .tab(section: "unknown"))), from: window).body == .done)
        guard case .edit(_, let operations, _) = service.handle(WireRequest(id: 15, body: .wake(session: session, context: Self.field)), from: id).body else {
            Issue.record("wake に答えない")
            return
        }
        #expect(operations.contains(.commit(text: "👍")))
        #expect(sent.value.last == .hidePalette)
    }

    @Test("R-26: 顔文字に切り替えると，1 行の広いマスの数を添えて送る．四角いマスなら省く")
    func kaomoji() throws {
        let id = connect()
        let session = try open(id)
        let window = connect(isCandidateWindow: true)
        _ = openPalette(session: session, from: id)
        #expect(shownPanel?.cellsPerRow == nil)
        #expect(shownPanel?.modes.map(\.kind) == [.emoji, .symbol, .kaomoji])
        #expect(service.handle(WireRequest(id: 10, body: .choosePalette(target: .mode(kind: .kaomoji))), from: window).body == .done)
        _ = service.handle(WireRequest(id: 11, body: .wake(session: session, context: Self.field)), from: id)
        let panel = try #require(shownPanel)
        #expect(panel.modes.first { $0.isSelected }?.kind == .kaomoji)
        #expect(panel.columns == UInt32(DefaultSettings.paletteColumns))
        #expect(panel.cellsPerRow == UInt32(DefaultSettings.paletteColumns / DefaultSettings.paletteWideCellSpan))
        #expect(panel.rows.first?.cells.map(\.text) == ["m(_ _)m"])
    }

    @Test("R-26: セッションを閉じたら，そのセッションが出していたパレットを閉じる")
    func closesWithSession() throws {
        let id = connect()
        let session = try open(id)
        _ = openPalette(session: session, from: id)
        sent.value.removeAll()
        _ = service.handle(WireRequest(id: 20, body: .closeSession(session: session)), from: id)
        #expect(sent.value.contains(.hidePalette))
    }

    @Test("R-26: パレットを渡していないエンジンでは，パレットのキーを受けない")
    func unavailable() throws {
        let plainService = EngineService(
            makeSession: { [settings] in InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: settings) },
            settings: settings, ui: { _ in }, openSettings: {})
        let id = plainService.connect()
        _ = plainService.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        guard case .sessionOpened(let session, _) = plainService.handle(WireRequest(id: 2, body: .openSession), from: id).body else {
            Issue.record("セッションを作れない")
            return
        }
        let body = plainService.handle(WireRequest(id: 3, body: .key(session: session, input: WireKeyInput(
            key: .character(text: "e"), modifiers: WireModifiers(shift: false, control: true, alt: true), isKeypad: false), context: Self.field)), from: id).body
        guard case .edit(let handled, _, _) = body else {
            Issue.record("edit で答えない")
            return
        }
        #expect(!handled)
    }
}

@MainActor
@Suite("設定の画面からパレットの記録を消す")
struct EnginePaletteHistoryTests {
    @Test("R-26: 設定の画面の頼みで，パレットで使った文字の記録を消す")
    func resetsHistory() {
        var cleared = 0
        let settings = FakeSettings(DefaultSettings.settings)
        let service = EngineService(
            makeSession: { InputSession(converter: FakeConverter(), lexicon: FakeLexicon(), settings: settings) },
            settings: settings, ui: { _ in }, openSettings: {},
            services: SettingsServices(resetPaletteHistory: { cleared += 1 }))
        let id = service.connect(isSettingsApp: true)
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        #expect(service.handle(WireRequest(id: 2, body: .resetPaletteHistory), from: id).body == .done)
        #expect(cleared == 1)
    }
}
