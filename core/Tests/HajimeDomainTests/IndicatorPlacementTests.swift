import Testing
@testable import HajimeDomain

@Suite("入力モードの表示の位置")
struct IndicatorPlacementTests {
    let screen = Rect(x: 0, y: 0, width: 1000, height: 800)
    let size = Rect(x: 0, y: 0, width: 32, height: 32)
    /// 入力位置の行の下に OS が出す表示のために空ける高さ
    let clearance = 30.0

    private func place(_ caret: Rect) -> PanelPlacement.Placement {
        PanelPlacement.placeIndicator(caret: caret, size: size, screen: screen, clearance: clearance)
    }

    @Test("入力位置の行の上に置く(行のすぐ下には OS が入力ソースの表示を出す)")
    func above() {
        let caret = Rect(x: 100, y: 500, width: 2, height: 20)
        let placed = place(caret)
        #expect(placed.side == .above)
        #expect(placed.frame.x == 100)
        #expect(placed.frame.y == caret.maxY + PanelPlacement.gap)
    }

    @Test("上に入らなければ，OS の表示の分だけ離して下に置く")
    func belowSystemIndicator() {
        let caret = Rect(x: 100, y: 770, width: 2, height: 20)
        let placed = place(caret)
        #expect(placed.side == .below)
        #expect(placed.frame.maxY == caret.y - PanelPlacement.gap - clearance)
    }

    @Test("縦書きの縦に長い行でも，画面の中の上に置く．上にも下にも入らなければ画面の中に収める")
    func verticalLine() {
        let column = Rect(x: 900, y: 300, width: 20, height: 400)
        let placed = place(column)
        #expect(placed.side == .above)
        #expect(placed.frame.y == column.maxY + PanelPlacement.gap)
        // 画面いっぱいの行: 上にも下にも入らないので，画面の上の端に収める
        let full = place(Rect(x: 900, y: 0, width: 20, height: 800))
        #expect(full.frame.maxY == screen.maxY)
        #expect(full.frame.y >= screen.y)
    }

    @Test("画面の右端と左端で切れないようにずらす")
    func horizontalEdges() {
        #expect(place(Rect(x: 990, y: 500, width: 2, height: 20)).frame.maxX == screen.maxX)
        #expect(place(Rect(x: -10, y: 500, width: 2, height: 20)).frame.x == screen.x)
    }
}
