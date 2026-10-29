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

    /// - Parameters:
    ///   - caret: 入力位置の行の長方形
    ///   - size: 候補ウィンドウの大きさ(x と y は使わない)
    ///   - screen: 入力位置がある画面の，使える範囲
    /// - Returns: 候補ウィンドウの左下の座標
    public static func origin(caret: Rect, size: Rect, screen: Rect) -> (x: Double, y: Double) {
        var y = caret.y - gap - size.height
        if y < screen.y {
            y = caret.maxY + gap
        }
        y = min(max(y, screen.y), screen.maxY - size.height)
        let x = min(max(caret.x, screen.x), screen.maxX - size.width)
        return (x, y)
    }
}
