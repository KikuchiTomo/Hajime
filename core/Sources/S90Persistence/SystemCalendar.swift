import Foundation
import S90Application
import S90Domain

/// OS の時計と暦(グレゴリオ暦，端末の時間帯)から日時を読む
@MainActor
public final class SystemCalendar: CalendarReading {
    private let clock: () -> Date
    private let timeZone: (Date) -> TimeZone

    /// - Parameters:
    ///   - clock: 今の日時．組み立ての場所が OS の時計を渡し，テストでは決まった日時を渡す
    ///   - timeZone: その日時での時間帯．既定は端末の時間帯(夏時間の切り替わりに合わせて毎回読む)
    public init(clock: @escaping () -> Date, timeZone: @escaping (Date) -> TimeZone = SystemCalendar.localTimeZone(at:)) {
        self.clock = clock
        self.timeZone = timeZone
    }

    public func now() -> CalendarDate {
        components(of: clock())
    }

    public func day(offsetFromToday offset: Int) -> CalendarDate {
        let now = clock()
        let calendar = calendar(at: now)
        return components(of: calendar.date(byAdding: .day, value: offset, to: now) ?? now)
    }

    private func calendar(at date: Date) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone(date)
        return calendar
    }

    private func components(of date: Date) -> CalendarDate {
        let parts = calendar(at: date).dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        return CalendarDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0, weekday: parts.weekday ?? 1,
                            hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// 端末の時間帯．Windows の Foundation は OS の時間帯を読めず GMT を返すので，C ランタイムが読む
    /// その日時での UTC との差(夏時間を含む)から作る
    public nonisolated static func localTimeZone(at date: Date) -> TimeZone {
        #if os(Windows)
        var time = time_t(date.timeIntervalSince1970)
        var parts = tm()
        if localtime_s(&parts, &time) == 0 {
            let local = _mkgmtime(&parts)
            if local != -1, let zone = TimeZone(secondsFromGMT: Int(local - time)) {
                return zone
            }
        }
        #endif
        return .current
    }
}
