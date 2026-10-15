import Foundation
import Testing
import VirtualRemoteCore
@testable import VirtualRemote

/// Mode switching and launch at login, with fake discovery, a fake adapter and a fake login item.
@MainActor
@Suite(.serialized) struct AppModelTests {
    @MainActor private final class Rig {
        let app: AppModel
        let browser = FakeBrowser()
        let loginItem = FakeLoginItem()
        let defaults: UserDefaults
        let pathLookups = Counter()
        private let suite = "VirtualRemoteTests.appmodel"

        init(savedMode: AppMode? = nil, savedRawMode: String? = nil) {
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            if let savedMode { defaults.set(savedMode.rawValue, forKey: "appMode") }
            if let savedRawMode { defaults.set(savedRawMode, forKey: "appMode") }
            let browser = browser
            let controller = ControllerModel(
                keyStore: MemoryKeyStore(), defaults: defaults, browse: { browser.stream() })
            let receiver = ReceiverModel(
                keyStore: MemoryKeyStore(),
                environment: .fake(paths: nil, pathLookups: pathLookups))
            app = AppModel(
                controller: controller, receiver: receiver, defaults: defaults,
                loginItem: loginItem)
        }

        func cleanUp() {
            app.controller.shutdown()
            app.receiver.stop()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    // MARK: mode

    @Test func withNothingSavedTheAppIsAController() async {
        let rig = Rig()
        defer { rig.cleanUp() }

        #expect(rig.app.mode == .controller)
        #expect(await eventually { rig.browser.startCount == 1 })  // it browses
        #expect(rig.app.receiver.status == .stopped)  // it does not listen
        #expect(rig.pathLookups.value == 0)
    }

    @Test(arguments: AppMode.allCases)
    func aSavedModeIsRestored(mode: AppMode) async {
        let rig = Rig(savedMode: mode)
        defer { rig.cleanUp() }

        #expect(rig.app.mode == mode)
    }

    @Test func anUnknownSavedModeFallsBackToController() {
        let rig = Rig(savedRawMode: "broadcast")
        defer { rig.cleanUp() }

        #expect(rig.app.mode == .controller)
    }

    @Test func receiverModeListensAndDoesNotBrowse() async {
        let rig = Rig(savedMode: .receiver)
        defer { rig.cleanUp() }

        #expect(await eventually { rig.pathLookups.value == 1 })  // the receiver started
        try? await Task.sleep(for: .milliseconds(100))
        #expect(rig.browser.startCount == 0)  // the controller side stayed off
    }

    @Test func bothModeRunsTheControllerAndTheReceiver() async {
        let rig = Rig(savedMode: .both)
        defer { rig.cleanUp() }

        #expect(await eventually { rig.browser.startCount == 1 })
        #expect(await eventually { rig.pathLookups.value == 1 })
    }

    @Test func changingTheModeIsSavedAndApplied() async {
        let rig = Rig()
        defer { rig.cleanUp() }
        #expect(await eventually { rig.browser.startCount == 1 })

        rig.app.setMode(.receiver)

        #expect(rig.app.mode == .receiver)
        #expect(rig.defaults.string(forKey: "appMode") == "receiver")
        #expect(await eventually { rig.browser.terminatedCount == 1 })  // controller side shut down
        #expect(await eventually { rig.pathLookups.value == 1 })  // receiver side started
    }

    @Test func leavingReceiverModeStopsTheReceiver() async {
        let rig = Rig(savedMode: .both)
        defer { rig.cleanUp() }
        #expect(await eventually { rig.pathLookups.value == 1 })

        rig.app.setMode(.controller)

        #expect(rig.app.receiver.status == .stopped)
        #expect(rig.defaults.string(forKey: "appMode") == "controller")
    }

    @Test func choosingTheCurrentModeAgainChangesNothing() async {
        let rig = Rig()
        defer { rig.cleanUp() }
        #expect(await eventually { rig.browser.startCount == 1 })

        rig.app.setMode(.controller)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(rig.browser.startCount == 1)
        #expect(rig.browser.terminatedCount == 0)
    }

    // MARK: launch at login

    @Test func launchAtLoginStartsOffAndReflectsTheSystem() {
        let rig = Rig()
        defer { rig.cleanUp() }
        #expect(rig.app.launchAtLogin == false)

        let enabled = Rig()
        defer { enabled.cleanUp() }
        try? enabled.loginItem.register()
        enabled.app.setLaunchAtLogin(true)
        #expect(enabled.app.launchAtLogin)
    }

    @Test func turningLaunchAtLoginOnAndOff() {
        let rig = Rig()
        defer { rig.cleanUp() }

        rig.app.setLaunchAtLogin(true)
        #expect(rig.loginItem.registers == 1)
        #expect(rig.app.launchAtLogin)
        #expect(rig.app.launchAtLoginError == nil)

        rig.app.setLaunchAtLogin(false)
        #expect(rig.loginItem.unregisters == 1)
        #expect(rig.app.launchAtLogin == false)
    }

    @Test func aFailedLoginItemShowsAMessageAndKeepsTheRealState() {
        let rig = Rig()
        defer { rig.cleanUp() }
        rig.loginItem.failNext(with: NSError(domain: "test", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Not allowed",
        ]))

        rig.app.setLaunchAtLogin(true)

        #expect(rig.app.launchAtLoginError == "Launch at login failed: Not allowed")
        #expect(rig.app.launchAtLogin == false)  // the system did not enable it
    }

    @Test func aLaterSuccessClearsTheLoginError() {
        let rig = Rig()
        defer { rig.cleanUp() }
        rig.loginItem.failNext(with: NSError(domain: "test", code: 1))
        rig.app.setLaunchAtLogin(true)
        #expect(rig.app.launchAtLoginError != nil)

        rig.app.setLaunchAtLogin(true)

        #expect(rig.app.launchAtLoginError == nil)
        #expect(rig.app.launchAtLogin)
    }
}
