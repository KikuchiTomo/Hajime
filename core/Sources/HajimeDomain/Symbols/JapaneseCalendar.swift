/// 日本の暦の名前(祝日・和風月名・干支・年度・時候の挨拶・時間帯の挨拶)．入れるときに中身を決める語(TextTemplate)と
/// 日時の書式(DateTimeFormat)で使う．OS の暦には頼らない(OS ごとに結果を変えないため)
public enum JapaneseCalendar {
    // MARK: - 祝日

    /// 祝日を求められる年．今の祝日法(天皇誕生日が 2 月 23 日)になった 2020 年から，春分と秋分の式が合う 2099 年まで
    public static let holidayYears = 2020...2099

    /// その日の祝日・休日の名前(振替休日と国民の休日を含む)．祝日でない日と，holidayYears の外の年は nil．
    /// 春分の日と秋分の日は式で求めるので，官報で決まった日と違う年がありうる
    public static func holiday(on date: CalendarDate) -> String? {
        holidays(in: date.year)[date.daysSinceEpoch]
    }

    /// 平日(土日でも祝日でもない日)か
    public static func isBusinessDay(_ date: CalendarDate) -> Bool {
        date.weekday != 1 && date.weekday != 7 && holiday(on: date) == nil
    }

    /// その年の祝日と休日．鍵は 1970 年 1 月 1 日からの日数
    static func holidays(in year: Int) -> [Int: String] {
        guard holidayYears.contains(year) else { return [:] }
        var holidays: [Int: String] = [:]
        func add(_ month: Int, _ day: Int, _ name: String) {
            holidays[CalendarDate.days(year: year, month: month, day: day)] = name
        }
        add(1, 1, "元日")
        add(1, monday(year: year, month: 1, week: 2), "成人の日")
        add(2, 11, "建国記念の日")
        add(2, 23, "天皇誕生日")
        add(3, equinox(year: year, base: 20.8431), "春分の日")
        add(4, 29, "昭和の日")
        add(5, 3, "憲法記念日")
        add(5, 4, "みどりの日")
        add(5, 5, "こどもの日")
        // 2020 年と 2021 年は，東京オリンピックのために海の日・スポーツの日・山の日を移した
        switch year {
        case 2020:
            add(7, 23, "海の日")
            add(7, 24, "スポーツの日")
            add(8, 10, "山の日")
        case 2021:
            add(7, 22, "海の日")
            add(7, 23, "スポーツの日")
            add(8, 8, "山の日")
        default:
            add(7, monday(year: year, month: 7, week: 3), "海の日")
            add(8, 11, "山の日")
            add(10, monday(year: year, month: 10, week: 2), "スポーツの日")
        }
        add(9, monday(year: year, month: 9, week: 3), "敬老の日")
        add(9, equinox(year: year, base: 23.2488), "秋分の日")
        add(11, 3, "文化の日")
        add(11, 23, "勤労感謝の日")
        let nationalHolidays = holidays.keys.sorted()
        // 国民の休日: 前の日と次の日が祝日で，その日は祝日でない日
        for day in nationalHolidays where holidays[day + 2] != nil && holidays[day + 1] == nil {
            holidays[day + 1] = "国民の休日"
        }
        // 振替休日: 日曜日の祝日のあと，祝日でない最初の日
        for day in nationalHolidays where CalendarDate.weekday(days: day) == 1 {
            var next = day + 1
            while holidays[next] != nil { next += 1 }
            holidays[next] = "振替休日"
        }
        return holidays
    }

    /// その月の第 week 月曜日の日
    private static func monday(year: Int, month: Int, week: Int) -> Int {
        let first = CalendarDate.weekday(days: CalendarDate.days(year: year, month: month, day: 1))
        return 1 + (2 - first + 7) % 7 + (week - 1) * 7
    }

    /// 春分の日(base 20.8431)と秋分の日(base 23.2488)の日．1980〜2099 年に合う式
    private static func equinox(year: Int, base: Double) -> Int {
        Int(base + 0.242194 * Double(year - 1980)) - (year - 1980) / 4
    }

    // MARK: - 暦の名前

    private static let monthNames = ["睦月", "如月", "弥生", "卯月", "皐月", "水無月", "文月", "葉月", "長月", "神無月", "霜月", "師走"]
    private static let heavenlyStems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let earthlyBranches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    /// 月ごとの時候の挨拶(手紙の書き出し)
    private static let seasonalGreetings = [
        "厳寒の候", "余寒の候", "早春の候", "陽春の候", "新緑の候", "梅雨の候", "盛夏の候", "残暑の候", "初秋の候", "秋冷の候", "晩秋の候", "師走の候",
    ]
    /// 年度の始まりの月
    private static let fiscalYearStartMonth = 4
    /// 時間帯の挨拶と，その挨拶にする時刻の始まり(時)．遅い時刻から並べる
    private static let greetings: [(from: Int, text: String)] = [(18, "こんばんは"), (11, "こんにちは"), (4, "おはようございます")]

    /// 和風月名(11 月 → 霜月)
    public static func monthName(_ month: Int) -> String {
        monthNames[min(max(month, 1), 12) - 1]
    }

    /// 年の干支(2026 → 丙午)．年の切り替わりは 1 月 1 日にする
    public static func sexagenaryYear(_ year: Int) -> String {
        heavenlyStems[floorModulo(year - 4, 10)] + earthlyBranches[floorModulo(year - 4, 12)]
    }

    /// 年度(4 月始まり．2027 年 3 月は 2026 年度)
    public static func fiscalYear(of date: CalendarDate) -> Int {
        date.month >= fiscalYearStartMonth ? date.year : date.year - 1
    }

    /// 月の時候の挨拶(11 月 → 晩秋の候)
    public static func seasonalGreeting(month: Int) -> String {
        seasonalGreetings[min(max(month, 1), 12) - 1]
    }

    /// 時刻の挨拶(4〜10 時はおはようございます，11〜17 時はこんにちは，ほかはこんばんは)
    public static func greeting(hour: Int) -> String {
        greetings.first { hour >= $0.from }?.text ?? greetings[0].text
    }

    private static func floorModulo(_ value: Int, _ divisor: Int) -> Int {
        (value % divisor + divisor) % divisor
    }
}
