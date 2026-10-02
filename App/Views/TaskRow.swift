import NowCore
import SwiftData
import SwiftUI

/// Which text field in the list has focus. Editing a row's title or notes makes that row active.
enum RowFocus: Hashable {
    case title(UUID), notes(UUID)

    var taskID: UUID {
        switch self {
        case .title(let id), .notes(let id): id
        }
    }
}

/// One Reminders-style row: circle, title, notes, due line, inline subtasks.
/// Click the title to edit in place. The active row shows notes and quick controls, and ⓘ opens the details.
struct TaskRow: View {
    @Bindable var task: TaskItem
    /// Nil for completed tasks.
    let ranked: RankedTask?
    let now: Date
    var focus: FocusState<RowFocus?>.Binding
    /// Whether this row's details popover is open (Mac).
    var inspecting: Binding<Bool> = .constant(false)
    let onOpen: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    #if os(macOS)
    @State private var hovering = false
    #endif

    private var isOverdue: Bool { ranked?.tier == .overdue }
    private var canStartTimer: Bool { task.estimateMinutes != nil && !task.isDone }
    private var isActive: Bool { focus.wrappedValue?.taskID == task.id }
    /// Editing inline or in the details popover. The row keeps its editing look (highlight, notes,
    /// chips) while the popover is open, so it doesn't change shape under the popover's arrow.
    private var isEditing: Bool { isActive || inspecting.wrappedValue }

    private var showsInfoButton: Bool {
        #if os(macOS)
        isActive || hovering || inspecting.wrappedValue
        #else
        isActive
        #endif
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            CompletionCircle(isDone: task.isDone, progress: timerProgress) { done in
                task.status = done ? .done : .todo
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if !task.isDone {
                        PriorityIcon(priority: task.priority)
                    }
                    TextField("New Task", text: $task.title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                        .focused(focus, equals: .title(task.id))
                        #if os(macOS)
                        .overlay {
                            // The text field answers a right-click with its own text menu (Look Up,
                            // Cut, Copy). Until the row is being edited, right-clicks go to the row's
                            // task menu instead. While editing, the field keeps its menu for spelling.
                            if !isEditing { RightClickPassThrough() }
                        }
                        #endif
                        .onSubmit { focus.wrappedValue = nil }
                        .onChange(of: task.title) { _, title in
                            // Vertical fields take Return as a newline; treat it as "done" like Reminders.
                            guard title.contains("\n") else { return }
                            task.title = title.replacingOccurrences(of: "\n", with: "")
                            focus.wrappedValue = nil
                        }
                }

                if isEditing || !task.notes.isEmpty {
                    NotesField(text: $task.notes)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(isEditing ? 1...6 : 1...2)
                        .focused(focus, equals: .notes(task.id))
                }

                #if os(macOS)
                if isEditing && !task.isDone {
                    // Reminders-style chips under the notes while editing. They wrap rather than
                    // widen the row, which would push ⓘ off-screen and scroll the list sideways.
                    ChipFlow(spacing: 6) {
                        InlineEditControls(task: task, now: now, onCustomDate: onOpen)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .menuIndicator(.hidden)
                    .padding(.top, 2)
                } else {
                    detailLine
                }
                #else
                detailLine
                #endif

                ForEach(task.sortedSubtasks) { subtask in
                    SubtaskLine(subtask: subtask)
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // While editing, the date chip offers the same choices.
            if isOverdue && !isEditing {
                Menu {
                    QuickDateButtons(presets: QuickDate.reschedule, now: now) { task.reschedule(to: $0) }
                    Divider()
                    Button("Pick a Date…", action: onOpen)
                } label: {
                    Text("Reschedule").foregroundStyle(.red)
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .buttonStyle(.glass)
                .controlSize(.small)
                .tint(.red)
            }

            if showsInfoButton {
                Button(action: onOpen) {
                    Image(systemName: "info.circle")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Show Details")
                #if os(macOS)
                .popover(isPresented: inspecting, arrowEdge: .trailing) {
                    TaskDetailView(task: task)
                }
                #endif
            }
        }
        .cardRow(highlighted: isEditing)
        #if os(macOS)
        .onHover { hovering = $0 }
        #endif
        .contextMenu { contextMenu }
        .swipeActions(edge: .leading) {
            if !task.isDone {
                Button { withAnimation { task.status = .done } } label: { Label("Done", systemImage: "checkmark") }
                    .tint(.green)
            }
            if canStartTimer && !task.isTimerRunning {
                Button { task.startTimer() } label: { Label("Start", systemImage: "play.fill") }
                    .tint(.accentColor)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { task.moveToTrash() } label: { Label("Delete", systemImage: "trash") }
            // Overdue beats snooze in the ranking, so snoozing an overdue task would do nothing visible.
            if !task.isDone && !isOverdue {
                Button { task.snooze(until: now.addingTimeInterval(3600)) } label: { Label("Snooze 1h", systemImage: "moon.zzz") }
                    .tint(.indigo)
            }
        }
    }

    /// "Today, 10:00 · Start by 09:15 · 12m left · 2/5"
    @ViewBuilder
    private var detailLine: some View {
        let parts = detailParts
        if !parts.isEmpty {
            // One text, so a long line wraps as a whole instead of truncating each part.
            parts.enumerated().reduce(Text("")) { line, item in
                let separator = item.offset > 0 ? Text(" · ").foregroundStyle(.secondary) : Text("")
                return Text("\(line)\(separator)\(Text(item.element.text).foregroundStyle(item.element.color))")
            }
            .font(.subheadline)
            .lineLimit(2)
        }
    }

    /// How far a running timer has got, for the ring around the completion circle. The row redraws
    /// every minute, which is enough for a ring that fills over the task's estimate.
    private var timerProgress: Double? {
        guard let start = task.timerStartedAt, let end = task.timerEnd, end > start else { return nil }
        return min(max(Date.now.timeIntervalSince(start) / end.timeIntervalSince(start), 0), 1)
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
        if let end = task.timerEnd {
            let left = end.timeIntervalSinceNow
            parts.append(left > 0 ? ("\(DueLabel.duration((left / 60).rounded(.up) * 60)) left", .accentColor) : ("Time's up", .orange))
        }
        if let recurrence = task.recurrence {
            parts.append((recurrence.label, .secondary))
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
        Picker("Priority", selection: $task.priority) {
            ForEach(Priority.allCases.reversed(), id: \.self) { PriorityLabel(priority: $0).tag($0) }
        }
        if canStartTimer {
            if task.isTimerRunning {
                Button("Stop Timer") { task.stopTimer() }
            } else {
                Button("Start Timer") { task.startTimer() }
            }
        }
        if !task.isDone {
            if !isOverdue {
                Menu("Snooze") {
                    QuickDateButtons(presets: QuickDate.snooze, now: now) { task.snooze(until: $0) }
                }
            }
            Menu("Reschedule") {
                QuickDateButtons(presets: QuickDate.reschedule, now: now) { task.reschedule(to: $0) }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { task.moveToTrash() }
    }
}

#if os(macOS)
/// Catches right-clicks and Control-clicks, which then travel up to the row's context menu. Every
/// other click falls through to whatever is underneath.
private struct RightClickPassThrough: NSViewRepresentable {
    final class CatcherView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let menuClick = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return menuClick ? super.hitTest(point) : nil
        }
    }

    func makeNSView(context: Context) -> NSView { CatcherView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

/// Reminders' hollow circle. Fills briefly before the task leaves the list so the tap feels acknowledged.
struct CompletionCircle: View {
    let isDone: Bool
    /// While a task timer runs, a ring fills around the circle over the estimate.
    var progress: Double? = nil
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
                .overlay {
                    if let progress, !filled {
                        Circle()
                            .trim(from: 0, to: max(progress, 0.02))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(1.5)
                    }
                }
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

/// Reminders-style quick controls for the row being edited: the date, then icon-only chips for
/// priority, estimate, and repeat that show their value once set, and a timer button for tasks
/// with an estimate. The caller lays them out
/// (under the row on Mac, above the keyboard on iPhone).
struct InlineEditControls: View {
    @Bindable var task: TaskItem
    @Environment(AppSettings.self) private var settings
    let now: Date
    /// Specific dates and times, and custom repeats, are set in the details view.
    let onCustomDate: () -> Void

    var body: some View {
        Menu {
            Button("Today") { task.setDueDay(now) }
            Button("Tomorrow") {
                // A calendar day, not 24 hours, so daylight-saving days land on the right date.
                if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) { task.setDueDay(tomorrow) }
            }
            Divider()
            QuickDateButtons(presets: QuickDate.reschedule, now: now) { task.reschedule(to: $0) }
            Divider()
            Button("Custom…", action: onCustomDate)
            if task.dueDate != nil {
                Button("Remove Date", role: .destructive) { task.clearDueDate() }
            }
        } label: {
            Label(task.dueDate.map { DueLabel.text(for: $0, hasTime: task.hasDueTime, now: now) } ?? "Add Date", systemImage: "calendar")
        }

        Menu {
            Picker("Priority", selection: $task.priority) {
                ForEach(Priority.allCases.reversed(), id: \.self) { PriorityLabel(priority: $0).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            // The icon already shows the level, so no name next to it. Marks style has no icon; its "!!" is the value.
            if task.priority != .none, settings.priorityStyle.image(for: task.priority) == nil {
                Text(task.priority.marks).accessibilityLabel(priorityName)
            } else {
                iconOnly(settings.priorityStyle.image(for: task.priority) ?? Image(systemName: "exclamationmark"), name: priorityName)
            }
        }
        .help(priorityName)

        Menu {
            Picker("Estimate", selection: Binding(get: { task.estimateMinutes }, set: { task.setEstimate($0) })) {
                Text("None").tag(Int?.none)
                ForEach(TaskDetailView.estimates, id: \.self) { minutes in
                    Text(DueLabel.duration(TimeInterval(minutes * 60))).tag(Int?.some(minutes))
                }
            }
            .pickerStyle(.inline)
        } label: {
            chip(task.estimateMinutes.map { DueLabel.duration(TimeInterval($0 * 60)) }, name: "Estimate", icon: Image(systemName: "hourglass"))
        }
        .help("Estimate")

        Menu {
            Picker("Repeat", selection: $task.recurrence) {
                Text("Never").tag(Recurrence?.none)
                ForEach(Recurrence.allCases, id: \.self) { Text($0.label).tag(Recurrence?.some($0)) }
                if let custom = task.recurrence, !custom.isPreset {
                    Text(custom.label).tag(Recurrence?.some(custom))
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Custom…", action: onCustomDate)
        } label: {
            chip(task.recurrence?.label, name: "Repeat", icon: Image(systemName: "repeat"))
        }
        .help("Repeat")

        if let minutes = task.estimateMinutes, !task.isDone {
            Button {
                if task.isTimerRunning { task.stopTimer() } else { task.startTimer() }
            } label: {
                // Icon only: the estimate chip beside it already shows the length.
                iconOnly(Image(systemName: task.isTimerRunning ? "stop.fill" : "play.fill"),
                         name: task.isTimerRunning ? "Stop Timer" : "Start Timer")
            }
            .help(task.isTimerRunning ? "Stop the timer" : "Start a \(DueLabel.duration(TimeInterval(minutes * 60))) timer")
        }
    }

    private var priorityName: String {
        task.priority == .none ? "Priority" : "Priority: \(task.priority.label)"
    }

    /// Like Reminders: just the icon until there's a value to show. `name` is what VoiceOver reads.
    @ViewBuilder
    private func chip(_ value: String?, name: String, icon: Image) -> some View {
        if let value {
            Label { Text(value) } icon: { icon }
                .accessibilityLabel("\(name): \(value)")
        } else {
            iconOnly(icon, name: name)
        }
    }

    /// An icon set in text, so an icon-only chip is as tall as the chips with a value. A plain image
    /// sizes the button to the glyph, and a thin one like `=` makes a short chip.
    private func iconOnly(_ icon: Image, name: String) -> some View {
        Text(icon).accessibilityLabel(name)
    }
}

/// Lays chips out left to right at their natural size, wrapping to a new line when the row runs out of width.
struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, maxWidth: proposal.width ?? .infinity)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, maxWidth: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(for subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        for subview in subviews {
            // A chip wider than the whole row gets the row's width, rather than widening the row.
            var size = subview.sizeThatFits(.unspecified)
            size.width = min(size.width, maxWidth)
            if origin.x > 0 && origin.x + size.width > maxWidth {
                origin = CGPoint(x: 0, y: origin.y + lineHeight + spacing)
                lineHeight = 0
            }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
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
