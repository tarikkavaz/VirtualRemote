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

    /// False for live streams and anything else without a known length. Such a
    /// player may report an elapsed time, but it is not a position that skipping
    /// or seeking can use: skipping a live stream jumps far behind the live edge.
    public var isSeekable: Bool { (duration ?? 0) > 0 }

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
    /// False when the receiver's output has no software volume or mute (HDMI,
    /// DisplayPort), so controllers should hide the volume controls.
    public var volumeAvailable: Bool

    public init(nowPlaying: NowPlayingInfo?, volume: Double, muted: Bool, volumeAvailable: Bool = true) {
        self.nowPlaying = nowPlaying
        self.volume = volume
        self.muted = muted
        self.volumeAvailable = volumeAvailable
    }

    private enum CodingKeys: String, CodingKey {
        case nowPlaying, volume, muted, volumeAvailable
    }

    // `volumeAvailable` is optional on the wire so states from receivers that
    // predate it still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nowPlaying = try c.decodeIfPresent(NowPlayingInfo.self, forKey: .nowPlaying)
        volume = try c.decode(Double.self, forKey: .volume)
        muted = try c.decode(Bool.self, forKey: .muted)
        volumeAvailable = try c.decodeIfPresent(Bool.self, forKey: .volumeAvailable) ?? true
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
    /// A player is active but has no known length or position (a live stream, for example).
    case positionUnavailable
    case processFailed(executable: String, status: Int32)
    case invalidAdapterOutput
}

extension RemoteError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noActivePlayer:
            "Nothing is playing."
        case .positionUnavailable:
            "This is a live stream or has no known length, so it cannot skip or seek."
        case .processFailed(let executable, let status):
            "The media helper (\(URL(fileURLWithPath: executable).lastPathComponent)) failed with status \(status)."
        case .invalidAdapterOutput:
            "Could not read the media state."
        }
    }

    /// Text to show a person for any error a command can throw.
    public static func userMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
