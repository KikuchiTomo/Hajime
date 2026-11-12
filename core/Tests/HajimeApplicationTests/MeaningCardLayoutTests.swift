import HajimeApplication
import Testing

/// 語の意味のカード(R-08)の配置．2 つの列の x，目印と文字の縦の揃い，例の縦の線，内側の余白，重なりを確かめる
@Suite("語の意味のカードの配置")
struct MeaningCardLayoutTests {
    typealias Layout = MeaningCardLayout

    /// 字の幅は書体の大きさの 0.6 倍(英数字)か 1 倍(日本語)．役割ごとに上下の高さを変え，行の箱で揃えないと揃わないようにする
    struct Measuring: MeaningCardMeasuring {
        static let sizes: [Layout.Role: Double] = [.headword: 15, .partOfSpeech: 10.5, .number: 10.5, .meaning: 13, .example: 12, .label: 11.5, .tag: 11.5]

        func width(_ text: String, _ role: Layout.Role) -> Double {
            let size = Self.sizes[role] ?? 10
            return text.reduce(0) { $0 + ($1.isASCII ? size * 0.6 : size) }
        }

        func ascent(_ role: Layout.Role) -> Double { (Self.sizes[role] ?? 10) * (role == .headword ? 0.95 : 0.88) }
        func descent(_ role: Layout.Role) -> Double { (Self.sizes[role] ?? 10) * (role == .number ? 0.12 : 0.24) }
    }

    static let metrics = Layout.Metrics.tokens

    static func content(senses: [Layout.Content.Sense] = [.init(number: "1", meaningLines: 1, exampleLines: 1),
                                                          .init(number: "2", meaningLines: 2, exampleLines: 1)],
                        others: [String] = ["取る", "採る", "執る", "捕る"], partOfSpeech: String? = "動詞") -> Layout.Content {
        Layout.Content(word: "撮る", partOfSpeech: partOfSpeech, senses: senses, others: others, othersLabel: "同音語")
    }

    static func place(_ content: Layout.Content = content(), width: Double = LayoutTokens.Meaning.listWidth) -> Layout {
        Layout(content: content, width: width, moreLabel: { "+\($0)" }, measuring: Measuring(), metrics: metrics)
    }

    static let samples: [(String, Layout.Content)] = [
        ("意味が 2 つで同音語あり", content()),
        ("意味が 1 つで例なし", content(senses: [.init(number: nil, meaningLines: 1, exampleLines: 0)], others: [])),
        ("意味が 3 つで折り返しあり", content(senses: [.init(number: "1", meaningLines: 3, exampleLines: 2), .init(number: "2", meaningLines: 1, exampleLines: 0),
                                              .init(number: "3", meaningLines: 2, exampleLines: 1)])),
        ("品詞なし", content(partOfSpeech: nil)),
        ("同音語が入りきらない", content(others: (1...12).map { "語\($0)" })),
    ]

    @Test("文の列の x は 1 か所: 見出しの語・意味・例の縦の線・「同音語」が同じ x から書き出す", arguments: samples.map(\.0))
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
        if let label = layout.othersLabel { #expect(label.line.x == x) }
        #expect(x == Self.metrics.padding + Self.metrics.markerWidth + Self.metrics.markerGap)
    }

    @Test("目印の列: アイコンと番号の札は同じ x・同じ幅で，その行の 1 行目の行の箱の縦の真ん中にある", arguments: samples.map(\.0))
    func markers(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        let markers = [layout.bookIcon] + layout.senses.compactMap(\.badge) + [layout.earIcon].compactMap { $0 }
        #expect(Set(markers.map(\.x)) == [Self.metrics.padding])
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
        if let ear = layout.earIcon, let label = layout.othersLabel {
            #expect(abs(ear.midY - label.line.box.midY) <= 0.5)
        }
    }

    @Test("札は語の行の箱の縦の真ん中: 品詞の札と同音語の札", arguments: samples.map(\.0))
    func chips(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        if let chip = layout.partOfSpeech {
            #expect(abs(chip.frame.midY - layout.headword.line.box.midY) <= 0.5)
            #expect(chip.frame.x - layout.headword.line.box.maxX >= Self.metrics.partOfSpeechGap - 0.5)
        }
        let label = layout.othersLabel
        for tag in layout.tags {
            #expect(abs(tag.frame.midY - (label?.line.box.midY ?? 0)) <= 0.5)
        }
        if let more = layout.more, let label { #expect(more.line.baseline == label.line.baseline) }
    }

    @Test("例の縦の線は例の文の行の箱の上の端から下の端まで", arguments: samples.map(\.0))
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

    @Test("内側の余白は上下左右で同じ", arguments: samples.map(\.0))
    func padding(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        let parts = layout.parts
        let top = parts.map(\.y).min() ?? 0
        let left = parts.map(\.x).min() ?? 0
        let bottom = layout.height - (parts.map(\.maxY).max() ?? 0)
        let padding = Self.metrics.padding
        #expect(abs(top - padding) <= 0.5)
        #expect(left == padding)
        // 下は高さを整数に切り上げる分(1 未満)だけ広くなることがある
        #expect(bottom >= padding - 0.5 && bottom < padding + 1)
        // 右: 区切りの線は左右の余白の内側いっぱい．文字と札は右の余白の内側に収まる
        if let separator = layout.separator {
            #expect(separator.x == padding)
            #expect(separator.maxX == layout.width - padding)
        }
        let textParts = layout.tags.map(\.frame) + [layout.partOfSpeech?.frame, layout.more?.line.box].compactMap { $0 }
        #expect(textParts.allSatisfy { $0.maxX <= layout.width - padding + 0.5 })
    }

    @Test("区切りの線の上と下は同じ間隔", arguments: samples.map(\.0).filter { $0 != "意味が 1 つで例なし" })
    func separatorGaps(name: String) throws {
        let layout = Self.place(try #require(Self.samples.first { $0.0 == name }?.1))
        let separator = try #require(layout.separator)
        let lastSense = try #require(layout.senses.last)
        let above = separator.y - (lastSense.example.last ?? lastSense.meaning.last)!.box.maxY
        let rowTop = ([layout.earIcon?.y, layout.othersLabel?.line.box.y] + layout.tags.map(\.frame.y)).compactMap { $0 }.min() ?? 0
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

    @Test("入らない同音語の札は「+n」にまとめ，右の余白の内側に収める")
    func moreTags() throws {
        let layout = Self.place(Self.content(others: (1...12).map { "語\($0)" }))
        let more = try #require(layout.more)
        #expect(more.text == "+\(12 - layout.tags.count)")
        #expect(more.line.box.maxX <= layout.width - Self.metrics.padding)
        #expect(!layout.tags.isEmpty)
    }

    @Test("長い見出しの語は品詞の札の手前で省く")
    func longHeadword() {
        var content = Self.content()
        content.word = String(repeating: "長", count: 40)
        let layout = Self.place(content)
        #expect(layout.headword.text.hasSuffix("…"))
        #expect((layout.partOfSpeech?.frame.maxX ?? 0) <= layout.width - Self.metrics.padding)
    }
}
