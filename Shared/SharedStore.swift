import Foundation

public enum WidgetKind {
    public static let arc = "ArcWidget"
}

public enum SharedStore {
    private static let key = "arc.snapshot"
    private static let fileName = "arc-snapshot.json"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static let groupDefaults = UserDefaults(suiteName: AppGroup.identifier)
    private static let groupContainer = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AppGroup.identifier
    )

    public static var isAppGroupAvailable: Bool {
        groupContainer != nil
    }

    public static func load() -> ArcSnapshot? {
        if let data = try? Data(contentsOf: snapshotURL()),
           let snapshot = try? decoder.decode(ArcSnapshot.self, from: data) {
            return snapshot
        }
        if let data = groupDefaults?.data(forKey: key) {
            return try? decoder.decode(ArcSnapshot.self, from: data)
        }
        return nil
    }

    public static func save(_ snapshot: ArcSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        let url = snapshotURL()
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
        groupDefaults?.set(data, forKey: key)
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: snapshotURL())
        groupDefaults?.removeObject(forKey: key)
    }

    public static func containerURL() -> URL? {
        groupContainer
    }

    private static func snapshotURL() -> URL {
        if let container = groupContainer {
            return container.appendingPathComponent(fileName)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }
}
