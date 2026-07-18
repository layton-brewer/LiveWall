import AppKit
import AVFoundation

/// A view whose backing layer is literally an AVPlayerLayer, so the video
/// just tracks the view's bounds automatically — no manual layout needed.
final class PlayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspectFill
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer { playerLayer }
}
