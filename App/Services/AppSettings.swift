import Foundation
import NowCore
import Observation

/// Ranking and notification preferences sync through iCloud key-value storage.
/// "Notify on this device" stays local so Mac and iPhone can differ.
@MainActor
@Observable
final class AppSettings {
    var ranking: RankingSettings {
        didSet { if ranking != oldValue { Self.save(ranking, key: Keys.ranking) } }
    }

    var notifications: NotificationSettings {
        didSet { if notifications != oldValue { Self.save(notifications, key: Keys.notifications) } }
    }

    var notifyOnThisDevice: Bool {
        didSet { UserDefaults.standard.set(notifyOnThisDevice, forKey: Keys.notifyHere) }
    }

    @ObservationIgnored private var cloudObserver: NSObjectProtocol?

    private enum Keys {
        static let ranking = "settings.ranking.v1"
        static let notifications = "settings.notifications.v1"
        static let notifyHere = "settings.notifyOnThisDevice"
    }

    init() {
        NSUbiquitousKeyValueStore.default.synchronize()
        ranking = Self.load(Keys.ranking) ?? RankingSettings()
        notifications = Self.load(Keys.notifications) ?? NotificationSettings()
        notifyOnThisDevice = UserDefaults.standard.object(forKey: Keys.notifyHere) as? Bool ?? true

        cloudObserver = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadFromCloud() }
        }
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
