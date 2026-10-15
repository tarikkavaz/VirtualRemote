import CoreGraphics
import Foundation
import ImageIO
import Network
import UniformTypeIdentifiers
import VirtualRemoteCore
@testable import VirtualRemote

/// A key store that lives in memory, so tests never touch the real Keychain.
final class MemoryKeyStore: KeyStoring {
    var keys: [String: PairingKey] = [:]
    var failSaves = false

    func load(account: String) -> PairingKey? { keys[account] }

    func save(_ key: PairingKey, account: String) throws {
        if failSaves { throw NSError(domain: "MemoryKeyStore", code: 1) }
        keys[account] = key
    }

    func delete(account: String) { keys[account] = nil }
}

actor StubPlayer: NowPlayingBackend {
    private var info: NowPlayingInfo?
    private(set) var sent: [MediaCommand] = []
    private(set) var seeks: [Double] = []

    init(info: NowPlayingInfo?) { self.info = info }

    func nowPlaying() async throws -> NowPlayingInfo? { info }
    func send(_ command: MediaCommand) async throws { sent.append(command) }
    func seek(to seconds: Double) async throws { seeks.append(seconds) }
}

actor StubVolume: VolumeBackend {
    func volume() async throws -> Double { 0.4 }
    func setVolume(_ value: Double) async throws {}
    func isMuted() async throws -> Bool { false }
    func setMuted(_ muted: Bool) async throws {}
}

extension NowPlayingInfo {
    static func sample(bundle: String = "tv.plex.desktop", artwork: Data? = nil) -> NowPlayingInfo {
        NowPlayingInfo(
            bundleIdentifier: bundle, title: "Film", artist: "Someone", playing: true,
            elapsedTime: 100, duration: 1000, playbackRate: 1, timestamp: Date(),
            artworkData: artwork)
    }
}

/// A real receiver on localhost, without Bonjour, with a stub player.
struct LoopbackReceiver {
    let server: RemoteServer
    let port: UInt16
    let key: PairingKey
    let player: StubPlayer

    static func start(
        info: NowPlayingInfo? = .sample(), icon: AppIcon? = nil, key: PairingKey = .generate()
    ) async throws -> LoopbackReceiver {
        let player = StubPlayer(info: info)
        let server = RemoteServer(
            executor: CommandExecutor(player: player, volume: StubVolume()),
            key: key,
            advertise: false,
            pollInterval: .milliseconds(50),
            iconLoader: { _ in icon }
        )
        let port = try await server.start()
        return LoopbackReceiver(server: server, port: port, key: key, player: player)
    }

    /// How the controller would list this receiver.
    func discovered(name: String = "Test Mac", kind: MacKind = .macMini) -> DiscoveredReceiver {
        DiscoveredReceiver(
            name: name,
            endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!),
            kind: kind)
    }
}

/// Polls until the condition holds or the timeout passes.
@MainActor
func eventually(
    timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

/// A solid-colour PNG of the given size.
func makePNG(width: Int, height: Int) -> Data {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 0.8, green: 0.2, blue: 0.4, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = CFDataCreateMutable(nil, 0)!
    let destination = CGImageDestinationCreateWithData(
        output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}
