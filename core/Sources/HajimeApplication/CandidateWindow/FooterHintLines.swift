/// 候補の窓の足元のキーの案内を，窓の幅に収まるように行に分ける(R-17)．
///
/// - 1 行目は，右に置く物(連想の知らせ・位置・辞書の名前)の分を除いた幅 first に入るだけの案内を，先頭から置く
/// - 入らない案内は 2 行目から足元の幅 rest に入るだけ置き，それでも残れば次の行に置く．案内は省かない
/// - 行の幅より広い案内は，その行に 1 つだけ置く(省かずに見せる)
/// - 1 行目に 1 つも入らなければ 1 行目は空にする(右に置く物は 1 行目のまま)
///
/// macOS の BranchView が使う．返す範囲は widths の添え字で，1 行目は必ず含む(案内が無ければ空の 1 行)
public enum FooterHintLines {
    public static func split(widths: [Double], gap: Double, first: Double, rest: Double) -> [Range<Int>] {
        var lines: [Range<Int>] = []
        var start = 0
        var used = 0.0
        var limit = first
        for (index, width) in widths.enumerated() {
            let next = index == start ? width : used + gap + width
            if next <= limit || (index == start && !lines.isEmpty) {
                used = next
                continue
            }
            // 入らない．今の行を閉じて次の行の頭に置く(1 行目が空のまま閉じることもある)
            lines.append(start..<index)
            start = index
            used = width
            limit = rest
        }
        lines.append(start..<widths.count)
        return lines
    }
}
