# Podium: scope

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
| Jira features | One level of subtasks. A status (To Do / In Progress) was dropped from the UI on 2026-09-27; tasks are done or not. |
| Full backlog | Hidden by default. "N Hidden · Show" reveals it. |
| Users | Just you. iCloud (CloudKit private database) is the account. |
| Notifications | Heads-up + due alerts, with Done / Snooze / Reschedule actions. |
| Recurring | Presets (Every Day, Weekday, Week, 2 Weeks, Month, Year) plus custom: every N days, weeks, months, or years, and weekly on chosen weekdays. Completing one creates the next occurrence. |
| Distribution | TestFlight first, App Store later. |
| Stack | SwiftUI, SwiftData + CloudKit, iOS 26 / macOS 26 (raised from 18 / 15 on 2026-09-26 for Liquid Glass). |

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
- **Row:** circle, priority icon, title, notes, then a detail line: due date (red when overdue), start-by, snoozed-until, timer time left, repeat, subtask count. Subtasks sit inline under the row. Swipe or right-click for Done / Snooze / Reschedule / Priority / Timer / Delete.
- **Inline editing (like Reminders):** click a title to edit it in place. The active row shows a Notes field and quick controls for date, priority, and estimate (under the row on Mac, above the keyboard on iPhone), plus ⓘ for the full details. The list holds its order while you edit and re-ranks when you're done. Clearing a title and leaving the row deletes the task.
- **Details sheet (ⓘ):** title, notes, date and time toggles, priority, status, estimate, subtasks, unsnooze, delete.
- **Settings:** appearance (System / Light / Dark) and priority icons, both per device, ranking mode, urgency horizon, working hours, notifications.
- **Mac Dock and menu bar:** by default Podium is in the Dock and ⌘Tab only while a window is open, and otherwise lives in the menu bar. Settings > Mac sets Show in Dock (While Window Is Open / Always / Never) and Show in Menu Bar.
- **Mac only:** large accent-colored "Now" list title in the content like Reminders, no toolbar title. Menu bar extra with the focus list and quick add. ⌘N focuses New Task.
- **Look:** neutral, like Apple's own apps (Nikhil found the tinted glass too colorful, 2026-09-27). On Mac the window uses the details popover's material, pinned active so it doesn't dim when the popover opens, and rows are rounded like the popover's form rows. On iPhone it's the grouped background with grouped cells. The toolbar, buttons, and keyboard bar stay Liquid Glass. The row being edited gets a light accent fill. System colors and accent throughout, so light and dark mode and the Mac accent setting apply. Requires iOS 26 / macOS 26.
- **Priority icons:** Settings > Priority Icons picks Bars (signal bars, default), Arrows (down / equals / up), or Marks (`!!!`). Low is blue, Medium orange, High red.
- **Name and icon:** the app is Podium (after "Now", then briefly "Rally"). The icon is a white waving swallowtail pennant on a gold pole (first place) over a midnight-navy tile, with no letter. It's drawn by `scripts/app-icon.swift`.

## Notifications

Planned by `NotificationPlanner` in NowCore, scheduled locally. Heads-up fires at start-by (or a lead time before the due time, default 1h). Due fires at the deadline. A task with a date but no time gets one alert on its day at 9:00 (the start of working hours when they're on), like Reminders' all-day alerts, not at 23:59. A snooze silences everything until it ends, then fires once. iOS allows 64 pending notifications, so the app schedules the nearest 60 and re-plans on every change, when it comes to the foreground, from an iPhone background refresh, and every 15 minutes on Mac (`Refresher`). The app badge shows the overdue count, and each due alert carries the count for its time, so the badge is right even while the app is suspended. "Notify on This Device" is per device, so you can avoid duplicate alerts on Mac and iPhone.

## Added after v1 scoping (2026-09-27)

- **Recurring tasks:** Repeat in the details sheet and the inline date menu. Completing a repeating task keeps it in Completed and creates the next occurrence (`Recurrence.nextDue` in NowCore). Missed occurrences are skipped, so it's never born overdue. Monthly and yearly stay anchored to the original day (Jan 31, Feb 28, Mar 31). Reopening an occurrence after the next one exists turns it into a one-off.
- **Timer:** tasks with an estimate can run a timer, started from the Timer chip while editing, the details, right-click, or swipe. While it runs, a ring fills around the task's circle and the detail line shows "12m left" (then "Time's up"). The Mac menu bar shows the minutes left, and the iPhone shows a Live Activity with a Done button. A notification fires when time's up.
- **History:** a toolbar button opens Completed (by day, tap the circle to reopen) and Recently Deleted. Deleting moves a task there. It can be restored for 30 days, then it's purged.
- **Widgets:** "Now" widget (small, medium, large, lock screen) with the top tasks, ranked like the app; the circles complete tasks. Medium splits 3/4 Now and 1/4 Upcoming (the next dated hidden tasks). Large shows Now above and up to 6 Upcoming below, also completable. Clicking elsewhere opens the app. On iPhone and Mac. The store lives in the App Group so the widget can read it.
- **Quick add on Mac:** a global shortcut (default ⌃⌥Space, set in Settings) opens a floating glass bar. Return adds the task.
- **Background refresh:** the iPhone re-plans notifications from a background refresh task, and the Mac every 15 minutes while it runs, so alerts past the 60-notification limit still get scheduled.

## Not in v1

Calendar integration, sharing, Jira import, Apple Watch, attachments, subtask deadlines.

## Next

- Siri / Shortcuts through App Intents.
- Cross-device notification dedupe instead of the per-device toggle.
- Keyboard navigation on Mac.
- Natural-language dates in the title ("call bob tmrw 3pm"). Nikhil isn't set on this one.
