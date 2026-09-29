import Foundation
import NowCore
import SwiftData
import UserNotifications

/// Schedules local notifications from `NotificationPlanner` and handles their actions.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private enum Action {
        static let complete = "COMPLETE"
        static let snooze15 = "SNOOZE_15"
        static let snooze60 = "SNOOZE_60"
        static let reschedule = "RESCHEDULE"
    }

    private static let category = "TASK"
    private nonisolated static let taskIDKey = "taskID"

    private let center = UNUserNotificationCenter.current()
    private var container: ModelContainer?

    /// Call once at launch, before the app finishes launching, so taps on
    /// notifications that cold-start the app still reach the delegate.
    func configure(container: ModelContainer) {
        self.container = container
        center.delegate = self
        let actions = [
            UNNotificationAction(identifier: Action.complete, title: "Done"),
            UNNotificationAction(identifier: Action.snooze15, title: "Snooze 15 Minutes"),
            UNNotificationAction(identifier: Action.snooze60, title: "Snooze 1 Hour"),
            UNNotificationAction(identifier: Action.reschedule, title: "Reschedule…", options: [.foreground]),
        ]
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: actions, intentIdentifiers: [])])
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// A running task timer that should alert when it ends.
    struct TimerAlert {
        let taskID: UUID
        let title: String
        let start: Date
        let end: Date
    }

    /// Replaces every pending notification with a fresh plan. Only `Refresher` calls this, one run at a time.
    func sync(tasks: [TaskSnapshot], timers: [TimerAlert], settings: AppSettings, now: Date = .now) async {
        center.removeAllPendingNotificationRequests()
        let overdue = Ranker.rank(tasks, now: now, settings: settings.ranking).overdueCount

        guard settings.notifyOnThisDevice else {
            try? await center.setBadgeCount(0)
            return
        }
        try? await center.setBadgeCount(overdue)

        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let plan = NotificationPlanner.plan(tasks, now: now, ranking: settings.ranking, notifications: settings.notifications)

        for item in plan {
            if Task.isCancelled { return }
            guard let task = byID[item.taskID] else { continue }
            let interval = item.fireDate.timeIntervalSince(now)
            guard interval >= 1 else { continue }

            let content = UNMutableNotificationContent()
            content.userInfo = [Self.taskIDKey: task.id.uuidString]
            if item.kind == .due || item.kind == .overdueBadge {
                // The app may be suspended when this fires, so the alert brings the badge up to date itself.
                content.badge = NSNumber(value: Ranker.rank(tasks, now: item.fireDate, settings: settings.ranking).overdueCount)
            }
            // A badge update stays silent: no title, body, or sound means nothing is shown.
            if item.kind != .overdueBadge {
                content.title = task.priority == .none ? task.title : "\(task.priority.marks) \(task.title)"
                content.body = body(for: item, task: task, settings: settings.ranking)
                content.sound = .default
                content.categoryIdentifier = Self.category
            }

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
        }

        for timer in timers {
            if Task.isCancelled { return }
            let interval = timer.end.timeIntervalSince(now)
            guard interval >= 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Time's up: \(timer.title)"
            content.body = "Mark it done, or keep going."
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.userInfo = [Self.taskIDKey: timer.taskID.uuidString]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "timer-\(timer.taskID.uuidString)", content: content, trigger: trigger))
        }
    }

    private func body(for item: PlannedNotification, task: TaskSnapshot, settings: RankingSettings) -> String {
        let due = settings.effectiveDue(for: task, calendar: .current)
        let dueTime = due.map { DueLabel.timeText($0) } ?? ""
        switch item.kind {
        case .headsUp:
            if let minutes = task.estimateMinutes {
                return "Start now. It takes about \(DueLabel.duration(TimeInterval(minutes * 60))) and it's due at \(dueTime)."
            }
            return "Due at \(dueTime)."
        case .due:
            guard !task.hasDueTime, let day = task.dueDate else { return "Due now." }
            // Date-only tasks alert in the morning of their day (see `NotificationPlanner`), unless
            // "Hold Alerts Until Working Hours" pushed it to a later day.
            if Calendar.current.isDate(item.fireDate, inSameDayAs: day) { return "Due today." }
            return "Overdue. It was due \(DueLabel.text(for: day, hasTime: false, now: item.fireDate).lowercased())."
        case .overdueBadge:
            return ""
        case .snoozeEnded:
            return due.map { "Back from snooze. Due \(DueLabel.text(for: $0, hasTime: task.hasDueTime, now: .now))." } ?? "Back from snooze."
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Badge-only updates have no title and shouldn't show an empty banner.
        notification.request.content.title.isEmpty ? [.badge] : [.banner, .list, .sound, .badge]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let taskID = (response.notification.request.content.userInfo[Self.taskIDKey] as? String).flatMap(UUID.init(uuidString:))
        guard let taskID else { return }
        await handle(action: action, taskID: taskID)
    }

    private func handle(action: String, taskID: UUID) async {
        guard let container else { return }
        let context = container.mainContext
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == taskID })
        descriptor.fetchLimit = 1
        // An already-delivered alert can outlive its task; don't act on a deleted one.
        guard let task = try? context.fetch(descriptor).first, !task.isTrashed else { return }

        switch action {
        case Action.complete: task.status = .done
        case Action.snooze15: task.snooze(until: .now.addingTimeInterval(15 * 60))
        case Action.snooze60: task.snooze(until: .now.addingTimeInterval(3600))
        default: return // Tapping or "Reschedule…" just opens the app, where overdue tasks offer reschedule.
        }
        try? context.save()
        // The app may be in the background and about to suspend, so don't wait for the debounce.
        await Refresher.shared.refreshNow()
    }
}
