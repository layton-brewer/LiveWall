import AppKit

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    /// A stable ID for this display, used to remember its wallpaper
    /// assignment. It's tied to the actual panel hardware via CoreGraphics,
    /// not the display's position or order, so it survives relaunches,
    /// restarts, and unplugging/replugging. Falls back to name + resolution
    /// if macOS won't give us a UUID.
    var displayKey: String? {
        guard let id = displayID else { return nil }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, uuid) {
            return string as String
        }
        return "\(localizedName)-\(Int(frame.width))x\(Int(frame.height))"
    }
}
