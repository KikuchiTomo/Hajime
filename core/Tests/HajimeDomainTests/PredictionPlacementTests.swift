import HajimeDomain
import Testing

@Suite("予測の窓の位置")
struct PredictionPlacementTests {
    private static let screen = Rect(x: 0, y: 0, width: 1000, height: 800)
    private static let size = Rect(x: 0, y: 0, width: 120, height: 28)
    private static let gap = 8.0

    private static func origin(tail: Rect, candidates: PanelPlacement.Side = .below) -> (x: Double, y: Double) {
        PredictionPlacement.origin(tail: tail, size: size, screen: screen, gap: gap, candidates: candidates)
    }

    @Test("最後の字の右端のすぐ右に，行の高さの中央をそろえて置く(最後の字に重ねない)")
    func besideTail() {
        let tail = Rect(x: 300, y: 400, width: 16, height: 40)
        let origin = Self.origin(tail: tail)
        #expect(origin.x == tail.maxX + Self.gap)
        #expect(origin.y == 406)
    }

    @Test("行より高い窓は，候補の窓の側へは行と候補の窓のあいだまでしか出さない(入力中の候補の窓に重ねない)")
    func keepsClearOfCandidates() {
        let tail = Rect(x: 300, y: 400, width: 14, height: 16)
        // 候補の窓が下: 候補の窓の上の辺(行の下からあいだを空けた所)より下へ出さない
        let below = Self.origin(tail: tail, candidates: .below)
        #expect(below.y == tail.y - PanelPlacement.gap)
        // 候補の窓が上: 候補の窓の下の辺より上へ出さない
        let above = Self.origin(tail: tail, candidates: .above)
        #expect(above.y + Self.size.height == tail.maxY + PanelPlacement.gap)
    }

    @Test("画面の右に入らないときは，左へ寄せて組み立て中の文字に重ねず，画面の右端にそろえて候補の窓と反対の側の行の外に置く")
    func wrapsAtRightEdge() {
        let tail = Rect(x: 940, y: 400, width: 16, height: 20)
        let below = Self.origin(tail: tail, candidates: .below)
        #expect(below.x == Self.screen.maxX - Self.size.width)
        #expect(below.y == tail.maxY + Self.gap)
        let above = Self.origin(tail: tail, candidates: .above)
        #expect(above.x == Self.screen.maxX - Self.size.width)
        #expect(above.y + Self.size.height == tail.y - Self.gap)
    }

    @Test("画面の上下からはみ出さない")
    func staysOnScreen() {
        let top = Self.origin(tail: Rect(x: 940, y: 790, width: 16, height: 10), candidates: .below)
        #expect(top.y == Self.screen.maxY - Self.size.height)
        let bottom = Self.origin(tail: Rect(x: 300, y: 0, width: 16, height: 10), candidates: .above)
        #expect(bottom.y >= Self.screen.y)
    }

    @Test("縦書きの最後の字(行の幅の長方形)でも，字の右に置く")
    func verticalText() {
        let tail = Rect(x: 500, y: 300, width: 20, height: 18)
        let origin = Self.origin(tail: tail)
        #expect(origin.x == tail.maxX + Self.gap)
    }
}
