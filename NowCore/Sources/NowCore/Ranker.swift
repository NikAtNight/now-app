import Foundation

public enum Tier: Int, Comparable, Sendable {
    /// Past the deadline. Always pinned at the top.
    case overdue
    /// Slack is inside the urgency horizon (or the start-by time has passed).
    case urgent
    /// Dated tasks beyond the horizon, and undated tasks.
    case later
    /// Hidden until `snoozedUntil`.
    case snoozed

    public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct RankedTask: Identifiable, Equatable, Sendable {
    public let task: TaskSnapshot
    public let tier: Tier
    public let effectiveDue: Date?
    /// `effectiveDue - estimate`. Only set when the task has both.
    public let startBy: Date?
    /// Time left before you'd have to start, in working time when working hours are on.
    public let slack: TimeInterval?

    public var id: UUID { task.id }
}

public struct Ranking: Equatable, Sendable {
    /// What the main screen shows: every overdue task, then the top of the list up to `focusCount`.
    public let focus: [RankedTask]
    /// Everything else that's still open, in rank order. Snoozed tasks come last.
    public let hidden: [RankedTask]

    public var overdueCount: Int { focus.filter { $0.tier == .overdue }.count }
    /// Urgent tasks that didn't fit in the focus list.
    public var urgentOverflow: Int { hidden.filter { $0.tier == .urgent }.count }
    public var all: [RankedTask] { focus + hidden }
}

public enum Ranker {
    public static func rank(_ tasks: [TaskSnapshot], now: Date, settings: RankingSettings, calendar: Calendar = .current) -> Ranking {
        let ranked = tasks
            .filter { $0.status != .done }
            .map { classify($0, now: now, settings: settings, calendar: calendar) }
            .sorted { precedes($0, $1, mode: settings.mode) }

        var focus: [RankedTask] = []
        var hidden: [RankedTask] = []
        for item in ranked {
            let pinned = item.tier == .overdue
            let hasRoom = focus.count < settings.focusCount && item.tier != .snoozed
            if pinned || hasRoom { focus.append(item) } else { hidden.append(item) }
        }
        return Ranking(focus: focus, hidden: hidden)
    }

    static func classify(_ task: TaskSnapshot, now: Date, settings: RankingSettings, calendar: Calendar) -> RankedTask {
        let due = settings.effectiveDue(for: task, calendar: calendar)
        let startBy = due.flatMap { task.estimateMinutes == nil ? nil : $0.addingTimeInterval(-task.estimate) }
        let slack = due.map { settings.timeRemaining(until: $0, now: now, calendar: calendar) - task.estimate }

        let tier: Tier
        if let due, due <= now {
            // Overdue beats snoozed: a missed deadline always needs a decision.
            tier = .overdue
        } else if let snoozedUntil = task.snoozedUntil, snoozedUntil > now {
            tier = .snoozed
        } else if let slack, slack < settings.urgencyHorizon {
            tier = .urgent
        } else {
            tier = .later
        }
        return RankedTask(task: task, tier: tier, effectiveDue: due, startBy: startBy, slack: slack)
    }

    static func precedes(_ a: RankedTask, _ b: RankedTask, mode: RankingMode) -> Bool {
        if a.tier != b.tier { return a.tier < b.tier }
        let keysA = sortKeys(a, mode: mode)
        let keysB = sortKeys(b, mode: mode)
        for (x, y) in zip(keysA, keysB) where x != y { return x < y }
        if a.task.createdAt != b.task.createdAt { return a.task.createdAt < b.task.createdAt }
        return a.task.id.uuidString < b.task.id.uuidString
    }

    /// Ascending sort keys for a task within its tier.
    private static func sortKeys(_ item: RankedTask, mode: RankingMode) -> [Double] {
        let priority = -Double(item.task.priority.rawValue)
        let due = item.effectiveDue?.timeIntervalSinceReferenceDate ?? .infinity
        let slack = item.slack ?? .infinity

        switch item.tier {
        case .overdue:
            // Highest priority first, then the one that's been overdue longest.
            return [priority, due]
        case .urgent:
            switch mode {
            case .deadlineFirst:
                return [slack, priority]
            case .priorityFirst:
                return [priority, slack]
            case .balanced:
                // Past the start-by time: no amount of priority makes it less late.
                if slack <= 0 { return [0, slack, priority] }
                return [1, slack / item.task.priority.weight, priority]
            }
        case .later:
            return [priority, due]
        case .snoozed:
            return [item.task.snoozedUntil?.timeIntervalSinceReferenceDate ?? 0, priority]
        }
    }
}
