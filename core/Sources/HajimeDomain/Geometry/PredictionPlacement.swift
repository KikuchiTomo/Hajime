/// 続く語句の予測の窓を，組み立て中の文字の最後の字のすぐ右に置く規則．
/// 組み立て中の文字(ライブ変換で見せている文も同じ文字)と，入力中の候補の窓に重ねない．
public enum PredictionPlacement {
    /// - Parameters:
    ///   - tail: 組み立て中の文字の最後の字の長方形(横は字の幅，縦は行の高さ)
    ///   - size: 予測の窓の大きさ(x と y は使わない)
    ///   - screen: 入力位置がある画面の，使える範囲
    ///   - gap: 最後の字と予測の窓のあいだ
    ///   - candidates: 候補の窓を置いている(置く)側．予測の窓は行より高いことがあるので，その側へは行と候補の窓のあいだ(PanelPlacement.gap)までしか出さない
    /// - Returns: 予測の窓の左下の座標
    ///
    /// ふつうは最後の字の右に，行の高さの中央をそろえて置く．画面の右に入らないときは，左へ寄せると組み立て中の文字に重なるので，
    /// 画面の右端にそろえて行の外(候補の窓と反対の側)に置く
    public static func origin(tail: Rect, size: Rect, screen: Rect, gap: Double, candidates: PanelPlacement.Side) -> (x: Double, y: Double) {
        var x = tail.maxX + gap
        var y = tail.y + (tail.height - size.height) / 2
        if x + size.width > screen.maxX {
            x = screen.maxX - size.width
            y = candidates == .below ? tail.maxY + gap : tail.y - gap - size.height
        } else {
            switch candidates {
            case .below: y = max(y, tail.y - PanelPlacement.gap)
            case .above: y = min(y, tail.maxY + PanelPlacement.gap - size.height)
            }
        }
        return (max(x, screen.x), min(max(y, screen.y), screen.maxY - size.height))
    }
}
