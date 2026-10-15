import Foundation
import Observation
import ServiceManagement
import VirtualRemoteCore

/// Starting the app at login. The system's login item in the app, a stand-in in tests.
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

struct SystemLoginItem: LoginItemControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

/// Owns both roles and applies the chosen mode.
@MainActor
@Observable
final class AppModel {
    let controller: ControllerModel
    let receiver: ReceiverModel

    private(set) var mode: AppMode
    private(set) var launchAtLogin = false
    private(set) var launchAtLoginError: String?
    /// Tab the Settings window shows; set before opening it to jump to a tab.
    var settingsTab: SettingsTab = .general

    private let defaults: UserDefaults
    private let loginItem: any LoginItemControlling
    private let modeKey = "appMode"

    init(
        controller: ControllerModel = ControllerModel(),
        receiver: ReceiverModel = ReceiverModel(),
        defaults: UserDefaults = .standard,
        loginItem: any LoginItemControlling = SystemLoginItem()
    ) {
        self.controller = controller
        self.receiver = receiver
        self.defaults = defaults
        self.loginItem = loginItem
        mode = AppMode(rawValue: defaults.string(forKey: modeKey) ?? "") ?? .controller
        refreshLaunchAtLogin()
        apply()
    }

    func setMode(_ newMode: AppMode) {
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(newMode.rawValue, forKey: modeKey)
        apply()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try loginItem.register()
            } else {
                try loginItem.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Launch at login failed: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = loginItem.isEnabled
    }

    private func apply() {
        if mode.isController {
            controller.startBrowsing()
        } else {
            controller.shutdown()
        }
        if mode.isReceiver {
            receiver.start()
        } else {
            receiver.stop()
        }
    }
}
