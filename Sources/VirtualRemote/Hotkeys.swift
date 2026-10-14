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
    static let previous = Self("previous", default: .init(.comma, modifiers: hyper))
    static let next = Self("next", default: .init(.period, modifiers: hyper))
}

@MainActor
enum Hotkeys {
    static let volumeStep = 0.05

    static let all: [(name: KeyboardShortcuts.Name, title: String)] = [
        (.playPause, "Play / Pause"),
        (.back10, "Back 10 s"),
        (.forward10, "Forward 10 s"),
        (.back20, "Back 20 s"),
        (.forward20, "Forward 20 s"),
        (.previous, "Previous"),
        (.next, "Next"),
        (.volumeUp, "Volume up"),
        (.volumeDown, "Volume down"),
    ]

    static func bind(to model: ControllerModel) {
        func on(_ name: KeyboardShortcuts.Name, _ command: RemoteCommand) {
            KeyboardShortcuts.onKeyDown(for: name) { [model] in
                Task { @MainActor in model.send(command) }
            }
        }
        on(.playPause, .togglePlayPause)
        on(.back10, .skip(seconds: -10))
        on(.forward10, .skip(seconds: 10))
        on(.back20, .skip(seconds: -20))
        on(.forward20, .skip(seconds: 20))
        on(.previous, .previous)
        on(.next, .next)
        on(.volumeUp, .adjustVolume(volumeStep))
        on(.volumeDown, .adjustVolume(-volumeStep))
    }
}

struct HotkeysView: View {
    var body: some View {
        Form {
            ForEach(Hotkeys.all, id: \.name) { item in
                KeyboardShortcuts.Recorder(item.title, name: item.name)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
