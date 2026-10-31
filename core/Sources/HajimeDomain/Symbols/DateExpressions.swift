/// 年月日と時刻．DateExpressions に渡す，暦の計算を済ませた値
public struct CalendarDate: Sendable, Equatable {
    public var year: Int
    public var month: Int
    public var day: Int
    /// 1 が日曜日
    public var weekday: Int
    public var hour: Int
    public var minute: Int
    public var second: Int
    /// UTC との差(秒)．ISO 8601 の形(「+09:00」)に使う
    public var utcOffsetSeconds: Int

    public init(year: Int, month: Int, day: Int, weekday: Int, hour: Int = 0, minute: Int = 0, second: Int = 0, utcOffsetSeconds: Int = 0) {
        self.year = year
        self.month = month
        self.day = day
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
        self.second = second
        self.utcOffsetSeconds = utcOffsetSeconds
    }
}

/// 「きょう」「あした」「いま」などの読みを，日付や時刻の候補にする
public enum DateExpressions {
    /// 読みと，今日から何日ずらすか
    private static let dayOffsets: [String: Int] = [
        "おととい": -2, "きのう": -1, "きょう": 0, "ほんじつ": 0, "あした": 1, "あす": 1, "みょうにち": 1, "あさって": 2,
    ]
    private static let yearOffsets: [String: Int] = ["きょねん": -1, "ことし": 0, "らいねん": 1]
    private static let nowReadings: Set<String> = ["いま", "げんざい"]
    /// 「にちじ」は日付と時刻を合わせた形(「2026/11/01 12:34:56」など)にする
    private static let dateTimeReadings: Set<String> = ["にちじ", "にちじこく", "たいむすたんぷ"]
    /// 「にちじ」の形．書式の記号は DateTimeFormat
    static let dateTimeFormats = [
        "YYYY/MM/DD hh:mm:ss", "YYYY/MM/DD hh:mm", "YYYY-MM-DD hh:mm:ss", "YYYY-MM-DD'T'hh:mm:ssZZ", "YYYY年M月D日 h時m分s秒",
        "YYYY年M月D日(ddd) h:mm", "GGE年M月D日 h時m分", "YYYYMMDDhhmmss",
    ]
    /// 「なう」は，今していることに添える日時の形(「なう (2026/10/28 01:08)」)にする
    private static let nowStampReading = "なう"
    private static let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]
    /// 令和元年の前の年．令和 n 年は西暦 n + 2018 年
    private static let reiwaOffset = 2018

    /// 読みに当たる候補．day は「今日から n 日ずらした日」を返す(暦の計算は呼び出し側で行う)
    public static func candidates(for reading: String, now: CalendarDate, day: (Int) -> CalendarDate) -> [String] {
        if let offset = dayOffsets[reading] {
            let date = day(offset)
            let week = weekdayNames[(date.weekday - 1 + 7) % 7]
            return [
                "\(date.year)/\(date.month)/\(date.day)",
                "\(date.year)-\(pad(date.month))-\(pad(date.day))",
                "\(date.year)年\(date.month)月\(date.day)日",
                "\(date.month)月\(date.day)日(\(week))",
                "令和\(date.year - reiwaOffset)年\(date.month)月\(date.day)日",
                "\(date.month)/\(date.day)(\(week))",
            ]
        }
        if let offset = yearOffsets[reading] {
            let year = now.year + offset
            return ["\(year)年", "令和\(year - reiwaOffset)年"]
        }
        if reading == nowStampReading {
            let stamp = "\(now.year)/\(pad(now.month))/\(pad(now.day)) \(pad(now.hour)):\(pad(now.minute))"
            return ["\(reading) (\(stamp))", stamp]
        }
        if nowReadings.contains(reading) {
            let half = now.hour < 12 ? "午前" : "午後"
            let hour12 = now.hour % 12
            return ["\(now.hour):\(pad(now.minute))", "\(now.hour)時\(now.minute)分", "\(half)\(hour12)時\(now.minute)分",
                    "\(pad(now.hour)):\(pad(now.minute)):\(pad(now.second))"]
        }
        if dateTimeReadings.contains(reading) {
            return dateTimeFormats.map { DateTimeFormat.format($0, date: now) }
        }
        return []
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
