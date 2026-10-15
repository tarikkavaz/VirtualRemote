import CoreGraphics
import Testing
@testable import VirtualRemote

@Suite struct SeekBarTests {
    @Test(arguments: [
        (0.0, "0:00"), (5.0, "0:05"), (59.9, "0:59"), (60.0, "1:00"), (61.0, "1:01"),
        (3599.0, "59:59"), (3600.0, "1:00:00"), (3661.0, "1:01:01"), (36_000.0, "10:00:00"),
        (-5.0, "0:00"),
    ])
    func clockFormatsMinutesAndHours(seconds: Double, expected: String) {
        #expect(SeekBar.clock(seconds) == expected)
    }

    @Test func clockSurvivesNonNumbers() {
        #expect(SeekBar.clock(.nan) == "0:00")
        #expect(SeekBar.clock(.infinity) == "0:00")
    }

    @Test func fractionIsHowFarAlongTheBarAPositionIs() {
        #expect(SeekBar.fraction(of: 0, in: 100) == 0)
        #expect(SeekBar.fraction(of: 25, in: 100) == 0.25)
        #expect(SeekBar.fraction(of: 100, in: 100) == 1)
    }

    @Test func fractionStaysInsideTheBar() {
        #expect(SeekBar.fraction(of: -10, in: 100) == 0)
        #expect(SeekBar.fraction(of: 500, in: 100) == 1)
    }

    @Test func fractionOfAnUnknownLengthIsNotADivisionByZero() {
        #expect(SeekBar.fraction(of: 30, in: 0) == 1)  // against a length of 1, clamped
        #expect(SeekBar.fraction(of: 0, in: 0) == 0)
    }

    @Test func aClickMapsToAPositionInTheTrack() {
        #expect(SeekBar.time(atX: 0, width: 200, duration: 1000) == 0)
        #expect(SeekBar.time(atX: 100, width: 200, duration: 1000) == 500)
        #expect(SeekBar.time(atX: 200, width: 200, duration: 1000) == 1000)
    }

    @Test func aDragPastTheEndsIsClamped() {
        #expect(SeekBar.time(atX: -50, width: 200, duration: 1000) == 0)
        #expect(SeekBar.time(atX: 999, width: 200, duration: 1000) == 1000)
    }

    @Test func aBarWithNoWidthGivesZero() {
        #expect(SeekBar.time(atX: 10, width: 0, duration: 1000) == 0)
    }
}

@Suite struct PlayerNamesTests {
    @Test(arguments: [
        ("tv.plex.desktop", "Plex"), ("company.thebrowser.Browser", "Arc"),
        ("com.google.Chrome", "Chrome"), ("com.apple.Safari", "Safari"),
        ("org.mozilla.firefox", "Firefox"), ("com.spotify.client", "Spotify"),
    ])
    func knownPlayersGetTheirName(bundleID: String, name: String) {
        #expect(PlayerNames.fallback(for: bundleID) == name)
    }

    @Test func anUnknownPlayerShowsItsBundleID() {
        #expect(PlayerNames.fallback(for: "com.example.Player") == "com.example.Player")
    }
}
