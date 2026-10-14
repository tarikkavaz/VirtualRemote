import Foundation

/// User preferences, stored in UserDefaults. Views bind to the same keys with
/// @AppStorage; code outside views reads the accessors, so a change applies on
/// the next use without any wiring.
enum AppSettings {
    enum Key {
        static let autoConnect = "autoConnect"
        static let volumeStepPercent = "volumeStepPercent"
        static let skipShortSeconds = "skipShortSeconds"
        static let skipLongSeconds = "skipLongSeconds"
    }

    enum Default {
        static let autoConnect = true
        static let volumeStepPercent = 5
        static let skipShortSeconds = 10
        static let skipLongSeconds = 20
    }

    enum Range {
        static let volumeStepPercent = 1...25
        static let skipSeconds = 1...600
    }

    static var autoConnect: Bool {
        UserDefaults.standard.object(forKey: Key.autoConnect) as? Bool ?? Default.autoConnect
    }

    /// Volume change per hotkey press, as a 0...1 fraction.
    static var volumeStep: Double {
        Double(int(Key.volumeStepPercent, Default.volumeStepPercent, Range.volumeStepPercent)) / 100
    }

    static var skipShortSeconds: Int {
        int(Key.skipShortSeconds, Default.skipShortSeconds, Range.skipSeconds)
    }

    static var skipLongSeconds: Int {
        int(Key.skipLongSeconds, Default.skipLongSeconds, Range.skipSeconds)
    }

    private static func int(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
        let stored = UserDefaults.standard.object(forKey: key) as? Int ?? fallback
        return min(max(stored, range.lowerBound), range.upperBound)
    }
}
