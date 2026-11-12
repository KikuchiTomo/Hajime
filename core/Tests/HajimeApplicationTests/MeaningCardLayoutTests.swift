import HajimeApplication
import Testing

/// 語の意味(R-08)の配置．2 つの列の x，目印と文字の縦の揃い，例の縦の線，見出しの行の位置，重なりを確かめる
@Suite("語の意味の配置")
struct MeaningCardLayoutTests {
    typealias Layout = MeaningCardLayout

    /// 字の幅は書体の大きさの 0.6 倍(英数字)か 1 倍(日本語)．役割ごとに上下の高さを変え，文字の箱で揃えないと揃わないようにする
    struct Measuring: MeaningCardMeasuring {
        static let sizes: [Layout.Role: Double] = [.headword: 15, .partOfSpeech: 10.5, .number: 10.5, .meaning: 13, .example: 12, .label: 11.5, .tag: 11.5]

        func width(_ text: String, _ role: Layout.Role) -> Double {
            let size = Self.sizes[role] ?? 10
            return text.reduce(0) { $0 + ($1.isASCII ? size * 0.6 : size) }
        }

        func ascent(_ role: Layout.Role) -> Double { (Self.sizes[role] ?? 10) * (role == .headword ? 0.95 : 0.88) }
        func descent(_ role: Layout.Role) -> Double { (Self.sizes[role] ?? 10) * (role == .number ? 0.12 : 0.24) }
        func size(_ role: Layout.Role) -> Double { Self.sizes[role] ?? 10 }
    }

    static let metrics = Layout.Metrics.tokens
    /// 候補の右に置くとき(目印の列はカードの左の端，見出しの行は候補の 1 行目の地 24 の真ん中)
    static let placement = Layout.Placement(left: 0, headerMidY: 12)

    static func content(senses: [Layout.Content.Sense] = [.init(number: "1", meaningLines: 1, exampleLines: 1),
                                                          .init(number: "2", meaningLines: 2, exampleLines: 1)],
                        others: [String] = ["取る", "採る", "執る", "捕る"], partOfSpeech: String? = "動詞") -> Layout.Content {
        Layout.Content(word: "撮る", partOfSpeech: partOfSpeech, senses: senses, others: others)
    }

    static func place(_ content: Layout.Content = content(), width: Double = LayoutTokens.Meaning.listWidth,
                      placement: Layout.Placement = placement) -> Layout {
        Layout(content: content, width: width, placement: placement, moreLabel: { "+\($0)" }, measuring: Measuring(), metrics: metrics)
    }

    static let samples: [(String, Layout.Content)] = [
        ("意味が 2 つで同音語あり", content()),
        ("意味が 1 つで例なし", content(senses: [.init(number: nil, meaningLines: 1, exampleLines: 0)], others: [])),
        ("意味が 3 つで折り返しあり", content(senses: [.init(number: "1", meaningLines: 3, exampleLines: 2), .init(number: "2", meaningLines: 1, exampleLines: 0),
                                              .init(number: "3", meaningLines: 2, exampleLines: 1)])),
        ("品詞なし", content(partOfSpeech: nil)),
        ("同音語が入りきらない", content(others: (1...12).map { "語\($0)" })),
    ]

    @Test("文の列の x は 1 か所: 見出しの語・意味・例の縦の線・同音語の札が同じ x から書き出す", arguments: samples.map(\.0))
    func textColumn(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        let x = layout.columns.textX
        #expect(layout.headword.line.x == x)
        for sense in layout.senses {
            #expect(sense.meaning.allSatisfy { $0.x == x })
            if let bar = sense.exampleBar { #expect(bar.x == x) }
            // 例は文の列の中で 1 段(トークン 1 つ)下げ，折り返した行もその x にそろえる
            #expect(sense.example.allSatisfy { $0.x == x + Self.metrics.exampleIndent })
        }
        if let first = layout.tags.first { #expect(first.frame.x == x) }
        #expect(x == Self.placement.left + Self.metrics.markerWidth + Self.metrics.markerGap)
    }

    @Test("候補の下に置くときは，目印の列の左の端を placement.left にずらす")
    func placementLeft() {
        let layout = Self.place(placement: .init(left: 4, headerMidY: 8))
        #expect(layout.bookIcon.x == 4)
        #expect(layout.columns.textX == 4 + Self.metrics.markerWidth + Self.metrics.markerGap)
        // 区切りの線は場所の幅いっぱい(窓のほかの区切りの線と端をそろえる)
        #expect(layout.separator?.x == 0)
        #expect(layout.separator?.maxX == layout.width)
    }

    @Test("目印の列: アイコンと番号の札は同じ x・同じ幅で，その行の 1 行目の文字の箱の縦の真ん中にある", arguments: samples.map(\.0))
    func markers(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        let markers = [layout.bookIcon] + layout.senses.compactMap(\.badge) + [layout.earIcon].compactMap { $0 }
        #expect(Set(markers.map(\.x)) == [Self.placement.left])
        #expect(Set(markers.map(\.width)) == [Self.metrics.markerWidth])
        #expect(abs(layout.bookIcon.midY - layout.headword.line.box.midY) <= 0.5)
        for sense in layout.senses {
            guard let badge = sense.badge, let first = sense.meaning.first else { continue }
            #expect(abs(badge.midY - first.box.midY) <= 0.5)
            // 番号の文字も札の真ん中
            let number = try #require(sense.number)
            #expect(abs(number.line.box.midY - badge.midY) <= 0.5)
            #expect(abs(number.line.box.midX - badge.midX) <= 0.5)
        }
    }

    @Test("見出しの行の縦の真ん中は，候補の 1 行目の真ん中(placement.headerMidY)", arguments: samples.map(\.0))
    func header(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        #expect(abs(layout.headerMidY - Self.placement.headerMidY) <= 0.5)
        #expect(abs(layout.headword.line.box.midY - Self.placement.headerMidY) <= 0.5)
        // 見出しの行の上の端(目印・札)がカードの上の端
        let height = Layout.headerHeight(measuring: Measuring(), metrics: Self.metrics)
        #expect(abs((layout.parts.map(\.y).min() ?? 0) - (Self.placement.headerMidY - height / 2)) <= 0.5)
    }

    @Test("札は行の文字の箱(または耳のアイコン)の縦の真ん中: 品詞の札と同音語の札", arguments: samples.map(\.0))
    func chips(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        if let chip = layout.partOfSpeech {
            #expect(abs(chip.frame.midY - layout.headword.line.box.midY) <= 0.5)
            #expect(chip.frame.x - layout.headword.line.box.maxX >= Self.metrics.partOfSpeechGap - 0.5)
        }
        for tag in layout.tags {
            #expect(abs(tag.frame.midY - (layout.earIcon?.midY ?? 0)) <= 0.5)
        }
        if let more = layout.more, let ear = layout.earIcon { #expect(abs(more.line.box.midY - ear.midY) <= 0.5) }
    }

    @Test("例の縦の線は例の文の文字の箱の上の端から下の端まで", arguments: samples.map(\.0))
    func exampleBar(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        for sense in layout.senses where !sense.example.isEmpty {
            let bar = try #require(sense.exampleBar)
            let first = try #require(sense.example.first), last = try #require(sense.example.last)
            #expect(bar.y == first.box.y)
            #expect(bar.maxY == last.box.maxY)
            #expect(bar.width == Self.metrics.exampleBarWidth)
            #expect(bar.maxX < first.x)
        }
    }

    @Test("左の端は目印の列，右の端はカードの幅，下の端は最後の部品", arguments: samples.map(\.0))
    func edges(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        let parts = layout.parts
        #expect(parts.map(\.x).min() == Self.placement.left)
        let bottom = layout.height - (parts.map(\.maxY).max() ?? 0)
        #expect(bottom >= 0 && bottom < 1)
        if let separator = layout.separator {
            #expect(separator.x == 0)
            #expect(separator.maxX == layout.width)
        }
        let textParts = layout.tags.map(\.frame) + [layout.partOfSpeech?.frame, layout.more?.line.box].compactMap { $0 }
        #expect(textParts.allSatisfy { $0.maxX <= layout.width + 0.5 })
    }

    @Test("区切りの線の上と下は同じ間隔", arguments: samples.map(\.0).filter { $0 != "意味が 1 つで例なし" })
    func separatorGaps(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        let separator = try #require(layout.separator)
        let lastSense = try #require(layout.senses.last)
        let above = separator.y - (lastSense.example.last ?? lastSense.meaning.last)!.box.maxY
        let rowTop = ([layout.earIcon?.y] + layout.tags.map(\.frame.y)).compactMap { $0 }.min() ?? 0
        let below = rowTop - separator.maxY
        #expect(abs(above - Self.metrics.othersGap) <= 0.5)
        #expect(abs(below - Self.metrics.othersGap) <= 1)
    }

    @Test("部品が重ならない", arguments: samples.map(\.0))
    func noOverlap(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        let parts = layout.parts
        for (index, part) in parts.enumerated() {
            for other in parts[(index + 1)...] {
                #expect(!part.intersects(other), "\(part) と \(other)")
            }
        }
    }

    @Test("入らない同音語の札は「+n」にまとめ，カードの幅に収める")
    func moreTags() throws {
        let layout = Self.place(Self.content(others: (1...12).map { "語\($0)" }))
        let more = try #require(layout.more)
        #expect(more.text == "+\(12 - layout.tags.count)")
        #expect(more.line.box.maxX <= layout.width)
        #expect(!layout.tags.isEmpty)
    }

    @Test("長い見出しの語は品詞の札の手前で省く")
    func longHeadword() {
        var content = Self.content()
        content.word = String(repeating: "長", count: 40)
        let layout = Self.place(content)
        #expect(layout.headword.text.hasSuffix("…"))
        #expect((layout.partOfSpeech?.frame.maxX ?? 0) <= layout.width)
    }
}
