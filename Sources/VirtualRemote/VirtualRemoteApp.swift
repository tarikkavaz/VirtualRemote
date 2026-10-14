import SwiftUI

@main
struct VirtualRemoteApp: App {
    @State private var app: AppModel

    init() {
        let app = AppModel()
        _app = State(initialValue: app)
        Hotkeys.bind(to: app.controller)
    }

    var body: some Scene {
        MenuBarExtra("Virtual Remote", systemImage: "appletvremote.gen4.fill") {
            PopoverView(app: app)
        }
        .menuBarExtraStyle(.window)

        Window("Hotkeys", id: "hotkeys") {
            HotkeysView()
        }
        .windowResizability(.contentSize)
    }
}
