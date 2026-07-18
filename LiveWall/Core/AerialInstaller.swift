import AppKit
import AVFoundation

/// This is the trick that gets LiveWall's video its own real section in
/// System Settings, instead of being buried under "Other" like a normal
/// third-party screen saver. macOS treats certain wallpaper videos as
/// "aerials" — Apple's own rotating scenery wallpapers — and keeps a
/// manifest of what's available. Add our own entry to that manifest and
/// the system treats our video exactly like one of its own: it shows up
/// as a proper "LiveWall" section under both Wallpaper and Screen Saver,
/// and picking it there also puts it on the lock screen.
///
/// None of this is documented or supported by Apple — we found it by
/// poking around `~/Library/Application Support/com.apple.wallpaper/aerials`
/// and reverse engineering the manifest format. Everything we touch is
/// user-owned, nothing needs admin rights, and we only ever add or remove
/// our own entries, never anyone else's. We also keep a backup of the
/// manifest the first time we touch it, just in case. If a macOS update
/// changes the format and wipes our entry, turning the toggle off and
/// back on just re-registers it.
enum AerialInstaller {
    /// Fixed IDs, not randomly generated ones — so swapping in a new video
    /// doesn't invalidate whatever the user already picked in System Settings.
    static let categoryID = "F1FE0000-0000-4000-8000-000000000001"
    static let subcategoryID = "F1FE0000-0000-4000-8000-000000000002"
    static let assetID = "F1FE0000-0000-4000-8000-000000000003"

    private static let sectionName = "LiveWall"
    private static let sectionDescription = "Video added by the LiveWall app"

    private static var aerialsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/com.apple.wallpaper/aerials",
            isDirectory: true
        )
    }

    private static var manifestURL: URL {
        aerialsRoot.appendingPathComponent("manifest/entries.json")
    }

    private static var videosDirectory: URL {
        aerialsRoot.appendingPathComponent("videos", isDirectory: true)
    }

    private static var thumbnailsDirectory: URL {
        aerialsRoot.appendingPathComponent("thumbnails", isDirectory: true)
    }

    private static var backupURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/LiveWall/entries.json.original"
        )
    }

    /// Where the wallpaper system keeps the current selection — which
    /// wallpaper and screen saver are actually active right now. A separate
    /// file from the manifest: the manifest is the menu, this is the order.
    private static var indexPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/com.apple.wallpaper/Store/Index.plist"
        )
    }

    private static var indexBackupURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/LiveWall/Index.plist.original"
        )
    }

    /// Older versions of macOS keep aerials in a root-owned system
    /// directory instead of this per-user store, so the whole trick only
    /// works where the store exists.
    static var isSupported: Bool {
        FileManager.default.fileExists(atPath: manifestURL.path)
    }

    static var isInstalled: Bool {
        guard let manifest = try? loadManifest(),
              let categories = manifest["categories"] as? [[String: Any]] else {
            return false
        }
        return categories.contains { ($0["id"] as? String) == categoryID }
    }

    static func install(videoURL: URL, displayName: String) async throws {
        var manifest = try loadManifest()
        try backUpManifestIfNeeded()

        var (categories, assets) = strippingLiveWallEntries(from: manifest)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: videosDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)

        // On the same APFS volume this is an instant clone, not a real
        // copy, so even huge videos register right away.
        let videoDestination = videosDirectory.appendingPathComponent("\(assetID).mov")
        try? fileManager.removeItem(at: videoDestination)
        try fileManager.copyItem(at: videoURL, to: videoDestination)

        let thumbnailDestination = thumbnailsDirectory.appendingPathComponent("\(assetID).png")
        try await writeThumbnail(for: videoURL, to: thumbnailDestination)

        let thumbnail = thumbnailDestination.absoluteString
        let shotID = "CUSTOM_" + assetID.replacingOccurrences(of: "-", with: "_")

        let asset: [String: Any] = [
            "id": assetID,
            "categories": [categoryID],
            "subcategories": [subcategoryID],
            "shotID": shotID,
            "pointsOfInterest": ["0": "\(shotID)_0"],
            "includeInShuffle": false,
            "previewImage": thumbnail,
            "accessibilityLabel": displayName,
            "preferredOrder": 0,
            "localizedNameKey": displayName,
            "url-4K-SDR-240FPS": videoDestination.absoluteString,
            "showInTopLevel": true,
        ]

        let category: [String: Any] = [
            "id": categoryID,
            "localizedNameKey": sectionName,
            "localizedDescriptionKey": sectionDescription,
            "previewImage": thumbnail,
            "preferredOrder": 1,
            "representativeAssetID": assetID,
            "subcategories": [[
                "id": subcategoryID,
                "localizedNameKey": sectionName,
                "localizedDescriptionKey": sectionDescription,
                "previewImage": thumbnail,
                "preferredOrder": 0,
                "representativeAssetID": assetID,
            ]],
        ]

        assets.append(asset)
        categories.append(category)
        manifest["assets"] = assets
        manifest["categories"] = categories
        try writeManifest(manifest)

        // Registering makes the video available; this makes it the actual
        // active wallpaper and screen saver, so nobody has to go pick it
        // in System Settings by hand.
        try makeActiveSelection()

        refreshWallpaperAgent()
    }

    /// Writes the LiveWall aerial into the selection store — the same
    /// result as clicking its tile in System Settings, minus the trip to
    /// System Settings. Each section of the file carries a tiny embedded
    /// plist naming the chosen asset; "Desktop" is the wallpaper and
    /// "Idle" is the screen saver.
    private static func makeActiveSelection() throws {
        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID], format: .binary, options: 0
        )
        let optionValues = try PropertyListSerialization.data(
            fromPropertyList: ["values": [String: Any]()], format: .binary, options: 0
        )
        let content: [String: Any] = [
            "Choices": [[
                "Provider": "com.apple.wallpaper.choice.aerials",
                "Files": [Any](),
                "Configuration": configuration,
            ]],
            "Shuffle": "$null",
            "EncodedOptionValues": optionValues,
        ]
        let now = Date()
        let group: [String: Any] = [
            "Desktop": ["Content": content, "LastSet": now, "LastUse": now],
            "Idle": ["Content": content, "LastSet": now, "LastUse": now],
            "Type": "individual",
        ]

        // Start from the existing file so per-display and per-Space setups
        // the user has made are left alone, and keep a copy of the
        // original the first time we ever touch it.
        var index: [String: Any] = [:]
        if let data = try? Data(contentsOf: indexPlistURL),
           let existing = try? PropertyListSerialization.propertyList(
               from: data, options: [], format: nil
           ) as? [String: Any] {
            index = existing
            if !FileManager.default.fileExists(atPath: indexBackupURL.path) {
                try? FileManager.default.createDirectory(
                    at: indexBackupURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: indexBackupURL)
            }
        }
        index["AllSpacesAndDisplays"] = group
        index["SystemDefault"] = group
        if index["Displays"] == nil { index["Displays"] = [String: Any]() }
        if index["Spaces"] == nil { index["Spaces"] = [String: Any]() }

        let data = try PropertyListSerialization.data(
            fromPropertyList: index, format: .binary, options: 0
        )
        try FileManager.default.createDirectory(
            at: indexPlistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: indexPlistURL, options: .atomic)
    }

    static func uninstall() throws {
        var manifest = try loadManifest()
        let (categories, assets) = strippingLiveWallEntries(from: manifest)
        manifest["assets"] = assets
        manifest["categories"] = categories
        try writeManifest(manifest)
        refreshWallpaperAgent()
    }

    static func openWallpaperSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"),
           NSWorkspace.shared.open(url) {
            return
        }
        if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Manifest plumbing

    private static func loadManifest() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw NSError(domain: "LiveWall", code: 2, userInfo: [
                NSLocalizedDescriptionKey:
                    "This macOS version doesn't have the per-user wallpaper store LiveWall knows how to extend.",
            ])
        }
        let data = try Data(contentsOf: manifestURL)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "LiveWall", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Unrecognized wallpaper manifest format.",
            ])
        }
        return object
    }

    private static func writeManifest(_ manifest: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func backUpManifestIfNeeded() throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        try fileManager.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(at: manifestURL, to: backupURL)
    }

    /// Strips out LiveWall's category and asset entries (and deletes their
    /// copied files), without touching anything Apple or another app added.
    private static func strippingLiveWallEntries(
        from manifest: [String: Any]
    ) -> (categories: [[String: Any]], assets: [[String: Any]]) {
        var categories = manifest["categories"] as? [[String: Any]] ?? []
        var assets = manifest["assets"] as? [[String: Any]] ?? []

        categories.removeAll { ($0["id"] as? String) == categoryID }

        let ours = assets.filter { (($0["categories"] as? [String]) ?? []).contains(categoryID) }
        assets.removeAll { (($0["categories"] as? [String]) ?? []).contains(categoryID) }

        let fileManager = FileManager.default
        for asset in ours {
            guard let id = asset["id"] as? String else { continue }
            try? fileManager.removeItem(at: videosDirectory.appendingPathComponent("\(id).mov"))
            try? fileManager.removeItem(at: thumbnailsDirectory.appendingPathComponent("\(id).png"))
        }
        return (categories, assets)
    }

    private static func writeThumbnail(for videoURL: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 900, height: 900)

        var cgImage: CGImage?
        for time in [CMTime(seconds: 1, preferredTimescale: 600), .zero] {
            if let (image, _) = try? await generator.image(at: time) {
                cgImage = image
                break
            }
        }
        guard let cgImage else {
            throw NSError(domain: "LiveWall", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't generate a preview image from the video.",
            ])
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "LiveWall", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Couldn't encode the preview image.",
            ])
        }
        try png.write(to: destination)
    }

    /// WallpaperAgent holds the manifest in memory, so a plain file edit
    /// isn't enough on its own — killing it forces a restart (it relaunches
    /// on its own) and that's what makes System Settings and the lock
    /// screen actually notice the change.
    private static func refreshWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        try? process.run()
        process.waitUntilExit()
    }
}
