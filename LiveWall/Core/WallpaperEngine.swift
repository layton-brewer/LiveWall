import AppKit
import Combine

/// A snapshot of one connected display's state, for the settings UI to render.
struct DisplayState: Identifiable, Equatable {
    let id: String
    let name: String
    let resolutionText: String
    var videoURL: URL?
    var scaling: ScalingMode
    var isMuted: Bool
    var volume: Float
}

/// The brain of the app. Owns one WallpaperScreenController per connected
/// display, saves and restores assignments, and pauses/resumes playback
/// when a display gets covered, the Mac sleeps, or the power source changes.
final class WallpaperEngine: ObservableObject {
    @Published private(set) var displayStates: [DisplayState] = []
    @Published var pauseOnBattery: Bool {
        didSet {
            persist()
            updatePlaybackStates()
        }
    }

    private let store = SettingsStore()
    private var settings: StoredSettings
    private var controllers: [String: WallpaperScreenController] = [:]

    private let powerMonitor = PowerMonitor()
    private var isSystemSleeping = false
    private var isSessionInactive = false
    private var isOnBattery = false
    private var reconcileWorkItem: DispatchWorkItem?
    private var persistWorkItem: DispatchWorkItem?

    init() {
        settings = store.load()
        pauseOnBattery = settings.pauseOnBattery

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil
        )
        workspaceCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        workspaceCenter.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.screensDidSleepNotification, object: nil
        )
        workspaceCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
        // Fast user switching: the desktop window doesn't count as occluded
        // while another user's session is up, so without these the video
        // would keep decoding for a desktop nobody can see.
        workspaceCenter.addObserver(
            self, selector: #selector(sessionResignedActive),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil
        )
        workspaceCenter.addObserver(
            self, selector: #selector(sessionBecameActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil
        )

        isOnBattery = PowerMonitor.isOnBattery()
        powerMonitor.onPowerSourceChanged = { [weak self] onBattery in
            guard let self else { return }
            self.isOnBattery = onBattery
            self.updatePlaybackStates()
        }
        powerMonitor.start()

        reconcile()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Public API (called from the UI)

    func assignVideo(url: URL, to displayKey: String) {
        guard let bookmark = try? Self.makeBookmark(for: url) else { return }
        var assignment = settings.assignments[displayKey]
            ?? StoredAssignment(bookmark: bookmark, scaling: .fill, muted: true, volume: 1.0)
        assignment.bookmark = bookmark
        settings.assignments[displayKey] = assignment
        persist()

        controllers[displayKey]?.load(
            url: url,
            scaling: assignment.scaling,
            muted: assignment.muted,
            volume: assignment.volume
        )
        updatePlaybackStates()
        rebuildDisplayStates()

        // If the screen saver or the native aerial trick is turned on,
        // keep their copies of the video in sync with whatever's now
        // assigned.
        if SaverInstaller.isInstalled, let saverURL = saverVideoURL {
            SaverInstaller.syncVideoInBackground(saverURL)
        }
        if AerialInstaller.isInstalled, let saverURL = saverVideoURL {
            let name = saverURL.deletingPathExtension().lastPathComponent
            Task {
                try? await AerialInstaller.install(videoURL: saverURL, displayName: name)
            }
        }
    }

    /// The video the screen saver should play: the main display's, falling
    /// back to any assigned video.
    var saverVideoURL: URL? {
        if let mainKey = NSScreen.main?.displayKey,
           let url = controllers[mainKey]?.videoURL {
            return url
        }
        return controllers.values.compactMap { $0.videoURL }.first
    }

    func removeVideo(from displayKey: String) {
        settings.assignments.removeValue(forKey: displayKey)
        persist()
        controllers[displayKey]?.clear()
        rebuildDisplayStates()
    }

    func setScaling(_ scaling: ScalingMode, for displayKey: String) {
        guard settings.assignments[displayKey] != nil else { return }
        settings.assignments[displayKey]?.scaling = scaling
        persist()
        controllers[displayKey]?.setScaling(scaling)
        rebuildDisplayStates()
    }

    func setMuted(_ muted: Bool, for displayKey: String) {
        guard settings.assignments[displayKey] != nil else { return }
        settings.assignments[displayKey]?.muted = muted
        persist()
        controllers[displayKey]?.setMuted(muted)
        rebuildDisplayStates()
    }

    func setVolume(_ volume: Float, for displayKey: String) {
        guard settings.assignments[displayKey] != nil else { return }
        settings.assignments[displayKey]?.volume = volume
        // Dragging the volume slider fires this many times a second, and
        // each save means JSON-encoding everything and writing to disk.
        // The player gets the new volume immediately; the save can wait
        // until the slider settles.
        schedulePersist()
        controllers[displayKey]?.setVolume(volume)
        rebuildDisplayStates()
    }

    func shutdown() {
        // Flush any save that's still sitting in the debounce window.
        persist()
        for controller in controllers.values {
            controller.tearDown()
        }
        controllers.removeAll()
    }

    // MARK: - Display reconciliation

    @objc private func screenParametersChanged() {
        // Display-change notifications tend to arrive in a burst, so wait a
        // beat and coalesce them before actually reconciling anything.
        reconcileWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.reconcile() }
        reconcileWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func reconcile() {
        var seen = Set<String>()
        for screen in NSScreen.screens {
            guard let key = screen.displayKey, !seen.contains(key) else { continue }
            seen.insert(key)

            if let controller = controllers[key] {
                controller.update(screen: screen)
            } else {
                let controller = WallpaperScreenController(screen: screen, displayKey: key)
                controller.onOcclusionChanged = { [weak self] in
                    self?.updatePlaybackStates()
                }
                controllers[key] = controller
                if let assignment = settings.assignments[key] {
                    applyStoredAssignment(assignment, to: controller, key: key)
                }
            }
        }

        // Tear down windows for disconnected displays but keep their stored
        // assignment so the wallpaper returns when the display is replugged.
        for (key, controller) in controllers where !seen.contains(key) {
            controller.tearDown()
            controllers.removeValue(forKey: key)
        }

        updatePlaybackStates()
        rebuildDisplayStates()
    }

    private func applyStoredAssignment(
        _ assignment: StoredAssignment,
        to controller: WallpaperScreenController,
        key: String
    ) {
        guard let url = resolveBookmark(assignment.bookmark, forKey: key) else { return }
        controller.load(
            url: url,
            scaling: assignment.scaling,
            muted: assignment.muted,
            volume: assignment.volume
        )
    }

    // MARK: - Playback gating

    @objc private func systemWillSleep() {
        isSystemSleeping = true
        updatePlaybackStates()
    }

    @objc private func systemDidWake() {
        isSystemSleeping = false
        updatePlaybackStates()
    }

    @objc private func sessionResignedActive() {
        isSessionInactive = true
        updatePlaybackStates()
    }

    @objc private func sessionBecameActive() {
        isSessionInactive = false
        updatePlaybackStates()
    }

    private func updatePlaybackStates() {
        let globallyPaused = isSystemSleeping || isSessionInactive
            || (pauseOnBattery && isOnBattery)
        for controller in controllers.values {
            if controller.hasVideo && !globallyPaused && !controller.isOccluded {
                controller.play()
            } else {
                controller.pause()
            }
        }
    }

    // MARK: - Persistence

    private func persist() {
        persistWorkItem?.cancel()
        persistWorkItem = nil
        settings.pauseOnBattery = pauseOnBattery
        store.save(settings)
    }

    /// A save that waits half a second before hitting the disk, for values
    /// that change in rapid bursts. Any direct persist() call in the
    /// meantime writes everything anyway, so nothing can get lost — the
    /// only way to skip a pending save entirely is quitting, and
    /// shutdown() flushes for that.
    private func schedulePersist() {
        persistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.persist() }
        persistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    static func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // Non-sandboxed fallback: a plain bookmark still survives renames/moves.
            return try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    private func resolveBookmark(_ data: Data, forKey key: String) -> URL? {
        var stale = false
        let url = (try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )) ?? (try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ))
        guard let url else { return nil }
        if stale, let fresh = try? Self.makeBookmark(for: url) {
            settings.assignments[key]?.bookmark = fresh
            persist()
        }
        return url
    }

    private func rebuildDisplayStates() {
        var states: [DisplayState] = []
        var seen = Set<String>()
        for screen in NSScreen.screens {
            guard let key = screen.displayKey, !seen.contains(key),
                  let controller = controllers[key] else { continue }
            seen.insert(key)
            let assignment = settings.assignments[key]
            let scale = screen.backingScaleFactor
            let pixels = "\(Int(screen.frame.width * scale)) × \(Int(screen.frame.height * scale))"
            states.append(DisplayState(
                id: key,
                name: screen.localizedName,
                resolutionText: pixels,
                videoURL: controller.videoURL,
                scaling: assignment?.scaling ?? .fill,
                isMuted: assignment?.muted ?? true,
                volume: assignment?.volume ?? 1.0
            ))
        }
        // Reconciles fire on every screen-parameter notification, and most
        // of the time nothing user-visible changed. Publishing only real
        // changes saves SwiftUI from re-rendering the panel for nothing.
        if states != displayStates {
            displayStates = states
        }
    }
}
