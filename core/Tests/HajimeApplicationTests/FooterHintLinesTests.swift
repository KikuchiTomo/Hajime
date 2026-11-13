import HajimeApplication
import Testing

/// 足元のキーの案内の折り返し: 入らない案内を省かずに次の行へ送る
@Suite("足元の案内の折り返し")
struct FooterHintLinesTests {
    @Test("1 行に入るときは 1 行のまま")
    func fitsOneLine() {
        #expect(FooterHintLines.split(widths: [40, 50, 60], gap: 8, first: 200, rest: 300) == [0..<3])
    }

    @Test("1 行目に入らない案内は 2 行目へ送り，1 つも省かない")
    func wraps() {
        // 1 行目は右の位置などの分だけ狭い(100)．2 行目からは足元の幅(150)
        let lines = FooterHintLines.split(widths: [40, 50, 60, 70, 30], gap: 8, first: 100, rest: 150)
        #expect(lines == [0..<2, 2..<4, 4..<5])
        #expect(lines.flatMap { Array($0) } == Array(0..<5))
    }

    @Test("行の幅より広い案内はその行に 1 つだけ置く")
    func oversized() {
        let lines = FooterHintLines.split(widths: [40, 200, 30], gap: 8, first: 100, rest: 150)
        #expect(lines == [0..<1, 1..<2, 2..<3])
    }

    @Test("1 行目に 1 つも入らなければ 1 行目を空にし，案内は 2 行目から")
    func emptyFirstLine() {
        #expect(FooterHintLines.split(widths: [80, 30], gap: 8, first: 50, rest: 150) == [0..<0, 0..<2])
    }

    @Test("案内が無ければ空の 1 行")
    func none() {
        #expect(FooterHintLines.split(widths: [], gap: 8, first: 100, rest: 150) == [0..<0])
    }
}
