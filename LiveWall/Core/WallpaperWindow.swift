import AppKit

/// The window that actually shows the wallpaper video. It's borderless and
/// click-through, and sits at the same level as the desktop picture itself —
/// above it, but still below the desktop icons, on every Space, and
/// invisible to Mission Control and Cmd+Tab.
final class WallpaperWindow: NSWindow {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)

        // kCGDesktopWindowLevel is where the system draws the desktop
        // picture. Put our window at that level and order it front, and it
        // ends up right above the static wallpaper, while the desktop icons
        // (one level up, at kCGDesktopIconWindowLevel) still draw on top of
        // our video like normal.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        ignoresMouseEvents = true
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        isExcludedFromWindowsMenu = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        displaysWhenScreenProfileChanges = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
