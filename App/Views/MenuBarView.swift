#if os(macOS)
import AppKit
import NowCore
import SwiftData
import SwiftUI

/// The Focus list, one click away in the menu bar.
struct MenuBarView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow

    @Query(filter: TaskItem.openPredicate)
    private var openTasks: [TaskItem]

    @State private var newTitle = ""

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            let ranking = Ranker.rank(openTasks.map(\.snapshot), now: now, settings: settings.ranking)
            let items = Dictionary(openTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Now").font(.headline)
                    Spacer()
                    if ranking.overdueCount > 0 {
                        Text("\(ranking.overdueCount) overdue").font(.caption).foregroundStyle(.red)
                    }
                }

                if ranking.focus.isEmpty {
                    Text("Nothing needs you right now.")
                        .foregroundStyle(.secondary)
                }

                ForEach(ranking.focus) { item in
                    if let task = items[item.id] {
                        MenuBarRow(task: task, ranked: item, now: now)
                    }
                }

                Divider()

                TextField("New Task", text: $newTitle)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .glassEffect(.regular, in: .capsule)
                    .onSubmit(add)

                HStack {
                    Button("Open Podium") {
                        openWindow(id: "main")
                        NSApp.activate()
                    }
                    OpenSettingsButton { Text("Settings…") }
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .padding(14)
            .frame(width: 320)
        }
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        context.insert(TaskItem(title: title))
        newTitle = ""
    }
}

/// What the menu bar item shows: the minutes left on a running task timer, if any.
///
/// The menu bar label must stay plain. SwiftUI renders it to an image and re-lays out the status
/// item on every update, and live content in it (a ticking timer text, a TimelineView, a query)
/// kept it re-rendering in a loop that pinned the main thread. So `Refresher` sets this, and it
/// ticks once a minute only while a timer runs.
@MainActor
@Observable
final class MenuBarStatus {
    static let shared = MenuBarStatus()

    private(set) var minutesLeft: Int?
    @ObservationIgnored private var timerEnd: Date?
    @ObservationIgnored private var ticker: Timer?

    func update(timerEnd: Date?) {
        self.timerEnd = timerEnd
        recompute()
        ticker?.invalidate()
        ticker = nil
        guard timerEnd != nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { MenuBarStatus.shared.recompute() }
        }
    }

    private func recompute() {
        let minutes = timerEnd.map { Int(($0.timeIntervalSinceNow / 60).rounded(.up)) }
        let next = minutes.flatMap { $0 > 0 ? $0 : nil }
        if next != minutesLeft { minutesLeft = next }
        if next == nil {
            ticker?.invalidate()
            ticker = nil
        }
    }
}

/// The menu bar item: the flag, plus the minutes left while a task timer runs.
struct MenuBarLabel: View {
    private let status = MenuBarStatus.shared

    var body: some View {
        if let minutes = status.minutesLeft {
            Text("\(Image(systemName: "flag.fill")) \(minutes)m")
        } else {
            Image(systemName: "flag.fill")
        }
    }
}

private struct MenuBarRow: View {
    let task: TaskItem
    let ranked: RankedTask
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CompletionCircle(isDone: task.isDone) { done in
                task.status = done ? .done : .todo
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    PriorityIcon(priority: task.priority)
                    Text(task.title).lineLimit(2)
                }
                if let due = task.dueDate {
                    Text(DueLabel.text(for: due, hasTime: task.hasDueTime, now: now))
                        .font(.caption)
                        .foregroundStyle(ranked.tier == .overdue ? Color.red : Color.secondary)
                }
            }
        }
    }
}
#endif
