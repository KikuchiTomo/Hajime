import HajimeApplication
import Testing

/// 語の意味の吹き出しの置き方: 選んでいる行のすぐ横，覆わない物を避けた上下の寄せ，左右の切り替え，三角の位置，枠線のつながり
@Suite("語の意味の吹き出しの置き方")
struct MeaningBubbleLayoutTests {
    typealias Layout = MeaningBubbleLayout
    typealias Box = Layout.Box

    static let metrics = Layout.Metrics(width: 288, padding: 12, radius: 12, pointerLength: 8, pointerWidth: 16, gap: 4, screenMargin: 12)
    static let screen = Box(x: 0, y: 0, width: 1200, height: 800)
    static let size = (width: 288.0, height: 160.0)

    /// 一覧の窓(幅 300)．行の背景は窓の左右の余白 12 の内側で，行の右の端は窓の右の端の 12 手前
    static func list(x: Double, y: Double, selected: Int) -> (window: Box, row: Box, obstacles: [Box]) {
        let window = Box(x: x, y: y, width: 300, height: 200)
        let rows = (0..<4).map { Box(x: x + 12, y: y + 12 + 28 * Double($0), width: 276, height: 24) }
        let footer = Box(x: x + 12, y: y + 160, width: 276, height: 28)
        let others = rows.indices.filter { $0 != selected }.map { rows[$0] }
        return (window, rows[selected], others + [footer])
    }

    /// 足元の案内が長くて横に広い分岐図の窓(幅 800)．枝の行は左に寄り，足元は窓の幅いっぱい
    static func wideBranch(selected: Int) -> (window: Box, row: Box, obstacles: [Box]) {
        let window = Box(x: 100, y: 100, width: 800, height: 220)
        let trunk = [Box(x: 112, y: 112, width: 60, height: 24), Box(x: 180, y: 112, width: 60, height: 24)]
        let rows = (0..<4).map { Box(x: 220, y: 140 + 28 * Double($0), width: 120, height: 24) }
        let footer = Box(x: 112, y: 270, width: 776, height: 38)
        let others = rows.indices.filter { $0 != selected }.map { rows[$0] }
        return (window, rows[selected], trunk + others + [footer])
    }

    static func place(_ setup: (window: Box, row: Box, obstacles: [Box]), size: (width: Double, height: Double) = size,
                      screen: Box = screen) -> Layout {
        Layout(row: setup.row, window: setup.window, size: size, preferredPointer: 20, screen: screen, obstacles: setup.obstacles,
               metrics: metrics)
    }

    /// 窓(画面の座標)の本体の枠
    static func bodyBox(_ layout: Layout) -> Box {
        Box(x: layout.window.x + layout.body.x, y: layout.window.y, width: layout.body.width, height: layout.body.height)
    }

    /// 三角の頂点(画面の座標)
    static func tip(_ layout: Layout) -> (x: Double, y: Double) {
        (layout.side == .right ? layout.window.x : layout.window.maxX, layout.window.y + layout.pointerY)
    }

    @Test("三角の頂点は選んでいる行の右の端から inline の所で，行の縦の真ん中を指す")
    func besideRow() {
        let setup = Self.list(x: 100, y: 100, selected: 1)
        let layout = Self.place(setup)
        #expect(layout.side == .right)
        #expect(Self.tip(layout).x - setup.row.maxX == Self.metrics.gap)
        #expect(Self.tip(layout).y == setup.row.midY)
        #expect(layout.pointerY == 20)
    }

    @Test("広い窓でも三角は選んでいる行のすぐ横で，ほかの候補・幹の文節・足元を覆わない", arguments: [0, 1, 2, 3])
    func wideWindow(selected: Int) {
        let setup = Self.wideBranch(selected: selected)
        let layout = Self.place(setup, size: (288, 110))
        #expect(Self.tip(layout).x - setup.row.maxX == Self.metrics.gap)
        #expect(Self.tip(layout).y == setup.row.midY)
        let body = Self.bodyBox(layout)
        for obstacle in setup.obstacles {
            #expect(!body.intersects(obstacle), "\(obstacle)")
        }
    }

    @Test("足元を覆う高さなら上へ寄せ，三角は行を指したまま")
    func avoidsFooter() {
        let setup = Self.wideBranch(selected: 3)
        let layout = Self.place(setup, size: (288, 110))
        let footer = setup.obstacles.last!
        #expect(Self.bodyBox(layout).maxY <= footer.y - Self.metrics.gap)
        #expect(Self.tip(layout).y == setup.row.midY)
    }

    @Test("行の横に入らなければ候補の窓の外の右，それも画面に入らなければ左に出す")
    func fallsBack() {
        // 窓の中の行の横だと足元と幹にはさまれて入らない高さ
        let tall = Self.place(Self.wideBranch(selected: 1), size: (288, 400), screen: Box(x: 0, y: 0, width: 1400, height: 800))
        #expect(tall.side == .right)
        #expect(tall.window.x == 100 + 800 + Self.metrics.gap)
        // 画面の右の端の近く
        let nearEdge = Self.place(Self.list(x: 880, y: 100, selected: 0))
        #expect(nearEdge.side == .left)
        #expect(nearEdge.window.maxX == 880 - Self.metrics.gap)
        #expect(Self.tip(nearEdge).y == 100 + 12 + 12)
    }

    @Test("画面の下に入らなければ上へ寄せ，画面の端とのあいだを空け，三角は行を指し続ける")
    func bottom() {
        let setup = Self.list(x: 100, y: 590, selected: 3)
        let layout = Self.place(setup)
        #expect(layout.window.maxY <= Self.screen.maxY - Self.metrics.screenMargin)
        #expect(Self.tip(layout).y == setup.row.midY)
        #expect(layout.pointerY <= 160 - Self.metrics.radius - Self.metrics.pointerWidth / 2)
    }

    @Test("候補の窓の上の端より上に出さず，窓の高さに入るなら下の端より下にも出さない")
    func withinWindow() {
        // いちばん上の行で，三角を本体の上の端から遠くに置きたいとき
        let top = Self.list(x: 100, y: 100, selected: 0)
        let raised = Layout(row: top.row, window: top.window, size: Self.size, preferredPointer: 40, screen: Self.screen,
                            obstacles: top.obstacles, metrics: Self.metrics)
        #expect(raised.window.y == top.window.y)
        #expect(Self.tip(raised).y == top.row.midY)
        // いちばん下の行
        let bottom = Self.list(x: 100, y: 100, selected: 3)
        let lowered = Self.place(bottom)
        #expect(lowered.window.maxY == bottom.window.maxY)
        #expect(Self.tip(lowered).y == bottom.row.midY)
    }

    @Test("候補の窓より高い吹き出しは，窓の上の端にそろえる")
    func tallerThanWindow() {
        let setup = Self.list(x: 100, y: 100, selected: 1)
        let layout = Self.place(setup, size: (288, 260))
        #expect(layout.window.y == setup.window.y)
        #expect(Self.tip(layout).y == setup.row.midY)
    }

    @Test("枠線は本体と三角を 1 本でなぞり，始まりに戻る", arguments: [100.0, 880.0])
    func outline(x: Double) throws {
        let layout = Self.place(Self.list(x: x, y: 100, selected: 1))
        let outline = layout.outline(metrics: Self.metrics, stroke: 1)
        let points = outline.segments.map { segment -> (Double, Double) in
            switch segment {
            case let .line(x, y): (x, y)
            case let .corner(_, _, toX, toY, _): (toX, toY)
            }
        }
        let last = try #require(points.last)
        #expect(last == (outline.startX, outline.startY))
        // 三角の頂点は窓の端(線の太さの半分だけ内側)
        let tipX = layout.side == .right ? 0.5 : layout.window.width - 0.5
        #expect(points.contains { $0 == (tipX, layout.pointerY) })
    }
}
