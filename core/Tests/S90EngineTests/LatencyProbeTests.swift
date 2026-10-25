import Foundation
import S90Application
import S90Domain
import S90Engine
import S90TestSupport
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
    @Test("ライブ変換を含めて 1 キーの処理を測る", .enabled(if: isReleaseBuild))
    func perKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-latency-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "latency")
        let session = InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(), settings: FakeSettings())
        // 辞書を読み込ませるための 1 回目は数えない
        _ = session.handle(KeyEvent(.character("a")), context: InputContext())
        _ = session.handle(KeyEvent(.escape), context: InputContext())
        let keys = Array("watashihaashitatoukyoudekaigininisshusekishimasu")
        let clock = ContinuousClock()
        var durations: [Duration] = []
        // 1 回目は辞書のページを読み込むので，2 回目の文を測る(ふだん使っている状態に近い)
        for pass in 0..<2 {
            for key in keys {
                let duration = clock.measure { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
                if pass == 1 { durations.append(duration) }
            }
            _ = session.handle(KeyEvent(.enter), context: InputContext())
        }
        let sorted = durations.sorted()
        let p50 = sorted[sorted.count / 2], p95 = sorted[sorted.count * 95 / 100], worst = sorted.last!
        print("S90_LATENCY p50=\(p50) p95=\(p95) max=\(worst) keys=\(keys.count)")
        // R-01 の受け入れ条件．デバッグビルドでは遅くなるので，CI では Release で測る
        #expect(p95 < .milliseconds(50))
    }
}
