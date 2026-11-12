/// 年月日と時刻の計算(ずらす・その週の曜日やその月の日に合わせる・UTC・UNIX 時間・週番号)．
/// 入れるときに中身を決める語(TextTemplate)の日時に使う．先発グレゴリオ暦で数え，OS の暦には頼らない(OS ごとに結果を変えないため)．
/// 時間帯の差(utcOffsetSeconds)はずらしても変えない．夏時間の切り替わりをまたいでずらすと，UTC と UNIX 時間が 1 時間ずれる
extension CalendarDate {
    /// ずらす単位
    public enum Unit: Sendable, Equatable {
        case minute, hour, day, week, month, year
    }

    /// 合わせる先
    public enum Anchor: Sendable, Equatable {
        /// その週(月曜から日曜)の曜日．1 が月曜，7 が日曜(ISO 8601)
        case weekday(Int)
        /// その月の日．月の日数より大きければ月末
        case dayOfMonth(Int)
        case endOfMonth
    }

    /// amount だけずらした日時．月と年でずらして月の日数を超えたら月末にする(1 月 31 日の 1 か月後は 2 月 28 日か 29 日)
    public func shifted(by amount: Int, _ unit: Unit) -> CalendarDate {
        switch unit {
        case .minute: return moved(days: 0, seconds: amount * 60)
        case .hour: return moved(days: 0, seconds: amount * 3600)
        case .day: return moved(days: amount, seconds: 0)
        case .week: return moved(days: amount * 7, seconds: 0)
        case .month, .year:
            let months = year * 12 + (month - 1) + (unit == .month ? amount : amount * 12)
            let newYear = Self.floorDivision(months, 12)
            let newMonth = months - newYear * 12 + 1
            return with(year: newYear, month: newMonth, day: min(day, Self.daysInMonth(year: newYear, month: newMonth)))
        }
    }

    /// 合わせた日．時刻はそのまま
    public func anchored(to anchor: Anchor) -> CalendarDate {
        switch anchor {
        case .weekday(let target): moved(days: min(max(target, 1), 7) - isoWeekday, seconds: 0)
        case .dayOfMonth(let target): with(year: year, month: month, day: min(max(target, 1), Self.daysInMonth(year: year, month: month)))
        case .endOfMonth: with(year: year, month: month, day: Self.daysInMonth(year: year, month: month))
        }
    }

    /// 1970 年 1 月 1 日 0 時(UTC)からの秒
    public var unixTime: Int { daysSinceEpoch * Self.secondsPerDay + secondsOfDay - utcOffsetSeconds }

    /// 同じ時点の協定世界時
    public var inUTC: CalendarDate {
        Self(days: daysSinceEpoch, seconds: secondsOfDay - utcOffsetSeconds, utcOffsetSeconds: 0)
    }

    /// その年の何日目か(1 月 1 日が 1)
    public var dayOfYear: Int { daysSinceEpoch - Self.days(year: year, month: 1, day: 1) + 1 }

    /// 曜日．1 が月曜，7 が日曜(ISO 8601)
    public var isoWeekday: Int { (weekday + 5) % 7 + 1 }

    /// ISO 8601 の週番号(1 月 4 日を含む週が第 1 週．週は月曜から)
    public var isoWeek: Int {
        // 週の木曜日がある年の週として数える
        let thursday = daysSinceEpoch + 4 - isoWeekday
        let thursdayYear = Self.civil(days: thursday).year
        return (thursday - Self.days(year: thursdayYear, month: 1, day: 1)) / 7 + 1
    }

    /// 四半期(1〜4)
    public var quarter: Int { (month - 1) / 3 + 1 }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    // MARK: - 日の数え方

    private static let secondsPerDay = 86_400

    private var secondsOfDay: Int { hour * 3600 + minute * 60 + second }

    private var daysSinceEpoch: Int { Self.days(year: year, month: month, day: day) }

    /// 1970 年 1 月 1 日からの日数と，その日の 0 時からの秒(範囲の外なら日に繰り入れる)から作る．曜日も数え直す
    private init(days: Int, seconds: Int, utcOffsetSeconds: Int) {
        let total = days + Self.floorDivision(seconds, Self.secondsPerDay)
        let rest = seconds - Self.floorDivision(seconds, Self.secondsPerDay) * Self.secondsPerDay
        let date = Self.civil(days: total)
        self.init(year: date.year, month: date.month, day: date.day, weekday: Self.weekday(days: total),
                  hour: rest / 3600, minute: rest % 3600 / 60, second: rest % 60, utcOffsetSeconds: utcOffsetSeconds)
    }

    private func moved(days: Int, seconds: Int) -> CalendarDate {
        Self(days: daysSinceEpoch + days, seconds: secondsOfDay + seconds, utcOffsetSeconds: utcOffsetSeconds)
    }

    private func with(year: Int, month: Int, day: Int) -> CalendarDate {
        Self(days: Self.days(year: year, month: month, day: day), seconds: secondsOfDay, utcOffsetSeconds: utcOffsetSeconds)
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    /// 1970 年 1 月 1 日(木曜)からの日数の曜日．1 が日曜
    private static func weekday(days: Int) -> Int {
        ((days % 7 + 7) % 7 + 4) % 7 + 1
    }

    private static func floorDivision(_ value: Int, _ divisor: Int) -> Int {
        value >= 0 ? value / divisor : -((-value + divisor - 1) / divisor)
    }

    /// 年月日 → 1970 年 1 月 1 日からの日数(3 月始まりの年に直して数える)
    static func days(year: Int, month: Int, day: Int) -> Int {
        let shiftedYear = month <= 2 ? year - 1 : year
        let era = floorDivision(shiftedYear, 400)
        let yearOfEra = shiftedYear - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// 1970 年 1 月 1 日からの日数 → 年月日
    static func civil(days: Int) -> (year: Int, month: Int, day: Int) {
        let shifted = days + 719_468
        let era = floorDivision(shifted, 146_097)
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return (year, month, day)
    }
}
