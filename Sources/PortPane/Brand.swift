import AppKit

/// Port's glyphs + resource resolver, relocated out of the thin
/// `Port` shim so the pane (what the launcher loads) and the
/// standalone app share one source.
///
/// Resolution deliberately does NOT use SwiftPM's `Bundle.module`:
/// that accessor `fatalError`s when the resource bundle isn't found,
/// and a dlopen'd pane inside a hand-assembled .app is exactly that
/// case. Instead we try the host's main bundle, then this pane
/// framework's own bundle, then the SwiftPM resource bundle sitting
/// next to the dylib — and fall back to an SF Symbol so there's
/// always a glyph.
enum PortBrand {
    private final class BundleToken {}

    static func resourceURL(_ name: String, _ ext: String) -> URL? {
        // 1. Host main bundle: standalone .app (PNGs flattened into
        //    Contents/Resources) or dev `swift run`.
        if let u = Bundle.main.url(forResource: name, withExtension: ext) {
            return u
        }
        let fw = Bundle(for: BundleToken.self)
        if let u = fw.url(forResource: name, withExtension: ext) {
            return u
        }
        // 2. Relative to THIS pane dylib (the merged case: the
        //    launcher loaded us out of an installed App.app, so
        //    Bundle.main is the launcher, not us).
        let dylib = fw.bundleURL
        let dirs = [dylib, dylib.deletingLastPathComponent()]
        for d in dirs {
            // SwiftPM resource bundle sitting beside the dylib (dev
            // .build, or copied next to it in Contents/Frameworks).
            let pkgBundle = d.appendingPathComponent(
                "Port_PortPane.bundle")
            if let b = Bundle(url: pkgBundle),
               let u = b.url(forResource: name, withExtension: ext) {
                return u
            }
            // Contents/Frameworks → ../Resources (app bundle layout).
            let res = d.deletingLastPathComponent()
                .appendingPathComponent("Resources/\(name).\(ext)")
            if FileManager.default.fileExists(atPath: res.path) {
                return res
            }
        }
        return nil
    }

    /// The boat glyph (SF Symbol) for both the menu-bar tray icon
    /// and in-app branding — not the bundled cleat PNG.
    static let menuBarIcon: NSImage = {
        let image = NSImage(systemSymbolName: "sailboat.fill",
                            accessibilityDescription: "Port") ?? NSImage()
        let height: CGFloat = 14
        let aspect = image.size.width / max(image.size.height, 1)
        image.size = NSSize(width: height * aspect, height: height)
        image.isTemplate = true
        return image
    }()

    static let appIcon: NSImage = {
        NSImage(systemSymbolName: "sailboat.fill",
                accessibilityDescription: "Port") ?? NSImage()
    }()
}
