import NowCore
import SwiftData
import SwiftUI

@main
struct NowApp: App {
    private let container: ModelContainer
    @State private var settings: AppSettings

    init() {
        do {
            // Syncs through the CloudKit container in the entitlements, and stays local without one.
            container = try SharedStore.makeContainer(cloudKit: true)
        } catch {
            fatalError("Could not open the task store: \(error)")
        }
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        NotificationService.shared.configure(container: container)
        Refresher.shared.start(container: container, settings: settings)
        SharedStore.appContainer = container
        SharedStore.afterIntentChange = { await Refresher.shared.refreshNow() }
        #if os(macOS)
        QuickAddController.shared.start(container: container, shortcut: settings.quickAddShortcut)
        TextInputSettings.install()
        DockIconController.shared.start(mode: settings.dockIcon)
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
        }
        .modelContainer(container)
        .environment(settings)
        #if os(iOS)
        .backgroundTask(.appRefresh(Refresher.backgroundTaskID)) {
            await Refresher.shared.refreshNow()
            await Refresher.scheduleBackgroundRefresh()
        }
        #endif
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

        MenuBarExtra(isInserted: Binding(get: { settings.showInMenuBar }, set: { settings.showInMenuBar = $0 })) {
            MenuBarView()
                .modelContainer(container)
                .environment(settings)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
        #endif
    }
}

#if os(iOS)
extension Appearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
#endif

extension Notification.Name {
    static let newTaskRequested = Notification.Name("NowNewTaskRequested")
}

/// The main window. Side effects like notifications live in `Refresher`, not here, so they keep
/// working with no window open.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            TaskListView()
        }
        #if os(macOS)
        // The same material as the details popover, so the two match and nothing shifts when it opens.
        .containerBackground(.clear, for: .window)
        .background { PopoverMaterial().ignoresSafeArea() }
        #endif
        #if os(iOS)
        .preferredColorScheme(settings.appearance.colorScheme)
        #endif
        // A widget click arrives as podium://open. This window takes it if it's open (rather than
        // SwiftUI opening another); if the Mac app is running with no window, SwiftUI opens one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { _ in
            #if os(macOS)
            // Bring the window up top, not just the app.
            NSApp.activate()
            NSApp.windows.first { $0.isVisible && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
            #endif
        }
        .task { await NotificationService.shared.requestAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            // Pending notifications are capped, so re-plan whenever the app comes back.
            case .active: Refresher.shared.refresh()
            #if os(iOS)
            case .background: Refresher.scheduleBackgroundRefresh()
            #endif
            default: break
            }
        }
    }
}
