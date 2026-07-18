import Foundation

/// Everything LiveWall remembers about one display. Keyed by the display's
/// hardware UUID elsewhere, so this survives relaunches, restarts, and
/// unplugging/replugging the monitor.
struct StoredAssignment: Codable {
    var bookmark: Data
    var scaling: ScalingMode
    var muted: Bool
    var volume: Float
}

struct StoredSettings: Codable {
    var assignments: [String: StoredAssignment] = [:]
    var pauseOnBattery: Bool = false
}

final class SettingsStore {
    private static let key = "LiveWallSettings"
    private let defaults = UserDefaults.standard

    func load() -> StoredSettings {
        guard let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(StoredSettings.self, from: data) else {
            return StoredSettings()
        }
        return settings
    }

    func save(_ settings: StoredSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
