import Foundation
import Testing
@testable import VirtualRemoteCore

/// Server and client on localhost, no Bonjour.
@Suite(.serialized) struct LoopbackTests {
    private let info = NowPlayingInfo(
        bundleIdentifier: "tv.plex.desktop",
        title: "Film",
        playing: true,
        elapsedTime: 100,
        duration: 1000,
        playbackRate: 1,
        timestamp: Date()
    )

    private struct Rig {
        let server: RemoteServer
        let port: UInt16
        let player: FakePlayer
        let volume: FakeVolume
        let key: PairingKey
    }

    private func startServer(key: PairingKey = .generate()) async throws -> Rig {
        let player = FakePlayer(info: info)
        let volume = FakeVolume(level: 0.4)
        let server = RemoteServer(
            executor: CommandExecutor(player: player, volume: volume),
            key: key,
            advertise: false,
            pollInterval: .milliseconds(50)
        )
        let port = try await server.start()
        return Rig(server: server, port: port, player: player, volume: volume, key: key)
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<100 {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @Test(.timeLimit(.minutes(1)))
    func clientReceivesInitialState() async throws {
        let rig = try await startServer()
        defer { rig.server.stop() }
        let client = RemoteClient(host: "127.0.0.1", port: rig.port, key: rig.key)
        defer { client.close() }
        try await client.connect()

        var it = client.messages.makeAsyncIterator()
        let first = try await it.next()
        guard case .state(let state) = first else {
            Issue.record("expected state, got \(String(describing: first))")
            return
        }
        #expect(state.nowPlaying?.bundleIdentifier == "tv.plex.desktop")
        #expect(state.volume == 0.4)
    }

    @Test(.timeLimit(.minutes(1)))
    func commandsReachExecutor() async throws {
        let rig = try await startServer()
        defer { rig.server.stop() }
        let client = RemoteClient(host: "127.0.0.1", port: rig.port, key: rig.key)
        defer { client.close() }
        try await client.connect()

        try await client.send(.togglePlayPause)
        try await client.send(.skip(seconds: 20))
        try await client.send(.setVolume(0.8))

        #expect(await eventually { await rig.player.sent == [.togglePlayPause] })
        #expect(await eventually { await rig.player.seeks.count == 1 })
        let seek = await rig.player.seeks.first ?? 0
        #expect(seek >= 120 && seek < 125)
        #expect(await eventually { await rig.volume.level == 0.8 })
    }

    @Test(.timeLimit(.minutes(1)))
    func stateChangesArePushed() async throws {
        let rig = try await startServer()
        defer { rig.server.stop() }
        let client = RemoteClient(host: "127.0.0.1", port: rig.port, key: rig.key)
        defer { client.close() }
        try await client.connect()

        var it = client.messages.makeAsyncIterator()
        _ = try await it.next()  // initial state
        await rig.volume.setLevelForTest(0.9)
        // The next push must carry the new volume (poll interval 50 ms).
        while let message = try await it.next() {
            if case .state(let s) = message, s.volume == 0.9 { return }
        }
        Issue.record("stream ended before the volume change arrived")
    }

    @Test(.timeLimit(.minutes(1)))
    func failedCommandReportsError() async throws {
        let rig = try await startServer()
        await rig.player.setInfoForTest(nil)
        defer { rig.server.stop() }
        let client = RemoteClient(host: "127.0.0.1", port: rig.port, key: rig.key)
        defer { client.close() }
        try await client.connect()

        try await client.send(.skip(seconds: 10))
        var it = client.messages.makeAsyncIterator()
        while let message = try await it.next() {
            if case .error(let text) = message {
                #expect(text.contains("noActivePlayer"))
                return
            }
        }
        Issue.record("no error message received")
    }

    @Test(.timeLimit(.minutes(1)))
    func wrongKeyIsRejected() async throws {
        let rig = try await startServer()
        defer { rig.server.stop() }
        let client = RemoteClient(host: "127.0.0.1", port: rig.port, key: .generate())
        defer { client.close() }
        await #expect(throws: (any Error).self) {
            try await client.connect()
        }
        #expect(await rig.player.sent.isEmpty)
    }
}

extension FakeVolume {
    func setLevelForTest(_ value: Double) { level = value }
}

extension FakePlayer {
    func setInfoForTest(_ value: NowPlayingInfo?) { info = value }
}
