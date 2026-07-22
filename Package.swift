// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NanoBar",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.5.0"),
    ],
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
            dependencies: [.product(name: "TOMLKit", package: "TOMLKit")],
            path: "Sources/Monitors",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
