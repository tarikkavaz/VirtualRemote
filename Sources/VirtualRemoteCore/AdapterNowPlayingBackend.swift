import Foundation

/// Drives mediaremote-adapter through `/usr/bin/perl`, which is entitled to
/// use MediaRemote on macOS 15.4+. The script and the framework must be
/// bundled with the app; the framework is passed as an argument, not linked.
public struct AdapterNowPlayingBackend: NowPlayingBackend {
    public let scriptPath: String
    public let frameworkPath: String

    public init(scriptPath: String, frameworkPath: String) {
        self.scriptPath = scriptPath
        self.frameworkPath = frameworkPath
    }

    public func nowPlaying() async throws -> NowPlayingInfo? {
        let output = try await adapter(["get", "--allow-missing-title"])
        return try Self.parse(output)
    }

    public func send(_ command: MediaCommand) async throws {
        _ = try await adapter(["send", String(command.rawValue)])
    }

    public func seek(to seconds: Double) async throws {
        let micros = Int((max(0, seconds) * 1_000_000).rounded())
        _ = try await adapter(["seek", String(micros)])
    }

    private func adapter(_ arguments: [String]) async throws -> String {
        try await ProcessRunner.run("/usr/bin/perl", [scriptPath, frameworkPath] + arguments)
    }

    private struct Raw: Decodable {
        var bundleIdentifier: String?
        var title: String?
        var artist: String?
        var playing: Bool?
        var elapsedTime: Double?
        var duration: Double?
        var playbackRate: Double?
        var timestamp: Date?
        var artworkData: String?  // base64
    }

    /// Parses `get` output. `null`, empty output, or output without a bundle
    /// identifier means no active session.
    static func parse(_ output: String) throws -> NowPlayingInfo? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let raw: Raw
        do {
            raw = try decoder.decode(Raw.self, from: Data(trimmed.utf8))
        } catch {
            throw RemoteError.invalidAdapterOutput
        }
        guard let bundle = raw.bundleIdentifier else { return nil }
        return NowPlayingInfo(
            bundleIdentifier: bundle,
            title: raw.title,
            artist: raw.artist,
            playing: raw.playing ?? false,
            elapsedTime: raw.elapsedTime,
            duration: raw.duration,
            playbackRate: raw.playbackRate,
            timestamp: raw.timestamp,
            artworkData: raw.artworkData.flatMap { Data(base64Encoded: $0) }
        )
    }
}
