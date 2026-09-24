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
    private static let taskIDKey = "taskID"

    private let center = UNUserNotificationCenter.current()
    private var container: ModelContainer?
    private var settings: AppSettings?

    /// Call once at launch, before the app finishes launching, so taps on
    /// notifications that cold-start the app still reach the delegate.
    func configure(container: ModelContainer, settings: AppSettings) {
        self.container = container
        self.settings = settings
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

    /// Replaces every pending notification with a fresh plan. Cheap enough to run on each change.
    func sync(tasks: [TaskSnapshot], settings: AppSettings, now: Date = .now) async {
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
            content.title = task.priority == .none ? task.title : "\(task.priority.marks) \(task.title)"
            content.body = body(for: item, task: task, settings: settings.ranking)
            content.sound = .default
            content.categoryIdentifier = Self.category
            content.userInfo = [Self.taskIDKey: task.id.uuidString]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: item.identifier, content: content, trigger: trigger))
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
            return "Due now."
        case .snoozeEnded:
            return due.map { "Back from snooze. Due \(DueLabel.text(for: $0, hasTime: task.hasDueTime, now: .now))." } ?? "Back from snooze."
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
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
        guard let task = try? context.fetch(descriptor).first else { return }

        switch action {
        case Action.complete: task.status = .done
        case Action.snooze15: task.snooze(until: .now.addingTimeInterval(15 * 60))
        case Action.snooze60: task.snooze(until: .now.addingTimeInterval(3600))
        default: return // Tapping or "Reschedule…" just opens the app, where overdue tasks offer reschedule.
        }
        try? context.save()

        // The app may be running in the background with no views to trigger a resync.
        if let settings, let all = try? context.fetch(FetchDescriptor<TaskItem>()) {
            await sync(tasks: all.map(\.snapshot), settings: settings)
        }
    }
}
