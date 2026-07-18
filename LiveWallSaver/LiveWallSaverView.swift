import ScreenSaver
import AVFoundation

/// The actual screen saver: plays whatever video LiveWall has assigned,
/// looped and muted, filling the screen.
///
/// This runs inside Apple's sandboxed legacyScreenSaver process, which can
/// only see files inside its own container — so the LiveWall app copies the
/// video (plus a small saver.json pointing at it) into that container ahead
/// of time, and this view just reads them back from
/// Application Support/LiveWall inside the sandbox's home directory.
@objc(LiveWallSaverView)
final class LiveWallSaverView: ScreenSaverView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        wantsLayer = true
        animationTimeInterval = 1.0
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        animationTimeInterval = 1.0
    }

    override func startAnimation() {
        super.startAnimation()
        setUpPlayerIfNeeded()
        player?.play()
    }

    override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    override func animateOneFrame() {
        // AVPlayerLayer draws itself — there's nothing to do here per frame.
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
        guard playerLayer == nil else { return }
        let message = "Open LiveWall, assign a video, and re-enable the screen saver toggle."
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.6),
            .font: NSFont.systemFont(ofSize: isPreview ? 9 : 20, weight: .medium),
        ]
        let textSize = (message as NSString).size(withAttributes: attributes)
        let origin = NSPoint(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2
        )
        (message as NSString).draw(at: origin, withAttributes: attributes)
    }

    private func setUpPlayerIfNeeded() {
        guard playerLayer == nil, let url = Self.configuredVideoURL() else { return }

        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)

        let videoLayer = AVPlayerLayer(player: queuePlayer)
        videoLayer.videoGravity = .resizeAspectFill
        videoLayer.frame = bounds
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        videoLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(videoLayer)

        playerLayer = videoLayer
        player = queuePlayer
    }

    static func configuredVideoURL() -> URL? {
        let directory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/LiveWall", isDirectory: true)
        let movieExtensions: Set<String> = ["mov", "mp4", "m4v"]

        let config = directory.appendingPathComponent("saver.json")
        if let data = try? Data(contentsOf: config),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = object["video"] as? String {
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        // Fallback: just grab whatever movie file is sitting in the container.
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return contents.first { movieExtensions.contains($0.pathExtension.lowercased()) }
    }
}
