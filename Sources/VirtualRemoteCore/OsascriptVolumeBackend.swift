import Foundation

/// System output volume through `osascript`. Verified on the Mac mini:
/// set + read-back works. Outputs without software volume report
/// `missing value`, which surfaces as `invalidAdapterOutput`.
public struct OsascriptVolumeBackend: VolumeBackend {
    public init() {}

    public func volume() async throws -> Double {
        let out = try await script("output volume of (get volume settings)")
        guard let percent = Double(out.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RemoteError.invalidAdapterOutput
        }
        return percent / 100
    }

    public func setVolume(_ value: Double) async throws {
        let percent = Int((min(max(value, 0), 1) * 100).rounded())
        _ = try await script("set volume output volume \(percent)")
    }

    public func isMuted() async throws -> Bool {
        let out = try await script("output muted of (get volume settings)")
        return out.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    public func setMuted(_ muted: Bool) async throws {
        _ = try await script("set volume output muted \(muted)")
    }

    private func script(_ source: String) async throws -> String {
        try await ProcessRunner.run("/usr/bin/osascript", ["-e", source])
    }
}
