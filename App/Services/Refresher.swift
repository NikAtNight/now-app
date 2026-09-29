import Foundation
import NowCore
import SwiftData
import WidgetKit
#if os(iOS)
import BackgroundTasks
#endif

/// Keeps everything derived from the task store in step with it: pending notifications and the
/// badge, widgets, and timer Live Activities on iPhone.
///
/// Every trigger (a save anywhere in the app, a CloudKit import, a settings change, the app coming
/// back, a background refresh, a periodic tick on Mac) funnels into one debounced refresh. Runs are
/// serialized, so an older run can't finish after a newer one and leave stale notifications.
@MainActor
final class Refresher {
    static let shared = Refresher()

    /// Registered in the iOS Info.plist under BGTaskSchedulerPermittedIdentifiers.
    static let backgroundTaskID = "com.talix.now.refresh"

    /// Set once this device has moved old midnight date-only dates to noon.
    private static let noonMigrationKey = "migration.dateOnlyNoon.v1"

    private var container: ModelContainer?
    private var settings: AppSettings?
    private var debounce: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    #if os(macOS)
    private var ticker: Timer?
    #endif

    /// Call once at launch.
    func start(container: ModelContainer, settings: AppSettings) {
        self.container = container
        self.settings = settings

        for name in [ModelContext.didSave, Notification.Name.NSPersistentStoreRemoteChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Refresher.shared.refresh() }
            })
        }
        #if os(macOS)
        // The Mac app keeps running in the menu bar, so re-plan now and then instead of relying on
        // app launches: only the nearest notifications fit in the pending queue.
        ticker = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { Refresher.shared.refresh() }
        }
        #endif

        refresh()
    }

    /// Schedules a refresh shortly, coalescing bursts of changes into one run: each trigger restarts
    /// a single short debounce. Runs themselves queue one after another and are never cancelled,
    /// since a run may already have cleared pending notifications before it re-adds them.
    func refresh() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await enqueueRun()
        }
    }

    /// Refreshes right away, for callers that may be suspended soon (notification actions, background tasks).
    func refreshNow() async {
        debounce?.cancel()
        await enqueueRun()
    }

    private func enqueueRun() async {
        let previous = running
        let task = Task {
            await previous?.value
            await run()
        }
        running = task
        await task.value
    }

    private func run() async {
        guard let container, let settings else { return }
        tidy(container.mainContext)
        let open = (try? container.mainContext.fetch(FetchDescriptor<TaskItem>(predicate: TaskItem.openPredicate))) ?? []
        let timers = open.compactMap { task -> NotificationService.TimerAlert? in
            guard let start = task.timerStartedAt, let end = task.timerEnd else { return nil }
            return NotificationService.TimerAlert(taskID: task.id, title: task.title, start: start, end: end)
        }
        await NotificationService.shared.sync(tasks: open.map(\.snapshot), timers: timers, settings: settings)
        #if os(iOS)
        await TimerActivities.reconcile(with: timers)
        #else
        MenuBarStatus.shared.update(timerEnd: timers.map(\.end).min())
        #endif
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Store upkeep that must happen whatever woke the app: purge expired deletions, move old
    /// date-only dates to noon (once), and keep one open occurrence per repeating series (two
    /// devices completing one offline each create the next). The extra ones go to Recently
    /// Deleted rather than away for good, in case one was edited.
    /// Saves only when something changed, so the save it triggers settles on the next run.
    private func tidy(_ context: ModelContext) {
        var changed = HistoryView.purgeExpired(in: context)
        // Repeating tasks from before series existed get one, so duplicates of them can be caught too.
        let open = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: TaskItem.openPredicate))) ?? []
        // The task's own ID, so every device backfilling the same task agrees on the series.
        for task in open where task.recurrenceRaw != nil && task.seriesID == nil {
            task.seriesID = task.id
            changed = true
        }
        // Date-only tasks used to be stored at midnight, which reads as the day before after moving
        // west. Move them to noon (`TaskItem.dateOnly`), once per device. Running it every time
        // would loop between two devices 12 hours apart, where one's noon is the other's midnight.
        if !UserDefaults.standard.bool(forKey: Self.noonMigrationKey) {
            let calendar = Calendar.current
            func atMidnight(_ date: Date?) -> Date? {
                guard let date, calendar.startOfDay(for: date) == date else { return nil }
                return date
            }
            for task in open where !task.hasDueTime {
                if let due = atMidnight(task.dueDate) {
                    task.dueDate = TaskItem.dateOnly(due)
                    changed = true
                }
                if let anchor = atMidnight(task.recurrenceAnchor) {
                    task.recurrenceAnchor = TaskItem.dateOnly(anchor)
                    changed = true
                }
            }
            UserDefaults.standard.set(true, forKey: Self.noonMigrationKey)
        }
        let occurrences = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { task in
            task.seriesID != nil && task.deletedAt == nil && task.statusRaw != "done"
        }))) ?? []
        for (_, open) in Dictionary(grouping: occurrences, by: \.seriesID) where open.count > 1 {
            // The furthest-along occurrence is the one the series has reached; ties keep the oldest.
            let keep = open.max { a, b in
                let (dueA, dueB) = (a.dueDate ?? .distantPast, b.dueDate ?? .distantPast)
                return dueA != dueB ? dueA < dueB : a.createdAt > b.createdAt
            }
            for task in open where task !== keep {
                task.moveToTrash()
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    #if os(iOS)
    /// Asks iOS to wake the app later to re-plan notifications past the pending-queue limit.
    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
    #endif
}
