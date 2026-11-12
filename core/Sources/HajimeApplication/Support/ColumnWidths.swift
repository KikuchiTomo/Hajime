import Foundation

/// 表の列の幅を，中身の長さで配る(取り込む前に見せる表．macOS と Windows で同じ配り方)．
/// 中身の長い列ほど広くし，空いている列(中身が見出しより短い)は見出しの幅まで縮めて，その分を長い列に回す
public enum ColumnWidths {
    /// natural は列ごとの中身のいちばん長い幅，minimum は縮めてもよい幅(見出しの幅)，available は配る幅の合計．
    /// 収まるときは余りを中身の長さの割合で足し，収まらないときは最小を超える分を同じ割合で削る．最小の合計も収まらなければ最小を割合で縮める
    public static func distribute(natural: [Double], minimum: [Double], available: Double) -> [Double] {
        guard !natural.isEmpty, natural.count == minimum.count else { return [] }
        let wanted = zip(natural, minimum).map { max($0, $1) }
        let total = wanted.reduce(0, +)
        if total <= available {
            let extra = available - total
            return wanted.map { total > 0 ? $0 + extra * $0 / total : available / Double(wanted.count) }
        }
        let floor = minimum.reduce(0, +)
        guard floor < available else {
            return minimum.map { floor > 0 ? available * $0 / floor : 0 }
        }
        let shrinkable = total - floor
        let cut = total - available
        return zip(wanted, minimum).map { width, least in width - cut * (width - least) / shrinkable }
    }
}
