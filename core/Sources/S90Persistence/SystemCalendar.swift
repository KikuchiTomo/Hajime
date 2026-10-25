import Foundation
import S90Application
import S90Domain

/// OS の時計と暦(グレゴリオ暦，端末の時間帯)から日時を読む
@MainActor
public final class SystemCalendar: CalendarReading {
    private let calendar = Calendar(identifier: .gregorian)
    private let clock: () -> Date

    /// - Parameter clock: 今の日時．組み立ての場所が OS の時計を渡し，テストでは決まった日時を渡す
    public init(clock: @escaping () -> Date) {
        self.clock = clock
    }

    public func now() -> CalendarDate {
        components(of: clock())
    }

    public func day(offsetFromToday offset: Int) -> CalendarDate {
        components(of: calendar.date(byAdding: .day, value: offset, to: clock()) ?? clock())
    }

    private func components(of date: Date) -> CalendarDate {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        return CalendarDate(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0, weekday: parts.weekday ?? 1,
                            hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}
