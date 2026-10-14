import Foundation
import Network

public struct DiscoveredReceiver: Equatable, Hashable, Sendable {
    public let name: String
    public let endpoint: NWEndpoint
}

/// Finds receivers advertising `_virtualremote._tcp` on the LAN.
public enum ReceiverBrowser {
    /// Emits the full current list each time it changes.
    public static func results() -> AsyncStream<[DiscoveredReceiver]> {
        AsyncStream { continuation in
            let browser = NWBrowser(
                for: .bonjour(type: TLSConfig.serviceType, domain: nil),
                using: .tcp
            )
            browser.browseResultsChangedHandler = { results, _ in
                let receivers = results.compactMap { result -> DiscoveredReceiver? in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    return DiscoveredReceiver(name: name, endpoint: result.endpoint)
                }
                continuation.yield(receivers.sorted { $0.name < $1.name })
            }
            browser.start(queue: DispatchQueue(label: "virtualremote.browser"))
            continuation.onTermination = { _ in browser.cancel() }
        }
    }
}
