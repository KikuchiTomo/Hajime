import HajimeDomain
import Testing

@Suite("分岐図の枝の線の配置")
struct BranchLinesTests {
    /// 下の枝: 文節の札の下の端(y = 40)から，28 ずつ離れた 5 つの行へ
    private func downward(radius: Double = 8, lineWidth: Double = 1.5, scale: Double = 2) -> BranchLines {
        BranchLines(stemX: 22, rootY: 40, rowMidYs: (0..<5).map { 56 + Double($0) * 28 }, tipX: 47, radius: radius, lineWidth: lineWidth, scale: scale)
    }

    /// 上の枝: 文節の札の上の端(y = 100)から，上へ 3 つの行へ
    private func upward(radius: Double = 8) -> BranchLines {
        BranchLines(stemX: 22, rootY: 100, rowMidYs: [84, 56, 28], tipX: 47, radius: radius, lineWidth: 1.5, scale: 2)
    }

    @Test("曲がり角はすべて同じ半径の 4 分の 1 の円")
    func sameTurns() {
        for lines in [downward(), upward()] {
            #expect(lines.radius == 8)
            for turn in lines.turns {
                // 始まりは幹の上，中心は始まりから水平に半径の分，終わりは中心から縦に半径の分
                #expect(turn.start.x == lines.root.x)
                #expect(turn.center.x - turn.start.x == lines.radius)
                #expect(turn.center.y == turn.start.y)
                #expect(turn.end.x == turn.center.x)
                #expect(abs(turn.end.y - turn.center.y) == lines.radius)
            }
        }
    }

    @Test("水平の線の終わりの x はすべての候補で同じ")
    func sameTips() {
        for lines in [downward(), upward()] {
            #expect(Set(lines.turns.map(\.tip.x)).count == 1)
            #expect(lines.turns.allSatisfy { $0.tip.y == $0.end.y && $0.tip.x > $0.end.x })
        }
    }

    @Test("幹はいちばん遠い候補の曲がり角の始まりで終わり，先が飛び出さない")
    func stemEndsAtLastTurn() {
        for lines in [downward(), upward()] {
            #expect(lines.stemEnd == lines.turns.last?.start)
        }
        let down = downward()
        #expect(down.stemEnd.y > down.root.y)
        let up = upward()
        #expect(up.stemEnd.y < up.root.y)
    }

    @Test("曲がり角と水平の線は隣の候補のものと重ならない．最初の曲がり角は根元より先から始まる")
    func noOverlap() {
        for (lines, direction) in [(downward(), 1.0), (upward(), -1.0)] {
            #expect((lines.turns[0].start.y - lines.root.y) * direction >= 0)
            for (near, far) in zip(lines.turns, lines.turns.dropFirst()) {
                // 次の曲がり角の始まりは，前の水平の線から線の太さ以上離れる
                #expect((far.start.y - near.end.y) * direction >= 1.5)
            }
        }
    }

    @Test("行が詰まっていれば，半径を行のあいだに収まるよう縮める")
    func shrinksRadius() {
        let tight = BranchLines(stemX: 22, rootY: 40, rowMidYs: [46, 56, 66], tipX: 47, radius: 8, lineWidth: 1.5, scale: 2)
        #expect(tight.radius == 6)
        for (near, far) in zip(tight.turns, tight.turns.dropFirst()) {
            #expect(far.start.y - near.end.y >= 1.5)
        }
    }

    @Test("半径 0 は直角．曲がり角の始まり・中心・終わりが行の中心の高さで幹の上に重なる")
    func squareTurns() {
        let lines = downward(radius: 0)
        #expect(lines.radius == 0)
        for turn in lines.turns {
            #expect(turn.start == turn.end)
            #expect(turn.center == turn.end)
            #expect(turn.start.x == lines.root.x)
        }
        #expect(lines.stemEnd.y == lines.turns.last?.end.y)
    }

    @Test("線の縁はデバイスのピクセルの境に来る")
    func pixelAligned() {
        func onPixelEdge(_ value: Double) -> Bool { value == value.rounded() }
        for (lineWidth, scale) in [(1.5, 2.0), (2, 2), (1, 1), (1, 2), (2, 1)] {
            let lines = downward(lineWidth: lineWidth, scale: scale)
            let half = lineWidth * scale / 2
            #expect(onPixelEdge(lines.root.x * scale - half))
            #expect(onPixelEdge(lines.root.y * scale))
            for turn in lines.turns {
                #expect(onPixelEdge(turn.end.y * scale - half))
                #expect(onPixelEdge(turn.tip.x * scale))
            }
            #expect(onPixelEdge(lines.radius * scale))
        }
        // 1 ピクセルの線は中心を半ピクセルずらす
        #expect(BranchLines.alignCenter(12, lineWidth: 1, scale: 1) == 12.5)
        #expect(BranchLines.alignCenter(12, lineWidth: 2, scale: 1) == 12)
    }

    @Test("選んでいる候補より先の幹．選んでいなければ幹の全体，いちばん遠い候補を選べば残りは無い")
    func stemAfterSelection() {
        let lines = downward()
        #expect(lines.stem(after: nil)?.from == lines.root)
        #expect(lines.stem(after: 1)?.from == lines.turns[1].start)
        #expect(lines.stem(after: 1)?.to == lines.stemEnd)
        #expect(lines.stem(after: lines.turns.count - 1) == nil)
        let empty = BranchLines(stemX: 22, rootY: 40, rowMidYs: [], tipX: 47, radius: 8, lineWidth: 1.5, scale: 2)
        #expect(empty.turns.isEmpty)
        #expect(empty.stem(after: nil) == nil)
    }
}
