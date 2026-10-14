import Testing
@testable import VirtualRemoteCore

@Suite struct PlayerCapabilitiesTests {
    @Test func plexSupportsStop() {
        #expect(PlayerCapabilities.supportsStop(bundleIdentifier: "tv.plex.desktop"))
    }

    @Test(arguments: ["com.spotify.client", "company.thebrowser.Browser", "", "unknown.app"])
    func othersDoNot(bundle: String) {
        #expect(!PlayerCapabilities.supportsStop(bundleIdentifier: bundle))
    }

    @Test func noPlayerMeansNoStop() {
        #expect(!PlayerCapabilities.supportsStop(bundleIdentifier: nil))
    }
}
