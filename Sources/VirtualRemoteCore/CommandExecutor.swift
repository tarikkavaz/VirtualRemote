import Foundation

/// Routes controller commands to the receiver's backends.
public actor CommandExecutor {
    private let player: NowPlayingBackend
    private let volumeBackend: VolumeBackend
    private let now: @Sendable () -> Date

    public init(
        player: NowPlayingBackend,
        volume: VolumeBackend,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.player = player
        self.volumeBackend = volume
        self.now = now
    }

    public func execute(_ command: RemoteCommand) async throws {
        switch command {
        case .play: try await transport(.play)
        case .pause: try await transport(.pause)
        case .togglePlayPause: try await transport(.togglePlayPause)
        case .stop: try await transport(.stop)
        case .next: try await transport(.next)
        case .previous: try await transport(.previous)
        case .skip(let seconds): try await skip(by: seconds)
        case .seek(let seconds): try await seek(to: seconds)
        case .setVolume(let value):
            try await volumeBackend.setVolume(Self.clamp(value, 0, 1))
        case .adjustVolume(let delta):
            let current = try await volumeBackend.volume()
            try await volumeBackend.setVolume(Self.clamp(current + delta, 0, 1))
        case .setMuted(let muted):
            try await volumeBackend.setMuted(muted)
        }
    }

    public func currentState() async throws -> RemoteState {
        async let nowPlaying = player.nowPlaying()
        // An output without software volume (HDMI, DisplayPort) cannot report one.
        // That must not stop the now-playing state from reaching controllers.
        async let volume: Double? = try? volumeBackend.volume()
        async let muted: Bool? = try? volumeBackend.isMuted()
        let (level, isMuted) = await (volume, muted)
        return try await RemoteState(
            nowPlaying: nowPlaying, volume: level ?? 0, muted: isMuted ?? false,
            volumeAvailable: level != nil)
    }

    /// Sends a transport command only when macOS has a Now Playing session. With
    /// none, macOS would hand "play" to Apple Music and launch it, which a remote
    /// should not do on its own. A paused or idle session still counts, so a press
    /// can resume it.
    private func transport(_ command: MediaCommand) async throws {
        guard try await player.nowPlaying() != nil else { throw RemoteError.noActivePlayer }
        try await player.send(command)
    }

    private func skip(by seconds: Double) async throws {
        guard let info = try await player.nowPlaying() else { throw RemoteError.noActivePlayer }
        guard info.isSeekable, let duration = info.duration,
              let elapsed = info.estimatedElapsed(at: now())
        else { throw RemoteError.positionUnavailable }
        try await player.seek(to: Self.clamp(elapsed + seconds, 0, duration))
    }

    private func seek(to seconds: Double) async throws {
        guard let info = try await player.nowPlaying() else { throw RemoteError.noActivePlayer }
        guard info.isSeekable, let duration = info.duration else {
            throw RemoteError.positionUnavailable
        }
        try await player.seek(to: Self.clamp(seconds, 0, duration))
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}
