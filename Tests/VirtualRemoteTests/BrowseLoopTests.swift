import Foundation
import Testing
import VirtualRemoteCore
@testable import VirtualRemote

/// The controller's discovery loop, fed by a stream the test controls instead of Bonjour.
@MainActor
@Suite(.serialized) struct BrowseLoopTests {
    @MainActor private final class Rig {
        let model: ControllerModel
        let store = MemoryKeyStore()
        let defaults: UserDefaults
        let browser = FakeBrowser()
        private let suite = "VirtualRemoteTests.browse"

        init(searchGrace: Duration = .milliseconds(150)) {
            defaults = UserDefaults(suiteName: suite)!
            defaults.removePersistentDomain(forName: suite)
            let browser = browser
            model = ControllerModel(
                keyStore: store, defaults: defaults, retryDelay: .milliseconds(100),
                searchGrace: searchGrace, browse: { browser.stream() })
        }

        func cleanUp() {
            model.shutdown()
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func listed(_ name: String) -> DiscoveredReceiver {
        DiscoveredReceiver(name: name, endpoint: .hostPort(host: "127.0.0.1", port: 1), kind: .generic)
    }

    @Test func discoveredReceiversAppearInTheList() async {
        let rig = Rig()
        defer { rig.cleanUp() }
        rig.model.startBrowsing()
        #expect(await eventually { rig.browser.startCount == 1 })

        rig.browser.send(.receivers([listed("Mini"), listed("Air")]))

        #expect(await eventually { rig.model.receivers.map(\.name) == ["Mini", "Air"] })
    }

    @Test func startingTwiceBrowsesOnce() async {
        let rig = Rig()
        defer { rig.cleanUp() }

        rig.model.startBrowsing()
        rig.model.startBrowsing()

        #expect(await eventually { rig.browser.startCount == 1 })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(rig.browser.startCount == 1)
    }

    @Test func aBlockedLocalNetworkShowsItsScreenUntilBrowsingWorks() async {
        let rig = Rig()
        defer { rig.cleanUp() }
        rig.model.startBrowsing()
        #expect(await eventually { rig.browser.startCount == 1 })

        rig.browser.send(.localNetworkDenied)
        #expect(await eventually { rig.model.status == .localNetworkDenied })

        rig.browser.send(.ready)
        #expect(await eventually { rig.model.status != .localNetworkDenied })
    }

    @Test func aFreshListAlsoClearsTheBlockedScreen() async {
        let rig = Rig()
        defer { rig.cleanUp() }
        rig.model.startBrowsing()
        #expect(await eventually { rig.browser.startCount == 1 })
        rig.browser.send(.localNetworkDenied)
        #expect(await eventually { rig.model.status == .localNetworkDenied })

        rig.browser.send(.receivers([listed("Mini")]))

        #expect(await eventually { rig.model.status == .needsReceiver })
    }

    @Test func theFirstSearchTurnsIntoNotFoundAfterTheGracePeriod() async {
        let rig = Rig(searchGrace: .milliseconds(150))
        defer { rig.cleanUp() }

        rig.model.startBrowsing()
        #expect(rig.model.status == .searching(name: nil))
        #expect(rig.model.searchGraceOver == false)

        #expect(await eventually { rig.model.searchGraceOver })
        #expect(rig.model.status == .notVisible(name: nil))
    }

    @Test func aRememberedReceiverIsAwaitedThenReportedMissing() async {
        let rig = Rig(searchGrace: .milliseconds(150))
        defer { rig.cleanUp() }
        rig.defaults.set("Mini", forKey: "lastReceiverName")

        rig.model.startBrowsing()
        #expect(rig.model.status == .searching(name: "Mini"))

        #expect(await eventually { rig.model.searchGraceOver })
        #expect(rig.model.status == .notVisible(name: "Mini"))
    }

    @Test func theRememberedReceiverIsConnectedWhenDiscoveryFindsIt() async throws {
        let rig = Rig()
        defer { rig.cleanUp() }
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.server.stop() }
        rig.store.keys["Test Mac"] = receiver.key
        rig.defaults.set("Test Mac", forKey: "lastReceiverName")
        rig.model.startBrowsing()
        #expect(await eventually { rig.browser.startCount == 1 })

        rig.browser.send(.receivers([receiver.discovered()]))

        #expect(await eventually { rig.model.isConnected })
        #expect(rig.model.selected?.name == "Test Mac")
        #expect(rig.model.status == .connected)
    }

    @Test func tryAgainBrowsesAfreshAndRestartsTheGracePeriod() async {
        let rig = Rig(searchGrace: .milliseconds(100))
        defer { rig.cleanUp() }
        rig.model.startBrowsing()
        #expect(await eventually { rig.model.searchGraceOver })

        rig.model.retry()

        #expect(rig.model.searchGraceOver == false)
        #expect(await eventually { rig.browser.startCount == 2 })
        #expect(await eventually { rig.browser.terminatedCount >= 1 })  // the old stream was dropped
        #expect(await eventually { rig.model.searchGraceOver })
    }

    @Test func shuttingDownStopsBrowsingAndForgetsTheList() async {
        let rig = Rig()
        defer { rig.cleanUp() }
        rig.model.startBrowsing()
        #expect(await eventually { rig.browser.startCount == 1 })
        rig.browser.send(.receivers([listed("Mini")]))
        #expect(await eventually { !rig.model.receivers.isEmpty })

        rig.model.shutdown()

        #expect(await eventually { rig.browser.terminatedCount == 1 })
        #expect(rig.model.receivers.isEmpty)
        #expect(rig.model.searchGraceOver == false)
    }
}
