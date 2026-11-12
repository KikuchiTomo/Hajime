import HajimeApplication
import HajimeDomain
import HajimeIPC
import HajimeTestSupport
import Testing

/// Windows の DLL が受け取る組み立て中の文字の流れ(ライブ変換)．打鍵が止まったら DLL の wake で変換して見せ，
/// 続けて打っても，変換して見せた文をかなに戻さない(macOS と同じに，かなと漢字が入れ替わってちらつかない)
@MainActor
@Suite("エンジンのプロセスのライブ変換の表示")
struct EngineServiceLiveConversionTests {
    /// DLL のタイマーのように，前の応答で頼まれた間隔(wakeAfterMilliseconds)だけ進む時計
    final class Clock {
        var now = ContinuousClock.now
    }

    private let service: EngineService
    private let clock = Clock()

    init() {
        var initial = DefaultSettings.settings
        initial.liveConversion = true
        let settings = FakeSettings(initial)
        let converter = FakeConverter([
            "きょうはらい": [("今日は雷", nil)],
            "きょうはらいぶ": [("今日はライブ", nil)],
        ])
        converter.trailingWords["今日は雷"] = .init(readingCount: 2, textCount: 1)
        converter.trailingWords["今日はライブ"] = .init(readingCount: 3, textCount: 3)
        let clock = clock
        service = EngineService(
            makeSession: { InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings) },
            settings: settings, ui: { _ in }, openSettings: { _ in }, now: { clock.now }
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

    /// 1 回の応答で DLL が組み立て中の文字に書く文字の並び(確定はしないこと)
    private static func compositions(_ body: WireResponseBody) -> [String] {
        guard case .edit(_, let operations, _) = body else { return [] }
        return operations.compactMap { operation -> String? in
            switch operation {
            case .setComposition(let segments, _, _, _): segments.map(\.text).joined()
            case .commit: "<確定>"
            default: nil
            }
        }
    }

    private static func wakeAfter(_ body: WireResponseBody) -> UInt32? {
        guard case .edit(_, _, let state) = body else { return nil }
        return state.wakeAfterMilliseconds
    }

    private func press(_ character: Character, _ session: UInt32, _ id: EngineService.ConnectionID) -> WireResponseBody {
        let input = WireKeyInput(key: .character(text: String(character)), modifiers: Self.plain, isKeypad: false)
        return service.handle(WireRequest(id: 3, body: .key(session: session, input: input, context: Self.field)), from: id).body
    }

    /// 打鍵が止まったあと，DLL が頼まれた間隔で wake して出す文字の並び
    private func pause(after body: WireResponseBody, _ session: UInt32, _ id: EngineService.ConnectionID) -> [String] {
        var shown: [String] = []
        var wait = Self.wakeAfter(body)
        var elapsed = 0
        while let current = wait, elapsed < 2000 {
            clock.now = clock.now + .milliseconds(Int(current))
            elapsed += Int(max(current, 1))
            let woke = service.handle(WireRequest(id: 4, body: .wake(session: session, context: Self.field)), from: id).body
            shown += Self.compositions(woke)
            wait = Self.wakeAfter(woke)
        }
        return shown
    }

    @Test("打鍵が止まって変換して見せた文は，続けて打ってもかなに戻さず，組み立て中のまま")
    func keepsConvertedTextWhileTyping() throws {
        let (id, session) = try open()
        var typed: [String] = []
        for character in "kyouhara" { typed += Self.compositions(press(character, session, id)) }
        let last = press("i", session, id)
        typed += Self.compositions(last)
        // 止まる前は末尾の短い語をかなのまま見せる
        #expect(typed.last == "今日はらい")
        #expect(pause(after: last, session, id).last == "今日は雷")
        // 続けて打つ．1 打鍵ごとの書き込みに，かなに戻した「今日はらい…」が挟まらない
        let consonant = Self.compositions(press("b", session, id))
        #expect(consonant == ["今日は雷b"])
        let vowel = Self.compositions(press("u", session, id))
        #expect(vowel == ["今日はライブ"])
        #expect(!(consonant + vowel).contains { $0.hasPrefix("今日はらい") || $0 == "<確定>" })
    }
}
