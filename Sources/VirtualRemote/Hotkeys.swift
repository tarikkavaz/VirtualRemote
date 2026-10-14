import KeyboardShortcuts
import SwiftUI
import VirtualRemoteCore

extension KeyboardShortcuts.Name {
    private static let hyper: NSEvent.ModifierFlags = [.control, .option, .command]
    private static let hyperShift: NSEvent.ModifierFlags = [.control, .option, .command, .shift]

    static let playPause = Self("playPause", default: .init(.space, modifiers: hyper))
    static let back10 = Self("back10", default: .init(.leftArrow, modifiers: hyper))
    static let forward10 = Self("forward10", default: .init(.rightArrow, modifiers: hyper))
    static let back20 = Self("back20", default: .init(.leftArrow, modifiers: hyperShift))
    static let forward20 = Self("forward20", default: .init(.rightArrow, modifiers: hyperShift))
    static let volumeUp = Self("volumeUp", default: .init(.upArrow, modifiers: hyper))
    static let volumeDown = Self("volumeDown", default: .init(.downArrow, modifiers: hyper))
    static let stop = Self("stop", default: .init(.s, modifiers: hyper))
    static let previous = Self("previous", default: .init(.comma, modifiers: hyper))
    static let next = Self("next", default: .init(.period, modifiers: hyper))
}

/// The "10" and "20" in the names are the default skip lengths; the real lengths
/// come from AppSettings. The names stay so existing recorded shortcuts keep working.
@MainActor
enum Hotkeys {
    /// Rows for the shortcuts list. Titles follow the current skip lengths.
    static func all(short: Int, long: Int) -> [(name: KeyboardShortcuts.Name, title: String)] {
        [
            (.playPause, "Play / Pause"),
            (.back10, "Back \(short) s"),
            (.forward10, "Forward \(short) s"),
            (.back20, "Back \(long) s"),
            (.forward20, "Forward \(long) s"),
            (.stop, "Stop"),
            (.previous, "Previous"),
            (.next, "Next"),
            (.volumeUp, "Volume up"),
            (.volumeDown, "Volume down"),
        ]
    }

    static func bind(to model: ControllerModel) {
        // The command is built at key press, so changed settings apply immediately.
        func on(_ name: KeyboardShortcuts.Name, _ command: @escaping @MainActor () -> RemoteCommand) {
            KeyboardShortcuts.onKeyDown(for: name) { [model] in
                Task { @MainActor in model.send(command()) }
            }
        }
        on(.playPause) { .togglePlayPause }
        on(.back10) { .skip(seconds: -Double(AppSettings.skipShortSeconds)) }
        on(.forward10) { .skip(seconds: Double(AppSettings.skipShortSeconds)) }
        on(.back20) { .skip(seconds: -Double(AppSettings.skipLongSeconds)) }
        on(.forward20) { .skip(seconds: Double(AppSettings.skipLongSeconds)) }
        on(.stop) { .stop }
        on(.previous) { .previous }
        on(.next) { .next }
        on(.volumeUp) { .adjustVolume(AppSettings.volumeStep) }
        on(.volumeDown) { .adjustVolume(-AppSettings.volumeStep) }
    }
}
