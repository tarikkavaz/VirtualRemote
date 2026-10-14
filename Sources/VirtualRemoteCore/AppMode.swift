import Foundation

public enum AppMode: String, CaseIterable, Sendable {
    case controller
    case receiver
    case both

    public var isController: Bool { self != .receiver }
    public var isReceiver: Bool { self != .controller }

    public var title: String {
        switch self {
        case .controller: "Controller"
        case .receiver: "Receiver"
        case .both: "Both"
        }
    }
}
