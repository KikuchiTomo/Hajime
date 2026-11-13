import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeIPC
import HajimePersistence

/// Windows のエンジン(EngineService)に，決まった間隔で打鍵を送ったときに，1 打鍵の返事がどれだけ遅れるかを測る．
/// DLL と同じく，返事の wakeAfterMilliseconds のあとに wake を送り，次の打鍵の時刻になったら打鍵を送る．
/// 打鍵の合間の処理(Zenzai で求め直すなど)が長いと，次の打鍵はその処理が終わるまで待たされる．
/// 1 行に，打鍵の番号・組み立て中の文字の数・遅れ(予定の時刻から返事まで，ms)・合間の wake の数・合間の処理の最長(ms)を出す．
/// 出すのは時間と長さと数だけ(入力した文字・読み・候補は出さない)
@MainActor
enum ServiceTyping {
    static func run(keys: String, repeats: Int, interval: Double, engine: AzooKeyConverterEngine) {
        engine.waitsForModels = false
        var settings = DefaultSettings.settings
        settings.liveConversion = true
        let store = TypingSettings(settings)
        let service = EngineService(
            makeSession: {
                let engineSession = engine.makeSession()
                let converter = SupplementedConverter(engineSession, settings: store, calendar: SystemCalendar(clock: { Date() }))
                return InputSession(converter: converter, lexicon: WordListLexicon(), settings: store, keyNames: .windows,
                                    scorer: engineSession, fusing: engineSession)
            },
            settings: store, ui: { _ in }, openSettings: { _ in })
        let id = service.connect()
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        guard case .sessionOpened(let session, _) = service.handle(WireRequest(id: 2, body: .openSession), from: id).body else { return }
        let field = WireFieldContext(applicationId: "playground.exe", isSecure: false, caret: WireRect(x: 10, y: 20, width: 1, height: 16))
        let plain = WireModifiers(shift: false, control: false, alt: false)
        let start = Date()
        func elapsed() -> Double { Date().timeIntervalSince(start) * 1000 }
        var shown = 0
        func read(_ body: WireResponseBody) -> UInt32? {
            guard case .edit(_, let operations, let state) = body else { return nil }
            for operation in operations {
                if case .setComposition(let segments, _, _, _) = operation { shown = segments.reduce(0) { $0 + $1.text.count } }
            }
            return state.wakeAfterMilliseconds
        }
        print("番号\t組み立て中の文字の数\t遅れ ms\t合間の wake の数\t合間の処理の最長 ms")
        var index = 0
        var wake: UInt32?
        for _ in 0..<repeats {
            for character in keys {
                let due = Double(index) * interval
                index += 1
                // 次の打鍵の時刻までは，DLL と同じく wake を送る
                var wakes = 0
                var longest = 0.0
                while let delay = wake, elapsed() + Double(delay) < due {
                    Thread.sleep(forTimeInterval: Double(delay) / 1000)
                    let began = elapsed()
                    wake = read(service.handle(WireRequest(id: 4, body: .wake(session: session, context: field)), from: id).body)
                    longest = max(longest, elapsed() - began)
                    wakes += 1
                }
                let wait = due - elapsed()
                if wait > 0 { Thread.sleep(forTimeInterval: wait / 1000) }
                let input = WireKeyInput(key: .character(text: String(character)), modifiers: plain, isKeypad: false)
                wake = read(service.handle(WireRequest(id: 3, body: .key(session: session, input: input, context: field)), from: id).body)
                let lag = elapsed() - due
                print(String(format: "%d\t%d\t%.1f\t%d\t%.1f", index, shown, lag, wakes, longest))
            }
        }
    }
}

/// 測るあいだだけ使う設定(変えない)
@MainActor
private final class TypingSettings: SettingsStoring {
    var current: Settings

    init(_ settings: Settings) {
        current = settings
    }

    func update(_ change: (inout Settings) -> Void) throws { change(&current) }
}
