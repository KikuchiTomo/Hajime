import HajimeApplication
import HajimeDomain
import HajimeIPC
import HajimeTestSupport
import Testing

/// Windows のエンジンで，長い文をまとまりに区切って候補ウィンドウに送り，押した文節(山形を含む)を文の全体の位置で受けて移る
@MainActor
@Suite("Windows のエンジン: 長い文のまとまり")
struct EngineSegmentGroupTests {
    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    private let sent = Box<[WireUiCommand]>([])
    private let service: EngineService
    private static let plain = WireModifiers(shift: false, control: false, alt: false)
    private static let field = WireFieldContext(applicationId: "notepad.exe", isSecure: false, caret: WireRect(x: 10, y: 20, width: 1, height: 16))

    init() {
        let reading = "あいうえお"
        let converter = FakeConverter([reading: [("亜胃鵜絵尾", nil)], "あ": [("亜", nil)], "い": [("胃", nil)], "う": [("鵜", nil)], "え": [("絵", nil)],
                                       "お": [("尾", nil)]])
        converter.words[reading] = ["亜", "胃", "鵜", "絵", "尾"].map { Candidate.Word(text: $0, readingCount: 1) }
        var initial = DefaultSettings.settings
        initial.liveConversion = false
        initial.branchSegmentsPerGroup = 3
        initial.initialFocus = .start
        let settings = FakeSettings(initial)
        let sent = sent
        service = EngineService(
            makeSession: {
                InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings, keyNames: .windows, groupsBranchSegments: true)
            },
            settings: settings, ui: { sent.value.append($0) }, openSettings: { _ in })
    }

    private var shownMap: WireBranchMap? {
        for command in sent.value.reversed() {
            if case .showBranchMap(let map, _) = command { return map }
        }
        return nil
    }

    private var focused: Int? { shownMap?.columns.firstIndex(where: \.isFocused) }

    @Test("文節は文の全体を送り，出すまとまりの範囲を添える．押した文節と山形は文の全体の位置で受けて移る")
    func groups() throws {
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
        func click(_ index: UInt32) {
            _ = service.handle(WireRequest(id: 4, body: .chooseCandidate(target: .segment(index: index))), from: window)
            _ = service.handle(WireRequest(id: 5, body: .wake(session: session, context: Self.field)), from: id)
        }
        for character in "aiueo" { press(.character(text: String(character))) }
        press(.space)
        let first = try #require(shownMap)
        #expect(first.columns.count == 5)
        #expect(first.groupStart == 0 && first.groupEnd == 3 && first.continuesBefore == nil && first.continuesAfter == true)
        // 文節へ移るキーは，出しているまとまりの中で左から数える(Windows のキーの名前)
        #expect(first.columns.map(\.jumpKey) == ["Alt+A", "Alt+S", "Alt+D", nil, nil])
        // 後ろへ続く山形を押すと(候補ウィンドウは文の全体の位置 3 を返す)，次のまとまりの最初の文節へ移る
        click(3)
        let second = try #require(shownMap)
        #expect(focused == 3)
        #expect(second.groupStart == 3 && second.groupEnd == 5 && second.continuesBefore == true && second.continuesAfter == nil)
        #expect(second.columns.map(\.jumpKey) == [nil, nil, nil, "Alt+A", "Alt+S"])
        // まとまりの中の文節を押すと，その文節へ移る(文の全体の位置 4)
        click(4)
        #expect(focused == 4)
        // 前へ続く山形(位置 2)を押すと，前のまとまりへ戻る
        click(2)
        #expect(focused == 2 && shownMap?.groupStart == 0)
    }
}
