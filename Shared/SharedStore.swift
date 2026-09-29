import Foundation
import NowCore
import SwiftData

/// The task store and the few settings the app shares with its widgets, both in the App Group.
enum SharedStore {
    /// macOS sandboxed apps can use a team-prefixed group without registering it; iOS needs the "group." form.
    #if os(macOS)
    static let groupID = "2TG5HP8NSV.com.talix.now"
    #else
    static let groupID = "group.com.talix.now"
    #endif

    static let schema = Schema([TaskItem.self, Subtask.self])

    /// Set by the app at launch. Intents running in the app's process use this container rather
    /// than opening a second one, then call `afterIntentChange` so notifications and Live Activities
    /// catch up before the app is suspended again.
    @MainActor static var appContainer: ModelContainer?
    @MainActor static var afterIntentChange: (() async -> Void)?

    /// Settings the widget needs to rank and draw tasks the same way as the app.
    static let defaults = UserDefaults(suiteName: groupID) ?? .standard

    enum Keys {
        static let ranking = "settings.ranking.v1"
        static let priorityStyle = "settings.priorityStyle"
    }

    private static var groupDirectory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }

    enum StoreError: Error {
        /// The widget only opens a store the app has already created (and migrated).
        case notCreatedYet
    }

    /// Opens the shared store. The app syncs it through CloudKit and is the only one that creates or
    /// migrates it. Widgets open it without CloudKit, only to read it or mark tasks done, and the app
    /// exports those changes on its next run.
    static func makeContainer(cloudKit: Bool) throws -> ModelContainer {
        guard let directory = groupDirectory else {
            // No App Group entitlement (for example an unsigned build): fall back to the app's own store.
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: cloudKit ? .automatic : .none)
            return try ModelContainer(for: schema, configurations: configuration)
        }
        let url = directory.appending(path: "Podium.store")
        if cloudKit {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try migrateLegacyStore(to: url)
            } catch {
                // Keep working from the untouched original this run; the migration retries next launch.
                let legacy = URL.applicationSupportDirectory.appending(path: "default.store")
                let configuration = ModelConfiguration(schema: schema, url: legacy, cloudKitDatabase: .automatic)
                return try ModelContainer(for: schema, configurations: configuration)
            }
        } else if !FileManager.default.fileExists(atPath: url.path) {
            // Creating it here would make the app think migration already happened.
            throw StoreError.notCreatedYet
        }
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: cloudKit ? .automatic : .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// Before widgets, the store lived in the app's own Application Support as default.store.
    /// Copies it (with its WAL and SHM files) into the group under temporary names, then renames the
    /// database file into place last. If anything fails or the app dies partway, the destination
    /// doesn't exist yet, so the next launch starts over from the untouched original.
    private static func migrateLegacyStore(to url: URL) throws {
        let fileManager = FileManager.default
        let legacy = URL.applicationSupportDirectory.appending(path: "default.store")
        guard !fileManager.fileExists(atPath: url.path), fileManager.fileExists(atPath: legacy.path) else { return }
        let suffixes = ["-wal", "-shm", ""] // the database itself last
        let staging = url.deletingLastPathComponent().appending(path: "Podium-migrating.store")
        func file(_ base: URL, _ suffix: String) -> URL { URL(fileURLWithPath: base.path + suffix) }

        for suffix in suffixes {
            try? fileManager.removeItem(at: file(staging, suffix))
            try? fileManager.removeItem(at: file(url, suffix))
        }
        for suffix in suffixes where fileManager.fileExists(atPath: file(legacy, suffix).path) {
            try fileManager.copyItem(at: file(legacy, suffix), to: file(staging, suffix))
        }
        for suffix in suffixes where fileManager.fileExists(atPath: file(staging, suffix).path) {
            try fileManager.moveItem(at: file(staging, suffix), to: file(url, suffix))
        }
        // Only now is the new store complete; the old one can go.
        for suffix in suffixes { try? fileManager.removeItem(at: file(legacy, suffix)) }
    }

    static var ranking: RankingSettings {
        defaults.data(forKey: Keys.ranking).flatMap { try? JSONDecoder().decode(RankingSettings.self, from: $0) } ?? RankingSettings()
    }

    static var priorityStyle: PriorityStyle {
        defaults.string(forKey: Keys.priorityStyle).flatMap(PriorityStyle.init(rawValue:)) ?? .bars
    }
}

/// Links into the app (the `podium` scheme is registered in the Info.plists).
enum PodiumURL {
    static let open = URL(string: "podium://open")!
}
