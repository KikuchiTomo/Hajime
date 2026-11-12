import HajimeApplication
import Testing

/// チップを左から並べて送る並べ方(R-21 の書き方のチップ)．チップは重ならず，間はそろい，幅を超えたら次の行に送る
struct FlowLayoutTests {
    private let gap = LayoutTokens.Space.group

    @Test("R-21: チップは左端から間をそろえて並べ，幅を超えるチップは次の行の左端に送る")
    func wrapsAtWidth() {
        let placements = FlowLayout.place(widths: [40, 60, 50, 30], spacing: gap, width: 120)
        #expect(placements == [
            .init(x: 0, row: 0), .init(x: 40 + gap, row: 0),
            .init(x: 0, row: 1), .init(x: 50 + gap, row: 1),
        ])
    }

    @Test("R-21: 同じ行のチップは重ならず，チップとチップの間はどこでも同じ")
    func gapsAreEqual() {
        let widths: [Double] = [44, 70, 31, 90, 12, 64, 58]
        let placements = FlowLayout.place(widths: widths, spacing: gap, width: 200)
        for index in placements.indices.dropFirst() where placements[index].row == placements[index - 1].row {
            #expect(placements[index].x == placements[index - 1].x + widths[index - 1] + gap)
        }
        for (placement, width) in zip(placements, widths) {
            #expect(placement.x == 0 || placement.x + width <= 200)
        }
    }

    @Test("R-21: 1 つで幅を超えるチップも縮めず行の先頭に置く")
    func wideItemStandsAlone() {
        let placements = FlowLayout.place(widths: [30, 300, 30], spacing: gap, width: 120)
        #expect(placements.map(\.row) == [0, 1, 2])
        #expect(placements.map(\.x) == [0, 0, 0])
    }
}
