import Foundation
import Network

/// Why a connection or a browse failed, as far as the error says.
public enum ConnectionFailure: Equatable, Sendable {
    /// macOS refused local network access to this app.
    case localNetworkDenied
    /// The TLS handshake failed: the pre-shared key is not the receiver's.
    case keyMismatch
    /// Unreachable, refused, timed out, or anything else.
    case noAnswer

    public static func classify(_ error: Error) -> ConnectionFailure {
        guard let error = error as? NWError else { return .noAnswer }
        switch error {
        case .dns(let code):
            // kDNSServiceErr_PolicyDenied and kDNSServiceErr_NoAuth
            return (code == -65570 || code == -65555) ? .localNetworkDenied : .noAnswer
        case .tls(let status):
            // errSSLClosedGraceful, errSSLClosedAbort, errSSLClosedNoNotify: the peer went
            // away, which says nothing about the key. Anything else is a failed handshake
            // (a wrong key shows as -9820, "bad MAC").
            return [-9805, -9806, -9816].contains(status) ? .noAnswer : .keyMismatch
        default:
            return .noAnswer
        }
    }
}

/// State of the link to the selected receiver.
public enum LinkState: Equatable, Sendable {
    case idle
    case connecting
    /// Connect timed out or failed for a reason other than the key.
    case noAnswer
    case keyMismatch
    case connected
    /// Was connected, then dropped. A retry is under way.
    case lost
}

/// What the popover tells the user about the connection.
public enum ControllerStatus: Equatable, Sendable {
    case needsReceiver
    case searching(name: String?)
    case notVisible(name: String?)
    case connecting(name: String, kind: MacKind)
    case noAnswer(name: String)
    case keyMismatch(name: String)
    case localNetworkDenied
    case lost(name: String)
    case connected

    public struct Input: Sendable {
        /// macOS is blocking local network access (browsing or connecting was denied).
        public var localNetworkDenied: Bool
        public var selectedName: String?
        public var selectedKind: MacKind
        /// The selected receiver is in the current Bonjour list.
        public var selectedVisible: Bool
        public var link: LinkState
        /// The receiver we would connect to automatically, if none is selected yet.
        public var rememberedName: String?
        public var anyReceivers: Bool
        /// The first search period is over, so "not found" is now a real answer.
        public var searchGraceOver: Bool

        public init(
            localNetworkDenied: Bool = false, selectedName: String? = nil,
            selectedKind: MacKind = .generic, selectedVisible: Bool = false,
            link: LinkState = .idle, rememberedName: String? = nil,
            anyReceivers: Bool = false, searchGraceOver: Bool = false
        ) {
            self.localNetworkDenied = localNetworkDenied
            self.selectedName = selectedName
            self.selectedKind = selectedKind
            self.selectedVisible = selectedVisible
            self.link = link
            self.rememberedName = rememberedName
            self.anyReceivers = anyReceivers
            self.searchGraceOver = searchGraceOver
        }
    }

    public static func derive(_ input: Input) -> ControllerStatus {
        if input.link == .connected { return .connected }
        if input.localNetworkDenied { return .localNetworkDenied }

        if let name = input.selectedName {
            switch input.link {
            case .keyMismatch:
                return .keyMismatch(name: name)
            case .connected:
                return .connected
            case .lost:
                return input.selectedVisible ? .lost(name: name) : .notVisible(name: name)
            case .connecting, .idle:
                return input.selectedVisible
                    ? .connecting(name: name, kind: input.selectedKind)
                    : .notVisible(name: name)
            case .noAnswer:
                return input.selectedVisible ? .noAnswer(name: name) : .notVisible(name: name)
            }
        }

        if let remembered = input.rememberedName {
            return input.searchGraceOver ? .notVisible(name: remembered) : .searching(name: remembered)
        }
        if !input.anyReceivers {
            return input.searchGraceOver ? .notVisible(name: nil) : .searching(name: nil)
        }
        return .needsReceiver
    }
}
