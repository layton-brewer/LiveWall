import Foundation

/// Everything LiveWall remembers about one display. Keyed by the display's
/// hardware UUID elsewhere, so this survives relaunches, restarts, and
/// unplugging/replugging the monitor. The trim values are optional on
/// purpose — nil means "play the whole file", and it also keeps settings
/// saved by older versions decoding cleanly.
struct StoredAssignment: Codable {
    var bookmark: Data
    var scaling: ScalingMode
    var muted: Bool
    var volume: Float
    var trimStart: Double?
    var trimEnd: Double?
}

struct StoredSettings: Codable {
    var assignments: [String: StoredAssignment] = [:]
    var pauseOnBattery: Bool = false
    var pauseOnLowPower: Bool = true

    private enum CodingKeys: String, CodingKey {
        case assignments
        case pauseOnBattery
        case pauseOnLowPower
    }

    init() {}

    // Hand-written so settings saved before a field existed still load —
    // synthesized decoding would throw on the missing key and silently
    // wipe everyone's assignments on update.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assignments = try container.decodeIfPresent(
            [String: StoredAssignment].self, forKey: .assignments
        ) ?? [:]
        pauseOnBattery = try container.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? false
        pauseOnLowPower = try container.decodeIfPresent(Bool.self, forKey: .pauseOnLowPower) ?? true
    }
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
