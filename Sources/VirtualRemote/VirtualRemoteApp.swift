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
        MenuBarExtra {
            PopoverView(app: app)
        } label: {
            if let icon = MenuBarIcon.image {
                Image(nsImage: icon)
            } else {
                Image(systemName: "appletvremote.gen4.fill")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(app: app)
        }
    }
}
