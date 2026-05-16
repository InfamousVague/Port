# port (native)

Native macOS menu-bar port manager. See every listening port, kill/pause the process behind it, forward it to another local port, and check your LAN address. Swift + SwiftUI `MenuBarExtra`, no third-party dependencies.

## Commit Convention
Angular commits required with scope. See @.claude/rules/commit-rules.md for details.

## Code Style
See @.claude/rules/code-style.md

## Architecture

- `Sources/Port/PortApp.swift` — `@main` SwiftUI app: `MenuBarExtra` + `.accessory` activation (no Dock icon).
- `Sources/Port/Models.swift` — model types + `PortStore` (`@Observable`, `@MainActor`).
- `Sources/Port/PortScanner.swift` — `lsof -F` field-mode scan, parsed natively.
- `Sources/Port/ProcessControl.swift` — `kill(2)` via Darwin (TERM/KILL/STOP/CONT).
- `Sources/Port/Forwarder.swift` — TCP proxy on `Network.framework` (`NWListener`/`NWConnection`).
- `Sources/Port/NATPMP.swift` — native NAT-PMP client (RFC 6886) for router/external port mapping.
- `Sources/Port/LocalAddress.swift` — `getifaddrs(3)` for the primary LAN IPv4.
- `Sources/Port/ContentView.swift` — the menu-bar panel UI + forward sheet.

## Icons

- `art/AppIcon-source.png` — Dock/app icon source (cleat on glass). `scripts/make-app.sh` turns it into `AppIcon.icns`.
- `art/MenuBarIcon-source.png` — white cleat on a dark field. `scripts/process_menubar_icon.py` white-keys + crops it into `Sources/Port/Resources/MenuBarIcon.png`, used as a template `NSStatusItem` image.

Regenerate the menu-bar glyph:
```
python3 scripts/process_menubar_icon.py art/MenuBarIcon-source.png Sources/Port/Resources/MenuBarIcon.png
```

## Running

```
swift build
swift run                 # menu-bar item appears; no Dock icon
bash scripts/make-app.sh  # assembles Port.app (LSUIElement + app icon), ad-hoc signed
open Port.app             # run the bundled menu-bar agent
```
