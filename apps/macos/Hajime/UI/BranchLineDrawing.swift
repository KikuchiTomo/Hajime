import AppKit
import HajimeDomain

/// 分岐図の幹と枝の線を描く．配置は core の BranchLines が決める．
///
/// 選んでいない線(幹と，候補ごとの曲がり角と水平の線)は 1 つのパスにまとめて 1 回でなぞり，重なったところを濃くしない．
/// 選んでいる候補への道(幹の根元からその候補の曲がり角まで，曲がり角，水平の線)は，最後に選択の色と太さで上に重ねる．
/// 線の端は平らにし，直角の角は尖らせる．上下が反転した(isFlipped の)ビューで使う
@MainActor
enum BranchLineDrawing {
    struct Style {
        var lineWidth: CGFloat
        var selectedWidth: CGFloat
        /// 曲がり角の半径．0 なら直角
        var radius: CGFloat
        var color: NSColor
        var selection: NSColor
    }

    /// rowMidYs は候補の行の縦の中心(幹に近い順)．selected は選んでいる候補の位置
    static func draw(stemX: CGFloat, rootY: CGFloat, rowMidYs: [CGFloat], tipX: CGFloat, selected: Int?, style: Style) {
        let scale = deviceScale
        func layout(_ width: CGFloat) -> BranchLines {
            BranchLines(stemX: Double(stemX), rootY: Double(rootY), rowMidYs: rowMidYs.map(Double.init), tipX: Double(tipX),
                        radius: Double(style.radius), lineWidth: Double(width), scale: Double(scale))
        }
        let lines = layout(style.lineWidth)
        let path = NSBezierPath()
        let last = lines.turns.count - 1
        for (index, turn) in lines.turns.enumerated() where index != selected {
            // 幹はいちばん遠い候補の曲がり角とひと続きにし，角に切れ目を作らない(選んでいる候補より先の部分だけを描く)
            if index == last, let stem = lines.stem(after: selected) {
                path.move(to: point(stem.from))
                path.line(to: point(stem.to))
            } else {
                path.move(to: point(turn.start))
            }
            append(turn, to: path)
        }
        stroke(path, color: style.color, width: style.lineWidth)
        guard let selected, lines.turns.indices.contains(selected) else { return }
        let route = layout(style.selectedWidth)
        let turn = route.turns[selected]
        let selectedPath = NSBezierPath()
        selectedPath.move(to: point(route.root))
        selectedPath.line(to: point(turn.start))
        append(turn, to: selectedPath)
        stroke(selectedPath, color: style.selection, width: style.selectedWidth)
    }

    /// 1 ポイントあたりのデバイスのピクセル数(今描いている先の倍率)
    private static var deviceScale: CGFloat {
        guard let context = NSGraphicsContext.current?.cgContext else { return 1 }
        return abs(context.convertToDeviceSpace(CGSize(width: 1, height: 1)).width)
    }

    /// 曲がり角(半径が 0 なら直角)と水平の線を足す．今の点は曲がり角の始まりにあること
    private static func append(_ turn: BranchLines.Turn, to path: NSBezierPath) {
        let radius = CGFloat(turn.end.x - turn.start.x)
        if radius > 0 {
            path.appendArc(from: NSPoint(x: turn.start.x, y: turn.end.y), to: point(turn.tip), radius: radius)
        } else {
            path.line(to: point(turn.end))
        }
        path.line(to: point(turn.tip))
    }

    private static func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
        guard !path.isEmpty else { return }
        color.setStroke()
        path.lineWidth = width
        path.lineCapStyle = .butt
        path.lineJoinStyle = .miter
        path.stroke()
    }

    private static func point(_ point: Point) -> NSPoint {
        NSPoint(x: point.x, y: point.y)
    }
}
