/// 画面の座標(左下が原点，上が y の正)の長方形．OS の型に依存しないための自前の型．
public struct Rect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

/// 候補ウィンドウを入力位置の近くに置く規則．画面からはみ出すときは上に出し，左右は画面の中に収める．
public enum PanelPlacement {
    /// 入力位置の行と候補ウィンドウのあいだの隙間
    public static let gap: Double = 4

    /// 候補ウィンドウを入力位置の行の下と上のどちらに置くか
    public enum Side: Sendable, Equatable {
        case below
        case above
    }

    /// - Parameters:
    ///   - caret: 入力位置の行の長方形
    ///   - size: 候補ウィンドウの大きさ(x と y は使わない)
    ///   - screen: 入力位置がある画面の，使える範囲
    /// - Returns: 候補ウィンドウの左下の座標
    public static func origin(caret: Rect, size: Rect, screen: Rect) -> (x: Double, y: Double) {
        let placed = place(caret: caret, size: size, screen: screen, keeping: nil)
        return (placed.x, placed.y)
    }

    /// 前に置いた側(keeping)をなるべく保つ置き方．文節を移って窓の高さが変わるたびに上と下を行き来しないよう，
    /// 窓を出しているあいだは同じ側に置く．下に入らなくなったら上に移し，そのあとは下が空いても上のまま(上下に跳ねない)．
    /// 上に置いていて上にも入らないときだけ下に戻す
    /// - Returns: 候補ウィンドウの左下の座標と，置いた側
    public static func place(caret: Rect, size: Rect, screen: Rect, keeping side: Side?) -> (x: Double, y: Double, side: Side) {
        let below = caret.y - gap - size.height
        let above = caret.maxY + gap
        let fitsBelow = below >= screen.y
        let fitsAbove = above + size.height <= screen.maxY
        let chosen: Side = switch side {
        case .above?: fitsAbove || !fitsBelow ? .above : .below
        case .below?, nil: fitsBelow ? .below : .above
        }
        var y = chosen == .below ? below : above
        y = min(max(y, screen.y), screen.maxY - size.height)
        let x = min(max(caret.x, screen.x), screen.maxX - size.width)
        return (x, y, chosen)
    }
}
