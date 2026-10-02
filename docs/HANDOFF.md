# Podium (formerly Now, then Rally): Session Handoff - 2026-09-24

**Purpose:** record of the first build session for "Now", a single-column deadline todo app for iPhone and Mac. Written for the next agent, who has no session context. Everything here can be checked against the repo.

The spec is [`SCOPE.md`](../SCOPE.md). It records Nikhil's answers to the scoping questions (2026-09-24 chat) and supersedes nothing. This is the first handoff.

**Branch state:** `main`. Session 1 was the initial commit. Session 2 (same day) got the app compiling, signed, and running. Its changes are uncommitted in the working tree unless a later commit says otherwise.

**Validation state after session 2:**

| Gate | State |
|---|---|
| `NowCore` unit tests (`NowCore/test.sh`) | PASS, 40 tests in 5 suites |
| iOS app build (simulator and device, signed) | PASS, no warnings in `App/` |
| macOS app build (signed) | PASS, no warnings in `App/` |
| Running on iPhone 17 Pro simulator (iOS 26.5) | PASS for checklist items listed under Change 4 |
| Running on Mac | PASS: launches, ⌘N focuses New Task, quick add works, menu bar item present |
| CloudKit sync | NOT VERIFIED. See Change 4 |
| TestFlight | NOT STARTED |

Local setup facts:
- Xcode and XcodeGen are both installed now. `Now.xcodeproj` is gitignored, so run `xcodegen generate` after pulling.
- Team is `2TG5HP8NSV` (Nikhil's paid team, the `OU` on the signing certs). The `Apple Development` cert's `7W629ZZN3G` is a personal ID, not the team.
- Command-line builds need `-allowProvisioningUpdates`. The first signed build registered the App ID `com.talix.now` and container `iCloud.com.talix.now` on the team.
- Swift Testing under Command Line Tools still needs `NowCore/test.sh`. It runs plain `swift test` when Xcode is selected.

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
- `Config/`: entitlements (CloudKit container `iCloud.com.talix.now`, iCloud key-value storage, push notifications, and the Mac app sandbox) and an iOS Info.plist addition for remote-notification background mode.
- `Resources/`: asset catalog (accent color set, app icon empty) and the privacy manifest (UserDefaults, reason CA92.1).

## Change 4: Compile, sign, run (session 2)

**Why.** Nikhil asked to continue from this handoff and to use bundle ID `com.talix.now` with the existing Apple Developer account (2026-09-24 chat).

**What.**
- Identifiers: `com.talix.now`, `iCloud.com.talix.now`, and the KVS id changed in `project.yml` and both entitlements files. `DEVELOPMENT_TEAM: 2TG5HP8NSV`.
- `App/` compiled on the first try on both platforms. The only change was one Swift 6 warning, fixed by marking `NotificationService.taskIDKey` as `nonisolated`.
- App icon: placeholder, drawn with CoreGraphics. It's a blue gradient with a white ring and a dot. iOS gets a full-bleed 1024 image, Mac gets the inset rounded tile at every size. Replace it before the App Store. It's good enough for TestFlight.

**Checked by hand on the iOS simulator:**
- Quick add: the first 3 undated tasks fill the focus slots, and later ones show under "Just Added".
- Details sheet: turning on Time also turns on Date and defaults to the next full hour. The row then shows "Today, 10:00".
- Tapping the completion circle completes the task without opening the sheet, and "1 Completed · Clear · Show" appears. This settles the open question from session 1.
- Settings (Working Hours on) survive a relaunch, which settles the `@Observable` + `didSet` question.
- The notification permission prompt shows on first launch.

**CloudKit.** On the Mac, SwiftData's CloudKit setup fails with `CKErrorDomain 6` ("Error connecting to CloudKit daemon", underlying `NSCocoaErrorDomain 4099`). The provisioning profile includes the container and taskgated allows the entitlements, so signing is fine. The likely cause is that this Mac isn't signed into iCloud: `defaults read MobileMeAccounts` is empty. The simulator isn't signed in either. The app keeps working with local storage, as designed.

## Change 5: macOS 27 look, light/dark, inline editing (session 3, 2026-09-26)

**Why.** Nikhil asked for the theme to match Apple's macOS 27 standards with light and dark mode, then for Reminders-style inline editing instead of a details dialog (2026-09-26 chat).

**What.**
- Removed the custom `AccentColor` asset. The app follows the system accent (the Mac accent setting, system blue on iOS with its dark variant).
- `Appearance` setting (System / Light / Dark) in `AppSettings`, stored per device. Mac applies it through `NSApp.appearance` so Settings and the menu bar extra follow. iOS uses `preferredColorScheme`.
- Mac list: large accent-colored "Now" title in the content, toolbar title removed, + pushed to the trailing edge with `ToolbarSpacer` (macOS 26+).
- Priority marks use the accent color like Reminders.
- Inline editing: `TaskRow` titles are text fields. The active row (title or notes focused, tracked by `RowFocus`) shows Notes and `InlineEditControls` (date presets, priority, estimate). On iPhone those controls go in the keyboard toolbar. ⓘ opens the existing details sheet, and so does "Custom…" in the date menu. `TaskListView` freezes the ranking while a row is focused, so rows don't jump mid-edit.

**Checked by hand.** Mac in dark and light: inline title editing, priority and date menus, the order holding while editing and re-ranking on Escape, the Settings window. iPhone simulator: tapping a title activates the row, and the keyboard toolbar date menu sets the date in place.

**Not checked.** Menu bar extra in light mode. Swipe actions with the new text-field rows on a real device.

## Change 6: Rally, glass theme, priority icon styles, flag icon (session 3, 2026-09-26)

**Why.** Nikhil didn't like the name "Now" and was deciding between Relay and Rally. Nikhil also asked for a flag app icon in the style of the attached examples (a bold flag with a letter in it), a more glass look, input fields that match the theme instead of dark boxes, and a setting to switch between signal-bar and arrow priority icons (2026-09-26 chat).

**What.**
- Renamed to **Rally**: display and product name, project `Rally.xcodeproj`, targets and schemes `Rally-iOS` / `Rally-macOS`, entitlements `Config/Rally-*.entitlements`, menu bar item. The bundle ID stays `com.talix.now` because the App ID and iCloud container are registered. Code names (`NowCore`, `NowApp`) are unchanged. The list title is still "Now", since it names the list. Change it in `TaskListView` if Nikhil wants otherwise. Relay would also fit the "R" icon.
- Minimum OS raised to iOS 26 / macOS 26 for the Liquid Glass APIs.
- `App/Views/Glass.swift`: `GlassBackdrop` (accent-tinted gradient), `glassCard(highlighted:)` for rows, `EdgeInsets.glassCard`, and an `NSTextView.drawsBackground` override. On Mac, SwiftUI's field editor painted an opaque black box behind the text being edited. The override removes it app-wide.
- Mac window uses `.containerBackground(.thinMaterial, for: .window)`. Lists, the details sheet, and Settings hide their scroll backgrounds and sit on the backdrop. Show, Hide, and Clear buttons, the edit chips, and Reschedule use `.glass`. The menu bar quick add is a glass capsule.
- `App/Views/PriorityIcon.swift`: `PriorityIcon` and `PriorityLabel` render the `PriorityStyle` chosen in Settings (bars / arrows / marks, per device). Used in rows, the priority chip and menus, the context menu, the details sheet, the menu bar, and a preview row in Settings.
- Opening Settings or the details sheet ends inline editing, so the iPhone keyboard bar doesn't float over the sheet.
- App icon: drawn by `scripts/app-icon.swift` (usage in its header). Blue-to-violet glassy tile, white waving swallowtail pennant on a tilted pole with a ball finial, heavy condensed "R" knocked out.

**Checked by hand.** Mac (dark): glass cards, alignment, red Reschedule, tinted active row with glass chips. iPhone simulator (light and dark): glass list, active row, keyboard bar, Settings with the priority preview, Arrows style, no floating bar over Settings.

**Not checked.** The Mac black-box fix while editing. I stopped driving the Mac with synthetic input after a click and keystrokes landed in Nikhil's T3 window. The menu bar extra and the details sheet with the new backdrop, on both platforms.

**Renamed again, same day:** Nikhil picked **Podium** from a list of alternatives. The project, targets, schemes, and entitlements are now `Podium*`. The bundle ID is still `com.talix.now`. Nikhil rejected five new logo concepts (flag-as-P, podium, pennant with star, ribbon P, checkered P) and kept the pennant. From eight color and treatment variations, Nikhil picked "Midnight + gold": a white pennant on a gold pole over a navy tile. Then Nikhil asked to drop the letter, so the icon has no letter.

## Change 7: fixes, widgets, timer, repeat, history, quick add (session 4, 2026-09-27)

**Why.** Nikhil asked to fix the Codex review's C1 (Tomorrow off by a day around DST) and C2 (Mac appearance needed a window), the 23:00 time default, and the details sheet's opaque header and footer on Mac. Nikhil also asked for background refresh and four features: the Mac quick-add hotkey, widgets, a task timer, repeating tasks, and a History / Recently Deleted screen (2026-09-27 chat). Nikhil passed on natural-language dates.

**What.**
- **Date fixes.** Inline "Tomorrow" uses a calendar day. Turning Time on defaults to the next full hour and rolls to tomorrow near midnight. NowCore builds local clock times through `Calendar.date(atMinute:on:)` (new `ClockTime.swift`), which fixes the 23:59 date-only deadline, the working-hours window, and quick-date times on DST days. Invalid working hours (no weekdays, end before start) now count as off instead of making every task urgent. `WorkingHours.isValid` is public.
- **Appearance.** Applied in `AppSettings` (Mac: `NSApplication.shared.appearance`), so it works with no main window.
- **`GlassSheet`** (in `Glass.swift`): on Mac, sheets draw their own title and glass Done button inside the glass, since macOS draws sheet toolbars as opaque bars. Used by Details and History. iOS keeps the navigation bar.
- **Model.** `TaskItem` gains `deletedAt`, `recurrenceRaw`, `recurrenceAnchor`, `seriesID`, `spawnedNext`, and `timerStartedAt`. All are optional or defaulted, so CloudKit is fine. Queries use the shared `openPredicate`, `completedPredicate`, and `trashedPredicate`. Inline `#Predicate`s with several optional comparisons time out the type-checker.
- **Recently Deleted.** Deletes move tasks to trash (`moveToTrash`). `HistoryView` shows Completed by day and Recently Deleted, with restore, delete now, and empty. Items are purged after 30 days.
- **Repeat.** `NowCore/Recurrence.swift` (tested). Completing a repeating task, from any path, runs through the `status` setter, which inserts the next occurrence. Monthly and yearly repeats count from the series anchor. A series keeps at most one open occurrence: `Refresher.tidy()` moves duplicates from offline double-completion to trash, and restoring a duplicate makes it a one-off. Removing the date (`clearDueDate`) clears the repeat.
- **Timer.** For tasks with an estimate. `TimerControl` shows on the row. Other surfaces: the Mac menu bar countdown (`MenuBarLabel`), an iPhone Live Activity (`TaskTimerAttributes`, `TimerActivities`, `Widgets/TimerLiveActivity.swift`), and a "time's up" notification.
- **`Refresher`** (new) replaces RootView's sync. It triggers on saves, CloudKit imports, settings changes, becoming active, an iPhone background refresh (`com.talix.now.refresh`), and a 15-minute Mac tick. Each run re-plans notifications, syncs Live Activities, reloads widgets, and does store upkeep. A single debounce feeds a queue of runs that are never cancelled.
- **Widgets.** Targets `PodiumWidgets-iOS` / `PodiumWidgets-macOS` (`com.talix.now.widgets`) with small, medium, and lock-screen families. Tapping a circle completes the task through `CompleteTaskIntent`, which is a `LiveActivityIntent` on iPhone so it runs in the app. The store moved to the App Group (`SharedStore`). Groups are `group.com.talix.now` on iOS and `2TG5HP8NSV.com.talix.now` on Mac. The legacy store is copied over once, crash-safely. Widgets never create the store. Settings the widget needs are mirrored to group defaults.
- **Quick add (Mac).** `App/Mac/QuickAdd.swift` registers a Carbon global hotkey (no Accessibility permission) and shows a nonactivating glass panel. The shortcut is set in Settings (default ⌃⌥Space).

**Review.** Codex astra ran one correctness review of the batch and three verification rounds. All confirmed blocking findings were fixed: migration safety, widget-first store creation, cleared titles hard-deleting, offline duplicate series, stale actions reviving trashed series, monthly drift, a date removal orphaning the repeat, the intent leaving the timer running, purge timing, a refresh cancelling itself, and the restore loop. Round 3's verdicts are in the transcript; see the final report.

**Checked.** NowCore: 67 tests pass. Both platforms build (Debug, Release, iOS device). The iPhone simulator was run by hand through: the store migration, the History button, Repeat and Estimate in details, starting the timer (countdown on the row, survives a relaunch), completing a repeating task (the next occurrence appears, including when completed early), swipe-delete and restore in History, and a cleared title going to Recently Deleted. On Mac, the Release app is installed at `/Applications/Podium.app` and its store migrated to the App Group.

**Not checked.** The Live Activity (the simulator control couldn't leave the app), widgets on the home screen or desktop, the Mac quick-add hotkey, and the Mac sheet header, since driving the Mac needs Nikhil's keyboard or focus. Background refresh only runs on a device. Completing from a Mac widget runs in the extension, so the app's timer alert isn't cleaned up until its next refresh (15 minutes at most).

**Follow-up, same day.** On Mac, ⓘ opens the details as a popover anchored to the button, like Reminders (`TaskListView.inspecting`, which also holds the order while it's open). iPhone keeps the sheet. The details layout follows Reminders: title and notes without labels, then "Date & Time" and "Organization". Inline editing chips follow Reminders too: the date, then icon-only priority, estimate, and repeat that show a value once set. The timer is a small ▶︎ (⏹ plus countdown while running) at the end of the detail line, which is now one wrapping text. Mac text fields follow the system autocorrect, text replacement, and spell-check settings (`TextInputSettings` in `Glass.swift`); SwiftUI leaves them off. Unverified on Mac: the popover, the chips, and autocorrect. They need Nikhil's keyboard.

**Look change, same day.** Opening the popover made the list flicker. Two causes were fixed. First, the row now keeps its editing look while its popover is open. Second, the window material dimmed as the window lost key status, so the Mac window now uses `PopoverMaterial` (an `NSVisualEffectView` with `.popover`, state `.active`). Nikhil confirmed the flicker is gone, then found the tinted glass too colorful, so the gradient backdrop and the glass cards are gone on both platforms and in the widget: `ListBackdrop` and `cardRow()` in `Glass.swift`.

**Hang, custom repeats, widget column.**
- **Menu bar hang.** Starting a timer hung the Mac app at 100% CPU. The cause was the menu bar label showing a live countdown: SwiftUI renders `MenuBarExtra` labels to an image, and any live content in them (a timer text, a `TimelineView`, even the `@Query` feeding it) re-rendered in a loop. The label is now plain, fed by `MenuBarStatus`, which `Refresher` sets and which ticks once a minute only while a timer runs. It shows minutes left ("14m"). Checked by sampling: 0% CPU idle and with a fake running timer.
- **Custom repeats.** `Recurrence` is now a rule (`unit`, `interval`, `weekdays`) instead of an enum, with the old cases as presets that keep their stored names. Custom rules store as `every:<n>:<unit>[:<weekdays>]`. Note that `==` and `hash` are explicit, because the default for a `RawRepresentable` type compares `rawValue`, which recursed. The details view's Repeat has Custom… (Frequency, Every N, weekday toggles). NowCore: 75 tests.
- **Widget.** The medium widget has Now on the left and Upcoming on the right: the next three dated hidden tasks, soonest first.

**Widget click opens the app.** The widget has `widgetURL(podium://open)`, and the `podium` scheme is registered in `Config/Info-iOS.plist` and the new `Config/Info-macOS.plist`. On Mac, `RootView` uses `handlesExternalEvents(preferring:allowing:)` so an open window takes the link. With no window (the app still runs in the menu bar), SwiftUI opens one. Checked with `open -g podium://open`: no window becomes one window, and repeat links keep one.

**Timer design, status dropped.** Nikhil found the ▶︎/⏹ icons clunky and "In Progress" meaningless. The row has no timer button now. A running timer shows as a progress ring on the completion circle and "12m left" in the detail line. Starting and stopping happen from the Timer chip (inline controls and the iPhone keyboard bar), the details, right-click, or swipe. Status is gone from the UI (details, right-click, detail line), and starting a timer no longer sets it. `statusRaw` stays in the model for compatibility. Mac widget links also activate the app and bring the window to the front.

**Mac widget gotcha.** Replacing `/Applications/Podium.app` doesn't restart a running widget extension. The old `PodiumWidgets` process keeps serving the old layout from memory. After installing, kill the old process (`pgrep -f "Applications/Podium.app/Contents/PlugIns/PodiumWidgets"`) and relaunch the app, which reloads timelines. Check which copy macOS uses with `pluginkit -m -v -i com.talix.now.widgets`.

**Dock icon.** `App/Mac/DockIcon.swift` switches the activation policy: `.regular` while a titled, non-panel window is open, `.accessory` otherwise. It follows the Show in Dock setting (While Window Is Open by default, Always, Never). Show in Menu Bar drives `MenuBarExtra(isInserted:)`. Checked with `lsappinfo`: closing the window gives UIElement, and `podium://open` gives Foreground with one window.

**Settings without a Dock icon.** An accessory app has no menu bar, so Podium › Settings… wasn't reachable when Podium was out of the Dock. There's now `OpenSettingsButton` (in `DockIcon.swift`): a ⚙︎ in the window toolbar and "Settings…" in the menu bar panel. It calls `openSettings`, activates, and raises the window with `orderFrontRegardless`, because macOS can decline to activate a background accessory app.

## Change 8: test pass and fixes (session 5, 2026-09-28 and 29)

**Why.** On Mac, editing an overdue, rescheduled task made the list scroll sideways, drew the chips over the swipe's Delete button, and pushed ⓘ off-screen, so Custom… on the date chip had nowhere to open (Nikhil's screenshot, 2026-09-28). Nikhil also found the chips too wide. Then Nikhil asked for a full test pass and for every issue and nit it found to be fixed (2026-09-29).

**What.**
- **Mac edit chips.** `ChipFlow` (a `Layout` in `TaskRow.swift`) wraps the chips instead of a `.fixedSize()` `HStack` that could be wider than the window. Reschedule hides while the row is being edited, since the date chip has the same presets. The priority chip is icon-only, or just `!!!` for Marks, and the timer chip is ▶︎/■. Tooltips keep the text.
- **Date-only tasks** are stored at local noon (`TaskItem.dateOnly`), so the day holds after a time-zone change. `Refresher.tidy` moves old exact-midnight values (due date and repeat anchor) to noon, once per device (`migration.dateOnlyNoon.v1`). Running it on every refresh would loop between two devices 12 hours apart, where one's noon is the other's midnight.
- **Repeats.** Editing the date by hand goes through `TaskItem.setDueDate`, which moves the series anchor too, so a monthly repeat follows the new day. Applying a repeat to an open task resets `spawnedNext` and starts a fresh series ID, so a reopened occurrence given a repeat again carries on, and `tidy` doesn't take it for a duplicate of the occurrence it already spawned.
- **Estimate.** `TaskItem.setEstimate` stops the timer when the estimate is cleared.
- **Alerts.** Date-only tasks alert once at `WorkingHours.morningMinute` (9:00, or the start of working hours) on their day, saying "Due today." (or "Overdue. It was due …" when held to a later day). Due alerts carry `content.badge` with the overdue count at their fire time, and a silent `.overdueBadge` notification (badge only) updates it when a date-only task goes overdue at the end of its day.
- **Quick dates.** "This Morning" shows before the morning time, so at 01:30 there's an option for 9:00 today, not only tomorrow's.
- **Settings** re-plan from `AppSettings` itself, so changes apply on Mac with no window open, and Priority Icons reloads the widgets. The working-hours pickers set clock fields, which fixes daylight-saving days.
- **Accessibility.** Icon-only chips have names for VoiceOver ("Priority: High", "Estimate", "Repeat").
- **iPhone UI.** The Clear confirmation is attached to the Clear button, so the popover points at it, and it shows its question with the right plural. Add Subtask keeps focus after Return.
- **Shipping.** A widget privacy manifest (`Widgets/PrivacyInfo.xcprivacy`), and `1C8F.1` for App Group defaults in both. `ITSAppUsesNonExemptEncryption` is false on both platforms. The widget reads the store once per timeline.

**Review.** A read-only review of the first round found the 12-hour migration loop, the reused series ID, the missing end-of-day badge update, the held-alert wording, the widget not reloading on Priority Icons, the Date picker skipping `setDueDay`, the estimate footer, chip accessibility, and `ChipFlow` letting one chip overflow. All are fixed.

**Checked.** NowCore: 80 tests pass. Mac Release and both Debug builds pass with no warnings, and both privacy manifests land in the built app and widget. On the iPhone simulator (no iCloud account), from a fresh install: first launch and the notification prompt, quick add and Just Added, the keyboard-bar chips, details (estimate, custom repeat, subtasks), completing a repeating task, swipe snooze, start, and delete, the hidden list, a due alert firing on time, the overdue look and Reschedule, Pick a Date…, the long-press menu, History restore, a cleared title going to Recently Deleted, the timer ring and its Live Activity (start and stop), settings applying and surviving a relaunch, dark mode, and Marks. After the fixes: the badge shows 1 as the due alert fires with the app in the background, the Clear dialog, subtask focus, clearing the estimate stopping the timer, the noon migration, and chip accessibility names.

**Not checked.** Everything on the Mac (the chips, the swipe, Custom…, quick add, the menu bar), since synthetic input there lands in Nikhil's other windows. Widgets on a home screen and notification actions, because the device tool keeps bringing Podium to the front. The notification showed a blank icon on the simulator; check it on a device. The silent end-of-day badge update is covered by planner tests but wasn't seen firing.

**Second test pass (2026-09-29, same session).** Nikhil asked why the rest wasn't tested, and approved taking over the Mac's mouse and keyboard with a backup of the store.
- **How to drive things.** The device tool brings its session app forward before every tap, so for the home screen, widgets, and notification banners, open the session on `com.apple.springboard` instead, and take screenshots with the T3 device screenshot rather than the tool's own. On the Mac, the device tool clicks in the wrong place. Use `CGEvent` mouse events at window coordinates from `CGWindowListCopyWindowInfo`, send keys with `CGEvent.postToPid` to Podium's process only (with Show in Dock set to Never, Podium can't be brought to the front, and keys posted globally go to whatever app is), press toolbar buttons and sheet buttons through System Events, and fill the quick-add panel's field through accessibility. Synthetic events can't open menu bar items or trigger row swipe actions on the Mac.
- **Checked on the iPhone simulator:** the widget on the home screen (it matches the app's order and completes a task from its circle), the Done action on an alert (completes the task and creates the next occurrence of a repeat without opening the app, clears the badge, updates the widget), and the silent end-of-day badge update.
- **Checked on the Mac:** inline editing chips (they wrap and ⓘ stays visible), the date menu, Custom… opening the details popover and changing the date, right-click menus, ⌘N and adding a task, the ⌃⌥Space quick add panel, the Settings window, History, and the timer with its menu bar countdown.
- **iCloud sync works on this Mac.** The store's `ANSCKEVENT` table shows hundreds of successful setup, import, and export events. `defaults read MobileMeAccounts` is empty on this macOS even though the Mac is signed in, so don't use it to check. Because of sync, restoring the store file from a backup doesn't undo changes (the app re-imports them from CloudKit). Test edits on the Mac were undone through the app instead, and the store matched the backup afterwards.
- **Found and fixed:** a right-click on a Mac task title opened the text field's menu instead of the task menu (`RightClickPassThrough` in `TaskRow.swift` catches right-clicks until the row is being edited). History on the Mac was 470 points wide in a 349-point window (`GlassSheet` now has a fixed width of 340). The widget took up to 15 minutes to show a task as overdue (its timeline now adds entries at each due and start-by time in the next two hours). Starting or stopping a timer took about 20 seconds to reach the menu bar, since `Refresher` waits for autosave (`startTimer` and `stopTimer` now save straight away).
- **Still not checked:** the Mac menu bar panel, Mac row swipe actions, Mac desktop widgets, background refresh (debugger access is off on this Mac; it needs `sudo DevToolsSecurity -enable`), and sync between two devices.

## Change 9: lists in notes (session 6, 2026-10-02)

**Why.** Nikhil couldn't make a bulleted list in a task's notes, and Reminders supports it (screenshot of a note starting "* Ask her questions", 2026-10-02).

**What.**
- On the Mac, Return in a vertical `TextField` submits instead of adding a line, so notes could never get a second line. `NotesField` (`App/Views/NotesField.swift`, used by `TaskRow` and `TaskDetailView`) handles Return itself with `onKeyPress` and places the cursor through a `TextSelection` binding.
- `NoteList` in NowCore does the list editing on plain text, so notes stay a `String`. Lines starting with "• ", "- ", "* ", or "1. " are list items. Return starts the next item (numbers count up), Return on an empty item ends the list, and "- " or "* " typed at the start of a line becomes "• ".
- iPhone types Return into the text, so there the newline arrives as a change. A newline typed next to another one is ambiguous, and it's read as Return at the end of the line before.

**Checked.** NowCore: 93 tests pass. Mac and iPhone simulator Debug builds pass. `NotesField` was driven in an offscreen window with in-process key events: typing a list, ending it, and Return in the middle of a list all give the right text and cursor.

**Not checked.** By hand in the running app on either platform.

---

## Remaining work

In order:

1. **Verify iCloud sync.** Sign into iCloud on the Mac (or run on a real iPhone that's signed in) and confirm `ANSCKEVENT` in the store shows a successful setup. The store is now in the App Group: `~/Library/Group Containers/2TG5HP8NSV.com.talix.now/Library/Application Support/Podium.store` on Mac. Then test sync between two devices. Before TestFlight, deploy the CloudKit schema from Development to Production in the CloudKit Console, or TestFlight builds won't sync.
2. **Run the rest of the manual checklist** below. Items 1 and 3 through 8 need dated tasks and waiting in real time. Notification actions (item 8) are best tested on a device.
3. **Design pass.** Compare against Reminders side by side. Small nits: on iOS the New Task field grabs focus again after the details sheet closes, and the keyboard covers the bottom of the list.
4. **Try the new pieces on real hardware:** widgets, the timer Live Activity, background refresh, and the Mac quick-add hotkey (⌃⌥Space).
5. **TestFlight.** Create the App Store Connect record for `com.talix.now`, archive, upload. Only when Nikhil asks.

Known gaps, deliberately out of v1 (see SCOPE.md "Next"):
- There's no background refresh, so notifications past the nearest 60 only get planned when the app opens.
- Duplicate alerts on Mac and iPhone are avoided with a per-device toggle, not real cancellation across devices.
- No widgets, no natural-language dates, no Siri/Shortcuts, no recurring tasks.

Still open from session 1 (settings persistence was checked in session 2):
- The `CompletionCircle` delay: if the list re-ranks during those 450ms, confirm the row doesn't flicker.
- `TaskRow` wraps the title and notes in an `onTapGesture` next to borderless buttons. The circle doesn't open the sheet. The Reschedule menu hasn't been checked yet.

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
