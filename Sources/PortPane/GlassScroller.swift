import AppKit
import SwiftUI

/// Forces a SwiftUI `ScrollView`'s underlying `NSScrollView` to the
/// translucent **overlay** scroller with no drawn background.
///
/// With the system "Show scroll bars" set to *Always* (or inside a
/// material/glass popover) AppKit renders the *legacy* scroller —
/// an opaque black track that looks wrong against the glass. There's
/// no SwiftUI API to force the overlay style, so we reach the
/// enclosing scroll view via a zero-size companion NSView and flip
/// it. If it can't be found we no-op (scrollbar stays as-is, never
/// a crash).
///
/// Usage: attach to the content *inside* the ScrollView so the
/// companion view lives in the document-view hierarchy:
///
///     ScrollView { LazyVStack { … }.glassScrollers() }
private struct ScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var scroll = nsView.enclosingScrollView
            if scroll == nil {
                var s: NSView? = nsView.superview
                while let cur = s {
                    if let found = cur as? NSScrollView {
                        scroll = found
                        break
                    }
                    s = cur.superview
                }
            }
            guard let sv = scroll else { return }
            sv.scrollerStyle = .overlay
            sv.drawsBackground = false
            sv.backgroundColor = .clear
            sv.contentView.drawsBackground = false
            sv.verticalScroller?.scrollerStyle = .overlay
            sv.horizontalScroller?.scrollerStyle = .overlay
        }
    }
}

extension View {
    /// Glass-ify the enclosing ScrollView's scrollers (translucent
    /// overlay, no opaque track). Attach to the scroll *content*.
    func glassScrollers() -> some View {
        background(ScrollViewConfigurator())
    }
}
