import AppKit
import Foundation
import Observation
import VirtualRemoteCore

@MainActor
@Observable
final class ControllerModel {
    enum Connection: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
    }

    private(set) var receivers: [DiscoveredReceiver] = []
    private(set) var selected: DiscoveredReceiver?
    private(set) var connection: Connection = .idle
    private(set) var state: RemoteState?
    private(set) var lastError: String?
    var needsPairing = false
    /// Thumbnails by id, as sent by the receiver.
    private(set) var artworkImages: [String: NSImage] = [:]

    private let keyStore = KeychainKeyStore(service: "org.kavaz.VirtualRemote")
    private let defaults = UserDefaults.standard
    private let lastReceiverKey = "lastReceiverName"
    private var client: RemoteClient?
    private var browseTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?

    var isConnected: Bool { connection == .connected }

    func startBrowsing() {
        guard browseTask == nil else { return }
        browseTask = Task {
            for await list in ReceiverBrowser.results() {
                receivers = list
                autoSelectIfNeeded()
            }
        }
    }

    /// Stops browsing and drops the connection (used when leaving controller mode).
    func shutdown() {
        browseTask?.cancel()
        browseTask = nil
        teardown()
        receivers = []
        selected = nil
        connection = .idle
        needsPairing = false
    }

    func select(_ receiver: DiscoveredReceiver) {
        selected = receiver
        defaults.set(receiver.name, forKey: lastReceiverKey)
        if let key = keyStore.load(account: receiver.name) {
            needsPairing = false
            connect(receiver, key: key)
        } else {
            teardown()
            connection = .idle
            needsPairing = true
        }
    }

    /// Returns false when the text is not a valid key.
    func submitPairing(_ text: String) -> Bool {
        guard let selected, let key = PairingKey(displayString: text) else { return false }
        do {
            try keyStore.save(key, account: selected.name)
        } catch {
            lastError = "Could not save key to Keychain: \(error.localizedDescription)"
            return false
        }
        needsPairing = false
        connect(selected, key: key)
        return true
    }

    func forgetSelected() {
        guard let selected else { return }
        keyStore.delete(account: selected.name)
        teardown()
        connection = .idle
        needsPairing = true
    }

    func send(_ command: RemoteCommand) {
        guard let client, isConnected else { return }
        Task {
            do {
                try await client.send(command)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func autoSelectIfNeeded() {
        guard AppSettings.autoConnect, selected == nil,
              let name = defaults.string(forKey: lastReceiverKey),
              let match = receivers.first(where: { $0.name == name })
        else { return }
        select(match)
    }

    private func connect(_ receiver: DiscoveredReceiver, key: PairingKey) {
        teardown()
        connection = .connecting
        let client = RemoteClient(endpoint: receiver.endpoint, key: key)
        self.client = client
        connectionTask = Task {
            do {
                try await Self.connect(client, timeout: .seconds(10))
                connection = .connected
                lastError = nil
                for try await message in client.messages {
                    handle(message)
                }
                connection = .failed("Disconnected")
            } catch is CancellationError {
                return
            } catch is ConnectTimeout {
                client.close()
                connection = .failed(
                    "No answer after 10 s. Check that the receiver is running and that "
                        + "Local Network access is allowed in System Settings > Privacy & Security."
                )
            } catch {
                connection = .failed("Could not connect. Check the pairing key.")
            }
            state = nil
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled, selected == receiver {
                connect(receiver, key: key)
            }
        }
    }

    private struct ConnectTimeout: Error {}

    private nonisolated static func connect(_ client: RemoteClient, timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await client.connect() }
            group.addTask {
                try await Task.sleep(for: timeout)
                // Closing unblocks the pending connect call; otherwise the group
                // would wait for it and the timeout could never surface.
                client.close()
                throw ConnectTimeout()
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func handle(_ message: RemoteMessage) {
        switch message {
        case .state(let s): state = s
        case .error(let text): lastError = text
        case .artwork(let artwork):
            if artworkImages.count >= 16 { artworkImages.removeAll() }
            artworkImages[artwork.id] = NSImage(data: artwork.jpeg)
        case .command: break
        }
    }

    private func teardown() {
        connectionTask?.cancel()
        connectionTask = nil
        client?.close()
        client = nil
        state = nil
    }
}
