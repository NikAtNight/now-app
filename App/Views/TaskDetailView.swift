import NowCore
import SwiftData
import SwiftUI

/// Reminders-style details sheet. Edits save as you go.
struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newSubtask = ""

    private static let estimates = [15, 30, 45, 60, 90, 120, 180, 240, 480]

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $task.title)
                    .font(.headline)
                TextField("Notes", text: $task.notes, axis: .vertical)
                    .lineLimit(1...6)
            }

            Section {
                Toggle(isOn: hasDate) { Label("Date", systemImage: "calendar") }
                if task.dueDate != nil {
                    DatePicker("Date", selection: dueDate, displayedComponents: .date)
                }
                Toggle(isOn: hasTime) { Label("Time", systemImage: "clock") }
                if task.hasDueTime {
                    DatePicker("Time", selection: dueDate, displayedComponents: .hourAndMinute)
                }
            }

            Section {
                Picker(selection: $task.priority) {
                    ForEach(Priority.allCases, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    Label("Priority", systemImage: "exclamationmark")
                }
                Picker(selection: $task.status) {
                    ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    Label("Status", systemImage: "circle.dashed")
                }
                Picker(selection: $task.estimateMinutes) {
                    Text("None").tag(Int?.none)
                    ForEach(Self.estimates, id: \.self) { minutes in
                        Text(DueLabel.duration(TimeInterval(minutes * 60))).tag(Int?.some(minutes))
                    }
                } label: {
                    Label("Estimate", systemImage: "hourglass")
                }
            } footer: {
                if task.estimateMinutes != nil {
                    Text("With an estimate, the task shows up and alerts you when it's time to start, not when it's due.")
                }
            }

            if let snoozed = task.snoozedUntil, snoozed > .now {
                Section {
                    LabeledContent("Snoozed Until", value: DueLabel.text(for: snoozed, hasTime: true, now: .now))
                    Button("Unsnooze") { task.snoozedUntil = nil }
                }
            }

            Section("Subtasks") {
                ForEach(task.sortedSubtasks) { subtask in
                    SubtaskEditor(subtask: subtask)
                }
                .onDelete { offsets in
                    let sorted = task.sortedSubtasks
                    for index in offsets { context.delete(sorted[index]) }
                }
                TextField("Add Subtask", text: $newSubtask)
                    .onSubmit(addSubtask)
            }

            Section {
                Button("Delete Task", role: .destructive) {
                    context.delete(task)
                    dismiss()
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Details")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .frame(minWidth: 420, minHeight: 560)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var hasDate: Binding<Bool> {
        Binding {
            task.dueDate != nil
        } set: { on in
            if on {
                task.dueDate = task.dueDate ?? Calendar.current.startOfDay(for: .now)
            } else {
                task.dueDate = nil
                task.hasDueTime = false
            }
        }
    }

    private var hasTime: Binding<Bool> {
        Binding {
            task.hasDueTime
        } set: { on in
            if on {
                // Default to the next full hour on the chosen day, like Reminders.
                let calendar = Calendar.current
                let day = task.dueDate ?? .now
                let nextHour = calendar.component(.hour, from: .now) + 1
                task.dueDate = calendar.date(bySettingHour: min(nextHour, 23), minute: 0, second: 0, of: day)
            }
            task.hasDueTime = on
        }
    }

    private var dueDate: Binding<Date> {
        Binding { task.dueDate ?? .now } set: { task.dueDate = $0 }
    }

    private func addSubtask() {
        let title = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let subtask = Subtask(title: title, order: (task.subtasks?.map(\.order).max() ?? -1) + 1)
        context.insert(subtask)
        subtask.parent = task
        newSubtask = ""
    }
}

private struct SubtaskEditor: View {
    @Bindable var subtask: Subtask

    var body: some View {
        HStack(spacing: 10) {
            Button { subtask.isDone.toggle() } label: {
                Image(systemName: subtask.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(subtask.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            TextField("Subtask", text: $subtask.title)
        }
    }
}
