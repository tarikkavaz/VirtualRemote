import AppKit
import SwiftUI

extension View {
    /// Shows the pointing-hand cursor while the mouse is over this view.
    func pointerCursor() -> some View {
        modifier(PointerCursor())
    }
}

private struct PointerCursor: ViewModifier {
    @State private var pushed = false

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.pointerStyle(.link)
        } else {
            content
                .onHover { inside in
                    if inside, !pushed {
                        NSCursor.pointingHand.push()
                        pushed = true
                    } else if !inside, pushed {
                        NSCursor.pop()
                        pushed = false
                    }
                }
                .onDisappear {
                    if pushed {
                        NSCursor.pop()
                        pushed = false
                    }
                }
        }
    }
}
