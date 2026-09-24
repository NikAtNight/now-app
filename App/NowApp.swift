import NowCore
import SwiftData
import SwiftUI

@main
struct NowApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings

    init() {
        let schema = Schema([TaskItem.self, Subtask.self])
        // .automatic syncs through the CloudKit container in the entitlements, and stays local without one.
        let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
        do {
            container = try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not open the task store: \(error)")
        }
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        NotificationService.shared.configure(container: container, settings: settings)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
        }
        .modelContainer(container)
        .environment(settings)
        #if os(macOS)
        .defaultSize(width: 520, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") { NotificationCenter.default.post(name: .newTaskRequested, object: nil) }
                    .keyboardShortcut("n")
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .frame(width: 460)
                .environment(settings)
        }

        MenuBarExtra("Now", systemImage: "checklist") {
            MenuBarView()
                .modelContainer(container)
                .environment(settings)
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

extension Notification.Name {
    static let newTaskRequested = Notification.Name("NowNewTaskRequested")
}

/// Keeps notifications in step with the data. Lives above the list so it runs on every platform.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Query private var tasks: [TaskItem]
    @State private var activations = 0

    var body: some View {
        NavigationStack {
            TaskListView()
        }
        .task { await NotificationService.shared.requestAuthorization() }
        .task(id: syncKey) {
            await NotificationService.shared.sync(tasks: tasks.map(\.snapshot), settings: settings)
        }
        .onChange(of: scenePhase) { _, phase in
            // Pending notifications are capped, so re-plan whenever the app comes back.
            if phase == .active { activations += 1 }
        }
    }

    private struct SyncKey: Equatable {
        let tasks: [TaskSnapshot]
        let ranking: RankingSettings
        let notifications: NotificationSettings
        let notifyHere: Bool
        let activations: Int
    }

    private var syncKey: SyncKey {
        SyncKey(
            tasks: tasks.map(\.snapshot),
            ranking: settings.ranking,
            notifications: settings.notifications,
            notifyHere: settings.notifyOnThisDevice,
            activations: activations
        )
    }
}
