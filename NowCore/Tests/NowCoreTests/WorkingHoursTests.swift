import Foundation
import Testing
@testable import NowCore

struct WorkingHoursTests {
    let hours = WorkingHours(isEnabled: true)

    @Test func countsOnlyInsideTheWindow() {
        // Thu 08:00 -> Thu 12:00 = 3h (09:00-12:00).
        #expect(hours.workingSeconds(from: date(2026, 9, 24, 8), to: date(2026, 9, 24, 12), calendar: utc) == 3 * 3600)
    }

    @Test func skipsWeekends() {
        // Fri 16:00 -> Mon 10:00 = 1h Friday + 1h Monday.
        #expect(hours.workingSeconds(from: date(2026, 9, 25, 16), to: date(2026, 9, 28, 10), calendar: utc) == 2 * 3600)
    }

    @Test func reversedRangeIsZero() {
        #expect(hours.workingSeconds(from: date(2026, 9, 24, 12), to: date(2026, 9, 24, 10), calendar: utc) == 0)
    }

    @Test func emptyScheduleIsZero() {
        let none = WorkingHours(isEnabled: true, weekdays: [])
        #expect(none.workingSeconds(from: date(2026, 9, 24), to: date(2026, 9, 30), calendar: utc) == 0)
    }

    @Test func nextWorkingMoment() {
        #expect(hours.nextWorkingMoment(atOrAfter: date(2026, 9, 24, 10), calendar: utc) == date(2026, 9, 24, 10))
        #expect(hours.nextWorkingMoment(atOrAfter: date(2026, 9, 24, 7), calendar: utc) == date(2026, 9, 24, 9))
        #expect(hours.nextWorkingMoment(atOrAfter: date(2026, 9, 25, 18), calendar: utc) == date(2026, 9, 28, 9))
    }

    @Test func handlesDaylightSavingDay() {
        var vancouver = Calendar(identifier: .gregorian)
        vancouver.timeZone = TimeZone(identifier: "America/Vancouver")!
        // 2026-11-01 is a Sunday (DST ends). Monday 11-02 09:00-17:00 should be a normal 8h.
        let everyDay = WorkingHours(isEnabled: true, weekdays: Set(1...7))
        let sunday = vancouver.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let tuesday = vancouver.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        #expect(everyDay.workingSeconds(from: sunday, to: tuesday, calendar: vancouver) == 16 * 3600)
    }
}

struct InvalidWorkingHoursTests {
    static let invalid = [
        WorkingHours(isEnabled: true, weekdays: [], startMinute: 7 * 60 + 30),
        WorkingHours(isEnabled: true, startMinute: 17 * 60, endMinute: 9 * 60),
        WorkingHours(isEnabled: true, startMinute: 9 * 60, endMinute: 9 * 60),
    ]

    @Test func isValid() {
        #expect(WorkingHours(isEnabled: true).isValid)
        #expect(Self.invalid.allSatisfy { !$0.isValid })
    }

    @Test(arguments: invalid)
    func timeRemainingFallsBackToWallClock(_ hours: WorkingHours) {
        let ranking = RankingSettings(workingHours: hours)
        let due = date(2026, 9, 26, 10) // Saturday, 48h away.
        #expect(ranking.timeRemaining(until: due, now: now, calendar: utc) == 48 * 3600)
    }

    @Test(arguments: invalid)
    func dateOnlyTasksAreDueAt2359(_ hours: WorkingHours) {
        #expect(RankingSettings(workingHours: hours).dateOnlyDueMinute == 23 * 60 + 59)
    }

    @Test(arguments: invalid)
    func mutedAlertsAreNotMoved(_ hours: WorkingHours) {
        let due = date(2026, 9, 24, 21)
        let result = NotificationPlanner.plan([task("t", due: due)], now: now, ranking: RankingSettings(workingHours: hours), notifications: NotificationSettings(muteOutsideWorkingHours: true), calendar: utc)
        #expect(result.map(\.fireDate) == [due.addingTimeInterval(-3600), due])
    }

    @Test(arguments: invalid)
    func morningIsNine(_ hours: WorkingHours) {
        #expect(QuickDate.tomorrowMorning.date(from: now, workingHours: hours, calendar: utc) == date(2026, 9, 25, 9))
    }
}
