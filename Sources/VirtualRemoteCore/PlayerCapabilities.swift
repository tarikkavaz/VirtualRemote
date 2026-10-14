import Foundation

/// Which Now Playing apps react to which commands. Learned by testing, not
/// reported by the system; extend as more players are verified.
public enum PlayerCapabilities {
    /// Apps verified to implement the system stop command.
    /// Verified: Plex. Ignored (tested): Spotify, Arc/YouTube.
    static let stopSupported: Set<String> = ["tv.plex.desktop"]

    public static func supportsStop(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return stopSupported.contains(bundleIdentifier)
    }
}
