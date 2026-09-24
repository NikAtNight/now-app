import Foundation

public struct PlannedNotification: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// Start-by time for tasks with an estimate, otherwise a fixed lead before the deadline.
        case headsUp
        case due
        /// Fires when a snooze runs out.
        case snoozeEnded
    }

    public let taskID: UUID
    public let kind: Kind
    public let fireDate: Date

    public var identifier: String { "\(taskID.uuidString).\(kind.rawValue)" }
}

public enum NotificationPlanner {
    /// iOS keeps at most 64 pending local notifications per app. Stay under it.
    public static let defaultLimit = 60

    /// Every future notification the open tasks need, soonest first, capped at `limit`.
    /// Re-run whenever tasks change or the app comes to the foreground so later ones get scheduled.
    public static func plan(
        _ tasks: [TaskSnapshot],
        now: Date,
        ranking: RankingSettings,
        notifications: NotificationSettings,
        calendar: Calendar = .current,
        limit: Int = defaultLimit
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []

        for task in tasks where task.status != .done {
            let snoozedUntil = task.snoozedUntil.flatMap { $0 > now ? $0 : nil }
            var candidates: [(PlannedNotification.Kind, Date)] = []

            if let due = ranking.effectiveDue(for: task, calendar: calendar) {
                let lead = task.estimateMinutes == nil ? notifications.headsUpLead : task.estimate
                if lead > 0 { candidates.append((.headsUp, due.addingTimeInterval(-lead))) }
                candidates.append((.due, due))
            }
            if let snoozedUntil {
                candidates.append((.snoozeEnded, snoozedUntil))
            }

            for (kind, date) in candidates {
                // A snooze silences everything before it ends.
                if let snoozedUntil, kind != .snoozeEnded, date < snoozedUntil { continue }
                var fireDate = date
                if notifications.muteOutsideWorkingHours, ranking.workingHours.isEnabled {
                    fireDate = ranking.workingHours.nextWorkingMoment(atOrAfter: fireDate, calendar: calendar)
                }
                guard fireDate > now else { continue }
                planned.append(PlannedNotification(taskID: task.id, kind: kind, fireDate: fireDate))
            }
        }

        return Array(planned.sorted { ($0.fireDate, $0.identifier) < ($1.fireDate, $1.identifier) }.prefix(limit))
    }
}
