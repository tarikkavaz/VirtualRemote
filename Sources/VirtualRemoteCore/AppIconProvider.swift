import AppKit
import Foundation

public enum AppIconProvider {
    /// Name and icon of the installed app with this bundle id, or nil when it is not installed here.
    public static func load(bundleIdentifier: String, pixels: Int = 64) -> AppIcon? {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier),
              let png = png(of: workspace.icon(forFile: url.path), pixels: pixels)
        else { return nil }
        let bundle = Bundle(url: url)
        let name = ["CFBundleDisplayName", "CFBundleName"]
            .compactMap { bundle?.object(forInfoDictionaryKey: $0) as? String }
            .first { !$0.isEmpty }
            ?? url.deletingPathExtension().lastPathComponent
        return AppIcon(bundleIdentifier: bundleIdentifier, name: name, png: png)
    }

    static func png(of image: NSImage, pixels: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
            from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

/// Remembers resolved icons (and misses) so the 1 s poll does not hit the disk.
actor AppIconCache {
    private let loader: @Sendable (String) -> AppIcon?
    private var entries: [String: AppIcon?] = [:]

    init(loader: @escaping @Sendable (String) -> AppIcon?) {
        self.loader = loader
    }

    func icon(for bundleIdentifier: String) -> AppIcon? {
        if let hit = entries[bundleIdentifier] { return hit }
        let icon = loader(bundleIdentifier)
        entries[bundleIdentifier] = .some(icon)
        return icon
    }
}
