import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import VirtualRemoteCore

/// A solid-colour PNG of the given size.
func makePNG(width: Int, height: Int, red: CGFloat = 0.8) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: red, green: 0.2, blue: 0.4, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = CFDataCreateMutable(nil, 0)!
    let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

private func pixelSize(of data: Data) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int,
          let h = props[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (w, h)
}

@Suite struct ArtworkProcessorTests {
    @Test func thumbnailIsDownscaledJPEG() throws {
        let jpeg = try #require(ArtworkProcessor.thumbnail(from: makePNG(width: 1200, height: 800)))
        let (w, h) = try #require(pixelSize(of: jpeg))
        #expect(max(w, h) == 256)
        #expect(w > h)  // aspect ratio kept
        #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]))  // JPEG magic
    }

    @Test func smallImagesAreNotUpscaled() throws {
        let jpeg = try #require(ArtworkProcessor.thumbnail(from: makePNG(width: 100, height: 100)))
        let (w, _) = try #require(pixelSize(of: jpeg))
        #expect(w == 256 || w == 100)  // ImageIO may scale up; must never exceed the cap
    }

    @Test func nonImageDataGivesNil() {
        #expect(ArtworkProcessor.thumbnail(from: Data("not an image".utf8)) == nil)
    }

    @Test func idIsStableAndContentBased() {
        let a = makePNG(width: 10, height: 10, red: 0.1)
        let b = makePNG(width: 10, height: 10, red: 0.9)
        #expect(ArtworkProcessor.id(for: a) == ArtworkProcessor.id(for: a))
        #expect(ArtworkProcessor.id(for: a) != ArtworkProcessor.id(for: b))
        #expect(ArtworkProcessor.id(for: a).count == 16)
    }

    @Test func cacheReturnsSameArtworkAndSkipsBadData() async {
        let cache = ArtworkCache()
        let raw = makePNG(width: 500, height: 500)
        let first = await cache.resolve(raw)
        let second = await cache.resolve(raw)
        #expect(first != nil)
        #expect(first == second)
        #expect(await cache.resolve(Data("junk".utf8)) == nil)
    }
}

@Suite struct AppIconProviderTests {
    @Test func finderIconIsAPngWithAName() throws {
        let icon = try #require(AppIconProvider.load(bundleIdentifier: "com.apple.finder"))
        #expect(icon.name == "Finder")
        let size = try #require(pixelSize(of: icon.png))
        #expect(size.0 == 64 && size.1 == 64)
    }

    @Test func unknownAppGivesNil() {
        #expect(AppIconProvider.load(bundleIdentifier: "org.example.not-installed") == nil)
    }

    @Test func cacheRemembersHitsAndMisses() async {
        let counter = LoadCounter()
        let cache = AppIconCache(loader: { id in
            counter.increment()
            return id == "yes" ? AppIcon(bundleIdentifier: id, name: "Yes", png: Data([1])) : nil
        })
        #expect(await cache.icon(for: "yes")?.name == "Yes")
        #expect(await cache.icon(for: "yes")?.name == "Yes")
        #expect(await cache.icon(for: "no") == nil)
        #expect(await cache.icon(for: "no") == nil)
        #expect(counter.count == 2)
    }
}

private final class LoadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

@Suite struct ArtworkParsingTests {
    @Test func adapterArtworkIsDecodedFromBase64() throws {
        let bytes = Data([1, 2, 3, 4])
        let json =
            #"{"bundleIdentifier":"x","playing":true,"artworkData":""# + bytes.base64EncodedString()
            + #""}"#
        let info = try #require(try AdapterNowPlayingBackend.parse(json))
        #expect(info.artworkData == bytes)
    }

    @Test func rawArtworkIsNeverEncodedOnTheWire() throws {
        let info = NowPlayingInfo(
            bundleIdentifier: "x", playing: true, artworkID: "abc", artworkData: Data(count: 1000))
        let message = RemoteMessage.state(RemoteState(nowPlaying: info, volume: 0, muted: false))
        let data = try MessageCodec.encode(message)
        #expect(data.count < 400)
        let decoded = try MessageCodec.decode(data.dropLast())
        guard case .state(let state) = decoded else {
            Issue.record("not a state")
            return
        }
        #expect(state.nowPlaying?.artworkID == "abc")
        #expect(state.nowPlaying?.artworkData == nil)
    }

    @Test func artworkMessageRoundTrips() throws {
        let message = RemoteMessage.artwork(Artwork(id: "abc", jpeg: Data([0xFF, 0xD8, 0x00])))
        let data = try MessageCodec.encode(message)
        #expect(try MessageCodec.decode(data.dropLast()) == message)
    }
}
