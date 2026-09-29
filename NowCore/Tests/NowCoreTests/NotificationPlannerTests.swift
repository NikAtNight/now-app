import Foundation
import Testing
@testable import NowCore

struct NotificationPlannerTests {
    func plan(_ tasks: [TaskSnapshot], ranking: RankingSettings = RankingSettings(), notifications: NotificationSettings = NotificationSettings(), limit: Int = 60) -> [PlannedNotification] {
        NotificationPlanner.plan(tasks, now: now, ranking: ranking, notifications: notifications, calendar: utc, limit: limit)
    }

    @Test func headsUpAndDue() {
        let due = now.addingTimeInterval(3 * 3600)
        let result = plan([task("t", due: due)])
        #expect(result.map(\.kind) == [.headsUp, .due])
        #expect(result.map(\.fireDate) == [due.addingTimeInterval(-3600), due])
    }

    @Test func estimateSetsHeadsUpToStartBy() {
        let due = now.addingTimeInterval(5 * 3600)
        let result = plan([task("t", due: due, estimate: 90)])
        #expect(result.first?.fireDate == due.addingTimeInterval(-90 * 60))
    }

    @Test func pastNotificationsAreDropped() {
        // Heads-up would be 30 minutes ago.
        let result = plan([task("t", due: now.addingTimeInterval(1800))])
        #expect(result.map(\.kind) == [.due])
    }

    @Test func dateOnlyTasksAlertOnceInTheMorning() {
        // Not at 22:59 and 23:59, when a date-only task's deadline falls. That moment only gets a
        // silent badge update.
        let result = plan([task("t", due: date(2026, 9, 25, 12), hasTime: false)])
        #expect(result.map(\.kind) == [.due, .overdueBadge])
        #expect(result.map(\.fireDate) == [date(2026, 9, 25, 9), date(2026, 9, 25, 23, 59)])
    }

    @Test func dateOnlyMorningFollowsWorkingHours() {
        let ranking = RankingSettings(workingHours: WorkingHours(isEnabled: true, startMinute: 8 * 60))
        let result = plan([task("t", due: date(2026, 9, 25, 12), hasTime: false)], ranking: ranking)
        #expect(result.map(\.fireDate) == [date(2026, 9, 25, 8), date(2026, 9, 25, 17)])
    }

    @Test func dateOnlyTaskForTodayPastTheMorningOnlyUpdatesTheBadge() {
        let result = plan([task("t", due: date(2026, 9, 24, 12), hasTime: false)])
        #expect(result.map(\.kind) == [.overdueBadge])
    }

    @Test func badgeUpdatesAreNotHeldForWorkingHours() {
        // Silent, so there's nothing to hold back. Saturday's task still counts as overdue on Saturday night.
        let ranking = RankingSettings(workingHours: WorkingHours(isEnabled: true))
        let saturday = task("t", due: date(2026, 9, 26, 12), hasTime: false)
        let result = plan([saturday], ranking: ranking, notifications: NotificationSettings(muteOutsideWorkingHours: true))
        #expect(result.map(\.kind) == [.overdueBadge, .due])
        #expect(result.map(\.fireDate) == [date(2026, 9, 26, 17), date(2026, 9, 28, 9)])
    }

    @Test func undatedAndDoneTasksGetNothing() {
        #expect(plan([task("undated"), task("done", due: now.addingTimeInterval(7200), status: .done)]).isEmpty)
    }

    @Test func snoozeSilencesEarlierAlertsAndAddsItsOwn() {
        let due = now.addingTimeInterval(3 * 3600)
        let snoozeEnd = now.addingTimeInterval(2.5 * 3600)
        let result = plan([task("t", due: due, snoozedUntil: snoozeEnd)])
        #expect(result.map(\.kind) == [.snoozeEnded, .due])
    }

    @Test func mutedAlertsMoveToNextWorkingWindow() {
        let ranking = RankingSettings(workingHours: WorkingHours(isEnabled: true))
        let due = date(2026, 9, 24, 21) // Thursday 9pm, after hours.
        let result = plan([task("t", due: due)], ranking: ranking, notifications: NotificationSettings(muteOutsideWorkingHours: true))
        #expect(result.allSatisfy { $0.fireDate == date(2026, 9, 25, 9) })
    }

    @Test func respectsLimitKeepingTheSoonest() {
        let tasks = (1...50).map { task("t\($0)", due: now.addingTimeInterval(Double($0) * 7200)) }
        let result = plan(tasks, limit: 10)
        #expect(result.count == 10)
        #expect(result == result.sorted { $0.fireDate < $1.fireDate })
        #expect(result.first?.taskID == tasks[0].id)
    }
}
