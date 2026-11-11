@testable import HajimeApplication
import HajimeDomain
import Testing

@Suite("変換中の変更の取り消しの段(R-17)")
struct ConversionHistoryTests {
    private typealias History = ConversionHistory<String>

    @Test("変える前の状態を積み，新しいものから取り出す")
    func undoesNewestFirst() {
        var history = History(depth: 8)
        history.record(before: "a", run: History.Run(.extendSegment, segment: 0))
        history.record(before: "b", run: History.Run(.nextCandidate, segment: 0))
        #expect(history.undo() == "b")
        #expect(history.undo() == "a")
        #expect(history.undo() == nil)
    }

    @Test("同じ文節で続けて候補を送ったときと，同じ字種のキーを続けて押したときは 1 段にまとめる")
    func mergesRuns() {
        var history = History(depth: 8)
        history.record(before: "a", run: History.Run(.nextCandidate, segment: 1))
        history.record(before: "b", run: History.Run(.nextCandidate, segment: 1))
        history.record(before: "c", run: History.Run(.previousCandidate, segment: 1))
        #expect(history.steps == ["a"])
        history.record(before: "d", run: History.Run(.switchKanaType, segment: 1))
        history.record(before: "e", run: History.Run(.switchKanaType, segment: 1))
        #expect(history.steps == ["a", "d"])
        // ほかの字種のキー・ほかの文節の候補はまとめない
        history.record(before: "f", run: History.Run(.segmentToKatakana, segment: 1))
        history.record(before: "g", run: History.Run(.nextCandidate, segment: 0))
        #expect(history.steps == ["a", "d", "f", "g"])
    }

    @Test("変更でないキーを挟むと，続けた変更のまとまりは切れる．まとめないコマンドは毎回段にする")
    func breaksRuns() {
        var history = History(depth: 8)
        history.record(before: "a", run: History.Run(.nextCandidate, segment: 0))
        history.breakRun()
        history.record(before: "b", run: History.Run(.nextCandidate, segment: 0))
        history.record(before: "c", run: History.Run(nil, segment: 0))
        history.record(before: "d", run: History.Run(nil, segment: 0))
        #expect(history.steps == ["a", "b", "c", "d"])
    }

    @Test("段は depth まで．古い段から捨てる")
    func keepsDepth() {
        var history = History(depth: DefaultSettings.conversionUndoDepth)
        for index in 0..<(DefaultSettings.conversionUndoDepth + 2) {
            history.record(before: String(index), run: nil)
        }
        #expect(history.steps.count == DefaultSettings.conversionUndoDepth)
        #expect(history.steps.first == "2")
        history.clear()
        #expect(history.undo() == nil)
    }
}
