import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ArtworkProcessor {
    /// Stable id for an image: first 8 bytes of its SHA-256, hex.
    public static func id(for data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// JPEG no larger than `maxPixel` on its longest side, or nil if the data is not an image.
    public static func thumbnail(from data: Data, maxPixel: Int = 256) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let output = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Remembers recent thumbnails so a 1 s poll does not re-encode the same image.
actor ArtworkCache {
    private var entries: [(id: String, jpeg: Data?)] = []
    private let capacity = 8

    /// nil when the data is not a decodable image.
    func resolve(_ raw: Data) -> Artwork? {
        let id = ArtworkProcessor.id(for: raw)
        if let hit = entries.first(where: { $0.id == id }) {
            return hit.jpeg.map { Artwork(id: id, jpeg: $0) }
        }
        let jpeg = ArtworkProcessor.thumbnail(from: raw)
        entries.append((id, jpeg))
        if entries.count > capacity { entries.removeFirst() }
        return jpeg.map { Artwork(id: id, jpeg: $0) }
    }
}
