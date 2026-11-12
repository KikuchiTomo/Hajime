import HajimeDomain

/// パレットの説明の欄の配置(R-26)．左に見本の四角，右に情報の列を置く 2 段の配置にし，情報は見本の下へ回り込ませない．
///
/// 情報の列は，上に見出しの行，その下に「項目名 → 値」の表を置く．
/// - 見出しの行: 名前を大きく出し，名前を定めたところ(CLDR)を同じベースラインに小さく添える．ピン留めのボタンは見出しの行の縦の中心に置く
/// - 表: 項目名はいちばん長い項目名の幅の列に置き，値はどの行も同じ x から書き出す．折り返した値の 2 行目以降も値の x にそろえる
/// - 項目名と値は文字のベースラインで合わせる．ショートコードとコードポイントの札も，中の文字のベースラインを項目名に合わせる
/// - 行の間は metrics.rowGap 1 つ
///
/// 欄の高さ(height)は，設定で出る行がすべて出たときの高さ(Unicode の名前は metrics.unicodeNameLines 行)にし，選んでいる文字では変えない．
/// Unicode の名前がその行数に入らなければ末尾を「…」で省く(読み上げでは全体を伝える)．中身が欄に入りきらなければ
/// (長いショートコードや多くのコードポイントの札が何行にもなるとき)，読みを省き，Unicode の名前を 1 行にし，Unicode の名前を省く順に詰め，
/// それでも入らない札は「+n」にまとめる．
///
/// 文字の幅と書体の高さは描く側が測る(PalettePreviewMeasuring)．座標は上が y の小さい側．
/// macOS の PalettePreviewDrawing がこの配置を描き，Windows の候補ウィンドウ(palette::preview)は同じ決め方を Rust で持つ
public struct PalettePreviewLayout: Sendable, Equatable {
    /// 文字の役割．描く側が役割ごとに書体と色を決める
    public enum Role: Sendable, Hashable, CaseIterable {
        /// 見出しの名前
        case heading
        /// 見出しに添える，名前を定めたところ
        case source
        /// 表の項目名
        case label
        /// 表の値(Unicode の名前と読み)
        case value
        /// 入らなかった読みや札の数(「+n」)
        case more
        /// ショートコードとコードポイントの札の文字
        case code
        /// 行に入らない札を縮めた文字
        case smallCode
    }

    /// 長方形．上が y の小さい側
    public struct Box: Sendable, Equatable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
        public var midY: Double { y + height / 2 }

        func intersects(_ other: Box) -> Bool {
            x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
        }
    }

    /// 1 行の文字．x から書き，baseline に文字のベースラインを置く
    public struct Text: Sendable, Equatable {
        public var text: String
        public var role: Role
        public var x: Double
        public var baseline: Double
        public var width: Double
    }

    /// 等幅の文字の札．lines は札の中の行(行より広い札だけ 2 行以上)で，baselines はその行のベースライン
    public struct Chip: Sendable, Equatable {
        public var lines: [String]
        public var role: Role
        public var frame: Box
        public var textX: Double
        public var baselines: [Double]
    }

    /// 表の項目名．文言は描く側(UIStrings・strings.rs)が渡す
    public struct Labels: Sendable {
        public var unicode: String
        /// UCD の名前の無い並びで，代わりに出す英語の名前
        public var english: String
        public var readings: String
        public var shortcodes: String
        public var codePoints: String
        /// 入らなかった読みや札の数
        public var more: @Sendable (Int) -> String

        public init(unicode: String, english: String, readings: String, shortcodes: String, codePoints: String, more: @escaping @Sendable (Int) -> String) {
            self.unicode = unicode
            self.english = english
            self.readings = readings
            self.shortcodes = shortcodes
            self.codePoints = codePoints
            self.more = more
        }
    }

    /// 寸法(描く側がデザイントークンから渡す)
    public struct Metrics: Sendable {
        /// 見本の四角と情報の列のあいだ
        public var tileGap: Double
        /// 項目名の列と値のあいだ
        public var labelGap: Double
        /// 見出しの名前と，名前を定めたところのあいだ
        public var sourceGap: Double
        /// 行と行のあいだ
        public var rowGap: Double
        public var chipPaddingX: Double
        public var chipPaddingY: Double
        /// 札と札のあいだ(横)
        public var chipGap: Double
        /// Unicode の名前の行の数の上限(欄の高さもこの数で見込む)
        public var unicodeNameLines: Int

        public init(tileGap: Double, labelGap: Double, sourceGap: Double, rowGap: Double, chipPaddingX: Double, chipPaddingY: Double, chipGap: Double,
                    unicodeNameLines: Int) {
            self.tileGap = tileGap
            self.labelGap = labelGap
            self.sourceGap = sourceGap
            self.rowGap = rowGap
            self.chipPaddingX = chipPaddingX
            self.chipPaddingY = chipPaddingY
            self.chipGap = chipGap
            self.unicodeNameLines = max(unicodeNameLines, 1)
        }
    }

    public var texts: [Text]
    public var chips: [Chip]
    /// 見出しの行の縦の中心．ピン留めのボタンをここに合わせる
    public var headingMidY: Double
    /// 値を書き出す x(表の行が無ければ情報の列の左の端)
    public var valueX: Double

    // MARK: - 高さ

    /// 欄の中身の高さ(上下の余白を除く)．見本の高さと，設定で出る行がすべて出たときの高さの大きいほう
    public static func height(fields: PalettePanel.PreviewFields, tileHeight: Double, measuring: some PalettePreviewMeasuring, metrics: Metrics) -> Double {
        let rows = Rows(measuring: measuring, metrics: metrics)
        var height = rows.heading.height
        if fields.unicodeName { height += metrics.rowGap + rows.text.height(lines: metrics.unicodeNameLines) }
        if fields.readings { height += metrics.rowGap + rows.text.height(lines: 1) }
        if fields.shortcodes { height += metrics.rowGap + rows.chip.height(lines: 1) }
        if fields.codePoints { height += metrics.rowGap + rows.chip.height(lines: 1) }
        return max(tileHeight, height)
    }

    /// 見出しの行の縦の中心(area の上の端から)．選んでいる文字が無くてもピン留めのボタンの位置を決められる
    public static func headingMidY(top: Double, measuring: some PalettePreviewMeasuring, metrics: Metrics) -> Double {
        top + Rows(measuring: measuring, metrics: metrics).heading.height / 2
    }

    // MARK: - 配置

    /// - Parameters:
    ///   - area: 欄の中身を置く場所(上下の余白を除く)
    ///   - tile: 見本の四角．情報の列はこの右から area の右の端まで
    ///   - pinWidth: 見出しの行の右に空けておくピン留めのボタンの幅
    ///   - kind: 今の種類．項目名の列の幅は，この種類で出しうる項目名で決める(顔文字は読みだけ)
    public init(preview: PalettePanel.Preview, fields: PalettePanel.PreviewFields, kind: PaletteItem.Kind, area: Box, tile: Box, pinWidth: Double,
                labels: Labels, measuring: some PalettePreviewMeasuring, metrics: Metrics) {
        // 顔文字は Unicode の名前・ショートコード・コードポイントを出さない(PalettePanel.Preview(item:))
        var shown = fields
        if kind == .kaomoji {
            shown = PalettePanel.PreviewFields(unicodeName: false, readings: fields.readings, shortcodes: false, codePoints: false)
        }
        let plan = Planner(preview: preview, fields: shown, area: area, tile: tile, pinWidth: pinWidth, labels: labels, measuring: measuring, metrics: metrics)
        var options = PlanOptions(unicodeLines: metrics.unicodeNameLines)
        var layout = plan.layout(options)
        // 入りきらなければ，読みを省き，Unicode の名前を 1 行にし，Unicode の名前を省く(求められた Unicode の名前をなるべく残す)
        let steps: [(inout PlanOptions) -> Void] = [{ $0.readings = false }, { $0.unicodeLines = 1 }, { $0.unicodeName = false }]
        for step in steps where layout.bottom(measuring) > area.maxY {
            step(&options)
            layout = plan.layout(options)
        }
        self = plan.limitingChips(layout)
    }

    init(texts: [Text], chips: [Chip], headingMidY: Double, valueX: Double) {
        self.texts = texts
        self.chips = chips
        self.headingMidY = headingMidY
        self.valueX = valueX
    }

    /// 説明の欄と同じ決め方で折り返した行(描く側が読み上げや見本で使う．テストでも確かめる)
    public static func wrapped(_ text: String, width: Double, maxLines: Int = .max, measure: (String) -> Double) -> [String] {
        PreviewLineBreaking.wrapped(text, width: width, maxLines: maxLines, measure: measure)
    }

    /// 文字と札の枠(文字は書体の高さの枠)．重なりと欄からのはみ出しを確かめるのに使う
    public func frames(_ measuring: some PalettePreviewMeasuring) -> [Box] {
        texts.map { Box(x: $0.x, y: $0.baseline - measuring.ascent($0.role), width: $0.width, height: measuring.ascent($0.role) + measuring.descent($0.role)) }
            + chips.map(\.frame)
    }

    func bottom(_ measuring: some PalettePreviewMeasuring) -> Double {
        frames(measuring).map(\.maxY).max() ?? 0
    }
}

/// 文字の幅と書体の高さを測る．描く側が OS の書体で測る
public protocol PalettePreviewMeasuring {
    func width(_ text: String, _ role: PalettePreviewLayout.Role) -> Double
    /// ベースラインから上の高さ
    func ascent(_ role: PalettePreviewLayout.Role) -> Double
    /// ベースラインから下の高さ
    func descent(_ role: PalettePreviewLayout.Role) -> Double
}

/// 行の高さ．1 行目のベースラインは行の上の端から ascent，続く行は pitch ずつ下
struct PreviewRowMetrics {
    var ascent: Double
    var descent: Double
    var pitch: Double { ascent + descent }
    /// 1 行の高さ
    var height: Double { pitch }

    func height(lines: Int) -> Double { pitch * Double(max(lines, 1)) }
}

/// 見出しの行と表の行の高さ．表の行は，文字の値の行も札の行も同じ高さにし，縦の間隔をそろえる
private struct Rows {
    var heading: PreviewRowMetrics
    var text: PreviewRowMetrics
    /// 札の行も text と同じ
    var chip: PreviewRowMetrics { text }

    init(measuring: some PalettePreviewMeasuring, metrics: PalettePreviewLayout.Metrics) {
        heading = PreviewRowMetrics(ascent: max(measuring.ascent(.heading), measuring.ascent(.source)),
                                    descent: max(measuring.descent(.heading), measuring.descent(.source)))
        // 札は中の文字の上下に余白を足しても，行の高さに収める
        text = PreviewRowMetrics(
            ascent: max(measuring.ascent(.label), measuring.ascent(.value), measuring.ascent(.more), measuring.ascent(.code) + metrics.chipPaddingY),
            descent: max(measuring.descent(.label), measuring.descent(.value), measuring.descent(.more), measuring.descent(.code) + metrics.chipPaddingY))
    }
}

/// 詰め方．入りきらないときに変える
private struct PlanOptions {
    var unicodeLines: Int
    var readings = true
    var unicodeName = true
}

/// 1 つの文字の配置を，詰め方(PlanOptions)ごとに作る
private struct Planner<Measuring: PalettePreviewMeasuring> {
    let preview: PalettePanel.Preview
    let fields: PalettePanel.PreviewFields
    let area: PalettePreviewLayout.Box
    let tile: PalettePreviewLayout.Box
    let pinWidth: Double
    let labels: PalettePreviewLayout.Labels
    let measuring: Measuring
    let metrics: PalettePreviewLayout.Metrics
    let rows: Rows

    init(preview: PalettePanel.Preview, fields: PalettePanel.PreviewFields, area: PalettePreviewLayout.Box, tile: PalettePreviewLayout.Box,
         pinWidth: Double, labels: PalettePreviewLayout.Labels, measuring: Measuring, metrics: PalettePreviewLayout.Metrics) {
        self.preview = preview
        self.fields = fields
        self.area = area
        self.tile = tile
        self.pinWidth = pinWidth
        self.labels = labels
        self.measuring = measuring
        self.metrics = metrics
        rows = Rows(measuring: measuring, metrics: metrics)
    }

    /// 情報の列の左の端
    var left: Double { tile.maxX + metrics.tileGap }

    /// 項目名の列の幅．出す設定(と種類)の項目名のうちいちばん長いもの(選んでいる文字によらず値の x を変えない)
    var labelWidth: Double {
        var candidates: [String] = []
        if fields.unicodeName { candidates += [labels.unicode, labels.english] }
        if fields.readings { candidates.append(labels.readings) }
        if fields.shortcodes { candidates.append(labels.shortcodes) }
        if fields.codePoints { candidates.append(labels.codePoints) }
        return candidates.map { measuring.width($0, .label) }.max() ?? 0
    }

    var valueX: Double {
        let width = labelWidth
        return width > 0 ? left + width + metrics.labelGap : left
    }

    func layout(_ options: PlanOptions) -> PalettePreviewLayout {
        var texts: [PalettePreviewLayout.Text] = []
        var chips: [PalettePreviewLayout.Chip] = []
        // 見出しの行．名前と名前を定めたところを同じベースラインに置く
        let headingBaseline = area.y + rows.heading.ascent
        let source = preview.nameSource.map { ($0, measuring.width($0, .source)) }
        let nameSpace = area.maxX - pinWidth - left - (source.map { metrics.sourceGap + $0.1 } ?? 0)
        let name = truncated(preview.name, .heading, width: nameSpace)
        let nameWidth = measuring.width(name, .heading)
        texts.append(.init(text: name, role: .heading, x: left, baseline: headingBaseline, width: nameWidth))
        if let (text, width) = source {
            texts.append(.init(text: text, role: .source, x: left + nameWidth + metrics.sourceGap, baseline: headingBaseline, width: width))
        }
        var y = area.y + rows.heading.height
        let valueX = valueX
        let valueWidth = area.maxX - valueX
        // Unicode の名前(並びは英語の名前)．値の x にそろえて折り返す
        if options.unicodeName, fields.unicodeName, !preview.unicodeName.isEmpty {
            y += metrics.rowGap
            let label = preview.unicodeNameSource == PaletteStrings.unicodeSource ? labels.unicode : labels.english
            let lines = PreviewLineBreaking.wrapped(preview.unicodeName, width: valueWidth, maxLines: options.unicodeLines) { measuring.width($0, .value) }
            for (index, line) in lines.enumerated() {
                let baseline = y + rows.text.ascent + rows.text.pitch * Double(index)
                if index == 0 { texts.append(labelText(label, baseline: baseline)) }
                texts.append(.init(text: line, role: .value, x: valueX, baseline: baseline, width: measuring.width(line, .value)))
            }
            y += rows.text.height(lines: lines.count)
        }
        // 読み．入る数だけ「、」でつなぎ，残りの数を添える
        if options.readings, fields.readings, !preview.readings.isEmpty {
            y += metrics.rowGap
            let baseline = y + rows.text.ascent
            texts.append(labelText(labels.readings, baseline: baseline))
            let (shown, rest) = fittingReadings(width: valueWidth)
            let width = measuring.width(shown, .value)
            texts.append(.init(text: shown, role: .value, x: valueX, baseline: baseline, width: width))
            if rest > 0 {
                let more = labels.more(rest)
                texts.append(.init(text: more, role: .more, x: valueX + width + metrics.chipGap, baseline: baseline, width: measuring.width(more, .more)))
            }
            y += rows.text.height(lines: 1)
        }
        // ショートコードとコードポイントの札
        // 出さない設定の項目は，値があっても出さない(PalettePanel.Preview(item:) は空にして渡す)
        for (label, values, shown) in [(labels.shortcodes, preview.shortcodes, fields.shortcodes), (labels.codePoints, preview.codePoints, fields.codePoints)]
            where shown && !values.isEmpty {
            y += metrics.rowGap
            texts.append(labelText(label, baseline: y + rows.chip.ascent))
            let (placed, lines) = flowChips(values, top: y, x: valueX, width: valueWidth)
            chips += placed
            y += rows.chip.height(lines: lines)
        }
        return PalettePreviewLayout(texts: texts, chips: chips, headingMidY: area.y + rows.heading.height / 2, valueX: valueX)
    }

    private func labelText(_ text: String, baseline: Double) -> PalettePreviewLayout.Text {
        .init(text: text, role: .label, x: left, baseline: baseline, width: measuring.width(text, .label))
    }

    /// 札を値の幅で流し込む．入らない札は次の行へ送り，値の幅より広い札は字を縮め，それでも入らなければ札の中で折り返す(札の高さは行の数だけ)
    private func flowChips(_ values: [String], top: Double, x left: Double, width: Double) -> ([PalettePreviewLayout.Chip], Int) {
        var chips: [PalettePreviewLayout.Chip] = []
        var line = 0
        var x = left
        let padding = metrics.chipPaddingX * 2
        for value in values {
            var role = PalettePreviewLayout.Role.code
            var chipWidth = measuring.width(value, .code) + padding
            var lines = [value]
            if chipWidth > width {
                role = .smallCode
                chipWidth = measuring.width(value, .smallCode) + padding
                if chipWidth > width {
                    lines = PreviewLineBreaking.wrapped(value, width: width - padding) { measuring.width($0, .smallCode) }
                    chipWidth = (lines.map { measuring.width($0, .smallCode) }.max() ?? 0) + padding
                }
            }
            // 行の途中で入らない札と，2 行以上の札は，次の行の頭から置く
            if x > left, x + chipWidth > left + width || lines.count > 1 {
                line += 1
                x = left
            }
            let baselines = lines.indices.map { top + rows.chip.ascent + rows.chip.pitch * Double(line + $0) }
            let first = baselines[0], last = baselines[baselines.count - 1]
            let frame = PalettePreviewLayout.Box(x: x, y: first - measuring.ascent(role) - metrics.chipPaddingY, width: chipWidth,
                                                 height: last - first + measuring.ascent(role) + measuring.descent(role) + metrics.chipPaddingY * 2)
            chips.append(.init(lines: lines, role: role, frame: frame, textX: x + metrics.chipPaddingX, baselines: baselines))
            if lines.count > 1 {
                line += lines.count
                x = left
            } else {
                x += chipWidth + metrics.chipGap
            }
        }
        return (chips, x > left ? line + 1 : line)
    }

    /// 欄の下の端を越える札を除き，除いた数を最後に残した札の後ろに「+n」で示す．「+n」が入らなければその札も除く
    func limitingChips(_ layout: PalettePreviewLayout) -> PalettePreviewLayout {
        guard layout.bottom(measuring) > area.maxY else { return layout }
        var result = layout
        let total = layout.chips.count
        result.chips = layout.chips.filter { $0.frame.maxY <= area.maxY }
        while let last = result.chips.last {
            let more = labels.more(total - result.chips.count)
            let width = measuring.width(more, .more)
            let x = last.frame.maxX + metrics.chipGap
            if x + width <= area.maxX {
                result.texts.append(.init(text: more, role: .more, x: x, baseline: last.baselines[0], width: width))
                return result
            }
            result.chips.removeLast()
        }
        return result
    }

    /// 幅に入る数の読み(「、」でつなぐ)と，入らなかった読みの数．1 つ目も入らなければ末尾を省く
    private func fittingReadings(width: Double) -> (String, Int) {
        let readings = preview.readings
        func moreWidth(_ rest: Int) -> Double { rest > 0 ? metrics.chipGap + measuring.width(labels.more(rest), .more) : 0 }
        for count in stride(from: readings.count, through: 1, by: -1) {
            let text = readings.prefix(count).joined(separator: PaletteStrings.readingSeparator)
            if measuring.width(text, .value) + moreWidth(readings.count - count) <= width { return (text, readings.count - count) }
        }
        let rest = readings.count - 1
        return (truncated(readings[0], .value, width: width - moreWidth(rest)), rest)
    }

    private func truncated(_ text: String, _ role: PalettePreviewLayout.Role, width: Double) -> String {
        PreviewLineBreaking.truncated(text, width: width) { measuring.width($0, role) }
    }
}

/// 説明の欄の文字の折り返しと省略．英数字の語は空白・「-」・「_」のあとで分け，語が 1 行に入らなければ途中で分ける．
/// 日本語はどの字のあいだでも分けるが，句読点などを行の頭に置かない(Windows の scene::fitting と同じ決め方)
enum PreviewLineBreaking {
    /// 行の頭に置かない字
    private static let lineStartForbidden: Set<Character> = Set("、。，．・：；？！ー…‥）」』】〕〉》,.:;!?)]}")
    private static let ellipsis = "…"

    /// 幅 width で折り返した行．行の頭と末尾の空白は除く．maxLines を超える分は，最後の行の末尾を「…」にして省く
    static func wrapped(_ text: String, width: Double, maxLines: Int = .max, measure: (String) -> Double) -> [String] {
        var lines: [String] = []
        var rest = Array(text)
        while !rest.isEmpty, lines.count < maxLines {
            let count = lineBreak(rest, width: width, measure: measure)
            if lines.count == maxLines - 1, count < rest.count {
                lines.append(truncated(String(rest), width: width, measure: measure))
                break
            }
            lines.append(String(rest[..<count]).trimmingSpaces())
            rest = Array(rest[count...].drop { $0 == " " })
        }
        return lines
    }

    /// characters の頭から width に入る 1 行の字数(少なくとも 1 字)
    static func lineBreak(_ characters: [Character], width: Double, measure: (String) -> Double) -> Int {
        guard measure(String(characters)) > width else { return characters.count }
        // characters[..<low] は入る(1 字目は入らなくても置く)．characters[..<high] は入らない
        var low = 1, high = characters.count
        while high - low > 1 {
            let middle = (low + high) / 2
            if measure(String(characters[..<middle])) <= width { low = middle } else { high = middle }
        }
        return stride(from: low, through: 1, by: -1).first { canBreak(characters, at: $0) } ?? low
    }

    /// 幅に収まるよう末尾を「…」で省く
    static func truncated(_ text: String, width: Double, measure: (String) -> Double) -> String {
        guard measure(text) > width else { return text }
        let characters = Array(text)
        var low = 0, high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if measure(String(characters[..<middle]).trimmingSpaces() + ellipsis) <= width { low = middle } else { high = middle - 1 }
        }
        return low == 0 ? ellipsis : String(characters[..<low]).trimmingSpaces() + ellipsis
    }

    /// characters[end - 1] と characters[end] のあいだで行を分けてよいか．英数字の語の途中と，行の頭に置かない字の前では分けない
    private static func canBreak(_ characters: [Character], at end: Int) -> Bool {
        guard end < characters.count else { return true }
        let before = characters[end - 1], after = characters[end]
        if lineStartForbidden.contains(after) { return false }
        if before == " " || before == "-" || before == "_" || after == " " { return true }
        return !(before.isASCII && after.isASCII)
    }
}

private extension String {
    /// 頭と末尾の半角の空白を除いたもの(Foundation を使わない)
    func trimmingSpaces() -> String {
        String(drop { $0 == " " }.reversed().drop { $0 == " " }.reversed())
    }
}
