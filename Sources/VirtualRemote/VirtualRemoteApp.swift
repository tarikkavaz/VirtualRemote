import SwiftUI

@main
struct VirtualRemoteApp: App {
    @State private var model: ControllerModel

    init() {
        let model = ControllerModel()
        _model = State(initialValue: model)
        Hotkeys.bind(to: model)
        model.startBrowsing()
    }

    var body: some Scene {
        MenuBarExtra("Virtual Remote", systemImage: "appletvremote.gen4.fill") {
            PopoverView(model: model)
        }
        .menuBarExtraStyle(.window)

        Window("Hotkeys", id: "hotkeys") {
            HotkeysView()
        }
        .windowResizability(.contentSize)
    }
}
