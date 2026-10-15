import AppKit
import SwiftUI

extension View {
    /// Shows the pointing-hand cursor while the mouse is over this view. Pass
    /// `enabled: false` for a disabled control, which should keep the arrow.
    func pointerCursor(enabled: Bool = true) -> some View {
        modifier(PointerCursor(enabled: enabled))
    }
}

private struct PointerCursor: ViewModifier {
    let enabled: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        if !enabled {
            content
        } else if #available(macOS 15, *) {
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
