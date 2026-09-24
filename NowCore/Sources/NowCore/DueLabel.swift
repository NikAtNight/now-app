import Foundation

/// Reminders-style due text: "Today, 10:00", "Tomorrow", "2026-09-27, 18:00".
public enum DueLabel {
    public static func text(for due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let day: String
        if calendar.isDate(due, inSameDayAs: now) {
            day = "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(due, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else {
            day = due.formatted(Date.ISO8601FormatStyle(timeZone: calendar.timeZone).year().month().day())
        }
        guard hasTime else { return day }
        return "\(day), \(timeText(due, calendar: calendar, locale: locale))"
    }

    public static func timeText(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// "35m", "2h 10m", "3d". Rounds to the minute.
    public static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int((abs(interval) / 60).rounded())
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60, rest = minutes % 60
        if hours < 24 { return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m" }
        let days = hours / 24
        return "\(days)d"
    }
}
