import Foundation
import Testing
@testable import NowCore

struct DaylightSavingTests {
    @Test(arguments: [0, 1])
    func dateOnlyTaskIsDueAtLocal2359(_ index: Int) {
        let (month, day) = dstDays[index]
        let t = task("t", due: torontoDate(2026, month, day, 12), hasTime: false)
        #expect(RankingSettings().effectiveDue(for: t, calendar: toronto) == torontoDate(2026, month, day, 23, 59))
    }

    @Test(arguments: [0, 1])
    func workingWindowIsLocalNineToFive(_ index: Int) {
        let (month, day) = dstDays[index]
        let everyDay = WorkingHours(isEnabled: true, weekdays: Set(1...7))
        let window = everyDay.window(on: torontoDate(2026, month, day, 12), calendar: toronto)
        #expect(window?.start == torontoDate(2026, month, day, 9))
        #expect(window?.end == torontoDate(2026, month, day, 17))
    }

    @Test(arguments: [0, 1])
    func tomorrowMorningCrossesTheChange(_ index: Int) {
        let (month, day) = dstDays[index]
        let lateBefore = toronto.date(byAdding: .hour, value: 23, to: toronto.date(byAdding: .day, value: -1, to: torontoDate(2026, month, day))!)!
        #expect(QuickDate.tomorrowMorning.date(from: lateBefore, workingHours: WorkingHours(), calendar: toronto) == torontoDate(2026, month, day, 9))
    }
}
