import Foundation
import NowCore
import SwiftData

// CloudKit-backed SwiftData rules: every property optional or defaulted,
// relationships optional, no unique constraints. Enums are stored raw so
// #Predicate can filter on them.

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var statusRaw: String = "todo"
    var priorityRaw: Int = 0
    /// For date-only tasks the time part is ignored; see `hasDueTime`.
    var dueDate: Date?
    var hasDueTime: Bool = false
    var estimateMinutes: Int?
    var snoozedUntil: Date?
    var createdAt: Date = Date()
    var completedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \Subtask.parent)
    var subtasks: [Subtask]? = []

    init(title: String, dueDate: Date? = nil, hasDueTime: Bool = false, priority: Priority = .none) {
        self.title = title
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priorityRaw = priority.rawValue
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set {
            statusRaw = newValue.rawValue
            completedAt = newValue == .done ? (completedAt ?? .now) : nil
            if newValue == .done { snoozedUntil = nil }
        }
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var isDone: Bool { status == .done }

    var sortedSubtasks: [Subtask] {
        (subtasks ?? []).sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
    }

    var snapshot: TaskSnapshot {
        TaskSnapshot(
            id: id,
            title: title,
            priority: priority,
            status: status,
            dueDate: dueDate,
            hasDueTime: hasDueTime,
            estimateMinutes: estimateMinutes,
            snoozedUntil: snoozedUntil,
            createdAt: createdAt
        )
    }

    func reschedule(to date: Date) {
        dueDate = date
        hasDueTime = true
        snoozedUntil = nil
    }

    func snooze(until date: Date) {
        snoozedUntil = date
    }
}

@Model
final class Subtask {
    var id: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    var order: Int = 0
    var createdAt: Date = Date()
    var parent: TaskItem?

    init(title: String, order: Int) {
        self.title = title
        self.order = order
    }
}
