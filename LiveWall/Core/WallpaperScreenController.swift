import AppKit
import AVFoundation

/// Everything one display needs to show its wallpaper: the window, the
/// player, and the looper. AVFoundation streams the video straight from
/// disk, so it doesn't matter whether it's a tiny 480p clip or a
/// multi-gigabyte 8K one — it never gets loaded into memory all at once.
final class WallpaperScreenController {
    let displayKey: String
    private(set) var screen: NSScreen
    private(set) var videoURL: URL?
    private(set) var isOccluded = false

    /// Fires on the main queue whenever this display's wallpaper window
    /// becomes fully covered or uncovered — a fullscreen app, for example.
    var onOcclusionChanged: (() -> Void)?

    private let window: WallpaperWindow
    private let playerView: PlayerView
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var accessingSecurityScope = false
    private var occlusionObserver: NSObjectProtocol?

    init(screen: NSScreen, displayKey: String) {
        self.screen = screen
        self.displayKey = displayKey
        playerView = PlayerView(frame: NSRect(origin: .zero, size: screen.frame.size))
        window = WallpaperWindow(frame: screen.frame)
        window.contentView = playerView

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let occluded = !self.window.occlusionState.contains(.visible)
            if occluded != self.isOccluded {
                self.isOccluded = occluded
                self.onOcclusionChanged?()
            }
        }
    }

    deinit {
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }

    var hasVideo: Bool { player != nil }

    /// Called after a display layout change — the NSScreen instance may have
    /// been recreated, so this just re-points at whatever the new one is.
    func update(screen: NSScreen) {
        self.screen = screen
        window.setFrame(screen.frame, display: true)
    }

    func load(
        url: URL,
        scaling: ScalingMode,
        muted: Bool,
        volume: Float,
        trimStart: Double? = nil,
        trimEnd: Double? = nil
    ) {
        clear()

        videoURL = url
        accessingSecurityScope = url.startAccessingSecurityScopedResource()

        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = muted
        queuePlayer.volume = volume
        // A wallpaper video should never be the reason your Mac won't sleep.
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false

        looper = Self.makeLooper(player: queuePlayer, url: url, trimStart: trimStart, trimEnd: trimEnd)
        player = queuePlayer
        playerView.playerLayer.player = queuePlayer
        playerView.playerLayer.videoGravity = scaling.videoGravity

        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)
    }

    /// Swaps the loop range without tearing down the whole player. Trimming
    /// is non-destructive — the file is untouched, the looper just plays a
    /// slice of it.
    func setTrim(start: Double?, end: Double?) {
        guard let player, let videoURL else { return }
        looper?.disableLooping()
        player.removeAllItems()
        looper = Self.makeLooper(player: player, url: videoURL, trimStart: start, trimEnd: end)
    }

    private static func makeLooper(
        player: AVQueuePlayer,
        url: URL,
        trimStart: Double?,
        trimEnd: Double?
    ) -> AVPlayerLooper {
        let item = AVPlayerItem(url: url)
        // AVFoundation happily buffers a big chunk of video ahead by
        // default, which adds up fast on an 8K file. This is a local file
        // on a loop — a few seconds of read-ahead is plenty, and it keeps
        // the memory footprint down.
        item.preferredForwardBufferDuration = 5

        // Only honor a trim that's actually a real slice — at least half a
        // second long, starting inside the file.
        if let trimStart, let trimEnd, trimStart >= 0, trimEnd - trimStart >= 0.5 {
            let range = CMTimeRange(
                start: CMTime(seconds: trimStart, preferredTimescale: 600),
                end: CMTime(seconds: trimEnd, preferredTimescale: 600)
            )
            return AVPlayerLooper(player: player, templateItem: item, timeRange: range)
        }
        return AVPlayerLooper(player: player, templateItem: item)
    }

    func clear() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        playerView.playerLayer.player = nil
        player = nil
        window.orderOut(nil)
        if accessingSecurityScope, let videoURL {
            videoURL.stopAccessingSecurityScopedResource()
        }
        accessingSecurityScope = false
        videoURL = nil
    }

    func setScaling(_ scaling: ScalingMode) {
        playerView.playerLayer.videoGravity = scaling.videoGravity
    }

    func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    func setVolume(_ volume: Float) {
        player?.volume = volume
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func tearDown() {
        clear()
        window.close()
    }
}
