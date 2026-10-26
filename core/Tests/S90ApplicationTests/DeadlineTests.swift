import S90Application
import Testing

@Suite("待つものの時間の上限")
struct DeadlineTests {
    /// 取り消されるまで返さない仕事．取り消しを受けたら印を付けて返す
    actor Probe {
        private(set) var cancelled = false
        func mark() { cancelled = true }
    }

    @Test("上限を過ぎたら nil を返し，仕事に取り消しを伝える(CPU を使い続けない)")
    func timeoutCancelsWork() async {
        let probe = Probe()
        let value = await Deadline.run(seconds: 0.05) { () async -> Int in
            while !Task.isCancelled { await Task.yield() }
            await probe.mark()
            return 1
        }
        #expect(value == nil)
        for _ in 0..<1000 where !(await probe.cancelled) { await Task.yield() }
        #expect(await probe.cancelled)
    }

    @Test("呼んだ側が取り消されたら，仕事にも取り消しを伝える")
    func callerCancellationReachesWork() async {
        let probe = Probe()
        let caller = Task {
            await Deadline.run(seconds: 60) { () async -> Int in
                while !Task.isCancelled { await Task.yield() }
                await probe.mark()
                return 1
            }
        }
        caller.cancel()
        _ = await caller.value
        #expect(await probe.cancelled)
    }

    @Test("上限より早く終われば値を返す")
    func returnsValue() async {
        #expect(await Deadline.run(seconds: 5) { 7 } == 7)
    }
}
