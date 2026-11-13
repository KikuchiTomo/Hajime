import HajimeApplication
import HajimeDomain
import HajimeIPC
import HajimeTestSupport
import Testing

/// Windows のエンジンで，先の枝の丸を候補ウィンドウに送り，候補ウィンドウが知らせた枝の向き(branchLayout)で矢印キーを効かせる
@MainActor
@Suite("Windows のエンジン: 先の枝の丸")
struct EngineBranchStationTests {
    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private static let dictionary = AssociationDictionary(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "類語", groupCount: 1)
    private static let plain = WireModifiers(shift: false, control: false, alt: false)
    private static let field = WireFieldContext(applicationId: "notepad.exe", isSecure: false, caret: WireRect(x: 10, y: 20, width: 1, height: 16))

    private let sent = Box<[WireUiCommand]>([])
    private let service: EngineService

    init() {
        let converter = FakeConverter(["うつくしい": [("美しい", nil), ("美しき", nil)]], clauses: ["うつくしい": [("美しい", 5), ("美しき", 5)]])
        let lookup = FakeAssociationLookup([Self.dictionary.id: ["美しい": [AssociationGroup(label: "見た目が快い", words: ["綺麗", "華麗"])]]])
        var initial = DefaultSettings.settings
        initial.associationDictionaries = [Self.dictionary]
        initial.conversionMacros = true
        initial.liveConversion = false
        let settings = FakeSettings(initial)
        let sent = sent
        service = EngineService(
            makeSession: {
                InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings, associations: lookup, keyNames: .windows,
                             branchStations: true)
            },
            settings: settings, ui: { sent.value.append($0) }, openSettings: { _ in })
    }

    private var shownMap: WireBranchMap? {
        for command in sent.value.reversed() {
            if case .showBranchMap(let map, _) = command { return map }
        }
        return nil
    }

    @Test("丸の並びと今いる丸を送る．候補ウィンドウが枝を左へ出していると知らせたら，← で丸へ入り → で戻る．入力欄の側からは知らせられない")
    func mirrored() throws {
        let id = service.connect()
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        guard case .sessionOpened(let session, _) = service.handle(WireRequest(id: 2, body: .openSession), from: id).body else {
            Issue.record("セッションを作れない")
            return
        }
        let window = service.connect(isCandidateWindow: true)
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: window)
        func press(_ key: WireKey) {
            _ = service.handle(WireRequest(id: 3, body: .key(session: session, input: WireKeyInput(key: key, modifiers: Self.plain, isKeypad: false),
                                                             context: Self.field)), from: id)
        }
        for character in "utukusii" { press(.character(text: String(character))) }
        press(.space)
        let detail = try #require(shownMap?.detail)
        #expect(detail.stations.map(\.kind) == [.association, .macro])
        #expect(detail.current == nil)

        // 入力欄の側(候補ウィンドウでない口)からの知らせは受けない
        #expect(service.handle(WireRequest(id: 4, body: .branchLayout(mirrored: true)), from: id).body == .error(code: .malformed))
        #expect(service.handle(WireRequest(id: 5, body: .branchLayout(mirrored: true)), from: window).body == .done)
        press(.left)
        #expect(shownMap?.detail?.current == 0)
        #expect(shownMap?.detail?.items == ["綺麗", "華麗"])
        press(.right)
        #expect(shownMap?.detail?.current == nil)

        // 右へ出していると知らせ直したら，→ で丸へ入る
        _ = service.handle(WireRequest(id: 6, body: .branchLayout(mirrored: false)), from: window)
        press(.right)
        #expect(shownMap?.detail?.current == 0)
    }
}
