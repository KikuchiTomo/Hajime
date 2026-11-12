/// 語の意味のカード(R-08)の配置．一覧と分岐図，候補の右と候補の下で同じものを使う．
///
/// カードの中は「目印の列」と「文の列」の 2 列にする．
/// - 目印の列は幅が決まっていて，見出しの辞書のアイコン・意味の番号の札・同音語の耳のアイコンを，列の中で横の真ん中に置く
/// - 文の列は，見出しの語・意味・使い方の例の縦の線・「同音語」を，どれも同じ x(columns.textX)から書き出す．
///   使い方の例の文は，そこから metrics.exampleIndent だけ下げる．折り返した行も，それぞれの書き出しの x にそろえる
///
/// 縦は，文字の箱で積む．文字の箱は，書体の大きさの高さで，行の箱(ベースラインから上の ascent と下の descent の範囲)と縦の真ん中が同じもの．
/// 日本語の字の外形はほぼこの箱に収まるので，箱と箱のあいだが見た目の間隔になる(行の箱は書体の上下の余白を含むので使わない)．
/// - 目印と札は，その行の 1 行目の文字の箱の縦の真ん中に置く(枠の真ん中ではなく文字に合わせる)
/// - 文字の箱・札・目印のあいだと，カードの縁とのあいだを，トークンの間隔にする．内側の余白は上下左右とも metrics.padding
/// - 折り返した行のベースラインは metrics.meaningPitch(例は examplePitch)ずつ下げる
/// - 例の縦の線は，例の 1 行目の文字の箱の上の端から，最後の行の文字の箱の下の端まで
///
/// 意味と例を幅で折り返すのは描く側(行の頭に置かない字の決まりが OS の行分けにあるため)．
/// 描く側は columns の幅で折り返し，行の数を Content に入れてこの配置を作る．座標はカードの左上が原点で，下が y の正．
/// macOS の MeaningCardDrawing がこの配置を描き，Windows の候補ウィンドウ(scene::meaning)は同じ決め方を Rust で持つ
public struct MeaningCardLayout: Sendable, Equatable {
    /// 文字の役割．描く側が役割ごとに書体を決める
    public enum Role: Sendable, Hashable, CaseIterable {
        /// 見出しの語
        case headword
        /// 品詞の札の文字
        case partOfSpeech
        /// 意味の番号の札の文字
        case number
        /// 意味の文
        case meaning
        /// 使い方の例
        case example
        /// 「同音語」と，入らなかった札の数(「+n」)
        case label
        /// 同音語の札の文字
        case tag
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
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }

        public func intersects(_ other: Box) -> Bool {
            x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
        }

        func offsetBy(dx: Double, dy: Double) -> Box {
            Box(x: x + dx, y: y + dy, width: width, height: height)
        }
    }

    /// 1 行の文字．x から書き，baseline に文字のベースラインを置く．box はその行の文字の箱(書体の大きさの高さ)
    public struct Line: Sendable, Equatable {
        public var x: Double
        public var baseline: Double
        public var box: Box
    }

    /// 1 行の文字(中身を配置が持つもの)．見出しの語・「同音語」・「+n」・番号
    public struct Text: Sendable, Equatable {
        public var text: String
        public var role: Role
        public var line: Line
    }

    /// 札．frame の中に，文字(text)を textX から baseline に書く
    public struct Chip: Sendable, Equatable {
        public var text: String
        public var role: Role
        public var frame: Box
        public var textX: Double
        public var baseline: Double
    }

    /// 1 つの意味．badge は意味が 2 つ以上のときの番号の札(number はその中の文字)
    public struct Sense: Sendable, Equatable {
        public var badge: Box?
        public var number: Text?
        public var meaning: [Line]
        /// 使い方の例の左の縦の線．例が無ければ nil
        public var exampleBar: Box?
        public var example: [Line]
    }

    /// 横の列．x はカードの左の端から
    public struct Columns: Sendable, Equatable {
        /// 目印の列
        public var markerX: Double
        public var markerWidth: Double
        /// 文の列(見出しの語・意味・例の縦の線・「同音語」の書き出し)
        public var textX: Double
        public var textWidth: Double
        /// 例の文の書き出しと幅
        public var exampleX: Double
        public var exampleWidth: Double

        public init(width: Double, metrics: Metrics) {
            markerX = metrics.padding
            markerWidth = metrics.markerWidth
            textX = markerX + markerWidth + metrics.markerGap
            textWidth = max(width - metrics.padding - textX, 0)
            exampleX = textX + metrics.exampleIndent
            exampleWidth = max(textWidth - metrics.exampleIndent, 0)
        }
    }

    /// 寸法(デザイントークン size.meaning)
    public struct Metrics: Sendable, Equatable {
        /// カードの内側の余白(上下左右とも)
        public var padding: Double
        /// 目印の列の幅．目印(アイコンと番号の札)の一辺もこれ
        public var markerWidth: Double
        /// 目印の列と文の列のあいだ
        public var markerGap: Double
        /// 見出しと最初の意味のあいだ
        public var headerGap: Double
        /// 意味と意味のあいだ
        public var senseGap: Double
        /// 意味の文と使い方の例のあいだ
        public var exampleGap: Double
        /// 文の列の x から例の文の x まで(例の縦の線は文の列の x に引く)
        public var exampleIndent: Double
        public var exampleBarWidth: Double
        /// 折り返した行のベースラインの間隔
        public var meaningPitch: Double
        public var examplePitch: Double
        /// 最後の意味と区切りの線，区切りの線と同音語の行のあいだ
        public var othersGap: Double
        public var separatorWidth: Double
        /// 見出しの語と品詞の札のあいだ
        public var partOfSpeechGap: Double
        public var partOfSpeechHeight: Double
        public var partOfSpeechPaddingX: Double
        /// 「同音語」と最初の札のあいだ，札と札のあいだ
        public var tagGap: Double
        public var tagHeight: Double
        public var tagPaddingX: Double

        public init(padding: Double, markerWidth: Double, markerGap: Double, headerGap: Double, senseGap: Double, exampleGap: Double, exampleIndent: Double,
                    exampleBarWidth: Double, meaningPitch: Double, examplePitch: Double, othersGap: Double, separatorWidth: Double, partOfSpeechGap: Double,
                    partOfSpeechHeight: Double, partOfSpeechPaddingX: Double, tagGap: Double, tagHeight: Double, tagPaddingX: Double) {
            self.padding = padding
            self.markerWidth = markerWidth
            self.markerGap = markerGap
            self.headerGap = headerGap
            self.senseGap = senseGap
            self.exampleGap = exampleGap
            self.exampleIndent = exampleIndent
            self.exampleBarWidth = exampleBarWidth
            self.meaningPitch = meaningPitch
            self.examplePitch = examplePitch
            self.othersGap = othersGap
            self.separatorWidth = separatorWidth
            self.partOfSpeechGap = partOfSpeechGap
            self.partOfSpeechHeight = partOfSpeechHeight
            self.partOfSpeechPaddingX = partOfSpeechPaddingX
            self.tagGap = tagGap
            self.tagHeight = tagHeight
            self.tagPaddingX = tagPaddingX
        }

        /// デザイントークン(size.meaning)の値
        public static let tokens = Metrics(
            padding: LayoutTokens.Meaning.padding, markerWidth: LayoutTokens.Meaning.markerWidth, markerGap: LayoutTokens.Meaning.markerGap,
            headerGap: LayoutTokens.Meaning.headerGap, senseGap: LayoutTokens.Meaning.senseGap, exampleGap: LayoutTokens.Meaning.exampleGap,
            exampleIndent: LayoutTokens.Meaning.exampleIndent, exampleBarWidth: LayoutTokens.Meaning.exampleBarWidth,
            meaningPitch: LayoutTokens.Meaning.meaningPitch, examplePitch: LayoutTokens.Meaning.examplePitch, othersGap: LayoutTokens.Meaning.othersGap,
            separatorWidth: LayoutTokens.Candidate.frameWidth, partOfSpeechGap: LayoutTokens.Meaning.partOfSpeechGap,
            partOfSpeechHeight: LayoutTokens.Meaning.partOfSpeechHeight, partOfSpeechPaddingX: LayoutTokens.Meaning.partOfSpeechPaddingX,
            tagGap: LayoutTokens.Meaning.tagGap, tagHeight: LayoutTokens.Glass.tagHeight, tagPaddingX: LayoutTokens.Glass.tagPaddingX)
    }

    /// カードに出す中身．意味と例は，描く側が columns の幅で折り返した行の数
    public struct Content: Sendable, Equatable {
        public struct Sense: Sendable, Equatable {
            /// 番号の札の文字(意味が 1 つなら nil)
            public var number: String?
            public var meaningLines: Int
            public var exampleLines: Int

            public init(number: String?, meaningLines: Int, exampleLines: Int) {
                self.number = number
                self.meaningLines = meaningLines
                self.exampleLines = exampleLines
            }
        }

        public var word: String
        public var partOfSpeech: String?
        public var senses: [Sense]
        /// 同音語の札に出す語
        public var others: [String]
        /// 同音語の行の見出し(「同音語」)
        public var othersLabel: String

        public init(word: String, partOfSpeech: String?, senses: [Sense], others: [String], othersLabel: String) {
            self.word = word
            self.partOfSpeech = partOfSpeech
            self.senses = senses
            self.others = others
            self.othersLabel = othersLabel
        }
    }

    /// カードの大きさ(内側の余白を含む)
    public var width: Double
    public var height: Double
    public var columns: Columns
    /// 見出しの辞書のアイコンの枠(目印の列の一辺の正方形)
    public var bookIcon: Box
    /// 見出しの語(入らなければ末尾を「…」で省いたもの)
    public var headword: Text
    public var partOfSpeech: Chip?
    public var senses: [Sense]
    /// 同音語の行の上の区切りの線．同音語が無ければ nil
    public var separator: Box?
    public var earIcon: Box?
    public var othersLabel: Text?
    public var tags: [Chip]
    /// 入らなかった札の数(「+n」)
    public var more: Text?

    /// 見出しの行の縦の真ん中(カードの上の端から)．分岐図で候補からつなぐ線はここへ引く
    public var headerMidY: Double { bookIcon.midY }

    /// - Parameters:
    ///   - width: カードの幅(内側の余白を含む)
    ///   - moreLabel: 入らなかった札の数の文言(「+n」)
    public init(content: Content, width: Double, moreLabel: (Int) -> String, measuring: some MeaningCardMeasuring, metrics: Metrics) {
        let columns = Columns(width: width, metrics: metrics)
        let rows = RowPlacer(measuring: measuring)
        self.width = width
        self.columns = columns
        let right = width - metrics.padding

        // 見出し: 辞書のアイコン・語・品詞の札を，語の行の箱の縦の真ん中にそろえる
        var y = metrics.padding
        let headerHeight = max(rows.em(.headword), metrics.partOfSpeechHeight, metrics.markerWidth)
        let headerMid = y + headerHeight / 2
        let posWidth = content.partOfSpeech.map { (measuring.width($0, .partOfSpeech) + metrics.partOfSpeechPaddingX * 2).rounded(.up) }
        let wordWidth = max(right - columns.textX - (posWidth.map { $0 + metrics.partOfSpeechGap } ?? 0), 0)
        let word = Self.truncated(content.word, width: wordWidth) { measuring.width($0, .headword) }
        let wordLine = rows.centered(.headword, x: columns.textX, width: measuring.width(word, .headword), midY: headerMid)
        headword = Text(text: word, role: .headword, line: wordLine)
        bookIcon = Self.marker(x: columns.markerX, size: metrics.markerWidth, midY: wordLine.box.midY)
        if let name = content.partOfSpeech, let posWidth {
            let frame = Box(x: (wordLine.box.maxX + metrics.partOfSpeechGap).rounded(), y: (wordLine.box.midY - metrics.partOfSpeechHeight / 2).rounded(),
                            width: posWidth, height: metrics.partOfSpeechHeight)
            partOfSpeech = rows.chip(name, role: .partOfSpeech, frame: frame, paddingX: metrics.partOfSpeechPaddingX)
        } else {
            partOfSpeech = nil
        }
        y += headerHeight + metrics.headerGap

        // 意味: 番号の札は 1 行目の行の箱の縦の真ん中．例は縦の線を文の列の x に引き，文を下げる
        var senses: [Sense] = []
        for (index, sense) in content.senses.enumerated() {
            if index > 0 { y += metrics.senseGap }
            let meaning = rows.paragraph(.meaning, lines: sense.meaningLines, x: columns.textX, width: columns.textWidth, top: y, pitch: metrics.meaningPitch)
            var badge: Box?
            var number: Text?
            if let label = sense.number, let first = meaning.first {
                let frame = Self.marker(x: columns.markerX, size: metrics.markerWidth, midY: first.box.midY)
                badge = frame
                number = Text(text: label, role: .number,
                              line: rows.centered(.number, x: frame.midX - measuring.width(label, .number) / 2, width: measuring.width(label, .number), midY: frame.midY))
            }
            y = meaning.last?.box.maxY ?? y
            var bar: Box?
            var example: [Line] = []
            if sense.exampleLines > 0 {
                y += metrics.exampleGap
                example = rows.paragraph(.example, lines: sense.exampleLines, x: columns.exampleX, width: columns.exampleWidth, top: y, pitch: metrics.examplePitch)
                if let first = example.first, let last = example.last {
                    bar = Box(x: columns.textX, y: first.box.y, width: metrics.exampleBarWidth, height: last.box.maxY - first.box.y)
                    y = last.box.maxY
                }
            }
            senses.append(Sense(badge: badge, number: number, meaning: meaning, exampleBar: bar, example: example))
        }
        self.senses = senses

        // 同音語: 区切りの線の下に，耳のアイコン・「同音語」・札．入らない札は「+n」にまとめる
        separator = nil
        earIcon = nil
        othersLabel = nil
        tags = []
        more = nil
        if !content.others.isEmpty {
            y += metrics.othersGap
            let line = Box(x: metrics.padding, y: y.rounded(), width: width - metrics.padding * 2, height: metrics.separatorWidth)
            separator = line
            y = line.maxY + metrics.othersGap
            let rowHeight = max(rows.em(.label), metrics.tagHeight, metrics.markerWidth)
            let labelLine = rows.centered(.label, x: columns.textX, width: measuring.width(content.othersLabel, .label), midY: y + rowHeight / 2)
            othersLabel = Text(text: content.othersLabel, role: .label, line: labelLine)
            earIcon = Self.marker(x: columns.markerX, size: metrics.markerWidth, midY: labelLine.box.midY)
            var x = labelLine.box.maxX + metrics.tagGap
            for (index, word) in content.others.enumerated() {
                let tagWidth = (measuring.width(word, .tag) + metrics.tagPaddingX * 2).rounded(.up)
                let rest = content.others.count - index - 1
                let reserve = rest > 0 ? metrics.tagGap + measuring.width(moreLabel(rest), .label) : 0
                if x + tagWidth + reserve > right {
                    let text = moreLabel(content.others.count - index)
                    more = Text(text: text, role: .label, line: rows.centered(.label, x: x, width: measuring.width(text, .label), midY: labelLine.box.midY))
                    break
                }
                let frame = Box(x: x.rounded(), y: (labelLine.box.midY - metrics.tagHeight / 2).rounded(), width: tagWidth, height: metrics.tagHeight)
                tags.append(rows.chip(word, role: .tag, frame: frame, paddingX: metrics.tagPaddingX))
                x = frame.maxX + metrics.tagGap
            }
            y += rowHeight
        }
        height = (y + metrics.padding).rounded(.up)
    }

    /// 置いた部品の枠(重なりを確かめるのに使う)
    public var parts: [Box] {
        var boxes = [bookIcon, headword.line.box]
        if let partOfSpeech { boxes.append(partOfSpeech.frame) }
        for sense in senses {
            if let badge = sense.badge { boxes.append(badge) }
            boxes += sense.meaning.map(\.box) + sense.example.map(\.box)
            if let bar = sense.exampleBar { boxes.append(bar) }
        }
        boxes += [separator, earIcon, othersLabel?.line.box, more?.line.box].compactMap { $0 }
        return boxes + tags.map(\.frame)
    }

    /// 目印の枠: 目印の列の中で，midY を縦の真ん中にした正方形
    private static func marker(x: Double, size: Double, midY: Double) -> Box {
        Box(x: x, y: (midY - size / 2).rounded(), width: size, height: size)
    }

    /// 末尾を「…」にして width に収めたもの
    static func truncated(_ text: String, width: Double, measure: (String) -> Double) -> String {
        guard measure(text) > width else { return text }
        var characters = Array(text)
        while !characters.isEmpty {
            characters.removeLast()
            let candidate = String(characters) + "…"
            if measure(candidate) <= width { return candidate }
        }
        return "…"
    }
}

/// 文字の幅と書体の高さを測る．描く側が OS の書体で測る
public protocol MeaningCardMeasuring {
    func width(_ text: String, _ role: MeaningCardLayout.Role) -> Double
    /// ベースラインから上の高さ
    func ascent(_ role: MeaningCardLayout.Role) -> Double
    /// ベースラインから下の高さ
    func descent(_ role: MeaningCardLayout.Role) -> Double
    /// 書体の大きさ(文字の箱の高さ)
    func size(_ role: MeaningCardLayout.Role) -> Double
}

/// 文字の箱を置く．ベースラインは整数の位置にし(字をぼかさない)，箱は丸めたベースラインから求める
private struct RowPlacer<Measuring: MeaningCardMeasuring> {
    var measuring: Measuring

    /// 文字の箱の高さ
    func em(_ role: MeaningCardLayout.Role) -> Double { measuring.size(role) }

    /// 行の箱の高さ(行の間隔の下限)
    func lineHeight(_ role: MeaningCardLayout.Role) -> Double {
        measuring.ascent(role) + measuring.descent(role)
    }

    /// 文字の箱の縦の真ん中が midY の 1 行．行の箱の真ん中を文字の箱の真ん中に合わせる
    func centered(_ role: MeaningCardLayout.Role, x: Double, width: Double, midY: Double) -> MeaningCardLayout.Line {
        let ascent = measuring.ascent(role), descent = measuring.descent(role)
        let baseline = (midY + (ascent - descent) / 2).rounded()
        let center = baseline - (ascent - descent) / 2
        return MeaningCardLayout.Line(x: x, baseline: baseline, box: .init(x: x, y: center - em(role) / 2, width: width, height: em(role)))
    }

    /// 1 行目の文字の箱の上の端が top の段落．続く行のベースラインは pitch ずつ下げる(行の箱より狭ければ行の箱の高さ)
    func paragraph(_ role: MeaningCardLayout.Role, lines: Int, x: Double, width: Double, top: Double, pitch: Double) -> [MeaningCardLayout.Line] {
        guard lines > 0 else { return [] }
        let first = centered(role, x: x, width: width, midY: top + em(role) / 2)
        let step = max(pitch, lineHeight(role).rounded(.up))
        return (0..<lines).map { index in
            var placed = first
            placed.baseline += step * Double(index)
            placed.box = placed.box.offsetBy(dx: 0, dy: step * Double(index))
            return placed
        }
    }

    /// frame の中の札の文字．文字の箱を札の縦の真ん中に置く
    func chip(_ text: String, role: MeaningCardLayout.Role, frame: MeaningCardLayout.Box, paddingX: Double) -> MeaningCardLayout.Chip {
        let placed = centered(role, x: frame.x + paddingX, width: measuring.width(text, role), midY: frame.midY)
        return MeaningCardLayout.Chip(text: text, role: role, frame: frame, textX: frame.x + paddingX, baseline: placed.baseline)
    }
}
