import Foundation
import Testing
import VirtualRemoteCore
@testable import VirtualRemote

/// The controller model against a real receiver on localhost.
@MainActor
@Suite(.serialized) struct ControllerModelTests {
    /// A model with an in-memory key store and its own UserDefaults domain.
    @MainActor private final class Rig {
        let model: ControllerModel
        let store = MemoryKeyStore()
        let defaults: UserDefaults
        // One fixed name: macOS keeps an empty plist per suite even after it is
        // cleared, so a new name per test would leave a file for every test.
        // The suite is serialized, so tests never share it at the same time.
        private let suite = "VirtualRemoteTests.defaults"

        init(retryDelay: Duration = .milliseconds(100), errorDuration: Duration = .seconds(5)) {
            defaults = UserDefaults(suiteName: suite)!
            model = ControllerModel(
                keyStore: store, defaults: defaults, retryDelay: retryDelay,
                errorDuration: errorDuration)
        }

        func cleanUp() {
            model.shutdown()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    @Test func selectingWithoutAKeyAsksForPairing() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }

        rig.model.select(receiver.discovered())

        #expect(rig.model.needsPairing)
        #expect(rig.model.connection == .idle)
        #expect(rig.model.selected?.name == "Test Mac")
    }

    @Test func invalidKeyTextIsRejectedAndNothingIsSaved() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }
        rig.model.select(receiver.discovered())

        #expect(rig.model.submitPairing("not a key") == false)
        #expect(rig.store.keys.isEmpty)
        #expect(rig.model.needsPairing)
    }

    @Test func pairingWithTheRightKeyConnectsSavesTheKeyAndReceivesState() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }
        rig.model.select(receiver.discovered())

        #expect(rig.model.submitPairing(receiver.key.displayString))

        #expect(await eventually { rig.model.isConnected })
        #expect(await eventually { rig.model.state?.nowPlaying?.title == "Film" })
        #expect(rig.store.keys["Test Mac"] == receiver.key)
        #expect(rig.model.needsPairing == false)
        #expect(rig.model.status == .connected)
        #expect(rig.model.isBusy == false)
    }

    @Test func aSavedKeyConnectsStraightAway() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }
        rig.store.keys["Test Mac"] = receiver.key

        rig.model.select(receiver.discovered())

        #expect(rig.model.needsPairing == false)
        #expect(await eventually { rig.model.isConnected })
    }

    @Test func aWrongKeyShowsAMismatchAndDoesNotKeepRetrying() async throws {
        let rig = Rig(retryDelay: .milliseconds(50))
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }
        rig.model.updateReceivers([receiver.discovered()])
        rig.store.keys["Test Mac"] = .generate()  // not the receiver's key

        rig.model.select(receiver.discovered())

        #expect(await eventually { rig.model.connection == .keyMismatch })
        #expect(rig.model.status == .keyMismatch(name: "Test Mac"))
        // Several retry delays later it must still say mismatch: no retry loop.
        try await Task.sleep(for: .milliseconds(400))
        #expect(rig.model.connection == .keyMismatch)
    }

    @Test func forgettingTheKeyDeletesItAndAsksForPairingAgain() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }
        rig.store.keys["Test Mac"] = receiver.key
        rig.model.select(receiver.discovered())
        #expect(await eventually { rig.model.isConnected })

        rig.model.forgetSelected()

        #expect(rig.store.keys["Test Mac"] == nil)
        #expect(rig.model.needsPairing)
        #expect(rig.model.isConnected == false)
        #expect(rig.model.connection == .idle)
    }

    @Test func aReceiverThatStopsShowsConnectionLost() async throws {
        let rig = Rig(retryDelay: .seconds(2))  // long enough to observe "lost" first
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        rig.store.keys["Test Mac"] = receiver.key
        rig.model.updateReceivers([receiver.discovered()])
        rig.model.select(receiver.discovered())
        #expect(await eventually { rig.model.isConnected })

        receiver.server.stop()

        #expect(await eventually { rig.model.connection == .lost })
        #expect(rig.model.status == .lost(name: "Test Mac"))
        #expect(rig.model.state == nil)
        #expect(rig.model.isBusy)
    }

    @Test func commandsReachTheReceiver() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }
        rig.store.keys["Test Mac"] = receiver.key
        rig.model.select(receiver.discovered())
        #expect(await eventually { rig.model.isConnected })

        rig.model.send(.togglePlayPause)
        rig.model.send(.seek(to: 640))

        var sent: [MediaCommand] = []
        var seeks: [Double] = []
        for _ in 0..<100 where sent.isEmpty || seeks.isEmpty {
            sent = await receiver.player.sent
            seeks = await receiver.player.seeks
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(sent == [.togglePlayPause])
        #expect(seeks == [640])
    }

    @Test func aFailedCommandShowsAFriendlyMessageThatFadesAway() async throws {
        let rig = Rig(errorDuration: .milliseconds(300))
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start(info: nil)  // nothing playing
        defer { receiver.server.stop() }
        rig.store.keys["Test Mac"] = receiver.key
        rig.model.select(receiver.discovered())
        #expect(await eventually { rig.model.isConnected })

        rig.model.send(.skip(seconds: 10))

        #expect(await eventually { rig.model.lastError == "Nothing is playing." })
        #expect(await eventually { rig.model.lastError == nil })
    }

    @Test func aNewerMessageIsNotClearedByTheOlderTimer() async throws {
        let rig = Rig(errorDuration: .milliseconds(500))
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start(info: nil)
        defer { receiver.server.stop() }
        rig.store.keys["Test Mac"] = receiver.key
        rig.model.select(receiver.discovered())
        #expect(await eventually { rig.model.isConnected })

        rig.model.send(.skip(seconds: 10))  // first message, expires 500 ms after it arrives
        #expect(await eventually { rig.model.lastError != nil })
        try await Task.sleep(for: .milliseconds(300))
        rig.model.send(.skip(seconds: 10))  // second message restarts the timer
        try await Task.sleep(for: .milliseconds(350))  // past the first timer, before the second

        #expect(rig.model.lastError == "Nothing is playing.")
        #expect(await eventually { rig.model.lastError == nil })
    }

    @Test func sendingWhileNotConnectedDoesNothing() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        rig.model.send(.play)  // no client: must not crash or flip any state
        #expect(rig.model.connection == .idle)
        #expect(rig.model.lastError == nil)
    }

    @Test func artworkAndTheAppIconArrive() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let icon = AppIcon(
            bundleIdentifier: "tv.plex.desktop", name: "Plex", png: makePNG(width: 64, height: 64))
        let info = NowPlayingInfo.sample(artwork: makePNG(width: 600, height: 600))
        let receiver = try await LoopbackReceiver.start(info: info, icon: icon)
        defer { receiver.server.stop() }
        rig.store.keys["Test Mac"] = receiver.key

        rig.model.select(receiver.discovered())

        #expect(await eventually { rig.model.appIcons["tv.plex.desktop"] != nil })
        #expect(rig.model.appNames["tv.plex.desktop"] == "Plex")
        #expect(await eventually { rig.model.state?.nowPlaying?.artworkID != nil })
        let artworkID = try #require(rig.model.state?.nowPlaying?.artworkID)
        #expect(rig.model.artworkImages[artworkID] != nil)
    }

    @Test func theRememberedReceiverIsSelectedWhenItAppears() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }
        rig.store.keys["Test Mac"] = receiver.key
        rig.defaults.set("Test Mac", forKey: "lastReceiverName")
        let other = LoopbackReceiverStub.discovered(name: "Other Mac")

        rig.model.updateReceivers([other])
        #expect(rig.model.selected == nil)  // not the remembered one

        rig.model.updateReceivers([other, receiver.discovered()])
        #expect(rig.model.selected?.name == "Test Mac")
        #expect(await eventually { rig.model.isConnected })
    }

    @Test func autoConnectOffLeavesTheRememberedReceiverAlone() async throws {
        UserDefaults.standard.set(false, forKey: AppSettings.Key.autoConnect)
        defer { UserDefaults.standard.removeObject(forKey: AppSettings.Key.autoConnect) }
        let rig = Rig()
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }
        rig.store.keys["Test Mac"] = receiver.key
        rig.defaults.set("Test Mac", forKey: "lastReceiverName")

        rig.model.updateReceivers([receiver.discovered()])

        #expect(rig.model.selected == nil)
        #expect(rig.model.connection == .idle)
    }

    @Test func shutdownDropsEverything() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }
        rig.store.keys["Test Mac"] = receiver.key
        rig.model.updateReceivers([receiver.discovered()])
        rig.model.select(receiver.discovered())
        #expect(await eventually { rig.model.isConnected })

        rig.model.shutdown()

        #expect(rig.model.selected == nil)
        #expect(rig.model.receivers.isEmpty)
        #expect(rig.model.connection == .idle)
        #expect(rig.model.state == nil)
        #expect(rig.model.needsPairing == false)
    }
}

/// A listed receiver nobody connects to.
private enum LoopbackReceiverStub {
    static func discovered(name: String) -> DiscoveredReceiver {
        DiscoveredReceiver(
            name: name, endpoint: .hostPort(host: "127.0.0.1", port: 1), kind: .generic)
    }
}
