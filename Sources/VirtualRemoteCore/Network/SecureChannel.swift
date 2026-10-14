import Foundation
import Network

/// Resumes a continuation at most once.
final class Once<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(with: result)
    }
}

/// One TLS-PSK connection carrying newline-delimited JSON messages.
/// Used by both client and server. All NWConnection callbacks run on `queue`.
final class SecureChannel: @unchecked Sendable {
    let incoming: AsyncThrowingStream<RemoteMessage, Error>

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "virtualremote.channel")
    private let continuation: AsyncThrowingStream<RemoteMessage, Error>.Continuation
    private var framer = LineFramer()  // touched only on `queue`

    init(connection: NWConnection) {
        self.connection = connection
        (incoming, continuation) = AsyncThrowingStream.makeStream()
    }

    /// Starts the connection and returns once the handshake completes.
    /// Fails fast on `.waiting` (unreachable host, refused connection).
    func start() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = Once(cont)
            connection.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    once.resume(with: .success(()))
                    receiveNext()
                case .waiting(let error), .failed(let error):
                    once.resume(with: .failure(error))
                    continuation.finish(throwing: error)
                    connection.cancel()
                case .cancelled:
                    once.resume(with: .failure(CancellationError()))
                    continuation.finish()
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func send(_ message: RemoteMessage) async throws {
        let data = try MessageCodec.encode(message)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            )
        }
    }

    func close() {
        connection.cancel()
    }

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                do {
                    for line in try framer.append(data) {
                        // An undecodable line from an authenticated peer is ignored.
                        if let message = try? MessageCodec.decode(line) {
                            continuation.yield(message)
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                    connection.cancel()
                    return
                }
            }
            if let error {
                continuation.finish(throwing: error)
                return
            }
            if isComplete {
                continuation.finish()
                return
            }
            receiveNext()
        }
    }
}
