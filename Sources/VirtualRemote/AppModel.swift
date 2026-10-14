import Foundation
import Observation
import ServiceManagement
import VirtualRemoteCore

/// Owns both roles and applies the chosen mode.
@MainActor
@Observable
final class AppModel {
    let controller = ControllerModel()
    let receiver = ReceiverModel()

    private(set) var mode: AppMode
    private(set) var launchAtLogin = false
    private(set) var launchAtLoginError: String?

    private let defaults = UserDefaults.standard
    private let modeKey = "appMode"

    init() {
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
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Launch at login failed: \(error.localizedDescription)"
        }
        refreshLaunchAtLogin()
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
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
