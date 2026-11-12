import HajimeApplication
import Testing

/// 候補の一覧の窓の区画の配置．縁の内側の余白，区切りの線の上と下の間隔，語の意味のカードの揃いを確かめる
@Suite("候補の一覧の窓の配置")
struct CandidateListLayoutTests {
    typealias Layout = CandidateListLayout

    static let rounded = Layout.Metrics.rounded(rowPitch: LayoutTokens.Glass.rowHeight, headerHeight: 20, footerHeight: 18)
    static let bevel = Layout.Metrics.bevel(rowPitch: LayoutTokens.Candidate.rowHeight, headerHeight: 20, footerHeight: 18, hasShadow: true)

    struct Sample: CustomTestStringConvertible, Sendable {
        var name: String
        var style: Layout.Style
        var hasHeader: Bool
        var card: Layout.Card?
        var testDescription: String { name }

        var metrics: Layout.Metrics { style == .rounded ? CandidateListLayoutTests.rounded : CandidateListLayoutTests.bevel }

        func place(rows: Int = 4, maximumWidth: Double = 720) -> Layout {
            Layout(style: style, listWidth: 180, footerWidth: 160, hasHeader: hasHeader, rowCount: rows, card: card, maximumWidth: maximumWidth, metrics: metrics)
        }
    }

    static let samples: [Sample] = [Layout.Style.rounded, .bevel].flatMap { style in
        [Sample(name: "\(style) カードなし", style: style, hasHeader: false, card: nil),
         Sample(name: "\(style) 文字種の行", style: style, hasHeader: true, card: nil),
         Sample(name: "\(style) 下のカード", style: style, hasHeader: false, card: .below(width: 312, height: 120)),
         Sample(name: "\(style) 文字種の行と下のカード", style: style, hasHeader: true, card: .below(width: 312, height: 120))]
    }

    @Test("縁の内側の余白は上下左右で同じ", arguments: samples)
    func windowPadding(sample: Sample) {
        let layout = sample.place()
        let parts = layout.parts
        let outer = sample.metrics.edge + sample.metrics.padding
        #expect(parts.map(\.x).min() == outer)
        #expect(parts.map(\.y).min() == outer)
        #expect(abs(layout.body.maxX - (parts.map(\.maxX).max() ?? 0) - outer) <= 0.5)
        #expect(abs(layout.body.maxY - (parts.map(\.maxY).max() ?? 0) - outer) <= 0.5)
        #expect(layout.width == layout.body.width + sample.metrics.shadow)
    }

    @Test("区切りの線の上と下は同じ間隔(候補の下のカードの上と下も)", arguments: samples)
    func separatorGaps(sample: Sample) throws {
        let layout = sample.place()
        let gap = sample.metrics.separatorGap
        let last = try #require(layout.rows.last)
        let above = layout.footerSeparator.y - max(last.maxY, layout.card?.maxY ?? 0)
        let below = layout.footer.y - layout.footerSeparator.maxY
        #expect(above == gap)
        #expect(below == gap)
        if let header = layout.header, let line = layout.headerSeparator, let first = layout.rows.first {
            #expect(line.y - header.maxY == gap)
            #expect(first.y - line.maxY == gap)
        }
        if case .below = sample.card, let card = layout.card {
            // platinum と desk は一覧とのあいだに区切りの線を引き，線の上と下を同じ空きにする
            if sample.style == .bevel, let line = layout.cardSeparator {
                #expect(line.y - last.maxY == gap)
                #expect(card.y - line.maxY == gap)
            } else {
                #expect(card.y - last.maxY == gap)
            }
        }
    }

    @Test("候補の下のカード: 左右の端は足元の区切りの線の端", arguments: samples.filter {
        if case .below = $0.card { return true }
        return false
    })
    func belowCard(sample: Sample) throws {
        let layout = sample.place()
        let card = try #require(layout.card)
        #expect(card.x == layout.footerSeparator.x)
        #expect(card.maxX == layout.footerSeparator.maxX)
    }

    @Test("候補の行の地は同じ x と幅で，行と行のあいだは rowInset の 2 倍．押せる範囲は隙間なく並ぶ", arguments: samples)
    func rows(sample: Sample) {
        let layout = sample.place()
        #expect(Set(layout.rows.map(\.x)).count == 1)
        #expect(Set(layout.rows.map(\.width)).count == 1)
        for (row, next) in zip(layout.rows, layout.rows.dropFirst()) {
            #expect(next.y - row.maxY == sample.metrics.rowInset * 2)
        }
        for (row, next) in zip(layout.hitRows, layout.hitRows.dropFirst()) {
            #expect(next.y == row.maxY)
        }
    }

    @Test("区画が重ならない", arguments: samples)
    func noOverlap(sample: Sample) {
        let layout = sample.place()
        let parts = layout.parts
        for (index, part) in parts.enumerated() {
            for other in parts[(index + 1)...] {
                #expect(!part.intersects(other), "\(part) と \(other)")
            }
        }
    }

    @Test("窓の幅の上限を超えるときは候補の列を狭め，候補の行と区切りの線の右の端はそろえたまま")
    func maximumWidth() throws {
        let wide = Layout(style: .rounded, listWidth: 800, footerWidth: 160, hasHeader: false, rowCount: 3, card: nil, maximumWidth: 720,
                          metrics: Self.rounded)
        #expect(wide.width <= 720)
        let first = try #require(wide.rows.first)
        #expect(first.maxX == wide.footerSeparator.maxX)
    }
}
