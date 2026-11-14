import HajimeApplication
import HajimeDomain
import HajimeIPC
import HajimeTestSupport
import Testing

/// Windows のエンジン(エンジンのホストと同じ作り: 先の枝の丸とまとまりを使う)に決まったキーを順に渡し，
/// 候補ウィンドウへ送った分岐図で，今いる場所(文節・幹の上・文字種・丸・丸の中身)をたどる(R-17 の矢印キーで木をたどる)
@MainActor
@Suite("Windows のエンジン: 矢印キーで木をたどる")
struct EngineTreeNavigationTests {
    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private static let dictionary = AssociationDictionary(id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", name: "類語", groupCount: 1)
    private static let plain = WireModifiers(shift: false, control: false, alt: false)
    private static let field = WireFieldContext(applicationId: "notepad.exe", isSecure: false, caret: WireRect(x: 10, y: 20, width: 1, height: 16))

    private let sent = Box<[WireUiCommand]>([])
    private let service: EngineService
    private let session: UInt32
    private let input: EngineService.ConnectionID
    private let window: EngineService.ConnectionID

    init() throws {
        let long = "あいうえおかきくけ"
        let converter = FakeConverter(["うつくしい": [("美しい", nil), ("美しき", nil)], long: [("亜胃鵜絵尾蚊木区毛", nil)]],
                                      clauses: ["うつくしい": [("美しい", 5), ("美しき", 5)]])
        converter.words[long] = ["亜", "胃", "鵜", "絵", "尾", "蚊", "木", "区", "毛"].map { Candidate.Word(text: $0, readingCount: 1) }
        let lookup = FakeAssociationLookup([Self.dictionary.id: ["美しい": [AssociationGroup(label: "見た目が快い", words: ["綺麗", "華麗"])]]])
        var initial = DefaultSettings.settings
        // 候補から始めて木をたどる動きを確かめる(変換の直後に幹の上から始める設定は，別のテストで確かめる)
        initial.branchStartsOnTrunk = false
        initial.associationDictionaries = [Self.dictionary]
        initial.conversionMacros = true
        initial.liveConversion = false
        initial.initialFocus = .start
        let settings = FakeSettings(initial)
        let sent = sent
        service = EngineService(
            makeSession: {
                InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings, associations: lookup, keyNames: .windows,
                             branchStations: true, groupsBranchSegments: true)
            },
            settings: settings, ui: { sent.value.append($0) }, openSettings: { _ in })
        input = service.connect()
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: input)
        guard case .sessionOpened(let opened, _) = service.handle(WireRequest(id: 2, body: .openSession), from: input).body else {
            throw CancellationError()
        }
        session = opened
        window = service.connect(isCandidateWindow: true)
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: window)
    }

    private var map: WireBranchMap? {
        for command in sent.value.reversed() {
            if case .showBranchMap(let map, _) = command { return map }
        }
        return nil
    }

    private var focused: WireBranchColumn? { map?.columns.first(where: \.isFocused) }
    private var focusedIndex: Int? { map?.columns.firstIndex(where: \.isFocused) }

    private func press(_ key: WireKey) {
        _ = service.handle(WireRequest(id: 3, body: .key(session: session, input: WireKeyInput(key: key, modifiers: Self.plain, isKeypad: false),
                                                         context: Self.field)), from: input)
    }

    private func type(_ romaji: String) {
        for character in romaji { press(.character(text: String(character))) }
        press(.space)
    }

    @Test("幹の上の ↑ で文字種の先頭へ，← → で文字種を移り，どの文字種からでも ↓ の 1 回で幹の上へ戻る")
    func variants() throws {
        type("utukusii")
        #expect(map?.trunkFocused != true && focused?.selectedAlternative == 0)
        press(.up)
        #expect(map?.trunkFocused == true)
        press(.up)
        #expect(map?.trunkFocused != true && focused?.selectedVariant == 0)
        press(.right)
        press(.right)
        #expect(focused?.selectedVariant == 2)
        press(.left)
        #expect(focused?.selectedVariant == 1)
        // 2 番目以降の文字種からでも，↓ の 1 回で幹の上へ戻る(前の文字種へは移らない)
        press(.down)
        #expect(map?.trunkFocused == true && focused?.selectedVariant == nil)
        // 幹の上の ↓ で候補へ下りる
        press(.down)
        #expect(map?.trunkFocused != true && focused?.selectedAlternative != nil)
    }

    @Test("候補の → で最初の丸へ，↓ で中身へ入り，↑ で丸へ，もう一度 ↑ で候補へ戻る")
    func stations() throws {
        type("utukusii")
        #expect(map?.detail?.stations.map(\.kind) == [.association, .macro])
        press(.right)
        #expect(map?.detail?.current == 0 && map?.detail?.selectedItem == nil)
        press(.right)
        #expect(map?.detail?.current == 1)
        press(.left)
        #expect(map?.detail?.current == 0)
        press(.down)
        #expect(map?.detail?.selectedItem == 0)
        press(.down)
        #expect(map?.detail?.selectedItem == 1)
        press(.up)
        press(.up)
        #expect(map?.detail?.current == 0 && map?.detail?.selectedItem == nil)
        press(.up)
        #expect(map?.detail?.current == nil && focused?.selectedAlternative == 0)
    }

    @Test("候補ウィンドウが反転を知らせたら，← で丸へ入って進み，→ で戻る")
    func mirrored() throws {
        type("utukusii")
        #expect(service.handle(WireRequest(id: 4, body: .branchLayout(mirrored: true)), from: window).body == .done)
        press(.left)
        #expect(map?.detail?.current == 0)
        press(.left)
        #expect(map?.detail?.current == 1)
        press(.right)
        press(.right)
        #expect(map?.detail?.current == nil)
    }

    @Test("9 文節の文で幹の上の → を続けると，8 文節のまとまりをまたいで次のまとまりへ移り，← で前のまとまりへ戻る")
    func groups() throws {
        type("aiueokakikuke")
        #expect(map?.columns.count == 9 && map?.groupStart == 0 && map?.groupEnd == 8 && map?.continuesAfter == true)
        // 候補の → は先の枝(変換マクロの丸)へ入るので，幹の上へ上って文節を移る
        press(.up)
        #expect(map?.trunkFocused == true)
        for _ in 0..<7 { press(.right) }
        #expect(focusedIndex == 7 && map?.groupStart == 0)
        press(.right)
        #expect(focusedIndex == 8 && map?.groupStart == 8 && map?.continuesBefore == true)
        // 文節へ移るキーは，出しているまとまりの中で左から数える
        #expect(focused?.jumpKey == "Alt+A")
        press(.left)
        #expect(focusedIndex == 7 && map?.groupStart == 0)
    }
}
