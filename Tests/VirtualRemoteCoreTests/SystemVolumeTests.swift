import Foundation
import Testing
@testable import VirtualRemoteCore

/// These read the real audio device of the Mac running the tests, so they only
/// compare CoreAudio with AppleScript; they never change the volume.
@Suite struct SystemVolumeTests {
    @Test func coreAudioVolumeMatchesAppleScript() async throws {
        guard let fast = CoreAudioVolume.volume() else { return }  // device without software volume
        let slow = try await OsascriptVolumeBackend().volume()
        #expect(abs(fast - slow) <= 0.02)
        #expect((0...1).contains(fast))
    }

    @Test func coreAudioMuteMatchesAppleScript() async throws {
        guard let fast = CoreAudioVolume.isMuted() else { return }
        let slow = try await OsascriptVolumeBackend().isMuted()
        #expect(fast == slow)
    }

    @Test func systemBackendUsesCoreAudioOrFallsBackToAppleScript() async throws {
        let backend = SystemVolumeBackend()
        if let expected = CoreAudioVolume.volume() {
            #expect(try await backend.volume() == expected)
        } else {
            // An output without software volume (HDMI, DisplayPort): the fallback
            // reports "missing value" as invalidAdapterOutput, as before.
            do {
                _ = try await backend.volume()
            } catch {
                #expect(error as? RemoteError == .invalidAdapterOutput)
            }
        }
    }

    @Test func coreAudioReadIsMuchCheaperThanASpawn() {
        let start = ContinuousClock.now
        for _ in 0..<200 { _ = CoreAudioVolume.volume() }
        let elapsed = ContinuousClock.now - start
        // 200 reads; one osascript spawn alone costs about 70 ms.
        #expect(elapsed < .seconds(1))
    }
}
