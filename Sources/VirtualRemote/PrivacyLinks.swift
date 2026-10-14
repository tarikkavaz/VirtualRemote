import AppKit

/// Shortcuts into System Settings for the permissions the app depends on.
enum PrivacyLinks {
    /// Privacy & Security > Local Network. If macOS renames the anchor, the
    /// link still opens System Settings at Privacy & Security.
    static func openLocalNetwork() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")
    }

    private static func open(_ link: String) {
        if let url = URL(string: link) { NSWorkspace.shared.open(url) }
    }
}
