import AppKit
import Foundation
import Observation
import VirtualRemoteCore

@MainActor
@Observable
final class ControllerModel {
    private(set) var receivers: [DiscoveredReceiver] = []
    private(set) var selected: DiscoveredReceiver?
    private(set) var connection: LinkState = .idle
    /// The first search period is over, so "no receivers found" is a real answer.
    private(set) var searchGraceOver = false
    private(set) var state: RemoteState?
    private(set) var lastError: String?
    var needsPairing = false
    /// Thumbnails by id, as sent by the receiver.
    private(set) var artworkImages: [String: NSImage] = [:]
    /// Player app icons and names by bundle id, as sent by the receiver.
    private(set) var appIcons: [String: NSImage] = [:]
    private(set) var appNames: [String: String] = [:]

    private let keyStore = KeychainKeyStore(service: "org.kavaz.VirtualRemote")
    private let defaults = UserDefaults.standard
    private let lastReceiverKey = "lastReceiverName"
    private var client: RemoteClient?
    private var browseTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    /// macOS refused local network access while browsing or connecting.
    private var browserDenied = false
    private var connectDenied = false

    var isConnected: Bool { connection == .connected }

    /// What the popover tells the user about the connection.
    var status: ControllerStatus {
        let match = selected.flatMap { s in receivers.first { $0 == s } }
        return ControllerStatus.derive(.init(
            localNetworkDenied: browserDenied || connectDenied,
            selectedName: selected?.name,
            selectedKind: match?.kind ?? selected?.kind ?? .generic,
            selectedVisible: match != nil,
            link: connection,
            rememberedName: AppSettings.autoConnect ? defaults.string(forKey: lastReceiverKey) : nil,
            anyReceivers: !receivers.isEmpty,
            searchGraceOver: searchGraceOver
        ))
    }

    /// Something is in progress, so the status dot shows it.
    var isBusy: Bool {
        switch status {
        case .searching, .connecting, .lost: true
        default: false
        }
    }

    func startBrowsing() {
        guard browseTask == nil else { return }
        searchGraceOver = false
        graceTask?.cancel()
        graceTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { searchGraceOver = true }
        }
        browseTask = Task {
            for await event in ReceiverBrowser.events() {
                switch event {
                case .receivers(let list):
                    browserDenied = false
                    receivers = list
                    autoSelectIfNeeded()
                case .localNetworkDenied:
                    browserDenied = true
                case .ready:
                    browserDenied = false
                }
            }
        }
    }

    /// Searches again and reconnects now, instead of waiting for the next automatic try.
    func retry() {
        connectDenied = false
        browseTask?.cancel()
        browseTask = nil
        startBrowsing()
        if let selected, let key = keyStore.load(account: selected.name) {
            connect(selected, key: key)
        }
    }

    /// Stops browsing and drops the connection (used when leaving controller mode).
    func shutdown() {
        browseTask?.cancel()
        browseTask = nil
        graceTask?.cancel()
        graceTask = nil
        teardown()
        receivers = []
        selected = nil
        connection = .idle
        needsPairing = false
        browserDenied = false
        connectDenied = false
        searchGraceOver = false
    }

    func select(_ receiver: DiscoveredReceiver) {
        connectDenied = false
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

    /// `isRetry` keeps the status of the failed attempt on screen while the next one
    /// runs, so it does not flicker between "no answer" and "connecting".
    private func connect(_ receiver: DiscoveredReceiver, key: PairingKey, isRetry: Bool = false) {
        teardown()
        if !isRetry { connection = .connecting }
        let client = RemoteClient(endpoint: receiver.endpoint, key: key)
        self.client = client
        connectionTask = Task {
            var wasConnected = false
            do {
                try await Self.connect(client, timeout: .seconds(10))
                wasConnected = true
                connection = .connected
                connectDenied = false
                lastError = nil
                for try await message in client.messages {
                    handle(message)
                }
                connection = .lost
            } catch is CancellationError {
                return
            } catch is ConnectTimeout {
                client.close()
                connection = .noAnswer
            } catch {
                switch ConnectionFailure.classify(error) {
                case .localNetworkDenied:
                    connectDenied = true
                    connection = .noAnswer
                case .keyMismatch where !wasConnected:
                    connection = .keyMismatch
                default:
                    connection = wasConnected ? .lost : .noAnswer
                }
            }
            state = nil
            // Retrying cannot fix a wrong key. The user has to enter it again.
            if connection == .keyMismatch { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled, selected == receiver {
                connect(receiver, key: key, isRetry: true)
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
        case .appIcon(let icon):
            appIcons[icon.bundleIdentifier] = NSImage(data: icon.png)
            appNames[icon.bundleIdentifier] = icon.name
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
