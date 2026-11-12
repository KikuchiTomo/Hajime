import HajimeApplication
import HajimeDomain
import Testing

/// パレットの窓の部品の位置(R-26)．窓の内側の余白・区切りの上下の間隔・右の端・足元・種類で変えない窓の大きさを確かめる
@Suite("パレットの窓の配置")
struct PaletteWindowLayoutTests {
    typealias Layout = PaletteWindowLayout
    typealias Box = PalettePreviewLayout.Box

    static let metrics = Layout.Metrics(padding: 12, sectionGap: 12, groupGap: 8, itemGap: 4, controlHeight: 28, textRowHeight: 16, scrollbarWidth: 3,
                                        lineWidth: 1, footerHeight: 17, border: 0, shadow: 0)
    static let previewMetrics = PalettePreviewLayout.Metrics(tileGap: 8, labelGap: 8, sourceGap: 8, rowGap: 4, chipPaddingX: 4, chipPaddingY: 2,
                                                             chipGap: 4, unicodeNameLines: 2, headingHeight: 20, rowHeight: 16)

    func layout(kind: PaletteItem.Kind, fields: PalettePanel.PreviewFields? = .init(), metrics: Layout.Metrics = metrics, cellSize: Double = 36,
                rows: Int = 6) -> Layout {
        let height = { (kind: PaletteItem.Kind) in
            fields.map { PalettePreviewLayout.height(fields: $0, kind: kind, tileHeight: 48, metrics: Self.previewMetrics) }
        }
        let extra = Layout.extraRows(previewHeight: height(kind), windowPreviewHeight: height(.emoji), cellSize: cellSize)
        return Layout(columns: 9, visibleRows: rows + extra, cellSize: cellSize, tabCount: 10, modeWidths: [52, 40, 52], previewHeight: height(kind),
                      metrics: metrics)
    }

    @Test("R-26: 窓の内側の余白は上下左右とも同じで，中身の右の端は 1 か所にそろう")
    func padding() {
        for border in [0.0, 2.0] {
            let layout = layout(kind: .emoji, metrics: Layout.Metrics(padding: 12, sectionGap: 12, groupGap: 8, itemGap: 4, controlHeight: 28,
                                                                     textRowHeight: 16, scrollbarWidth: 3, lineWidth: 1, footerHeight: 17,
                                                                     border: border, shadow: border))
            let top = layout.search.y - layout.body.y
            let left = layout.content.x - layout.body.x
            let right = layout.body.maxX - layout.content.maxX
            let bottom = layout.body.maxY - layout.footer.maxY
            #expect(Set([top, left, right, bottom]) == [12 + border])
            #expect(layout.width == layout.body.width + border)
            let rights = [layout.modes.last?.maxX, layout.search.maxX + 8 + 144, layout.scrollbar.maxX, layout.skinToneButton.maxX,
                          layout.preview?.maxX, layout.footer.maxX]
            #expect(Set(rights.compactMap { $0 }) == [layout.content.maxX])
        }
    }

    @Test("R-26: 区切りの線の上と下の間隔は，どの種類でも区画のあいだの 12")
    func separators() {
        for kind in PaletteItem.Kind.allCases {
            let layout = layout(kind: kind)
            let preview = try! #require(layout.preview)
            #expect(layout.separators.count == 2)
            #expect(layout.separators[0] - layout.grid.maxY == 12, "\(kind)")
            #expect(preview.y - (layout.separators[0] + 1) == 12, "\(kind)")
            #expect(layout.separators[1] - preview.maxY == 12, "\(kind)")
            #expect(layout.footer.y - (layout.separators[1] + 1) == 12, "\(kind)")
        }
        // 説明を出さなければ，マス目と足元のあいだの区切り 1 本だけ
        let hidden = layout(kind: .emoji, fields: nil)
        #expect(hidden.separators.count == 1)
        #expect(hidden.separators[0] - hidden.grid.maxY == 12)
        #expect(hidden.footer.y - (hidden.separators[0] + 1) == 12)
    }

    @Test("R-26: 説明の欄が低い種類は，回せる分をマス目の行に回し，回しきれない端の分だけ窓を低くする．幅は変えない")
    func rowsByKind() {
        let emoji = layout(kind: .emoji)
        let symbol = layout(kind: .symbol)
        let kaomoji = layout(kind: .kaomoji)
        for other in [symbol, kaomoji] {
            #expect(other.width == emoji.width)
        }
        // 顔文字は説明の欄が 68 低い．1 行(36)をマス目に回し，残りの 32 だけ窓を低くする
        #expect(kaomoji.grid.height == emoji.grid.height + 36)
        #expect(emoji.height - kaomoji.height == 32)
        // 記号は 20 低いので行は回さず，20 だけ窓を低くする
        #expect(symbol.grid.height == emoji.grid.height)
        #expect(emoji.height - symbol.height == 20)
    }

    @Test("R-26: 足元のキーキャップと肌の色のボタンは同じ高さと縦の中心で，上下の余白が等しい")
    func footer() {
        let layout = layout(kind: .emoji)
        #expect(layout.skinToneButton.height == layout.footer.height)
        #expect(layout.skinToneButton.midY == layout.footer.midY)
        let above = layout.footer.y - ((layout.separators.last ?? 0) + 1)
        let below = layout.body.maxY - layout.footer.maxY
        #expect(above == below)
    }

    @Test("R-26: 絵文字は実際の外形の中心を箱の中心に合わせ，上下左右の余白の差を 1 以内にする")
    func inkCentering() {
        // 右と下に寄った外形(描く原点からの位置)
        let ink = Box(x: 0.25, y: 3, width: 12.5, height: 12)
        let box = Box(x: 100, y: 40, width: 17, height: 17)
        let origin = Layout.centeredOrigin(ink: ink, in: box)
        let drawn = Box(x: origin.x + ink.x, y: origin.y + ink.y, width: ink.width, height: ink.height)
        #expect(abs((drawn.x - box.x) - (box.maxX - drawn.maxX)) <= 1)
        #expect(abs((drawn.y - box.y) - (box.maxY - drawn.maxY)) <= 1)
    }
}
