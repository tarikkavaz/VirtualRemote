import Foundation
import Network

public struct DiscoveredReceiver: Equatable, Hashable, Sendable {
    public let name: String
    public let endpoint: NWEndpoint
    /// Family of the receiver's Mac; `.generic` when it does not say (older versions).
    public let kind: MacKind

    public init(name: String, endpoint: NWEndpoint, kind: MacKind = .generic) {
        self.name = name
        self.endpoint = endpoint
        self.kind = kind
    }

    // Identity is the service, so a changed or late-arriving icon never makes
    // the selected receiver look like a different one.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.endpoint == rhs.endpoint
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(endpoint)
    }
}

public enum BrowserEvent: Equatable, Sendable {
    /// The full current list, each time it changes.
    case receivers([DiscoveredReceiver])
    /// macOS refuses local network access, so nothing can be found.
    case localNetworkDenied
    /// The browser works (again).
    case ready
}

/// Finds receivers advertising `_virtualremote._tcp` on the LAN.
public enum ReceiverBrowser {
    public static func events() -> AsyncStream<BrowserEvent> {
        AsyncStream { continuation in
            let browser = NWBrowser(
                // The TXT variant is needed to receive each receiver's `kind`.
                for: .bonjourWithTXTRecord(type: TLSConfig.serviceType, domain: nil),
                using: .tcp
            )
            browser.browseResultsChangedHandler = { results, _ in
                let receivers = results.compactMap { result -> DiscoveredReceiver? in
                    guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                    var kind = MacKind.generic
                    if case .bonjour(let record) = result.metadata,
                       let raw = record[MacKind.txtKey], let parsed = MacKind(rawValue: raw) {
                        kind = parsed
                    }
                    return DiscoveredReceiver(name: name, endpoint: result.endpoint, kind: kind)
                }
                continuation.yield(.receivers(receivers.sorted { $0.name < $1.name }))
            }
            browser.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.yield(.ready)
                case .waiting(let error), .failed(let error):
                    if ConnectionFailure.classify(error) == .localNetworkDenied {
                        continuation.yield(.localNetworkDenied)
                    }
                default:
                    break
                }
            }
            browser.start(queue: DispatchQueue(label: "virtualremote.browser"))
            continuation.onTermination = { _ in browser.cancel() }
        }
    }
}
