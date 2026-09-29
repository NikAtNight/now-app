import NowCore
import SwiftData
import SwiftUI

/// Completed tasks by day, and Recently Deleted with restore. Deleted tasks are purged after 30 days.
struct HistoryView: View {
    enum Page: String, CaseIterable {
        case completed = "Completed"
        case deleted = "Recently Deleted"
    }

    static let retentionDays = 30

    @Environment(\.modelContext) private var context

    @Query(filter: TaskItem.completedPredicate, sort: [SortDescriptor(\TaskItem.completedAt, order: .reverse)])
    private var completed: [TaskItem]

    @Query(filter: TaskItem.trashedPredicate, sort: [SortDescriptor(\TaskItem.deletedAt, order: .reverse)])
    private var deleted: [TaskItem]

    @State private var page = Page.completed
    @State private var confirmEmpty = false

    var body: some View {
        GlassSheet(title: "History") {
            List {
                Picker("Show", selection: $page) {
                    ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                switch page {
                case .completed: completedPage
                case .deleted: deletedPage
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .confirmationDialog("Delete \(deleted.count) tasks for good?", isPresented: $confirmEmpty) {
            Button("Delete for Good", role: .destructive) {
                for task in deleted { context.delete(task) }
            }
        }
    }

    @ViewBuilder
    private var completedPage: some View {
        if completed.isEmpty {
            empty("Nothing completed yet.")
        }
        let days = Dictionary(grouping: completed) { Calendar.current.startOfDay(for: $0.completedAt ?? .distantPast) }
        ForEach(days.keys.sorted(by: >), id: \.self) { day in
            Section {
                ForEach(days[day] ?? []) { task in
                    HistoryRow(task: task) {
                        Text(task.completedAt ?? .now, format: .dateTime.hour().minute())
                    }
                    .swipeActions {
                        Button(role: .destructive) { task.moveToTrash() } label: { Label("Delete", systemImage: "trash") }
                    }
                    .contextMenu {
                        Button("Mark as Not Done") { task.status = .todo }
                        Button("Delete", role: .destructive) { task.moveToTrash() }
                    }
                }
            } header: {
                Text(day, format: .dateTime.weekday(.wide).month().day())
            }
        }
    }

    @ViewBuilder
    private var deletedPage: some View {
        if deleted.isEmpty {
            empty("Nothing deleted.")
        } else {
            HStack {
                Text("Tasks are deleted for good after \(Self.retentionDays) days.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Empty", role: .destructive) { confirmEmpty = true }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        ForEach(deleted) { task in
            HistoryRow(task: task) {
                Text(daysLeft(task))
            }
            .swipeActions(edge: .leading) {
                Button { task.restore() } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                    .tint(.accentColor)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { context.delete(task) } label: { Label("Delete Now", systemImage: "trash") }
            }
            .contextMenu {
                Button("Restore") { task.restore() }
                Button("Delete Now", role: .destructive) { context.delete(task) }
            }
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func daysLeft(_ task: TaskItem) -> String {
        let deletedDay = Calendar.current.startOfDay(for: task.deletedAt ?? .now)
        let elapsed = Calendar.current.dateComponents([.day], from: deletedDay, to: Calendar.current.startOfDay(for: .now)).day ?? 0
        let left = max(Self.retentionDays - elapsed, 0)
        return left == 1 ? "1 day left" : "\(left) days left"
    }

    /// Removes tasks that have been in Recently Deleted longer than the retention period.
    /// Returns whether anything was removed.
    static func purgeExpired(in context: ModelContext, now: Date = .now) -> Bool {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) else { return false }
        let expired = FetchDescriptor<TaskItem>(predicate: #Predicate { task in
            task.deletedAt != nil && task.deletedAt! < cutoff
        })
        let tasks = (try? context.fetch(expired)) ?? []
        for task in tasks { context.delete(task) }
        return !tasks.isEmpty
    }
}

/// A read-only task line for History: a status glyph, priority, title, and a trailing detail.
private struct HistoryRow<Detail: View>: View {
    @Bindable var task: TaskItem
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if task.isTrashed {
                Image(systemName: "trash").foregroundStyle(.secondary)
            } else {
                // Tapping the filled circle reopens the task, like Reminders.
                Button { task.status = .todo } label: {
                    Image(systemName: "largecircle.fill.circle").foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Mark as not done")
            }
            PriorityIcon(priority: task.priority)
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .foregroundStyle(task.isTrashed ? .secondary : .primary)
                .lineLimit(2)
            Spacer()
            detail
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .cardRow()
    }
}
