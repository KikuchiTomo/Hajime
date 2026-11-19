import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimePersistence

/// 決まった間隔でキーが届いたときの，キーが届いてから処理し終えるまでの時間を測る．
///
/// 1 キーの処理だけを測る道具(LatencyProbeTests)では，打鍵の合間にメインスレッドで進める処理(あとから足す候補・
/// 入力中に済ませなかった変換・分岐図の下見)が次のキーを待たせる時間が見えない．ここではアプリの入力コントローラ
/// (HajimeInputController)と同じ段取りで合間の処理を動かし，キーは別のスレッドから決まった時刻にメインスレッドへ届ける．
/// 届いた時刻から処理し終えた時刻までが，利用者が感じる遅れになる(画面に出す時間は含まない)
@MainActor
final class TypingLatencyProbe {
    private let session: InputSession
    private let service: ZenzaiTypoService?
    private let settings: Settings
    private var settleTask: Task<Void, Never>?
    private var followUpTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var committed = ""
    private let clock = ContinuousClock()
    /// 合間の処理の種類ごとの 1 歩の時間(ミリ秒)
    fileprivate(set) var steps: [String: [Double]] = [:]

    /// 変換を待つ表示を出してから，変換した表示に出し直すまでの時間(ミリ秒)
    fileprivate(set) var conversionLags: [Double] = []
    private var pendingSince: ContinuousClock.Instant?
    private var lastContext = InputContext()

    /// - Parameter defers: 打っているあいだの変換を裏で求めるか(アプリと同じ)．false なら今までどおりキーの処理の中で待つ
    init(session: InputSession, service: ZenzaiTypoService?, settings: Settings, defers: Bool) {
        self.session = session
        self.service = service
        self.settings = settings
        if defers {
            session.setConversionArrivalHandler { [weak self] in self?.conversionArrived() }
        }
    }

    private func conversionArrived() {
        _ = measure("届いた変換を出す") { session.conversionDidArrive(context: lastContext) }
        if session.needsFollowUpsAfterArrival {
            followUpTask?.cancel()
            runFollowUps(context: lastContext)
        }
        if !session.awaitsConversion, let since = pendingSince {
            conversionLags.append(Self.milliseconds(clock.now - since))
            pendingSince = nil
        }
    }

    private func measure<T>(_ kind: String, _ work: () -> T) -> T {
        let start = clock.now
        let value = work()
        steps[kind, default: []].append(Self.milliseconds(clock.now - start))
        return value
    }

    nonisolated static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000
    }

    /// キーを 1 つ処理する(HajimeInputController.handle と同じ順)．キーの処理そのものの時間を返す
    func press(_ key: KeyEvent.Key) -> Double {
        followUpTask?.cancel()
        followUpTask = nil
        // アプリと同じく，入力位置の前の文字は決まった長さまでしか渡さない(InputContextProvider)
        let context = InputContext(precedingText: session.isComposing ? nil : String(committed.suffix(DefaultSettings.maximumLeftContextLength)))
        let start = clock.now
        let result = session.handle(KeyEvent(key), context: context)
        let elapsed = Self.milliseconds(clock.now - start)
        for action in result.actions { if case .commit(let value) = action { committed += value } }
        lastContext = context
        if session.awaitsConversion {
            if pendingSince == nil { pendingSince = start }
        } else {
            pendingSince = nil
        }
        runFollowUps(context: context)
        scheduleSettle(context: context)
        return elapsed
    }

    private func runFollowUps(context: InputContext) {
        let steps = session.followUps(context: context)
        guard !steps.isEmpty else { return }
        followUpTask = Task { @MainActor [weak self] in
            for step in steps {
                await Task.yield()
                guard !Task.isCancelled, let self else { return }
                _ = self.measure("あとから足す") { step() }
            }
        }
    }

    private func warmLattice() async {
        for step in session.latticeWarmingSteps {
            await Task.yield()
            guard !Task.isCancelled else { return }
            measure("下見") { step() }
        }
    }

    private func scheduleSettle(context: InputContext) {
        settleTask?.cancel()
        settleTask = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        let settles = session.awaitsSettle
        guard settles || session.awaitsReview else { return }
        let settleDelay = settings.liveConversionDelay
        let correctionDelay = settings.correctionDelay
        settleTask = Task { @MainActor [weak self] in
            let start = ContinuousClock.now
            if let self, self.session.awaitsDeferredConversion {
                try? await Task.sleep(for: .seconds(DefaultSettings.deferredConversionPollInterval))
                guard !Task.isCancelled else { return }
                self.measure("追いかける変換") { self.session.performDeferredConversion() }
                await self.warmLattice()
            }
            if let self, let service = self.service {
                try? await Task.sleep(until: start + .seconds(DefaultSettings.correctionPrefetchDelay), clock: .continuous)
                guard !Task.isCancelled else { return }
                if let request = self.session.prefetchRequest {
                    self.prefetchTask = Task { await service.prefetch(forKeys: request.keys, leftContext: request.leftContext) }
                }
            }
            if settles {
                try? await Task.sleep(until: start + .seconds(settleDelay), clock: .continuous)
                guard !Task.isCancelled, let self else { return }
                _ = self.measure("止まったとき") { self.session.settle(context: context) }
                await self.warmLattice()
            }
            guard let self, self.session.awaitsReview else { return }
            try? await Task.sleep(until: start + .seconds(correctionDelay), clock: .continuous)
            guard !Task.isCancelled else { return }
            if let request = self.session.correctionRequest, let service = self.service {
                let prefetch = self.prefetchTask
                let corrections = await Deadline.run(seconds: self.settings.reviewCorrectionTimeout) {
                    await prefetch?.value
                    return await service.corrections(forKeys: request.keys, leftContext: request.leftContext)
                }
                guard !Task.isCancelled else { return }
                guard let corrections else {
                    self.session.skipReview()
                    return
                }
                self.session.provideCorrections(corrections)
            }
            _ = self.measure("見直し") { self.session.review(context: context) }
            await self.warmLattice()
        }
    }

    /// 前に呼んでから確定した文字
    func takeCommitted() -> String {
        defer { committedSinceTake = committed.count }
        return String(committed.dropFirst(committedSinceTake))
    }

    private var committedSinceTake = 0

    func stop() {
        settleTask?.cancel()
        followUpTask?.cancel()
        prefetchTask?.cancel()
    }

    struct Sample: Sendable {
        var handle: Double
        var latency: Double
    }

    /// file の各行(ローマ字)を，intervals の間隔(ミリ秒)ごとに打ち，届いてから処理し終えるまでの時間をまとめて出す．
    /// 行の中の空白は Space(変換)，行の終わりで Enter を押す
    static func run(file: String, intervals: [Double], engine: AzooKeyConverterEngine, service: ZenzaiTypoService?,
                    terms: (any TermDictionaryLookup)?, usesFusion: Bool, trace: Bool, traceThreshold: Double = 16, defers: Bool, pause: Double, printsText: Bool) throws {
        let lines = try String(contentsOfFile: file, encoding: .utf8).split(whereSeparator: \.isNewline)
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }.map(String.init)
        var settings = DefaultSettings.settings
        if !usesFusion { settings.jinenModel = .off }
        let store = StaticSettings(settings)
        print("負荷: \(loadAverage())")
        for interval in intervals {
            let engineSession = engine.makeSession()
            let converter = SupplementedConverter(engineSession, settings: store, calendar: SystemCalendar(clock: { Date() }), terms: terms)
            let session = InputSession(converter: converter, lexicon: WordListLexicon(), settings: store, typoService: service,
                                       branchStations: true, groupsBranchSegments: true, scorer: engineSession, fusing: usesFusion ? engineSession : nil)
            let probe = TypingLatencyProbe(session: session, service: service, settings: settings, defers: defers)
            // 辞書とモデルを読み込ませる 1 文は数えない
            for key in "kyouhaiitenkidesu" { _ = probe.press(KeyEvent.Key.character(key)) }
            _ = probe.press(KeyEvent.Key.enter)
            probe.steps = [:]
            probe.conversionLags = []
            var handle: [Double] = []
            var latency: [Double] = []
            for line in lines {
                // 「|」は打鍵の止まり(止まったあとの処理が動くあいだ待ってから，次のキーを打つ)
                let keys: [KeyEvent.Key?] = line.map { $0 == "|" ? nil : $0 == " " ? KeyEvent.Key.space : KeyEvent.Key.character($0) } + [KeyEvent.Key.enter]
                let results: [Sample] = waitFor { await deliver(keys, every: interval, pause: pause, to: probe) }
                handle += results.map(\.handle)
                latency += results.map(\.latency)
                if trace {
                    for (index, result) in results.enumerated() where result.latency > traceThreshold {
                        print(String(format: "  間隔 %.0f ms  キー %d  処理 %.1f ms  遅れ %.1f ms", interval, index + 1, result.handle, result.latency))
                    }
                }
                probe.stop()
                if printsText { print("  確定: \(probe.takeCommitted())") }
                // 次の文の前に，止まったあとの処理を終わらせる
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            }
            print(String(format: "間隔 %.0f ms  キー %d", interval, handle.count))
            print("  キーの処理      " + summary(handle))
            print("  届いてからの遅れ " + summary(latency)
                  + String(format: "  16ms 超 %d  50ms 超 %d  100ms 超 %d", latency.filter { $0 > 16 }.count, latency.filter { $0 > 50 }.count,
                           latency.filter { $0 > 100 }.count))
            if defers { print("  変換が表示に出るまで " + summary(probe.conversionLags) + " (\(probe.conversionLags.count) 回)") }
            for (kind, values) in probe.steps.sorted(by: { $0.key < $1.key }) {
                print("  合間: \(kind) \(values.count) 回  " + summary(values))
            }
        }
    }

    private static func summary(_ values: [Double]) -> String {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return "なし" }
        func percentile(_ value: Double) -> Double { sorted[min(sorted.count - 1, Int(Double(sorted.count) * value))] }
        return String(format: "中央値 %.1f ms  95%% %.1f ms  99%% %.1f ms  最大 %.1f ms", percentile(0.5), percentile(0.95), percentile(0.99), sorted.last ?? 0)
    }

    private static func loadAverage() -> String {
        #if os(Windows)
        // Windows には負荷の平均を返す関数が無い
        return "不明"
        #else
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return "不明" }
        return String(format: "%.1f", loads[0])
        #endif
    }

    /// キーを決まった時刻にメインスレッドへ届ける．届ける側はメインスレッドの外で待つので，メインスレッドが塞がっていれば届くのが遅れる
    private nonisolated static func deliver(_ keys: [KeyEvent.Key?], every interval: Double, pause: Double, to probe: TypingLatencyProbe) async -> [Sample] {
        let clock = ContinuousClock()
        var due = clock.now + .milliseconds(20)
        var results: [Sample] = []
        for key in keys {
            guard let key else {
                due += .milliseconds(Int(pause))
                continue
            }
            due += .milliseconds(Int(interval))
            try? await Task.sleep(until: due, clock: .continuous)
            let arrived = clock.now
            let handle = await MainActor.run { probe.press(key) }
            results.append(Sample(handle: handle, latency: milliseconds(clock.now - arrived)))
        }
        return results
    }
}
