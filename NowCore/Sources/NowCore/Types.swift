import Foundation

public enum Priority: Int, Codable, CaseIterable, Comparable, Sendable {
    case none = 0, low = 1, medium = 2, high = 3

    public static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Divisor applied to slack in balanced mode. Higher priority makes a task feel closer.
    public var weight: Double {
        switch self {
        case .none, .low: 1
        case .medium: 2
        case .high: 4
        }
    }

    /// Reminders-style marks shown before the title.
    public var marks: String {
        switch self {
        case .none: ""
        case .low: "!"
        case .medium: "!!"
        case .high: "!!!"
        }
    }

    public var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

public enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo, inProgress, done

    public var label: String {
        switch self {
        case .todo: "To Do"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }
}

public enum RankingMode: String, Codable, CaseIterable, Sendable {
    case deadlineFirst, priorityFirst, balanced

    public var label: String {
        switch self {
        case .deadlineFirst: "Deadline First"
        case .priorityFirst: "Priority First"
        case .balanced: "Balanced"
        }
    }

    public var summary: String {
        switch self {
        case .deadlineFirst: "Closest deadline wins. Priority breaks ties."
        case .priorityFirst: "Highest priority wins. Deadline breaks ties."
        case .balanced: "Time left is weighed against priority, so a high priority task can beat a nearer low priority one."
        }
    }
}

/// Plain value copy of a task. The ranker and planner only ever see these.
public struct TaskSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var priority: Priority
    public var status: TaskStatus
    /// For date-only tasks this is any moment on the due day; see `hasDueTime`.
    public var dueDate: Date?
    public var hasDueTime: Bool
    public var estimateMinutes: Int?
    public var snoozedUntil: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        priority: Priority = .none,
        status: TaskStatus = .todo,
        dueDate: Date? = nil,
        hasDueTime: Bool = true,
        estimateMinutes: Int? = nil,
        snoozedUntil: Date? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.id = id
        self.title = title
        self.priority = priority
        self.status = status
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.estimateMinutes = estimateMinutes
        self.snoozedUntil = snoozedUntil
        self.createdAt = createdAt
    }

    public var estimate: TimeInterval { TimeInterval(estimateMinutes ?? 0) * 60 }
}
