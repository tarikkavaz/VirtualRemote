import Foundation
import Testing
@testable import VirtualRemoteCore

@Suite struct MessageCodecTests {
    @Test(arguments: [
        RemoteMessage.command(.play),
        .command(.togglePlayPause),
        .command(.stop),
        .command(.skip(seconds: -10)),
        .command(.seek(to: 1234.5)),
        .command(.setVolume(0.35)),
        .command(.setMuted(true)),
        .state(RemoteState(
            nowPlaying: NowPlayingInfo(
                bundleIdentifier: "tv.plex.desktop",
                title: "Film",
                playing: true,
                elapsedTime: 12.5,
                duration: 8700,
                playbackRate: 1,
                timestamp: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            volume: 0.41,
            muted: false
        )),
        .state(RemoteState(nowPlaying: nil, volume: 0, muted: true)),
    ])
    func roundTrip(message: RemoteMessage) throws {
        let data = try MessageCodec.encode(message)
        #expect(data.last == 0x0A)
        let decoded = try MessageCodec.decode(data.dropLast())
        #expect(decoded == message)
    }

    @Test func encodedMessageIsSingleLine() throws {
        let data = try MessageCodec.encode(.command(.skip(seconds: 20)))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.filter { $0 == "\n" }.count == 1)
    }

    @Test func garbageThrows() {
        #expect(throws: (any Error).self) {
            try MessageCodec.decode(Data("not json".utf8))
        }
    }
}
