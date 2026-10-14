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
    private let keyStore = KeychainKeyStore(service: "org.kavaz.VirtualRemote")
    private var server: RemoteServer?
    private var startTask: Task<Void, Never>?

    init() {
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
        startTask = Task {
            defer { startTask = nil }
            guard let paths = AdapterPaths.bundled() else {
                status = .failed("The media adapter is missing from the app bundle.")
                return
            }
            adapterWorks = nil
            adapterWorks = await paths.selfTest()
            let name = Self.computerName()
            let executor = CommandExecutor(
                player: AdapterNowPlayingBackend(paths: paths),
                volume: OsascriptVolumeBackend()
            )
            let server = RemoteServer(executor: executor, key: key, serviceName: name)
            do {
                let port = try await server.start()
                if Task.isCancelled {
                    server.stop()
                    return
                }
                self.server = server
                status = .listening(name: name, port: port)
            } catch {
                status = .failed("Could not start listening: \(error.localizedDescription)")
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

    private static func computerName() -> String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }
}
