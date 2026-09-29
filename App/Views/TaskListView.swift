import NowCore
import SwiftData
import SwiftUI

/// The one screen: what needs you now, with everything else a tap away.
struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(filter: TaskItem.openPredicate)
    private var openTasks: [TaskItem]

    @Query(filter: TaskItem.completedPredicate, sort: [SortDescriptor(\TaskItem.completedAt, order: .reverse)])
    private var completedTasks: [TaskItem]

    @State private var showHidden = false
    @State private var showCompleted = false
    @State private var confirmClear = false
    @State private var showHistory = false
    @State private var editing: TaskItem?
    /// Tasks added this session stay visible so they don't vanish into the hidden list before you date them.
    @State private var justAdded: [UUID] = []
    @FocusState private var newTaskFocused: Bool
    @FocusState private var rowFocus: RowFocus?
    /// The task whose details popover is open (Mac). Like editing, it holds the order.
    @State private var inspecting: UUID?
    /// The order at the moment editing started. Held until editing ends so rows don't jump or vanish mid-edit.
    @State private var frozenRanking: Ranking?
    #if os(iOS)
    @State private var showSettings = false
    #endif

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            content(now: timeline.date)
        }
        .navigationTitle("Now")
        #if os(macOS)
        // Like Reminders on the Mac: the title sits large in the content, not in the toolbar.
        .toolbar(removing: .title)
        #endif
        .toolbar { toolbar }
        .sheet(item: $editing) { task in
            TaskDetailView(task: task)
        }
        .sheet(isPresented: $showHistory) { HistoryView() }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            GlassSheet(title: "Settings") { SettingsView() }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .newTaskRequested)) { _ in
            newTaskFocused = true
        }
        // Opening a sheet ends inline editing, so the keyboard controls don't float over it.
        .onChange(of: editing?.id) { _, id in
            if id != nil { rowFocus = nil }
        }
        #if os(iOS)
        .onChange(of: showSettings) { _, shown in
            if shown { rowFocus = nil }
        }
        #endif
        .onChange(of: showHistory) { _, shown in
            if shown { rowFocus = nil }
        }
        // Hold the order while a row is being edited or its details popover is open, so the row (and
        // the popover anchored to it) doesn't jump or vanish mid-edit.
        .onChange(of: rowFocus?.taskID ?? inspecting) { _, held in
            if held != nil {
                if frozenRanking == nil { frozenRanking = liveRanking(now: .now) }
                return
            }
            // Clicking ⓘ can clear focus a moment before the popover opens. Wait a tick before
            // letting go, so the list doesn't re-rank and re-freeze in between.
            Task { @MainActor in
                await Task.yield()
                if (rowFocus?.taskID ?? inspecting) == nil { frozenRanking = nil }
            }
        }
        .onChange(of: rowFocus?.taskID) { old, new in
            // Like Reminders, a task whose title was cleared goes away when you leave it. It goes to
            // Recently Deleted rather than for good, since it may still have subtasks or a date.
            if let old, old != new, editing?.id != old, inspecting != old, let task = openTasks.first(where: { $0.id == old }) ?? completedTasks.first(where: { $0.id == old }),
               task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, task.notes.isEmpty {
                task.moveToTrash()
            }
        }
    }

    /// Details open in a popover on the ⓘ on Mac, like Reminders, and in a sheet on iPhone.
    private func openDetails(_ task: TaskItem) {
        #if os(macOS)
        inspecting = task.id
        #else
        editing = task
        #endif
    }

    private func inspectingBinding(_ task: TaskItem) -> Binding<Bool> {
        Binding { inspecting == task.id } set: { shown in
            if shown { inspecting = task.id } else if inspecting == task.id { inspecting = nil }
        }
    }

    private func liveRanking(now: Date) -> Ranking {
        Ranker.rank(openTasks.map(\.snapshot), now: now, settings: settings.ranking)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        #if os(macOS)
        // With the title removed, this keeps the add button on the trailing edge like Reminders.
        ToolbarSpacer(.flexible)
        #endif
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            Button { showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        // Settings from the window too: with no Dock icon Podium has no menu bar, so no Podium › Settings.
        ToolbarItem(placement: .primaryAction) {
            OpenSettingsButton { Label("Settings", systemImage: "gearshape") }
        }
        #endif
        ToolbarItem(placement: .primaryAction) {
            Button { newTaskFocused = true } label: { Label("New Task", systemImage: "plus") }
        }
        #if os(iOS)
        ToolbarItemGroup(placement: .topBarLeading) {
            Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            Button { showHistory = true } label: { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        ToolbarItemGroup(placement: .keyboard) {
            if let id = rowFocus?.taskID, let task = openTasks.first(where: { $0.id == id }) {
                InlineEditControls(task: task, now: .now) { editing = task }
                Spacer()
            }
        }
        #endif
    }

    private func content(now: Date) -> some View {
        let live = liveRanking(now: now)
        let ranking = frozenRanking ?? live
        let liveByID = Dictionary(live.all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = Dictionary(openTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let focusIDs = Set(ranking.focus.map(\.id))
        let recent = justAdded.filter { !focusIDs.contains($0) }.compactMap { id in ranking.hidden.first { $0.id == id } }
        let recentIDs = Set(recent.map(\.id))
        let hidden = ranking.hidden.filter { !recentIDs.contains($0.id) }

        return List {
            #if os(macOS)
            Text("Now")
                .font(.largeTitle.bold())
                .foregroundStyle(.tint)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            #endif

            summary(hiddenCount: hidden.count, overflow: ranking.urgentOverflow)

            if ranking.focus.isEmpty && recent.isEmpty {
                Text("Nothing needs you right now.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
            }

            rows(ranking.focus, items: items, live: liveByID, now: now)

            if !recent.isEmpty {
                Section("Just Added") { rows(recent, items: items, live: liveByID, now: now) }
            }

            if showHidden && !hidden.isEmpty {
                Section("Later") { rows(hidden, items: items, live: liveByID, now: now) }
            }

            NewTaskRow(focused: $newTaskFocused) { task in
                justAdded.append(task.id)
            }

            completedSection(now: now)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background { ListBackdrop() }
        .animation(.default, value: ranking.all.map(\.id))
    }

    /// Reminders-style counter line: "5 Hidden • Show", with a nudge when urgent work is hidden.
    private func summary(hiddenCount: Int, overflow: Int) -> some View {
        HStack(spacing: 6) {
            if hiddenCount == 0 {
                Text("Nothing hidden")
            } else if overflow > 0 && !showHidden {
                Text("\(hiddenCount) Hidden").foregroundStyle(.secondary)
                Text("•").foregroundStyle(.secondary)
                Text("\(overflow) more urgent").foregroundStyle(.red)
            } else {
                Text("\(hiddenCount) Hidden")
            }
            Spacer()
            if hiddenCount > 0 {
                Button(showHidden ? "Hide" : "Show") {
                    withAnimation { showHidden.toggle() }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func rows(_ ranked: [RankedTask], items: [UUID: TaskItem], live: [UUID: RankedTask], now: Date) -> some View {
        ForEach(ranked) { item in
            if let task = items[item.id] {
                // The order may be frozen, but show each task's live state (overdue, start-by).
                TaskRow(task: task, ranked: live[item.id] ?? item, now: now, focus: $rowFocus,
                        inspecting: inspectingBinding(task)) { openDetails(task) }
            }
        }
    }

    private var clearQuestion: String {
        let count = completedTasks.count
        return "Move \(count) completed \(count == 1 ? "task" : "tasks") to Recently Deleted?"
    }

    @ViewBuilder
    private func completedSection(now: Date) -> some View {
        if !completedTasks.isEmpty {
            HStack(spacing: 6) {
                Text("\(completedTasks.count) Completed")
                Text("•")
                Button("Clear") { confirmClear = true }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    // On the button, so on iPhone the dialog points at it rather than the top of the screen.
                    .confirmationDialog(clearQuestion, isPresented: $confirmClear, titleVisibility: .visible) {
                        Button("Clear", role: .destructive) {
                            for task in completedTasks { task.moveToTrash() }
                        }
                    }
                Spacer()
                Button(showCompleted ? "Hide" : "Show") {
                    withAnimation { showCompleted.toggle() }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .padding(.top, 12)

            if showCompleted {
                ForEach(completedTasks) { task in
                    TaskRow(task: task, ranked: nil, now: now, focus: $rowFocus,
                            inspecting: inspectingBinding(task)) { openDetails(task) }
                }
            }
        }
    }
}

/// The always-present "New Task" row at the bottom of the list, like Reminders.
struct NewTaskRow: View {
    @Environment(\.modelContext) private var context
    var focused: FocusState<Bool>.Binding
    var onAdd: (TaskItem) -> Void
    @State private var title = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
            TextField("New Task", text: $title)
                .focused(focused)
                .onSubmit(add)
                .submitLabel(.done)
                .textFieldStyle(.plain)
        }
        .cardRow()
    }

    private func add() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let task = TaskItem(title: trimmed)
        context.insert(task)
        title = ""
        onAdd(task)
        focused.wrappedValue = true
    }
}
