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

    @Query(filter: #Predicate<TaskItem> { $0.statusRaw != "done" })
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
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)

                HStack {
                    Button("Open Now") {
                        openWindow(id: "main")
                        NSApp.activate()
                    }
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                }
                .buttonStyle(.borderless)
                .font(.subheadline)
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
                Text(task.priority == .none ? task.title : "\(task.priority.marks) \(task.title)")
                    .lineLimit(2)
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
