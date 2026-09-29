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
    /// For date-only tasks the time part is ignored; see `hasDueTime`. They're stored at local noon
    /// (see `dateOnly`), so the day holds when the device moves to another time zone.
    var dueDate: Date?
    var hasDueTime: Bool = false
    var estimateMinutes: Int?
    var snoozedUntil: Date?
    var createdAt: Date = Date()
    var completedAt: Date?
    /// Set when the task is moved to Recently Deleted. Purged for good after 30 days.
    var deletedAt: Date?
    /// A `Recurrence` raw value. Completing the task creates the next occurrence.
    var recurrenceRaw: String?
    /// True once completing this occurrence has created the next one, so it only happens once.
    var spawnedNext: Bool = false
    /// The series' first due date. Monthly and yearly repeats count from it so short months don't drift.
    var recurrenceAnchor: Date?
    /// Shared by every occurrence of a repeating series. A series has at most one open occurrence,
    /// so when two devices each create the next one offline, `Refresher` keeps one per series.
    var seriesID: UUID?
    /// When the task's timer was started. The timer runs for `estimateMinutes`.
    var timerStartedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \Subtask.parent)
    var subtasks: [Subtask]? = []

    init(title: String, dueDate: Date? = nil, hasDueTime: Bool = false, priority: Priority = .none) {
        self.title = title
        self.dueDate = dueDate
        self.hasDueTime = hasDueTime
        self.priorityRaw = priority.rawValue
    }

    /// Every completion path (circle, swipe, pickers, notification and widget actions) goes through
    /// here, so the side effects of finishing a task live in one place.
    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set {
            let wasDone = status == .done
            statusRaw = newValue.rawValue
            completedAt = newValue == .done ? (completedAt ?? .now) : nil
            if newValue == .done {
                snoozedUntil = nil
                timerStartedAt = nil
                if !wasDone { spawnNextOccurrence() }
            } else if wasDone, spawnedNext {
                // The series already moved on to the next occurrence, so a reopened one is a one-off.
                recurrenceRaw = nil
                seriesID = nil
            }
        }
    }

    var recurrence: Recurrence? {
        get { recurrenceRaw.flatMap(Recurrence.init(rawValue:)) }
        set {
            recurrenceRaw = newValue?.rawValue
            // A repeating task needs a date to repeat from.
            if newValue != nil, dueDate == nil { dueDate = Self.dateOnly(.now) }
            recurrenceAnchor = newValue == nil ? nil : dueDate
            // A fresh series, not the task's own ID: a reopened first occurrence had that ID as its
            // series, which its spawned next occurrence still carries. Reusing it would make the two
            // look like duplicates, and `Refresher.tidy` would trash this one.
            seriesID = newValue == nil ? nil : (seriesID ?? UUID())
            // A reopened occurrence that already spawned its next one lost its repeat. Given a new
            // one, completing it again should carry the series on.
            if newValue != nil, !isDone { spawnedNext = false }
        }
    }

    var isTrashed: Bool { deletedAt != nil }

    var isTimerRunning: Bool { timerStartedAt != nil }

    /// When the running timer finishes: the start plus the estimate.
    var timerEnd: Date? {
        guard let timerStartedAt, let estimateMinutes else { return nil }
        return timerStartedAt.addingTimeInterval(TimeInterval(estimateMinutes * 60))
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

    /// Removes the date, and with it any repeat, since a series needs a date to repeat from.
    func clearDueDate() {
        dueDate = nil
        hasDueTime = false
        recurrenceRaw = nil
        recurrenceAnchor = nil
        seriesID = nil
    }

    /// Every hand edit of the date goes through here. A repeating task's series then counts from
    /// the new date, so a monthly repeat moved to the 15th keeps landing on the 15th.
    func setDueDate(_ date: Date) {
        dueDate = date
        if recurrenceRaw != nil { recurrenceAnchor = date }
    }

    func reschedule(to date: Date) {
        setDueDate(date)
        hasDueTime = true
        snoozedUntil = nil
    }

    /// Moves the due date to `day`, keeping the time of day if there is one.
    func setDueDay(_ day: Date, calendar: Calendar = .current) {
        if hasDueTime, let dueDate {
            let time = calendar.dateComponents([.hour, .minute], from: dueDate)
            let start = calendar.startOfDay(for: day)
            setDueDate(calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: start) ?? start)
        } else {
            setDueDate(Self.dateOnly(day, calendar: calendar))
        }
        snoozedUntil = nil
    }

    /// How a date-only task stores its day: local noon. Midnight would read as the day before
    /// after moving west (Oct 1 00:00 in Toronto is Sep 30 21:00 in Vancouver); noon holds the day
    /// for any shift under 12 hours.
    static func dateOnly(_ day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? calendar.startOfDay(for: day)
    }

    /// The timer runs for the estimate, so clearing the estimate stops it. Otherwise a stale start
    /// would come back as "Time's up" whenever an estimate is set again.
    func setEstimate(_ minutes: Int?) {
        estimateMinutes = minutes
        if minutes == nil { stopTimer() }
    }

    func snooze(until date: Date) {
        snoozedUntil = date
    }

    func startTimer(now: Date = .now) {
        guard estimateMinutes != nil else { return }
        timerStartedAt = now
        saveNow()
    }

    func stopTimer() {
        timerStartedAt = nil
        saveNow()
    }

    /// The Mac menu bar countdown, the Live Activity, and the time's-up alert follow saves, and
    /// autosave can take 20 seconds. A timer should show up as soon as it starts.
    private func saveNow() {
        try? modelContext?.save()
    }

    func moveToTrash() {
        deletedAt = .now
        timerStartedAt = nil
    }

    func restore() {
        deletedAt = nil
        // A series keeps one open occurrence (see `Refresher`). If another is already open, this one
        // comes back as a one-off; otherwise it'd be trashed again as a duplicate.
        guard let seriesID, let context = modelContext else { return }
        let id = self.id
        let others = FetchDescriptor<TaskItem>(predicate: #Predicate { task in
            task.seriesID == seriesID && task.id != id && task.deletedAt == nil && task.statusRaw != "done"
        })
        if ((try? context.fetchCount(others)) ?? 0) > 0 {
            self.seriesID = nil
            recurrenceRaw = nil
            recurrenceAnchor = nil
        }
    }

    private func spawnNextOccurrence() {
        // A trashed task (say, completed from a stale notification) must not restart its series.
        guard let recurrence, let dueDate, !spawnedNext, deletedAt == nil, let context = modelContext else { return }
        let anchor = recurrenceAnchor ?? dueDate
        let nextDue = recurrence.nextOccurrence(currentDue: dueDate, anchor: anchor, now: .now, calendar: .current)
        let next = TaskItem(title: title, dueDate: nextDue, hasDueTime: hasDueTime, priority: priority)
        next.notes = notes
        next.estimateMinutes = estimateMinutes
        next.recurrenceRaw = recurrenceRaw
        next.recurrenceAnchor = anchor
        next.seriesID = seriesID ?? id
        context.insert(next)
        for subtask in sortedSubtasks {
            let copy = Subtask(title: subtask.title, order: subtask.order)
            context.insert(copy)
            copy.parent = next
        }
        spawnedNext = true
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

extension TaskItem {
    /// Not done and not in Recently Deleted: the tasks that get ranked.
    static let openPredicate = #Predicate<TaskItem> { task in
        task.deletedAt == nil && task.statusRaw != "done"
    }

    static let completedPredicate = #Predicate<TaskItem> { task in
        task.deletedAt == nil && task.statusRaw == "done"
    }

    static let trashedPredicate = #Predicate<TaskItem> { task in
        task.deletedAt != nil
    }
}
