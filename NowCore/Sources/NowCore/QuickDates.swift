import Foundation

/// One-tap reschedule and snooze targets.
public enum QuickDate: String, CaseIterable, Identifiable, Sendable {
    case inFifteenMinutes, inOneHour, thisEvening, tomorrowMorning, nextWeek

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .inFifteenMinutes: "In 15 Minutes"
        case .inOneHour: "In 1 Hour"
        case .thisEvening: "This Evening"
        case .tomorrowMorning: "Tomorrow Morning"
        case .nextWeek: "Next Week"
        }
    }

    public static let reschedule: [QuickDate] = [.inOneHour, .thisEvening, .tomorrowMorning, .nextWeek]
    public static let snooze: [QuickDate] = [.inFifteenMinutes, .inOneHour, .tomorrowMorning]

    /// The target date, or nil when it no longer makes sense (e.g. "This Evening" after 6pm).
    /// Morning means the start of working hours when set, otherwise 9:00.
    public func date(from now: Date, workingHours: WorkingHours, calendar: Calendar = .current) -> Date? {
        let morningMinute = workingHours.isEnabled ? workingHours.startMinute : 9 * 60
        let today = calendar.startOfDay(for: now)

        func at(_ minute: Int, daysFromToday days: Int) -> Date? {
            calendar.date(byAdding: .day, value: days, to: today)
                .flatMap { calendar.date(byAdding: .minute, value: minute, to: $0) }
        }

        switch self {
        case .inFifteenMinutes:
            return now.addingTimeInterval(15 * 60)
        case .inOneHour:
            return now.addingTimeInterval(3600)
        case .thisEvening:
            guard let evening = at(18 * 60, daysFromToday: 0), evening > now else { return nil }
            return evening
        case .tomorrowMorning:
            return at(morningMinute, daysFromToday: 1)
        case .nextWeek:
            // Next Monday. On a Monday, that's a week out.
            let weekday = calendar.component(.weekday, from: now)
            let untilMonday = (9 - weekday) % 7
            let days = untilMonday == 0 ? 7 : untilMonday
            return at(morningMinute, daysFromToday: days)
        }
    }
}
