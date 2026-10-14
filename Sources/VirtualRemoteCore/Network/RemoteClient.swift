import Foundation
import Network

/// Controller side: one connection to one receiver.
public final class RemoteClient: @unchecked Sendable {
    private let channel: SecureChannel

    /// Receiver state pushes and errors. Finishes when the connection ends.
    public var messages: AsyncThrowingStream<RemoteMessage, Error> { channel.incoming }

    public init(endpoint: NWEndpoint, key: PairingKey) {
        channel = SecureChannel(
            connection: NWConnection(to: endpoint, using: TLSConfig.parameters(key: key))
        )
    }

    public convenience init(host: String, port: UInt16, key: PairingKey) {
        self.init(
            endpoint: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!),
            key: key
        )
    }

    /// Completes after the TLS handshake. Throws if the key does not match.
    public func connect() async throws {
        try await channel.start()
    }

    public func send(_ command: RemoteCommand) async throws {
        try await channel.send(.command(command))
    }

    public func close() {
        channel.close()
    }
}
