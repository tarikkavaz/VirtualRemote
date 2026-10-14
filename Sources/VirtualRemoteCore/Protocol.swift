import Foundation

/// Commands a controller sends to a receiver.
public enum RemoteCommand: Codable, Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case next
    case previous
    /// Relative seek. Negative = back.
    case skip(seconds: Double)
    /// Absolute volume, 0...1.
    case setVolume(Double)
    /// Relative volume change, in 0...1 units.
    case adjustVolume(Double)
    case setMuted(Bool)
}

/// What the system reports as the active Now Playing session.
public struct NowPlayingInfo: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var title: String?
    public var artist: String?
    public var playing: Bool
    /// Elapsed seconds as of `timestamp`.
    public var elapsedTime: Double?
    public var duration: Double?
    public var playbackRate: Double?
    public var timestamp: Date?

    public init(
        bundleIdentifier: String,
        title: String? = nil,
        artist: String? = nil,
        playing: Bool,
        elapsedTime: Double? = nil,
        duration: Double? = nil,
        playbackRate: Double? = nil,
        timestamp: Date? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.artist = artist
        self.playing = playing
        self.elapsedTime = elapsedTime
        self.duration = duration
        self.playbackRate = playbackRate
        self.timestamp = timestamp
    }

    /// Elapsed seconds now. `elapsedTime` is a sample taken at `timestamp`,
    /// so while playing we add the time since the sample.
    public func estimatedElapsed(at now: Date) -> Double? {
        guard let elapsedTime else { return nil }
        guard playing, let timestamp else { return elapsedTime }
        let rate = playbackRate ?? 1
        return elapsedTime + max(0, now.timeIntervalSince(timestamp)) * rate
    }
}

/// Full receiver state pushed to controllers.
public struct RemoteState: Codable, Equatable, Sendable {
    public var nowPlaying: NowPlayingInfo?
    public var volume: Double
    public var muted: Bool

    public init(nowPlaying: NowPlayingInfo?, volume: Double, muted: Bool) {
        self.nowPlaying = nowPlaying
        self.volume = volume
        self.muted = muted
    }
}

public enum RemoteMessage: Codable, Equatable, Sendable {
    case command(RemoteCommand)
    case state(RemoteState)
    /// Receiver could not run a command.
    case error(String)
}

public enum RemoteError: Error, Equatable {
    case noActivePlayer
    case processFailed(executable: String, status: Int32)
    case invalidAdapterOutput
}
