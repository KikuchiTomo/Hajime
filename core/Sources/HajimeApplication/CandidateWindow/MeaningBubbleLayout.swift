/// 語の意味の吹き出し(R-08)の置き方と形．候補の窓とは別の小さな窓で，先(三角)で選んでいる候補の行の縦の真ん中を指す．
///
/// - 先の頂点は，選んでいる行の右の端から gap(inline)の所に置く．吹き出しは候補の窓の空いている所に重ねてよいが，
///   ほかの候補・幹の文節・足元の案内・入力中の文字(obstacles)は覆わない
/// - 縦は，先が行を指す位置(先は見出しの行の高さ)にし，覆ってしまう物があれば上か下へ寄せる．画面の上下の端からは screenMargin の内側．
///   寄せた分だけ先の位置をずらし，行を指し続ける．先は角の丸みにはかけない
/// - 行の右に置けなければ(画面の右に入らない・寄せても覆う・先が行に届かない)，候補の窓の右の外，それも無理なら窓の左の外に置く
/// - 縁の線は本体と先を 1 本でなぞる(outline)
///
/// 座標は上が y の小さい側(画面の上の端が 0 に近い)．macOS は画面の座標(下が y の小さい側)から直して使う．
/// Windows の候補ウィンドウ(scene::bubble)は同じ決め方を Rust で持つ
public struct MeaningBubbleLayout: Sendable, Equatable {
    public typealias Box = MeaningCardLayout.Box

    public enum Side: Sendable, Equatable {
        /// 候補の窓の右(先は本体の左の辺)
        case right
        /// 候補の窓の左(先は本体の右の辺)
        case left
    }

    public struct Metrics: Sendable, Equatable {
        /// 本体の幅(縁を含み，先を除く)
        public var width: Double
        public var padding: Double
        public var radius: Double
        public var pointerLength: Double
        public var pointerWidth: Double
        /// 候補の窓の縁と先の頂点のあいだ
        public var gap: Double
        /// 画面の端に寄せたときの，吹き出しの縁と画面の端のあいだ
        public var screenMargin: Double

        public init(width: Double, padding: Double, radius: Double, pointerLength: Double, pointerWidth: Double, gap: Double, screenMargin: Double) {
            self.width = width
            self.padding = padding
            self.radius = radius
            self.pointerLength = pointerLength
            self.pointerWidth = pointerWidth
            self.gap = gap
            self.screenMargin = screenMargin
        }

        /// rounded は角丸のテーマか(platinum と desk は角を丸めない)
        public static func tokens(rounded: Bool) -> Metrics {
            Metrics(width: LayoutTokens.Bubble.width, padding: LayoutTokens.Bubble.padding, radius: rounded ? LayoutTokens.Bubble.radius : 0,
                    pointerLength: LayoutTokens.Bubble.pointerLength, pointerWidth: LayoutTokens.Bubble.pointerWidth,
                    gap: LayoutTokens.Bubble.gap, screenMargin: LayoutTokens.Bubble.screenMargin)
        }
    }

    public var side: Side
    /// 窓(本体と先)の枠．画面の座標
    public var window: Box
    /// 本体の枠．窓の中の座標
    public var body: Box
    /// 先の頂点の y．窓の中の座標
    public var pointerY: Double

    /// - Parameters:
    ///   - row: 選んでいる候補の行の地(画面の座標)．先はこの行の縦の真ん中を指す
    ///   - window: 候補の窓の本体の枠(画面の座標)
    ///   - size: 本体の大きさ
    ///   - preferredPointer: 本体の上の端から先までの長さ(見出しの行の真ん中)
    ///   - screen: 画面の使える範囲
    ///   - obstacles: 覆わない物(ほかの候補・幹の文節・足元の案内・入力中の文字．画面の座標)
    public init(row: Box, window candidate: Box, size: (width: Double, height: Double), preferredPointer: Double, screen: Box, obstacles: [Box],
                metrics: Metrics) {
        let screen = Box(x: screen.x + metrics.screenMargin, y: screen.y + metrics.screenMargin,
                         width: screen.width - metrics.screenMargin * 2, height: screen.height - metrics.screenMargin * 2)
        let windowWidth = size.width + metrics.pointerLength
        let targetY = row.midY
        let half = metrics.pointerWidth / 2
        let pointerRange = (metrics.radius + half)...(size.height - metrics.radius - half)
        // x(窓の左の端)に置いたときの縦の位置と先の位置．覆う物があれば上か下へ寄せる．置けなければ nil
        func vertical(at x: Double) -> (y: Double, pointer: Double)? {
            guard x >= screen.x, x + windowWidth <= screen.maxX else { return nil }
            var top = screen.y, bottom = screen.maxY
            for obstacle in obstacles where obstacle.x < x + windowWidth && x < obstacle.maxX {
                if obstacle.y >= targetY {
                    bottom = min(bottom, obstacle.y - metrics.gap)
                } else if obstacle.maxY <= targetY {
                    top = max(top, obstacle.maxY + metrics.gap)
                } else {
                    return nil
                }
            }
            guard bottom - top >= size.height else { return nil }
            let y = min(max(targetY - preferredPointer, top), bottom - size.height)
            guard pointerRange.contains(targetY - y) else { return nil }
            return (y, targetY - y)
        }
        let besideRow = (Side.right, row.maxX + metrics.gap)
        let outsideRight = (Side.right, candidate.maxX + metrics.gap)
        let outsideLeft = (Side.left, candidate.x - metrics.gap - windowWidth)
        let found = [besideRow, outsideRight, outsideLeft].lazy.compactMap { side, x in vertical(at: x).map { (side, x, $0.y, $0.pointer) } }.first
        // どこにも置けなければ，候補の窓の右の外に置いて画面の中へ寄せる(先は角の丸みにかけない範囲で行を指す)
        let (side, x, y, pointer) = found ?? {
            let x = max(min(outsideRight.1, screen.maxX - windowWidth), screen.x)
            let y = max(min(targetY - preferredPointer, screen.maxY - size.height), screen.y)
            return (Side.right, x, y, min(max(targetY - y, pointerRange.lowerBound), pointerRange.upperBound))
        }()
        self.side = side
        self.window = Box(x: x.rounded(), y: y.rounded(), width: windowWidth, height: size.height)
        body = Box(x: side == .right ? metrics.pointerLength : 0, y: 0, width: size.width, height: size.height)
        pointerY = pointer.rounded()
    }

    /// 縁の線がなぞる点．本体の角は丸め(corner)，先は 3 つの点でとがらせる．
    /// 線の太さ stroke の半分だけ内側を通し，線をピクセルにそろえる．左上の角の終わりから時計回り
    public enum Segment: Sendable, Equatable {
        case line(x: Double, y: Double)
        /// 角の丸み．corner は角の点，to は曲がり終える点(半径 radius)
        case corner(cornerX: Double, cornerY: Double, toX: Double, toY: Double, radius: Double)
    }

    public func outline(metrics: Metrics, stroke: Double) -> (startX: Double, startY: Double, segments: [Segment]) {
        let half = stroke / 2
        let left = body.x + half, right = body.maxX - half, top = body.y + half, bottom = body.maxY - half
        let radius = max(metrics.radius - half, 0)
        let tipHalf = metrics.pointerWidth / 2
        var segments: [Segment] = [.line(x: right - radius, y: top)]
        segments.append(.corner(cornerX: right, cornerY: top, toX: right, toY: top + radius, radius: radius))
        if side == .left {
            segments += [.line(x: right, y: pointerY - tipHalf), .line(x: right + metrics.pointerLength, y: pointerY), .line(x: right, y: pointerY + tipHalf)]
        }
        segments.append(.line(x: right, y: bottom - radius))
        segments.append(.corner(cornerX: right, cornerY: bottom, toX: right - radius, toY: bottom, radius: radius))
        segments.append(.line(x: left + radius, y: bottom))
        segments.append(.corner(cornerX: left, cornerY: bottom, toX: left, toY: bottom - radius, radius: radius))
        if side == .right {
            segments += [.line(x: left, y: pointerY + tipHalf), .line(x: left - metrics.pointerLength, y: pointerY), .line(x: left, y: pointerY - tipHalf)]
        }
        segments.append(.line(x: left, y: top + radius))
        segments.append(.corner(cornerX: left, cornerY: top, toX: left + radius, toY: top, radius: radius))
        return (left + radius, top, segments)
    }
}
