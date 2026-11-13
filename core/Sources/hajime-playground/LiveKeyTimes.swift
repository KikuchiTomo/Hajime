import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeIPC
import HajimePersistence

/// ライブ変換のまま長い文を打ったときの 1 打鍵の時間を，読みの長さごとに測る(Windows で長い文ほど重くなる件)．
/// アプリと同じ InputSession に 1 キーずつ押し，段階ごとに測る:
/// - キー: InputSession.handle
/// - 後の処理: 画面を出したあとに 1 つずつ求めて足す処理(followUps)をすべて動かした時間と数
/// - 合間: 打鍵の合間に求める変換(performDeferredConversion)
/// - 通信: エンジンが DLL に返す形(RoutedActions と WireResponse の JSON)を作る時間と大きさ
/// 出すのは時間と長さと数だけ(入力した文字・読み・候補は出さない)
@MainActor
enum LiveKeyTimes {
    /// settleEvery が 0 でなければ，その数のキーごとに打鍵が止まったとき(settle)を挟む(アプリでは止まったときに Zenzai で求め直し，
    /// その時間で入力中に Zenzai を使うかを決める)．adaptive なら，モデルを読み終えてから，アプリと同じく時間で切り替える
    static func run(keys: String, repeats: Int, settleEvery: Int, adaptive: Bool, engine: AzooKeyConverterEngine) {
        if adaptive { engine.waitsForModels = false }
        var settings = DefaultSettings.settings
        settings.liveConversion = true
        let store = StaticSettings(settings)
        let engineSession = engine.makeSession()
        let converter = SupplementedConverter(engineSession, settings: store, calendar: SystemCalendar(clock: { Date() }))
        let session = InputSession(converter: converter, lexicon: WordListLexicon(), settings: store, scorer: engineSession, fusing: engineSession)
        let clock = ContinuousClock()
        let encoder = JSONEncoder()
        func milliseconds(_ duration: Duration) -> Double {
            Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000
        }
        print("番号\t読みの長さ\tキー ms\t後の処理 ms\t後の処理の数\t合間 ms\t通信 ms\t通信 バイト")
        var index = 0
        var shown = 0
        for _ in 0..<repeats {
            for character in keys {
                index += 1
                var result: KeyResult?
                let key = milliseconds(clock.measure { result = session.handle(KeyEvent(.character(character)), context: InputContext()) })
                var actions = result?.actions ?? []
                var steps = 0
                let follow = milliseconds(clock.measure {
                    for step in session.followUps(context: InputContext()) {
                        actions += step()
                        steps += 1
                    }
                })
                let idle = milliseconds(clock.measure {
                    var count = 0
                    while session.awaitsDeferredConversion, count < 64 {
                        session.performDeferredConversion()
                        count += 1
                    }
                })
                var bytes = 0
                let wire = milliseconds(clock.measure {
                    let routed = RoutedActions(actions, anchor: nil)
                    let body = WireResponseBody.edit(handled: true, operations: routed.edits,
                                                     state: WireSessionState(mode: .japanese, isComposing: true, keymap: settings.keymap,
                                                                             wakeAfterMilliseconds: nil, keyboardLayout: nil))
                    bytes = (try? encoder.encode(body).count) ?? 0
                    for command in routed.ui { bytes += (try? encoder.encode(command).count) ?? 0 }
                })
                for action in actions {
                    if case .setMarkedText(let marked) = action { shown = marked.segments.reduce(0) { $0 + $1.text.count } }
                }
                print(String(format: "%d\t%d\t%.2f\t%.2f\t%d\t%.2f\t%.2f\t%d", index, shown, key, follow, steps, idle, wire, bytes))
            }
        }
    }
}
