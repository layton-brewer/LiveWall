import AppKit

/// Handles installing and removing the bundled screen saver module, and
/// keeps a copy of the wallpaper video somewhere the sandboxed screen
/// saver process (legacyScreenSaver) is actually allowed to read from.
enum SaverInstaller {
    static let saverFileName = "LiveWallSaver.saver"

    private static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    static var installedSaverURL: URL {
        home.appendingPathComponent("Library/Screen Savers/\(saverFileName)")
    }

    static var bundledSaverURL: URL? {
        Bundle.main.url(forResource: "LiveWallSaver", withExtension: "saver")
    }

    /// Application Support inside the legacyScreenSaver sandbox — the one
    /// place we can be sure the saver process is allowed to read from.
    static var saverDataDirectory: URL {
        home.appendingPathComponent(
            "Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/LiveWall",
            isDirectory: true
        )
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedSaverURL.path)
    }

    static func install() throws {
        guard let bundled = bundledSaverURL else {
            throw NSError(domain: "LiveWall", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "The screen saver module is missing from the app bundle.",
            ])
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: installedSaverURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: installedSaverURL.path) {
            try fileManager.removeItem(at: installedSaverURL)
        }
        try fileManager.copyItem(at: bundled, to: installedSaverURL)
    }

    static func uninstall() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: installedSaverURL.path) {
            try fileManager.removeItem(at: installedSaverURL)
        }
        // Also clean up the video copy and config file we placed in the
        // saver's sandbox container.
        if fileManager.fileExists(atPath: saverDataDirectory.path) {
            try fileManager.removeItem(at: saverDataDirectory)
        }
    }

    /// Copies the video into the saver's sandbox container and updates the
    /// config to point at it. If it's on the same APFS volume the copy is
    /// basically instant (a clone, not a real copy); either way this runs
    /// on a background queue so a big cross-volume copy won't hang the app.
    static func syncVideoInBackground(_ url: URL) {
        DispatchQueue.global(qos: .utility).async {
            do {
                try syncVideo(url)
            } catch {
                NSLog("LiveWall: failed to sync screen saver video: \(error)")
            }
        }
    }

    static func syncVideo(_ url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: saverDataDirectory, withIntermediateDirectories: true)
        let destination = saverDataDirectory.appendingPathComponent(url.lastPathComponent)

        // Clear out whatever video was synced here before.
        let movieExtensions: Set<String> = ["mov", "mp4", "m4v"]
        let existing = (try? fileManager.contentsOfDirectory(
            at: saverDataDirectory, includingPropertiesForKeys: nil
        )) ?? []
        for file in existing
        where movieExtensions.contains(file.pathExtension.lowercased())
            && file.lastPathComponent != destination.lastPathComponent {
            try? fileManager.removeItem(at: file)
        }

        let sourceSize = (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? UInt64
        let destinationSize = (try? fileManager.attributesOfItem(atPath: destination.path))?[.size] as? UInt64
        if sourceSize == nil || sourceSize != destinationSize {
            try? fileManager.removeItem(at: destination)
            try fileManager.copyItem(at: url, to: destination)
        }

        let config = ["video": destination.lastPathComponent]
        let data = try JSONSerialization.data(withJSONObject: config)
        try data.write(to: saverDataDirectory.appendingPathComponent("saver.json"))
    }

    static func openScreenSaverSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }
}
