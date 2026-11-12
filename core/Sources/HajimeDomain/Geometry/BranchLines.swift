/// 分岐図の枝の線の配置(ADR 0007)．
///
/// 幹の文節のタグの端から 1 本の縦の線(幹)を伸ばし，候補ごとに同じ半径の 4 分の 1 の円で曲がって，
/// 水平の線で候補の行の手前まで伸ばす．直線の枝は半径を 0 にした同じ形(直角に曲がる)にする．
/// - 曲がり角の形と水平の線の終わりの x は，どの候補でも同じ
/// - 幹はいちばん遠い候補の曲がり角の始まりで終わる(先を飛び出させない)
/// - 曲がり角と水平の線は，隣の候補のものと重ならない．幹は 1 本だけで，候補ごとに描くのは曲がり角と水平の線だけ
///
/// 線の端をデバイスのピクセルの境にそろえる．太さが奇数のピクセルの線は，中心を半ピクセルずらす．
/// 座標は上が y の小さい側．macOS の BranchView がこの配置を描き，Windows の候補ウィンドウ(scene::branch_lines)は同じ決め方を Rust で持つ
public struct BranchLines: Sendable, Equatable {
    /// 1 つの候補への曲がり角と水平の線
    public struct Turn: Sendable, Equatable {
        /// 幹から離れ始める点(幹の上)
        public var start: Point
        /// 4 分の 1 の円の中心．直角なら end と同じ
        public var center: Point
        /// 曲がり終えた点．ここから水平の線が始まる
        public var end: Point
        /// 水平の線の終わり(候補の行の手前)
        public var tip: Point
    }

    /// 幹の根元(文節のタグの端)
    public var root: Point
    /// 幹の先(いちばん遠い候補の曲がり角の始まり)．候補が無ければ根元と同じ
    public var stemEnd: Point
    /// 曲がり角の半径．すべての候補で同じ
    public var radius: Double
    /// 幹に近い順
    public var turns: [Turn]

    /// - Parameters:
    ///   - stemX: 幹の x
    ///   - rootY: 幹の根元の y．下へ伸ばすなら文節のタグの下の端，上へ伸ばすなら上の端
    ///   - rowMidYs: 候補の行の縦の中心．幹に近い順に並べる．根元より大きければ下へ，小さければ上へ伸ばす
    ///   - tipX: 水平の線の終わりの x
    ///   - radius: 曲がり角の半径．0 なら直角．根元から最初の行まで，または行と行のあいだ(線の太さの分を除く)に入らなければ縮める
    ///   - lineWidth: 線の太さ
    ///   - scale: 1 ポイントあたりのデバイスのピクセル数
    public init(stemX: Double, rootY: Double, rowMidYs: [Double], tipX: Double, radius: Double, lineWidth: Double, scale: Double) {
        let x = Self.alignCenter(stemX, lineWidth: lineWidth, scale: scale)
        let rootY = Self.alignEdge(rootY, scale: scale)
        let tipX = Self.alignEdge(tipX, scale: scale)
        let mids = rowMidYs.map { Self.alignCenter($0, lineWidth: lineWidth, scale: scale) }
        let direction: Double = (mids.first ?? rootY) < rootY ? -1 : 1
        // 半径は，根元から最初の行まで・行と行のあいだ(線の太さの分の隙間を残す)・水平の線の長さのどれにも収める
        var limit = max(min(radius, tipX - x), 0)
        if let first = mids.first { limit = min(limit, abs(first - rootY)) }
        for (near, far) in zip(mids, mids.dropFirst()) { limit = min(limit, max(abs(far - near) - lineWidth, 0)) }
        let radius = Self.alignEdge(limit, scale: scale, rule: .down)
        root = Point(x: x, y: rootY)
        self.radius = radius
        turns = mids.map { mid in
            let startY = mid - direction * radius
            return Turn(start: Point(x: x, y: startY), center: Point(x: x + radius, y: startY),
                        end: Point(x: x + radius, y: mid), tip: Point(x: tipX, y: mid))
        }
        stemEnd = turns.last?.start ?? root
    }

    /// 幹のうち，index 番目の候補の曲がり角より先の部分．index が nil なら幹の全体．無ければ nil．
    /// 選んでいる候補への道(根元からその曲がり角まで)を別の色で描くとき，残りの幹をこれで描く
    public func stem(after index: Int?) -> (from: Point, to: Point)? {
        let from = index.map { turns[$0].start } ?? root
        return from == stemEnd ? nil : (from, stemEnd)
    }

    /// 線の端がデバイスのピクセルの境に来る，線の中心の座標
    public static func alignCenter(_ value: Double, lineWidth: Double, scale: Double) -> Double {
        let pixels = lineWidth * scale
        return ((value * scale - pixels / 2).rounded() + pixels / 2) / scale
    }

    /// デバイスのピクセルの境の座標
    public static func alignEdge(_ value: Double, scale: Double, rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Double {
        (value * scale).rounded(rule) / scale
    }
}
