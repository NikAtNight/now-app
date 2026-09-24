import NowCore
import SwiftData
import SwiftUI

/// One Reminders-style row: circle, title, notes, due line, inline subtasks.
struct TaskRow: View {
    @Bindable var task: TaskItem
    /// Nil for completed tasks.
    let ranked: RankedTask?
    let now: Date
    let onOpen: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    private var isOverdue: Bool { ranked?.tier == .overdue }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            CompletionCircle(isDone: task.isDone) { done in
                task.status = done ? .done : .todo
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(titleText)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.primary)

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                detailLine

                ForEach(task.sortedSubtasks) { subtask in
                    SubtaskLine(subtask: subtask)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            if isOverdue {
                Menu {
                    QuickDateButtons(presets: QuickDate.reschedule, now: now) { task.reschedule(to: $0) }
                    Divider()
                    Button("Pick a Date…", action: onOpen)
                } label: {
                    Text("Reschedule")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
            }
        }
        .padding(.vertical, 4)
        .contextMenu { contextMenu }
        .swipeActions(edge: .leading) {
            if !task.isDone {
                Button { withAnimation { task.status = .done } } label: { Label("Done", systemImage: "checkmark") }
                    .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { context.delete(task) } label: { Label("Delete", systemImage: "trash") }
            if !task.isDone {
                Button { task.snooze(until: now.addingTimeInterval(3600)) } label: { Label("Snooze 1h", systemImage: "moon.zzz") }
                    .tint(.indigo)
            }
        }
    }

    private var titleText: AttributedString {
        var title = AttributedString(task.title.isEmpty ? "Untitled" : task.title)
        guard task.priority != .none, !task.isDone else { return title }
        var marks = AttributedString(task.priority.marks + " ")
        marks.foregroundColor = .orange
        title = marks + title
        return title
    }

    /// "Today, 10:00 · Start by 09:15 · In Progress · 2/5"
    @ViewBuilder
    private var detailLine: some View {
        let parts = detailParts
        if !parts.isEmpty {
            HStack(spacing: 4) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    if index > 0 { Text("·").foregroundStyle(.secondary) }
                    Text(part.text).foregroundStyle(part.color)
                }
            }
            .font(.subheadline)
            .lineLimit(1)
        }
    }

    private var detailParts: [(text: String, color: Color)] {
        var parts: [(text: String, color: Color)] = []
        if let due = task.dueDate {
            parts.append((DueLabel.text(for: due, hasTime: task.hasDueTime, now: now), isOverdue ? .red : .secondary))
        }
        if let ranked, ranked.tier != .overdue, let startBy = ranked.startBy {
            let behind = startBy <= now
            parts.append((behind ? "Start now" : "Start by \(DueLabel.timeText(startBy))", behind ? .orange : .secondary))
        }
        if ranked?.tier == .snoozed, let until = task.snoozedUntil {
            parts.append(("Snoozed until \(DueLabel.text(for: until, hasTime: true, now: now))", .indigo))
        }
        if task.status == .inProgress {
            parts.append(("In Progress", .blue))
        }
        let subtasks = task.subtasks ?? []
        if !subtasks.isEmpty {
            parts.append(("\(subtasks.filter(\.isDone).count)/\(subtasks.count)", .secondary))
        }
        return parts
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Show Details", action: onOpen)
        Picker("Status", selection: $task.status) {
            ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        Picker("Priority", selection: $task.priority) {
            ForEach(Priority.allCases.reversed(), id: \.self) { Text($0.label).tag($0) }
        }
        if !task.isDone {
            Menu("Snooze") {
                QuickDateButtons(presets: QuickDate.snooze, now: now) { task.snooze(until: $0) }
            }
            Menu("Reschedule") {
                QuickDateButtons(presets: QuickDate.reschedule, now: now) { task.reschedule(to: $0) }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { context.delete(task) }
    }
}

/// Reminders' hollow circle. Fills briefly before the task leaves the list so the tap feels acknowledged.
struct CompletionCircle: View {
    let isDone: Bool
    let onChange: (Bool) -> Void
    @State private var pendingDone = false

    var body: some View {
        let filled = isDone || pendingDone
        Button {
            if isDone {
                onChange(false)
                return
            }
            withAnimation(.easeOut(duration: 0.15)) { pendingDone = true }
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation { onChange(true) }
                pendingDone = false
            }
        } label: {
            Image(systemName: filled ? "largecircle.fill.circle" : "circle")
                .font(.title3)
                .foregroundStyle(filled ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(isDone ? "Mark as not done" : "Mark as done")
    }
}

struct SubtaskLine: View {
    @Bindable var subtask: Subtask

    var body: some View {
        HStack(spacing: 8) {
            Button { subtask.isDone.toggle() } label: {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            Text(subtask.title)
                .strikethrough(subtask.isDone)
                .foregroundStyle(subtask.isDone ? Color.secondary : Color.primary)
        }
        .font(.subheadline)
    }
}

/// One button per quick date that still makes sense right now.
struct QuickDateButtons: View {
    let presets: [QuickDate]
    let now: Date
    let action: (Date) -> Void
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ForEach(presets) { preset in
            if let date = preset.date(from: now, workingHours: settings.ranking.workingHours) {
                Button(preset.label) { action(date) }
            }
        }
    }
}
