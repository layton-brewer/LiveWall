import AppKit
import AVFoundation

/// Grabs a preview frame from a video and caches it, so the Displays tab
/// doesn't have to re-decode the same video every time it redraws.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [URL: NSImage] = [:]

    func thumbnail(for url: URL) async -> NSImage? {
        if let cached = cache[url] { return cached }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)

        let candidates = [CMTime(seconds: 1, preferredTimescale: 600), .zero]
        for time in candidates {
            if let (cgImage, _) = try? await generator.image(at: time) {
                let image = NSImage(cgImage: cgImage, size: .zero)
                cache[url] = image
                return image
            }
        }
        return nil
    }
}
