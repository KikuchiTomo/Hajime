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

    /// 置いた窓．次に置くときに，同じ側や候補が並び始める辺を保つのに使う
    public struct Placement: Sendable, Equatable {
        /// 窓の左下の座標と大きさ
        public var frame: Rect
        /// 置いたときの入力位置の行
        public var caret: Rect
        /// 入力位置の行の下と上のどちらに置いたか
        public var side: Side

        public init(frame: Rect, caret: Rect, side: Side) {
            self.frame = frame
            self.caret = caret
            self.side = side
        }
    }

    /// - Parameters:
    ///   - caret: 入力位置の行の長方形
    ///   - size: 候補ウィンドウの大きさ(x と y は使わない)
    ///   - screen: 入力位置がある画面の，使える範囲
    /// - Returns: 候補ウィンドウの左下の座標
    public static func origin(caret: Rect, size: Rect, screen: Rect) -> (x: Double, y: Double) {
        let frame = place(caret: caret, size: size, screen: screen, keeping: nil).frame
        return (frame.x, frame.y)
    }

    /// 前に置いた側(keeping)をなるべく保つ置き方．文節を移って窓の高さが変わるたびに上と下を行き来しないよう，
    /// 窓を出しているあいだは同じ側に置く．下に入らなくなったら上に移し，そのあとは下が空いても上のまま(上下に跳ねない)．
    /// 上に置いていて上にも入らないときだけ下に戻す．
    ///
    /// holding に前の窓を渡すと，候補が並び始める辺(上と左)を動かさない．候補を選んでいるあいだに使い，
    /// 使い分けの欄が出たりページが変わったりして窓の大きさが変わっても，同じ候補を同じ位置に出す．
    /// - 上に置くときは，入力位置の行が上下に動いていなければ上の辺を保つ．窓が低くなっても下げない．
    ///   高くなって入力位置の行に重なるときだけ上に伸ばす(下に置くときは，もともと上の辺が入力位置の行の下にある)
    /// - 入力位置が左右に動いていなければ左の辺を保つ．画面の右からはみ出すときだけ左に寄せる
    /// - Returns: 候補ウィンドウの位置と大きさ，置いた側
    public static func place(caret: Rect, size: Rect, screen: Rect, keeping side: Side?, holding held: Placement? = nil) -> Placement {
        let below = caret.y - gap - size.height
        let above = caret.maxY + gap
        let fitsBelow = below >= screen.y
        let fitsAbove = above + size.height <= screen.maxY
        let chosen: Side = switch side {
        case .above?: fitsAbove || !fitsBelow ? .above : .below
        case .below?, nil: fitsBelow ? .below : .above
        }
        var y = chosen == .below ? below : above
        if chosen == .above, let held, held.side == .above, held.caret.maxY == caret.maxY {
            y = max(held.frame.maxY - size.height, above)
        }
        y = min(max(y, screen.y), screen.maxY - size.height)
        var x = min(max(caret.x, screen.x), screen.maxX - size.width)
        if let held, held.caret.x == caret.x {
            x = max(min(held.frame.x, screen.maxX - size.width), screen.x)
        }
        return Placement(frame: Rect(x: x, y: y, width: size.width, height: size.height), caret: caret, side: chosen)
    }
}
