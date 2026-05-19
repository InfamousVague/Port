// swift-tools-version: 5.9
import PackageDescription

// Port: `PortPane` (whole port manager as a dynamic library via
// SuiteKit, loadable by the launcher; bundles its PNG glyphs as
// target resources) + `Port` (thin @main standalone shim).
let package = Package(
    name: "Port",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Port", targets: ["Port"]),
        .library(name: "PortPane", type: .dynamic, targets: ["PortPane"])
    ],
    dependencies: [ .package(path: "../suitekit-swift") ],
    targets: [
        .target(
            name: "PortPane",
            dependencies: [.product(name: "SuiteKit", package: "suitekit-swift")],
            path: "Sources/PortPane",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Port",
            dependencies: ["PortPane", .product(name: "SuiteKit", package: "suitekit-swift")],
            path: "Sources/Port"
        )
    ]
)
