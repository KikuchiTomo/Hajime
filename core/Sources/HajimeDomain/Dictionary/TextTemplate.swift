/// 入れるときに中身を決める語(動的なユーザー辞書と変換マクロ)．語の中の `{名前}` や `{名前:引数}` を，そのときの値に置き換える．
///
/// | 書き方 | 入る文字 |
/// |---|---|
/// | `{datetime:YYYY/MM/DD hh:mm:ss}` | 今の日時を書式で(書式の記号は DateTimeFormat) |
/// | `{date}` `{time}` | `{datetime:YYYY/MM/DD}` と `{datetime:hh:mm}` の略．`{date:M/D}` のように書式も書ける |
/// | `{utc:…}` | 協定世界時の日時(既定の書式は `YYYY-MM-DD'T'hh:mm:ss'Z'`) |
/// | `{unixtime}` | UNIX 時間(秒) |
/// | `{date+1d}` `{time-30m}` `{date+1M@end}` | 日時の名前のあとに，ずらす量と合わせる先を左から順に当てる(DateStep) |
/// | `{holiday}` `{holiday:平日}` | 祝日の名前(JapaneseCalendar)．祝日でなければ空か引数の文字 |
/// | `{season}` `{greeting}` | 月の時候の挨拶(「晩秋の候」)と，時刻の挨拶(「こんにちは」) |
/// | `{days:12/25}` `{days:2027-03-31}` | その日までの日数(過ぎていれば負)．年を書かなければ次に来るその日 |
/// | `{age:1990-04-01}` | その日に生まれた人の満年齢 |
/// | `{uuid}` | UUID(大文字．小文字は `{uuid|lower}`) |
/// | `{random:1-6}` | その範囲の整数 |
/// | `{alnum:8}` `{hex:8}` | その長さの英数字・16 進数(小文字) |
/// | `{pick:A,B,C}` | `,` で区切ったうちのどれか 1 つ |
/// | `{text}` `{reading}` | (変換マクロだけ)選んでいる語と，その読み |
/// | `{text|upper}` | 値に変換をかける(TextFilter) |
/// | `{{` `}}` | `{` と `}` そのもの |
///
/// 知らない名前は置き換えずにそのまま残す．コマンドを動かしたり，ファイルや画面の中身(クリップボードなど)を読んだりする名前は作らない
/// (語を入れるだけで入力内容が外に出たり，何かが動いたりしないように)
public enum TextTemplate {
    /// 置き換えに使う値．呼び出し側(SupplementedConverter と AssociationFinder)が渡す
    public struct Values {
        public var now: CalendarDate?
        public var uuid: (() -> String)?
        /// 範囲の中の整数を 1 つ
        public var random: ((ClosedRange<Int>) -> Int)?
        public var text: String?
        public var reading: String?

        public init(now: CalendarDate? = nil, uuid: (() -> String)? = nil, random: ((ClosedRange<Int>) -> Int)? = nil,
                    text: String? = nil, reading: String? = nil) {
            self.now = now
            self.uuid = uuid
            self.random = random
            self.text = text
            self.reading = reading
        }
    }

    /// 日時の名前のあとに書く，ずらす量(`+1d`)と合わせる先(`@mon`)
    ///
    /// - ずらす量: `+` か `-` と数と単位．単位は m 分・h 時間・d 日・w 週・M 月・y 年・b 平日(土日と祝日を飛ばす)
    /// - 合わせる先: `@mon`〜`@sun` その週(月曜から日曜)の曜日，`@1`〜`@31` その月の日(月の日数より大きければ月末)，`@end` 月末
    public enum DateStep: Sendable, Equatable {
        case shift(Int, CalendarDate.Unit)
        case anchor(CalendarDate.Anchor)

        /// `+1M@end` のような並び．読めなければ nil
        static func parse(_ text: Substring) -> [DateStep]? {
            var steps: [DateStep] = []
            var rest = text
            while let first = rest.first {
                rest = rest.dropFirst()
                if first == "@" {
                    let word = rest.prefix { $0.isASCII && ($0.isLetter || $0.isNumber) }
                    rest = rest.dropFirst(word.count)
                    guard let anchor = anchor(named: word) else { return nil }
                    steps.append(.anchor(anchor))
                } else if first == "+" || first == "-" {
                    let digits = rest.prefix { ("0"..."9").contains($0) }
                    rest = rest.dropFirst(digits.count)
                    guard let amount = Int(digits), amount <= DefaultSettings.maximumTemplateShift,
                        let symbol = rest.first, let unit = units[symbol] else { return nil }
                    rest = rest.dropFirst()
                    steps.append(.shift(first == "-" ? -amount : amount, unit))
                } else {
                    return nil
                }
            }
            return steps
        }

        func apply(to date: CalendarDate) -> CalendarDate {
            switch self {
            case .shift(let amount, let unit): date.shifted(by: amount, unit)
            case .anchor(let anchor): date.anchored(to: anchor)
            }
        }

        private static let units: [Character: CalendarDate.Unit] = [
            "m": .minute, "h": .hour, "d": .day, "w": .week, "M": .month, "y": .year, "b": .businessDay,
        ]
        private static let weekdays = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]

        private static func anchor(named word: Substring) -> CalendarDate.Anchor? {
            if word == "end" { return .endOfMonth }
            if let index = weekdays.firstIndex(of: String(word)) { return .weekday(index + 1) }
            if let day = Int(word), (1...31).contains(day) { return .dayOfMonth(day) }
            return nil
        }
    }

    /// 語に置き換える部分(`{` で始まる名前)があるか
    public static func containsPlaceholder(_ text: String) -> Bool {
        tokens(of: text).contains { if case .placeholder = $0 { true } else { false } }
    }

    /// 語の中で使っている名前(`{text|upper}` なら text)
    public static func names(in text: String) -> Set<String> {
        Set(tokens(of: text).compactMap { if case .placeholder(let body) = $0 { String(parts(of: body).name) } else { nil } })
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

    /// `名前[ずらす量と合わせる先][:引数][|変換...]` を分けたもの
    private static func parts(of body: String) -> (name: Substring, steps: Substring, argument: Substring?, filters: [Substring]) {
        let segments = body.split(separator: "|", omittingEmptySubsequences: false)
        let head = segments.first ?? Substring(body)
        var nameAndSteps = head
        var argument: Substring?
        if let colon = head.firstIndex(of: ":") {
            nameAndSteps = head[..<colon]
            argument = head[head.index(after: colon)...]
        }
        let stepsStart = nameAndSteps.firstIndex { $0 == "+" || $0 == "-" || $0 == "@" } ?? nameAndSteps.endIndex
        return (nameAndSteps[..<stepsStart], nameAndSteps[stepsStart...], argument, segments.dropFirst().filter { !$0.isEmpty })
    }

    /// 置き換える値．分からなければ nil
    private static func value(of body: String, values: Values) -> String? {
        let parts = parts(of: body)
        var filters: [TextFilter] = []
        for name in parts.filters {
            guard let filter = TextFilter(rawValue: String(name)) else { return nil }
            filters.append(filter)
        }
        let raw: String?
        if dateNames.contains(String(parts.name)) {
            raw = dateValue(name: parts.name, steps: parts.steps, argument: parts.argument, values: values)
        } else {
            guard parts.steps.isEmpty else { return nil }
            raw = baseValue(name: parts.name, argument: parts.argument.map(String.init), values: values)
        }
        return raw.map { filters.reduce($0) { value, filter in filter.apply(to: value) } }
    }

    private static let dateNames: Set<String> = ["datetime", "date", "time", "utc", "unixtime", "holiday", "season", "greeting", "days", "age"]

    private static func dateValue(name: Substring, steps: Substring, argument: Substring?, values: Values) -> String? {
        guard let now = values.now, let steps = DateStep.parse(steps) else { return nil }
        let date = steps.reduce(now) { $1.apply(to: $0) }
        let format = argument.map(String.init)
        switch name {
        case "date": return DateTimeFormat.format(format ?? "YYYY/MM/DD", date: date)
        case "time": return DateTimeFormat.format(format ?? "hh:mm", date: date)
        case "utc": return DateTimeFormat.format(format ?? "YYYY-MM-DD'T'hh:mm:ss'Z'", date: date.inUTC)
        case "unixtime": return String(date.unixTime)
        case "holiday": return JapaneseCalendar.holiday(on: date) ?? format ?? ""
        case "season": return JapaneseCalendar.seasonalGreeting(month: date.month)
        case "greeting": return JapaneseCalendar.greeting(hour: date.hour)
        case "days":
            guard let format, let target = day(format, from: date) else { return nil }
            return String(date.days(until: target))
        case "age":
            guard let format, let birth = day(format, from: date, requiresYear: true), birth.days(until: date) >= 0 else { return nil }
            let hadBirthday = (date.month, date.day) >= (birth.month, birth.day)
            return String(date.year - birth.year - (hadBirthday ? 0 : 1))
        default: return DateTimeFormat.format(format ?? "YYYY/MM/DD hh:mm:ss", date: date)
        }
    }

    /// `2027-03-31`・`2027/3/31`・`12/25` の日．年を書かなければ，today から数えて次に来るその日(今日なら今日)．
    /// 無い日(2 月 30 日など)と読めない書き方は nil
    private static func day(_ text: String, from today: CalendarDate, requiresYear: Bool = false) -> CalendarDate? {
        let numbers = text.split(whereSeparator: { $0 == "-" || $0 == "/" }).map { Int($0) }
        guard numbers.count == 3 || (numbers.count == 2 && !requiresYear), numbers.allSatisfy({ $0 != nil }) else { return nil }
        let values = numbers.compactMap { $0 }
        let (month, day) = (values[values.count - 2], values[values.count - 1])
        guard (1...12).contains(month), day >= 1 else { return nil }
        func date(year: Int) -> CalendarDate? {
            guard DefaultSettings.templateYearRange.contains(year), day <= CalendarDate.daysInMonth(year: year, month: month) else { return nil }
            return today.anchored(to: .dayOfMonth(1)).shifted(by: (year - today.year) * 12 + month - today.month, .month)
                .anchored(to: .dayOfMonth(day))
        }
        if values.count == 3 { return date(year: values[0]) }
        // うるう日は 4 年(100 年おきの例外を含め 8 年)のうちに来る
        return (today.year...today.year + 8).lazy.compactMap { date(year: $0) }.first { today.days(until: $0) >= 0 }
    }

    private static func baseValue(name: Substring, argument: String?, values: Values) -> String? {
        switch name {
        case "uuid":
            return values.uuid?()
        case "random":
            guard let random = values.random else { return nil }
            let bounds = (argument ?? "1-100").split(separator: "-", maxSplits: 1).compactMap { Int($0) }
            guard bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] <= DefaultSettings.maximumTemplateRandomRange else { return nil }
            return String(random(bounds[0]...bounds[1]))
        case "alnum", "hex":
            guard let random = values.random else { return nil }
            let length = argument.map { Int($0) } ?? DefaultSettings.templateRandomTextLength
            guard let length, (1...DefaultSettings.maximumTemplateRandomTextLength).contains(length) else { return nil }
            let alphabet = name == "hex" ? hexDigits : alphanumerics
            return String((0..<length).map { _ in alphabet[min(max(random(0...alphabet.count - 1), 0), alphabet.count - 1)] })
        case "pick":
            guard let random = values.random, let argument else { return nil }
            let choices = argument.split(separator: ",", omittingEmptySubsequences: false)
            return String(choices[min(max(random(0...choices.count - 1), 0), choices.count - 1)])
        case "text":
            return values.text
        case "reading":
            return values.reading
        default:
            return nil
        }
    }

    private static let alphanumerics = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
    private static let hexDigits = Array("0123456789abcdef")
}
