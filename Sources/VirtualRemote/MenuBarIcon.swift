import AppKit

enum MenuBarIcon {
    /// The remote shape as a template image: macOS colors it for light and dark
    /// menu bars. nil when the files are missing (e.g. `swift run` without the
    /// bundle), so callers can fall back to an SF Symbol.
    static let image: NSImage? = {
        guard let image = Bundle.main.image(forResource: "MenuBarIcon") else { return nil }
        let height: CGFloat = 18
        image.size = NSSize(width: height * image.size.width / image.size.height, height: height)
        image.isTemplate = true
        return image
    }()
}
