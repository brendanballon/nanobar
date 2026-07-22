// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NanoBar",
    platforms: [.macOS(.v15)],
    targets: [
        .testTarget(
            name: "MonitorsTests",
            dependencies: ["Monitors"],
            path: "Tests/MonitorsTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "NanoBar",
            dependencies: ["Widgets", "Monitors"],
            path: "Sources/NanoBar",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "Widgets",
            dependencies: ["Monitors"],
            path: "Sources/Widgets",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "Monitors",
            path: "Sources/Monitors",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
