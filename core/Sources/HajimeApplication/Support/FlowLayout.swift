/// チップを左から並べ，幅に収まらなければ次の行に送る並べ方．macOS の設定の画面のチップ(書き方のチップ・試した結果のチップ．WrappingStack)が使う．
/// Windows の設定の画面は settings の template_reference が同じ決まりで並べる
public enum FlowLayout {
    /// チップの左端(並べる欄の左端を 0 とする)と行の番号
    public struct Placement: Equatable, Sendable {
        public var x: Double
        public var row: Int

        public init(x: Double, row: Int) {
            self.x = x
            self.row = row
        }
    }

    /// widths のチップを，横に spacing の間をあけて幅 width に並べたときの置き場所．
    /// 行の先頭のチップは左端に置き，1 つで幅を超えるチップも行の先頭に置く(縮めない)
    public static func place(widths: [Double], spacing: Double, width: Double) -> [Placement] {
        var placements: [Placement] = []
        var x = 0.0
        var row = 0
        for itemWidth in widths {
            if x > 0, x + itemWidth > width {
                row += 1
                x = 0
            }
            placements.append(Placement(x: x, row: row))
            x += itemWidth + spacing
        }
        return placements
    }
}
