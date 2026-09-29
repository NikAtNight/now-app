import Foundation
import Testing
@testable import NowCore

struct QuickDateTests {
    let hours = WorkingHours()

    @Test func presets() {
        #expect(QuickDate.inOneHour.date(from: now, workingHours: hours, calendar: utc) == date(2026, 9, 24, 11))
        #expect(QuickDate.thisEvening.date(from: now, workingHours: hours, calendar: utc) == date(2026, 9, 24, 18))
        #expect(QuickDate.tomorrowMorning.date(from: now, workingHours: hours, calendar: utc) == date(2026, 9, 25, 9))
        #expect(QuickDate.nextWeek.date(from: now, workingHours: hours, calendar: utc) == date(2026, 9, 28, 9))
    }

    @Test func thisEveningDisappearsAfterSix() {
        #expect(QuickDate.thisEvening.date(from: date(2026, 9, 24, 19), workingHours: hours, calendar: utc) == nil)
    }

    @Test func nextWeekFromMondayIsAWeekOut() {
        #expect(QuickDate.nextWeek.date(from: date(2026, 9, 28, 10), workingHours: hours, calendar: utc) == date(2026, 10, 5, 9))
    }

    @Test func thisMorningOnlyBeforeTheMorning() {
        // At 01:30 "Tomorrow Morning" is a day and a half away, so this morning gets its own preset.
        #expect(QuickDate.thisMorning.date(from: date(2026, 9, 24, 1, 30), workingHours: hours, calendar: utc) == date(2026, 9, 24, 9))
        #expect(QuickDate.thisMorning.date(from: now, workingHours: hours, calendar: utc) == nil)
    }

    @Test func morningFollowsWorkingHours() {
        let early = WorkingHours(isEnabled: true, startMinute: 7 * 60 + 30)
        #expect(QuickDate.tomorrowMorning.date(from: now, workingHours: early, calendar: utc) == date(2026, 9, 25, 7, 30))
    }
}

struct DueLabelTests {
    let locale = Locale(identifier: "en_GB")

    @Test func relativeDays() {
        #expect(DueLabel.text(for: date(2026, 9, 24, 10), hasTime: true, now: now, calendar: utc, locale: locale) == "Today, 10:00")
        #expect(DueLabel.text(for: date(2026, 9, 25), hasTime: false, now: now, calendar: utc, locale: locale) == "Tomorrow")
        #expect(DueLabel.text(for: date(2026, 9, 23), hasTime: false, now: now, calendar: utc, locale: locale) == "Yesterday")
        #expect(DueLabel.text(for: date(2026, 9, 27, 18), hasTime: true, now: now, calendar: utc, locale: locale) == "2026-09-27, 18:00")
    }

    @Test func durations() {
        #expect(DueLabel.duration(35 * 60) == "35m")
        #expect(DueLabel.duration(-130 * 60) == "2h 10m")
        #expect(DueLabel.duration(3 * 3600) == "3h")
        #expect(DueLabel.duration(80 * 3600) == "3d")
    }
}
