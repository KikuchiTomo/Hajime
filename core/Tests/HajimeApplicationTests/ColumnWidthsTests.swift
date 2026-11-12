import HajimeApplication
import Testing

/// 取り込む前に見せる表の列の幅の配り方(R-16・R-21)
struct ColumnWidthsTests {
    @Test("R-21: 収まるときは中身の長さの割合で余りを足し，空いている列は見出しの幅にする")
    func fits() {
        let widths = ColumnWidths.distribute(natural: [100, 200, 0], minimum: [40, 40, 60], available: 720)
        #expect(widths.reduce(0, +) == 720)
        // 長い列ほど広い．中身の無い列は見出しの幅から少しだけ広がる
        #expect(widths[1] > widths[0])
        #expect(widths[2] < widths[0])
    }

    @Test("R-21: 収まらないときは見出しの幅を超える分を削り，見出しの幅より狭くしない")
    func shrinks() {
        let widths = ColumnWidths.distribute(natural: [300, 500, 60], minimum: [40, 40, 60], available: 600)
        #expect(abs(widths.reduce(0, +) - 600) < 0.001)
        #expect(widths[2] == 60)
        #expect(widths.allSatisfy { $0 >= 40 })
        #expect(widths[1] > widths[0])
    }

    @Test("見出しの幅の合計も収まらなければ見出しの幅の割合で縮める")
    func tooNarrow() {
        let widths = ColumnWidths.distribute(natural: [300, 300], minimum: [100, 300], available: 200)
        #expect(widths == [50, 150])
    }
}
