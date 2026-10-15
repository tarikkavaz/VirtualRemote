import Foundation

/// Commands a controller sends to a receiver.
public enum RemoteCommand: Codable, Equatable, Sendable {
    case play
    case pause
    case togglePlayPause
    case stop
    case next
    case previous
    /// Relative seek. Negative = back.
    case skip(seconds: Double)
    /// Absolute position in seconds, e.g. from clicking the progress bar.
    case seek(to: Double)
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
    /// Id of the thumbnail the receiver sent as a separate `artwork` message.
    public var artworkID: String?
    /// Raw image from the adapter. Receiver-side only: never encoded, so it
    /// cannot end up inside state messages.
    public var artworkData: Data?

    private enum CodingKeys: String, CodingKey {
        case bundleIdentifier, title, artist, playing, elapsedTime, duration
        case playbackRate, timestamp, artworkID
    }

    public init(
        bundleIdentifier: String,
        title: String? = nil,
        artist: String? = nil,
        playing: Bool,
        elapsedTime: Double? = nil,
        duration: Double? = nil,
        playbackRate: Double? = nil,
        timestamp: Date? = nil,
        artworkID: String? = nil,
        artworkData: Data? = nil
    ) {
        self.artworkID = artworkID
        self.artworkData = artworkData
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

/// Downscaled JPEG thumbnail, sent once per controller before the state that references it.
public struct Artwork: Codable, Equatable, Sendable {
    public var id: String
    public var jpeg: Data

    public init(id: String, jpeg: Data) {
        self.id = id
        self.jpeg = jpeg
    }
}

/// The player app's name and a small PNG icon, read on the receiver and sent
/// once per controller before the state that references the app.
public struct AppIcon: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public var png: Data

    public init(bundleIdentifier: String, name: String, png: Data) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.png = png
    }
}

public enum RemoteMessage: Codable, Equatable, Sendable {
    case command(RemoteCommand)
    case state(RemoteState)
    case artwork(Artwork)
    case appIcon(AppIcon)
    /// Receiver could not run a command.
    case error(String)
}

public enum RemoteError: Error, Equatable {
    case noActivePlayer
    case processFailed(executable: String, status: Int32)
    case invalidAdapterOutput
}
