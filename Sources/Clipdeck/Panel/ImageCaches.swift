import AppKit
import ImageIO

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private nonisolated static let maxPixelSize = 640

    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL?) async -> NSImage? {
        guard let url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        let cgImage = await Task.detached(priority: .userInitiated) { Self.thumbnail(at: url) }.value
        guard let cgImage else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    private nonisolated static func thumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

@MainActor
enum AppIcons {
    private static let appIcons = NSCache<NSString, NSImage>()
    private static let fileIcons = NSCache<NSString, NSImage>()

    static func icon(forBundleID bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let cached = appIcons.object(forKey: bundleID as NSString) {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons.setObject(icon, forKey: bundleID as NSString)
        return icon
    }

    static func icon(forFile path: String) -> NSImage {
        if let cached = fileIcons.object(forKey: path as NSString) {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        fileIcons.setObject(icon, forKey: path as NSString)
        return icon
    }
}
