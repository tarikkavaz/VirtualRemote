import Foundation
import Testing
@testable import VirtualRemoteCore

@Suite struct CommandQueueTests {
    private func drain(_ q: CommandQueue) -> [RemoteCommand] {
        var out: [RemoteCommand] = []
        while let c = q.pop() { out.append(c) }
        return out
    }

    @Test func adjacentSetVolumeKeepsLatest() {
        let q = CommandQueue()
        for v in [0.1, 0.2, 0.3] { q.push(.setVolume(v)) }
        #expect(drain(q) == [.setVolume(0.3)])
    }

    @Test func adjacentAdjustVolumeSums() {
        let q = CommandQueue()
        q.push(.adjustVolume(0.05))
        q.push(.adjustVolume(0.05))
        q.push(.adjustVolume(-0.02))
        let result = drain(q)
        #expect(result.count == 1)
        if case .adjustVolume(let d) = result[0] { #expect(abs(d - 0.08) < 1e-9) }
    }

    @Test func otherCommandsKeepOrderAndAreNotMerged() {
        let q = CommandQueue()
        q.push(.setVolume(0.1))
        q.push(.setVolume(0.2))
        q.push(.togglePlayPause)
        q.push(.setVolume(0.3))
        q.push(.skip(seconds: 10))
        q.push(.skip(seconds: 10))
        #expect(drain(q) == [
            .setVolume(0.2), .togglePlayPause, .setVolume(0.3),
            .skip(seconds: 10), .skip(seconds: 10),
        ])
    }

    @Test func adjacentSeeksKeepOnlyTheLast() {
        let q = CommandQueue()
        q.push(.seek(to: 10))
        q.push(.seek(to: 20))
        q.push(.seek(to: 30))
        q.push(.togglePlayPause)
        q.push(.seek(to: 40))
        #expect(drain(q) == [.seek(to: 30), .togglePlayPause, .seek(to: 40)])
    }

    @Test func popOnEmptyReturnsNil() {
        #expect(CommandQueue().pop() == nil)
    }

    @Test func pendingCommandsSurviveFinish() async {
        let q = CommandQueue()
        q.push(.pause)
        q.finish()
        var signals = 0
        for await _ in q.signals { signals += 1 }
        #expect(signals == 1)
        #expect(q.pop() == .pause)
    }
}
