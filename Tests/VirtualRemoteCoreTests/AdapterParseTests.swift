import Foundation
import Testing
@testable import VirtualRemoteCore

/// Fixtures are real `get` outputs captured on the Mac mini (macOS 27.0.1).
@Suite struct AdapterParseTests {
    @Test func plex() throws {
        let out = #"{"timestamp":"2026-10-14T19:41:54Z","mediaType":"kMRMediaRemoteNowPlayingInfoTypeVideo","contentItemIdentifier":"AB0ED5D2-34A4-43DB-9D87-8E35E3637826","title":"Spider-Man: Brand New Day","bundleIdentifier":"tv.plex.desktop","elapsedTime":0.125,"playing":true,"processIdentifier":64803,"duration":8700.6720000000005,"playbackRate":1,"artworkMimeType":"image\/jpeg"}"#
        let info = try #require(try AdapterNowPlayingBackend.parse(out))
        #expect(info.bundleIdentifier == "tv.plex.desktop")
        #expect(info.title == "Spider-Man: Brand New Day")
        #expect(info.playing)
        #expect(info.elapsedTime == 0.125)
        #expect(info.timestamp != nil)
    }

    @Test func arc() throws {
        let out = #"{"playbackRate":1,"album":"","elapsedTime":3723.6169169999998,"timestamp":"2026-10-14T19:51:09Z","bundleIdentifier":"company.thebrowser.Browser","processIdentifier":90832,"title":"Joe Rogan Experience #2565 - Michael Douglas","artworkMimeType":"image\/jpeg","duration":7825.0410000000002,"artist":"PowerfulJRE","contentItemIdentifier":"C2B5C66E-57EC-4FAD-9884-72D147555CB0","playing":true}"#
        let info = try #require(try AdapterNowPlayingBackend.parse(out))
        #expect(info.bundleIdentifier == "company.thebrowser.Browser")
        #expect(info.artist == "PowerfulJRE")
        #expect(info.duration == 7825.0410000000002)
    }

    @Test func idleClientWithoutTitle() throws {
        let out = #"{"playing":false,"processIdentifier":98753,"bundleIdentifier":"com.spotify.client"}"#
        let info = try #require(try AdapterNowPlayingBackend.parse(out))
        #expect(info.playing == false)
        #expect(info.title == nil)
        #expect(info.elapsedTime == nil)
    }

    @Test(arguments: ["null", "null\n", "", "  \n"])
    func noSession(out: String) throws {
        #expect(try AdapterNowPlayingBackend.parse(out) == nil)
    }

    @Test func missingBundleMeansNoSession() throws {
        #expect(try AdapterNowPlayingBackend.parse(#"{"playing":true}"#) == nil)
    }

    @Test func malformedThrows() {
        #expect(throws: RemoteError.invalidAdapterOutput) {
            try AdapterNowPlayingBackend.parse("{oops")
        }
    }
}
