# Now: Session Handoff - 2026-09-24

**Purpose:** record of the first build session for "Now", a single-column deadline todo app for iPhone and Mac. Written for the next agent, who has no session context. Everything here can be checked against the repo.

The spec is [`SCOPE.md`](../SCOPE.md). It records Nikhil's answers to the scoping questions (2026-09-24 chat) and supersedes nothing. This is the first handoff.

**Branch state:** `main`, one initial commit, pushed to `github.com/NikAtNight/now-app` (public).

**Validation state at handoff:**

| Gate | State |
|---|---|
| `NowCore` unit tests (`NowCore/test.sh`) | PASS, 40 tests in 5 suites |
| `NowCore` build (`swift build`) | PASS |
| iOS app build | BLOCKED: Xcode not installed, only Command Line Tools |
| macOS app build | BLOCKED: same |
| Running the app / screenshots | NOT RUN: needs a build first |
| CloudKit sync across devices | NOT RUN: needs an Apple Developer team and the container |
| Independent review of `App/` (gpt-5.5, read-only) | Done. 1 finding (optional `@Query` sort key), fixed |

Local setup facts:
- The Command Line Tools can't expand SwiftData macros (`@Model`, `@Query`). That's why `App/` has never been compiled. Everything in `App/` is unverified until Xcode is installed.
- Swift Testing under CLT only works with extra flags and the Foundation cross-import disabled. `NowCore/test.sh` handles that and falls back to plain `swift test` when Xcode is selected.
- XcodeGen is not installed. Installing it (`brew install xcodegen`) is a global change, so ask Nikhil first.

---

## Change 1: `NowCore` package (ranking, scheduling, dates)

**Why.** Nikhil wants to see only the few tasks that need doing now, ordered by deadline or priority (2026-09-24 chat). Keeping this as pure, clock-injected logic makes it testable without the UI.

**What.**
- `Types.swift`: `Priority` (none/low/medium/high, weights 1/1/2/4, Reminders-style `!` marks), `TaskStatus` (todo/inProgress/done), `RankingMode`, and `TaskSnapshot`, the value type the logic works on.
- `WorkingHours.swift`: working seconds between two dates, the next working moment, and handling for daylight-saving days.
- `Settings.swift`: `RankingSettings` (mode, urgency horizon with a 24h default, working hours, focus count of 3). Date-only tasks resolve to 23:59, or to the end of the workday when working hours are on. Also `NotificationSettings`.
- `Ranker.swift`: tiers are overdue, then urgent, then later, then snoozed. Overdue is always shown, even past 3 tasks, and it outranks snooze. The mode only changes ordering inside the urgent tier. Balanced mode puts tasks past their start-by time first, then sorts by `slack / weight`. Ties are broken by creation date, then id, so the order is deterministic.
- `NotificationPlanner.swift`: heads-up alerts fire at start-by if there's an estimate, otherwise at a lead time before the deadline. Due alerts fire at the deadline. A snooze suppresses earlier alerts and adds a "snooze ended" alert. There's an optional hold until working hours. Output is capped at 60, because iOS allows at most 64 pending notifications.
- `QuickDates.swift`: presets for reschedule and snooze. "This Evening" is hidden after 18:00. "Next Week" means next Monday.
- `DueLabel.swift`: Reminders-style date labels ("Today, 10:00", "Tomorrow", "2026-09-27, 18:00") and duration labels.
- Tests in `NowCore/Tests/NowCoreTests/` use a fixed UTC calendar. "Now" in the tests is Thursday 2026-09-24 10:00.

## Change 2: SwiftUI app (`App/`), shared by the iOS and macOS targets

**Why.** Nikhil asked for native iPhone and Mac apps and said the screens "can be as simple as Apple Reminders" (2026-09-24, with a screenshot of Reminders).

**What.**
- `Models/TaskItem.swift`: the `TaskItem` and `Subtask` SwiftData models, written to follow CloudKit's rules (every property defaulted or optional, no unique constraints). Status and priority are stored as raw values so `#Predicate` can filter on them.
- `Services/AppSettings.swift`: `@Observable` settings saved to UserDefaults and mirrored to iCloud key-value storage. "Notify on This Device" is deliberately stored only on the device.
- `Services/NotificationService.swift`: schedules alerts from `NotificationPlanner`. Alert actions are Done, Snooze 15m, Snooze 1h, and Reschedule (which opens the app). The app badge shows the overdue count. After handling an action it re-plans, because the app may be running in the background with no views open.
- `NowApp.swift`: sets up the model container (`cloudKitDatabase: .automatic`) and configures notifications at launch. On Mac it adds a Settings window, a menu bar item, and ⌘N. `RootView` re-plans notifications whenever tasks or settings change, and whenever the app comes back to the foreground.
- `Views/TaskListView.swift`: the single screen. From top to bottom:
  - A "N Hidden · Show" line, with a red "N more urgent" nudge when urgent tasks are hidden.
  - The focus rows.
  - "Just Added", which keeps new undated tasks visible so they don't vanish into the hidden list.
  - "Later", shown on demand.
  - The New Task row.
  - "N Completed · Clear · Show".

  The list re-ranks every minute.
- `Views/TaskRow.swift`: each row shows a completion circle that fills for 450ms before the task leaves, priority marks, the title, notes, and a detail line (due date in red when overdue, start-by time, snoozed-until, In Progress, subtask count). Subtasks show inline. Overdue rows get a red Reschedule menu. There are swipe actions and a context menu.
- `Views/TaskDetailView.swift`: Reminders-style details sheet with date and time toggles, priority, status, estimate, subtasks, unsnooze, and delete.
- `Views/SettingsView.swift`: ranking mode, urgency horizon, working hours (start, end, weekdays), and notifications.
- `Views/MenuBarView.swift` (Mac only): the focus list plus a quick add field.

## Change 3: Project config

- `project.yml`: XcodeGen spec with `Now-iOS` and `Now-macOS` targets and `NowCore` as a local package. It uses Swift 5 language mode on purpose, to keep the risk of first-compile concurrency errors low.
- `Config/`: entitlements (CloudKit container `iCloud.com.nikhilkapadia.now`, iCloud key-value storage, push notifications, and the Mac app sandbox) and an iOS Info.plist addition for remote-notification background mode.
- `Resources/`: asset catalog (accent color set, app icon empty) and the privacy manifest (UserDefaults, reason CA92.1).

---

## Remaining work

In order:

1. **Get it compiling.** Install Xcode. Ask before running `brew install xcodegen`. Then run `xcodegen generate`, and build both schemes. Expect small compile fixes in `App/`.
2. **Run and look.** Test in the iOS Simulator and on the Mac. Compare against Reminders, since that's the design reference. Adjust spacing, fonts, and how the "N Hidden" line reads.
3. **Signing and iCloud.** Needs Nikhil's Apple Developer team ID in `project.yml` (`DEVELOPMENT_TEAM`). Confirm the bundle ID and container. Test sync between two devices.
4. **App icon.** The icon set is empty, and TestFlight requires one.
5. **TestFlight.** Set up App Store Connect, archive, and upload. Only do this when Nikhil asks.

Known gaps, deliberately out of v1 (see SCOPE.md "Next"):
- There's no background refresh, so notifications past the nearest 60 only get planned when the app opens.
- Duplicate alerts on Mac and iPhone are avoided with a per-device toggle, not real cancellation across devices.
- No widgets, no natural-language dates, no Siri/Shortcuts, no recurring tasks.

Things to check once it builds:
- `@Observable` with `didSet` in `AppSettings`: confirm settings save and survive a relaunch.
- The `CompletionCircle` delay: if the list re-ranks during those 450ms, confirm the row doesn't flicker.
- `TaskRow` wraps the title and notes in an `onTapGesture` next to borderless buttons. Confirm the circle and the Reschedule menu don't also open the details sheet.

## Manual acceptance checklist

Run these on the iPhone simulator and the Mac. There's one user (iCloud account = you).

1. Add 5 tasks due in 1h, 2h, 3h, 4h, and 5h. Only the first 3 show, and the line reads "2 Hidden · 2 more urgent".
2. Add an undated High task. It appears under "Just Added". After relaunch it's hidden until fewer than 3 urgent tasks remain.
3. Set a task's due time 1 minute from now. Within a minute of it passing, the date turns red, the row pins to the top, and a Reschedule menu appears. "Tomorrow Morning" moves it.
4. Switch Settings to Balanced. A High task due in 8h ranks above a Low task due in 3h.
5. Give a task due in 3h an estimate of 4h. It shows "Start now" and ranks first.
6. Turn working hours on (Mon-Fri, 9-5). On a Friday afternoon, a task due Monday 9:30 becomes urgent.
7. Snooze a task for 15 minutes from the swipe or context menu. It moves under "Later" (after Show) marked "Snoozed until…", and comes back 15 minutes later.
8. Notifications: tap Done on a due alert. The task completes without opening the app, and the badge updates.
9. Mac: ⌘N focuses New Task. The menu bar item shows the same 3 tasks and supports quick add.
10. Add subtasks in the details sheet. They show inline with a count like "1/3", and you can tick them off from the list.

## Source context

- The 2026-09-24 chat with Nikhil. The scoping Q&A is summarized in the Decisions table in `SCOPE.md`.
- Reminders screenshot (2026-09-24): single list, hollow circles, grey notes line, red overdue dates, "N Completed • Clear … Show" header.
