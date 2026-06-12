// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StickyGrid",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "StickyGrid", targets: ["StickyGridApp"]),
        .executable(name: "sticky", targets: ["StickyCLI"]),
        .library(name: "StickyGridCore", targets: ["StickyGridCore"]),
    ],
    targets: [
        .target(name: "StickyGridCore"),
        .executableTarget(name: "StickyCLI", dependencies: ["StickyGridCore"]),
        .executableTarget(
            name: "StickyGridApp",
            dependencies: ["StickyGridCore"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "StickyGridCoreTests",
            dependencies: ["StickyGridCore"]
        ),
        .testTarget(
            name: "StickyGridAppTests",
            dependencies: ["StickyGridApp"]
        ),
    ]
)
