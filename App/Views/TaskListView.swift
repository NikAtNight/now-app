import NowCore
import SwiftData
import SwiftUI

/// The one screen: what needs you now, with everything else a tap away.
struct TaskListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @Query(filter: #Predicate<TaskItem> { $0.statusRaw != "done" })
    private var openTasks: [TaskItem]

    @Query(filter: #Predicate<TaskItem> { $0.statusRaw == "done" }, sort: [SortDescriptor(\TaskItem.completedAt, order: .reverse)])
    private var completedTasks: [TaskItem]

    @State private var showHidden = false
    @State private var showCompleted = false
    @State private var confirmClear = false
    @State private var editing: TaskItem?
    /// Tasks added this session stay visible so they don't vanish into the hidden list before you date them.
    @State private var justAdded: [UUID] = []
    @FocusState private var newTaskFocused: Bool
    #if os(iOS)
    @State private var showSettings = false
    #endif

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            content(now: timeline.date)
        }
        .navigationTitle("Now")
        #if os(macOS)
        .navigationSubtitle(Text("Only what needs you"))
        #endif
        .toolbar { toolbar }
        .sheet(item: $editing) { task in
            NavigationStack { TaskDetailView(task: task) }
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar { Button("Done") { showSettings = false } }
            }
        }
        #endif
        .confirmationDialog("Delete \(completedTasks.count) completed tasks?", isPresented: $confirmClear) {
            Button("Delete", role: .destructive) {
                for task in completedTasks { context.delete(task) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTaskRequested)) { _ in
            newTaskFocused = true
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { newTaskFocused = true } label: { Label("New Task", systemImage: "plus") }
        }
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        }
        #endif
    }

    private func content(now: Date) -> some View {
        let ranking = Ranker.rank(openTasks.map(\.snapshot), now: now, settings: settings.ranking)
        let items = Dictionary(openTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let focusIDs = Set(ranking.focus.map(\.id))
        let recent = justAdded.filter { !focusIDs.contains($0) }.compactMap { id in ranking.hidden.first { $0.id == id } }
        let recentIDs = Set(recent.map(\.id))
        let hidden = ranking.hidden.filter { !recentIDs.contains($0.id) }

        return List {
            summary(hiddenCount: hidden.count, overflow: ranking.urgentOverflow)

            if ranking.focus.isEmpty && recent.isEmpty {
                Text("Nothing needs you right now.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }

            rows(ranking.focus, items: items, now: now)

            if !recent.isEmpty {
                Section("Just Added") { rows(recent, items: items, now: now) }
            }

            if showHidden && !hidden.isEmpty {
                Section("Later") { rows(hidden, items: items, now: now) }
            }

            NewTaskRow(focused: $newTaskFocused) { task in
                justAdded.append(task.id)
            }

            completedSection(now: now)
        }
        .listStyle(.plain)
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
                .buttonStyle(.borderless)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func rows(_ ranked: [RankedTask], items: [UUID: TaskItem], now: Date) -> some View {
        ForEach(ranked) { item in
            if let task = items[item.id] {
                TaskRow(task: task, ranked: item, now: now) { editing = task }
            }
        }
    }

    @ViewBuilder
    private func completedSection(now: Date) -> some View {
        if !completedTasks.isEmpty {
            HStack(spacing: 6) {
                Text("\(completedTasks.count) Completed")
                Text("•")
                Button("Clear") { confirmClear = true }
                    .buttonStyle(.borderless)
                Spacer()
                Button(showCompleted ? "Hide" : "Show") {
                    withAnimation { showCompleted.toggle() }
                }
                .buttonStyle(.borderless)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .padding(.top, 12)

            if showCompleted {
                ForEach(completedTasks) { task in
                    TaskRow(task: task, ranked: nil, now: now) { editing = task }
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
        }
        .listRowSeparator(.hidden)
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
