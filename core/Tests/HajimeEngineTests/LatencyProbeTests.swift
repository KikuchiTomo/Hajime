import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeTestSupport
import Testing

#if DEBUG
private let isReleaseBuild = false
#else
private let isReleaseBuild = true
#endif

/// 時間はデバッグビルドでは何倍にもなるので，Release でだけ測る(swift test -c release)
@Suite("1 キーあたりの処理時間", .serialized)
@MainActor
struct LatencyProbeTests {
    /// 同じ文を打つ回数．ほかのプロセスに CPU を取られた回があっても，ほかの回で正しく測れるようにする
    private static let passes = 5

    @Test("ライブ変換を含めて 1 キーの処理を測る", .enabled(if: isReleaseBuild))
    func perKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-latency-\(UUID().uuidString)")
        // 環境変数 HAJIME_ZENZAI_MODEL にモデルの場所があれば，Zenzai ありで測る
        let zenzai = try ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"].map { try ZenzaiModel.verified(at: URL(fileURLWithPath: $0)) }
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "latency", zenzai: zenzai)
        engine.warmUp()
        let session = InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(), settings: FakeSettings())
        // 辞書を読み込ませるための 1 回目は数えない
        _ = session.handle(KeyEvent(.character("a")), context: InputContext())
        _ = session.handle(KeyEvent(.escape), context: InputContext())
        // nn のあとの母音を含む語(反映・皆・女)も入れ，読みを選ぶための変換の手間も測る
        let keys = Array("watashihaashitatoukyoudekaigininisshusekishimasuminnnanoikenwohanneisuru")
        let clock = ContinuousClock()
        var passP95s: [Duration] = []
        var all: [Duration] = []
        // 1 回目は辞書のページを読み込むので数えず，2 回目からの文を測る(ふだん使っている状態に近い)
        for pass in 0...Self.passes {
            var durations: [Duration] = []
            for key in keys {
                durations.append(clock.measure { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) })
                // アプリと同じく，打鍵の合間に Zenzai の変換を追いかけて求め，分岐図の候補も前もって求める(Zenzai が遅い環境だけ．
                // 1 キーの時間には入れない)．文節の候補はためてあるので，求めるのは新しい文節の分だけで，人の打鍵の間に収まる
                if session.awaitsDeferredConversion {
                    session.performDeferredConversion()
                    session.latticeWarmingSteps.forEach { $0() }
                }
            }
            _ = session.handle(KeyEvent(.enter), context: InputContext())
            guard pass > 0 else { continue }
            passP95s.append(Self.p95(durations))
            all += durations
        }
        let sorted = all.sorted()
        let best = passP95s.min()!
        print("HAJIME_LATENCY zenzai=\(engine.usesZenzai) p50=\(sorted[sorted.count / 2]) p95=\(Self.p95(all)) max=\(sorted.last!) best_pass_p95=\(best) pass_p95=\(passP95s) keys=\(keys.count) passes=\(Self.passes)\(Self.loadAverage)")
        // R-01 の受け入れ条件(p95 で 50ms 以内)．ほかのプロセスが CPU を使うと時間は延びるだけで縮まないので，
        // 同じ文を何度か打ち，いちばん速かった回の p95 で判定する．遅くなる変更はどの回でも遅くなるので見逃さない
        #expect(best < .milliseconds(50), "どの回も p95 が 50ms を超えた: \(passP95s)")
    }

    @Test("長い文で，打つ位置ごとの 1 キーの時間と Space で変換するまでの時間を測る", .enabled(if: isReleaseBuild))
    func longSentence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-latency-\(UUID().uuidString)")
        let zenzai = try ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"].map { try ZenzaiModel.verified(at: URL(fileURLWithPath: $0)) }
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "latency", zenzai: zenzai)
        engine.warmUp()
        // アプリと同じく，記号・日付・送り仮名などの候補を足す変換器(SupplementedConverter)を通して測る
        let settings = FakeSettings()
        let converter = SupplementedConverter(engine.makeSession(), settings: settings, calendar: FakeCalendar())
        let session = InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings)
        _ = session.handle(KeyEvent(.character("a")), context: InputContext())
        _ = session.handle(KeyEvent(.escape), context: InputContext())
        let keys = Array("kinouhatomodatitoeigawominiittekaerinikissatendekohiwonondekaraiedeyuuhanwotabemasita")
        let clock = ContinuousClock()
        // ほかのプロセスに CPU を取られた回があっても正しく測れるよう，同じ文を何回か打ち，項目ごとにいちばん速かった回で判定する(perKey と同じ)
        var chunks: [Duration] = []
        var space = Duration.seconds(Int64.max), right = Duration.seconds(Int64.max), resize = Duration.seconds(Int64.max)
        var warmedSpace = Duration.seconds(Int64.max), warmingStep = Duration.seconds(Int64.max)
        for _ in 0..<Self.passes {
            // 打鍵が止まったあいだに分岐図の候補を前もって求めたとき(アプリでふつうに起きる順)の Space
            for key in keys { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
            _ = session.settle(context: InputContext())
            let steps = session.latticeWarmingSteps
            warmingStep = min(warmingStep, steps.map { step in clock.measure { step() } }.max() ?? .zero)
            warmedSpace = min(warmedSpace, clock.measure { _ = session.handle(KeyEvent(.space), context: InputContext()) })
            _ = session.handle(KeyEvent(.enter), context: InputContext())
            var durations: [Duration] = []
            for key in keys {
                durations.append(clock.measure { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) })
                // アプリと同じく，打鍵の合間に Zenzai の変換を追いかけて求め，分岐図の候補も前もって求める(Zenzai が遅い環境だけ．
                // 1 キーの時間には入れない)．文節の候補はためてあるので，求めるのは新しい文節の分だけで，人の打鍵の間に収まる
                if session.awaitsDeferredConversion {
                    session.performDeferredConversion()
                    session.latticeWarmingSteps.forEach { $0() }
                }
            }
            space = min(space, clock.measure { _ = session.handle(KeyEvent(.space), context: InputContext()) })
            // 変換中の文節の移動と，文節の長さを変える操作(区切り直しと下見)
            right = min(right, clock.measure { _ = session.handle(KeyEvent(.right), context: InputContext()) })
            resize = min(resize, clock.measure { _ = session.handle(KeyEvent(.right, modifiers: [.shift]), context: InputContext()) })
            _ = session.handle(KeyEvent(.enter), context: InputContext())
            let passChunks = stride(from: 0, to: durations.count, by: 10).map { start in
                durations[start..<min(start + 10, durations.count)].max()!
            }
            chunks = chunks.isEmpty ? passChunks : zip(chunks, passChunks).map { min($0, $1) }
        }
        print("HAJIME_LONG zenzai=\(engine.usesZenzai) keys=\(keys.count) passes=\(Self.passes) max_per_10keys=\(chunks) space=\(space) warmed_space=\(warmedSpace) warming_step=\(warmingStep) right=\(right) resize=\(resize)\(Self.loadAverage)")
        // 文が長くなっても 1 キーは 50ms 以内(R-01)．Space で分岐図を出すまでは，待たされたと感じない 0.1 秒を目安に，
        // ほかのプロセスの負荷で延びる分を見込んで 0.15 秒以内．文節ごとにライブ変換の状態を捨てて変換し直していたときは 0.58 秒だった
        #expect(chunks.allSatisfy { $0 < .milliseconds(50) }, "長い文で 1 キーが 50ms を超えた: \(chunks)")
        #expect(space < .milliseconds(150), "長い文で Space から分岐図までが 0.15 秒を超えた: \(space)")
        // 打鍵が止まったあいだに前もって求めていれば，Space は文節ごとに変換し直さない
        // 前もって求める 1 歩のあいだに来たキーはその分待つので，1 歩も 1 キーと同じく 50ms 以内
        #expect(warmingStep < .milliseconds(50), "前もって求める 1 歩が 50ms を超えた: \(warmingStep)")
        // Zenzai が遅い環境では打鍵の合間にも前もって求めるので，止まらずに押した Space も同じくらい速い(そのときは 50ms 以内を見る)
        #expect(warmedSpace < space || warmedSpace < .milliseconds(50), "前もって求めても Space が速くならない: \(warmedSpace)，求めないとき \(space)")
        #expect(right < .milliseconds(150) && resize < .milliseconds(150), "長い文で変換中の操作が 0.15 秒を超えた: → \(right)，⇧→ \(resize)")
    }

    @Test("短い文(文節が 1 つ)でも，打鍵が止まったあいだに前もって求めると Space が速くなる", .enabled(if: isReleaseBuild))
    func shortSentenceWarmedSpace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-latency-\(UUID().uuidString)")
        let zenzai = try ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"].map { try ZenzaiModel.verified(at: URL(fileURLWithPath: $0)) }
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "latency", zenzai: zenzai)
        engine.warmUp()
        // アプリでは打ち間違いの訂正を裏で求めるので，Space の時間に入らない．ここでも訂正を切って，分岐図を出す時間だけを測る
        var initial = Settings()
        initial.typoCorrection = .off
        initial.misreadings = false
        let settings = FakeSettings(initial)
        let session = InputSession(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: FakeCalendar()),
                                   lexicon: FakeLexicon(), settings: settings)
        let clock = ContinuousClock()
        var cold = Duration.seconds(Int64.max), warmed = Duration.seconds(Int64.max)
        for _ in 0..<Self.passes {
            for warming in [false, true] {
                for key in "kyouhaame" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
                _ = session.settle(context: InputContext())
                if warming { session.latticeWarmingSteps.forEach { $0() } }
                let space = clock.measure { _ = session.handle(KeyEvent(.space), context: InputContext()) }
                if warming { warmed = min(warmed, space) } else { cold = min(cold, space) }
                _ = session.handle(KeyEvent(.escape), context: InputContext())
                _ = session.handle(KeyEvent(.escape), context: InputContext())
            }
        }
        print("HAJIME_SHORT zenzai=\(engine.usesZenzai) space=\(cold) warmed_space=\(warmed)\(Self.loadAverage)")
        #expect(warmed < cold, "前もって求めても Space が速くならない: \(warmed)，求めないとき \(cold)")
    }

    /// 測ったときの負荷．時間が延びたときに，負荷のせいかを出力から見分けられるようにする
    private static var loadAverage: String {
        #if canImport(Darwin)
        var load = [Double](repeating: 0, count: 3)
        guard getloadavg(&load, 3) == 3 else { return "" }
        return " load=\(load.map { String(format: "%.2f", $0) })"
        #else
        return ""
        #endif
    }

    private static func p95(_ durations: [Duration]) -> Duration {
        let sorted = durations.sorted()
        return sorted[sorted.count * 95 / 100]
    }
}
