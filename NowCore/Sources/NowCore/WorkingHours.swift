import Foundation

public struct WorkingHours: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// `Calendar` weekday numbers, 1 = Sunday ... 7 = Saturday.
    public var weekdays: Set<Int>
    /// Minutes after midnight.
    public var startMinute: Int
    public var endMinute: Int

    public init(isEnabled: Bool = false, weekdays: Set<Int> = [2, 3, 4, 5, 6], startMinute: Int = 9 * 60, endMinute: Int = 17 * 60) {
        self.isEnabled = isEnabled
        self.weekdays = weekdays
        self.startMinute = startMinute
        self.endMinute = endMinute
    }

    public static let standard = WorkingHours()

    /// False when no weekdays are picked or the day ends at or before it starts.
    public var isValid: Bool { !weekdays.isEmpty && endMinute > startMinute }

    /// On and valid. Invalid working hours are treated as off.
    var isActive: Bool { isEnabled && isValid }

    /// When "morning" is, in minutes after midnight: the start of the workday when working hours
    /// are on, otherwise 9:00. Used by the morning quick dates and date-only alerts.
    public var morningMinute: Int { isActive ? startMinute : 9 * 60 }

    /// The working window on the day containing `date`, or nil if that day isn't a working day.
    public func window(on date: Date, calendar: Calendar) -> DateInterval? {
        guard isValid, weekdays.contains(calendar.component(.weekday, from: date)) else { return nil }
        guard let start = calendar.date(atMinute: startMinute, on: date),
              let end = calendar.date(atMinute: endMinute, on: date) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Working seconds in `[from, to)`. Returns 0 if `to <= from` or the schedule is empty.
    public func workingSeconds(from: Date, to: Date, calendar: Calendar) -> TimeInterval {
        guard to > from, isValid else { return 0 }
        var total: TimeInterval = 0
        var day = calendar.startOfDay(for: from)
        while day < to {
            if let window = window(on: day, calendar: calendar) {
                let start = max(window.start, from)
                let end = min(window.end, to)
                if end > start { total += end.timeIntervalSince(start) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    /// `date` if it falls inside working hours, otherwise the start of the next working window.
    /// Returns `date` unchanged when the schedule is empty.
    public func nextWorkingMoment(atOrAfter date: Date, calendar: Calendar) -> Date {
        guard isValid else { return date }
        var day = calendar.startOfDay(for: date)
        for _ in 0..<8 {
            if let window = window(on: day, calendar: calendar), window.end > date {
                return max(window.start, date)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return date
    }
}
