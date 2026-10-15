import Foundation

/// The family of Mac a receiver runs on. Advertised in the Bonjour TXT record so
/// controllers can show a matching icon before connecting.
public enum MacKind: String, Sendable {
    case macMini, macStudio, macPro, macBook, iMac, generic

    /// Maps a marketing name such as "Mac mini" or "MacBook Pro".
    public init(machineName: String?) {
        let name = (machineName ?? "").lowercased()
        if name.contains("macbook") {
            self = .macBook
        } else if name.contains("mac mini") {
            self = .macMini
        } else if name.contains("mac studio") {
            self = .macStudio
        } else if name.contains("imac") {  // before "mac pro": "iMac Pro" contains it
            self = .iMac
        } else if name.contains("mac pro") {
            self = .macPro
        } else {
            self = .generic
        }
    }

    /// SF Symbol for this family.
    public var symbolName: String {
        switch self {
        case .macMini: "macmini"
        case .macStudio: "macstudio"
        case .macPro: "macpro.gen3"
        case .macBook: "laptopcomputer"
        case .iMac: "imac"
        case .generic: "desktopcomputer"
        }
    }

    static let txtKey = "kind"

    /// The family of the Mac this runs on, from `system_profiler` (well under a second).
    public static func detect() async -> MacKind {
        guard let json = try? await ProcessRunner.run(
            "/usr/sbin/system_profiler", ["-json", "SPHardwareDataType"]),
            let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
            let hardware = (root["SPHardwareDataType"] as? [[String: Any]])?.first
        else { return .generic }
        return MacKind(machineName: hardware["machine_name"] as? String)
    }
}
