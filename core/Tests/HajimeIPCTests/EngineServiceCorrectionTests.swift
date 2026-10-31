import HajimeApplication
import HajimeDomain
@testable import HajimeIPC
import HajimeTestSupport
import Testing

/// 打ち間違いの訂正を別に求めるとき(Zenzai があるとき)の，エンジンのプロセスの流れ(R-02)．
/// DLL からは要求と応答しか無いので，訂正を求めているあいだは短い wake を頼み，求め終わったあとの wake で結果を返す
@MainActor
@Suite("エンジンのプロセスで打ち間違いの訂正を裏で求める")
struct EngineServiceCorrectionTests {
    /// 「youdesu」を「yoidesu」に直す訂正を返す．finishes が false なら取り消されるまで返さない
    struct Service: TypoCorrecting {
        var finishes = true
        /// 前もって求めたことを記録する．記録するときは，取り消されるまで返さない
        var prefetches: Prefetches?

        func prefetch(forKeys keys: [String], leftContext: String?) async {
            guard let prefetches else { return }
            await prefetches.requested(keys)
            while !Task.isCancelled { await Task.yield() }
            await prefetches.cancelled()
        }

        func corrections(forKeys keys: [String], leftContext: String?) async -> [String: [ReadingCorrection]] {
            if !finishes {
                while !Task.isCancelled { await Task.yield() }
                return [:]
            }
            return ["youdesu": [
                ReadingCorrection(keys: "yoidesu", reading: "ヨイデス", score: -1, cost: 1),
                ReadingCorrection(keys: "youdesu", reading: "ヨウデス", score: -9, cost: 0),
            ]]
        }
    }

    actor Prefetches {
        private(set) var requests: [[String]] = []
        private(set) var cancellations = 0
        func requested(_ keys: [String]) { requests.append(keys) }
        func cancelled() { cancellations += 1 }
    }

    /// DLL のタイマーのように，前の応答で頼まれた間隔(wakeAfterMilliseconds)だけ待ってから wake する時計
    final class Clock {
        var now = ContinuousClock.now
        var requestedWait: UInt32?
    }

    private let settings: FakeSettings
    private let service: EngineService
    private let clock = Clock()

    init(service typo: Service = Service(), liveConversion: Bool = false) {
        var initial = DefaultSettings.settings
        initial.liveConversion = liveConversion
        let settings = FakeSettings(initial)
        let converter = FakeConverter(["ようです": [("様です", nil)], "よいです": [("良いです", nil)]])
        let clock = clock
        self.settings = settings
        self.service = EngineService(
            makeSession: { InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings, typoService: typo) },
            settings: settings, ui: { _ in }, openSettings: {}, typoService: typo, now: { clock.now }
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

    private func press(_ key: WireKey, _ session: UInt32, _ id: EngineService.ConnectionID) -> WireResponseBody {
        let body = service.handle(WireRequest(id: 3, body: .key(session: session, input: WireKeyInput(key: key, modifiers: Self.plain, isKeypad: false), context: Self.field)), from: id).body
        clock.requestedWait = Self.wakeAfter(body)
        return body
    }

    private func type(_ text: String, _ session: UInt32, _ id: EngineService.ConnectionID) {
        for character in text { _ = press(.character(text: String(character)), session, id) }
    }

    private func wake(_ session: UInt32, _ id: EngineService.ConnectionID) -> WireResponseBody {
        if let wait = clock.requestedWait { clock.now = clock.now + .milliseconds(Int(wait)) }
        let body = service.handle(WireRequest(id: 4, body: .wake(session: session, context: Self.field)), from: id).body
        clock.requestedWait = Self.wakeAfter(body)
        return body
    }

    private static func composition(_ body: WireResponseBody) -> String? {
        guard case .edit(_, let operations, _) = body else { return nil }
        return operations.compactMap { operation -> String? in
            if case .setComposition(let segments, _) = operation { return segments.map(\.text).joined() }
            return nil
        }.last
    }

    /// 見直すまでに要る wake の回数の上限(いちばん長い correctionDelay を，いちばん短い wake の間隔で割った数)
    private static let wakesUntilReview = Int(DefaultSettings.correctionDelayRange.upperBound / DefaultSettings.latticeWarmingPollInterval) + 2

    private static func wakeAfter(_ body: WireResponseBody) -> UInt32? {
        guard case .edit(_, _, let state) = body else { return nil }
        return state.wakeAfterMilliseconds
    }

    @Test("Space ですぐ変換を出し，訂正は裏で求めて，届いたあとの wake で直した変換に入れ替える")
    func conversionShowsAtOnceAndCorrectsLater() async throws {
        let (id, session) = try open()
        type("youdesu", session, id)
        let space = press(.space, session, id)
        // 訂正を待たずに変換を出す(候補が遅れて出ない)．文節の長さの下見などは，すぐ来てもらう wake で足す
        #expect(Self.composition(space) == "様です")
        #expect(Self.wakeAfter(space) == EngineService.followUpPollMilliseconds)
        var followed = wake(session, id)
        while Self.wakeAfter(followed) == EngineService.followUpPollMilliseconds { followed = wake(session, id) }
        #expect(Self.wakeAfter(followed) == EngineService.correctionPollMilliseconds)
        await service.waitForCorrections()
        let woke = wake(session, id)
        #expect(Self.composition(woke) == "良いです")
        #expect(Self.wakeAfter(woke) != EngineService.correctionPollMilliseconds)
    }

    @Test("訂正が長くかかるときは，期限を過ぎたら求めるのをやめ，出した変換はそのまま")
    func conversionGivesUpAfterDeadline() throws {
        let test = EngineServiceCorrectionTests(service: Service(finishes: false))
        let (id, session) = try test.open()
        test.type("youdesu", session, id)
        #expect(Self.composition(test.press(.space, session, id)) == "様です")
        let early = test.wake(session, id)
        #expect(Self.composition(early) == nil)
        #expect(Self.wakeAfter(early) == EngineService.correctionPollMilliseconds)
        test.clock.now = test.clock.now + .seconds(DefaultSettings.lateCorrectionTimeout + 1)
        let late = test.wake(session, id)
        #expect(Self.composition(late) == nil)
        #expect(Self.wakeAfter(late) != EngineService.correctionPollMilliseconds)
    }

    @Test("変換したあとに次のキーを打ったら，あとから届いた訂正では変換を直さない")
    func keyCancelsWaitingConversion() async throws {
        let (id, session) = try open()
        type("youdesu", session, id)
        _ = press(.space, session, id)
        _ = press(.character(text: "n"), session, id)
        await service.waitForCorrections()
        let woke = wake(session, id)
        #expect(Self.composition(woke) != "良いです")
    }

    @Test("打鍵が止まったら訂正を裏で求め，求め終わったあとの wake で見直して直す")
    func reviewUsesProvidedCorrections() async throws {
        let (id, session) = try open()
        type("youdesu", session, id)
        var marked: String?
        // 見直すのは打鍵が止まってから correctionDelay たったとき．それまで DLL の間隔で wake する
        for _ in 0..<Self.wakesUntilReview {
            let woke = wake(session, id)
            if let text = Self.composition(woke) { marked = text }
            await service.waitForCorrections()
        }
        #expect(marked == "よいです")
    }

    @Test("打鍵が止まったあとの訂正が長くかかるときは，期限を過ぎたらやめ，その入力は求め直さない")
    func reviewGivesUpAfterDeadline() throws {
        let test = EngineServiceCorrectionTests(service: Service(finishes: false))
        let (id, session) = try test.open()
        test.type("youdesu", session, id)
        var started = false
        for _ in 0..<Self.wakesUntilReview where !started {
            started = Self.wakeAfter(test.wake(session, id)) == EngineService.correctionPollMilliseconds
        }
        #expect(started)
        test.clock.now = test.clock.now + .seconds(DefaultSettings.reviewCorrectionTimeout + 1)
        _ = test.wake(session, id)
        // 見直したことにしたので，次の wake で訂正を求め直さない(求め直し続けると裏の仕事が止まらない)
        #expect(Self.wakeAfter(test.wake(session, id)) != EngineService.correctionPollMilliseconds)
        #expect(Self.wakeAfter(test.wake(session, id)) != EngineService.correctionPollMilliseconds)
    }

    @Test("打鍵が少し止まったら，見直すときの訂正を前もって求め始め，次のキーが来たら取り消す")
    func prefetchesWhileTypingAndCancelsOnNextKey() async throws {
        let prefetches = Prefetches()
        let test = EngineServiceCorrectionTests(service: Service(prefetches: prefetches))
        let (id, session) = try test.open()
        test.type("youdesu", session, id)
        let typed = test.clock.now
        // DLL の wake の間隔で来てもらううちに，correctionPrefetchDelay たったところで前もって求め始める．見直す時機よりずっと早い
        for _ in 0..<Self.wakesUntilReview where await prefetches.requests.isEmpty {
            _ = test.wake(session, id)
            for _ in 0..<100 where await prefetches.requests.isEmpty { await Task.yield() }
        }
        #expect(await prefetches.requests == [["youdesu"]])
        let started = test.clock.now - typed
        #expect(started >= .seconds(DefaultSettings.correctionPrefetchDelay))
        #expect(started < .seconds(DefaultSettings.liveCorrectionDelay))
        _ = test.press(.character(text: "n"), session, id)
        for _ in 0..<1_000 where await prefetches.cancellations == 0 { await Task.yield() }
        #expect(await prefetches.cancellations == 1)
    }
}
