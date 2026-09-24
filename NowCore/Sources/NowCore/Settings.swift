import Foundation

public struct RankingSettings: Codable, Hashable, Sendable {
    public var mode: RankingMode
    /// A task becomes urgent once its slack drops below this.
    public var urgencyHorizon: TimeInterval
    public var workingHours: WorkingHours
    public var focusCount: Int

    public init(mode: RankingMode = .balanced, urgencyHorizon: TimeInterval = 24 * 3600, workingHours: WorkingHours = .standard, focusCount: Int = 3) {
        self.mode = mode
        self.urgencyHorizon = urgencyHorizon
        self.workingHours = workingHours
        self.focusCount = focusCount
    }

    /// Minutes after midnight that a date-only task is due.
    /// End of the working day when working hours are on, otherwise 23:59.
    public var dateOnlyDueMinute: Int {
        workingHours.isEnabled ? workingHours.endMinute : 23 * 60 + 59
    }

    /// Resolves the moment a task is actually due.
    public func effectiveDue(for task: TaskSnapshot, calendar: Calendar) -> Date? {
        guard let due = task.dueDate else { return nil }
        if task.hasDueTime { return due }
        return calendar.date(byAdding: .minute, value: dateOnlyDueMinute, to: calendar.startOfDay(for: due))
    }

    /// Time left until `due`, in working time when working hours are on. Negative when overdue.
    public func timeRemaining(until due: Date, now: Date, calendar: Calendar) -> TimeInterval {
        if due <= now { return due.timeIntervalSince(now) }
        guard workingHours.isEnabled else { return due.timeIntervalSince(now) }
        return workingHours.workingSeconds(from: now, to: due, calendar: calendar)
    }
}

public struct NotificationSettings: Codable, Hashable, Sendable {
    /// Heads-up lead time for tasks without an estimate.
    public var headsUpLead: TimeInterval
    /// Push alerts that land outside working hours to the next working window.
    public var muteOutsideWorkingHours: Bool

    public init(headsUpLead: TimeInterval = 3600, muteOutsideWorkingHours: Bool = false) {
        self.headsUpLead = headsUpLead
        self.muteOutsideWorkingHours = muteOutsideWorkingHours
    }
}
