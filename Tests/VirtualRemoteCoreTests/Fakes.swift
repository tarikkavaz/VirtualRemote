import Foundation
@testable import VirtualRemoteCore

actor FakePlayer: NowPlayingBackend {
    var info: NowPlayingInfo?
    private(set) var sent: [MediaCommand] = []
    private(set) var seeks: [Double] = []

    init(info: NowPlayingInfo? = nil) { self.info = info }

    func nowPlaying() async throws -> NowPlayingInfo? { info }
    func send(_ command: MediaCommand) async throws { sent.append(command) }
    func seek(to seconds: Double) async throws { seeks.append(seconds) }
}

/// An output without software volume: every read fails, like HDMI or DisplayPort.
struct NoVolume: VolumeBackend {
    func volume() async throws -> Double { throw RemoteError.invalidAdapterOutput }
    func setVolume(_ value: Double) async throws {}
    func isMuted() async throws -> Bool { throw RemoteError.invalidAdapterOutput }
    func setMuted(_ muted: Bool) async throws {}
}

actor FakeVolume: VolumeBackend {
    var level: Double
    var muted: Bool

    init(level: Double = 0.5, muted: Bool = false) {
        self.level = level
        self.muted = muted
    }

    func volume() async throws -> Double { level }
    func setVolume(_ value: Double) async throws { level = value }
    func isMuted() async throws -> Bool { muted }
    func setMuted(_ muted: Bool) async throws { self.muted = muted }
}
