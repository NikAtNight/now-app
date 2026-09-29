import AppIntents
import Foundation
import SwiftData
import WidgetKit

/// Marks a task done from a widget or a timer Live Activity without opening the app.
/// On iPhone it's a Live Activity intent, so it runs in the app's process and the app can end the
/// timer's alert and Live Activity. On Mac it runs in the widget's process and opens the store itself.
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Task"
    static let isDiscoverable = false

    @Parameter(title: "Task ID")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskID) else { return .result() }
        let context = try SharedStore.appContainer?.mainContext ?? ModelContext(SharedStore.makeContainer(cloudKit: false))
        var descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        // A stale widget can still show a task that was deleted or already done since.
        if let task = try context.fetch(descriptor).first, !task.isDone, !task.isTrashed {
            task.status = .done
            try context.save()
        }
        await SharedStore.afterIntentChange?()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

#if os(iOS)
extension CompleteTaskIntent: LiveActivityIntent {}
#endif
