import Foundation
import NowCore
import Observation
#if os(macOS)
import AppKit
#endif

/// Ranking and notification preferences sync through iCloud key-value storage.
/// "Notify on this device", appearance, and priority icons stay local so Mac and iPhone can differ.
@MainActor
@Observable
final class AppSettings {
    var ranking: RankingSettings {
        didSet {
            guard ranking != oldValue else { return }
            Self.save(ranking, key: Keys.ranking)
            shareWithWidgets()
            // Here rather than in a view, so it happens on Mac with no window open too.
            Refresher.shared.refresh()
        }
    }

    var notifications: NotificationSettings {
        didSet {
            guard notifications != oldValue else { return }
            Self.save(notifications, key: Keys.notifications)
            Refresher.shared.refresh()
        }
    }

    var notifyOnThisDevice: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnThisDevice, forKey: Keys.notifyHere)
            Refresher.shared.refresh()
        }
    }

    var appearance: Appearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Keys.appearance)
            applyAppearance()
        }
    }

    var priorityStyle: PriorityStyle {
        didSet {
            UserDefaults.standard.set(priorityStyle.rawValue, forKey: Keys.priorityStyle)
            shareWithWidgets()
            // Reloads the widgets, which draw the same icons.
            Refresher.shared.refresh()
        }
    }

    #if os(macOS)
    var dockIcon: DockIconMode {
        didSet {
            UserDefaults.standard.set(dockIcon.rawValue, forKey: Keys.dockIcon)
            DockIconController.shared.setMode(dockIcon)
        }
    }

    var showInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showInMenuBar, forKey: Keys.showInMenuBar) }
    }

    var quickAddShortcut: QuickAddShortcut {
        didSet {
            UserDefaults.standard.set(quickAddShortcut.rawValue, forKey: Keys.quickAddShortcut)
            QuickAddController.shared.register(quickAddShortcut)
        }
    }
    #endif

    @ObservationIgnored private var cloudObserver: NSObjectProtocol?

    private enum Keys {
        static let ranking = "settings.ranking.v1"
        static let notifications = "settings.notifications.v1"
        static let notifyHere = "settings.notifyOnThisDevice"
        static let appearance = "settings.appearance"
        static let priorityStyle = "settings.priorityStyle"
        static let quickAddShortcut = "settings.quickAddShortcut"
        static let dockIcon = "settings.dockIcon"
        static let showInMenuBar = "settings.showInMenuBar"
    }

    init() {
        NSUbiquitousKeyValueStore.default.synchronize()
        ranking = Self.load(Keys.ranking) ?? RankingSettings()
        notifications = Self.load(Keys.notifications) ?? NotificationSettings()
        notifyOnThisDevice = UserDefaults.standard.object(forKey: Keys.notifyHere) as? Bool ?? true
        appearance = UserDefaults.standard.string(forKey: Keys.appearance).flatMap(Appearance.init(rawValue:)) ?? .system
        priorityStyle = UserDefaults.standard.string(forKey: Keys.priorityStyle).flatMap(PriorityStyle.init(rawValue:)) ?? .bars
        #if os(macOS)
        quickAddShortcut = UserDefaults.standard.string(forKey: Keys.quickAddShortcut).flatMap(QuickAddShortcut.init(rawValue:)) ?? .controlOptionSpace
        dockIcon = UserDefaults.standard.string(forKey: Keys.dockIcon).flatMap(DockIconMode.init(rawValue:)) ?? .whileWindowOpen
        showInMenuBar = UserDefaults.standard.object(forKey: Keys.showInMenuBar) as? Bool ?? true
        #endif
        applyAppearance()
        shareWithWidgets()

        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadFromCloud() }
        }
    }

    /// Widgets rank and draw tasks with the same settings, read from the App Group.
    private func shareWithWidgets() {
        SharedStore.defaults.set(try? JSONEncoder().encode(ranking), forKey: SharedStore.Keys.ranking)
        SharedStore.defaults.set(priorityStyle.rawValue, forKey: SharedStore.Keys.priorityStyle)
    }

    /// On Mac the appearance is app-wide, so it applies with or without a main window open.
    /// iOS applies it per scene with `preferredColorScheme`.
    private func applyAppearance() {
        #if os(macOS)
        NSApplication.shared.appearance = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        #endif
    }

    private func reloadFromCloud() {
        if let remote: RankingSettings = Self.load(Keys.ranking), remote != ranking { ranking = remote }
        if let remote: NotificationSettings = Self.load(Keys.notifications), remote != notifications { notifications = remote }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        let data = NSUbiquitousKeyValueStore.default.data(forKey: key) ?? UserDefaults.standard.data(forKey: key)
        return data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NSUbiquitousKeyValueStore.default.set(data, forKey: key)
    }
}

enum Appearance: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
