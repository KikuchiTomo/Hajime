import HajimeApplication
import HajimeDomain
import Testing

/// パレットの説明の欄の配置(R-26)．左の見本と右の情報の列，項目名と値の列，ベースラインの揃い，欄の高さを確かめる
@Suite("パレットの説明の欄の配置")
struct PalettePreviewLayoutTests {
    typealias Layout = PalettePreviewLayout

    /// 字の幅は書体の大きさの 0.6 倍(英数字)か 1 倍(日本語)．書体ごとに上下の高さを変え，ベースラインで揃えないと揃わないようにする
    struct Measuring: PalettePreviewMeasuring {
        static let sizes: [Layout.Role: Double] = [.heading: 13, .source: 10, .label: 10, .value: 11, .more: 11, .code: 10, .smallCode: 8]

        func width(_ text: String, _ role: Layout.Role) -> Double {
            let size = Self.sizes[role] ?? 10
            return text.reduce(0) { $0 + ($1.isASCII ? size * 0.6 : size) }
        }

        func ascent(_ role: Layout.Role) -> Double { (Self.sizes[role] ?? 10) * (role == .label ? 1.0 : 0.92) }
        func descent(_ role: Layout.Role) -> Double { (Self.sizes[role] ?? 10) * (role == .heading ? 0.3 : 0.24) }
    }

    static let metrics = Layout.Metrics(tileGap: 8, labelGap: 8, sourceGap: 8, rowGap: 4, chipPaddingX: 4, chipPaddingY: 2, chipGap: 4, unicodeNameLines: 2,
                                        headingHeight: 20, rowHeight: 16)
    static let labels = Layout.Labels(unicode: "Unicode", english: "英語", readings: "読み", shortcodes: "ショートコード", codePoints: "コードポイント",
                                      more: { "+\($0)" })
    static let pinWidth = 28.0
    static let pinIconSize = 14.0

    static let smile = PaletteItem(kind: .emoji, category: .smileys, text: "😄", japaneseName: "笑顔", nameReading: "えがお",
                                   englishName: "grinning face with smiling eyes", readings: ["すまいる", "はっぴー", "わーい", "えがお", "かお"],
                                   shortcodes: ["smile"])
    static let flag = PaletteItem(kind: .emoji, category: .flags, text: "🇯🇵", japaneseName: "旗: 日本", nameReading: "にっぽん", englishName: "flag: Japan",
                                  readings: ["こっき", "にほん"], shortcodes: ["jp", "flag-jp"])
    static let repeatOne = PaletteItem(kind: .emoji, category: .symbols, text: "🔂", japaneseName: "1 曲リピート", englishName: "repeat single button",
                                       readings: ["りぴーと"], shortcodes: ["repeat_one"])
    static let shobon = PaletteItem(kind: .kaomoji, category: .sorrow, text: "(´・ω・｀)", japaneseName: "しょぼーん", nameReading: "しょぼーん",
                                    readings: ["しょぼーん", "しょんぼり", "がっかり"])

    struct Placed {
        var layout: Layout
        var area: Layout.Box
        var tile: Layout.Box
        var height: Double
    }

    func place(_ item: PaletteItem, text: String? = nil, fields: PalettePanel.PreviewFields = .init(), tileWidth: Double = 48,
               shortcodes: [String]? = nil) -> Placed {
        var preview = PalettePanel.Preview(item: item, text: text ?? item.text, fields: fields, isPinned: false)
        if let shortcodes { preview.shortcodes = shortcodes }
        let height = Layout.height(fields: fields, kind: item.kind, tileHeight: 48, metrics: Self.metrics)
        let area = Layout.Box(x: 8, y: 4, width: 333, height: height)
        let tile = Layout.Box(x: area.x, y: area.y, width: tileWidth, height: 48)
        let layout = Layout(preview: preview, fields: fields, kind: item.kind, area: area, tile: tile, pinWidth: Self.pinWidth, labels: Self.labels,
                            measuring: Measuring(), metrics: Self.metrics)
        return Placed(layout: layout, area: area, tile: tile, height: height)
    }

    /// 項目名ごとの，値の 1 行目のベースライン(文字の値かタグ)
    func valueBaseline(after label: Layout.Text, in layout: Layout) -> Double? {
        let values = layout.texts.filter { $0.role == .value }.map(\.baseline) + layout.chips.map(\.baselines[0])
        return values.filter { $0 >= label.baseline - 0.5 }.min()
    }

    func expectAligned(_ placed: Placed, sourceLocation: SourceLocation = #_sourceLocation) {
        let layout = placed.layout
        let measuring = Measuring()
        // 値は，どの行も同じ x から書き出す(折り返した行と，行の頭のタグも)
        let lineStarts = layout.texts.filter { $0.role == .value }.map(\.x)
            + layout.chips.filter { chip in !layout.chips.contains { $0.frame.maxX <= chip.frame.x && $0.baselines[0] == chip.baselines[0] } }.map(\.frame.x)
        #expect(Set(lineStarts).count <= 1, sourceLocation: sourceLocation)
        #expect(lineStarts.allSatisfy { $0 == layout.valueX }, sourceLocation: sourceLocation)
        // 項目名は情報の列の左の端にそろい，ベースラインが値の 1 行目と同じ
        let labels = layout.texts.filter { $0.role == .label }
        #expect(Set(labels.map(\.x)).count <= 1, sourceLocation: sourceLocation)
        #expect(labels.allSatisfy { $0.x == placed.tile.maxX + Self.metrics.tileGap }, sourceLocation: sourceLocation)
        for label in labels {
            let value = valueBaseline(after: label, in: layout)
            #expect(value.map { abs($0 - label.baseline) <= 0.5 } == true, "\(label.text)", sourceLocation: sourceLocation)
        }
        // 見出しと添える文字のベースラインが同じ．ピン留めのアイコンの中心は見出しの行の中心
        let heading = layout.texts.filter { $0.role == .heading || $0.role == .source }.map(\.baseline)
        #expect(Set(heading).count == 1, sourceLocation: sourceLocation)
        #expect(layout.headingMidY == Layout.headingMidY(top: placed.area.y, metrics: Self.metrics), sourceLocation: sourceLocation)
        // 行の高さはトークンで決まり，文字は行の縦の真ん中に置く(見出しの行)
        if let name = heading.first {
            let top = name - measuring.ascent(.heading), bottom = name + measuring.descent(.heading)
            #expect(abs((top - placed.area.y) - (placed.area.y + Self.metrics.headingHeight - bottom)) <= 1, sourceLocation: sourceLocation)
        }
        // 部品どうし(見本とピン留めのアイコンを含む)が重ならず，欄の中に収まる
        let pin = Layout.Box(x: placed.area.maxX - Self.pinWidth / 2 - Self.pinIconSize / 2, y: layout.headingMidY - Self.pinIconSize / 2,
                             width: Self.pinIconSize, height: Self.pinIconSize)
        let frames = layout.frames(measuring) + [placed.tile, pin]
        for (index, frame) in frames.enumerated() {
            for other in frames[(index + 1)...] {
                #expect(!(frame.x < other.maxX && other.x < frame.maxX && frame.y < other.maxY && other.y < frame.maxY), "\(frame) \(other)",
                        sourceLocation: sourceLocation)
            }
        }
        for frame in layout.frames(measuring) {
            #expect(frame.x >= placed.area.x && frame.maxX <= placed.area.maxX + 0.001 && frame.y >= placed.area.y - 0.001
                    && frame.maxY <= placed.area.maxY + 0.001, "\(frame)", sourceLocation: sourceLocation)
        }
    }

    @Test("R-26: 情報は見本の右の列に置き，値の x と項目名と値のベースラインをそろえる")
    func aligned() {
        let placed = place(Self.smile)
        let layout = placed.layout
        expectAligned(placed)
        // 見本の下へ回り込ませない
        #expect(layout.frames(Measuring()).allSatisfy { $0.x >= placed.tile.maxX + Self.metrics.tileGap })
        #expect(layout.texts.filter { $0.role == .label }.map(\.text) == ["Unicode", "読み", "ショートコード", "コードポイント"])
        #expect(layout.texts.filter { $0.role == .value }.map(\.text) == ["SMILING FACE WITH OPEN MOUTH", "AND SMILING EYES", "えがお、すまいる、はっぴー、わーい"])
        #expect(layout.chips.map(\.lines) == [[":smile:"], ["U+1F604"]])
        #expect(layout.texts.first { $0.role == .source }?.text == "CLDR")
    }

    @Test("R-26: 欄の高さは設定で出る行がすべて出たときの高さで，行は中身どおりに上から詰め，典型の絵文字では最後の行の下に空きを残さない")
    func height() throws {
        let placed = place(Self.smile)
        let bottom = placed.layout.frames(Measuring()).map(\.maxY).max() ?? 0
        #expect(placed.area.maxY - bottom <= Self.metrics.rowGap)
        #expect(placed.area.maxY - bottom >= 0)
        // 項目を減らせば欄は低くなり，その項目名は出さない．値の x は出す項目名だけで決める
        let fewer = place(Self.smile, fields: .init(unicodeName: true, readings: false, shortcodes: false, codePoints: false))
        #expect(fewer.height < placed.height)
        #expect(fewer.layout.texts.filter { $0.role == .label }.map(\.text) == ["Unicode"])
        #expect(fewer.layout.valueX < placed.layout.valueX)
        expectAligned(fewer)
        // 何も出さなくても見本の高さは空ける
        let none = place(Self.smile, fields: .init(unicodeName: false, readings: false, shortcodes: false, codePoints: false))
        #expect(none.height == 48)
        // 種類ごとに，その種類で出る行の分だけの高さにする(顔文字は見出しと読み，記号はショートコードの行を取らない)
        let all = PalettePanel.PreviewFields()
        let emoji = Layout.height(fields: all, kind: .emoji, tileHeight: 48, metrics: Self.metrics)
        let symbol = Layout.height(fields: all, kind: .symbol, tileHeight: 48, metrics: Self.metrics)
        let kaomoji = Layout.height(fields: all, kind: .kaomoji, tileHeight: 48, metrics: Self.metrics)
        let expected: Double = 20 + 4 + 32 + 20 * 3
        #expect(emoji == expected)
        #expect(symbol == emoji - 20)
        #expect(kaomoji == 48)
        // 選んでいる文字が変わっても値の x は同じ
        #expect(place(Self.flag).layout.valueX == placed.layout.valueX)
        // 行は中身どおりに上から詰める(行の間はどこも 4)．Unicode の名前が 1 行の記号は，取っておいた 2 行目の分が最後の行の下に残る
        let arrow = PaletteItem(kind: .symbol, category: .arrows, text: "⇒", japaneseName: "右向き二重矢印", readings: ["やじるし"])
        let symbolPlaced = place(arrow)
        expectAligned(symbolPlaced)
        let valueLines = symbolPlaced.layout.texts.filter { $0.role == .value }.map(\.baseline)
        let labelBaselines = symbolPlaced.layout.texts.filter { $0.role == .label }.map(\.baseline)
        let row: Double = 16 + 4
        for (upper, lower) in zip(labelBaselines, labelBaselines.dropFirst()) {
            let lines = Double(valueLines.filter { $0 >= upper && $0 < lower }.count)
            #expect(lower - upper == row + 16 * (lines - 1))
        }

    }

    @Test("R-26: 並びの英語の名前は「英語」の行に出し，「CLDR」は見出しの 1 か所だけ")
    func english() {
        let placed = place(Self.flag)
        expectAligned(placed)
        let texts = placed.layout.texts
        #expect(texts.filter { $0.text == "CLDR" }.count == 1)
        #expect(texts.first { $0.role == .label }?.text == "英語")
        #expect(texts.contains { $0.role == .value && $0.text == "flag: Japan" })
        #expect(placed.layout.chips.map(\.lines) == [[":jp:"], [":flag-jp:"], ["U+1F1EF"], ["U+1F1F5"]])
    }

    @Test("R-26: Unicode の名前が 2 行に入らなければ，2 行目の末尾を「…」で省く")
    func longName() {
        let placed = place(Self.repeatOne)
        expectAligned(placed)
        let lines = placed.layout.texts.filter { $0.role == .value && $0.text.uppercased() == $0.text && $0.text.contains(" ") }
        #expect(lines.count == 2)
        #expect(lines.last?.text.hasSuffix("…") == true)
        #expect(lines.first?.text.hasPrefix("CLOCKWISE") == true)
    }

    @Test("R-26: 長いショートコードのチップで欄が足りなければ，Unicode の名前より先に読みを省く")
    func readingsFirst() {
        let item = PaletteItem(kind: .emoji, category: .symbols, text: "⏭️", japaneseName: "次の曲ボタン", nameReading: "つぎのきょくぼたん",
                               englishName: "next track button", readings: ["ぼたん", "つぎのしーん"],
                               shortcodes: ["black_right_pointing_double_triangle_with_vertical_bar"])
        let placed = place(item)
        expectAligned(placed)
        #expect(placed.layout.texts.filter { $0.role == .label }.map(\.text) == ["Unicode", "ショートコード", "コードポイント"])
        #expect(placed.layout.texts.filter { $0.role == .value }.map(\.text) == ["BLACK RIGHT-POINTING DOUBLE", "TRIANGLE WITH VERTICAL BAR"])
        #expect(placed.layout.chips.first?.lines.count == 2)
    }

    @Test("R-26: 顔文字は広い見本の右に名前と読みだけを出す")
    func kaomoji() {
        let placed = place(Self.shobon, tileWidth: 140)
        expectAligned(placed)
        #expect(placed.layout.texts.map(\.text) == ["しょぼーん", "読み", "しょんぼり、がっかり"])
        #expect(placed.layout.chips.isEmpty)
    }

    @Test("R-26: タグが入りきらなければ読みと Unicode の名前を詰め，それでも入らないタグは「+n」にまとめる．タグの字は切らない")
    func overflow() {
        let kiss = "👩🏽‍❤️‍💋‍👨🏿"
        let item = PaletteItem(kind: .emoji, category: .people, text: kiss, japaneseName: "キス", englishName: "kiss: woman, man, medium skin tone, dark skin tone",
                               readings: ["きす"], shortcodes: ["woman-kiss-man"])
        let long = "smiling_face_with_smiling_eyes_and_hand_covering_mouth"
        let placed = place(item, shortcodes: [":\(long):"])
        expectAligned(placed)
        let layout = placed.layout
        // 値の幅より広いショートコードは字を縮め，それでも入らなければタグの中で折り返す
        let wide = layout.chips.first { $0.role == .smallCode }
        #expect(wide?.lines.joined() == ":\(long):")
        // タグの中の行のベースラインも，値の行と同じ間隔で並ぶ
        let pitches = zip(wide?.baselines.dropFirst() ?? [], wide?.baselines ?? []).map { $0 - $1 }
        #expect(Set(pitches).count <= 1)
        #expect(layout.chips.allSatisfy { !$0.lines.joined().contains("…") })
        let shown = layout.chips.filter { $0.lines.first?.hasPrefix("U+") == true }.count
        let more = layout.texts.first { $0.role == .more }.flatMap { Int($0.text.dropFirst()) } ?? 0
        #expect(shown + more == kiss.unicodeScalars.count)
    }

    @Test("R-26: 折り返しは英数字の語の途中で分けず，日本語は句読点を行の頭に置かない")
    func lineBreaking() {
        let count: (String) -> Double = { Double($0.count) }
        #expect(PalettePreviewLayout.wrapped("SMILING FACE WITH OPEN MOUTH", width: 12, measure: count) == ["SMILING FACE", "WITH OPEN", "MOUTH"])
        #expect(PalettePreviewLayout.wrapped("SMILING FACE WITH OPEN MOUTH", width: 12, maxLines: 2, measure: count) == ["SMILING FACE", "WITH OPEN M…"])
        #expect(PalettePreviewLayout.wrapped("サウスジョージア・サウス", width: 8, measure: count) == ["サウスジョージ", "ア・サウス"])
        #expect(PalettePreviewLayout.wrapped(":face_with_hand:", width: 11, measure: count) == [":face_with_", "hand:"])
    }
}
