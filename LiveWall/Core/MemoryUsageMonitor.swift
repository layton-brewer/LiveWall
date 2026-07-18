import Darwin
import Foundation

/// Tracks how much memory LiveWall itself is using. CPU isn't a useful
/// number to show here since hardware video decode barely touches it —
/// memory (all those buffered and decoded frames) is what actually
/// reflects the real cost of running the wallpaper engine.
@MainActor
final class MemoryUsageMonitor: ObservableObject {
    @Published private(set) var usageMB: Double = 0

    private var timer: Timer?

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func sample() {
        guard let bytes = Self.currentPhysicalFootprintBytes() else { return }
        usageMB = Double(bytes) / 1_048_576
    }

    /// Physical memory footprint, in bytes — the same number Activity
    /// Monitor shows in its Memory column, pulled the same way it does.
    private static func currentPhysicalFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }
}
