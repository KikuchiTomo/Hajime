/// 入れるときに中身を決める語(動的なユーザー辞書と変換マクロ)．語の中の `{名前}` や `{名前:引数}` を，そのときの値に置き換える．
///
/// | 書き方 | 入る文字 |
/// |---|---|
/// | `{datetime:YYYY/MM/DD hh:mm:ss}` | 今の日時を書式で(書式の記号は DateTimeFormat) |
/// | `{datetime+1d:MM/DD}` | 今日から n 日ずらした日(`-7d` で 7 日前) |
/// | `{date}` `{time}` | `{datetime:YYYY/MM/DD}` と `{datetime:hh:mm}` の略 |
/// | `{uuid}` | UUID(大文字) |
/// | `{random:1-6}` | その範囲の整数 |
/// | `{text}` `{reading}` | (変換マクロだけ)選んでいる語と，その読み |
/// | `{text|upper}` | 値に変換をかける(upper・lower・capitalize・katakana・hiragana・halfwidth(半角カタカナ)・fullwidth(全角英数)) |
/// | `{{` `}}` | `{` と `}` そのもの |
///
/// 知らない名前は置き換えずにそのまま残す．コマンドを動かしたり，ファイルや画面の中身(クリップボードなど)を読んだりする名前は作らない
/// (語を入れるだけで入力内容が外に出たり，何かが動いたりしないように)
public enum TextTemplate {
    /// 置き換えに使う値．呼び出し側(SupplementedConverter と AssociationFinder)が渡す
    public struct Values {
        public var now: CalendarDate?
        /// 今日から n 日ずらした日
        public var day: ((Int) -> CalendarDate)?
        public var uuid: (() -> String)?
        /// 範囲の中の整数を 1 つ
        public var random: ((ClosedRange<Int>) -> Int)?
        public var text: String?
        public var reading: String?

        public init(now: CalendarDate? = nil, day: ((Int) -> CalendarDate)? = nil, uuid: (() -> String)? = nil,
                    random: ((ClosedRange<Int>) -> Int)? = nil, text: String? = nil, reading: String? = nil) {
            self.now = now
            self.day = day
            self.uuid = uuid
            self.random = random
            self.text = text
            self.reading = reading
        }
    }

    /// 語に置き換える部分(`{` で始まる名前)があるか
    public static func containsPlaceholder(_ text: String) -> Bool {
        tokens(of: text).contains { if case .placeholder = $0 { true } else { false } }
    }

    /// 置き換えた文字列．長さは DefaultSettings.maximumTemplateOutputLength まで
    public static func expand(_ template: String, values: Values) -> String {
        var result = ""
        for token in tokens(of: template) {
            switch token {
            case .literal(let text):
                result += text
            case .placeholder(let body):
                result += value(of: body, values: values) ?? "{\(body)}"
            }
            if result.count > DefaultSettings.maximumTemplateOutputLength { return String(result.prefix(DefaultSettings.maximumTemplateOutputLength)) }
        }
        return result
    }

    private enum Token: Equatable {
        case literal(String)
        case placeholder(String)
    }

    private static func tokens(of text: String) -> [Token] {
        var tokens: [Token] = []
        var literal = ""
        var characters = Array(text)[...]
        while let character = characters.first {
            characters = characters.dropFirst()
            if character == "{", characters.first == "{" {
                literal.append("{")
                characters = characters.dropFirst()
            } else if character == "}", characters.first == "}" {
                literal.append("}")
                characters = characters.dropFirst()
            } else if character == "{", let end = characters.firstIndex(of: "}"), !characters[..<end].contains("{") {
                if !literal.isEmpty { tokens.append(.literal(literal)) }
                literal = ""
                tokens.append(.placeholder(String(characters[..<end])))
                characters = characters[characters.index(after: end)...]
            } else {
                literal.append(character)
            }
        }
        if !literal.isEmpty { tokens.append(.literal(literal)) }
        return tokens
    }

    /// `名前[+nd][:引数][|変換]` の値．分からなければ nil
    private static func value(of body: String, values: Values) -> String? {
        var head = Substring(body)
        var filters: [Substring] = []
        if let bar = body.firstIndex(of: "|") {
            head = body[..<bar]
            filters = body[body.index(after: bar)...].split(separator: "|")
        }
        var name = head
        var argument: Substring?
        if let colon = head.firstIndex(of: ":") {
            name = head[..<colon]
            argument = head[head.index(after: colon)...]
        }
        guard let raw = baseValue(name: String(name), argument: argument.map(String.init), values: values) else { return nil }
        return filters.reduce(Optional(raw)) { value, filter in value.flatMap { apply(String(filter), to: $0) } }
    }

    private static func baseValue(name: String, argument: String?, values: Values) -> String? {
        switch name {
        case "date":
            return values.now.map { DateTimeFormat.format(argument ?? "YYYY/MM/DD", date: $0) }
        case "time":
            return values.now.map { DateTimeFormat.format(argument ?? "hh:mm", date: $0) }
        case "uuid":
            return values.uuid?()
        case "random":
            guard let random = values.random else { return nil }
            let bounds = (argument ?? "1-100").split(separator: "-", maxSplits: 1).compactMap { Int($0) }
            guard bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] <= DefaultSettings.maximumTemplateRandomRange else { return nil }
            return String(random(bounds[0]...bounds[1]))
        case "text":
            return values.text
        case "reading":
            return values.reading
        default:
            guard name.hasPrefix("datetime") else { return nil }
            let format = argument ?? "YYYY/MM/DD hh:mm:ss"
            let offset = name.dropFirst("datetime".count)
            if offset.isEmpty { return values.now.map { DateTimeFormat.format(format, date: $0) } }
            // 「+1d」「-7d」．日の単位だけ
            guard offset.hasSuffix("d"), let days = Int(offset.dropLast()), abs(days) <= DefaultSettings.maximumTemplateDayOffset,
                offset.first == "+" || offset.first == "-", let day = values.day else { return nil }
            return DateTimeFormat.format(format, date: day(days))
        }
    }

    private static func apply(_ filter: String, to value: String) -> String? {
        switch filter {
        case "upper": value.uppercased()
        case "lower": value.lowercased()
        case "capitalize": value.prefix(1).uppercased() + value.dropFirst()
        case "katakana": KanaWidth.katakana(from: value)
        case "hiragana": KanaWidth.hiragana(from: value)
        case "halfwidth": KanaWidth.halfwidthKatakana(from: KanaWidth.katakana(from: value))
        case "fullwidth": KanaWidth.fullwidthASCII(from: value)
        default: nil
        }
    }
}

/// 日時の書式．長い記号から順に当てはめ，記号でない文字はそのまま残す．`'...'` で囲んだところも記号として読まない
///
/// YYYY 年(4 桁)・YY 年(下 2 桁)・MM 月(2 桁)・M 月・DD 日(2 桁)・D 日・hh 時(24 時間制 2 桁)・h 時・mm 分(2 桁)・m 分・ss 秒(2 桁)・s 秒・
/// A 午前/午後・KK 時(12 時間制 2 桁)・K 時(12 時間制)・dddd 曜日(「月曜日」)・ddd 曜日(「月」)・EEE 曜日(「Mon」)・GG 元号(「令和」)・
/// E 元号の年(「8」)・ZZ 時間帯(「+09:00」)
public enum DateTimeFormat {
    private static let symbols = ["YYYY", "dddd", "ddd", "EEE", "YY", "MM", "DD", "hh", "mm", "ss", "KK", "GG", "ZZ", "M", "D", "h", "m", "s", "K", "A", "E"]
    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
    private static let englishWeekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    public static func format(_ pattern: String, date: CalendarDate) -> String {
        var result = ""
        var rest = Substring(pattern)
        while let first = rest.first {
            if first == "'" {
                let body = rest.dropFirst()
                let end = body.firstIndex(of: "'") ?? body.endIndex
                result += body[..<end]
                rest = end < body.endIndex ? body[body.index(after: end)...] : ""
                continue
            }
            if let symbol = symbols.first(where: { rest.hasPrefix($0) }) {
                result += value(of: symbol, date: date)
                rest = rest.dropFirst(symbol.count)
            } else {
                result.append(first)
                rest = rest.dropFirst()
            }
        }
        return result
    }

    private static func value(of symbol: String, date: CalendarDate) -> String {
        let hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12
        let weekday = (date.weekday - 1 + 7) % 7
        switch symbol {
        case "YYYY": return String(date.year)
        case "YY": return pad(date.year % 100)
        case "MM": return pad(date.month)
        case "M": return String(date.month)
        case "DD": return pad(date.day)
        case "D": return String(date.day)
        case "hh": return pad(date.hour)
        case "h": return String(date.hour)
        case "mm": return pad(date.minute)
        case "m": return String(date.minute)
        case "ss": return pad(date.second)
        case "s": return String(date.second)
        case "KK": return pad(hour12)
        case "K": return String(hour12)
        case "A": return date.hour < 12 ? "午前" : "午後"
        case "dddd": return weekdays[weekday] + "曜日"
        case "ddd": return weekdays[weekday]
        case "EEE": return englishWeekdays[weekday]
        case "GG": return Era.name(forYear: date.year)
        case "E": return String(Era.year(of: date.year))
        case "ZZ":
            let offset = date.utcOffsetSeconds
            let sign = offset < 0 ? "-" : "+"
            return "\(sign)\(pad(abs(offset) / 3600)):\(pad(abs(offset) % 3600 / 60))"
        default: return symbol
        }
    }

    static func pad(_ value: Int) -> String {
        value < 10 && value >= 0 ? "0\(value)" : String(value)
    }

    /// 元号．令和(2019 年から)だけを扱う．それより前の年は西暦の数を返す
    enum Era {
        static let reiwaOffset = 2018
        static func name(forYear year: Int) -> String { year > reiwaOffset ? "令和" : "" }
        static func year(of year: Int) -> Int { year > reiwaOffset ? year - reiwaOffset : year }
    }
}
