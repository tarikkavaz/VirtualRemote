import Foundation

/// MediaRemote command IDs understood by mediaremote-adapter's `send`.
public enum MediaCommand: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case next = 4
    case previous = 5
}

public protocol NowPlayingBackend: Sendable {
    /// nil when there is no active session.
    func nowPlaying() async throws -> NowPlayingInfo?
    func send(_ command: MediaCommand) async throws
    /// Absolute position in seconds.
    func seek(to seconds: Double) async throws
}

public protocol VolumeBackend: Sendable {
    func volume() async throws -> Double
    func setVolume(_ value: Double) async throws
    func isMuted() async throws -> Bool
    func setMuted(_ muted: Bool) async throws
}
