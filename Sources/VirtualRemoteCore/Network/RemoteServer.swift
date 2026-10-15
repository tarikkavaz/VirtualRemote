import Foundation
import Network

/// Receiver side: accepts paired controllers, runs their commands, and
/// pushes state changes.
public final class RemoteServer: @unchecked Sendable {
    private let executor: CommandExecutor
    private let key: PairingKey
    private let serviceName: String
    private let advertise: Bool
    private let pollInterval: Duration
    private let registry = ClientRegistry()
    private let artworkCache = ArtworkCache()
    private let iconCache: AppIconCache
    private let queue = DispatchQueue(label: "virtualremote.server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var pollTask: Task<Void, Never>?

    public init(
        executor: CommandExecutor,
        key: PairingKey,
        serviceName: String = Host.current().localizedName ?? "Mac",
        advertise: Bool = true,
        pollInterval: Duration = .seconds(1),
        iconLoader: @escaping @Sendable (String) -> AppIcon? = { AppIconProvider.load(bundleIdentifier: $0) }
    ) {
        self.iconCache = AppIconCache(loader: iconLoader)
        self.executor = executor
        self.key = key
        self.serviceName = serviceName
        self.advertise = advertise
        self.pollInterval = pollInterval
    }

    /// Starts listening and returns the TCP port.
    public func start() async throws -> UInt16 {
        let listener = try NWListener(using: TLSConfig.parameters(key: key))
        if advertise {
            listener.service = NWListener.Service(name: serviceName, type: TLSConfig.serviceType)
        }
        listener.newConnectionHandler = { [self] connection in
            Task { await serve(SecureChannel(connection: connection)) }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { cont in
            let once = Once(cont)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resume(with: .success(listener.port?.rawValue ?? 0))
                case .failed(let error):
                    once.resume(with: .failure(error))
                case .cancelled:
                    once.resume(with: .failure(CancellationError()))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        lock.withLock {
            self.listener = listener
            pollTask = Task { [self] in await pollLoop() }
        }
        return port
    }

    public func stop() {
        lock.lock()
        listener?.cancel()
        listener = nil
        pollTask?.cancel()
        pollTask = nil
        lock.unlock()
        Task { await registry.closeAll() }
    }

    private func serve(_ channel: SecureChannel) async {
        do {
            try await channel.start()
        } catch {
            return  // handshake failed: wrong key or dropped connection
        }
        let id = await registry.add(channel)
        if let snap = await snapshot() {
            await registry.deliver(to: id, snap)
        }
        // Reader and runner are separate so reading never waits on slow
        // commands, and queued volume changes can be merged.
        let queue = CommandQueue()
        let reader = Task {
            do {
                for try await message in channel.incoming {
                    if case .command(let command) = message { queue.push(command) }
                }
            } catch {
                // connection error: end the queue
            }
            queue.finish()
        }
        for await _ in queue.signals {
            var ranCommand = false
            while let command = queue.pop() {
                ranCommand = true
                do {
                    try await executor.execute(command)
                } catch {
                    try? await channel.send(.error(String(describing: error)))
                }
            }
            if ranCommand { await publish(force: true) }
        }
        reader.cancel()
        await registry.remove(id)
        channel.close()
    }

    /// Current state with the raw image replaced by a thumbnail id, plus the thumbnail
    /// and the player's icon.
    private func snapshot() async -> Snapshot? {
        guard var state = try? await executor.currentState() else { return nil }
        var artwork: Artwork?
        if let raw = state.nowPlaying?.artworkData {
            artwork = await artworkCache.resolve(raw)
            state.nowPlaying?.artworkID = artwork?.id
        }
        state.nowPlaying?.artworkData = nil
        var icon: AppIcon?
        if let bundleID = state.nowPlaying?.bundleIdentifier {
            icon = await iconCache.icon(for: bundleID)
        }
        return Snapshot(state: state, artwork: artwork, icon: icon)
    }

    private func publish(force: Bool) async {
        guard let snap = await snapshot() else { return }
        await registry.broadcast(snap, force: force)
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: pollInterval)
            if await registry.hasClients {
                await publish(force: false)
            }
        }
    }
}

struct Snapshot {
    var state: RemoteState
    var artwork: Artwork?
    var icon: AppIcon?
}

actor ClientRegistry {
    private struct Client {
        let channel: SecureChannel
        var sentArtwork: Set<String> = []
        var sentIcons: Set<String> = []
    }

    private var clients: [UUID: Client] = [:]
    private var last: RemoteState?

    var hasClients: Bool { !clients.isEmpty }

    func add(_ channel: SecureChannel) -> UUID {
        let id = UUID()
        clients[id] = Client(channel: channel)
        return id
    }

    func remove(_ id: UUID) {
        clients[id] = nil
        if clients.isEmpty { last = nil }
    }

    func broadcast(_ snap: Snapshot, force: Bool) async {
        guard force || snap.state != last else { return }
        last = snap.state
        for id in Array(clients.keys) {
            await deliver(to: id, snap)
        }
    }

    /// Sends the thumbnail and the app icon first if this controller has not got
    /// them yet, then the state.
    func deliver(to id: UUID, _ snap: Snapshot) async {
        guard let client = clients[id] else { return }
        if let artwork = snap.artwork, !client.sentArtwork.contains(artwork.id) {
            try? await client.channel.send(.artwork(artwork))
            clients[id]?.sentArtwork.insert(artwork.id)
        }
        if let icon = snap.icon, !client.sentIcons.contains(icon.bundleIdentifier) {
            try? await client.channel.send(.appIcon(icon))
            clients[id]?.sentIcons.insert(icon.bundleIdentifier)
        }
        try? await client.channel.send(.state(snap.state))
    }

    func closeAll() {
        for client in clients.values { client.channel.close() }
        clients.removeAll()
        last = nil
    }
}
