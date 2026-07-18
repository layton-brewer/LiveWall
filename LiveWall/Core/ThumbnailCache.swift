import AppKit
import AVFoundation

/// Grabs a preview frame from a video and caches it, so the Displays tab
/// doesn't have to re-decode the same video every time it redraws. The
/// cache is an NSCache with a small cap rather than a plain dictionary,
/// so previewing lots of different videos over a long session can't
/// quietly pile up decoded images in memory forever.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 24
        return cache
    }()

    func thumbnail(for url: URL) async -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)

        let candidates = [CMTime(seconds: 1, preferredTimescale: 600), .zero]
        for time in candidates {
            if let (cgImage, _) = try? await generator.image(at: time) {
                let image = NSImage(cgImage: cgImage, size: .zero)
                cache.setObject(image, forKey: url as NSURL)
                return image
            }
        }
        return nil
    }
}
