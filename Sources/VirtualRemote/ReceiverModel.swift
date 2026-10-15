import Foundation
import Observation
import SystemConfiguration
import VirtualRemoteCore

@MainActor
@Observable
final class ReceiverModel {
    enum Status: Equatable {
        case stopped
        case starting
        case listening(name: String, port: UInt16)
        case failed(String)
    }

    private(set) var status: Status = .stopped
    private(set) var key: PairingKey
    /// nil while checking or before the first start.
    private(set) var adapterWorks: Bool?
    private(set) var keychainWarning: String?

    private static let keyAccount = "receiver"
    private let keyStore: any KeyStoring
    private let environment: ReceiverEnvironment
    private var server: RemoteServer?
    private var startTask: Task<Void, Never>?
    /// Identifies the current start, so a cancelled one never clears a newer one.
    private var startToken = UUID()

    init(
        keyStore: any KeyStoring = KeychainKeyStore(service: "org.kavaz.VirtualRemote"),
        environment: ReceiverEnvironment = .live
    ) {
        self.keyStore = keyStore
        self.environment = environment
        if let stored = keyStore.load(account: Self.keyAccount) {
            key = stored
        } else {
            key = .generate()
            persist(key)
        }
    }

    func start() {
        guard startTask == nil, server == nil else { return }
        status = .starting
        let token = UUID()
        startToken = token
        startTask = Task {
            defer {
                if startToken == token { startTask = nil }
            }
            // stop() may have run since this task was created. It owns the status then.
            guard !Task.isCancelled else { return }
            guard let paths = environment.adapterPaths() else {
                status = .failed("The media adapter is missing from the app bundle.")
                return
            }
            adapterWorks = nil
            let works = await environment.selfTest(paths)
            guard !Task.isCancelled else { return }
            adapterWorks = works
            let name = environment.computerName()
            let executor = environment.makeExecutor(paths)
            let kind = await environment.detectKind()
            let server = RemoteServer(
                executor: executor, key: key, serviceName: name, kind: kind,
                advertise: environment.advertise)
            do {
                let port = try await server.start()
                if Task.isCancelled {
                    server.stop()
                    return
                }
                self.server = server
                status = .listening(name: name, port: port)
            } catch {
                if !Task.isCancelled {
                    status = .failed("Could not start listening: \(error.localizedDescription)")
                }
            }
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        server?.stop()
        server = nil
        status = .stopped
    }

    /// Existing controllers must pair again with the new key.
    func regenerateKey() {
        let wasRunning = server != nil || startTask != nil
        stop()
        key = .generate()
        persist(key)
        if wasRunning { start() }
    }

    private func persist(_ key: PairingKey) {
        do {
            try keyStore.save(key, account: Self.keyAccount)
            keychainWarning = nil
        } catch {
            keychainWarning =
                "Could not save the key to the Keychain. It will change on next launch."
        }
    }

    nonisolated static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }
}

/// Everything the receiver needs from the outside world, so tests can run the real
/// start sequence with fakes instead of a bundled adapter and Bonjour.
struct ReceiverEnvironment: Sendable {
    var adapterPaths: @Sendable () -> AdapterPaths?
    var selfTest: @Sendable (AdapterPaths) async -> Bool
    var makeExecutor: @Sendable (AdapterPaths) -> CommandExecutor
    var detectKind: @Sendable () async -> MacKind
    var computerName: @Sendable () -> String
    /// Announce the receiver over Bonjour.
    var advertise: Bool

    static let live = ReceiverEnvironment(
        adapterPaths: { AdapterPaths.bundled() },
        selfTest: { await $0.selfTest() },
        makeExecutor: { paths in
            CommandExecutor(
                player: AdapterNowPlayingBackend(paths: paths),
                volume: SystemVolumeBackend())
        },
        detectKind: { await MacKind.detect() },
        computerName: { ReceiverModel.computerName() },
        advertise: true)
}
