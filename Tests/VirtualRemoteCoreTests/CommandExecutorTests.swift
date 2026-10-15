import Foundation
import Testing
@testable import VirtualRemoteCore

@Suite struct CommandExecutorTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func playing(
        elapsed: Double, duration: Double = 1000, at: Date? = nil, isPlaying: Bool = true
    ) -> NowPlayingInfo {
        NowPlayingInfo(
            bundleIdentifier: "tv.plex.desktop",
            playing: isPlaying,
            elapsedTime: elapsed,
            duration: duration,
            playbackRate: 1,
            timestamp: at ?? t0
        )
    }

    private func make(
        info: NowPlayingInfo?, level: Double = 0.5, nowOffset: TimeInterval = 0
    ) -> (CommandExecutor, FakePlayer, FakeVolume) {
        let player = FakePlayer(info: info)
        let volume = FakeVolume(level: level)
        let now = t0.addingTimeInterval(nowOffset)
        return (CommandExecutor(player: player, volume: volume, now: { now }), player, volume)
    }

    @Test(arguments: [
        RemoteCommand.play, .pause, .togglePlayPause, .stop, .next, .previous,
    ])
    func transportIsRefusedWhenNothingIsPlaying(command: RemoteCommand) async {
        // macOS would send "play" to Apple Music and launch it. A remote must not.
        let (exec, player, _) = make(info: nil)
        await #expect(throws: RemoteError.noActivePlayer) {
            try await exec.execute(command)
        }
        #expect(await player.sent.isEmpty)
    }

    @Test func aPausedOrIdleSessionCanStillBeResumed() async throws {
        let idle = NowPlayingInfo(bundleIdentifier: "com.spotify.client", playing: false)
        let (exec, player, _) = make(info: idle)
        try await exec.execute(.play)
        try await exec.execute(.next)
        #expect(await player.sent == [.play, .next])
    }

    @Test func volumeStillWorksWhenNothingIsPlaying() async throws {
        let (exec, _, volume) = make(info: nil, level: 0.4)
        try await exec.execute(.setVolume(0.7))
        try await exec.execute(.setMuted(true))
        #expect(await volume.level == 0.7)
        #expect(await volume.muted)
    }

    @Test func transportCommandsMapToMediaCommands() async throws {
        let (exec, player, _) = make(info: playing(elapsed: 10))
        try await exec.execute(.play)
        try await exec.execute(.pause)
        try await exec.execute(.togglePlayPause)
        try await exec.execute(.stop)
        try await exec.execute(.next)
        try await exec.execute(.previous)
        #expect(await player.sent == [.play, .pause, .togglePlayPause, .stop, .next, .previous])
        #expect(MediaCommand.stop.rawValue == 3)  // adapter id for kMRStop
    }

    @Test func skipForwardAddsToElapsed() async throws {
        let (exec, player, _) = make(info: playing(elapsed: 100))
        try await exec.execute(.skip(seconds: 20))
        #expect(await player.seeks == [120])
    }

    @Test func seekGoesToTheAbsolutePosition() async throws {
        let (exec, player, _) = make(info: playing(elapsed: 100))
        try await exec.execute(.seek(to: 640))
        #expect(await player.seeks == [640])
    }

    @Test func seekClampsToStartAndEnd() async throws {
        let (exec, player, _) = make(info: playing(elapsed: 100, duration: 1000))
        try await exec.execute(.seek(to: -5))
        try await exec.execute(.seek(to: 5000))
        #expect(await player.seeks == [0, 1000])
    }

    @Test func seekWithoutSessionThrows() async {
        let (exec, player, _) = make(info: nil)
        await #expect(throws: RemoteError.noActivePlayer) {
            try await exec.execute(.seek(to: 10))
        }
        #expect(await player.seeks.isEmpty)
    }

    @Test func skipCompensatesForSampleAgeWhilePlaying() async throws {
        let (exec, player, _) = make(info: playing(elapsed: 100), nowOffset: 5)
        try await exec.execute(.skip(seconds: -10))
        #expect(await player.seeks == [95])
    }

    @Test func skipDoesNotAdvanceWhilePaused() async throws {
        let (exec, player, _) = make(
            info: playing(elapsed: 100, isPlaying: false), nowOffset: 30
        )
        try await exec.execute(.skip(seconds: 10))
        #expect(await player.seeks == [110])
    }

    @Test func skipClampsToStartAndEnd() async throws {
        let (exec, player, _) = make(info: playing(elapsed: 4, duration: 100))
        try await exec.execute(.skip(seconds: -10))
        try await exec.execute(.skip(seconds: 500))
        #expect(await player.seeks == [0, 100])
    }

    @Test func skipWithoutSessionThrows() async {
        let (exec, player, _) = make(info: nil)
        await #expect(throws: RemoteError.noActivePlayer) {
            try await exec.execute(.skip(seconds: 10))
        }
        #expect(await player.seeks.isEmpty)
    }

    @Test func skipWithoutElapsedThrows() async {
        // A player is active but reports no position, like a live stream.
        let live = NowPlayingInfo(bundleIdentifier: "com.apple.Safari", playing: true)
        let (exec, player, _) = make(info: live)
        await #expect(throws: RemoteError.positionUnavailable) {
            try await exec.execute(.skip(seconds: 10))
        }
        #expect(await player.seeks.isEmpty)
    }

    @Test func aLiveStreamWithAnElapsedTimeCannotSkipOrSeek() async {
        // What Arc reports for a YouTube live stream: an elapsed time, no duration.
        // Skipping from that position jumped far behind the live edge.
        let live = NowPlayingInfo(
            bundleIdentifier: "company.thebrowser.Browser", playing: true,
            elapsedTime: 9.2, playbackRate: 1, timestamp: t0)
        let (exec, player, _) = make(info: live)
        await #expect(throws: RemoteError.positionUnavailable) {
            try await exec.execute(.skip(seconds: 20))
        }
        await #expect(throws: RemoteError.positionUnavailable) {
            try await exec.execute(.seek(to: 30))
        }
        #expect(await player.seeks.isEmpty)
    }

    @Test(arguments: [0.0, -5.0])
    func aZeroOrNegativeDurationCannotSeek(duration: Double) async {
        let odd = playing(elapsed: 10, duration: duration)
        let (exec, player, _) = make(info: odd)
        await #expect(throws: RemoteError.positionUnavailable) {
            try await exec.execute(.seek(to: 5))
        }
        #expect(await player.seeks.isEmpty)
    }

    @Test func seekableMeansAPositiveDuration() {
        #expect(playing(elapsed: 1, duration: 60).isSeekable)
        #expect(playing(elapsed: 1, duration: 0).isSeekable == false)
        #expect(NowPlayingInfo(bundleIdentifier: "x", playing: true).isSeekable == false)
    }

    @Test func volumeIsClamped() async throws {
        let (exec, _, volume) = make(info: nil, level: 0.95)
        try await exec.execute(.adjustVolume(0.1))
        #expect(await volume.level == 1)
        try await exec.execute(.setVolume(-3))
        #expect(await volume.level == 0)
    }

    @Test func adjustVolumeIsRelative() async throws {
        let (exec, _, volume) = make(info: nil, level: 0.4)
        try await exec.execute(.adjustVolume(-0.1))
        #expect(abs(await volume.level - 0.3) < 1e-9)
    }

    @Test func muteToggles() async throws {
        let (exec, _, volume) = make(info: nil)
        try await exec.execute(.setMuted(true))
        #expect(await volume.muted)
    }

    @Test func stateStillArrivesWhenTheOutputHasNoVolume() async throws {
        let info = playing(elapsed: 100)
        let exec = CommandExecutor(player: FakePlayer(info: info), volume: NoVolume())
        let state = try await exec.currentState()
        #expect(state.nowPlaying == info)
        #expect(state.volumeAvailable == false)
        #expect(state.volume == 0)
        #expect(state.muted == false)
    }

    @Test func stateReportsVolumeAsAvailableNormally() async throws {
        let (exec, _, _) = make(info: playing(elapsed: 1), level: 0.3)
        #expect(try await exec.currentState().volumeAvailable)
    }

    @Test func currentStateCombinesBackends() async throws {
        let info = playing(elapsed: 10)
        let (exec, _, _) = make(info: info, level: 0.41)
        let state = try await exec.currentState()
        #expect(state == RemoteState(nowPlaying: info, volume: 0.41, muted: false))
    }
}
