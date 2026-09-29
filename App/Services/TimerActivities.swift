#if os(iOS)
import ActivityKit
import Foundation

/// Keeps one Live Activity per running task timer: starts missing ones and ends stale ones.
enum TimerActivities {
    static func reconcile(with timers: [NotificationService.TimerAlert]) async {
        let running = Activity<TaskTimerAttributes>.activities
        for activity in running {
            let attributes = activity.attributes
            let stillRunning = timers.contains { $0.taskID == attributes.taskID && $0.end == attributes.end }
            if !stillRunning || attributes.end <= .now {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for timer in timers where timer.end > .now {
            let exists = running.contains { $0.attributes.taskID == timer.taskID && $0.attributes.end == timer.end }
            guard !exists else { continue }
            let attributes = TaskTimerAttributes(taskID: timer.taskID, title: timer.title, start: timer.start, end: timer.end)
            // Requests only succeed while the app is in the foreground, which is when timers are started.
            _ = try? Activity.request(attributes: attributes, content: .init(state: .init(), staleDate: timer.end))
        }
    }
}
#endif
