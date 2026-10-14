import AppKit
import SwiftUI

/// Sizes the menu bar window to the SwiftUI content it is attached to.
/// macOS grows that window when the content gets taller but never shrinks it
/// again, so a shorter mode would leave empty space below the content. The
/// window's top edge stays where it is.
struct WindowFitter: NSViewRepresentable {
    func makeNSView(context: Context) -> FitView { FitView() }
    func updateNSView(_ nsView: FitView, context: Context) {}

    final class FitView: NSView {
        override func layout() {
            super.layout()
            // Resizing the window inside a layout pass re-enters layout.
            DispatchQueue.main.async { [weak self] in self?.fitWindow() }
        }

        private func fitWindow() {
            guard let window, frame.height > 0 else { return }
            let height = frame.height
            guard abs(window.frame.height - height) > 0.5 else { return }
            var windowFrame = window.frame
            windowFrame.origin.y = windowFrame.maxY - height
            windowFrame.size.height = height
            window.setFrame(windowFrame, display: true)
        }
    }
}
