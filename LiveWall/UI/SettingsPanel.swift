import AppKit

/// The panel that pops down from the menu bar icon. It's a "titled" window
/// with the title bar hidden — a trick to keep macOS's native rounded
/// corners and shadow without actually showing a title bar or buttons.
final class SettingsPanel: NSPanel {
    init(contentViewController: NSViewController) {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.contentViewController = contentViewController

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        // Dragging a SwiftUI slider inside a hosted view reads as a
        // "background" drag to AppKit, so with background-dragging on, the
        // whole window moves instead of the slider knob. The panel anchors
        // itself under the menu bar on every open anyway, so window
        // dragging isn't worth broken sliders.
        isMovableByWindowBackground = false
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.moveToActiveSpace, .ignoresCycle, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
