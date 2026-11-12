import HajimeApplication
import Testing

/// 語の意味の吹き出しの置き方: 左右の切り替え，画面の上下への寄せ，先の位置，縁の線のつながり
@Suite("語の意味の吹き出しの置き方")
struct MeaningBubbleLayoutTests {
    typealias Layout = MeaningBubbleLayout
    typealias Box = Layout.Box

    static let metrics = Layout.Metrics(width: 288, padding: 12, radius: 12, pointerLength: 8, pointerWidth: 16, gap: 4, screenMargin: 12)
    static let screen = Box(x: 0, y: 0, width: 1200, height: 800)

    static func anchor(x: Double, y: Double) -> Box { Box(x: x, y: y, width: 300, height: 200) }

    static func place(anchorX: Double, anchorY: Double, targetY: Double) -> Layout {
        Layout(anchor: anchor(x: anchorX, y: anchorY), targetY: targetY, size: (288, 160), preferredPointer: 20, screen: screen, metrics: metrics)
    }

    @Test("右に入れば右に出し，先は選んでいる行を見出しの行の高さで指す")
    func right() {
        let layout = Self.place(anchorX: 100, anchorY: 100, targetY: 150)
        #expect(layout.side == .right)
        #expect(layout.window.x == 100 + 300 + Self.metrics.gap)
        #expect(layout.body.x == Self.metrics.pointerLength)
        #expect(layout.window.y + layout.pointerY == 150)
        #expect(layout.pointerY == 20)
    }

    @Test("画面の右の端に入らなければ左に出す")
    func left() {
        let layout = Self.place(anchorX: 800, anchorY: 100, targetY: 150)
        #expect(layout.side == .left)
        #expect(layout.window.maxX == 800 - Self.metrics.gap)
        #expect(layout.body.x == 0)
        #expect(layout.window.y + layout.pointerY == 150)
    }

    @Test("画面の下に入らなければ上へ寄せ，画面の端とのあいだを空け，先は行を指し続ける")
    func bottom() {
        let layout = Self.place(anchorX: 100, anchorY: 580, targetY: 760)
        #expect(layout.window.maxY == Self.screen.maxY - Self.metrics.screenMargin)
        #expect(layout.window.y + layout.pointerY == 760)
        #expect(layout.pointerY <= 160 - Self.metrics.radius - Self.metrics.pointerWidth / 2)
    }

    @Test("画面の上に入らなければ下へ寄せ，先は角の丸みにかけない")
    func top() {
        let layout = Self.place(anchorX: 100, anchorY: 0, targetY: 6)
        #expect(layout.window.y == Self.screen.y + Self.metrics.screenMargin)
        #expect(layout.pointerY == Self.metrics.radius + Self.metrics.pointerWidth / 2)
    }

    @Test("縁の線は本体と先を 1 本でなぞり，始まりに戻る", arguments: [100.0, 800.0])
    func outline(anchorX: Double) throws {
        let layout = Self.place(anchorX: anchorX, anchorY: 100, targetY: 150)
        let outline = layout.outline(metrics: Self.metrics, stroke: 1)
        let points = outline.segments.map { segment -> (Double, Double) in
            switch segment {
            case let .line(x, y): (x, y)
            case let .corner(_, _, toX, toY, _): (toX, toY)
            }
        }
        let last = try #require(points.last)
        #expect(last == (outline.startX, outline.startY))
        // 先の頂点は窓の端(線の太さの半分だけ内側)
        let tipX = layout.side == .right ? 0.5 : layout.window.width - 0.5
        #expect(points.contains { $0 == (tipX, layout.pointerY) })
    }
}
