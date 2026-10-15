import AudioToolbox
import CoreAudio
import Foundation

/// Reads the default output device's volume and mute state straight from
/// CoreAudio. The receiver does this every second, and a process spawn per
/// read (osascript) was about 85% of its idle CPU. Each reader returns nil when
/// the device does not offer the property (HDMI and some USB outputs have no
/// software volume or mute).
public enum CoreAudioVolume {
    /// 'vmvc', kAudioHardwareServiceDeviceProperty_VirtualMainVolume: the same
    /// value the system volume slider and AppleScript's "output volume" use.
    private static let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663)

    public static func volume() -> Double? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = outputAddress(virtualMainVolume)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        return min(max(Double(value), 0), 1)
    }

    public static func isMuted() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = outputAddress(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr
        else { return nil }
        return value != 0
    }

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != AudioDeviceID(kAudioObjectUnknown) ? device : nil
    }
}

/// The receiver's volume backend: cheap CoreAudio reads, with `osascript` for
/// setting values and as the fallback when CoreAudio cannot answer.
public struct SystemVolumeBackend: VolumeBackend {
    private let fallback = OsascriptVolumeBackend()

    public init() {}

    public func volume() async throws -> Double {
        if let value = CoreAudioVolume.volume() { return value }
        return try await fallback.volume()
    }

    public func setVolume(_ value: Double) async throws {
        try await fallback.setVolume(value)
    }

    public func isMuted() async throws -> Bool {
        if let muted = CoreAudioVolume.isMuted() { return muted }
        return try await fallback.isMuted()
    }

    public func setMuted(_ muted: Bool) async throws {
        try await fallback.setMuted(muted)
    }
}
