import CoreGraphics
import Foundation

/// The arithmetic behind the progress bar, kept apart from the view so it can be tested.
enum SeekBar {
    /// "1:05", or "1:02:03" from one hour up. Negative values show as zero.
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// How far along the bar a position is, from 0 to 1. A zero or unknown length gives 0.
    static func fraction(of seconds: Double, in duration: Double) -> CGFloat {
        CGFloat(min(max(seconds / max(duration, 1), 0), 1))
    }

    /// The position a click or drag at `x` points to, kept inside the track.
    static func time(atX x: CGFloat, width: CGFloat, duration: Double) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * duration
    }
}

enum PlayerNames {
    /// Names for common players, used until the receiver sends the app's own name.
    static func fallback(for bundleID: String) -> String {
        let known = [
            "tv.plex.desktop": "Plex",
            "company.thebrowser.Browser": "Arc",
            "com.google.Chrome": "Chrome",
            "com.apple.Safari": "Safari",
            "org.mozilla.firefox": "Firefox",
            "com.spotify.client": "Spotify",
        ]
        return known[bundleID] ?? bundleID
    }
}
