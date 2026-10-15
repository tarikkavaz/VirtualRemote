import AppKit

enum GitHubMark {
    /// The GitHub logo as a template image. nil when the files are missing
    /// (e.g. `swift run` without the bundle), so callers can fall back to an SF Symbol.
    static let image: NSImage? = {
        guard let image = Bundle.main.image(forResource: "GitHubMark") else { return nil }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }()
}
