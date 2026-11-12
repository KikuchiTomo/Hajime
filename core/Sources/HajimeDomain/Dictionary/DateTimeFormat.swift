/// 日時の書式．長い記号から順に当てはめ，記号でない文字はそのまま残す．`'...'` で囲んだところも記号として読まない
///
/// | 記号 | 入る文字 |
/// |---|---|
/// | YYYY・YY | 年(4 桁・下 2 桁) |
/// | MM・M | 月(2 桁・そのまま) |
/// | MMMM・MMM | 英語の月(「November」「Nov」) |
/// | DD・D | 日(2 桁・そのまま) |
/// | DDDD・DDD | 年の何日目か(3 桁・そのまま) |
/// | hh・h | 時(24 時間制．2 桁・そのまま) |
/// | KK・K | 時(12 時間制．2 桁・そのまま) |
/// | mm・m，ss・s | 分，秒(2 桁・そのまま) |
/// | A・AA | 「午前」「午後」，「AM」「PM」 |
/// | dddd・ddd | 曜日(「月曜日」「月」) |
/// | EEEE・EEE | 英語の曜日(「Monday」「Mon」) |
/// | GG・E | 元号(「令和」)と元号の年(「8」) |
/// | WW・W | ISO 8601 の週番号(2 桁・そのまま) |
/// | Q | 四半期(1〜4) |
/// | ZZ | 時間帯(「+09:00」) |
public enum DateTimeFormat {
    private static let symbols = [
        "YYYY", "MMMM", "DDDD", "dddd", "EEEE", "MMM", "DDD", "ddd", "EEE",
        "YY", "MM", "DD", "hh", "mm", "ss", "KK", "AA", "GG", "WW", "ZZ",
        "M", "D", "h", "m", "s", "K", "A", "E", "W", "Q",
    ].sorted { $0.count > $1.count }
    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
    private static let englishWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    private static let englishMonths = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                                        "October", "November", "December"]

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
        let monthName = englishMonths[min(max(date.month, 1), 12) - 1]
        switch symbol {
        case "YYYY": return String(date.year)
        case "YY": return pad(date.year % 100)
        case "MMMM": return monthName
        case "MMM": return String(monthName.prefix(3))
        case "MM": return pad(date.month)
        case "M": return String(date.month)
        case "DDDD": return pad(date.dayOfYear, width: 3)
        case "DDD": return String(date.dayOfYear)
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
        case "AA": return date.hour < 12 ? "AM" : "PM"
        case "dddd": return weekdays[weekday] + "曜日"
        case "ddd": return weekdays[weekday]
        case "EEEE": return englishWeekdays[weekday]
        case "EEE": return String(englishWeekdays[weekday].prefix(3))
        case "GG": return Era.of(date).name
        case "E": return String(Era.of(date).year)
        case "WW": return pad(date.isoWeek)
        case "W": return String(date.isoWeek)
        case "Q": return String(date.quarter)
        case "ZZ":
            let offset = date.utcOffsetSeconds
            let sign = offset < 0 ? "-" : "+"
            return "\(sign)\(pad(abs(offset) / 3600)):\(pad(abs(offset) % 3600 / 60))"
        default: return symbol
        }
    }

    static func pad(_ value: Int, width: Int = 2) -> String {
        let digits = String(value)
        return value >= 0 && digits.count < width ? String(repeating: "0", count: width - digits.count) + digits : digits
    }

    /// 元号．明治より前の日は元号の名前を空にし，年は西暦の数を返す
    enum Era {
        /// 元号の名前と始まりの日(年・月・日)．新しい元号から並べる
        private static let eras: [(name: String, start: (Int, Int, Int))] = [
            ("令和", (2019, 5, 1)), ("平成", (1989, 1, 8)), ("昭和", (1926, 12, 25)), ("大正", (1912, 7, 30)), ("明治", (1868, 1, 25)),
        ]

        static func of(_ date: CalendarDate) -> (name: String, year: Int) {
            let key = (date.year, date.month, date.day)
            guard let era = eras.first(where: { key >= $0.start }) else { return ("", date.year) }
            return (era.name, date.year - era.start.0 + 1)
        }
    }
}
