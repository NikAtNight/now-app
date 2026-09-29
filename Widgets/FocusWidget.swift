import AppIntents
import NowCore
import SwiftData
import SwiftUI
import WidgetKit

@main
struct PodiumWidgets: WidgetBundle {
    var body: some Widget {
        FocusWidget()
        #if os(iOS)
        TimerLiveActivity()
        #endif
    }
}

/// The top tasks, ranked exactly like the app's list.
struct FocusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Focus", provider: FocusProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Now")
        .description("The tasks that need you next.")
        #if os(iOS)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
        #else
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        #endif
    }
}

struct FocusEntry: TimelineEntry {
    struct Item: Identifiable {
        let id: UUID
        let title: String
        let priority: Priority
        let due: String?
        let isOverdue: Bool
    }

    let date: Date
    let items: [Item]
    /// Hidden tasks with a date, soonest first: what's coming once the current ones are done.
    let upcoming: [Item]
    let hiddenCount: Int
    let style: PriorityStyle

    static let placeholder = FocusEntry(date: .now, items: [
        Item(id: UUID(), title: "Send the invoice", priority: .high, due: "Today, 13:00", isOverdue: true),
        Item(id: UUID(), title: "Review pull request", priority: .medium, due: "Today, 18:00", isOverdue: false),
        Item(id: UUID(), title: "Book the dentist", priority: .none, due: "Tomorrow", isOverdue: false),
    ], upcoming: [
        Item(id: UUID(), title: "Renew passport", priority: .none, due: "Tomorrow", isOverdue: false),
        Item(id: UUID(), title: "Plan the trip", priority: .low, due: "Friday", isOverdue: false),
    ], hiddenCount: 4, style: .bars)
}

struct FocusProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (FocusEntry) -> Void) {
        completion(context.isPreview ? .placeholder : Self.entry(at: .now, tasks: Self.loadOpenTasks()))
    }

    /// Re-ranks every 15 minutes for two hours, since tasks become urgent or overdue as time passes.
    /// The app also reloads the widget whenever tasks change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusEntry>) -> Void) {
        let now = Date.now
        let end = now.addingTimeInterval(2 * 3600)
        // Read the store once; each entry only re-ranks the same tasks at a later time.
        let tasks = Self.loadOpenTasks()
        var moments = (0..<8).map { now.addingTimeInterval(Double($0) * 15 * 60) }
        // Also redraw the moment a task goes overdue or reaches its start-by time, rather than up
        // to 15 minutes later.
        let ranking = SharedStore.ranking
        for task in tasks {
            guard let due = ranking.effectiveDue(for: task, calendar: .current) else { continue }
            moments += [due, due.addingTimeInterval(-task.estimate)].filter { $0 > now && $0 < end }
        }
        let entries = Set(moments).sorted().map { Self.entry(at: $0, tasks: tasks) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func entry(at date: Date, tasks: [TaskSnapshot]) -> FocusEntry {
        let ranking = Ranker.rank(tasks, now: date, settings: SharedStore.ranking)
        func item(_ ranked: RankedTask) -> FocusEntry.Item {
            FocusEntry.Item(
                id: ranked.id,
                title: ranked.task.title.isEmpty ? "Untitled" : ranked.task.title,
                priority: ranked.task.priority,
                due: ranked.task.dueDate.map { DueLabel.text(for: $0, hasTime: ranked.task.hasDueTime, now: date) },
                isOverdue: ranked.tier == .overdue
            )
        }
        let upcoming = ranking.hidden
            .filter { $0.effectiveDue != nil && $0.tier != .snoozed }
            .sorted { ($0.effectiveDue ?? .distantFuture) < ($1.effectiveDue ?? .distantFuture) }
            .prefix(6)
            .map(item)
        return FocusEntry(date: date, items: ranking.focus.map(item), upcoming: upcoming,
                          hiddenCount: ranking.hidden.count, style: SharedStore.priorityStyle)
    }

    /// Timeline callbacks can run off the main thread, so read through a context made here.
    private static func loadOpenTasks() -> [TaskSnapshot] {
        guard let container = try? SharedStore.makeContainer(cloudKit: false) else { return [] }
        let context = ModelContext(container)
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>(predicate: TaskItem.openPredicate))) ?? []
        return tasks.map(\.snapshot)
    }
}

struct FocusWidgetView: View {
    let entry: FocusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(.fill.tertiary, for: .widget)
            // Clicking anywhere but a circle opens the app. On Mac the app may be running with no
            // window, so an explicit link makes SwiftUI open one.
            .widgetURL(PodiumURL.open)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text(entry.items.first?.title ?? "Nothing needs you")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if entry.items.isEmpty {
                    Text("Nothing needs you").foregroundStyle(.secondary)
                }
                ForEach(entry.items.prefix(3)) { item in
                    Text(item.title).lineLimit(1)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            list
        }
    }

    @ViewBuilder
    private var list: some View {
        switch family {
        case .systemMedium:
            // Now gets most of the width; Upcoming is a narrow glance on the right.
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 10) {
                    nowColumn
                        .frame(width: geometry.size.width * 0.72, alignment: .leading)
                    Divider()
                    compactUpcoming
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 10) {
                nowColumn
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("Upcoming").font(.headline).foregroundStyle(.secondary)
                if entry.upcoming.isEmpty {
                    Text("Nothing scheduled.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(entry.upcoming) { item in
                    upcomingRow(item)
                }
                Spacer(minLength: 0)
            }
        default:
            nowColumn
        }
    }

    /// The medium widget's quarter-width column: small type, titles can wrap.
    private var compactUpcoming: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Upcoming").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if entry.upcoming.isEmpty {
                Text("Nothing scheduled.").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(entry.upcoming.prefix(3)) { item in
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(.caption).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let due = item.due {
                        Text(due).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var nowColumn: some View {
        let limit = family == .systemSmall ? 2 : 3
        return VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            HStack {
                Text("Now").font(.headline).foregroundStyle(.tint)
                Spacer()
                if entry.hiddenCount > 0 && family != .systemMedium {
                    Text("\(entry.hiddenCount) hidden").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if entry.items.isEmpty {
                Spacer()
                Text("Nothing needs you right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.items.prefix(limit)) { item in
                    row(item)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// One line per task, so the large widget fits six: circle, title, date on the right.
    private func upcomingRow(_ item: FocusEntry.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(intent: CompleteTaskIntent(taskID: item.id)) {
                Image(systemName: "circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            priorityGlyph(item.priority)
            Text(item.title).lineLimit(1)
            Spacer(minLength: 6)
            if let due = item.due {
                Text(due).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.subheadline)
    }

    private func row(_ item: FocusEntry.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(intent: CompleteTaskIntent(taskID: item.id)) {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    priorityGlyph(item.priority)
                    Text(item.title).lineLimit(family == .systemSmall ? 2 : 1)
                }
                .font(.subheadline)
                if let due = item.due {
                    Text(due)
                        .font(.caption2)
                        .foregroundStyle(item.isOverdue ? .red : .secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func priorityGlyph(_ priority: Priority) -> some View {
        if priority != .none {
            if let image = entry.style.image(for: priority) {
                image.foregroundStyle(priority.color)
            } else {
                Text(priority.marks).foregroundStyle(priority.color)
            }
        }
    }
}
