import HajimeApplication
import SwiftUI

/// 子を横に並べ，幅に収まらなければ次の行に送る(「試す」の結果のタグ，書き方のチップ)．並べ方は core の FlowLayout．
/// 1 行目の最初の子の文字のベースラインを，この部品のベースラインにする(Grid の .firstTextBaseline で見出しとそろえる)
struct WrappingStack: Layout {
    var spacing: CGFloat
    /// 行と行の間(省けば spacing)
    var rowSpacing: CGFloat?

    private var lineSpacing: CGFloat { rowSpacing ?? spacing }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (index, x) in zip(row.indices, row.xs) {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: bounds.minX + x, y: y), proposal: ProposedViewSize(size))
            }
            y += row.height + lineSpacing
        }
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                           cache: inout ()) -> CGFloat? {
        guard guide == .firstTextBaseline, let first = subviews.first else { return nil }
        return bounds.minY + first.dimensions(in: .unspecified)[.firstTextBaseline]
    }

    private struct Row {
        var indices: [Int] = []
        var xs: [CGFloat] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let placements = FlowLayout.place(widths: sizes.map { Double($0.width) }, spacing: Double(spacing), width: Double(width))
        var rows: [Row] = []
        for (index, placement) in placements.enumerated() {
            if placement.row >= rows.count { rows.append(Row()) }
            rows[placement.row].indices.append(index)
            rows[placement.row].xs.append(CGFloat(placement.x))
            rows[placement.row].width = CGFloat(placement.x) + sizes[index].width
            rows[placement.row].height = max(rows[placement.row].height, sizes[index].height)
        }
        return rows
    }
}
