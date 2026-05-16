import SwiftUI
import AppKit

@main
struct PortApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = PortStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(store)
        } label: {
            Image(nsImage: PortApp.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    /// Resolve a bundled resource: Bundle.main (signed .app, flattened into
    /// Contents/Resources) first, then Bundle.module (dev `swift run`).
    static func resourceURL(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.module.url(forResource: name, withExtension: ext)
    }

    /// White cleat glyph, set as a template so macOS tints it for the
    /// active menu-bar appearance (dark on light bars, light on dark).
    static let menuBarIcon: NSImage = {
        let image: NSImage
        if let url = resourceURL("MenuBarIcon", "png"),
           let loaded = NSImage(contentsOf: url) {
            image = loaded
        } else {
            image = NSImage(systemSymbolName: "sailboat.fill", accessibilityDescription: "Port")
                ?? NSImage()
        }
        let height: CGFloat = 14
        let aspect = image.size.width / max(image.size.height, 1)
        image.size = NSSize(width: height * aspect, height: height)
        image.isTemplate = true
        return image
    }()

    /// Full-color app icon (cleat on glass), for in-app branding.
    static let appIcon: NSImage = {
        if let url = resourceURL("AppIcon", "png"),
           let loaded = NSImage(contentsOf: url) {
            return loaded
        }
        return NSImage(systemSymbolName: "sailboat.fill", accessibilityDescription: "Port")
            ?? NSImage()
    }()
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar agent: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
    }
}
