import Foundation
import IOKit.ps

/// Watches whether the Mac is on AC power or battery, using IOKit, and
/// reports changes on the main queue.
final class PowerMonitor {
    /// Fires with `true` the moment the Mac switches to battery power.
    var onPowerSourceChanged: ((Bool) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    static func isOnBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() else {
            return false
        }
        return (type as String) == kIOPSBatteryPowerValue
    }

    func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                monitor.onPowerSourceChanged?(PowerMonitor.isOnBattery())
            }
        }, context)?.takeRetainedValue() else {
            return
        }
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
    }

    deinit {
        stop()
    }
}
