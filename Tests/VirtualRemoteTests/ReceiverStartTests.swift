import Foundation
import Testing
import VirtualRemoteCore
@testable import VirtualRemote

/// The receiver's real start sequence, with a fake adapter and no Bonjour.
@MainActor
@Suite struct ReceiverStartTests {
    private func listeningPort(_ model: ReceiverModel) -> UInt16? {
        if case .listening(_, let port) = model.status { return port }
        return nil
    }

    private func isListening(_ model: ReceiverModel) -> Bool { listeningPort(model) != nil }

    @Test func startReachesListeningAndServesState() async throws {
        let model = ReceiverModel(keyStore: MemoryKeyStore(), environment: .fake())
        defer { model.stop() }

        model.start()
        #expect(model.status == .starting)

        #expect(await eventually { isListening(model) })
        let port = try #require(listeningPort(model))
        #expect(port > 0)
        #expect(model.adapterWorks == true)
        guard case .listening(let name, _) = model.status else { return }
        #expect(name == "Test Mac")

        let client = RemoteClient(host: "127.0.0.1", port: port, key: model.key)
        defer { client.close() }
        try await client.connect()
        var iterator = client.messages.makeAsyncIterator()
        while let message = try await iterator.next() {
            if case .state(let state) = message {
                #expect(state.nowPlaying?.title == "Film")
                return
            }
        }
        Issue.record("no state arrived")
    }

    @Test func aFailingSelfTestIsReportedButTheReceiverStillListens() async {
        let model = ReceiverModel(
            keyStore: MemoryKeyStore(), environment: .fake(selfTest: { _ in false }))
        defer { model.stop() }

        model.start()

        #expect(await eventually { isListening(model) })
        #expect(model.adapterWorks == false)
    }

    @Test func aMissingAdapterFailsWithAMessage() async {
        let model = ReceiverModel(keyStore: MemoryKeyStore(), environment: .fake(paths: nil))

        model.start()

        let expected = ReceiverModel.Status.failed("The media adapter is missing from the app bundle.")
        #expect(await eventually { model.status == expected })
    }

    @Test func stoppingClosesThePort() async throws {
        let model = ReceiverModel(keyStore: MemoryKeyStore(), environment: .fake())
        model.start()
        #expect(await eventually { isListening(model) })
        let port = try #require(listeningPort(model))

        model.stop()

        #expect(model.status == .stopped)
        let client = RemoteClient(host: "127.0.0.1", port: port, key: model.key)
        defer { client.close() }
        await #expect(throws: (any Error).self) { try await client.connect() }
    }

    @Test func startingTwiceStartsOnlyOnce() async {
        let executors = Counter()
        let model = ReceiverModel(
            keyStore: MemoryKeyStore(), environment: .fake(executors: executors))
        defer { model.stop() }

        model.start()
        model.start()
        #expect(await eventually { isListening(model) })
        model.start()  // already running

        try? await Task.sleep(for: .milliseconds(100))
        #expect(executors.value == 1)
    }

    @Test func stoppingWhileTheAdapterIsBeingCheckedLeavesItStopped() async {
        let executors = Counter()
        let model = ReceiverModel(
            keyStore: MemoryKeyStore(),
            environment: .fake(
                selfTest: { _ in
                    try? await Task.sleep(for: .milliseconds(300))
                    return true
                },
                executors: executors))

        model.start()
        model.stop()  // while the self-test is still running

        try? await Task.sleep(for: .milliseconds(600))
        #expect(model.status == .stopped)
        #expect(model.adapterWorks == nil)
        #expect(executors.value == 0)  // the cancelled start never went further
    }

    @Test func aCancelledStartDoesNotLetASecondStartRunTwice() async {
        let executors = Counter()
        let model = ReceiverModel(
            keyStore: MemoryKeyStore(),
            environment: .fake(
                selfTest: { _ in
                    try? await Task.sleep(for: .milliseconds(200))
                    return true
                },
                executors: executors))
        defer { model.stop() }

        model.start()
        model.stop()
        model.start()  // the second start is the one that counts
        // The first, cancelled start ends at once, while the second is still checking the
        // adapter. It must not clear the second one, or this third call, made while the
        // second is still in flight, would start a duplicate.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.status == .starting)
        model.start()

        #expect(await eventually { isListening(model) })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(executors.value == 1)
    }

    @Test func aNewKeyWhileRunningRestartsWithTheNewKeyOnly() async throws {
        let model = ReceiverModel(keyStore: MemoryKeyStore(), environment: .fake())
        defer { model.stop() }
        model.start()
        #expect(await eventually { isListening(model) })
        let oldKey = model.key

        model.regenerateKey()

        #expect(model.key != oldKey)
        #expect(await eventually { isListening(model) })
        let port = try #require(listeningPort(model))

        let stale = RemoteClient(host: "127.0.0.1", port: port, key: oldKey)
        defer { stale.close() }
        await #expect(throws: (any Error).self) { try await stale.connect() }

        let fresh = RemoteClient(host: "127.0.0.1", port: port, key: model.key)
        defer { fresh.close() }
        try await fresh.connect()
    }

    @Test func aNewKeyWhileStoppedStaysStopped() {
        let model = ReceiverModel(keyStore: MemoryKeyStore(), environment: .fake())

        model.regenerateKey()

        #expect(model.status == .stopped)
    }
}
