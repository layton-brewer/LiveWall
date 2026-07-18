import AppKit
import SwiftUI

/// The menu bar entry point: a status item that toggles a popdown panel
/// aligned under the menu bar at the right edge of the screen.
final class StatusItemController: NSObject, NSWindowDelegate {
    /// Must match SettingsView's own `.frame(width:height:)` so AppKit's
    /// window size and SwiftUI's content size always agree.
    private static let panelContentSize = NSSize(width: 380, height: 376)

    private let statusItem: NSStatusItem
    private let panel: SettingsPanel
    private var lastCloseTime: TimeInterval = 0
    private var mouseUpPoller: Timer?

    init(engine: WallpaperEngine) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        let hostingController = NSHostingController(rootView: SettingsView(engine: engine))
        // Without this, switching tabs makes NSHostingController keep
        // resizing the window to match whatever the new tab's content
        // wants — and since AppKit resizes from the bottom-left corner,
        // that shoves the panel's top edge up past the menu bar. The
        // explicit setContentSize below is the single source of truth
        // for size instead.
        hostingController.sizingOptions = []
        hostingController.view.autoresizingMask = [.width, .height]

        // Real Liquid Glass where the OS has it; the classic frosted
        // NSVisualEffectView with rounded corners everywhere else.
        let backdropController = NSViewController()
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 14
            glass.contentView = hostingController.view
            backdropController.view = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.maskImage = Self.roundedCornerMask(radius: 14)
            hostingController.view.frame = effect.bounds
            effect.addSubview(hostingController.view)
            backdropController.view = effect
        }

        panel = SettingsPanel(contentViewController: backdropController)
        panel.setContentSize(Self.panelContentSize)
        super.init()

        panel.delegate = self

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "play.rectangle.on.rectangle",
                accessibilityDescription: "LiveWall"
            )
            button.target = self
            button.action = #selector(togglePanel(_:))
        }
    }

    @objc private func togglePanel(_ sender: Any?) {
        if panel.isVisible {
            closePanel()
        } else {
            // If the click that fired this action already closed the panel by
            // taking key status away, treat it as a close, not a reopen.
            guard ProcessInfo.processInfo.systemUptime - lastCloseTime > 0.25 else { return }
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Top edge flush with the bottom of the menu bar, right edge flush with
    /// the right side of the screen the status item is on.
    private func positionPanel() {
        guard let screen = statusItem.button?.window?.screen ?? NSScreen.main else { return }
        panel.layoutIfNeeded()
        let size = panel.frame.size
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.maxX - size.width,
            y: visible.maxY - size.height
        ))
    }

    private func closePanel() {
        mouseUpPoller?.invalidate()
        mouseUpPoller = nil
        lastCloseTime = ProcessInfo.processInfo.systemUptime
        panel.orderOut(nil)
    }

    // MARK: - NSWindowDelegate

    /// If the panel's size ever changes for any reason, snap it back under
    /// the menu bar and against the right edge of the screen, so it can
    /// never end up drifting somewhere odd.
    func windowDidResize(_ notification: Notification) {
        positionPanel()
    }

    /// Closes the panel when you click anywhere outside it — except when
    /// that click is actually the start of a drag from Finder. A mouse-down
    /// that starts a drag also takes away key status, so if a button's
    /// still held down we wait for mouse-up instead: if it lands back on
    /// the panel, that was a drop, so keep it open; otherwise close it.
    func windowDidResignKey(_ notification: Notification) {
        if NSEvent.pressedMouseButtons != 0 {
            deferCloseUntilMouseUp()
        } else {
            closePanel()
        }
    }

    /// A stretchable rounded-rect image for NSVisualEffectView's mask —
    /// how you get rounded corners on a blur view before Liquid Glass.
    private static func roundedCornerMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private func deferCloseUntilMouseUp() {
        guard mouseUpPoller == nil else { return }
        mouseUpPoller = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard NSEvent.pressedMouseButtons == 0 else { return }
            timer.invalidate()
            self.mouseUpPoller = nil
            if self.panel.frame.contains(NSEvent.mouseLocation) {
                // A drop just landed on the panel; keep it open and key.
                self.panel.makeKeyAndOrderFront(nil)
            } else {
                self.closePanel()
            }
        }
    }
}
