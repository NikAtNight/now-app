import Foundation
@testable import NowCore

let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Builds a UTC date. 2026-09-24 is a Thursday.
func date(_ year: Int = 2026, _ month: Int = 9, _ day: Int = 24, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// Thursday 2026-09-24, 10:00 UTC.
let now = date(2026, 9, 24, 10)

func task(
    _ title: String,
    priority: Priority = .none,
    due: Date? = nil,
    hasTime: Bool = true,
    estimate: Int? = nil,
    snoozedUntil: Date? = nil,
    status: TaskStatus = .todo,
    created: Date = date(2026, 1, 1)
) -> TaskSnapshot {
    TaskSnapshot(title: title, priority: priority, status: status, dueDate: due, hasDueTime: hasTime, estimateMinutes: estimate, snoozedUntil: snoozedUntil, createdAt: created)
}

extension Ranking {
    var focusTitles: [String] { focus.map(\.task.title) }
    var allTitles: [String] { all.map(\.task.title) }
}
