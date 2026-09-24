# Now: scope

A todo app for one person that shows only the 3 things you should do next, ranked by deadline and priority. Everything else stays hidden until it matters. Native iPhone and Mac apps, synced through iCloud. The screens follow Apple Reminders: one plain list, a hollow circle per task, and a details sheet.

## Decisions

| Topic | Decision |
|---|---|
| Visible tasks | Top 3. Overdue tasks are always shown, even if that makes more than 3. |
| Estimate | Optional. When set, urgency and the heads-up alert use start-by time (due minus estimate). |
| Ranking | User picks Deadline First, Priority First, or Balanced in Settings. |
| Undated tasks | Allowed. They only fill empty slots once nothing urgent is waiting. |
| Working hours | Optional setting. When on, time left counts only working hours. |
| Overdue | Pinned at the top in red, with an inline Reschedule menu. |
| Calendar | None. Dates and times work like Reminders. |
| Jira features | Status (To Do / In Progress / Done) and one level of subtasks. |
| Full backlog | Hidden by default. "N Hidden · Show" reveals it. |
| Users | Just you. iCloud (CloudKit private database) is the account. |
| Notifications | Heads-up + due alerts, with Done / Snooze / Reschedule actions. |
| Recurring | Not in v1. |
| Distribution | TestFlight first, App Store later. |
| Stack | SwiftUI, SwiftData + CloudKit, iOS 18 / macOS 15. |

## Ranking

Pure function in `NowCore/Sources/NowCore/Ranker.swift`. Done tasks are ignored. The rest go into tiers that never mix:

1. **Overdue:** priority, then longest overdue.
2. **Urgent** (slack under the horizon, default 24h). Slack is `due - now - estimate`.
   - Deadline First: slack, then priority.
   - Priority First: priority, then slack.
   - Balanced: tasks past their start-by time first, then `slack / weight` (High 4, Medium 2, Low/None 1).
3. **Later:** priority, then due date, with undated tasks last.
4. **Snoozed:** hidden until the snooze ends. A snoozed task that goes overdue comes back as overdue.

Date-only tasks are due at 23:59, or at the end of the workday when working hours are on.

## Screens

- **List (both platforms):** "N Hidden · Show" line, the focus rows, a "Just Added" section for new undated tasks, a "Later" section when shown, the "New Task" row, and "N Completed · Clear · Show" at the bottom.
- **Row:** circle, priority marks (`!!!`), title, notes, then a detail line: due date (red when overdue), start-by, snoozed-until, In Progress, subtask count. Subtasks sit inline under the row. Swipe or right-click for Done / Snooze / Reschedule / Status / Priority / Delete.
- **Details sheet:** title, notes, date and time toggles, priority, status, estimate, subtasks, unsnooze, delete.
- **Settings:** ranking mode, urgency horizon, working hours, notifications.
- **Mac only:** menu bar extra with the focus list and quick add. ⌘N focuses New Task.

## Notifications

Planned by `NotificationPlanner` in NowCore, scheduled locally. Heads-up fires at start-by (or a lead time before the due time, default 1h). Due fires at the deadline. A snooze silences everything until it ends, then fires once. iOS allows 64 pending notifications, so the app schedules the nearest 60 and re-plans on every change and every time it comes to the foreground. The app badge shows the overdue count. "Notify on This Device" is per device, so you can avoid duplicate alerts on Mac and iPhone.

## Not in v1

Calendar integration, recurring tasks, sharing, Jira import, Apple Watch, attachments, subtask deadlines.

## Next (v1.1)

- Widgets (home and lock screen) showing the focus list.
- Natural-language dates in the title ("call bob tmrw 3pm").
- Siri / Shortcuts through App Intents.
- Cross-device notification dedupe instead of the per-device toggle.
- Background refresh so pending notifications get re-planned without opening the app.
