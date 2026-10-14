import Foundation

/// Locations of the bundled mediaremote-adapter files.
public struct AdapterPaths: Equatable, Sendable {
    public let script: String
    public let framework: String
    public let testClient: String

    public init(directory: URL) {
        script = directory.appendingPathComponent("mediaremote-adapter.pl").path
        framework = directory.appendingPathComponent("MediaRemoteAdapter.framework").path
        testClient = directory.appendingPathComponent("MediaRemoteAdapterTestClient").path
    }

    /// Paths inside the running app bundle (`Contents/Resources/adapter`).
    public static func bundled(in bundle: Bundle = .main) -> AdapterPaths? {
        guard let resources = bundle.resourceURL else { return nil }
        let paths = AdapterPaths(directory: resources.appendingPathComponent("adapter"))
        return paths.allExist ? paths : nil
    }

    public var allExist: Bool {
        [script, framework, testClient].allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }

    /// True when the adapter can read and control Now Playing on this macOS.
    /// A false result usually means a macOS update broke the adapter.
    public func selfTest() async -> Bool {
        do {
            _ = try await ProcessRunner.run("/usr/bin/perl", [script, framework, testClient, "test"])
            return true
        } catch {
            return false
        }
    }
}

extension AdapterNowPlayingBackend {
    public init(paths: AdapterPaths) {
        self.init(scriptPath: paths.script, frameworkPath: paths.framework)
    }
}
