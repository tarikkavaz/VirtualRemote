import Foundation
import KeyboardShortcuts
import Testing
@testable import VirtualRemote

/// Reads and writes the test process's own UserDefaults, and puts everything back.
@Suite(.serialized) struct AppSettingsTests {
    private let keys = [
        AppSettings.Key.autoConnect, AppSettings.Key.volumeStepPercent,
        AppSettings.Key.skipShortSeconds, AppSettings.Key.skipLongSeconds,
    ]

    private func clean() {
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }

    @Test func unsetValuesUseTheDefaults() {
        clean()
        defer { clean() }
        #expect(AppSettings.autoConnect == true)
        #expect(AppSettings.volumeStep == 0.05)
        #expect(AppSettings.skipShortSeconds == 10)
        #expect(AppSettings.skipLongSeconds == 20)
    }

    @Test func storedValuesAreUsed() {
        clean()
        defer { clean() }
        UserDefaults.standard.set(false, forKey: AppSettings.Key.autoConnect)
        UserDefaults.standard.set(10, forKey: AppSettings.Key.volumeStepPercent)
        UserDefaults.standard.set(15, forKey: AppSettings.Key.skipShortSeconds)
        UserDefaults.standard.set(45, forKey: AppSettings.Key.skipLongSeconds)

        #expect(AppSettings.autoConnect == false)
        #expect(AppSettings.volumeStep == 0.10)
        #expect(AppSettings.skipShortSeconds == 15)
        #expect(AppSettings.skipLongSeconds == 45)
    }

    @Test func outOfRangeValuesAreClamped() {
        clean()
        defer { clean() }
        UserDefaults.standard.set(0, forKey: AppSettings.Key.volumeStepPercent)
        UserDefaults.standard.set(0, forKey: AppSettings.Key.skipShortSeconds)
        UserDefaults.standard.set(99_999, forKey: AppSettings.Key.skipLongSeconds)
        #expect(AppSettings.volumeStep == 0.01)
        #expect(AppSettings.skipShortSeconds == 1)
        #expect(AppSettings.skipLongSeconds == 600)

        UserDefaults.standard.set(500, forKey: AppSettings.Key.volumeStepPercent)
        #expect(AppSettings.volumeStep == 0.25)
    }
}

@MainActor
@Suite struct HotkeysTests {
    @Test func theListHasEveryShortcutOnce() {
        let rows = Hotkeys.all(short: 10, long: 20)

        #expect(rows.count == 10)
        #expect(Set(rows.map(\.name.rawValue)).count == 10)
        #expect(Set(rows.map(\.title)).count == 10)
    }

    @Test func skipTitlesFollowTheChosenLengths() {
        let titles = Hotkeys.all(short: 7, long: 30).map(\.title)

        #expect(titles.contains("Back 7 s"))
        #expect(titles.contains("Forward 7 s"))
        #expect(titles.contains("Back 30 s"))
        #expect(titles.contains("Forward 30 s"))
        #expect(!titles.contains("Back 10 s"))
    }
}
