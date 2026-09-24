import Foundation
import Testing
@testable import NowCore

struct RankerTests {
    func rank(_ tasks: [TaskSnapshot], _ settings: RankingSettings = RankingSettings()) -> Ranking {
        Ranker.rank(tasks, now: now, settings: settings, calendar: utc)
    }

    @Test func focusShowsThreeAndHidesTheRest() {
        let tasks = (1...5).map { task("t\($0)", due: now.addingTimeInterval(Double($0) * 3600)) }
        let ranking = rank(tasks)
        #expect(ranking.focusTitles == ["t1", "t2", "t3"])
        #expect(ranking.hidden.map(\.task.title) == ["t4", "t5"])
        #expect(ranking.urgentOverflow == 2)
    }

    @Test func doneTasksAreExcluded() {
        let ranking = rank([task("done", due: now, status: .done), task("open")])
        #expect(ranking.allTitles == ["open"])
    }

    @Test func overdueIsPinnedEvenBeyondFocusCount() {
        let overdue = (1...4).map { task("late\($0)", due: now.addingTimeInterval(Double(-$0) * 60)) }
        let ranking = rank(overdue + [task("soon", priority: .high, due: now.addingTimeInterval(600))])
        #expect(ranking.focus.count == 4)
        #expect(ranking.focus.allSatisfy { $0.tier == .overdue })
        #expect(ranking.overdueCount == 4)
        #expect(ranking.hidden.map(\.task.title) == ["soon"])
    }

    @Test func overdueOrdersByPriorityThenOldest() {
        let ranking = rank([
            task("lowOld", priority: .low, due: now.addingTimeInterval(-7200)),
            task("highRecent", priority: .high, due: now.addingTimeInterval(-60)),
            task("lowRecent", priority: .low, due: now.addingTimeInterval(-60)),
        ])
        #expect(ranking.focusTitles == ["highRecent", "lowOld", "lowRecent"])
    }

    @Test func overdueWinsOverSnooze() {
        let ranking = rank([task("late", due: now.addingTimeInterval(-60), snoozedUntil: now.addingTimeInterval(3600))])
        #expect(ranking.focus.first?.tier == .overdue)
    }

    @Test func deadlineFirstMode() {
        let settings = RankingSettings(mode: .deadlineFirst)
        let ranking = rank([
            task("highLater", priority: .high, due: now.addingTimeInterval(5 * 3600)),
            task("lowSooner", priority: .low, due: now.addingTimeInterval(2 * 3600)),
        ], settings)
        #expect(ranking.focusTitles == ["lowSooner", "highLater"])
    }

    @Test func deadlineFirstBreaksTiesWithPriority() {
        let due = now.addingTimeInterval(3600)
        let ranking = rank([task("low", priority: .low, due: due), task("high", priority: .high, due: due)], RankingSettings(mode: .deadlineFirst))
        #expect(ranking.focusTitles == ["high", "low"])
    }

    @Test func priorityFirstMode() {
        let ranking = rank([
            task("lowSooner", priority: .low, due: now.addingTimeInterval(2 * 3600)),
            task("highLater", priority: .high, due: now.addingTimeInterval(20 * 3600)),
        ], RankingSettings(mode: .priorityFirst))
        #expect(ranking.focusTitles == ["highLater", "lowSooner"])
    }

    @Test func balancedLetsHighPriorityBeatNearerLowPriority() {
        // High due in 8h -> 8/4 = 2h effective. Low due in 3h -> 3h effective.
        let ranking = rank([
            task("low3h", priority: .low, due: now.addingTimeInterval(3 * 3600)),
            task("high8h", priority: .high, due: now.addingTimeInterval(8 * 3600)),
        ])
        #expect(ranking.focusTitles == ["high8h", "low3h"])
    }

    @Test func balancedStillRespectsLargeGaps() {
        // High due in 20h -> 5h effective. Low due in 1h -> 1h effective.
        let ranking = rank([
            task("high20h", priority: .high, due: now.addingTimeInterval(20 * 3600)),
            task("low1h", priority: .low, due: now.addingTimeInterval(3600)),
        ])
        #expect(ranking.focusTitles == ["low1h", "high20h"])
    }

    @Test func balancedPutsPastStartByFirst() {
        // Due in 1h but needs 2h: already 1h behind, beats a high priority with room.
        let ranking = rank([
            task("high", priority: .high, due: now.addingTimeInterval(2 * 3600)),
            task("behind", due: now.addingTimeInterval(3600), estimate: 120),
        ])
        #expect(ranking.focusTitles == ["behind", "high"])
        #expect(ranking.focus[0].tier == .urgent)
    }

    @Test func estimateMovesUrgencyToStartBy() {
        // Due in 30h, outside the 24h horizon, but a 10h estimate puts slack at 20h.
        let ranking = rank([task("big", due: now.addingTimeInterval(30 * 3600), estimate: 600)])
        #expect(ranking.focus[0].tier == .urgent)
        #expect(ranking.focus[0].startBy == now.addingTimeInterval(20 * 3600))
        #expect(abs((ranking.focus[0].slack ?? 0) - 20 * 3600) < 0.001)
    }

    @Test func undatedTasksWaitBehindUrgentOnes() {
        let ranking = rank([
            task("undatedHigh", priority: .high),
            task("urgentLow", priority: .low, due: now.addingTimeInterval(3600)),
        ])
        #expect(ranking.focusTitles == ["urgentLow", "undatedHigh"])
        #expect(ranking.focus[1].tier == .later)
    }

    @Test func laterTierIsPriorityThenDateThenUndated() {
        let ranking = rank([
            task("undatedMed", priority: .medium),
            task("datedMedFar", priority: .medium, due: date(2026, 10, 30, 9)),
            task("datedMedNear", priority: .medium, due: date(2026, 10, 1, 9)),
            task("undatedHigh", priority: .high),
        ], RankingSettings(focusCount: 10))
        #expect(ranking.focusTitles == ["undatedHigh", "datedMedNear", "datedMedFar", "undatedMed"])
    }

    @Test func undatedFillEmptySlots() {
        let ranking = rank([task("only urgent", due: now.addingTimeInterval(3600)), task("a", priority: .low), task("b")])
        #expect(ranking.focusTitles == ["only urgent", "a", "b"])
    }

    @Test func snoozedTasksAreHiddenAndLast() {
        let ranking = rank([
            task("snoozed", priority: .high, due: now.addingTimeInterval(3600), snoozedUntil: now.addingTimeInterval(1800)),
            task("normal"),
        ])
        #expect(ranking.focusTitles == ["normal"])
        #expect(ranking.hidden.map(\.tier) == [.snoozed])
    }

    @Test func expiredSnoozeIsIgnored() {
        let ranking = rank([task("back", due: now.addingTimeInterval(3600), snoozedUntil: now.addingTimeInterval(-60))])
        #expect(ranking.focus.first?.tier == .urgent)
    }

    @Test func dateOnlyTaskIsDueAtEndOfDay() {
        let ranking = rank([task("today", due: date(2026, 9, 24), hasTime: false)])
        #expect(ranking.focus[0].effectiveDue == date(2026, 9, 24, 23, 59))
        #expect(ranking.focus[0].tier == .urgent)
    }

    @Test func dateOnlyTaskUsesEndOfWorkdayWhenWorkingHoursOn() {
        let settings = RankingSettings(workingHours: WorkingHours(isEnabled: true))
        let ranking = rank([task("today", due: date(2026, 9, 24), hasTime: false)], settings)
        #expect(ranking.focus[0].effectiveDue == date(2026, 9, 24, 17))
    }

    @Test func workingHoursMakeMondayMorningUrgentOnFriday() {
        let friday5pm = date(2026, 9, 25, 17)
        let mondayMorning = date(2026, 9, 28, 9, 30)
        let dueMonday = task("monday", due: mondayMorning)

        let clock = Ranker.rank([dueMonday], now: friday5pm, settings: RankingSettings(), calendar: utc)
        #expect(clock.focus[0].tier == .later)

        let working = Ranker.rank([dueMonday], now: friday5pm, settings: RankingSettings(workingHours: WorkingHours(isEnabled: true)), calendar: utc)
        #expect(working.focus[0].tier == .urgent)
        #expect(abs((working.focus[0].slack ?? 0) - 30 * 60) < 0.001)
    }

    @Test func orderIsDeterministicForIdenticalTasks() {
        let a = task("a", created: date(2026, 1, 1))
        let b = task("b", created: date(2026, 1, 2))
        #expect(rank([b, a]).focusTitles == ["a", "b"])
        #expect(rank([a, b]).focusTitles == ["a", "b"])
    }
}
