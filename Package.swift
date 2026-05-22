// swift-tools-version: 5.9
import PackageDescription

// Port: three SPM products —
//
//   • `PortPane` (.dynamic) — port manager loaded by the launcher.
//   • `Port` (.executable) — thin standalone shim hosting the pane.
//   • `PortShared` (.library, .static) — App Group + SharedPort model
//     + SharedPortStore + AppIntent definitions. Consumed by both
//     `PortPane` and the Xcode widget target at
//     `Widget/PortWidgets.xcodeproj`. SwiftPM can't build the widget
//     extension itself (SR-14944: no app-extension productType), but
//     it can share data models cleanly via a local-package dependency
//     from the xcodeproj.
let package = Package(
    name: "Port",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Port", targets: ["Port"]),
        .library(name: "PortPane", type: .dynamic,
                 targets: ["PortPane"]),
        .library(name: "PortShared", targets: ["PortShared"])
    ],
    dependencies: [ .package(path: "../suitekit-swift") ],
    targets: [
        .target(
            name: "PortShared",
            path: "Sources/PortShared"
        ),
        .target(
            name: "PortPane",
            dependencies: [
                "PortShared",
                .product(name: "SuiteKit", package: "suitekit-swift")
            ],
            path: "Sources/PortPane",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Port",
            dependencies: [
                "PortPane",
                "PortShared",
                .product(name: "SuiteKit", package: "suitekit-swift")
            ],
            path: "Sources/Port"
        )
    ]
)
