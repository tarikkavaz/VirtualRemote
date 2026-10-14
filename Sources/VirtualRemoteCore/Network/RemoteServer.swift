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
    private let queue = DispatchQueue(label: "virtualremote.server")
    private let lock = NSLock()
    private var listener: NWListener?
    private var pollTask: Task<Void, Never>?

    public init(
        executor: CommandExecutor,
        key: PairingKey,
        serviceName: String = Host.current().localizedName ?? "Mac",
        advertise: Bool = true,
        pollInterval: Duration = .seconds(1)
    ) {
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
        if let state = try? await executor.currentState() {
            try? await channel.send(.state(state))
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

    private func publish(force: Bool) async {
        guard let state = try? await executor.currentState() else { return }
        await registry.broadcast(state, force: force)
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

actor ClientRegistry {
    private var channels: [UUID: SecureChannel] = [:]
    private var last: RemoteState?

    var hasClients: Bool { !channels.isEmpty }

    func add(_ channel: SecureChannel) -> UUID {
        let id = UUID()
        channels[id] = channel
        return id
    }

    func remove(_ id: UUID) {
        channels[id] = nil
        if channels.isEmpty { last = nil }
    }

    func broadcast(_ state: RemoteState, force: Bool) async {
        guard force || state != last else { return }
        last = state
        for channel in channels.values {
            try? await channel.send(.state(state))
        }
    }

    func closeAll() {
        for channel in channels.values { channel.close() }
        channels.removeAll()
        last = nil
    }
}
