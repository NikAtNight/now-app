import Foundation

/// How a task repeats once completed: every `interval` days, weeks, months, or years, and for
/// weekly rules optionally on chosen weekdays ("every 2 weeks on Mon, Wed").
///
/// The common rules are named presets. They keep the raw values the app stored before custom
/// rules existed ("daily", "weekly", …), so older tasks still decode.
public struct Recurrence: Hashable, Sendable, RawRepresentable, CaseIterable {
    public enum Unit: String, CaseIterable, Sendable {
        case day, week, month, year
    }

    public var unit: Unit
    /// At least 1.
    public var interval: Int
    /// For weekly rules, the `Calendar` weekdays it falls on (1 = Sunday … 7 = Saturday).
    /// Empty means the due date's own weekday. Always empty for other units.
    public var weekdays: Set<Int>

    public init(unit: Unit, interval: Int = 1, weekdays: Set<Int> = []) {
        self.unit = unit
        self.interval = max(1, interval)
        self.weekdays = unit == .week ? weekdays.filter { (1...7).contains($0) } : []
    }

    // Compare the fields. The default for a RawRepresentable type compares `rawValue`, which
    // itself looks up presets by equality, so it would recurse forever.
    public static func == (lhs: Recurrence, rhs: Recurrence) -> Bool {
        lhs.unit == rhs.unit && lhs.interval == rhs.interval && lhs.weekdays == rhs.weekdays
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(unit)
        hasher.combine(interval)
        hasher.combine(weekdays)
    }

    public static let daily = Recurrence(unit: .day)
    public static let weekdays = Recurrence(unit: .week, weekdays: [2, 3, 4, 5, 6])
    public static let weekly = Recurrence(unit: .week)
    public static let biweekly = Recurrence(unit: .week, interval: 2)
    public static let monthly = Recurrence(unit: .month)
    public static let yearly = Recurrence(unit: .year)

    /// The presets, in menu order.
    public static let allCases: [Recurrence] = [.daily, .weekdays, .weekly, .biweekly, .monthly, .yearly]

    private static let presetNames: [(rule: Recurrence, name: String)] = [
        (.daily, "daily"), (.weekdays, "weekdays"), (.weekly, "weekly"),
        (.biweekly, "biweekly"), (.monthly, "monthly"), (.yearly, "yearly"),
    ]

    public var isPreset: Bool { Self.allCases.contains(self) }

    /// Presets use their names; custom rules are "every:<interval>:<unit>[:<weekdays>]".
    public var rawValue: String {
        if let preset = Self.presetNames.first(where: { $0.rule == self }) { return preset.name }
        var raw = "every:\(interval):\(unit.rawValue)"
        if !weekdays.isEmpty { raw += ":" + weekdays.sorted().map(String.init).joined(separator: ",") }
        return raw
    }

    public init?(rawValue: String) {
        if let preset = Self.presetNames.first(where: { $0.name == rawValue }) {
            self = preset.rule
            return
        }
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "every", let interval = Int(parts[1]), interval >= 1,
              let unit = Unit(rawValue: String(parts[2])) else { return nil }
        let days = parts.count > 3 ? Set(parts[3].split(separator: ",").compactMap { Int($0) }) : []
        self.init(unit: unit, interval: interval, weekdays: days)
    }

    public var label: String {
        switch self {
        case .daily: return "Every Day"
        case .weekdays: return "Every Weekday"
        case .weekly: return "Every Week"
        case .monthly: return "Every Month"
        case .yearly: return "Every Year"
        default: break
        }
        let names: (singular: String, plural: String) = switch unit {
        case .day: ("Day", "Days")
        case .week: ("Week", "Weeks")
        case .month: ("Month", "Months")
        case .year: ("Year", "Years")
        }
        var text = interval == 1 ? "Every \(names.singular)" : "Every \(interval) \(names.plural)"
        if !weekdays.isEmpty {
            let symbols = Calendar(identifier: .gregorian).shortWeekdaySymbols
            text += " on " + weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
        }
        return text
    }

    /// The next occurrence for a repeating task that was due at `due` and is being completed at `now`.
    /// Always after both, skipping missed occurrences, and keeps the local time of day of `due`.
    /// Occurrences are counted from `due` itself, so monthly and yearly don't drift after short months.
    public func nextDue(after due: Date, now: Date, calendar: Calendar) -> Date {
        let floor = max(due, now)
        if unit == .week, !weekdays.isEmpty {
            return nextOnWeekdays(after: due, floor: floor, calendar: calendar)
        }
        let (component, size) = step
        // Start near `now` so a very overdue task doesn't walk every missed occurrence.
        let elapsed = calendar.dateComponents([component], from: due, to: now).value(for: component) ?? 0
        var k = max(1, elapsed / size - 1)
        for _ in 0..<1000 {
            if let next = calendar.date(byAdding: component, value: k * size, to: due), next > floor {
                return next
            }
            k += 1
        }
        return calendar.date(byAdding: component, value: size, to: floor) ?? floor.addingTimeInterval(86_400)
    }

    /// The occurrence after `currentDue` in a series, when it's completed at `now`.
    ///
    /// Monthly and yearly count from `anchor` (the series' first due date) so short months don't
    /// shift later occurrences: Jan 31, Feb 28, Mar 31. Other rules step from `currentDue`.
    /// The result is after both `currentDue` and `now`, and keeps `currentDue`'s time of day, so
    /// moving one occurrence to a new time carries over.
    public func nextOccurrence(currentDue: Date, anchor: Date?, now: Date, calendar: Calendar) -> Date {
        // Search from the anchor's day at this occurrence's time, so an occurrence moved to an
        // earlier or later time still steps past itself and the new time carries over.
        let time = calendar.dateComponents([.hour, .minute, .second], from: currentDue)
        let base: Date
        switch unit {
        case .month, .year:
            let anchorDay = anchor ?? currentDue
            base = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: anchorDay) ?? anchorDay
        case .day, .week:
            base = currentDue
        }
        return nextDue(after: base, now: max(currentDue, now), calendar: calendar)
    }

    /// Walks forward a day at a time to the next chosen weekday in a week that's on the rhythm
    /// (every `interval` weeks, counted from the due date's week).
    private func nextOnWeekdays(after due: Date, floor: Date, calendar: Calendar) -> Date {
        let dueWeek = calendar.dateInterval(of: .weekOfYear, for: due)?.start ?? due
        // Start just before `floor` so a very overdue task doesn't walk every missed day.
        var offset = max(0, (calendar.dateComponents([.day], from: due, to: floor).day ?? 0) - 1)
        for _ in 0..<(14 * interval + 14) {
            if let day = calendar.date(byAdding: .day, value: offset, to: due), day > floor,
               weekdays.contains(calendar.component(.weekday, from: day)),
               let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start,
               let weeks = calendar.dateComponents([.weekOfYear], from: dueWeek, to: week).weekOfYear,
               weeks % interval == 0 {
                return day
            }
            offset += 1
        }
        return calendar.date(byAdding: .day, value: 7 * interval, to: floor) ?? floor.addingTimeInterval(7 * 86_400)
    }

    /// One step, as a calendar component and count.
    private var step: (Calendar.Component, Int) {
        switch unit {
        case .day: (.day, interval)
        case .week: (.day, 7 * interval)
        case .month: (.month, interval)
        case .year: (.year, interval)
        }
    }
}
