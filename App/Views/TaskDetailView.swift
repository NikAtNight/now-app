import NowCore
import SwiftData
import SwiftUI

/// Reminders-style task details: a popover on the ⓘ on Mac, a sheet on iPhone. Edits save as you go.
struct TaskDetailView: View {
    @Bindable var task: TaskItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var newSubtask = ""
    @FocusState private var addingSubtask: Bool
    /// Keeps the custom repeat fields open while a custom rule happens to match a preset.
    @State private var editingCustomRepeat = false

    static let estimates = [15, 30, 45, 60, 90, 120, 180, 240, 480]

    var body: some View {
        #if os(macOS)
        form
            .frame(width: 360)
            .frame(minHeight: 420, idealHeight: 640)
        #else
        GlassSheet(title: "Details") { form }
        #endif
    }

    private var form: some View {
        Form {
            // Like Reminders: the title and notes lead, with no field labels.
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("", text: $task.title, prompt: Text("Title"), axis: .vertical)
                        .font(.title2.bold())
                        .textFieldStyle(.plain)
                        .labelsHidden()
                    NotesField(text: $task.notes)
                        .foregroundStyle(.secondary)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .lineLimit(1...6)
                }
                .padding(.vertical, 4)
            }

            Section("Date & Time") {
                Toggle(isOn: hasDate) { Label("Date", systemImage: "calendar") }
                if task.dueDate != nil {
                    DatePicker("Date", selection: dueDay, displayedComponents: .date)
                }
                Toggle(isOn: hasTime) { Label("Time", systemImage: "clock") }
                if task.hasDueTime {
                    DatePicker("Time", selection: dueDate, displayedComponents: .hourAndMinute)
                }
                Picker(selection: repeatChoice) {
                    Text("Never").tag(RepeatChoice.never)
                    ForEach(Recurrence.allCases, id: \.self) { Text($0.label).tag(RepeatChoice.preset($0)) }
                    Divider()
                    Text("Custom…").tag(RepeatChoice.custom)
                } label: {
                    Label("Repeat", systemImage: "repeat")
                }
                if repeatChoice.wrappedValue == .custom, let rule = task.recurrence {
                    CustomRepeatFields(rule: rule) { task.recurrence = $0 }
                }
            }

            Section {
                Picker(selection: $task.priority) {
                    ForEach(Priority.allCases.reversed(), id: \.self) { PriorityLabel(priority: $0).tag($0) }
                } label: {
                    Label("Priority", systemImage: "exclamationmark")
                }
                Picker(selection: Binding(get: { task.estimateMinutes }, set: { task.setEstimate($0) })) {
                    Text("None").tag(Int?.none)
                    ForEach(Self.estimates, id: \.self) { minutes in
                        Text(DueLabel.duration(TimeInterval(minutes * 60))).tag(Int?.some(minutes))
                    }
                } label: {
                    Label("Estimate", systemImage: "hourglass")
                }
                if let minutes = task.estimateMinutes, !task.isDone {
                    Button {
                        if task.isTimerRunning { task.stopTimer() } else { task.startTimer() }
                    } label: {
                        Label(task.isTimerRunning ? "Stop Timer" : "Start \(DueLabel.duration(TimeInterval(minutes * 60))) Timer",
                              systemImage: task.isTimerRunning ? "stop.circle" : "timer")
                    }
                }
            } header: {
                Text("Organization")
            } footer: {
                if task.estimateMinutes != nil {
                    // Date-only tasks alert once in the morning, so only timed ones get the start-time alert.
                    Text(task.hasDueTime
                         ? "With an estimate, the task shows up and alerts you when it's time to start, not when it's due."
                         : "With an estimate, the task shows up when it's time to start, not when it's due.")
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
                    .focused($addingSubtask)
                    .onSubmit(addSubtask)
            }

            Section {
                Button("Delete Task", role: .destructive) {
                    task.moveToTrash()
                    dismiss()
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    enum RepeatChoice: Hashable {
        case never, preset(Recurrence), custom
    }

    private var repeatChoice: Binding<RepeatChoice> {
        Binding {
            guard let rule = task.recurrence else { return .never }
            return editingCustomRepeat || !rule.isPreset ? .custom : .preset(rule)
        } set: { choice in
            switch choice {
            case .never:
                editingCustomRepeat = false
                task.recurrence = nil
            case .preset(let rule):
                editingCustomRepeat = false
                task.recurrence = rule
            case .custom:
                editingCustomRepeat = true
                if task.recurrence == nil {
                    // Start from "every week on this day", the most common custom rule.
                    let day = Calendar.current.component(.weekday, from: task.dueDate ?? .now)
                    task.recurrence = Recurrence(unit: .week, weekdays: [day])
                }
            }
        }
    }

    private var hasDate: Binding<Bool> {
        Binding {
            task.dueDate != nil
        } set: { on in
            if on {
                if task.dueDate == nil { task.setDueDate(TaskItem.dateOnly(.now)) }
            } else {
                task.clearDueDate()
            }
        }
    }

    private var hasTime: Binding<Bool> {
        Binding {
            task.hasDueTime
        } set: { on in
            if on {
                // Default to the next full hour, like Reminders. For today that can roll over to
                // tomorrow (turning Time on at 23:30 gives tomorrow 00:00, not a time that has passed).
                let calendar = Calendar.current
                let now = Date.now
                let nextHour = calendar.dateInterval(of: .hour, for: now).map(\.end) ?? now
                let day = task.dueDate ?? now
                if calendar.isDate(day, inSameDayAs: now) {
                    task.setDueDate(nextHour)
                } else {
                    let hour = calendar.component(.hour, from: nextHour)
                    task.setDueDate(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day)
                }
            } else if let due = task.dueDate {
                task.setDueDate(TaskItem.dateOnly(due))
            }
            task.hasDueTime = on
        }
    }

    private var dueDate: Binding<Date> {
        Binding { task.dueDate ?? .now } set: { task.setDueDate($0) }
    }

    /// The Date picker only picks the day. `setDueDay` keeps the time, or noon for a date-only task,
    /// rather than whatever time the picker hands back.
    private var dueDay: Binding<Date> {
        Binding { task.dueDate ?? .now } set: { task.setDueDay($0) }
    }

    private func addSubtask() {
        let title = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let subtask = Subtask(title: title, order: (task.subtasks?.map(\.order).max() ?? -1) + 1)
        context.insert(subtask)
        subtask.parent = task
        newSubtask = ""
        // Stay in the field so the next subtask can be typed straight away, like Reminders.
        addingSubtask = true
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

/// Frequency, "every N", and weekdays for a custom repeat, like Reminders' Custom repeat.
private struct CustomRepeatFields: View {
    let rule: Recurrence
    let onChange: (Recurrence) -> Void

    var body: some View {
        Picker("Frequency", selection: Binding(get: { rule.unit }, set: { unit in
            onChange(Recurrence(unit: unit, interval: rule.interval, weekdays: unit == .week ? rule.weekdays : []))
        })) {
            Text("Daily").tag(Recurrence.Unit.day)
            Text("Weekly").tag(Recurrence.Unit.week)
            Text("Monthly").tag(Recurrence.Unit.month)
            Text("Yearly").tag(Recurrence.Unit.year)
        }
        Stepper(value: Binding(get: { rule.interval }, set: { interval in
            onChange(Recurrence(unit: rule.unit, interval: interval, weekdays: rule.weekdays))
        }), in: 1...99) {
            Text("Every \(rule.interval) \(unitName(rule.unit, count: rule.interval))")
        }
        if rule.unit == .week {
            WeekdayPicker(weekdays: Binding(get: { rule.weekdays }, set: { days in
                onChange(Recurrence(unit: .week, interval: rule.interval, weekdays: days))
            }))
        }
        Text(rule.label)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func unitName(_ unit: Recurrence.Unit, count: Int) -> String {
        let (one, many) = switch unit {
        case .day: ("day", "days")
        case .week: ("week", "weeks")
        case .month: ("month", "months")
        case .year: ("year", "years")
        }
        return count == 1 ? one : many
    }
}
